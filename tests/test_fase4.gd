extends Node
## Prueba de la Fase 4: menú, partida completa en ambos bandos y registro CSV.

var failures := 0
var csv_backup = null


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func clear() -> void:
	for c in get_children():
		c.queue_free()
	await frames(3)


func start_match(role: int) -> MatchScenario:
	await clear()
	GameManager.selected_role = role
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(3)
	return m


func player_ghost() -> Ghost:
	for g in get_tree().get_nodes_in_group("ghosts"):
		if (g as Ghost).is_player_controlled:
			return g
	return null


func csv_lines() -> PackedStringArray:
	if not FileAccess.file_exists(PlaytestLogger.path):
		return PackedStringArray()
	return FileAccess.get_file_as_string(PlaytestLogger.path).strip_edges().split("\n")


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"  # Nunca tocar los datos reales.
	if FileAccess.file_exists(PlaytestLogger.path):
		csv_backup = FileAccess.get_file_as_string(PlaytestLogger.path)
		DirAccess.remove_absolute(PlaytestLogger.path)
	await run()
	await clear()
	# Restaurar el CSV del usuario.
	DirAccess.remove_absolute(PlaytestLogger.path)
	if csv_backup != null:
		var f := FileAccess.open(PlaytestLogger.path, FileAccess.WRITE)
		f.store_string(csv_backup)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	var cfg := GameManager.config
	cfg.prep_time = 1.0
	cfg.match_duration = 4.0

	# Menú
	var menu: Control = load("res://scenes/main/MainMenu.tscn").instantiate()
	add_child(menu)
	await frames(2)
	var buttons := menu.find_children("*", "Button", true, false)
	check(buttons.size() >= 7, "Menú con sus botones (%d)" % buttons.size())
	var visible_buttons := buttons.filter(func(b): return b.is_visible_in_tree())
	check(menu.current_page() == "inicio" and visible_buttons.size() <= 5, "El inicio solo enseña lo principal (%d botones)" % visible_buttons.size())
	menu._show("pruebas")
	check(menu.go_back() and menu.current_page() == "mas" and menu.go_back() and menu.current_page() == "inicio", "Volver sube de nivel en el menú")
	check(not menu.go_back(), "En el inicio no hay más atrás")
	menu.queue_free()
	var lobby: Control = load("res://scenes/main/Lobby.tscn").instantiate()
	add_child(lobby)
	await frames(2)
	check(lobby.current_page() == "elegir", "Multijugador empieza eligiendo modo")
	lobby._show_page("online")
	check(lobby.go_back() and lobby.current_page() == "elegir" and not lobby.go_back(), "Volver desde Por internet")
	lobby.queue_free()
	await frames(2)

	# ---- Partida como Hunter: gana capturando a todos ----
	var m := await start_match(DummySpawn.Role.HUNTER)
	var hunters := get_tree().get_nodes_in_group("hunters")
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	check(hunters.size() == 1 and ghosts.size() == 3, "Cazador vs 3 Presas")
	var hunter: Hunter = hunters[0]
	check(m.phase == MatchScenario.Phase.PREP and hunter.frozen, "Preparación: Hunter congelado")
	check(m._hud._blackout.visible, "Preparación: pantalla negra para el Hunter")
	await frames(70)
	check(m.phase == MatchScenario.Phase.PLAYING and not hunter.frozen and not m._hud._blackout.visible, "Tras la preparación empieza la caza")
	hunter.fire_net()
	for g in ghosts:
		var ghost := g as Ghost
		if ghost.state == Ghost.State.HIDDEN:
			ghost.expel_from_hiding()
		ghost.apply_net()
		ghost.capture()
	await frames(3)
	check(m.phase == MatchScenario.Phase.ENDED and m.winner_role == DummySpawn.Role.HUNTER, "Capturar a todos -> gana el Hunter")
	check(m._result_screen != null and m._result_screen.visible, "Se muestra la pantalla de resultados")
	check(hunter.frozen, "Al terminar, todos congelados")
	m._rating = 4
	m._log_match(true)
	var lines := csv_lines()
	check(lines.size() == 2 and lines[0].begins_with("fecha,rol_jugador,ganador"), "CSV con cabecera y una fila")
	check(lines.size() == 2 and ",hunter,hunter," in lines[1] and lines[1].contains(",4,,normal,"), "Fila: rol hunter, gana hunter, diversión 4 (ronda intermedia: sin jugar otra)")
	check(lines.size() == 2 and lines[1].split(",")[6] == "1" and lines[1].split(",")[7] == "3", "Fila: 1 red disparada, 3 acertadas (%s)" % (lines[1] if lines.size() == 2 else ""))

	# ---- Partida como Ghost: gana si se acaba el tiempo ----
	m = await start_match(DummySpawn.Role.GHOST)
	ghosts = get_tree().get_nodes_in_group("ghosts")
	hunters = get_tree().get_nodes_in_group("hunters")
	check(ghosts.size() == 3 and hunters.size() == 1, "Presa (con 2 Presas IA) vs 1 Cazador")
	var ghost: Ghost = player_ghost()
	check(ghost.is_player_controlled and not hunters[0].is_player_controlled, "El jugador es el Ghost")
	check(not m._hud._blackout.visible, "Jugando como Ghost no hay pantalla negra")
	ghost.enter_hiding(get_tree().get_nodes_in_group("hiding_spots")[2])
	await frames(320)
	check(m.phase == MatchScenario.Phase.ENDED and m.winner_role == DummySpawn.Role.GHOST, "Se acaba el tiempo con el Ghost libre -> ganan los Ghosts")
	check(m._stats["tiempo_escondido_s"] > 3.0, "Cuenta el tiempo escondido (%.1f s)" % m._stats["tiempo_escondido_s"])

	# ---- Partida como Ghost: el maniquí Hunter atrapa y captura ----
	cfg.match_duration = 30.0
	# Puntería perfecta: con el error aleatorio de la IA la prueba fallaba ~1 de cada 6 veces.
	var aim_error := cfg.ai_aim_error
	cfg.ai_aim_error = 0.0
	m = await start_match(DummySpawn.Role.GHOST)
	ghost = player_ghost()
	hunter = get_tree().get_nodes_in_group("hunters")[0]
	await frames(65)
	# Las otras dos Presas (IA) ya están capturadas: solo queda la del jugador.
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g != ghost:
			if (g as Ghost).state == Ghost.State.HIDDEN:
				(g as Ghost).expel_from_hiding()
			(g as Ghost).state = Ghost.State.NETTED
			(g as Ghost).capture()
	# Delante del Hunter, a 4 m, en el pasillo.
	var forward := -hunter.global_basis.z
	ghost.global_position = hunter.global_position + Vector3(forward.x, 0, forward.z).normalized() * 4.0
	var ended := false
	for i in 600:
		await frames(1)
		if m.phase == MatchScenario.Phase.ENDED:
			ended = true
			break
	cfg.ai_aim_error = aim_error
	check(ended and m.winner_role == DummySpawn.Role.HUNTER, "El Hunter maniquí dispara, se acerca y captura -> gana el Hunter (estado ghost=%d)" % ghost.state)

	await clear()
	lines = csv_lines()
	check(lines.size() == 4, "Salir de cada partida deja una fila en el CSV (%d filas)" % (lines.size() - 1))
	cfg.prep_time = 8.0
	cfg.match_duration = 180.0
