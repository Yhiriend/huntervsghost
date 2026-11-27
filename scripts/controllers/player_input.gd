class_name PlayerInput
extends CharacterController
## Traduce teclado/ratón/mando o los controles táctiles a intenciones del personaje.
## El movimiento es relativo a la cámara: "arriba" siempre es hacia el fondo de la pantalla.
## Con controles táctiles el Hunter usa auto-apuntado: fija el Ghost visible más cercano
## hacia donde vas o miras, con algo de anticipación de su movimiento.

## Altura del plano sobre el que se proyecta el ratón para apuntar.
const AIM_HEIGHT := 0.8
## Un Ghost fijado se mantiene hasta este ángulo (más que para fijarlo: no salta de uno a otro).
const AIM_KEEP_ANGLE := 150.0
## Y hasta esta distancia relativa a touch_aim_range.
const AIM_KEEP_RANGE_FACTOR := 1.2

## Ghost fijado por el auto-apuntado.
var aim_target: Ghost


func reset() -> void:
	aim_target = null


func update_intent(character: CharacterBase, intent: CharacterIntent) -> void:
	var touch := GameManager.is_touch_mode()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sneak := Input.is_action_pressed("sneak")
	if touch and TouchControls.move != Vector2.ZERO:
		# Inclinar poco el joystick = sigilo; la velocidad la decide el sigilo, no la inclinación.
		sneak = TouchControls.move.length() < GameManager.config.touch_sneak_threshold
		input = TouchControls.move.normalized()
	if touch and TouchControls.walk_held:
		sneak = true  # Botón CAMINAR: camina aunque el joystick esté a tope.

	var cam := character.get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var forward := Vector3.FORWARD
	if cam:
		right = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
		forward = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()

	intent.move_dir = right * input.x + forward * -input.y
	intent.sneak = sneak

	if touch:
		# El ratón no dispara (en el móvil cada toque también genera un clic emulado).
		intent.fire = TouchControls.take_fire()
		intent.interact = TouchControls.take_interact() or Input.is_action_just_pressed("interact")
		intent.interact_held = TouchControls.interact_held or Input.is_action_pressed("interact")
		intent.decoy = TouchControls.take_decoy() or Input.is_action_just_pressed("decoy")
		intent.decoy_held = TouchControls.decoy_held or Input.is_action_pressed("decoy")
		if character is Hunter:
			_update_auto_aim(character as Hunter, intent)
		return

	aim_target = null
	intent.fire = Input.is_action_just_pressed("fire")
	intent.interact = Input.is_action_just_pressed("interact")
	intent.interact_held = Input.is_action_pressed("interact")
	intent.decoy = Input.is_action_just_pressed("decoy")
	intent.decoy_held = Input.is_action_pressed("decoy")
	if cam:
		var mouse := character.get_viewport().get_mouse_position()
		var plane := Plane(Vector3.UP, character.global_position.y + AIM_HEIGHT)
		var hit: Variant = plane.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
		if hit != null:
			intent.aim_point = hit
			intent.has_aim = true


# --- Auto-apuntado (móvil) ---------------------------------------------------------

func _update_auto_aim(hunter: Hunter, intent: CharacterIntent) -> void:
	var cfg := GameManager.config
	if not cfg.touch_auto_aim:
		aim_target = null
		return
	# Referencia: hacia donde se mueve; si está quieto, hacia donde mira.
	var reference := intent.move_dir
	if reference.length_squared() < 0.01:
		reference = -hunter.global_basis.z
	reference.y = 0.0
	reference = reference.normalized()

	if aim_target and not _is_valid_target(hunter, aim_target, reference, cfg.touch_aim_range * AIM_KEEP_RANGE_FACTOR, AIM_KEEP_ANGLE):
		aim_target = null
	if aim_target == null:
		aim_target = find_aim_target(hunter, reference)
	if aim_target == null:
		return

	# Anticipación: dónde estará el Ghost cuando llegue la red.
	var distance := AIController.flat_distance(hunter.global_position, aim_target.global_position)
	var flight_time := distance / maxf(cfg.net_speed, 0.1)
	var predicted := aim_target.global_position + aim_target.velocity * flight_time * cfg.touch_aim_lead
	intent.aim_point = Vector3(predicted.x, hunter.global_position.y + AIM_HEIGHT, predicted.z)
	intent.has_aim = true


## Ghost libre y visible más conveniente: cerca y en la dirección de referencia.
func find_aim_target(hunter: Hunter, reference: Vector3) -> Ghost:
	var cfg := GameManager.config
	var best: Ghost = null
	var best_score := INF
	for node in hunter.get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if not _is_valid_target(hunter, ghost, reference, cfg.touch_aim_range, cfg.touch_aim_max_angle):
			continue
		var to_ghost := ghost.global_position - hunter.global_position
		to_ghost.y = 0.0
		var angle := rad_to_deg(reference.angle_to(to_ghost))
		var score := to_ghost.length() * (1.0 + angle / 90.0)
		if score < best_score:
			best_score = score
			best = ghost
	return best


func _is_valid_target(hunter: Hunter, ghost: Ghost, reference: Vector3, max_range: float, max_angle: float) -> bool:
	if not is_instance_valid(ghost) or ghost.state != Ghost.State.FREE:
		return false
	var to_ghost := ghost.global_position - hunter.global_position
	to_ghost.y = 0.0
	if to_ghost.length() > max_range or to_ghost.length() < 0.01:
		return false
	if rad_to_deg(reference.angle_to(to_ghost)) > max_angle:
		return false
	return hunter.vision.can_see(ghost)
