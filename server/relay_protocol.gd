extends RefCounted
## Protocolo entre el juego y el servidor de salas (server/relay_server.gd), sobre ENet (UDP).
## Sin class_name: el servidor se ejecuta con --script en un VPS sin la caché de clases del editor.
##
## Cada paquete empieza por un byte de tipo. Los de control van por el canal 0 (fiables) y
## llevan detrás var_to_bytes(Array). Los de datos (DATA) llevan un entero de 32 bits
## (destino al enviar, origen al recibir) y después el paquete del juego tal cual.

const DEFAULT_PORT := 24680
const GAME_TAG := "cazador-o-presa"
## Cambia si cambia este protocolo (no el del juego, que ya comprueba Net.PROTOCOL).
const VERSION := 1
const CHANNELS := 4
const MAX_ROOM_PEERS := 4
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const CODE_LENGTH := 4

# Canales: 0 control, 1 datos fiables, 2 sin garantía pero en orden, 3 sin garantía ni orden.
const CH_CONTROL := 0
const CH_RELIABLE := 1
const CH_ORDERED := 2
const CH_UNRELIABLE := 3

# Cliente -> servidor
const HOST := 1  ## [tag, version] crea una sala; quien la crea es el peer 1.
const JOIN := 2  ## [tag, version, code]
const KICK := 3  ## [peer] (solo el anfitrión)
# Servidor -> cliente
const ROOM := 10  ## [code]
const JOINED := 11  ## [peer, code]
const PEER_ON := 12  ## [peer] (solo al anfitrión)
const PEER_OFF := 13  ## [peer] (solo al anfitrión)
const ERROR := 14  ## [texto]
# Ambos sentidos
const DATA := 20


static func control(type: int, args: Array) -> PackedByteArray:
	var out := PackedByteArray([type])
	out.append_array(var_to_bytes(args))
	return out


static func control_args(packet: PackedByteArray) -> Array:
	if packet.size() < 2:
		return []
	var value: Variant = bytes_to_var(packet.slice(1))
	return value if value is Array else []


static func data(peer: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(5)
	out[0] = DATA
	out.encode_s32(1, peer)
	out.append_array(payload)
	return out


static func flags_for(channel: int) -> int:
	match channel:
		CH_ORDERED:
			return ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
		CH_UNRELIABLE:
			return ENetPacketPeer.FLAG_UNSEQUENCED | ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
	return ENetPacketPeer.FLAG_RELIABLE
