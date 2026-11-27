extends RefCounted
## Servidor de salas para jugar por internet. No ejecuta el juego: solo reenvía paquetes.
## Quien crea la sala sigue siendo el anfitrión (peer 1) y simula la partida como en red local;
## el servidor da a cada sala un código y pasa los paquetes entre el anfitrión y los demás.
## Lo arranca server/relay_main.gd (en el VPS) o las pruebas.

const P := preload("res://server/relay_protocol.gd")
## Margen para que llegue el mensaje de error antes de cortar la conexión.
const KICK_DELAY_MS := 300

var connection: ENetConnection
## code -> {"peers": {id: ENetPacketPeer}, "next_id": int, "name": String, "open": bool}
var rooms: Dictionary = {}
## ENetPacketPeer -> {"code": String, "id": int}
var members: Dictionary = {}
var verbose := true
var _pending_kicks: Array = []  # [ENetPacketPeer, msec]


func start(port: int = P.DEFAULT_PORT, max_clients: int = 256) -> Error:
	connection = ENetConnection.new()
	var err := connection.create_host_bound("*", port, max_clients, P.CHANNELS)
	if err != OK:
		connection = null
		return err
	_log("Servidor de salas escuchando en UDP %d" % port)
	return OK


func stop() -> void:
	if connection:
		for peer in connection.get_peers():
			peer.peer_disconnect_now()
		connection.destroy()
		connection = null
	rooms.clear()
	members.clear()


func poll() -> void:
	if connection == null:
		return
	var now := Time.get_ticks_msec()
	for kick in _pending_kicks.duplicate():
		if now >= kick[1]:
			(kick[0] as ENetPacketPeer).peer_disconnect()
			_pending_kicks.erase(kick)
	while true:
		var event := connection.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = event[1]
		match type:
			ENetConnection.EVENT_DISCONNECT:
				_leave(peer)
			ENetConnection.EVENT_RECEIVE:
				_receive(peer, peer.get_packet(), event[3])


func room_count() -> int:
	return rooms.size()


func _receive(peer: ENetPacketPeer, packet: PackedByteArray, channel: int) -> void:
	if packet.is_empty():
		return
	var type := packet[0]
	if type == P.DATA:
		_forward(peer, packet, channel)
		return
	var args := P.control_args(packet)
	match type:
		P.HOST:
			if _check_version(peer, args):
				_create_room(peer, String(args[2]) if args.size() >= 3 else "")
		P.LIST:
			if _check_version(peer, args):
				_send(peer, P.control(P.ROOMS, [_open_rooms()]))
		P.INFO:
			var host_info: Dictionary = members.get(peer, {})
			if host_info.get("id", 0) == 1 and args.size() >= 2:
				var room: Dictionary = rooms[host_info["code"]]
				room["name"] = _clean_name(String(args[0]), host_info["code"])
				room["open"] = bool(args[1])
		P.JOIN:
			if _check_version(peer, args) and args.size() >= 3:
				_join(peer, String(args[2]).to_upper().strip_edges())
		P.KICK:
			var info: Dictionary = members.get(peer, {})
			if info.get("id", 0) == 1 and args.size() >= 1:
				var target: ENetPacketPeer = rooms[info["code"]]["peers"].get(int(args[0]))
				if target:
					target.peer_disconnect()


func _check_version(peer: ENetPacketPeer, args: Array) -> bool:
	if members.has(peer):
		return false
	if args.size() < 2 or args[0] != P.GAME_TAG:
		_reject(peer, "Servidor no válido.")
		return false
	if int(args[1]) != P.VERSION:
		_reject(peer, "Versión del juego distinta a la del servidor: actualiza el juego.")
		return false
	return true


func _create_room(peer: ENetPacketPeer, room_name: String) -> void:
	var code := _new_code()
	rooms[code] = {"peers": {1: peer}, "next_id": 2, "name": _clean_name(room_name, code), "open": true}
	members[peer] = {"code": code, "id": 1}
	_send(peer, P.control(P.ROOM, [code]))
	_log("Sala %s creada (%d salas)" % [code, rooms.size()])


func _join(peer: ENetPacketPeer, code: String) -> void:
	if not rooms.has(code):
		_reject(peer, "No existe ninguna sala con el código %s." % code)
		return
	var room: Dictionary = rooms[code]
	if room["peers"].size() >= P.MAX_ROOM_PEERS:
		_reject(peer, "La sala está llena.")
		return
	if not room["open"]:
		_reject(peer, "La partida de esa sala ya ha empezado.")
		return
	# Identificadores grandes y únicos dentro de la sala (como los de ENetMultiplayerPeer).
	var id: int = room["next_id"]
	room["next_id"] = id + 1
	room["peers"][id] = peer
	members[peer] = {"code": code, "id": id}
	_send(peer, P.control(P.JOINED, [id, code]))
	_send(room["peers"][1], P.control(P.PEER_ON, [id]))
	_log("Sala %s: entra el jugador %d (%d)" % [code, id, room["peers"].size()])


func _leave(peer: ENetPacketPeer) -> void:
	_pending_kicks = _pending_kicks.filter(func(k): return k[0] != peer)
	if not members.has(peer):
		return
	var info: Dictionary = members[peer]
	members.erase(peer)
	var code: String = info["code"]
	var room: Dictionary = rooms.get(code, {})
	if room.is_empty():
		return
	room["peers"].erase(info["id"])
	if info["id"] == 1:
		# Sin anfitrión no hay partida: se cierra la sala y se echa a los demás.
		for other in room["peers"].values():
			members.erase(other)
			(other as ENetPacketPeer).peer_disconnect()
		rooms.erase(code)
		_log("Sala %s cerrada (%d salas)" % [code, rooms.size()])
	else:
		_send(room["peers"][1], P.control(P.PEER_OFF, [info["id"]]))
		_log("Sala %s: sale el jugador %d" % [code, info["id"]])


## Reenvía un paquete del juego. Destino como en MultiplayerPeer: 0 todos, >0 ese, <0 todos menos ese.
func _forward(peer: ENetPacketPeer, packet: PackedByteArray, channel: int) -> void:
	var info: Dictionary = members.get(peer, {})
	if info.is_empty() or packet.size() < 5:
		return
	var target := packet.decode_s32(1)
	var from: int = info["id"]
	var room_peers: Dictionary = rooms[info["code"]]["peers"]
	var out := P.data(from, packet.slice(5))
	var flags := P.flags_for(channel)
	for id in room_peers:
		if id == from:
			continue
		if target > 0 and id != target:
			continue
		if target < 0 and id == -target:
			continue
		(room_peers[id] as ENetPacketPeer).send(channel, out, flags)


## Salas que admiten jugadores: [[code, nombre, jugadores], ...], las más llenas primero.
func _open_rooms() -> Array:
	var out := []
	for code in rooms:
		var room: Dictionary = rooms[code]
		if room["open"] and room["peers"].size() < P.MAX_ROOM_PEERS:
			out.append([code, room["name"], room["peers"].size()])
	out.sort_custom(func(a, b): return a[2] > b[2])
	return out.slice(0, P.MAX_LISTED)


func _clean_name(room_name: String, code: String) -> String:
	var clean := room_name.strip_edges().left(P.MAX_NAME)
	return clean if clean != "" else "Sala %s" % code


func _reject(peer: ENetPacketPeer, reason: String) -> void:
	_send(peer, P.control(P.ERROR, [reason]))
	_pending_kicks.append([peer, Time.get_ticks_msec() + KICK_DELAY_MS])


func _send(peer: ENetPacketPeer, packet: PackedByteArray) -> void:
	peer.send(P.CH_CONTROL, packet, ENetPacketPeer.FLAG_RELIABLE)


func _new_code() -> String:
	while true:
		var code := ""
		for i in P.CODE_LENGTH:
			code += P.CODE_LETTERS[randi() % P.CODE_LETTERS.length()]
		if not rooms.has(code):
			return code
	return ""


func _log(text: String) -> void:
	if verbose:
		print("[%s] %s" % [Time.get_datetime_string_from_system(), text])
