extends Control
## Menú principal mínimo: elegir bando, ir a los escenarios de prueba o abrir los datos de partidas.

const TEST_SCENES := [
	["Prototype01 · casa libre", "res://scenes/test/Prototype01.tscn"],
	["TestCazador · 5 Presas maniquí", "res://scenes/test/TestHunter.tscn"],
	["TestPresa · Cazadores que patrullan", "res://scenes/test/TestGhost.tscn"],
	["TestAI · IA contra IA (espectador)", "res://scenes/test/TestAI.tscn"],
]


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Dos columnas para que quepa en un móvil en horizontal: jugar | escenarios de prueba.
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	center.add_child(page)
	page.add_child(_label("¿CAZADOR O PRESA?", 48, Color(0.45, 0.85, 1.0)))
	page.add_child(_label("Prototipo del MVP", 18, Color(0.7, 0.7, 0.8)))
	page.add_child(_spacer(14))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	page.add_child(columns)
	var play := _column()
	columns.add_child(play)
	var tests := _column()
	columns.add_child(tests)

	var cfg := GameManager.config
	play.add_child(_label("Partida", 16, Color(0.8, 0.8, 0.85)))
	play.add_child(_button("Jugar como CAZADOR  (vs %d Presas)" % cfg.ghost_count, func() -> void: GameManager.start_match(DummySpawn.Role.HUNTER), Color(1.0, 0.6, 0.25)))
	play.add_child(_button("Jugar como PRESA  (vs 1 Cazador)", func() -> void: GameManager.start_match(DummySpawn.Role.GHOST), Color(0.45, 0.85, 1.0)))
	play.add_child(_difficulty_row())
	play.add_child(_spacer(8))
	play.add_child(_button("Resultados de las pruebas", func() -> void: get_tree().change_scene_to_file("res://scenes/main/PlaytestSummary.tscn"), Color(0.7, 1.0, 0.7)))
	play.add_child(_button("Salir", func() -> void: get_tree().quit()))

	# Los atajos 1-4 solo existen con teclado.
	tests.add_child(_label("Escenarios de prueba" + ("" if GameManager.is_touch_mode() else "  (teclas 1-4)"), 16, Color(0.8, 0.8, 0.85)))
	for entry in TEST_SCENES:
		var path: String = entry[1]
		tests.add_child(_button(entry[0], func() -> void: get_tree().change_scene_to_file(path)))

	page.add_child(_spacer(10))
	page.add_child(_label("Música: \"Mystery & Crime Background Music\" — Oak Hill", 13, Color(0.55, 0.55, 0.65)))


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(400, 0)
	column.add_theme_constant_override("separation", 10)
	return column


## Dificultad de la IA rival: Fácil / Normal / Difícil.
func _difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = "IA rival:"
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	row.add_child(label)
	var group := ButtonGroup.new()
	for level in [GameManager.Difficulty.EASY, GameManager.Difficulty.NORMAL, GameManager.Difficulty.HARD]:
		var button := Button.new()
		button.text = ["Fácil", "Normal", "Difícil"][level]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = level == GameManager.difficulty
		button.custom_minimum_size = Vector2(96, 34)
		button.pressed.connect(GameManager.set_difficulty.bind(level))
		row.add_child(button)
	return row


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
