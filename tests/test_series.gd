extends Node
## Serie de rondas: 4 rondas con cambio de bando en la 3, primero a 3, desempate por parejas,
## votación al empatar, y el flujo real entre rondas (pantalla de resultados, CSV).

var failures := 0
const H := DummySpawn.Role.HUNTER
const G := DummySpawn.Role.GHOST


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"
	DirAccess.remove_absolute(PlaytestLogger.path)
	get_tree().create_timer(90.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	rules()
	await flow()
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	GameManager.series = null
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func play(series: MatchSeries, wins: Array) -> void:
	for w in wins:
		series.record(w)


func rules() -> void:
	var s := MatchSeries.new(H)
	check([1, 2, 3, 4].map(func(n): return s.role_for_round(n)) == [H, H, G, G], "Rondas 1-2 con tu bando, 3-4 cambiado")
	check([5, 6, 7, 8].map(func(n): return s.role_for_round(n)) == [H, G, H, G], "Desempates: una ronda con cada bando")
	check(MatchSeries.new(G).role_for_round(3) == H, "Empezando como Presa, en la ronda 3 eres Cazador")

	s = MatchSeries.new(H)
	play(s, [true, true, true])
	check(s.status == MatchSeries.Status.PLAYER_WINS and s.results.size() == 3, "3-0: ganas en la ronda 3 sin jugar la 4")

	s = MatchSeries.new(H)
	play(s, [true, false, false, false])
	check(s.status == MatchSeries.Status.AI_WINS, "1-3: gana la IA")

	s = MatchSeries.new(H)
	play(s, [true, false, true])
	check(s.status == MatchSeries.Status.PLAYING and s.current_round() == 4, "2-1 tras la ronda 3: se juega la 4")
	s.record(false)
	check(s.status == MatchSeries.Status.PLAYING and s.current_round() == 5 and s.is_tiebreak_round(5), "2-2: desempate (ronda 5)")
	s.record(true)
	check(s.status == MatchSeries.Status.PLAYING and s.current_round() == 6, "3-2 en el desempate: se juega la otra ronda de la pareja")
	s.record(true)
	check(s.status == MatchSeries.Status.PLAYER_WINS, "4-2 tras la pareja de desempate: ganas")

	s = MatchSeries.new(H)
	play(s, [true, true, false, false, true, false])
	check(s.status == MatchSeries.Status.TIE_VOTE, "3-3 tras el desempate: votación")
	s.continue_tiebreak()
	check(s.status == MatchSeries.Status.PLAYING and s.current_round() == 7 and s.current_role() == H, "Votar desempatar: ronda 7 (con tu bando inicial)")
	play(s, [false, true])
	check(s.status == MatchSeries.Status.TIE_VOTE, "4-4: otra votación")
	s.declare_draw()
	check(s.status == MatchSeries.Status.DRAW and s.is_over() and s.result_code() == "empate", "Votar terminar: empate")


func flow() -> void:
	var cfg := GameManager.config
	cfg.prep_time = 0.3
	GameManager.series = MatchSeries.new(H)
	GameManager.selected_role = H
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(m.round_number == 1 and m.series == GameManager.series, "La ronda usa la serie en curso")
	check(m._hud._round_label.text.begins_with("Ronda 1 de 4"), "El HUD muestra la ronda: %s" % m._hud._round_label.text)
	m._end(H)
	await frames(2)
	var rs := m._result_screen
	check(rs.primary_choice == "next" and not rs._questionnaire.visible, "Tras la ronda 1: botón Siguiente ronda, sin cuestionario")
	check(rs._series.text.contains("Tú 1 – 0 IA"), "Marcador en resultados: %s" % rs._series.text.replace("\n", " | "))

	# Simular las rondas 2 y 3 sin recargar escenas: el jugador las pierde.
	GameManager.series.record(false)
	GameManager.series.record(false)
	m._log_match(false)
	m.queue_free()
	await frames(3)
	GameManager.selected_role = GameManager.series.current_role()
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(m.round_number == 4 and m.player_role == G, "Ronda 4: juegas como Presa (bando cambiado)")
	check(m.description.contains("Cambio de bando") == false and m.description.contains("RONDA 4 DE 4"), "Intro de la ronda 4")
	m._end(H)  # Gana el Cazador (IA): 1-3.
	await frames(2)
	rs = m._result_screen
	check(GameManager.series.status == MatchSeries.Status.AI_WINS, "1-3: la IA gana la partida")
	check(rs.primary_choice == "new" and rs._questionnaire.visible, "Fin de la partida: Nueva partida y cuestionario")
	m._rating = 4
	m._log_match(true)
	var rows := PlaytestLogger.read_rows()
	var last: Dictionary = rows[-1]
	check(last.get("ronda") == "4" and last.get("marcador") == "1-3" and last.get("resultado_serie") == "gana_ia" and last.get("jugar_otra") == "si", "CSV: ronda 4, 1-3, gana_ia, jugar otra sí")
	check(rows[0].get("jugar_otra") == "" and rows[0].get("resultado_serie") == "", "CSV: la ronda intermedia no tiene 'jugar otra' ni resultado de serie")
	m.queue_free()
	await frames(3)

	# Votación de empate en la pantalla de resultados.
	var s := MatchSeries.new(H)
	play(s, [true, true, false, false, true])
	GameManager.series = s
	GameManager.selected_role = s.current_role()
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(m.round_number == 6 and m.player_role == G, "Ronda 6 (desempate) como Presa")
	m._end(H)  # Pierde la Presa del jugador: 3-3.
	await frames(2)
	check(m._result_screen.primary_choice == "tiebreak", "3-3: pantalla de votación (Desempatar / Terminar en empate)")
	m._on_choice("draw")
	await frames(2)
	check(s.status == MatchSeries.Status.DRAW and m._result_screen.primary_choice == "new" and m._result_screen._series.text.begins_with("EMPATE"), "Terminar en empate muestra el resultado final")
	cfg.prep_time = 8.0
