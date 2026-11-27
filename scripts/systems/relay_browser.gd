class_name RelayBrowser
extends RefCounted
## Lista las salas abiertas del servidor de salas (para "Por internet"), como la búsqueda
## automática de la red local. Usa su propia conexión ligera, aparte de la de la partida:
## se conecta, pide la lista cada REFRESH segundos y avisa cuando cambia. Hay que llamar a poll().

signal changed

const P := preload("res://server/relay_protocol.gd")
const REFRESH := 2.0
## Si no se consigue conectar, se reintenta tras este tiempo.
const RETRY := 4.0

## Salas abiertas: [{"code", "name", "players"}].
var rooms: Array = []
## "connecting" / "ok" / "error"
var state: String = "connecting"
var error_text: String = ""

var _address := ""
var _port := P.DEFAULT_PORT
var _connection: ENetConnection
var _server: ENetPacketPeer
var _connected := false
var _next_request := 0.0
var _retry_at := 0.0


func start(address: String, port: int) -> void:
	stop()
	_address = address
	_port = port
	_connect()


func stop() -> void:
	if _server:
		_server.peer_disconnect_now()
	if _connection:
		_connection.flush()
		_connection.destroy()
	_connection = null
	_server = null
	_connected = false


func poll(delta: float) -> void:
	if _connection == null:
		if _address != "" and _retry_at > 0.0:
			_retry_at -= delta
			if _retry_at <= 0.0:
				_connect()
		return
	while _connection:
		var event := _connection.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE:
			break
		match type:
			ENetConnection.EVENT_CONNECT:
				_connected = true
				_next_request = 0.0
			ENetConnection.EVENT_DISCONNECT, ENetConnection.EVENT_ERROR:
				_fail(error_text if error_text != "" else "No se puede conectar con el servidor de salas.")
				return
			ENetConnection.EVENT_RECEIVE:
				_receive((event[1] as ENetPacketPeer).get_packet())
	if _connected:
		_next_request -= delta
		if _next_request <= 0.0:
			_next_request = REFRESH
			_server.send(P.CH_CONTROL, P.control(P.LIST, [P.GAME_TAG, P.VERSION]), ENetPacketPeer.FLAG_RELIABLE)


func _connect() -> void:
	_retry_at = 0.0
	var ip := _address.strip_edges()
	if not ip.is_valid_ip_address():
		ip = IP.resolve_hostname(ip, IP.TYPE_IPV4)
	if ip == "":
		_fail("No se encuentra el servidor %s." % _address)
		return
	_connection = ENetConnection.new()
	if _connection.create_host(1, P.CHANNELS) != OK:
		_fail("No se pudo abrir la conexión.")
		return
	_server = _connection.connect_to_host(ip, _port, P.CHANNELS)
	if _server == null:
		_fail("No se pudo conectar con el servidor de salas.")
		return
	_server.set_timeout(8, 3000, 8000)
	if state != "ok":
		state = "connecting"
		changed.emit()


func _receive(packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	var args := P.control_args(packet)
	match packet[0]:
		P.ROOMS:
			var list := []
			for entry in (args[0] if not args.is_empty() else []):
				list.append({"code": String(entry[0]), "name": String(entry[1]), "players": int(entry[2])})
			var was := state
			state = "ok"
			error_text = ""
			if list != rooms or was != "ok":
				rooms = list
				changed.emit()
		P.ERROR:
			error_text = String(args[0]) if not args.is_empty() else "Error del servidor."


func _fail(text: String) -> void:
	stop()
	state = "error"
	error_text = text
	rooms = []
	_retry_at = RETRY
	changed.emit()
