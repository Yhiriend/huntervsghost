class_name MenuBackground
extends SubViewportContainer
## Fondo animado del menú principal: la casa de noche vista desde arriba. El Cazador recorre
## el pasillo barriendo con su linterna, la Presa se asoma tras el muro de la cocina y las
## luces parpadean de vez en cuando. Encima, MainMenu pone un velo oscuro para que se lea.
## Solo decorado: los personajes son los modelos sueltos (sin lógica de juego).
## Rendimiento: se dibuja a media resolución y a BACKGROUND_FPS (no hace falta más en un decorado).

const HOUSE := preload("res://scenes/game/House.tscn")
const ENVIRONMENT := preload("res://scenes/game/house_environment.tres")
const HUNTER_MODEL := preload("res://assets/characters/hunter.glb")
const PREY_MODEL := preload("res://assets/characters/prey.glb")

## Recorrido del Cazador por el pasillo (ida y vuelta) y su velocidad (m/s).
const PATROL_FROM := Vector3(-7.5, 0, 1.5)
const PATROL_TO := Vector3(7.5, 0, 1.5)
const PATROL_SPEED := 1.3
## La Presa se asoma por el extremo del muro de la cocina.
const PREY_HIDDEN := Vector3(4.6, 0, -5.85)
const PREY_PEEK := Vector3(6.55, 0, -5.85)
const BACKGROUND_FPS := 30.0

var _viewport: SubViewport
var _camera: Camera3D
var _hunter: Node3D
var _hunter_anim: AnimationPlayer
var _flashlight: SpotLight3D
var _prey: Node3D
var _time := 0.0
var _patrol := 0.0
var _patrol_dir := 1.0
var _turning := 0.0
var _next_flicker := 3.0
var _rooms: Array = []
var _render_wait := 0.0


func _ready() -> void:
	stretch = true
	# A media resolución: bajo el velo oscuro no se nota y cuesta menos de la mitad
	# (medido con tools/rendimiento.tscn).
	stretch_shrink = 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	add_to_group("graphics_quality")

	var environment := WorldEnvironment.new()
	environment.environment = ENVIRONMENT
	_viewport.add_child(environment)
	var house := HOUSE.instantiate()
	_viewport.add_child(house)
	var labels := house.get_node_or_null("RoomLabels")
	if labels:
		labels.visible = false  # Los rótulos SALA, COCINA... estorbarían al título.

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.far = 120.0
	_viewport.add_child(_camera)

	_hunter = HUNTER_MODEL.instantiate()
	_viewport.add_child(_hunter)
	_hunter.position = PATROL_FROM
	_hunter_anim = _find_player(_hunter)
	_play(_hunter_anim, "Walk")
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1.0, 0.85, 0.55)
	_flashlight.light_energy = 6.0
	_flashlight.spot_range = 10.0
	_flashlight.spot_angle = 28.0
	_flashlight.spot_attenuation = 0.6
	_flashlight.shadow_enabled = true
	_flashlight.position = Vector3(0, 1.1, -0.2)
	_hunter.add_child(_flashlight)

	_prey = PREY_MODEL.instantiate()
	_viewport.add_child(_prey)
	_prey.position = PREY_HIDDEN
	_prey.rotation.y = PI  # Mirando hacia el pasillo (+Z).
	_play(_find_player(_prey), "Idle")

	for room in house.find_children("*", "Room", true, false):
		_rooms.append(room)
	# Sala a oscuras desde el principio: más misterio.
	for room in _rooms:
		if room.name == "Sala":
			room.set_lit(false, false)
	_update_camera(0.0)
	apply_graphics_quality(GameManager.config.graphics_low)


func apply_graphics_quality(low: bool) -> void:
	if _flashlight:
		_flashlight.shadow_enabled = not low


func _process(delta: float) -> void:
	_time += delta
	_render_wait -= delta
	if _render_wait <= 0.0:
		_render_wait += 1.0 / BACKGROUND_FPS
		_render_wait = maxf(_render_wait, 0.0)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hunter(delta)
	_update_prey()
	_update_camera(delta)
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_next_flicker = randf_range(4.0, 9.0)
		_flicker()


func _update_hunter(delta: float) -> void:
	if _turning > 0.0:
		_turning -= delta
		if _turning <= 0.0:
			_play(_hunter_anim, "Walk")
		# Mientras se para, mira a un lado y a otro con la linterna.
		_hunter.rotation.y = _facing(Vector3(_patrol_dir, 0, 0)) + sin(_turning * 3.0) * 0.9
		return
	var length := PATROL_FROM.distance_to(PATROL_TO)
	_patrol += _patrol_dir * PATROL_SPEED * delta / length
	if _patrol >= 1.0 or _patrol <= 0.0:
		_patrol = clampf(_patrol, 0.0, 1.0)
		_patrol_dir = -_patrol_dir
		_turning = 2.2
		_play(_hunter_anim, "Idle")
	_hunter.position = PATROL_FROM.lerp(PATROL_TO, _patrol)
	_hunter.rotation.y = _facing(Vector3(_patrol_dir, 0, 0))
	# Barrido suave de la linterna hacia las habitaciones.
	_flashlight.rotation = Vector3(-0.35, sin(_time * 1.3) * 0.7, 0)


func _update_prey() -> void:
	# Se asoma cuando el Cazador le da la espalda y se esconde cuando va hacia ella.
	var peeking := _patrol_dir < 0.0 and _turning <= 0.0
	var target := PREY_PEEK if peeking else PREY_HIDDEN
	_prey.position = _prey.position.lerp(target, 0.02)


func _update_camera(_delta: float) -> void:
	var center := Vector3(sin(_time * 0.07) * 2.5, 0, 0.5 + cos(_time * 0.05) * 1.5)
	_camera.position = center + Vector3(sin(_time * 0.04) * 4.0, 19.0, 13.0)
	_camera.look_at(center, Vector3.UP)


## Una habitación parpadea y queda encendida o apagada.
func _flicker() -> void:
	if _rooms.is_empty():
		return
	var room: Room = _rooms.pick_random()
	var end_lit := randf() < 0.6
	var tween := create_tween()
	for i in randi_range(2, 4):
		tween.tween_callback(room.set_lit.bind(false, false))
		tween.tween_interval(randf_range(0.04, 0.12))
		tween.tween_callback(room.set_lit.bind(true, false))
		tween.tween_interval(randf_range(0.05, 0.2))
	tween.tween_callback(room.set_lit.bind(end_lit, true))


## Ángulo Y para que el modelo (que mira hacia -Z) mire en esa dirección.
func _facing(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _find_player(model: Node) -> AnimationPlayer:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null


func _play(player: AnimationPlayer, animation: String) -> void:
	if player == null or not player.has_animation(animation):
		return
	player.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
	player.play(animation, 0.2)
