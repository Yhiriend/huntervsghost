class_name MatchScenario
extends TestScenario
## Partida completa: preparación -> persecución con temporizador -> resultados.
## Los rivales los controla la IA:
##   Jugando como Hunter: ghost_count Ghosts IA que empiezan en sitios aleatorios y aprovechan
##     la preparación para alejarse o esconderse.
##   Jugando como Ghost (1 vs 1): un Hunter IA.
## Victoria del Hunter: todos los Ghosts capturados antes de que acabe el tiempo.
## Victoria de los Ghosts: al menos uno libre cuando el tiempo llega a cero.
## La captura se comprueba antes que el tiempo: una captura completada en el último frame cuenta.
## Cada partida se guarda en user://playtests.csv (PlaytestLogger).

enum Phase { PREP, PLAYING, ENDED }

const ROLE_HUNTER := DummySpawn.Role.HUNTER
const ROLE_GHOST := DummySpawn.Role.GHOST
## Probabilidad de que una habitación aleatoria empiece a oscuras.
const DARK_ROOM_CHANCE := 0.5

var phase: Phase = Phase.PREP
var time_left: float = 0.0
var prep_left: float = 0.0
var player_role: int = ROLE_HUNTER
var winner_role: int = -1

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
var _ghost_candidates: Array = []

var _last_beep: int = -1

@onready var _points: Node3D = $Points
@onready var _route: Path3D = $Routes/RutaPatrulla


func _ready() -> void:
	player_role = GameManager.selected_role
	allow_switch = false
	_build_spawns()
	_pick_dark_room()
	description = _intro_text()
	super()
	_connect_stats()
	prep_left = GameManager.config.prep_time
	time_left = GameManager.config.match_duration
	_set_phase(Phase.PREP)


func _physics_process(delta: float) -> void:
	super(delta)
	match phase:
		Phase.PREP:
			prep_left -= delta
			if prep_left <= 0.0:
				_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			time_left = maxf(0.0, time_left - delta)
			_accumulate_hidden_time(delta)
			if _count_free_ghosts() == 0:
				_end(ROLE_HUNTER)
			elif time_left <= 0.0:
				_end(ROLE_GHOST)
	_update_match_hud()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.ENDED and event.is_action_pressed("reset_scenario"):
		_leave(true)
		get_viewport().set_input_as_handled()
		return
	super(event)


## R durante la partida: reiniciarla.
func reset_scenario() -> void:
	_leave(true)


func _exit_tree() -> void:
	# Salir con Esc o cerrar la ventana también deja registro (como "abandonada" si no había terminado).
	_log_match(false)


# --- Montaje de la partida -------------------------------------------------------

func _build_spawns() -> void:
	var hunter_start: Marker3D = _points.get_node("HunterStart")
	if player_role == ROLE_HUNTER:
		_add_spawn("Cazador", ROLE_HUNTER, hunter_start.global_transform, {"player_start": true})
		for i in GameManager.config.ghost_count:
			_add_random_ghost(i)
	else:
		_add_spawn("Presa", ROLE_GHOST, (_points.get_node("GhostStart") as Marker3D).global_transform, {"player_start": true})
		_add_spawn("Cazador", ROLE_HUNTER, hunter_start.global_transform, {"behavior": DummySpawn.Behavior.AI})


## Cada Ghost IA empieza en un Marker3D distinto de Points/GhostSpots.
func _add_random_ghost(index: int) -> void:
	if _ghost_candidates.is_empty():
		_ghost_candidates.append_array(_points.get_node("GhostSpots").get_children())
		_ghost_candidates.shuffle()
	var candidate: Node3D = _ghost_candidates.pop_back()
	var props := {"behavior": DummySpawn.Behavior.AI}
	var basis := Basis(Vector3.UP, randf() * TAU)
	_add_spawn("Presa%d" % (index + 1), ROLE_GHOST, Transform3D(basis, candidate.global_position), props)


func _add_spawn(spawn_name: String, role: int, at: Transform3D, props: Dictionary) -> void:
	var spawn := DummySpawn.new()
	spawn.name = spawn_name
	spawn.role = role
	_spawns.add_child(spawn)
	spawn.global_transform = at
	spawn.route = spawn.get_path_to(_route)
	for key in props:
		spawn.set(key, props[key])


func _pick_dark_room() -> void:
	if randf() > DARK_ROOM_CHANCE:
		return
	var rooms := get_tree().get_nodes_in_group("rooms")
	var room: Node = rooms.pick_random()
	rooms_dark = PackedStringArray([room.name])


func _intro_text() -> String:
	if player_role == ROLE_HUNTER:
		return "Captura a las %d Presas antes de que acabe el tiempo." % GameManager.config.ghost_count
	return "Sobrevive hasta que acabe el tiempo. El Cazador sale en %d s." % int(GameManager.config.prep_time)


# --- Fases -----------------------------------------------------------------------

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	match phase:
		Phase.PREP:
			_freeze_group("hunters", true)
		Phase.PLAYING:
			_freeze_group("hunters", false)
			_hud.set_blackout(false)
			Audio.play("hunt_start")
			_hud.show_message("¡A cazar!" if player_role == ROLE_HUNTER else "¡El Cazador ha salido!")
		Phase.ENDED:
			_freeze_group("hunters", true)
			_freeze_group("ghosts", true)


func _freeze_group(group: String, value: bool) -> void:
	for node in get_tree().get_nodes_in_group(group):
		(node as CharacterBase).frozen = value


func _end(winner: int) -> void:
	winner_role = winner
	_set_phase(Phase.ENDED)
	_hud.visible = false
	Audio.play("win" if winner == player_role else "lose")
	var title := "¡GANA EL CAZADOR!" if winner == ROLE_HUNTER else "¡GANAN LAS PRESAS!"
	_result_screen = ResultScreen.new()
	add_child(_result_screen)
	_result_screen.show_result(title, winner == player_role, _stats_text())
	_result_screen.rating_changed.connect(func(value: int) -> void: _rating = value)
	_result_screen.finished.connect(_leave)


func _leave(play_again: bool) -> void:
	_log_match(play_again)
	if play_again:
		get_tree().reload_current_scene()
	else:
		GameManager.go_to_menu()


# --- HUD -------------------------------------------------------------------------

func _update_match_hud() -> void:
	match phase:
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
	var row := {
		"fecha": Time.get_datetime_string_from_system(),
		"rol_jugador": "hunter" if player_role == ROLE_HUNTER else "ghost",
		"ganador": winner,
		"duracion_s": "%.1f" % _played_seconds(),
		"ghosts_total": ghosts,
		"ghosts_capturados": ghosts - _count_free_ghosts() if is_inside_tree() else "",
		"diversion_1a5": _rating if _rating > 0 else "",
		"jugar_otra": "si" if play_again else "no",
		"dificultad": GameManager.get_difficulty_name(),
	}
	if is_instance_valid(_result_screen):
		row.merge(_result_screen.get_answers(), true)
	for key in _stats:
		row[key] = ("%.1f" % _stats[key]) if _stats[key] is float else _stats[key]
	var err := PlaytestLogger.append(row)
	if err != OK:
		push_warning("No se pudo guardar la partida en %s (%s)" % [PlaytestLogger.path, error_string(err)])
