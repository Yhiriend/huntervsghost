class_name AIController
extends CharacterController
## Base de la IA (máquina de estados en HunterAI / GhostAI).
## Proporciona: navegación con NavigationAgent3D, apertura de puertas, oído (ruidos con error,
## igual que el jugador) y una etiqueta de depuración con el estado (visible con F2).
## La IA solo usa información que también tendría un jugador: lo que ve su VisionSensor
## y los ruidos que oye. Nunca consulta posiciones de rivales que no percibe.

const DOOR_OPEN_DISTANCE := 1.5
const STUCK_SPEED := 0.4
const STUCK_TIME := 1.2
const REPATH_INTERVAL := 0.3
## Por encima de esta altura la malla está sobre muebles o paredes (no es suelo).
const MAX_FLOOR_Y := 0.6

var character: CharacterBase
var agent: NavigationAgent3D
var state_name: String = ""
## Tiempo de juego de esta IA (segundos).
var now: float = 0.0

var _label: Label3D
var _has_destination: bool = false
var _destination := Vector3.ZERO
var _repath_timer: float = 0.0
var _stuck_timer: float = 0.0
## Último ruido oído de un rival: { "position": Vector3, "time": float }.
var _last_noise: Dictionary = {}


func _ready() -> void:
	character = get_parent() as CharacterBase
	agent = NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.6
	agent.radius = 0.25  # Como la cápsula de los personajes (ajustada a los modelos).
	agent.height = 1.6
	agent.path_max_distance = 3.0
	character.add_child.call_deferred(agent)

	_label = Label3D.new()
	_label.name = "AIStateLabel"
	_label.position = Vector3(0.0, 3.6, 0.0)  # Por encima del nombre (la cámara inclinada acerca las alturas).
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.007
	_label.font_size = 36
	_label.outline_size = 10
	_label.modulate = Color(0.6, 1.0, 0.6)
	character.add_child.call_deferred(_label)

	GameManager.noise_made.connect(_on_noise_made)


func get_tag() -> String:
	return "IA"


func reset() -> void:
	_has_destination = false
	_stuck_timer = 0.0
	_last_noise = {}
	now = 0.0


func update_intent(_character: CharacterBase, intent: CharacterIntent) -> void:
	intent.reset()
	var delta := character.get_physics_process_delta_time()
	now += delta
	if not is_navigation_ready():
		return
	think(delta, intent)
	if _label:
		_label.text = state_name


func _process(_delta: float) -> void:
	if _label:
		_label.visible = GameManager.debug_vision and character.controller == self


## Lo implementan HunterAI y GhostAI.
func think(_delta: float, _intent: CharacterIntent) -> void:
	pass


# --- Navegación ------------------------------------------------------------------

func is_navigation_ready() -> bool:
	var house := character.get_tree().get_first_node_in_group("house") as House
	return house != null and house.nav_ready and agent != null and agent.is_inside_tree()


func set_destination(point: Vector3) -> void:
	if _has_destination and _destination.distance_to(point) < 0.3:
		return
	_destination = point
	_has_destination = true
	agent.target_position = point
	_stuck_timer = 0.0


func clear_destination() -> void:
	_has_destination = false


func has_destination() -> bool:
	return _has_destination


## Sigue la ruta hacia el destino. Devuelve true al llegar (o si no hay destino).
func navigate(intent: CharacterIntent, delta: float) -> bool:
	if not _has_destination:
		return true
	if agent.is_navigation_finished() or flat_distance(character.global_position, _destination) < 0.5:
		_has_destination = false
		return true
	var next := agent.get_next_path_position()
	var dir := next - character.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return false
	intent.move_dir = dir.normalized()
	_handle_doors(intent)
	_check_stuck(delta)
	return false


## Punto aleatorio del suelo navegable (no encima de muebles).
func random_floor_point() -> Vector3:
	var map := character.get_world_3d().navigation_map
	for attempt in 12:
		var point := NavigationServer3D.map_get_random_point(map, 1, true)
		if point.y < MAX_FLOOR_Y:
			return Vector3(point.x, 0.0, point.z)
	return character.global_position


## Longitud aproximada del camino a pie (sirve para decidir qué escondite está "más cerca").
func path_length_to(point: Vector3, from: Vector3 = Vector3.INF) -> float:
	var start := character.global_position if from == Vector3.INF else from
	var map := character.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, start, point, true)
	if path.is_empty():
		return INF
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	return length


## Atascado: si se intenta avanzar sin moverse durante un rato, se descarta el destino.
func _check_stuck(delta: float) -> void:
	var speed := Vector2(character.velocity.x, character.velocity.z).length()
	if speed < STUCK_SPEED:
		_stuck_timer += delta
		if _stuck_timer > STUCK_TIME:
			_stuck_timer = 0.0
			_has_destination = false
			on_stuck()
	else:
		_stuck_timer = 0.0


## Lo pueden sobrescribir HunterAI y GhostAI.
func on_stuck() -> void:
	pass


## Abre (con E, como un jugador) la puerta cerrada que tenga delante.
func _handle_doors(intent: CharacterIntent) -> void:
	for node in character.get_tree().get_nodes_in_group("doors"):
		var door := node as Door
		if door.is_open:
			continue
		var to_door := door.global_position - character.global_position
		to_door.y = 0.0
		if to_door.length() < DOOR_OPEN_DISTANCE and to_door.normalized().dot(intent.move_dir) > 0.2:
			intent.interact = true
			intent.interact_with = door
			return


# --- Percepción -------------------------------------------------------------------

## Rivales que la IA percibe como "enemigos" (los Hunter para un Ghost y viceversa).
func is_enemy(node: Node) -> bool:
	return node is CharacterBase and node != character and (node is Hunter) != (character is Hunter)


func _on_noise_made(noise_position: Vector3, radius: float, source: Node) -> void:
	if character == null or not is_instance_valid(character) or not is_enemy(source):
		return
	if flat_distance(noise_position, character.global_position) > radius:
		return
	# Misma imprecisión que ve el jugador Hunter.
	var error := GameManager.config.noise_position_error
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0) * error
	_last_noise = {"position": noise_position + Vector3(jitter.x, 0.0, jitter.y), "time": now}


## Último ruido oído si es reciente (o un diccionario vacío).
func recent_noise(max_age: float = -1.0) -> Dictionary:
	if _last_noise.is_empty():
		return {}
	var age_limit := GameManager.config.ai_noise_memory if max_age < 0.0 else max_age
	return _last_noise if now - float(_last_noise["time"]) <= age_limit else {}


func forget_noise() -> void:
	_last_noise = {}


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
