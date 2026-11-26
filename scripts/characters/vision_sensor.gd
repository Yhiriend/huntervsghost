class_name VisionSensor
extends Node3D
## Visión de un personaje: cono (ángulo + radio) + línea de visión sin paredes de por medio.
## Lo usan el jugador (qué Ghosts se dibujan) y, más adelante, la IA: así nadie hace trampas.
## Con GameManager.debug_vision dibuja el cono recortado por las paredes y líneas a los objetivos
## (verde = lo ve, rojo = no lo ve). La zona interior más intensa es lo que se ve a oscuras.

## Altura de los "ojos". Las paredes (1,2 m) tapan; los muebles bajos, no.
const EYE_HEIGHT := 1.1
const WORLD_MASK := 1
const DEBUG_FLOOR_Y := 0.06
const LINE_SEEN := Color(0.3, 1.0, 0.4, 0.9)
const LINE_HIDDEN := Color(1.0, 0.3, 0.3, 0.7)

var _character: CharacterBase
var _mesh := ImmediateMesh.new()
var _debug_instance: MeshInstance3D


func _ready() -> void:
	_character = get_parent() as CharacterBase
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "VisionDebug"
	_debug_instance.top_level = true  # Se dibuja en coordenadas globales.
	_debug_instance.mesh = _mesh
	_debug_instance.material_override = material
	_debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debug_instance)


func get_eye_position() -> Vector3:
	return _character.global_position + Vector3.UP * EYE_HEIGHT


## Dirección a la que mira el personaje, en el plano XZ.
func get_forward() -> Vector3:
	var forward := -_character.global_basis.z
	forward.y = 0.0
	return forward.normalized()


func can_see(target: CharacterBase) -> bool:
	if not is_instance_valid(target) or not target.is_detectable():
		return false
	var to_target := target.global_position - _character.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > _character.get_vision_radius_at(target.global_position):
		return false
	if distance > GameManager.config.vision_proximity_radius and distance > 0.001:
		var angle := rad_to_deg(get_forward().angle_to(to_target))
		if angle > _character.get_vision_fov() * 0.5:
			return false
	return not _is_blocked(get_eye_position(), target.global_position + Vector3.UP * EYE_HEIGHT)


func _is_blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if GameManager.debug_vision and _character.is_visible_in_tree() and _character.is_active():
		_draw_debug()


func _draw_debug() -> void:
	var cfg := GameManager.config
	var space := get_world_3d().direct_space_state
	var eye := get_eye_position()
	var forward := get_forward()
	var radius := _character.get_vision_radius()
	var fov := deg_to_rad(_character.get_vision_fov())
	var rays := maxi(cfg.vision_debug_rays, 2)
	var color := _character.get_debug_color()

	var min_radius := _character.get_min_vision_radius()

	# Cono: abanico de rayos recortado por las paredes.
	var points := PackedVector3Array()
	var inner_points := PackedVector3Array()
	for i in rays + 1:
		var angle := -fov * 0.5 + fov * float(i) / float(rays)
		var dir := forward.rotated(Vector3.UP, angle)
		var end := eye + dir * radius
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, end, WORLD_MASK))
		var reach := radius if hit.is_empty() else eye.distance_to(hit.position)
		var point := eye + dir * reach
		var inner := eye + dir * minf(reach, min_radius)
		points.append(Vector3(point.x, DEBUG_FLOOR_Y, point.z))
		inner_points.append(Vector3(inner.x, DEBUG_FLOOR_Y + 0.005, inner.z))

	var center := Vector3(eye.x, DEBUG_FLOOR_Y, eye.z)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_fan(center, points, color)
	if min_radius < radius - 0.01:
		_add_fan(center + Vector3.UP * 0.005, inner_points, color)
	_mesh.surface_end()

	# Líneas hacia los objetivos cercanos. Solo hacia los que el jugador ya ve en pantalla:
	# una línea hacia alguien oculto (tras una pared, en otra habitación) delataría su posición.
	var lines: Array = []
	for node in _character.get_vision_targets():
		var target := node as CharacterBase
		if target == null or not target.is_detectable() or not target.is_visible_in_tree():
			continue
		if target.global_position.distance_to(_character.global_position) > radius:
			continue
		lines.append([target.global_position + Vector3.UP * EYE_HEIGHT, LINE_SEEN if can_see(target) else LINE_HIDDEN])
	if lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line in lines:
		_mesh.surface_set_color(line[1])
		_mesh.surface_add_vertex(eye)
		_mesh.surface_add_vertex(line[0])
	_mesh.surface_end()


func _add_fan(center: Vector3, points: PackedVector3Array, color: Color) -> void:
	for i in points.size() - 1:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(center)
		_mesh.surface_add_vertex(points[i])
		_mesh.surface_add_vertex(points[i + 1])
