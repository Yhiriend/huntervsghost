extends SceneTree
## Script de configuración de un solo uso (Fase 0).
## Uso: Godot --headless --path . --script res://tools/setup_project.gd
## Escribe el Input Map, los autoloads y la escena principal en project.godot,
## y genera resources/game_config.tres con los valores por defecto (si no existe).


func _init() -> void:
	_setup_input_map()
	ProjectSettings.set_setting("autoload/GameManager", "*res://scripts/autoload/game_manager.gd")
	ProjectSettings.set_setting("autoload/DebugOverlay", "*res://scripts/ui/debug_overlay.gd")
	ProjectSettings.set_setting("autoload/Audio", "*res://scripts/autoload/audio_manager.gd")
	ProjectSettings.set_setting("autoload/Net", "*res://scripts/autoload/net_manager.gd")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main/MainMenu.tscn")
	ProjectSettings.set_setting("application/config/name", "Cazador o Presa")
	ProjectSettings.set_setting("layer_names/3d_physics/layer_1", "world")
	ProjectSettings.set_setting("layer_names/3d_physics/layer_2", "characters")
	# Móvil: horizontal (gira con el sensor) y el botón Atrás lo gestiona el juego.
	ProjectSettings.set_setting("display/window/handheld/orientation", 4)
	ProjectSettings.set_setting("application/config/quit_on_go_back", false)
	ProjectSettings.set_setting("rendering/textures/vram_compression/import_etc2_astc", true)
	var err := ProjectSettings.save()
	print("project.godot guardado: ", error_string(err))

	# Solo se crea si no existe, para no pisar valores guardados desde el panel F1.
	if not FileAccess.file_exists("res://resources/game_config.tres"):
		var config_script: Script = load("res://scripts/resources/game_config.gd")
		var config: Resource = config_script.new()
		err = ResourceSaver.save(config, "res://resources/game_config.tres")
		print("game_config.tres guardado: ", error_string(err))
	quit()


func _setup_input_map() -> void:
	_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("move_up", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_down", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("sneak", [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_action("fire", [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_SPACE), _joy(JOY_BUTTON_A)])
	_action("interact", [_key(KEY_E), _joy(JOY_BUTTON_X)])
	_action("reset_scenario", [_key(KEY_R), _joy(JOY_BUTTON_BACK)])
	_action("switch_character", [_key(KEY_TAB), _joy(JOY_BUTTON_Y)])
	_action("zoom_in", [_mouse(MOUSE_BUTTON_WHEEL_UP), _key(KEY_EQUAL)])
	_action("zoom_out", [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _key(KEY_MINUS)])
	_action("debug_panel", [_key(KEY_F1)])
	_action("debug_vision", [_key(KEY_F2)])
	_action("scene_1", [_key(KEY_1)])
	_action("scene_2", [_key(KEY_2)])
	_action("scene_3", [_key(KEY_3)])
	_action("scene_4", [_key(KEY_4)])
	_action("spectate", [_key(KEY_P)])
	_action("back_to_menu", [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)])


func _action(action_name: String, events: Array) -> void:
	for e: InputEvent in events:
		e.device = -1  # Cualquier dispositivo, como hace el editor.
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": 0.2, "events": events})


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
