extends Node
## Partida de 4 con puntos individuales: rotación de Cazador, puntos y tiempo, minidesempate entre
## los empatados (relleno de IA y espectadores), votación, y el flujo real entre rondas
## (pantalla de resultados, CSV).

var failures := 0
const H := DummySpawn.Role.HUNTER
const G := DummySpawn.Role.GHOST
const D := 100.0  # Duración de ronda en estas pruebas.


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


func four() -> MatchSeries:
	return MatchSeries.new([{"name": "A", "peer": 1}, {"name": "B", "peer": 7}, {"name": "C", "peer": 0}, {"name": "D", "peer": 0}])


## Juega una ronda: captured = {participante: segundo de captura}; el resto sobrevive.
func play(s: MatchSeries, captured: Dictionary) -> void:
	var outcome := {}
	for i in s.current_prey():
		outcome[i] = captured.get(i, -1.0)
	s.record_round(outcome, D)


func rules() -> void:
	var solo := MatchSeries.solo("Yo", true)
	check(solo.participants.size() == 4 and solo.current_hunter() == 0 and solo.peer_of(0) == 1, "Solo empezando de Cazador: eres Cazador en la ronda 1")
	solo = MatchSeries.solo("Yo", false)
	check(solo.index_of_peer(1) == 3 and solo.current_hunter() != 3, "Solo empezando de Presa: eres Cazador en la última ronda")

	var s := four()
	check(s.current_hunter() == 0 and s.current_prey() == [1, 2, 3] and s.filler_count() == 0, "Ronda 1: A caza a B, C y D")
	play(s, {1: 30.0, 2: 60.0})  # A atrapa a B y C; D sobrevive.
	check(s.points == [2, 0, 0, 1], "A +2 (dos capturas), D +1 (sobrevive): %s" % [s.points])
	check(is_equal_approx(s.times[0], 70.0 + 40.0) and is_equal_approx(s.times[1], 30.0) and is_equal_approx(s.times[3], D), "Tiempos: al Cazador le sobraban 70+40 s; B duró 30 s; D toda la ronda")
	check(s.round_label() == "Ronda 2 de 4" and s.current_hunter() == 1, "Ronda 2: caza B")
	play(s, {})  # Nadie atrapado: A, C, D +1.
	play(s, {0: 10.0, 1: 10.0, 3: 10.0})  # C atrapa a todos.
	play(s, {})  # D no atrapa a nadie.
	# A: 2+1+0+1 = 4; B: 0+0+0+1 = 1; C: 0+1+3+1 = 5; D: 1+1+0+0 = 2.
	check(s.points == [4, 1, 5, 2], "Puntos tras 4 rondas: %s" % [s.points])
	check(s.is_over() and s.winners == [2] and s.result_code_for(1) == "gana_ia", "Gana C sin desempate (A pierde)")
	check(s.standings() == [2, 0, 3, 1], "Clasificación por puntos")

	# Empate a puntos -> decide el tiempo.
	s = four()
	play(s, {1: 50.0, 2: 50.0, 3: 50.0})  # A 3 pts.
	play(s, {0: 20.0, 2: 50.0, 3: 50.0})  # B 3 pts.
	play(s, {0: 90.0, 1: 90.0, 3: 90.0})  # C 3 pts, capturas tardías (menos tiempo para C).
	play(s, {0: 90.0, 1: 90.0, 2: 90.0})  # D 3 pts.
	check(s.points == [3, 3, 3, 3], "Empate a 3 puntos")
	check(s.is_over() and s.winners.size() == 1, "El tiempo deshace el empate a puntos")

	# Empate exacto (puntos y tiempo) entre A y B -> minidesempate solo entre ellos.
	s = four()
	play(s, {})  # A 0; B, C, D +1.
	play(s, {})  # B 0; A, C, D +1.
	play(s, {0: 0.0, 1: 0.0, 3: 0.0})  # C atrapa a A, B y D al instante: C +3.
	play(s, {0: 0.0, 1: 0.0, 2: 0.0})  # D +3.
	# A: 0+1+0+0 = 1, B: 1+0+0+0 = 1, C: 1+1+3+0 = 5, D: 1+1+0+3 = 5. C y D: mismos tiempos.
	check(s.points == [1, 1, 5, 5] and s.status == MatchSeries.Status.PLAYING and s.is_tiebreak(), "C y D empatados en puntos y tiempo: desempate")
	check(s.contenders == [2, 3] and s.current_hunter() == 2 and s.current_prey() == [3] and s.filler_count() == 2, "Desempate: C caza a D + 2 Presas de relleno")
	check(s.spectators() == [0, 1] and not s.is_playing(0), "A y B miran")
	check(s.round_label() == "Desempate 1 · ronda 1 de 2", "Etiqueta del desempate: %s" % s.round_label())
	var data := s.to_dict()
	var copy := MatchSeries.from_dict(data)
	check(copy.contenders == s.contenders and copy.points == s.points and copy.current_hunter() == 2 and copy.last_round["gained"].has(3), "to_dict / from_dict conserva la partida")
	play(s, {3: 40.0})  # C atrapa a D.
	play(s, {2: 40.0})  # D atrapa a C a la misma velocidad.
	check(s.status == MatchSeries.Status.TIE_VOTE and s.winners == [2, 3], "Siguen empatados tras el desempate: votación")
	check(s.points == [1, 1, 5, 5], "El desempate no cambia la clasificación general")
	s.continue_tiebreak()
	check(s.status == MatchSeries.Status.PLAYING and s.stage == 2 and s.current_hunter() == 2 and s.stage_points[2] == 0, "Votar desempatar: otro minidesempate desde cero")
	play(s, {})  # D sobrevive: +1.
	play(s, {})  # C sobrevive: +1.
	check(s.status == MatchSeries.Status.TIE_VOTE, "Otro empate: otra votación")
	s.declare_draw()
	check(s.is_over() and s.is_draw() and s.winners == [2, 3], "Votar terminar: empate entre C y D")

	# Desempate ganado.
	s = four()
	play(s, {})
	play(s, {})
	play(s, {0: 0.0, 1: 0.0, 3: 0.0})
	play(s, {0: 0.0, 1: 0.0, 2: 0.0})
	play(s, {3: 40.0})  # C atrapa a D.
	play(s, {})  # D no atrapa a C.
	check(s.is_over() and s.winners == [2], "C gana el desempate")

	# Un jugador se va: la IA ocupa su puesto.
	s = four()
	s.replace_with_ai(1)
	check(not s.is_human(1) and s.participant_name(1) == "B (IA)" and s.index_of_peer(7) == -1, "Jugador que se va -> IA con su nombre y puntos")


func flow() -> void:
	var cfg := GameManager.config
	cfg.prep_time = 0.3
	var old_duration := cfg.match_duration
	cfg.match_duration = D
	GameManager.series = MatchSeries.solo("Yo", true)
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(m.round_number == 1 and m.series == GameManager.series and m.player_role == H, "Ronda 1: eres el Cazador")
	check(get_tree().get_nodes_in_group("hunters").size() == 1 and get_tree().get_nodes_in_group("ghosts").size() == 3, "1 Cazador y 3 Presas")
	check(m._hud._round_label.text.begins_with("Ronda 1 de 4"), "El HUD muestra la ronda: %s" % m._hud._round_label.text)
	var labels := []
	for node in get_tree().get_nodes_in_group("ghosts"):
		labels.append((node as Ghost).display_name)
	check("IA 1" in labels and "IA 3" in labels, "Las Presas llevan el nombre de su participante: %s" % [labels])
	# Captura de IA 1 durante la caza.
	await frames(30)
	var victim: Ghost = null
	for node in get_tree().get_nodes_in_group("ghosts"):
		if (node as Ghost).display_name == "IA 1":
			victim = node
	victim.state = Ghost.State.NETTED
	victim.capture()
	m._end(G)  # Se acaba el tiempo con 2 libres.
	await frames(2)
	var rs := m._result_screen
	check(m.series.points[0] == 1 and m.series.points[1] == 0 and m.series.points[2] == 1, "Puntos: tú +1 (captura), IA 1 0, IA 2 +1: %s" % [m.series.points])
	check(rs._subtitle.text.begins_with("Has atrapado 1 de 3"), "Subtítulo: %s" % rs._subtitle.text)
	check(rs.primary_choice == "next" and not rs._questionnaire.visible, "Tras la ronda 1: Siguiente ronda, sin cuestionario")
	check(rs._table.text.contains("► Yo") and rs._series.text.contains("Cazador: IA 1"), "Clasificación y siguiente Cazador: %s" % rs._series.text.replace("\n", " | "))
	m._log_match(false)
	m.queue_free()
	await frames(3)

	# Ronda 2: eres Presa.
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(m.round_number == 2 and m.player_role == G and m.get_controlled_character() is Ghost, "Ronda 2: eres Presa")
	check(m.description.contains("Cazador: IA 1"), "La intro dice quién caza")
	m._end(G)
	await frames(2)
	check(m._result_screen._subtitle.text.contains("sobrevivido"), "Sobrevives: +1")
	m._log_match(false)
	m.queue_free()
	await frames(3)

	# Minidesempate en el que no juegas: espectador con cambio de cámara.
	var s := MatchSeries.solo("Yo", true)
	play(s, {})
	play(s, {})
	play(s, {0: 0.0, 1: 0.0, 3: 0.0})
	play(s, {0: 0.0, 1: 0.0, 2: 0.0})
	GameManager.series = s
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check(m.player_role == MatchScenario.ROLE_SPECTATOR and m.get_controlled_character() == null, "Desempate entre IA 2 e IA 3: miras")
	check(get_tree().get_nodes_in_group("ghosts").size() == 3 and m._count_free_scoring() == 1, "1 Presa que puntúa + 2 de relleno")
	check(m._can_switch_camera() and m._hud.camera_button, "Botón de cambiar cámara")
	var watched := m._watched
	var ev := InputEventAction.new()
	ev.action = "switch_character"
	ev.pressed = true
	m._unhandled_input(ev)
	check(m._watched != watched and m.get_controlled_character() == null, "Tab cambia a quién miras")
	# Atrapar a una de relleno no termina la ronda.
	for node in get_tree().get_nodes_in_group("ghosts"):
		if (node as Ghost).display_name.begins_with("Relleno"):
			(node as Ghost).state = Ghost.State.NETTED
			(node as Ghost).capture()
			break
	await frames(30)
	check(m.phase != MatchScenario.Phase.ENDED, "Capturar una Presa de relleno no termina la ronda")
	m._end(H)
	await frames(2)
	check(s.stage_round == 1 and s.stage_points[2] == 0 and s.stage_points[3] == 1, "La captura de relleno no da puntos (la Presa que sobrevive, sí)")
	m.queue_free()
	await frames(3)

	# Votación y final con cuestionario (sin red: tú decides).
	s = MatchSeries.solo("Yo", true)
	play(s, {})
	play(s, {})
	play(s, {0: 0.0, 1: 0.0, 3: 0.0})
	play(s, {0: 0.0, 1: 0.0, 2: 0.0})
	play(s, {3: 40.0})
	GameManager.series = s
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	# Forzar que IA 3 atrape a IA 2 a los 40 s: empate exacto -> votación.
	m._capture_times[2] = 40.0
	m._end(H)
	await frames(2)
	check(m._result_screen.primary_choice == "tiebreak", "Empate tras el desempate: botones de votación (%s, %s, %s)" % [s.status, s.stage_points, s.stage_times])
	m._on_choice("draw")
	await frames(2)
	check(s.is_draw() and m._result_screen.primary_choice == "new" and m._result_screen._questionnaire.visible and m._result_screen._series.text.begins_with("EMPATE"), "Terminar en empate: resultado final y cuestionario")
	m._rating = 4
	m._log_match(true)
	var rows := PlaytestLogger.read_rows()
	var last: Dictionary = rows[-1]
	check(last.get("rol_jugador") == "espectador" and last.get("resultado_serie") == "gana_ia" and last.get("jugar_otra") == "si" and last.get("modo") == "solo", "CSV: espectador, no ganas, jugar otra sí, modo solo")
	check(rows[0].get("jugar_otra") == "" and rows[0].get("resultado_serie") == "" and rows[0].get("puntos") == "1", "CSV: la ronda 1 sin resultado final y con tus puntos")
	cfg.prep_time = 8.0
	cfg.match_duration = old_duration
