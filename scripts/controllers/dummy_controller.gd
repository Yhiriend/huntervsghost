class_name DummyController
extends CharacterController
## Controlador de maniquí. No toma decisiones: sirve para probar mecánicas sin IA.
##   STATIC: se queda quieto.
##   ROUTE:  recorre en bucle los puntos de un Path3D y abre las puertas cerradas que encuentra.
##   shoots_on_sight (Hunter): si ve a un Ghost libre a tiro durante dummy_reaction_time, dispara.

const ARRIVE_DISTANCE := 0.4
const DOOR_OPEN_DISTANCE := 1.6

var behavior: DummySpawn.Behavior = DummySpawn.Behavior.STATIC
var sneak: bool = false
var shoots_on_sight: bool = false

var _waypoints := PackedVector3Array()
var _index: int = 0
var _seen_time: float = 0.0


func setup(spawn: DummySpawn) -> void:
	behavior = spawn.behavior
	sneak = spawn.route_sneak
	shoots_on_sight = spawn.shoots_on_sight
	_waypoints.clear()
	if behavior == DummySpawn.Behavior.ROUTE:
		var path := spawn.get_node_or_null(spawn.route) as Path3D
		if path == null or path.curve == null or path.curve.point_count == 0:
			push_warning("DummySpawn '%s' tiene ROUTE pero no un Path3D válido." % spawn.name)
		else:
			for i in path.curve.point_count:
				_waypoints.append(path.to_global(path.curve.get_point_position(i)))
	reset()


func reset() -> void:
	_index = 0
	_seen_time = 0.0


func update_intent(character: CharacterBase, intent: CharacterIntent) -> void:
	intent.reset()
	if behavior == DummySpawn.Behavior.ROUTE and not _waypoints.is_empty():
		_follow_route(character, intent)
	if shoots_on_sight and character is Hunter:
		_shoot_on_sight(character as Hunter, intent)


func _follow_route(character: CharacterBase, intent: CharacterIntent) -> void:
	var to_target := _waypoints[_index] - character.global_position
	to_target.y = 0.0
	if to_target.length() < ARRIVE_DISTANCE:
		_index = (_index + 1) % _waypoints.size()
		to_target = _waypoints[_index] - character.global_position
		to_target.y = 0.0
	intent.move_dir = to_target.normalized()
	intent.sneak = sneak
	_open_doors_nearby(character)


## Igual que hará la IA: las puertas cerradas en el camino se abren automáticamente.
func _open_doors_nearby(character: CharacterBase) -> void:
	for node in character.get_tree().get_nodes_in_group("doors"):
		var door := node as Door
		if door.is_open:
			continue
		var offset := door.global_position - character.global_position
		offset.y = 0.0
		if offset.length() < DOOR_OPEN_DISTANCE:
			door.set_open(true, character)


func _shoot_on_sight(hunter: Hunter, intent: CharacterIntent) -> void:
	var target: Ghost = null
	for node in hunter.get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if ghost.state != Ghost.State.FREE or not hunter.vision.can_see(ghost):
			continue
		if hunter.global_position.distance_to(ghost.global_position) <= GameManager.config.net_range:
			target = ghost
			break
	if target == null:
		_seen_time = 0.0
		return
	_seen_time += hunter.get_physics_process_delta_time()
	intent.aim_point = target.global_position
	intent.has_aim = true
	intent.fire = _seen_time >= GameManager.config.dummy_reaction_time and hunter.is_net_ready()
