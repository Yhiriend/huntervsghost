extends Control
## Menú principal mínimo: elegir bando, ir a los escenarios de prueba o abrir los datos de partidas.

const TEST_SCENES := [
	["Prototype01 · casa libre", "res://scenes/test/Prototype01.tscn"],
	["TestHunter · 5 Ghosts maniquí", "res://scenes/test/TestHunter.tscn"],
	["TestGhost · Hunters que patrullan", "res://scenes/test/TestGhost.tscn"],
]


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(_label("GHOST-HUNTER", 52, Color(0.45, 0.85, 1.0)))
	box.add_child(_label("Prototipo del MVP", 18, Color(0.7, 0.7, 0.8)))
	box.add_child(_spacer(16))

	var cfg := GameManager.config
	box.add_child(_button("Jugar como HUNTER  (vs %d Ghosts)" % cfg.ghost_count, func() -> void: GameManager.start_match(DummySpawn.Role.HUNTER), Color(1.0, 0.6, 0.25)))
	box.add_child(_button("Jugar como GHOST  (vs 1 Hunter)", func() -> void: GameManager.start_match(DummySpawn.Role.GHOST), Color(0.45, 0.85, 1.0)))
	box.add_child(_label("Los rivales son maniquíes hasta que esté la IA (Fase 5).", 13, Color(0.6, 0.6, 0.7)))
	box.add_child(_spacer(12))

	box.add_child(_label("Escenarios de prueba (también con 1 / 2 / 3)", 16, Color(0.8, 0.8, 0.85)))
	for entry in TEST_SCENES:
		var path: String = entry[1]
		box.add_child(_button(entry[0], func() -> void: get_tree().change_scene_to_file(path)))
	box.add_child(_spacer(12))

	box.add_child(_button("Abrir carpeta de datos (playtests.csv)", func() -> void: OS.shell_open(PlaytestLogger.get_folder())))
	box.add_child(_button("Salir", func() -> void: get_tree().quit()))


func _button(text: String, callback: Callable, color: Color = Color.WHITE) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(callback)
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
