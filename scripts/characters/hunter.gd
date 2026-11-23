class_name Hunter
extends CharacterBase
## Cazador: dispara redes que inmovilizan a los Ghosts y los captura manteniendo "interactuar".
## Jugando con ratón, mira siempre hacia el punto de apuntado.

signal net_fired(hunter: Hunter)

const DEBUG_COLOR := Color(1.0, 0.4, 0.05, 0.25)
const AIM_IN_RANGE := Color(1, 1, 1, 0.9)
const AIM_OUT_OF_RANGE := Color(0.6, 0.6, 0.6, 0.5)

## Segundos que faltan para poder disparar otra vez.
var net_cooldown_left: float = 0.0
## Ghost que se está capturando (null si no se captura).
var capture_target: Ghost = null
## Segundos acumulados manteniendo la captura.
var capture_progress: float = 0.0

var _aim_marker: MeshInstance3D
var _aim_material: StandardMaterial3D


func _ready() -> void:
	super()
	add_to_group("hunters")
	_build_aim_marker()


func get_base_speed() -> float:
	return GameManager.config.hunter_speed


func get_vision_fov() -> float:
	return GameManager.config.hunter_vision_fov


func get_vision_radius() -> float:
	return GameManager.config.vision_radius_lit


## Un Ghost en una habitación a oscuras solo se ve de cerca.
func get_vision_radius_at(target_position: Vector3) -> float:
	var cfg := GameManager.config
	if cfg.lights_affect_vision and Room.is_dark_at(get_tree(), target_position):
		return minf(cfg.vision_radius_dark, cfg.vision_radius_lit)
	return cfg.vision_radius_lit


func get_min_vision_radius() -> float:
	var cfg := GameManager.config
	return minf(cfg.vision_radius_dark, cfg.vision_radius_lit) if cfg.lights_affect_vision else cfg.vision_radius_lit


func get_vision_targets() -> Array[Node]:
	return get_tree().get_nodes_in_group("ghosts")


func get_debug_color() -> Color:
	return DEBUG_COLOR


func can_move() -> bool:
	return capture_target == null and super()


func reset_state() -> void:
	super()
	net_cooldown_left = 0.0
	_cancel_capture()


func is_net_ready() -> bool:
	return net_cooldown_left <= 0.0


## El Ghost atrapado más cercano dentro de la distancia de captura (o null).
func find_capturable_ghost() -> Ghost:
	var best: Ghost = null
	var best_distance := GameManager.config.capture_distance
	for node in get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if ghost == null or ghost.state != Ghost.State.NETTED:
			continue
		var distance := _flat_distance(ghost)
		if distance <= best_distance:
			best = ghost
			best_distance = distance
	return best


func _process_actions(delta: float) -> void:
	net_cooldown_left = maxf(0.0, net_cooldown_left - delta)
	_update_capture(delta)
	# Capturar tiene prioridad sobre usar objetos (puertas, armarios...).
	if capture_target == null and (interact_target != null or find_capturable_ghost() == null):
		_update_interaction(delta)
	if intent.fire and is_net_ready() and capture_target == null and interact_target == null:
		fire_net()
	_update_aim_marker()


## Misma función para jugador e IA.
func fire_net() -> void:
	var dir := Vector3.ZERO
	if intent.has_aim:
		dir = intent.aim_point - global_position
		dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_basis.z
		dir.y = 0.0
	dir = dir.normalized()
	rotation.y = atan2(-dir.x, -dir.z)

	var net := NetProjectile.new()
	get_parent().add_child(net)
	net.launch(self, dir)
	net_cooldown_left = GameManager.config.net_cooldown
	net_fired.emit(self)


func _update_capture(delta: float) -> void:
	if not intent.interact_held or interact_target != null:
		_cancel_capture()
		return
	if capture_target == null:
		capture_target = find_capturable_ghost()
		capture_progress = 0.0
		if capture_target == null:
			return
	var cfg := GameManager.config
	# Si el Ghost se libera o se aleja (empujado), la captura se pierde.
	if capture_target.state != Ghost.State.NETTED or _flat_distance(capture_target) > cfg.capture_distance + 0.3:
		_cancel_capture()
		return
	capture_progress += delta
	if capture_progress >= cfg.capture_time:
		capture_target.capture()
		_cancel_capture()


func _cancel_capture() -> void:
	capture_target = null
	capture_progress = 0.0


func _get_facing_dir(move_dir: Vector3) -> Vector3:
	if intent.has_aim:
		var to_aim := intent.aim_point - global_position
		to_aim.y = 0.0
		if to_aim.length_squared() > 0.04:
			return to_aim
	return move_dir


func _flat_distance(other: Node3D) -> float:
	var offset := other.global_position - global_position
	offset.y = 0.0
	return offset.length()


# --- Marcador de apuntado ------------------------------------------------------

func _build_aim_marker() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.32
	_aim_material = StandardMaterial3D.new()
	_aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = _aim_material
	_aim_marker = MeshInstance3D.new()
	_aim_marker.name = "AimMarker"
	_aim_marker.mesh = torus
	_aim_marker.top_level = true
	_aim_marker.visible = false
	add_child(_aim_marker)


func _update_aim_marker() -> void:
	_aim_marker.visible = is_player_controlled and intent.has_aim
	if not _aim_marker.visible:
		return
	_aim_marker.global_position = Vector3(intent.aim_point.x, 0.05, intent.aim_point.z)
	var in_range := _flat_distance(_aim_marker) <= GameManager.config.net_range
	_aim_material.albedo_color = AIM_IN_RANGE if in_range and is_net_ready() else AIM_OUT_OF_RANGE
