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
## Partida en curso (null fuera de una partida).
var series: MatchSeries
## Datos de la ronda que se va a cargar (semilla, dificultad...). Vacío = se generan al cargar.
var round_setup: Dictionary = {}
## Red: en el anfitrión recibe cada ruido para reenviarlo; en un cliente los ruidos solo
## llegan del anfitrión.
var noise_hook: Callable
var remote_noise: bool = false
## Aviso para mostrar al volver al menú (p. ej. "Se ha perdido la conexión").
var notice: String = ""

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
## Entorno compartido de la casa (partida, pruebas y fondo del menú).
var house_environment: Environment = preload("res://scenes/game/house_environment.tres")
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
	apply_graphics()


## Aplica los ajustes de rendimiento (al arrancar y al cambiarlos en el panel de ajustes).
func apply_graphics() -> void:
	if is_mobile():
		Engine.max_fps = config.max_fps_mobile
		var root := get_tree().root
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = config.render_scale_mobile
	house_environment.glow_enabled = not config.graphics_low
	get_tree().call_group("graphics_quality", "apply_graphics_quality", config.graphics_low)


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


## Partida en solitario contra 3 IA. role: bando del jugador en la primera ronda.
func start_match(role: int) -> void:
	Net.leave()
	selected_role = role
	series = MatchSeries.solo(Net.player_name, role == DummySpawn.Role.HUNTER)
	round_setup = {}
	get_tree().change_scene_to_file(MATCH_SCENE)


## Vuelve al menú principal (sale también de la sala de red).
func go_to_menu() -> void:
	series = null
	round_setup = {}
	Net.leave()
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
	if remote_noise or not config.noise_enabled or radius <= 0.0:
		return
	if noise_hook.is_valid():
		noise_hook.call(position, radius, source)
	noise_made.emit(position, radius, source)
