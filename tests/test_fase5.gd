extends Node
## Prueba de la Fase 5: IA conectada en partida y escenarios, navegación lista, control con P/Tab.

var failures := 0
var csv_backup = null


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func load_scene(path: String) -> Node:
	for c in get_children():
		c.queue_free()
	await frames(3)
	var s: Node = load(path).instantiate()
	add_child(s)
	await frames(3)
	return s


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"  # Nunca tocar los datos reales.
	if FileAccess.file_exists(PlaytestLogger.path):
		csv_backup = FileAccess.get_file_as_string(PlaytestLogger.path)
	await run()
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	if csv_backup != null:
		FileAccess.open(PlaytestLogger.path, FileAccess.WRITE).store_string(csv_backup)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	# Partida como Hunter: Ghosts con IA.
	GameManager.selected_role = DummySpawn.Role.HUNTER
	GameManager.series = null
	var m := await load_scene("res://scenes/game/Match.tscn")
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	check(ghosts.all(func(g): return g.controller is GhostAI), "Partida como Hunter: los Ghosts los controla GhostAI")
	var house: House = m.get_node("House")
	if not house.nav_ready:
		await house.navigation_ready
	check(house.nav_ready, "Navegación lista en la partida")
	var start := (ghosts[0] as Node3D).global_position
	await frames(240)
	check((ghosts[0] as Node3D).global_position.distance_to(start) > 1.0 or (ghosts[0] as Ghost).state == Ghost.State.HIDDEN,
		"Durante la preparación los Ghosts IA se mueven o se esconden")

	# Partida como Ghost: Hunter con IA.
	GameManager.selected_role = DummySpawn.Role.GHOST
	GameManager.series = null
	m = await load_scene("res://scenes/game/Match.tscn")
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	check(hunter.controller is HunterAI, "Partida como Ghost: el Hunter lo controla HunterAI")
	check(hunter.get_node("NameLabel").text.ends_with("IA"), "La etiqueta del Hunter dice IA")

	# TestAI: espectador, P toma el control, P lo devuelve a la IA.
	var s: TestScenario = await load_scene("res://scenes/test/TestAI.tscn")
	await frames(10)
	check(s.get_controlled_character() == null, "TestAI empieza en modo espectador")
	var chars := s.get_node("Characters").get_children().filter(func(c): return c is CharacterBase)
	check(chars.all(func(c): return c.controller is AIController), "TestAI: todos controlados por IA")
	var label: Label3D = chars[0].get_node("AIStateLabel")
	await frames(2)
	check(label.visible and label.text != "", "Etiqueta de estado de la IA visible (%s)" % label.text)
	await press("spectate")
	check(s.get_controlled_character() == chars[0] and chars[0].controller is PlayerInput, "P: tomar el control del personaje observado")
	await frames(2)
	check(not label.visible, "Con el jugador al mando se oculta la etiqueta de IA")
	await press("spectate")
	check(chars[0].controller is AIController, "P otra vez: el personaje vuelve a su IA")
	await press("switch_character")
	check(s._watched == 1, "Tab en espectador cambia de cámara")
