extends CanvasLayer
## Autoload "DebugOverlay": FPS, ayuda de controles y panel de ajustes en caliente.
##   F1 -> mostrar/ocultar el panel de ajustes.
##   F2 -> mostrar/ocultar los conos de visión (activos por defecto).
##   1/2/3 -> cambiar de escenario (Prototype01 / TestHunter / TestGhost).
##   Esc -> volver al menú principal.
## El panel se genera solo a partir de las variables @export_range de GameConfig.

const HELP_TEXT := "WASD mover · Ratón apuntar · Clic red · E usar (mantener: capturar/registrar) · Shift sigilo · Tab cambiar · R reiniciar · F1 ajustes · F2 conos · 1/2/3 escenario · Esc menú"
## Escenarios accesibles con las teclas 1, 2 y 3.
const SCENES := {
	"scene_1": "res://scenes/test/Prototype01.tscn",
	"scene_2": "res://scenes/test/TestHunter.tscn",
	"scene_3": "res://scenes/test/TestGhost.tscn",
}
const REFRESH_INTERVAL := 0.25

var _panel: PanelContainer
var _fps_label: Label
var _help_label: Label
var _status_label: Label
## nombre de propiedad -> { "slider": HSlider, "label": Label }
var _rows: Dictionary = {}
var _refresh_timer: float = 0.0
var _status_time_left: float = 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_values()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		for action in SCENES:
			if event.is_action(action):
				get_tree().change_scene_to_file(SCENES[action])
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("back_to_menu"):
		var current := get_tree().current_scene
		if current and current.scene_file_path != GameManager.MENU_SCENE:
			GameManager.go_to_menu()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("debug_vision"):
		GameManager.debug_vision = not GameManager.debug_vision
		_set_status("Conos de visión: %s" % ("ON" if GameManager.debug_vision else "OFF"))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	var current := get_tree().current_scene
	_help_label.visible = current != null and current.scene_file_path != GameManager.MENU_SCENE
	if _status_time_left > 0.0:
		_status_time_left -= delta
		if _status_time_left <= 0.0:
			_status_label.text = ""
	if _panel.visible:
		_refresh_timer -= delta
		if _refresh_timer <= 0.0:
			_refresh_timer = REFRESH_INTERVAL
			_refresh_values()


# --- Construcción de la interfaz ---------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_fps_label = Label.new()
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -160.0
	_fps_label.offset_right = -12.0
	_fps_label.offset_top = 8.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(_fps_label)
	root.add_child(_fps_label)

	var help := Label.new()
	_help_label = help
	help.text = HELP_TEXT
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.anchor_right = 1.0
	help.offset_left = 12.0
	help.offset_right = -12.0
	help.offset_top = -56.0
	help.offset_bottom = -8.0
	help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 14)
	_style_label(help)
	root.add_child(help)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8.0
	_panel.offset_top = 8.0
	_panel.offset_right = 380.0
	_panel.offset_bottom = -44.0
	root.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)

	var outer := VBoxContainer.new()
	margin.add_child(outer)

	var title := Label.new()
	title.text = "AJUSTES EN CALIENTE (F1)"
	title.add_theme_font_size_override("font_size", 18)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_build_config_rows(list)

	var buttons := HBoxContainer.new()
	outer.add_child(buttons)
	buttons.add_child(_make_button("Restaurar", _on_reset_pressed))
	var save_button := _make_button("Guardar en .tres", _on_save_pressed)
	save_button.disabled = not OS.has_feature("editor")
	buttons.add_child(save_button)

	_status_label = Label.new()
	_status_label.anchor_left = 1.0
	_status_label.anchor_right = 1.0
	_status_label.offset_left = -420.0
	_status_label.offset_right = -12.0
	_status_label.offset_top = 34.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(_status_label)
	root.add_child(_status_label)


func _build_config_rows(list: VBoxContainer) -> void:
	var config := GameManager.config
	var pending_group := ""
	for prop in config.get_property_list():
		if prop.usage & PROPERTY_USAGE_GROUP:
			pending_group = prop.name
			continue
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var is_bool: bool = prop.type == TYPE_BOOL
		var is_number: bool = (prop.type == TYPE_FLOAT or prop.type == TYPE_INT) and prop.hint == PROPERTY_HINT_RANGE
		if not is_bool and not is_number:
			continue

		if pending_group != "":
			var header := Label.new()
			header.text = pending_group.to_upper()
			header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
			list.add_child(header)
			pending_group = ""

		if is_bool:
			var check := CheckBox.new()
			check.text = prop.name.replace("_", " ")
			check.focus_mode = Control.FOCUS_NONE
			check.button_pressed = config.get(prop.name)
			check.add_theme_font_size_override("font_size", 13)
			check.toggled.connect(_on_check_toggled.bind(prop.name))
			list.add_child(check)
			_rows[prop.name] = {"check": check}
			continue

		var range_parts: PackedStringArray = String(prop.hint_string).split(",")
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		list.add_child(label)

		var slider := HSlider.new()
		slider.focus_mode = Control.FOCUS_NONE
		slider.min_value = float(range_parts[0])
		slider.max_value = float(range_parts[1])
		slider.step = float(range_parts[2]) if range_parts.size() > 2 else 0.01
		slider.value = config.get(prop.name)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(prop.name, prop.type))
		list.add_child(slider)

		_rows[prop.name] = {"slider": slider, "label": label}
		_update_row_label(prop.name)


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _style_label(label: Label) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)


# --- Lógica ----------------------------------------------------------------

func _on_slider_changed(value: float, prop_name: String, prop_type: int) -> void:
	GameManager.config.set(prop_name, int(value) if prop_type == TYPE_INT else value)
	_update_row_label(prop_name)


func _on_check_toggled(pressed: bool, prop_name: String) -> void:
	GameManager.config.set(prop_name, pressed)


func _update_row_label(prop_name: String) -> void:
	if not _rows[prop_name].has("label"):
		return
	var value: Variant = GameManager.config.get(prop_name)
	var text_value := ("%.2f" % value) if value is float else str(value)
	_rows[prop_name].label.text = "%s: %s" % [prop_name.replace("_", " "), text_value]


## Sincroniza los sliders con valores cambiados desde otro sitio (p. ej. el zoom con la rueda).
func _refresh_values() -> void:
	for prop_name in _rows:
		var row: Dictionary = _rows[prop_name]
		if row.has("check"):
			(row.check as CheckBox).set_pressed_no_signal(GameManager.config.get(prop_name))
		else:
			(row.slider as HSlider).set_value_no_signal(GameManager.config.get(prop_name))
			_update_row_label(prop_name)


func _on_reset_pressed() -> void:
	GameManager.reset_config_to_defaults()
	_refresh_values()
	_set_status("Valores por defecto restaurados (sin guardar).")


func _on_save_pressed() -> void:
	var err := GameManager.save_config()
	_set_status("Guardado en game_config.tres" if err == OK else "Error al guardar (%d)" % err)


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text
		_status_time_left = 2.5
