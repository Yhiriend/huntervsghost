class_name ResultScreen
extends CanvasLayer
## Pantalla de resultados: ganador, estadísticas, mini cuestionario de diversión y siguiente paso.
## Las respuestas se guardan en playtests.csv (todas son opcionales).

## play_again = true -> "Jugar otra vez"; false -> menú principal.
signal finished(play_again: bool)
signal rating_changed(rating: int)

var rating: int = 0
var _answers := {"tension": "", "resultado_por": "", "nota": ""}
var _note: LineEdit

var _title: Label
var _subtitle: Label
var _stats: Label


func _ready() -> void:
	layer = 110  # Por encima del overlay de depuración (FPS y ayuda).
	_build_ui()


func show_result(title: String, player_won: bool, stats_text: String) -> void:
	_title.text = title
	_subtitle.text = "¡Has ganado!" if player_won else "Has perdido"
	_subtitle.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if player_won else Color(1.0, 0.5, 0.45))
	_stats.text = stats_text


## Respuestas del cuestionario (columnas del CSV).
func get_answers() -> Dictionary:
	var answers := _answers.duplicate()
	answers["nota"] = _note.text.strip_edges() if _note else ""
	return answers


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_title = _label(36)
	box.add_child(_title)
	_subtitle = _label(24)
	box.add_child(_subtitle)
	_stats = _label(14)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_stats)

	box.add_child(_label(17, "¿Cuánto te has divertido?"))
	var rating_row := HBoxContainer.new()
	rating_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for i in range(1, 6):
		var button := Button.new()
		button.text = str(i)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(56, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_rating.bind(i))
		rating_row.add_child(button)
	box.add_child(rating_row)

	box.add_child(_label(15, "¿Hubo algún momento de tensión?"))
	box.add_child(_choice_row("tension", [["Sí", "si"], ["No", "no"]]))
	box.add_child(_label(15, "Has ganado o perdido sobre todo por..."))
	box.add_child(_choice_row("resultado_por", [["Mis decisiones", "decisiones"], ["Suerte", "suerte"], ["Algo injusto", "injusto"]]))
	_note = LineEdit.new()
	_note.placeholder_text = "¿Qué te ha frustrado o sorprendido? (opcional)"
	_note.custom_minimum_size = Vector2(0, 36)
	box.add_child(_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var again := Button.new()
	again.text = "Jugar otra vez (R)"
	again.custom_minimum_size = Vector2(200, 48)
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void: finished.emit(true))
	buttons.add_child(again)
	var menu := Button.new()
	menu.text = "Menú principal (Esc)"
	menu.custom_minimum_size = Vector2(200, 48)
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func() -> void: finished.emit(false))
	buttons.add_child(menu)
	box.add_child(buttons)


func _choice_row(key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for option in options:
		var button := Button.new()
		button.text = option[0]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(110, 36)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _answers[key] = option[1])
		row.add_child(button)
	return row


func _on_rating(value: int) -> void:
	rating = value
	rating_changed.emit(value)


func _label(font_size: int, text: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label
