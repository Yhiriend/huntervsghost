class_name RelayPeer
extends MultiplayerPeerExtension
## Conexión multijugador a través del servidor de salas (server/relay_server.gd).
## Para el resto del juego es un MultiplayerPeer más: el anfitrión es el peer 1 y los clientes
## solo hablan con él, igual que con ENetMultiplayerPeer en red local.

signal room_created(code: String)

const P := preload("res://server/relay_protocol.gd")

## Motivo del último fallo (texto para el jugador).
var error_text: String = ""
var room_code: String = ""
## Nombre con el que se anuncia la sala (solo anfitrión).
var room_name: String = ""

var _connection: ENetConnection
var _server: ENetPacketPeer
var _hosting := false
var _join_code := ""
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _unique_id := 0
var _peers: Dictionary = {}  # id -> true
var _incoming: Array = []  # [{"data", "from", "mode", "channel"}]
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false


func create_host(address: String, port: int = P.DEFAULT_PORT, name: String = "") -> Error:
	_hosting = true
	room_name = name
	return _connect(address, port)


func create_client(address: String, port: int, code: String) -> Error:
	_hosting = false
	_join_code = code.strip_edges().to_upper()
	return _connect(address, port)


func _connect(address: String, port: int) -> Error:
	var ip := address.strip_edges()
	if not ip.is_valid_ip_address():
		ip = IP.resolve_hostname(ip, IP.TYPE_IPV4)
		if ip == "":
			error_text = "No se encuentra el servidor %s." % address
			return ERR_CANT_RESOLVE
	_connection = ENetConnection.new()
	var err := _connection.create_host(1, P.CHANNELS)
	if err != OK:
		error_text = "No se pudo abrir la conexión (%s)." % error_string(err)
		return err
	_server = _connection.connect_to_host(ip, port, P.CHANNELS)
	if _server == null:
		error_text = "No se pudo conectar con el servidor."
		return ERR_CANT_CONNECT
	# Detecta antes un servidor caído o una conexión perdida (por defecto ENet tarda hasta 30 s).
	_server.set_timeout(8, 3000, 8000)
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


# --- MultiplayerPeer ---------------------------------------------------------------

func _poll() -> void:
	if _connection == null:
		return
	while _connection:
		var event := _connection.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE:
			break
		match type:
			ENetConnection.EVENT_CONNECT:
				P.tune_peer(_server)
				if _hosting:
					_send_control(P.HOST, [P.GAME_TAG, P.VERSION, room_name])
				else:
					_send_control(P.JOIN, [P.GAME_TAG, P.VERSION, _join_code])
			ENetConnection.EVENT_DISCONNECT, ENetConnection.EVENT_ERROR:
				if error_text == "":
					error_text = "No se pudo conectar con el servidor." if _status == MultiplayerPeer.CONNECTION_CONNECTING else "Se ha perdido la conexión con el servidor."
				_shutdown()
			ENetConnection.EVENT_RECEIVE:
				_receive((event[1] as ENetPacketPeer).get_packet(), event[3])


func _receive(packet: PackedByteArray, channel: int) -> void:
	if packet.is_empty():
		return
	var type := packet[0]
	if type == P.DATA:
		if packet.size() >= 5:
			_incoming.append({"data": packet.slice(5), "from": packet.decode_s32(1), "channel": 0, "mode": _mode_of(channel)})
		return
	var args := P.control_args(packet)
	match type:
		P.ROOM:
			room_code = String(args[0])
			_unique_id = 1
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			room_created.emit(room_code)
		P.JOINED:
			_unique_id = int(args[0])
			room_code = String(args[1])
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			_peers[1] = true
			peer_connected.emit(1)
		P.PEER_ON:
			var id := int(args[0])
			if _refusing:
				_send_control(P.KICK, [id])
				return
			_peers[id] = true
			peer_connected.emit(id)
		P.PEER_OFF:
			var id := int(args[0])
			if _peers.erase(id):
				peer_disconnected.emit(id)
		P.ERROR:
			error_text = String(args[0]) if not args.is_empty() else "Error del servidor."


## Anfitrión: actualiza cómo aparece la sala en la lista (abierta = admite jugadores).
func set_room_info(name: String, open: bool) -> void:
	room_name = name
	if _unique_id == 1:
		_send_control(P.INFO, [name, open])


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var channel := P.CH_RELIABLE
	match _mode:
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED:
			channel = P.CH_ORDERED
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE:
			channel = P.CH_UNRELIABLE
	var err := _server.send(channel, P.data(_target, buffer), P.flags_for(channel))
	# ENet solo envía lo encolado al llamar a service()/flush(): sin esto el paquete esperaría
	# al siguiente fotograma (hasta 16-33 ms más en un móvil).
	_connection.flush()
	return err


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	return _incoming.pop_front()["data"] if not _incoming.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _incoming[0]["from"] if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _incoming[0]["mode"] if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	return 0


func _get_max_packet_size() -> int:
	return 1 << 20


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return _unique_id


func _is_server() -> bool:
	return _unique_id == 1


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _unique_id == 1 and _peers.has(peer):
		_send_control(P.KICK, [peer])


func _close() -> void:
	if _server:
		_server.peer_disconnect_now()
	if _connection:
		_connection.flush()
	_shutdown()


# --- Interno ---------------------------------------------------------------------

func _shutdown() -> void:
	var was_connected := _status == MultiplayerPeer.CONNECTION_CONNECTED
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	if _connection:
		_connection.destroy()
	_connection = null
	_server = null
	_incoming.clear()
	if was_connected:
		for id in _peers.keys():
			peer_disconnected.emit(id)
	_peers.clear()


func _send_control(type: int, args: Array) -> void:
	if _server:
		_server.send(P.CH_CONTROL, P.control(type, args), ENetPacketPeer.FLAG_RELIABLE)
		_connection.flush()


func _mode_of(channel: int) -> MultiplayerPeer.TransferMode:
	match channel:
		P.CH_ORDERED:
			return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		P.CH_UNRELIABLE:
			return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE
