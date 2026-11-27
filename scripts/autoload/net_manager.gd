extends Node
## Autoload "Net": multijugador en red local (misma WiFi) o por internet (servidor de salas).
##
## - Un jugador crea la sala y hace de anfitrión: ejecuta la partida completa (física, IA,
##   capturas) y envía el estado a los demás. Los clientes solo mandan sus controles.
## - Las salas se anuncian por difusión UDP (DISCOVERY_PORT) cada segundo; también se puede
##   entrar escribiendo la IP del anfitrión.
## - Por internet, el anfitrión se conecta al servidor de salas del VPS (server/), que le da un
##   código de 4 letras; los demás se unen con ese código. El servidor solo reenvía paquetes:
##   todo lo demás funciona igual que en red local (RelayPeer en vez de ENetMultiplayerPeer).
## - Siempre se juega con 1 Cazador y 3 Presas: los puestos libres los ocupa la IA.
## - La partida (MatchSeries) la decide el anfitrión; cada ronda se carga en todos con
##   load_round(), y el anfitrión espera a que todos los clientes estén listos.

signal lobby_changed
signal rooms_changed
## Cambió la lista de salas de internet (online_browser.rooms / state).
signal online_rooms_changed
## Conexión con el anfitrión establecida / fallida.
signal joined
signal join_failed
## Se ha perdido la sesión (el anfitrión se fue o nos echó). reason es un texto para el jugador.
signal session_ended(reason: String)
## Un jugador se ha ido durante la sesión (solo en el anfitrión).
signal player_left(peer: int)

const PORT := 24680
const DISCOVERY_PORT := 24681
const MAX_PLAYERS := MatchSeries.SLOTS
const GAME_TAG := "cazador-o-presa"
const PROTOCOL := 2
const ANNOUNCE_INTERVAL := 1.0
## Una sala que no se anuncia en este tiempo desaparece de la lista.
const ROOM_TIMEOUT := 3.5
const SETTINGS_PATH := "user://ajustes.cfg"
const LOBBY_SCENE := "res://scenes/main/Lobby.tscn"
## Servidor de salas por defecto ("ip" o "ip:puerto"). Pon aquí la IP de tu VPS para que el
## APK que compartes ya lo traiga configurado; cada jugador puede cambiarlo en la sala.
const DEFAULT_ONLINE_SERVER := "51.79.58.49"
const RelayProtocol := preload("res://server/relay_protocol.gd")

## Nombre del jugador (se guarda en ajustes.cfg).
var player_name: String = ""
## Jugadores de la sala: peer -> {"name": String}. El anfitrión es el peer 1.
var players: Dictionary = {}
## Orden de llegada (el anfitrión primero).
var player_order: Array = []
var room_name: String = ""
## La sesión ya ha empezado a jugar (no se admiten más jugadores).
var in_game: bool = false
## Salas encontradas: ip -> {"name", "players", "port", "seen"}.
var rooms: Dictionary = {}
## Servidor de salas para jugar por internet ("ip" o "ip:puerto"; se guarda en ajustes.cfg).
var online_server: String = ""
## Sesión a través del servidor de salas, y su código.
var online: bool = false
var room_code: String = ""
## Motivo del último fallo de conexión (texto para el jugador).
var last_error: String = ""
## Conexión con el servidor de salas (Godot la sustituye antes de avisar de un fallo).
var _relay: RelayPeer
## Ping (ida y vuelta, ms) con cada peer: el cliente mide al anfitrión; el anfitrión a cada cliente.
var pings: Dictionary = {}
const PING_INTERVAL := 1.0
var _ping_left := 0.0
## Buscador de salas de internet (activo mientras se está en "Por internet").
var online_browser: RelayBrowser

## Clientes que ya han cargado la ronda actual (solo anfitrión).
var _ready_peers: Dictionary = {}
var _announce: PacketPeerUDP
var _announce_left: float = 0.0
var _listen: PacketPeerUDP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if _announce and is_host() and not in_game:
		_announce_left -= delta
		if _announce_left <= 0.0:
			_announce_left = ANNOUNCE_INTERVAL
			_send_announce()
	if _listen:
		_poll_discovery()
	if online_browser:
		online_browser.poll(delta)
	if is_active():
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = PING_INTERVAL
			for peer in multiplayer.get_peers():
				_ping.rpc_id(peer, Time.get_ticks_msec())
	elif not pings.is_empty():
		pings.clear()


# --- Estado ----------------------------------------------------------------------

## Hay una sesión de red (como anfitrión o cliente).
func is_active() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_active() and multiplayer.is_server()


func is_client() -> bool:
	return is_active() and not multiplayer.is_server()


## Peer de este dispositivo (1 = anfitrión o partida sin red).
func local_peer() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


## IPs de esta máquina en la red local (para que los demás se unan escribiéndola).
func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_172_private(address):
			out.append(address)
	return out


func set_player_name(value: String) -> void:
	player_name = value.strip_edges().left(14)
	if player_name == "":
		player_name = "Jugador"
	_save_settings()


# --- Sala ------------------------------------------------------------------------

func host_room() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	room_name = "Sala de %s" % player_name
	players = {1: {"name": player_name}}
	player_order = [1]
	in_game = false
	_announce = PacketPeerUDP.new()
	_announce.set_broadcast_enabled(true)
	_announce_left = 0.0
	stop_discovery()
	lobby_changed.emit()
	return OK


func join_room(address: String, port: int = PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Crea una sala en el servidor de internet. Es asíncrono: cuando el servidor da el código,
## se emiten lobby_changed y joined (o join_failed con last_error).
func host_online() -> Error:
	leave()
	var peer := RelayPeer.new()
	var target := _online_target()
	var err := peer.create_host(target[0], target[1], "Sala de %s" % player_name) if target[0] != "" else ERR_UNCONFIGURED
	if err != OK:
		last_error = peer.error_text if peer.error_text != "" else "Configura la dirección del servidor."
		return err
	peer.room_created.connect(_on_room_created.bind(peer))
	multiplayer.multiplayer_peer = peer
	online = true
	_relay = peer
	return OK


## Se une a una sala de internet con su código.
func join_online(code: String) -> Error:
	leave()
	var peer := RelayPeer.new()
	var target := _online_target()
	var err := peer.create_client(target[0], target[1], code) if target[0] != "" else ERR_UNCONFIGURED
	if err != OK:
		last_error = peer.error_text if peer.error_text != "" else "Configura la dirección del servidor."
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	_relay = peer
	return OK


## Empieza a listar las salas abiertas del servidor de internet (cada pocos segundos).
func start_online_browse() -> void:
	stop_online_browse()
	var target := _online_target()
	online_browser = RelayBrowser.new()
	online_browser.changed.connect(func() -> void: online_rooms_changed.emit())
	if target[0] == "":
		online_browser.state = "error"
		online_browser.error_text = "Configura la dirección del servidor."
	else:
		online_browser.start(target[0], target[1])
	online_rooms_changed.emit()


func stop_online_browse() -> void:
	if online_browser:
		online_browser.stop()
		online_browser = null


## Anfitrión online: la sala aparece en la lista solo mientras admite jugadores.
func _update_room_info() -> void:
	if online and is_host() and _relay:
		_relay.set_room_info(room_name, not in_game and players.size() < MAX_PLAYERS)


func set_online_server(value: String) -> void:
	online_server = value.strip_edges()
	_save_settings()


## [host, puerto] del servidor de salas configurado.
func _online_target() -> Array:
	var text := online_server.strip_edges()
	var port := RelayProtocol.DEFAULT_PORT
	var colon := text.rfind(":")
	if colon > 0 and text.count(":") == 1:
		port = text.substr(colon + 1).to_int()
		text = text.left(colon)
	return [text, port]


func _on_room_created(code: String, peer: RelayPeer) -> void:
	if multiplayer.multiplayer_peer != peer:
		return
	room_code = code
	room_name = peer.room_name
	players = {1: {"name": player_name}}
	player_order = [1]
	in_game = false
	lobby_changed.emit()
	joined.emit()


## Sale de la sala o partida (cierra la conexión).
func leave() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	room_code = ""
	_relay = null
	players = {}
	player_order = []
	in_game = false
	_ready_peers = {}
	if _announce:
		_announce.close()
		_announce = null


## Nombre de un jugador de la sala.
func name_of(peer: int) -> String:
	return players.get(peer, {}).get("name", "?")


# --- Ping ------------------------------------------------------------------------

## Ping a mostrar: con el anfitrión (cliente) o el peor de los clientes (anfitrión). -1 sin dato.
func ping_ms() -> int:
	if not is_active() or pings.is_empty():
		return -1
	if is_client():
		return int(pings.get(1, -1))
	var worst := -1
	for peer in pings:
		worst = maxi(worst, int(pings[peer]))
	return worst


@rpc("any_peer", "unreliable")
func _ping(sent_msec: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), sent_msec)


@rpc("any_peer", "unreliable")
func _pong(sent_msec: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var rtt := float(Time.get_ticks_msec() - sent_msec)
	# Suavizado para que el número no salte en cada medida.
	pings[peer] = rtt if not pings.has(peer) else lerpf(pings[peer], rtt, 0.4)


# --- Partida -----------------------------------------------------------------------

## Anfitrión: empieza una partida nueva con los jugadores de la sala (+ IA) en orden aleatorio.
func start_match() -> void:
	if not is_host():
		return
	var entries := []
	for peer in player_order:
		entries.append({"name": name_of(peer), "peer": peer})
	var ai := 1
	while entries.size() < MatchSeries.SLOTS:
		entries.append({"name": "IA %d" % ai, "peer": 0})
		ai += 1
	entries.shuffle()
	in_game = true
	_update_room_info()
	GameManager.series = MatchSeries.new(entries)
	load_round()


## Anfitrión: carga la ronda actual de GameManager.series en todos los dispositivos.
func load_round() -> void:
	if not is_host():
		return
	var setup := {
		"series": GameManager.series.to_dict(),
		"seed": randi(),
		"difficulty": GameManager.difficulty,
		"prep_time": GameManager.config.prep_time,
		"match_duration": GameManager.config.match_duration,
	}
	_ready_peers = {}
	_load_round.rpc(setup)


@rpc("authority", "call_local", "reliable")
func _load_round(setup: Dictionary) -> void:
	in_game = true
	if not is_host():
		GameManager.series = MatchSeries.from_dict(setup["series"])
		GameManager.config.prep_time = setup["prep_time"]
		GameManager.config.match_duration = setup["match_duration"]
	GameManager.round_setup = setup
	get_tree().change_scene_to_file(GameManager.MATCH_SCENE)


## Cliente: la escena de la ronda ya está cargada.
func report_round_ready() -> void:
	if is_client():
		_client_round_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func _client_round_ready() -> void:
	if is_host():
		_ready_peers[multiplayer.get_remote_sender_id()] = true


## Clientes conectados que ya tienen la ronda cargada.
func ready_peers() -> Array:
	var out := []
	for peer in multiplayer.get_peers():
		if _ready_peers.has(peer):
			out.append(peer)
	return out


func all_clients_ready() -> bool:
	for peer in multiplayer.get_peers():
		if not _ready_peers.has(peer):
			return false
	return true


## Anfitrión: todos vuelven a la sala de espera.
func back_to_lobby() -> void:
	if is_host():
		_back_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	in_game = false
	_update_room_info()
	GameManager.series = null
	GameManager.round_setup = {}
	get_tree().change_scene_to_file(LOBBY_SCENE)


# --- Conexiones ------------------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if not is_host():
		return
	# La partida ya ha empezado o la sala está llena: se rechaza.
	if in_game or players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(peer, "La partida ya ha empezado." if in_game else "La sala está llena.")
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if is_host() and peer in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(peer))


func _on_peer_disconnected(peer: int) -> void:
	if not is_host():
		return
	if players.has(peer):
		players.erase(peer)
		player_order.erase(peer)
		pings.erase(peer)
		_ready_peers.erase(peer)
		_send_lobby()
		player_left.emit(peer)


func _on_connected_to_server() -> void:
	_register.rpc_id(1, player_name, PROTOCOL)


func _on_connection_failed() -> void:
	last_error = _peer_error("")
	leave()
	join_failed.emit()


func _on_server_disconnected() -> void:
	# Godot ya ha quitado la conexión: el papel se mira en la del servidor de salas.
	var was_host := _relay != null and _relay.get_unique_id() == 1
	var fallback := "Se ha perdido la conexión con el anfitrión."
	if online:
		fallback = "Se ha perdido la conexión con el servidor." if was_host else "La sala se ha cerrado o se ha perdido la conexión."
	var reason := _peer_error(fallback)
	leave()
	session_ended.emit(reason)


## Texto de error del servidor de salas, si lo hay (y no es una desconexión genérica).
func _peer_error(fallback: String) -> String:
	if _relay and _relay.error_text != "" and not _relay.error_text.begins_with("Se ha perdido"):
		return _relay.error_text
	return fallback


@rpc("any_peer", "reliable")
func _register(name: String, protocol: int) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_rejected.rpc_id(peer, "Versión del juego distinta a la del anfitrión.")
		return
	if in_game or players.size() >= MAX_PLAYERS:
		return
	players[peer] = {"name": _unique_name(name)}
	player_order.append(peer)
	_send_lobby()


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave()
	session_ended.emit(reason)


func _send_lobby() -> void:
	_lobby_state.rpc(players, player_order, room_name)
	_update_room_info()
	lobby_changed.emit()


@rpc("authority", "reliable")
func _lobby_state(new_players: Dictionary, order: Array, new_room_name: String) -> void:
	var first := players.is_empty()
	players = new_players
	player_order = order
	room_name = new_room_name
	lobby_changed.emit()
	if first:
		joined.emit()


func _unique_name(wanted: String) -> String:
	var base := wanted.strip_edges().left(14)
	if base == "":
		base = "Jugador"
	var taken := []
	for peer in players:
		taken.append(players[peer]["name"])
	var candidate := base
	var n := 2
	while candidate in taken:
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate


# --- Descubrimiento de salas (LAN) -------------------------------------------------

func start_discovery() -> void:
	stop_discovery()
	rooms = {}
	_listen = PacketPeerUDP.new()
	_listen.set_broadcast_enabled(true)
	var err := _listen.bind(DISCOVERY_PORT)
	if err != OK:
		# Otro programa (p. ej. otra copia del juego en este ordenador) ya escucha: solo IP manual.
		push_warning("No se pueden buscar salas en el puerto %d (%s)" % [DISCOVERY_PORT, error_string(err)])
		_listen = null
	rooms_changed.emit()


func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null


func is_discovering() -> bool:
	return _listen != null


func _send_announce() -> void:
	var data := JSON.stringify({
		"game": GAME_TAG, "v": PROTOCOL, "name": room_name, "players": players.size(), "port": PORT,
	}).to_utf8_buffer()
	var targets := ["255.255.255.255"]
	for ip in local_ips():
		# Difusión de la subred (suponiendo /24, lo habitual en una WiFi doméstica).
		var parts := ip.split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for target in targets:
		_announce.set_dest_address(target, DISCOVERY_PORT)
		_announce.put_packet(data)


func _poll_discovery() -> void:
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var packet := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var info: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not info is Dictionary or info.get("game") != GAME_TAG or int(info.get("v", 0)) != PROTOCOL:
			continue
		changed = changed or not rooms.has(ip)
		rooms[ip] = {"name": String(info.get("name", ip)), "players": int(info.get("players", 0)), "port": int(info.get("port", PORT)), "seen": Time.get_ticks_msec()}
	var now := Time.get_ticks_msec()
	for ip in rooms.keys():
		if now - int(rooms[ip]["seen"]) > ROOM_TIMEOUT * 1000.0:
			rooms.erase(ip)
			changed = true
	if changed:
		rooms_changed.emit()


# --- Ajustes ---------------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = String(cfg.get_value("jugador", "nombre", ""))
		online_server = String(cfg.get_value("red", "servidor", ""))
	if online_server == "":
		online_server = DEFAULT_ONLINE_SERVER
	if player_name == "":
		player_name = "Jugador"


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("jugador", "nombre", player_name)
	if online_server != DEFAULT_ONLINE_SERVER:
		cfg.set_value("red", "servidor", online_server)
	elif cfg.has_section_key("red", "servidor"):
		cfg.erase_section_key("red", "servidor")
	cfg.save(SETTINGS_PATH)


static func _is_172_private(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var second := address.split(".")[1].to_int()
	return second >= 16 and second <= 31
