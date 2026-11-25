extends Node
## Prueba de la Fase 7: controles táctiles (joystick, sigilo, RED, botón de acción), auto-apuntado.

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = to_window(pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await frames(2)


func drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = to_window(pos)
	Input.parse_input_event(ev)
	await frames(2)


## Coordenadas del lienzo (1152x648 escalado) -> coordenadas de la ventana, como un toque real.
func to_window(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos


func face(hunter: Node3D, target: Vector3) -> void:
	var d := target - hunter.global_position
	hunter.rotation.y = atan2(-d.x, -d.z)


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("TIMEOUT")
		get_tree().quit(2))
	await run()
	GameManager.config.touch_controls_on_pc = false
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	var cfg := GameManager.config
	cfg.touch_controls_on_pc = true

	var s: TestScenario = load("res://scenes/test/TestHunter.tscn").instantiate()
	add_child(s)
	await frames(5)
	var hunter := s.get_controlled_character() as Hunter
	var hud: HUD = s._hud
	var tc: TouchControls = hud.touch
	check(hunter != null, "TestHunter: controlas al Hunter")
	check(tc.visible and tc.controls_enabled, "Modo táctil: controles visibles y activos")
	check(tc.show_fire, "Hunter: botón RED visible")
	check(tc._scenario_bar.visible, "Escenario de prueba: botones Cambiar/Espectador/Reiniciar")

	# --- Botón de acción deshabilitado (sin nada cerca) ---
	check(tc.action_text == "", "Al empezar no hay acción disponible")
	await touch(3, tc._action_center(), true)
	check(not hunter.intent.interact_held and tc._action_index == -1 and tc._joy_index == -1, "Tocar el botón de acción deshabilitado no hace nada")
	await touch(3, tc._action_center(), false)

	# --- Joystick: correr a la derecha ---
	var start := hunter.global_position
	var base := Vector2(200, tc.size.y - 200)
	await touch(0, base, true)
	await drag(0, base + Vector2(80, 0))
	check(TouchControls.move.x > 0.95, "Joystick a tope a la derecha (move=%s)" % TouchControls.move)
	await frames(30)
	check(not hunter.intent.sneak, "Joystick a tope = correr (sin sigilo)")
	var moved := hunter.global_position - start
	check(moved.x > 0.8 and absf(moved.z) < moved.x, "El Hunter se mueve a la derecha de la pantalla (%s)" % moved)

	# --- Joystick: poco inclinado = sigilo ---
	await drag(0, base + Vector2(30, 0))
	await frames(3)
	check(hunter.intent.sneak, "Joystick poco inclinado = sigilo (move=%.2f)" % TouchControls.move.length())

	# La base sigue al dedo si se pasa del radio.
	await drag(0, base + Vector2(300, 0))
	check(tc._joy_center.x > base.x + 100, "La base del joystick sigue al dedo")
	await touch(0, base, false)
	check(TouchControls.move == Vector2.ZERO, "Soltar el joystick lo centra")
	await frames(20)

	# --- Multitáctil: mover y disparar a la vez ---
	await touch(0, base, true)
	await drag(0, base + Vector2(0, -80))
	await touch(1, tc._fire_center(), true)
	await frames(2)
	check(hunter.net_cooldown_left > 0.0, "Botón RED dispara la red mientras mueves el joystick")
	check(TouchControls.move.y < -0.9, "El joystick sigue activo durante el disparo")
	await touch(1, tc._fire_center(), false)
	await touch(0, base, false)
	await frames(2)
	check(tc.fire_ready < 1.0, "El botón RED muestra la recarga (%.2f)" % tc.fire_ready)

	# --- Auto-apuntado ---
	hunter.net_cooldown_left = 0.0
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	var target: Ghost = null
	for g in ghosts:
		if (g as Ghost).state == Ghost.State.FREE and g.name == "GhostIluminado":
			target = g
	check(target != null, "Hay un Ghost iluminado para apuntar")
	var found_spot := false
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		hunter.global_position = target.global_position + dir * 4.0
		hunter.velocity = Vector3.ZERO
		face(hunter, target.global_position)
		await frames(3)
		if hunter.vision.can_see(target):
			found_spot = true
			break
	check(found_spot, "Hunter colocado viendo al Ghost a 4 m")
	var pi_input: PlayerInput = s._player_input
	await frames(2)
	check(pi_input.aim_target == target, "El auto-apuntado fija al Ghost visible")
	check(hunter.intent.has_aim and AIController.flat_distance(hunter.intent.aim_point, target.global_position) < 0.5, "El punto de mira está sobre el Ghost")
	await touch(1, tc._fire_center(), true)
	await touch(1, tc._fire_center(), false)
	var netted := false
	for i in 60:
		await frames(1)
		if target.state == Ghost.State.NETTED:
			netted = true
			break
	check(netted, "Disparar con auto-apuntado atrapa al Ghost")
	await frames(3)
	check(pi_input.aim_target == null, "Un Ghost atrapado deja de estar fijado")

	# Ghost a la espalda: no se fija.
	target.state = Ghost.State.FREE
	face(hunter, hunter.global_position * 2.0 - target.global_position)
	pi_input.aim_target = null
	await frames(3)
	check(pi_input.aim_target != target, "Un Ghost a la espalda no se fija")

	# --- Captura con el botón de acción (mantener) ---
	target.apply_net()
	hunter.global_position = target.global_position + (hunter.global_position - target.global_position).normalized() * 1.0
	await frames(3)
	check(tc.action_text == "CAPTURAR" and tc.action_hold, "Junto a un Ghost atrapado: botón CAPTURAR (mantén)")
	await touch(2, tc._action_center(), true)
	var captured := false
	for i in 150:
		await frames(1)
		if target.state == Ghost.State.CAPTURED:
			captured = true
			break
		if i == 30:
			check(tc.action_progress > 0.0, "El botón muestra el progreso de la captura (%.2f)" % tc.action_progress)
	await touch(2, tc._action_center(), false)
	check(captured, "Mantener el botón de acción captura al Ghost")

	# --- Puerta con el botón de acción ---
	var door: Door = null
	for d in get_tree().get_nodes_in_group("doors"):
		for offset in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			hunter.global_position = Vector3(d.global_position.x, hunter.global_position.y, d.global_position.z) + offset
			await frames(2)
			if hunter.find_interactable() == d:
				door = d
				break
		if door:
			break
	check(door != null, "Hunter junto a una puerta")
	if door:
		await frames(2)
		check(tc.action_text != "" and not tc.action_hold, "Botón de acción con texto: %s" % tc.action_text)
		var was_open := door.is_open
		await touch(2, tc._action_center(), true)
		await touch(2, tc._action_center(), false)
		await frames(40)
		check(door.is_open != was_open, "Tocar el botón de acción abre/cierra la puerta")

	# --- Botón Cambiar (Tab) ---
	var before := s.get_controlled_character()
	(tc._scenario_bar.get_child(0) as Button).pressed.emit()
	await frames(3)
	check(s.get_controlled_character() != before, "Botón Cambiar pasa el control a otro personaje")
	check(not tc.show_fire, "Controlando un Ghost no hay botón RED")

	# --- Desactivar el modo táctil ---
	cfg.touch_controls_on_pc = false
	await frames(2)
	check(not tc.visible, "Sin modo táctil los controles se ocultan")
	s.queue_free()
	await frames(3)

	# --- Partida: sin botones de escenario ---
	cfg.touch_controls_on_pc = true
	GameManager.selected_role = DummySpawn.Role.HUNTER
	PlaytestLogger.path = "user://_test_playtests.csv"
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(not m._hud.touch._scenario_bar.visible, "En partida no aparecen Cambiar/Espectador/Reiniciar")
	check(not m._hud.touch.controls_enabled, "Durante la preparación (Hunter congelado) no hay joystick")
	m.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
