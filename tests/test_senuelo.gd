extends Node
## Señuelo de la Presa: se deja con el botón, cada toque lanza pasos falsos en su sitio (ruido
## que oye la IA del Cazador), tiene recarga, mantener lo mueve, no tiene colisión, solo lo ve
## su dueño y desaparece al ser capturada.

var failures := 0
var noises: Array = []


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"
	get_tree().create_timer(60.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	GameManager.noise_made.connect(func(at: Vector3, radius: float, source: Node) -> void: noises.append([at, radius, source]))
	await run()
	Input.action_release("decoy")
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func place(c: CharacterBase, at: Vector3) -> void:
	c.global_position = Vector3(at.x, c.global_position.y, at.z)
	c.velocity = Vector3.ZERO


## Un punto de la habitación sin muebles ni paredes (a min_distance de avoid, si se indica).
func free_spot(room: Room, avoid: Vector3 = Vector3.INF, min_distance: float = 0.0) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 3  # Lo mismo con lo que chocan los personajes (sin contarlos a ellos).
	var exclude: Array[RID] = []
	for c in get_tree().get_nodes_in_group("ghosts") + get_tree().get_nodes_in_group("hunters"):
		exclude.append((c as CollisionObject3D).get_rid())
	query.exclude = exclude
	for r in range(0, 8):
		for k in 12:
			var angle := k * TAU / 12.0
			var p := room.global_position + Vector3(cos(angle), 0, sin(angle)) * r * 0.5
			if not room.contains_point(p) or (avoid != Vector3.INF and Vector2(p.x - avoid.x, p.z - avoid.z).length() < min_distance):
				continue
			# La colisión de la casa es una malla: una cápsula metida del todo dentro de un mueble
			# no toca ningún triángulo. El rayo hacia abajo tiene que llegar al suelo.
			var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p + Vector3(0, -1, 0), 3, exclude)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or (hit["position"] as Vector3).y > room.global_position.y + 0.2:
				continue
			query.transform = Transform3D(Basis(), p + Vector3(0, 0.8, 0))
			if space.intersect_shape(query, 1).is_empty():
				return p
	return room.global_position


func tap() -> void:
	Input.action_press("decoy")
	await frames(2)
	Input.action_release("decoy")
	await frames(2)


func run() -> void:
	var cfg := GameManager.config
	cfg.prep_time = 0.5
	cfg.match_duration = 60.0
	GameManager.selected_role = DummySpawn.Role.GHOST
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	var me := m.get_controlled_character() as Ghost
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	await frames(40)  # Fin de la preparación.
	if me.state == Ghost.State.HIDDEN:
		me.exit_hiding()
	hunter.frozen = true
	# Las otras Presas (IA) quietas: sus pasos también los oiría el Cazador.
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g != me:
			(g as Ghost).frozen = true
	await frames(2)
	check(not me.has_decoy() and m._hud.touch.show_decoy, "Al empezar no hay señuelo, pero sí su botón")

	var sala: Room = m.get_node("House/Rooms/Sala")
	var cocina: Room = m.get_node("House/Rooms/Cocina")
	# Dejarlo (en el centro de la Sala).
	place(me, free_spot(sala))
	place(hunter, free_spot(cocina))
	await frames(3)
	var spot := me.global_position
	await tap()
	check(me.has_decoy() and me.decoy_position.distance_to(spot) < 0.5, "Pulsar deja el señuelo a tus pies")
	var decoy: Decoy = me._decoy
	check(decoy != null and decoy.is_inside_tree() and decoy.visible, "Se ve la pelotita (eres su dueña)")
	check(decoy.find_children("*", "CollisionObject3D", true, false).is_empty() and decoy.find_children("*", "CollisionShape3D", true, false).is_empty(), "El señuelo no tiene colisión")
	check(noises.filter(func(n): return n[2] == me).is_empty(), "Dejarlo no hace ruido")

	# Alejarse y lanzar los pasos (el Cazador IA, cerca del señuelo, debe oírlos).
	place(me, free_spot(cocina))
	# Cazador en la Sala, a unos metros del señuelo: dentro del radio de los pasos.
	place(hunter, free_spot(sala, spot, 2.5))
	await frames(3)
	# Solo el oído de la IA: sin su "cerebro", el ruido oído no se gasta al reaccionar.
	var hunter_ai: AIController = null
	for node in hunter.get_children():
		if node is AIController:
			hunter_ai = node
	hunter.controller = null
	if hunter_ai:
		hunter_ai.forget_noise()
	noises.clear()
	await tap()
	await frames(int(cfg.decoy_steps * cfg.decoy_step_interval * 60.0) + 10)
	var steps := noises.filter(func(n): return n[2] == me)
	check(steps.size() == cfg.decoy_steps, "Toque: %d pasos falsos (%d)" % [cfg.decoy_steps, steps.size()])
	check(steps.all(func(n): return (n[0] as Vector3).distance_to(me.decoy_position) < 0.6), "Los pasos suenan en el señuelo, no donde estás")
	check(me.decoy_cooldown_left > 0.0, "Después tiene recarga (%.1f s)" % me.decoy_cooldown_left)
	var heard: Dictionary = hunter_ai.recent_noise() if hunter_ai else {}
	check(not heard.is_empty() and AIController.flat_distance(heard["position"], me.decoy_position) <= cfg.noise_position_error + 0.5, "La IA del Cazador oye los pasos falsos en el señuelo (%s)" % [heard])
	hunter.controller = hunter_ai

	noises.clear()
	await tap()
	await frames(30)
	check(noises.filter(func(n): return n[2] == me).is_empty(), "Durante la recarga no hace nada")

	# Mantener: lo mueve a donde estás.
	var old := me.decoy_position
	Input.action_press("decoy")
	await frames(int(cfg.decoy_move_hold * 60.0) + 6)
	Input.action_release("decoy")
	await frames(2)
	check(me.decoy_position.distance_to(me.global_position) < 0.5 and me.decoy_position.distance_to(old) > 3.0, "Mantener mueve el señuelo a donde estás (señuelo %s, tú %s, estado %d)" % [me.decoy_position, me.global_position, me.state])

	# Capturada: el señuelo desaparece.
	me.apply_net()
	me.capture()
	await frames(2)
	check(not me.has_decoy() and (not is_instance_valid(decoy) or decoy.is_queued_for_deletion()), "Al ser capturada el señuelo desaparece")
	m.queue_free()
	await frames(3)

	# Jugando de Cazador no se ve el señuelo de una Presa.
	GameManager.selected_role = DummySpawn.Role.HUNTER
	GameManager.series = null
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	var prey: Ghost = get_tree().get_nodes_in_group("ghosts")[0]
	if prey.state == Ghost.State.HIDDEN:
		prey.exit_hiding()
	prey.place_decoy()
	await frames(2)
	check(prey.has_decoy() and not prey._decoy.visible, "El Cazador no ve el señuelo")
	check(not m._hud.touch.show_decoy, "El Cazador no tiene botón de señuelo")
