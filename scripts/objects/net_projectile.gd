class_name NetProjectile
extends Node3D
## Red disparada por el Hunter. Avanza en línea recta hasta net_range.
## Se detiene en paredes y muebles altos; inmoviliza al primer Ghost libre que toque.
## Usa rayos en lugar de un cuerpo físico para no atravesar paredes a alta velocidad.

## Altura de vuelo: pasa por encima de sofás y mesas bajas, choca con encimeras (1 m) y paredes.
const FLIGHT_HEIGHT := 0.95
const WORLD_MASK := 1
const VISUAL_RADIUS := 0.2

var _shooter: CharacterBase
var _direction := Vector3.FORWARD
var _travelled: float = 0.0
var _finished: bool = false


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.5
	var mesh := SphereMesh.new()
	mesh.radius = VISUAL_RADIUS
	mesh.height = VISUAL_RADIUS * 2.0
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)


## Llamar justo después de añadir el nodo al árbol.
func launch(shooter: CharacterBase, direction: Vector3) -> void:
	_shooter = shooter
	_direction = direction.normalized()
	global_position = Vector3(shooter.global_position.x, shooter.global_position.y + FLIGHT_HEIGHT, shooter.global_position.z)


func _physics_process(delta: float) -> void:
	# La red de un Hunter oculto tampoco se ve.
	visible = not is_instance_valid(_shooter) or _shooter.is_visible_in_tree()
	if _finished:
		return
	var cfg := GameManager.config
	var step := minf(cfg.net_speed * delta, cfg.net_range - _travelled)
	var from := global_position
	var to := from + _direction * step

	# 1) ¿Choca con el escenario en este tramo?
	var wall_fraction := 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wall_fraction = from.distance_to(hit.position) / maxf(step, 0.0001)

	# 2) ¿Toca a algún Ghost libre antes que la pared?
	var ghost_hit: Ghost = null
	var ghost_fraction := wall_fraction
	for node in get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if ghost == null or ghost.state != Ghost.State.FREE or ghost == _shooter:
			continue
		var fraction := _segment_hit_fraction(from, to, ghost, cfg.net_hit_radius)
		if fraction >= 0.0 and fraction <= ghost_fraction:
			ghost_hit = ghost
			ghost_fraction = fraction

	if ghost_hit:
		ghost_hit.apply_net()
		_finish(from.lerp(to, ghost_fraction), true)
	elif wall_fraction < 1.0:
		_finish(hit.position, false)
	else:
		global_position = to
		_travelled += step
		if _travelled >= cfg.net_range - 0.001:
			_finish(to, false)


## Fracción del tramo [0..1] en la que la red toca al Ghost, o -1 si no lo toca (en el plano XZ).
func _segment_hit_fraction(from: Vector3, to: Vector3, ghost: Ghost, net_radius: float) -> float:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var c := Vector2(ghost.global_position.x, ghost.global_position.z)
	var hit_distance := 0.4 + net_radius  # 0,4 = radio de la cápsula del Ghost.
	var ab := b - a
	var length_sq := ab.length_squared()
	var t := 0.0 if length_sq < 0.000001 else clampf((c - a).dot(ab) / length_sq, 0.0, 1.0)
	if a.lerp(b, t).distance_to(c) > hit_distance:
		return -1.0
	return t


func _finish(at: Vector3, hit_ghost: bool) -> void:
	_finished = true
	global_position = at
	var tween := create_tween()
	if hit_ghost:
		tween.tween_property(self, "scale", Vector3.ONE * 4.0, 0.12)
		tween.tween_property(self, "scale", Vector3.ZERO, 0.1)
	else:
		tween.tween_property(self, "scale", Vector3.ZERO, 0.15)
	tween.tween_callback(queue_free)
