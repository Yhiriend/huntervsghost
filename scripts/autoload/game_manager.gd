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

## Dibuja los conos de visión de todos los personajes (F2). Activo por defecto.
var debug_vision: bool = true:
	set(value):
		debug_vision = value
		debug_vision_toggled.emit(value)


func _load_config() -> GameConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded := load(CONFIG_PATH) as GameConfig
		if loaded:
			return loaded
	push_warning("No se encontró %s; usando valores por defecto." % CONFIG_PATH)
	return GameConfig.new()


func start_match(role: int) -> void:
	selected_role = role
	get_tree().change_scene_to_file(MATCH_SCENE)


func go_to_menu() -> void:
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
