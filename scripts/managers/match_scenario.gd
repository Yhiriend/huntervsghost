class_name MatchScenario
extends TestScenario
## Una ronda de la partida: espera a los jugadores -> preparación -> caza con temporizador -> resultados.
## Siempre 1 Cazador y 3 Presas. Quién es quién lo decide la partida (MatchSeries en
## GameManager.series): cada participante es Cazador una vez; en los minidesempates solo juegan
## los empatados, las Presas que faltan son IA de relleno (no puntúan) y el resto mira.
## La ronda termina cuando el Cazador atrapa a todas las Presas que puntúan o se acaba el tiempo.
##
## Red (Net): el anfitrión simula todo y envía a los clientes una foto del estado cada
## SNAPSHOT_EVERY frames, más eventos fiables (puertas, luces, estados de las Presas, redes, fin
## de ronda) y los sonidos y ruidos del mundo. Los clientes solo envían sus controles.
## Cada ronda se guarda en user://playtests.csv (PlaytestLogger) en cada dispositivo.

enum Phase { WAITING, PREP, PLAYING, ENDED }
enum NetRole { OFFLINE, HOST, CLIENT }

const ROLE_HUNTER := DummySpawn.Role.HUNTER
const ROLE_GHOST := DummySpawn.Role.GHOST
## Rol del jugador local cuando no juega la ronda (mira).
const ROLE_SPECTATOR := -1
## Probabilidad de que una habitación aleatoria empiece a oscuras.
const DARK_ROOM_CHANCE := 0.5
## Frames de física entre fotos del estado (60 / 2 = 30 por segundo).
const SNAPSHOT_EVERY := 2
## Segundos máximos esperando a que los clientes carguen la ronda.
const WAIT_TIMEOUT := 10.0
## Valores por personaje en la foto del estado.
const SNAPSHOT_STRIDE := 9
const SNAPSHOT_HEADER := 3

var phase: Phase = Phase.WAITING
var time_left: float = 0.0
var prep_left: float = 0.0
## Bando del jugador local en esta ronda (ROLE_SPECTATOR si no juega).
var player_role: int = ROLE_HUNTER
var winner_role: int = -1
## Partida a la que pertenece esta ronda.
var series: MatchSeries
## Número global de esta ronda (1..).
var round_number: int = 1
## Participante del jugador local (-1 si no está en la partida).
var local_index: int = -1
var net_role: NetRole = NetRole.OFFLINE

var _stats := {
	"redes_disparadas": 0,
	"redes_acertadas": 0,
	"escapes_de_red": 0,
	"armarios_registrados": 0,
	"ghosts_encontrados_en_armario": 0,
	"tiempo_escondido_s": 0.0,
	"puertas_usadas": 0,
	"luces_usadas": 0,
}
var _rating: int = 0
var _logged: bool = false
var _result_screen: ResultScreen
var _rng := RandomNumberGenerator.new()
var _last_beep: int = -1
var _local_peer: int = 1
## Personaje -> índice de participante (-1 = Presa de relleno).
var _participant_of: Dictionary = {}
## Participante -> segundos desde el inicio de la caza en que fue capturado.
var _capture_times: Dictionary = {}
var _wait_left: float = WAIT_TIMEOUT

# Red
var _remote_inputs: Dictionary = {}
var _snapshot_frame: int = 0
var _fire_seq: int = 0
var _interact_seq: int = 0
var _nets: Dictionary = {}
var _net_counter: int = 0
## Votos del desempate: peer -> "tiebreak" / "draw" (anfitrión).
var _votes: Dictionary = {}
var _my_vote: String = ""
var _vote_progress: String = ""
var _doors: Array = []
var _rooms: Array = []
var _spots: Array = []
var _interactables: Array = []

@onready var _points: Node3D = $Points
@onready var _route: Path3D = $Routes/RutaPatrulla


func _ready() -> void:
	if Net.is_host():
		net_role = NetRole.HOST
	elif Net.is_client():
		net_role = NetRole.CLIENT
	_local_peer = Net.local_peer()
	var setup := GameManager.round_setup
	GameManager.round_setup = {}
	series = GameManager.series
	# Sin partida en curso (p. ej. al abrir la escena directamente): una en solitario.
	if series == null or (series.is_over() and net_role == NetRole.OFFLINE):
		series = MatchSeries.solo(Net.player_name, GameManager.selected_role == ROLE_HUNTER)
		GameManager.series = series
	_rng.seed = int(setup.get("seed", randi()))
	round_number = series.round_number
	local_index = series.index_of_peer(_local_peer)
	if local_index == series.current_hunter():
		player_role = ROLE_HUNTER
	elif local_index in series.current_prey():
		player_role = ROLE_GHOST
	else:
		player_role = ROLE_SPECTATOR
	start_spectating = player_role == ROLE_SPECTATOR
	allow_switch = false
	_build_spawns()
	_pick_dark_room()
	description = _intro_text()
	super()
	for entry in _entries:
		_participant_of[entry.character] = int(entry.spawn.get_meta("participant", -1))
	_doors = get_tree().get_nodes_in_group("doors")
	_rooms = get_tree().get_nodes_in_group("rooms")
	_spots = get_tree().get_nodes_in_group("hiding_spots")
	_interactables = get_tree().get_nodes_in_group("interactables")
	_connect_stats()
	for node in get_tree().get_nodes_in_group("ghosts"):
		(node as Ghost).state_changed.connect(_on_ghost_state_for_score)
	_hud.set_round_text("%s  ·  %s" % [series.round_label(), series.score_text()])
	prep_left = GameManager.config.prep_time
	time_left = GameManager.config.match_duration
	if net_role != NetRole.OFFLINE:
		_setup_network()
	_set_phase(Phase.PREP if net_role == NetRole.OFFLINE else Phase.WAITING)


func _physics_process(delta: float) -> void:
	super(delta)
	if net_role == NetRole.CLIENT:
		_send_intent()
	else:
		_simulate(delta)
		if net_role == NetRole.HOST:
			_snapshot_frame += 1
			if _snapshot_frame % SNAPSHOT_EVERY == 0:
				_send_snapshot()
	_hud.camera_button = _can_switch_camera()
	_update_match_hud()


func _simulate(delta: float) -> void:
	match phase:
		Phase.WAITING:
			_wait_left -= delta
			if Net.all_clients_ready() or _wait_left <= 0.0:
				_set_phase(Phase.PREP)
		Phase.PREP:
			prep_left -= delta
			if prep_left <= 0.0:
				_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			time_left = maxf(0.0, time_left - delta)
			_accumulate_hidden_time(delta)
			if _count_free_scoring() == 0:
				_end(ROLE_HUNTER)
			elif time_left <= 0.0:
				_end(ROLE_GHOST)


func _unhandled_input(event: InputEvent) -> void:
	# R en la pantalla de resultados = botón principal (siguiente ronda / nueva partida...).
	if phase == Phase.ENDED and event.is_action_pressed("reset_scenario"):
		if is_instance_valid(_result_screen) and _result_screen.primary_choice != "":
			_on_choice(_result_screen.primary_choice)
		get_viewport().set_input_as_handled()
		return
	# Espectador o Presa capturada: Tab cambia a quién se mira.
	if event.is_action_pressed("switch_character") and _can_switch_camera():
		var current := _watched if _controlled < 0 else _controlled
		_spectate((current + 1) % _entries.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reset_scenario") and net_role != NetRole.OFFLINE:
		get_viewport().set_input_as_handled()  # En red no se puede repetir la ronda.
		return
	super(event)


## R durante la partida: repetir esta ronda (no cuenta). Solo sin red.
func reset_scenario() -> void:
	if net_role != NetRole.OFFLINE:
		return
	_log_match(false)
	get_tree().reload_current_scene()


func _exit_tree() -> void:
	# Salir con Esc o cerrar la ventana también deja registro (como "abandonada" si no había terminado).
	_log_match(false)
	Audio.world_sound_hook = Callable()
	Audio.remote_world_sounds = false
	GameManager.noise_hook = Callable()
	GameManager.remote_noise = false


## Se puede cambiar de cámara: no se juega esta ronda, o la Presa del jugador ya está capturada.
func _can_switch_camera() -> bool:
	if phase == Phase.ENDED or _entries.is_empty():
		return false
	if _controlled < 0:
		return true
	var ghost := get_controlled_character() as Ghost
	return ghost != null and ghost.state == Ghost.State.CAPTURED


func _spectate_text(character: CharacterBase) -> String:
	var how := "Cambiar cámara" if GameManager.is_touch_mode() else "Tab: cambiar"
	return "Mirando a %s  (%s)" % [character.display_name, how]


# --- Montaje de la ronda ---------------------------------------------------------

func _build_spawns() -> void:
	var hunter_start: Marker3D = _points.get_node("HunterStart")
	_add_participant_spawn(series.current_hunter(), ROLE_HUNTER, hunter_start.global_transform)
	var spots: Array = _points.get_node("GhostSpots").get_children()
	_shuffle(spots)
	for index in series.current_prey():
		_add_participant_spawn(index, ROLE_GHOST, _random_spot(spots))
	for f in series.filler_count():
		var props := {"display_name": "Relleno %d" % (f + 1), "net_tag": "IA"}
		props["behavior"] = DummySpawn.Behavior.PUPPET if net_role == NetRole.CLIENT else DummySpawn.Behavior.AI
		_add_spawn("Relleno%d" % (f + 1), ROLE_GHOST, _random_spot(spots), props, -1)


func _random_spot(spots: Array) -> Transform3D:
	var candidate: Node3D = spots.pop_back()
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), candidate.global_position)


## Cada participante: el jugador local, la IA o (en red) un jugador remoto / una copia.
func _add_participant_spawn(index: int, role: int, at: Transform3D) -> void:
	var props := {"display_name": series.participant_name(index)}
	var peer := series.peer_of(index)
	if peer == _local_peer:
		props["player_start"] = true
	if net_role == NetRole.CLIENT:
		props["behavior"] = DummySpawn.Behavior.PUPPET
		props["net_tag"] = "IA" if peer == 0 else ""
	elif peer == 0:
		props["behavior"] = DummySpawn.Behavior.AI
	elif peer != _local_peer:
		props["behavior"] = DummySpawn.Behavior.NETWORK
		props["net_peer"] = peer
	_add_spawn("P%d" % index, role, at, props, index)


func _add_spawn(spawn_name: String, role: int, at: Transform3D, props: Dictionary, participant: int) -> void:
	var spawn := DummySpawn.new()
	spawn.name = spawn_name
	spawn.role = role
	spawn.set_meta("participant", participant)
	_spawns.add_child(spawn)
	spawn.global_transform = at
	spawn.route = spawn.get_path_to(_route)
	for key in props:
		spawn.set(key, props[key])


func _pick_dark_room() -> void:
	if _rng.randf() > DARK_ROOM_CHANCE:
		return
	var rooms := get_tree().get_nodes_in_group("rooms")
	if rooms.is_empty():
		return
	var room: Node = rooms[_rng.randi() % rooms.size()]
	rooms_dark = PackedStringArray([room.name])


## Barajado con la semilla de la ronda (igual en todos los dispositivos).
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


func _intro_text() -> String:
	var header := "%s · %s" % [series.round_label().to_upper(), series.score_text()]
	if series.is_tiebreak() and series.stage_round == 0:
		header += "\n¡DESEMPATE entre %s! Las Presas de relleno no puntúan." % _names(series.contenders)
	var hunter_name := series.participant_name(series.current_hunter())
	match player_role:
		ROLE_HUNTER:
			return header + "\nEres el CAZADOR: 1 punto por cada Presa que atrapes."
		ROLE_GHOST:
			return header + "\nEres PRESA (Cazador: %s). Sobrevive para ganar 1 punto. Sale en %d s." % [hunter_name, int(GameManager.config.prep_time)]
	return header + "\nMiras como espectador. Cazador: %s." % hunter_name


func _names(indices: Array) -> String:
	var names := PackedStringArray()
	for i in indices:
		names.append(series.participant_name(i))
	if names.size() <= 2:
		return " y ".join(names)
	return ", ".join(names.slice(0, -1)) + " y " + names[-1]


# --- Fases -----------------------------------------------------------------------

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	match phase:
		Phase.WAITING:
			_freeze_group("hunters", true)
			_freeze_group("ghosts", true)
		Phase.PREP:
			_freeze_group("hunters", true)
			_freeze_group("ghosts", false)
		Phase.PLAYING:
			_freeze_group("hunters", false)
			_freeze_group("ghosts", false)
			_hud.set_blackout(false)
			Audio.play("hunt_start")
			match player_role:
				ROLE_HUNTER:
					_hud.show_message("¡A cazar!")
				ROLE_GHOST:
					_hud.show_message("¡El Cazador ha salido!")
				_:
					_hud.show_message("¡Empieza la caza!")
		Phase.ENDED:
			_freeze_group("hunters", true)
			_freeze_group("ghosts", true)


func _freeze_group(group: String, value: bool) -> void:
	for node in get_tree().get_nodes_in_group(group):
		(node as CharacterBase).frozen = value


## Presas que puntúan (no de relleno) todavía libres.
func _count_free_scoring() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if int(_participant_of.get(ghost, -1)) >= 0 and ghost.state != Ghost.State.CAPTURED:
			count += 1
	return count


func _on_ghost_state_for_score(ghost: Ghost, _old_state: Ghost.State, new_state: Ghost.State) -> void:
	var index := int(_participant_of.get(ghost, -1))
	if new_state == Ghost.State.CAPTURED and index >= 0 and phase == Phase.PLAYING and net_role != NetRole.CLIENT:
		_capture_times[index] = _played_seconds()


## Anfitrión / sin red: fin de la ronda.
func _end(winner: int) -> void:
	winner_role = winner
	_set_phase(Phase.ENDED)
	var outcome := {}
	for index in series.current_prey():
		outcome[index] = _capture_times.get(index, -1.0)
	series.record_round(outcome, GameManager.config.match_duration)
	if net_role == NetRole.HOST:
		_send("_ev_round_end", [series.to_dict(), winner, _stats])
	_show_round_end()


func _show_round_end() -> void:
	_hud.visible = false
	var last := series.last_round
	var captured: Array = last.get("captured", [])
	var survived: Array = last.get("survived", [])
	var total := captured.size() + survived.size()
	var title := "¡EL CAZADOR LAS ATRAPÓ A TODAS!" if winner_role == ROLE_HUNTER else "¡SE ACABÓ EL TIEMPO!"
	var gained := int(last.get("gained", {}).get(local_index, 0))
	var subtitle := ""
	match player_role:
		ROLE_HUNTER:
			subtitle = "Has atrapado %d de %d Presas: +%d %s" % [captured.size(), total, gained, _pts(gained)]
		ROLE_GHOST:
			subtitle = "¡Has sobrevivido! +1 punto" if local_index in survived else "Te han atrapado: 0 puntos"
		_:
			subtitle = "%s atrapó a %d de %d" % [series.participant_name(int(last.get("hunter", -1))), captured.size(), total]
	_result_screen = ResultScreen.new()
	add_child(_result_screen)
	_result_screen.show_result(title, subtitle, gained > 0 or player_role == ROLE_SPECTATOR, _stats_text())
	_result_screen.rating_changed.connect(func(value: int) -> void: _rating = value)
	_result_screen.choice.connect(_on_choice)
	_refresh_result_screen()
	if series.is_over():
		Audio.play("win" if local_index in series.winners else "lose")
	else:
		Audio.play("win" if gained > 0 else "lose")


func _pts(n: int) -> String:
	return "punto" if n == 1 else "puntos"


## Clasificación: "1. ► Ana   4 puntos  (+1)   · 312 s".
func _standings_text() -> String:
	var lines := PackedStringArray()
	var gained: Dictionary = series.last_round.get("gained", {})
	var place := 1
	for i in series.standings():
		var name := series.participant_name(i)
		if i == local_index:
			name = "► " + name
		var delta := int(gained.get(i, 0))
		var plus := "  (+%d)" % delta if delta > 0 else ""
		var tie := ""
		if series.is_tiebreak() and series.is_playing(i):
			tie = "  · desempate: %d" % series.stage_points[i]
		lines.append("%d. %s   %d %s%s   · %d s%s" % [place, name, series.points[i], _pts(series.points[i]), plus, int(series.times[i]), tie])
		place += 1
	return "\n".join(lines)


## Clasificación, estado de la partida, cuestionario y botones.
func _refresh_result_screen() -> void:
	var rs := _result_screen
	if not is_instance_valid(rs):
		return
	rs.set_table_text(_standings_text())
	var decides := net_role != NetRole.CLIENT
	var leave := ["Salir (Esc)", "menu"]
	match series.status:
		MatchSeries.Status.PLAYING:
			var hunter := series.current_hunter()
			var next_text := "Siguiente: %s — Cazador: %s" % [series.round_label(), "¡TÚ!" if hunter == local_index else series.participant_name(hunter)]
			if series.is_tiebreak() and series.stage_round == 0:
				next_text = "¡Empate a puntos y tiempo! Desempate entre %s.\n%s" % [_names(series.contenders), next_text]
				if not series.is_playing(local_index):
					next_text += "\nTú miras como espectador."
			if not decides:
				next_text += "\nEsperando a que el anfitrión continúe..."
			rs.set_series_text(next_text)
			rs.set_questionnaire_visible(false)
			rs.set_choices([["Siguiente ronda (R)", "next"], ["Abandonar (Esc)", "menu"]] if decides else [leave])
		MatchSeries.Status.TIE_VOTE:
			var text := "¡Siguen empatados %s! ¿Otro desempate o terminar en empate?" % _names(series.winners)
			if _my_vote != "":
				text += "\nHas votado %s. %s" % ["desempatar" if _my_vote == "tiebreak" else "empate", _vote_progress]
				rs.set_choices([leave])
			else:
				rs.set_choices([["Desempatar (R)", "tiebreak"], ["Terminar en empate", "draw"]])
			rs.set_series_text(text, Color(0.6, 0.85, 1.0))
			rs.set_questionnaire_visible(false)
		_:
			var final := ""
			var color := Color(1.0, 0.5, 0.45)
			if series.is_draw():
				final = "EMPATE entre %s" % _names(series.winners)
				color = Color(0.8, 0.8, 0.9)
			elif local_index in series.winners:
				final = "¡HAS GANADO LA PARTIDA!"
				color = Color(0.5, 1.0, 0.55)
			else:
				final = "GANA %s" % series.participant_name(series.winners[0]).to_upper()
			rs.set_series_text(final + ("" if decides else "\nEsperando al anfitrión..."), color)
			rs.set_questionnaire_visible(true)
			if net_role == NetRole.HOST:
				rs.set_choices([["Nueva partida (R)", "new"], ["Volver a la sala", "lobby"], ["Menú (Esc)", "menu"]])
			elif decides:
				rs.set_choices([["Nueva partida (R)", "new"], ["Menú principal (Esc)", "menu"]])
			else:
				rs.set_choices([["Menú principal (Esc)", "menu"]])


func _on_choice(id: String) -> void:
	match id:
		"next":
			if net_role == NetRole.CLIENT:
				return
			_log_match(false)
			if net_role == NetRole.HOST:
				Net.load_round()
			else:
				get_tree().reload_current_scene()
		"tiebreak", "draw":
			if net_role == NetRole.OFFLINE:
				if id == "tiebreak":
					series.continue_tiebreak()
					_on_choice("next")
				else:
					series.declare_draw()
					_refresh_result_screen()
				return
			_my_vote = id
			_vote_progress = "Esperando al resto de votos..."
			_refresh_result_screen()
			if net_role == NetRole.HOST:
				_register_vote(1, id)
			else:
				_net_vote.rpc_id(1, id)
		"new":
			if net_role == NetRole.CLIENT:
				return
			_log_match(true)
			if net_role == NetRole.HOST:
				Net.start_match()
			else:
				GameManager.start_match(GameManager.selected_role)
		"lobby":
			_log_match(false)
			Net.back_to_lobby()
		"menu":
			_log_match(false)
			GameManager.go_to_menu()


# --- HUD -------------------------------------------------------------------------

func _update_match_hud() -> void:
	match phase:
		Phase.WAITING:
			_hud.set_timer_text("Esperando a los jugadores...")
		Phase.PREP:
			var seconds := ceili(prep_left)
			# Pitido en los últimos 3 segundos de la preparación.
			if seconds <= 3 and seconds != _last_beep:
				_last_beep = seconds
				Audio.play("beep")
			if player_role == ROLE_HUNTER:
				_hud.set_blackout(true, "Las Presas se están escondiendo...\n%d" % seconds)
			_hud.set_timer_text("Preparación: %d" % seconds)
		Phase.PLAYING:
			var total := ceili(time_left)
			_hud.set_timer_text("%d:%02d" % [total / 60, total % 60], time_left <= 30.0)
		Phase.ENDED:
			_hud.set_timer_text("")


# --- Estadísticas y registro -----------------------------------------------------

func _connect_stats() -> void:
	for node in get_tree().get_nodes_in_group("hunters"):
		(node as Hunter).net_fired.connect(func(_h: Hunter) -> void: _count("redes_disparadas"))
	for node in get_tree().get_nodes_in_group("ghosts"):
		(node as Ghost).state_changed.connect(_on_ghost_state_for_stats)
	for node in get_tree().get_nodes_in_group("hiding_spots"):
		(node as HidingSpot).searched.connect(_on_spot_searched)
	for node in get_tree().get_nodes_in_group("doors"):
		(node as Door).open_changed.connect(func(_d: Door, _open: bool) -> void: _count("puertas_usadas"))
	for node in get_tree().get_nodes_in_group("rooms"):
		(node as Room).lit_changed.connect(func(_r: Room, _lit: bool) -> void: _count("luces_usadas"))


func _on_spot_searched(_spot: HidingSpot, found: Ghost) -> void:
	_count("armarios_registrados")
	if found:
		_count("ghosts_encontrados_en_armario")


func _count(key: String) -> void:
	if phase != Phase.ENDED:
		_stats[key] += 1


func _on_ghost_state_for_stats(_ghost: Ghost, old_state: Ghost.State, new_state: Ghost.State) -> void:
	if new_state == Ghost.State.NETTED:
		_count("redes_acertadas")
	elif new_state == Ghost.State.FREE and old_state == Ghost.State.NETTED:
		_count("escapes_de_red")


func _accumulate_hidden_time(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("ghosts"):
		if (node as Ghost).state == Ghost.State.HIDDEN:
			_stats["tiempo_escondido_s"] += delta


func _played_seconds() -> float:
	return GameManager.config.match_duration - time_left


func _stats_text() -> String:
	var ghosts := get_tree().get_nodes_in_group("ghosts").size()
	var captured := ghosts - _count_free_ghosts()
	var played := int(_played_seconds())
	var lines := PackedStringArray([
		"Duración: %d:%02d" % [played / 60, played % 60],
		"Presas capturadas: %d / %d" % [captured, ghosts],
		"Redes: %d disparadas, %d acertadas, %d escapes" % [_stats["redes_disparadas"], _stats["redes_acertadas"], _stats["escapes_de_red"]],
		"Armarios registrados: %d (%d con Presa dentro)" % [_stats["armarios_registrados"], _stats["ghosts_encontrados_en_armario"]],
		"Tiempo escondido en armarios: %.1f s" % _stats["tiempo_escondido_s"],
		"Puertas usadas: %d · Luces usadas: %d" % [_stats["puertas_usadas"], _stats["luces_usadas"]],
	])
	return "\n".join(lines)


func _log_match(play_again: bool) -> void:
	if _logged or _entries.is_empty():
		return
	_logged = true
	var ghosts := get_tree().get_nodes_in_group("ghosts").size() if is_inside_tree() else 0
	var winner := "abandonada"
	if winner_role == ROLE_HUNTER:
		winner = "hunter"
	elif winner_role == ROLE_GHOST:
		winner = "ghosts"
	var role := "espectador"
	if player_role == ROLE_HUNTER:
		role = "hunter"
	elif player_role == ROLE_GHOST:
		role = "ghost"
	var row := {
		"fecha": Time.get_datetime_string_from_system(),
		"rol_jugador": role,
		"ganador": winner,
		"duracion_s": "%.1f" % _played_seconds(),
		"ghosts_total": ghosts,
		"ghosts_capturados": ghosts - _count_free_ghosts() if is_inside_tree() else "",
		"diversion_1a5": _rating if _rating > 0 else "",
		# "Jugar otra" solo tiene sentido al terminar la partida (las rondas intermedias continúan solas).
		"jugar_otra": ("si" if play_again else "no") if series.is_over() else "",
		"dificultad": GameManager.get_difficulty_name(),
		"serie": series.id,
		"ronda": round_number,
		"marcador": series.score_text(),
		"resultado_serie": series.result_code_for(_local_peer),
		"modo": ["solo", "anfitrion", "cliente"][net_role],
		"puntos": series.points[local_index] if local_index >= 0 else "",
	}
	if is_instance_valid(_result_screen):
		row.merge(_result_screen.get_answers(), true)
	for key in _stats:
		row[key] = ("%.1f" % _stats[key]) if _stats[key] is float else _stats[key]
	var err := PlaytestLogger.append(row)
	if err != OK:
		push_warning("No se pudo guardar la partida en %s (%s)" % [PlaytestLogger.path, error_string(err)])


# --- Red: preparación ------------------------------------------------------------

func _setup_network() -> void:
	Net.session_ended.connect(_on_session_ended)
	if net_role == NetRole.CLIENT:
		Audio.remote_world_sounds = true
		GameManager.remote_noise = true
		Net.report_round_ready()
		return
	for entry in _entries:
		if entry.fallback is NetInputController:
			_remote_inputs[(entry.fallback as NetInputController).peer] = entry.fallback
	Audio.world_sound_hook = _forward_sound
	GameManager.noise_hook = _forward_noise
	Net.player_left.connect(_on_player_left)
	for node in get_tree().get_nodes_in_group("ghosts"):
		(node as Ghost).state_changed.connect(_on_ghost_state_net)
	for node in _doors:
		(node as Door).open_changed.connect(func(door: Door, open: bool) -> void: _send("_ev_door", [_doors.find(door), open]))
	for node in _rooms:
		(node as Room).lit_changed.connect(func(room: Room, lit: bool) -> void: _send("_ev_room", [_rooms.find(room), lit]))
	for node in _spots:
		(node as HidingSpot).searched.connect(func(spot: HidingSpot, found: Ghost) -> void: _send("_ev_spot_searched", [_spots.find(spot), _index_of(found)]))
	for node in get_tree().get_nodes_in_group("hunters"):
		(node as Hunter).net_fired.connect(_on_net_fired)


func _index_of(character: CharacterBase) -> int:
	if character == null:
		return -1
	for i in _entries.size():
		if _entries[i].character == character:
			return i
	return -1


func _character_at(index: int) -> CharacterBase:
	return _entries[index].character if index >= 0 and index < _entries.size() else null


## Evento fiable a los clientes que ya tienen la ronda cargada.
func _send(method: StringName, args: Array) -> void:
	for peer in Net.ready_peers():
		callv("rpc_id", [peer, method] + args)


func _on_session_ended(reason: String) -> void:
	GameManager.notice = reason
	GameManager.go_to_menu()


## Un jugador se ha ido: la IA toma su personaje y su puesto (anfitrión).
func _on_player_left(peer: int) -> void:
	var index := series.index_of_peer(peer)
	if index < 0:
		return
	var who := series.participant_name(index)
	series.replace_with_ai(index)
	_remote_inputs.erase(peer)
	for entry in _entries:
		if int(_participant_of.get(entry.character, -1)) != index:
			continue
		var ai: CharacterController = HunterAI.new() if entry.character is Hunter else GhostAI.new()
		ai.name = "AI"
		entry.character.add_child(ai)
		entry.fallback = ai
		entry.character.display_name = series.participant_name(index)
		entry.character.set_controller(ai, false)
	_hud.show_message("%s se ha ido: le sustituye la IA" % who, 3.0)
	if series.status == MatchSeries.Status.TIE_VOTE:
		_votes.erase(peer)
		_check_votes()


# --- Red: anfitrión -> clientes -----------------------------------------------------

func _send_snapshot() -> void:
	var peers := Net.ready_peers()
	if peers.is_empty():
		return
	var data := PackedFloat32Array()
	data.resize(SNAPSHOT_HEADER + _entries.size() * SNAPSHOT_STRIDE)
	data[0] = phase
	data[1] = time_left
	data[2] = prep_left
	var at := SNAPSHOT_HEADER
	for entry in _entries:
		var c := entry.character
		data[at] = c.global_position.x
		data[at + 1] = c.global_position.y
		data[at + 2] = c.global_position.z
		data[at + 3] = c.rotation.y
		data[at + 4] = c.interact_progress
		data[at + 5] = _interactables.find(c.interact_target) if c.interact_target else -1
		data[at + 8] = -1
		if c is Ghost:
			data[at + 6] = (c as Ghost).net_time_left
			data[at + 7] = (c as Ghost).hide_cooldown_left
		elif c is Hunter:
			var hunter := c as Hunter
			data[at + 6] = hunter.net_cooldown_left
			data[at + 7] = hunter.capture_progress
			data[at + 8] = _index_of(hunter.capture_target)
		at += SNAPSHOT_STRIDE
	for peer in peers:
		_ev_snapshot.rpc_id(peer, data)


@rpc("authority", "unreliable_ordered")
func _ev_snapshot(data: PackedFloat32Array) -> void:
	if data.size() != SNAPSHOT_HEADER + _entries.size() * SNAPSHOT_STRIDE:
		return
	var new_phase := int(data[0]) as Phase
	if phase != Phase.ENDED and new_phase != Phase.ENDED and new_phase != phase:
		_set_phase(new_phase)
	time_left = data[1]
	prep_left = data[2]
	var at := SNAPSHOT_HEADER
	for entry in _entries:
		var c := entry.character
		c.set_net_target(Vector3(data[at], data[at + 1], data[at + 2]), data[at + 3])
		c.interact_progress = data[at + 4]
		var item := int(data[at + 5])
		c.interact_target = _interactables[item] if item >= 0 and item < _interactables.size() else null
		if c is Ghost:
			var ghost := c as Ghost
			if ghost.state != Ghost.State.NETTED:
				ghost.net_time_left = data[at + 6]
			ghost.hide_cooldown_left = data[at + 7]
		elif c is Hunter:
			var hunter := c as Hunter
			hunter.net_cooldown_left = data[at + 6]
			hunter.capture_progress = data[at + 7]
			hunter.capture_target = _character_at(int(data[at + 8])) as Ghost
		at += SNAPSHOT_STRIDE


func _on_ghost_state_net(ghost: Ghost, _old_state: Ghost.State, new_state: Ghost.State) -> void:
	_send("_ev_ghost_state", [_index_of(ghost), new_state, _spots.find(ghost.hiding_spot), ghost.net_time_left])


@rpc("authority", "reliable")
func _ev_ghost_state(index: int, state: int, spot_index: int, net_time: float) -> void:
	var ghost := _character_at(index) as Ghost
	if ghost:
		var spot: HidingSpot = _spots[spot_index] if spot_index >= 0 and spot_index < _spots.size() else null
		ghost.net_apply_state(state as Ghost.State, spot, net_time)


@rpc("authority", "reliable")
func _ev_door(index: int, open: bool) -> void:
	if index >= 0 and index < _doors.size():
		(_doors[index] as Door).set_open(open, null, true, true)


@rpc("authority", "reliable")
func _ev_room(index: int, lit: bool) -> void:
	if index >= 0 and index < _rooms.size():
		(_rooms[index] as Room).set_lit(lit)


@rpc("authority", "reliable")
func _ev_spot_searched(spot_index: int, found_index: int) -> void:
	if spot_index >= 0 and spot_index < _spots.size():
		var spot := _spots[spot_index] as HidingSpot
		spot.searched.emit(spot, _character_at(found_index) as Ghost)


func _on_net_fired(hunter: Hunter) -> void:
	var net := hunter.last_net
	if net == null:
		return
	_net_counter += 1
	var id := _net_counter
	_send("_ev_net_fired", [_index_of(hunter), net.get_direction(), id])
	net.finished.connect(func(at: Vector3, hit: bool) -> void: _send("_ev_net_end", [id, at, hit]))


@rpc("authority", "reliable")
func _ev_net_fired(hunter_index: int, direction: Vector3, id: int) -> void:
	var hunter := _character_at(hunter_index) as Hunter
	if hunter == null:
		return
	var net := NetProjectile.new()
	net.visual_only = true
	hunter.get_parent().add_child(net)
	net.launch(hunter, direction)
	_nets[id] = net


@rpc("authority", "reliable")
func _ev_net_end(id: int, at: Vector3, hit: bool) -> void:
	var net: NetProjectile = _nets.get(id)
	_nets.erase(id)
	if is_instance_valid(net):
		net.finish(at, hit)


func _forward_sound(sound: String, at: Vector3, max_distance: float, volume_db: float, vary_pitch: bool) -> void:
	for peer in Net.ready_peers():
		_ev_sound.rpc_id(peer, sound, at, max_distance, volume_db, vary_pitch)


@rpc("authority", "unreliable")
func _ev_sound(sound: String, at: Vector3, max_distance: float, volume_db: float, vary_pitch: bool) -> void:
	Audio.play_at(sound, at, max_distance, volume_db, vary_pitch, true)


func _forward_noise(at: Vector3, radius: float, source: Node) -> void:
	for peer in Net.ready_peers():
		_ev_noise.rpc_id(peer, at, radius, _index_of(source as CharacterBase))


@rpc("authority", "unreliable")
func _ev_noise(at: Vector3, radius: float, source_index: int) -> void:
	GameManager.noise_made.emit(at, radius, _character_at(source_index))


@rpc("authority", "reliable")
func _ev_round_end(series_data: Dictionary, winner: int, stats: Dictionary) -> void:
	series = MatchSeries.from_dict(series_data)
	GameManager.series = series
	winner_role = winner
	_stats = stats
	_set_phase(Phase.ENDED)
	_show_round_end()


## La partida ha cambiado tras una votación (empate declarado) o hay votos nuevos.
@rpc("authority", "reliable")
func _ev_series_update(series_data: Dictionary, progress: String) -> void:
	series = MatchSeries.from_dict(series_data)
	GameManager.series = series
	_vote_progress = progress
	if series.status != MatchSeries.Status.TIE_VOTE:
		_my_vote = ""
	_refresh_result_screen()


# --- Red: clientes -> anfitrión ------------------------------------------------------

## Las intenciones del frame anterior del jugador local (los personajes se procesan después
## del escenario), con contadores para disparar y usar.
func _send_intent() -> void:
	var me := get_controlled_character()
	if me == null or not Net.is_client():
		return
	if me.intent.fire:
		_fire_seq += 1
	if me.intent.interact:
		_interact_seq += 1
	_net_intent.rpc_id(1, NetInputController.make_packet(me.intent, _fire_seq, _interact_seq))


@rpc("any_peer", "unreliable_ordered")
func _net_intent(packet: PackedFloat32Array) -> void:
	# Puede llegar a la ronda anterior mientras se cambia de escena.
	if not is_inside_tree():
		return
	var controller: NetInputController = _remote_inputs.get(multiplayer.get_remote_sender_id())
	if controller:
		controller.apply_packet(packet)


@rpc("any_peer", "reliable")
func _net_vote(choice: String) -> void:
	if is_inside_tree() and net_role == NetRole.HOST:
		_register_vote(multiplayer.get_remote_sender_id(), choice)


func _register_vote(peer: int, choice: String) -> void:
	if series.status != MatchSeries.Status.TIE_VOTE:
		return
	_votes[peer] = choice
	_check_votes()


## Cuando han votado todos los jugadores conectados: gana la mayoría (empate de votos = empate).
func _check_votes() -> void:
	var voters := [1] + Array(multiplayer.get_peers())
	var done := 0
	var tiebreak := 0
	for peer in voters:
		if _votes.has(peer):
			done += 1
			if _votes[peer] == "tiebreak":
				tiebreak += 1
	_vote_progress = "Votos: %d de %d" % [done, voters.size()]
	if done < voters.size():
		_send("_ev_series_update", [series.to_dict(), _vote_progress])
		_refresh_result_screen()
		return
	_votes = {}
	if tiebreak * 2 > voters.size():
		series.continue_tiebreak()
		_log_match(false)
		Net.load_round()
	else:
		series.declare_draw()
		_my_vote = ""
		_send("_ev_series_update", [series.to_dict(), ""])
		_refresh_result_screen()
