extends Node
## Prueba de la Fase 6: dificultad, cuestionario en el CSV, migración del CSV, resumen.

var failures := 0
var csv_backup = null


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"  # Nunca tocar los datos reales.
	get_tree().create_timer(60.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	if FileAccess.file_exists(PlaytestLogger.path):
		csv_backup = FileAccess.get_file_as_string(PlaytestLogger.path)
		DirAccess.remove_absolute(PlaytestLogger.path)
	await run()
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("_test_playtests_anterior_"):
			DirAccess.remove_absolute("user://" + f)
	if csv_backup != null:
		FileAccess.open(PlaytestLogger.path, FileAccess.WRITE).store_string(csv_backup)
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	var cfg := GameManager.config
	# Dificultad
	GameManager.set_difficulty(GameManager.Difficulty.EASY)
	check(cfg.ai_aim_error == 2.8 and cfg.ai_reaction_time == 1.2, "Fácil aplica su preset")
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	check(cfg.ai_aim_error == GameConfig.new().ai_aim_error and cfg.ai_reaction_time == GameConfig.new().ai_reaction_time, "Normal restaura los valores por defecto")
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	check(GameManager.get_difficulty_name() == "dificil", "Nombre de la dificultad")

	# Migración: un CSV con cabecera antigua se convierte conservando sus filas (y se guarda copia).
	FileAccess.open(PlaytestLogger.path, FileAccess.WRITE).store_string("fecha,rol_jugador,ganador,diversion_1a5\n2026,hunter,hunter,4\n")
	PlaytestLogger.append({"rol_jugador": "ghost", "ganador": "ghosts"})
	var archived := Array(DirAccess.get_files_at("user://")).filter(func(f): return f.begins_with("_test_playtests_anterior_"))
	check(archived.size() == 1, "Copia del CSV antiguo guardada")
	var rows := PlaytestLogger.read_rows()
	check(rows.size() == 2 and rows[0]["ganador"] == "hunter" and rows[0]["diversion_1a5"] == "4" and rows[0]["nota"] == "", "Fila antigua migrada al formato nuevo")
	check(rows.size() == 2 and rows[1]["ganador"] == "ghosts", "Fila nueva añadida tras la migración")
	DirAccess.remove_absolute(PlaytestLogger.path)

	# Partida terminada con cuestionario.
	cfg.prep_time = 0.5
	cfg.match_duration = 2.0
	GameManager.selected_role = DummySpawn.Role.GHOST
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(3)
	var ghost: Ghost = get_tree().get_nodes_in_group("ghosts")[0]
	ghost.enter_hiding(get_tree().get_nodes_in_group("hiding_spots")[0])
	await frames(200)
	check(m.phase == MatchScenario.Phase.ENDED, "Partida terminada")
	var rs := m._result_screen
	rs._on_rating(5)
	m._rating = 5
	for b in rs.find_children("*", "Button", true, false):
		if b.text in ["Sí", "Suerte"]:
			b.pressed.emit()
	rs._note.text = "me gustó esconderme, 1 2 3"
	# Escribir en la nota no debe disparar atajos (1-4 cambian de escena).
	rs._note.grab_focus()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_1
	key.keycode = KEY_1
	key.pressed = true
	Input.parse_input_event(key)
	await frames(3)
	check(is_instance_valid(m) and m.is_inside_tree(), "Escribir '1' en la nota no cambia de escenario")
	m._log_match(true)
	rows = PlaytestLogger.read_rows()
	check(rows.size() == 1, "Una fila registrada")
	if rows.size() == 1:
		var r: Dictionary = rows[0]
		check(r["diversion_1a5"] == "5" and r["tension"] == "si" and r["resultado_por"] == "suerte", "Cuestionario guardado (5, tensión sí, suerte)")
		check(r["nota"] == "me gustó esconderme  1 2 3" and r["dificultad"] == "dificil", "Nota (sin comas) y dificultad guardadas: '%s' / %s" % [r["nota"], r["dificultad"]])
	m.queue_free()
	await frames(3)
	cfg.prep_time = 8.0
	cfg.match_duration = 180.0

	# Resumen con datos sintéticos.
	var data: Array[Dictionary] = []
	for i in 6:
		data.append({"rol_jugador": "hunter", "ganador": "hunter" if i < 3 else "ghosts", "duracion_s": "100", "redes_disparadas": "10", "redes_acertadas": "3",
			"escapes_de_red": "1", "armarios_registrados": "1", "tiempo_escondido_s": "0", "puertas_usadas": "2", "luces_usadas": "0",
			"diversion_1a5": "4", "jugar_otra": "si", "tension": "si", "resultado_por": "decisiones", "nota": "nota %d" % i, "dificultad": "normal"})
	data.append({"rol_jugador": "ghost", "ganador": "abandonada"})
	var report: String = (load("res://scripts/ui/playtest_summary.gd") as GDScript).build_report(data)
	check(report.contains("Partidas terminadas: [b]6[/b] · abandonadas: 1"), "Resumen: cuenta terminadas y abandonadas")
	check(report.contains("Victorias del jugador: [b]50 %[/b]"), "Resumen: 50 % de victorias como Hunter")
	check(report.contains("Precisión de red (tu precisión): [b]30 %[/b]"), "Resumen: precisión 30 %")
	check(report.contains("Partidas en que se usan luces: [b]0 %[/b]"), "Resumen: luces sin usar (señal amarilla)")
	check(report.contains("JUGANDO COMO PRESA[/b]  (0 partidas)"), "Resumen: bando sin partidas")
	check(report.contains("nota 5"), "Resumen: últimas notas")
	var empty: String = (load("res://scripts/ui/playtest_summary.gd") as GDScript).build_report([] as Array[Dictionary])
	check(empty.begins_with("Todavía no hay partidas"), "Resumen vacío con instrucciones")
