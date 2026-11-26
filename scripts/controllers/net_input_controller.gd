class_name NetInputController
extends CharacterController
## En el anfitrión: controla el personaje de un jugador remoto con las intenciones que envía su
## dispositivo (MatchScenario las recibe y las guarda en apply_packet()).
## Disparar y usar llegan como contadores: si el paquete de un frame se pierde, la pulsación no.

## Formato del paquete (PackedFloat32Array), compartido con MatchScenario.
enum Field { FIRE_SEQ, INTERACT_SEQ, MOVE_X, MOVE_Z, SNEAK, HAS_AIM, AIM_X, AIM_Z, HELD, SIZE }

var peer: int = 0
var _packet := PackedFloat32Array()
var _fire_seen: int = -1
var _interact_seen: int = -1
var _pending_fire: bool = false
var _pending_interact: bool = false


func get_tag() -> String:
	return ""


func reset() -> void:
	_packet = PackedFloat32Array()
	_pending_fire = false
	_pending_interact = false


func apply_packet(packet: PackedFloat32Array) -> void:
	if packet.size() < Field.SIZE:
		return
	var fire_seq := int(packet[Field.FIRE_SEQ])
	var interact_seq := int(packet[Field.INTERACT_SEQ])
	# El primer paquete solo fija la referencia de los contadores.
	if _fire_seen >= 0 and fire_seq != _fire_seen:
		_pending_fire = true
	if _interact_seen >= 0 and interact_seq != _interact_seen:
		_pending_interact = true
	_fire_seen = fire_seq
	_interact_seen = interact_seq
	_packet = packet


func update_intent(character: CharacterBase, intent: CharacterIntent) -> void:
	if _packet.size() < Field.SIZE:
		return
	intent.move_dir = Vector3(_packet[Field.MOVE_X], 0.0, _packet[Field.MOVE_Z])
	intent.sneak = _packet[Field.SNEAK] > 0.5
	intent.has_aim = _packet[Field.HAS_AIM] > 0.5
	if intent.has_aim:
		intent.aim_point = Vector3(_packet[Field.AIM_X], character.global_position.y + PlayerInput.AIM_HEIGHT, _packet[Field.AIM_Z])
	intent.interact_held = _packet[Field.HELD] > 0.5
	intent.fire = _pending_fire
	intent.interact = _pending_interact
	_pending_fire = false
	_pending_interact = false


## Construye el paquete a partir de las intenciones del jugador local (en el cliente).
static func make_packet(intent: CharacterIntent, fire_seq: int, interact_seq: int) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(Field.SIZE)
	p[Field.FIRE_SEQ] = fire_seq
	p[Field.INTERACT_SEQ] = interact_seq
	p[Field.MOVE_X] = intent.move_dir.x
	p[Field.MOVE_Z] = intent.move_dir.z
	p[Field.SNEAK] = 1.0 if intent.sneak else 0.0
	p[Field.HAS_AIM] = 1.0 if intent.has_aim else 0.0
	p[Field.AIM_X] = intent.aim_point.x
	p[Field.AIM_Z] = intent.aim_point.z
	p[Field.HELD] = 1.0 if intent.interact_held else 0.0
	return p
