extends Node
## Autoload "GameManager": estado global y acceso a la configuración.

signal debug_vision_toggled(enabled: bool)
## Alguien ha hecho ruido. radius = distancia a la que se oye. source = quien lo hizo (puede ser null).
signal noise_made(position: Vector3, radius: float, source: Node)

const CONFIG_PATH := "res://resources/game_config.tres"
const MENU_SCENE := "res://scenes/main/MainMenu.tscn"
const MATCH_SCENE := "res://scenes/game/Match.tscn"

var config: GameConfig = _load_config()

## Bando del jugador en la próxima partida (DummySpawn.Role: 0 = Hunter, 1 = Ghost).
var selected_role: int = 0
## Serie de rondas en curso (null fuera de una partida).
var series: MatchSeries

enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := ["facil", "normal", "dificil"]
## Valores de IA que cambia cada dificultad. NORMAL = los valores por defecto de GameConfig.
const DIFFICULTY_PRESETS := {
	Difficulty.EASY: {
		"ai_reaction_time": 1.2,
		"ai_aim_error": 2.8,
		"ai_lead_factor": 0.2,
		"ai_hunter_search_chance": 0.2,
		"ai_ghost_flee_distance": 6.0,
		"ai_ghost_hide_chance": 0.3,
		"ai_ghost_light_chance": 0.3,
	},
	Difficulty.NORMAL: {},
	Difficulty.HARD: {
		"ai_reaction_time": 0.5,
		"ai_aim_error": 1.2,
		"ai_lead_factor": 0.6,
		"ai_hunter_search_chance": 0.5,
		"ai_ghost_flee_distance": 11.0,
		"ai_ghost_hide_chance": 0.7,
		"ai_ghost_light_chance": 0.8,
	},
}
## Dificultad de la IA rival (afecta a la IA del bando contrario al jugador).
var difficulty: int = Difficulty.NORMAL

## Dibuja los conos de visión de todos los personajes (F2). Activo por defecto.
var debug_vision: bool = true:
	set(value):
		debug_vision = value
		debug_vision_toggled.emit(value)


func _ready() -> void:
	if is_mobile():
		config.camera_zoom = config.camera_zoom_touch


## Se ejecuta en un teléfono o tablet.
func is_mobile() -> bool:
	return OS.has_feature("mobile")


## Controles táctiles activos: en el móvil siempre; en PC si se activa en ajustes (F1).
func is_touch_mode() -> bool:
	return is_mobile() or config.touch_controls_on_pc


func _load_config() -> GameConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded := load(CONFIG_PATH) as GameConfig
		if loaded:
			return loaded
	push_warning("No se encontró %s; usando valores por defecto." % CONFIG_PATH)
	return GameConfig.new()


## Aplica una dificultad: primero restaura los valores de IA por defecto y luego los del preset.
func set_difficulty(level: int) -> void:
	difficulty = level
	var defaults := GameConfig.new()
	for key in DIFFICULTY_PRESETS[Difficulty.HARD]:
		config.set(key, defaults.get(key))
	var preset: Dictionary = DIFFICULTY_PRESETS[level]
	for key in preset:
		config.set(key, preset[key])


func get_difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


## Empieza una serie de rondas (MatchSeries) con el jugador en el bando indicado.
func start_match(role: int) -> void:
	selected_role = role
	series = MatchSeries.new(role)
	get_tree().change_scene_to_file(MATCH_SCENE)


func go_to_menu() -> void:
	series = null
	get_tree().change_scene_to_file(MENU_SCENE)


## Restaura todos los valores a los definidos en game_config.gd.
func reset_config_to_defaults() -> void:
	var defaults := GameConfig.new()
	for prop in defaults.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			config.set(prop.name, defaults.get(prop.name))


## Guarda los valores actuales en game_config.tres (solo funciona desde el editor).
func save_config() -> Error:
	if not OS.has_feature("editor"):
		return ERR_UNAVAILABLE
	return ResourceSaver.save(config, CONFIG_PATH)


## Punto único para generar ruido (pasos, puertas, interruptores, armarios).
func make_noise(position: Vector3, radius: float, source: Node) -> void:
	if config.noise_enabled and radius > 0.0:
		noise_made.emit(position, radius, source)
