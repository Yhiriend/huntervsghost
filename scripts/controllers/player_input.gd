class_name PlayerInput
extends CharacterController
## Traduce teclado/ratón/mando a intenciones del personaje.
## El movimiento es relativo a la cámara: "arriba" siempre es hacia el fondo de la pantalla.

## Altura del plano sobre el que se proyecta el ratón para apuntar.
const AIM_HEIGHT := 0.8


func update_intent(character: CharacterBase, intent: CharacterIntent) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam := character.get_viewport().get_camera_3d()

	var right := Vector3.RIGHT
	var forward := Vector3.FORWARD
	if cam:
		right = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
		forward = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()

	intent.move_dir = right * input.x + forward * -input.y
	intent.sneak = Input.is_action_pressed("sneak")
	intent.fire = Input.is_action_just_pressed("fire")
	intent.interact = Input.is_action_just_pressed("interact")
	intent.interact_held = Input.is_action_pressed("interact")

	if cam:
		var mouse := character.get_viewport().get_mouse_position()
		var plane := Plane(Vector3.UP, character.global_position.y + AIM_HEIGHT)
		var hit: Variant = plane.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
		if hit != null:
			intent.aim_point = hit
			intent.has_aim = true
