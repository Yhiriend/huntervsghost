class_name ResultScreen
extends CanvasLayer
## Pantalla de resultados de una ronda / de la partida.
##   - Título, lo que has ganado en la ronda, clasificación, estado de la partida y estadísticas.
##   - Mini cuestionario de diversión (solo al final de la serie; respuestas opcionales al CSV).
##   - Botones configurables (set_choices): emiten choice(id). El primero es el principal (R).

signal choice(id: String)
signal rating_changed(rating: int)

var rating: int = 0
## id del botón principal (lo activa R).
var primary_choice: String = ""
var _answers := {"tension": "", "resultado_por": "", "nota": ""}
var _note: LineEdit

var _title: Label
var _subtitle: Label
var _series: Label
var _table: Label
## Estadísticas en dos columnas (cabe mejor en la pantalla del móvil).
var _stats_left: Label
var _stats_right: Label
var _questionnaire: VBoxContainer
var _buttons: HBoxContainer


func _ready() -> void:
	layer = 110  # Por encima del overlay de depuración (FPS y ayuda).
	_build_ui()


## good: el subtítulo es una buena noticia para el jugador (verde) o no (rojo).
func show_result(title: String, subtitle: String, good: bool, stats_text: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if good else Color(1.0, 0.5, 0.45))
	var lines := stats_text.split("\n")
	var half := ceili(lines.size() / 2.0)
	_stats_left.text = "\n".join(lines.slice(0, half))
	_stats_right.text = "\n".join(lines.slice(half))


## Clasificación (una línea por participante).
func set_table_text(text: String) -> void:
	_table.text = text
	_table.visible = text != ""


## Estado de la partida (vacío = oculto).
func set_series_text(text: String, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	_series.text = text
	_series.visible = text != ""
	_series.add_theme_color_override("font_color", color)


func set_questionnaire_visible(enabled: bool) -> void:
	_questionnaire.visible = enabled


## Botones: [[texto, id], ...]. El primero es el principal.
func set_choices(choices: Array) -> void:
	for child in _buttons.get_children():
		child.queue_free()
	primary_choice = choices[0][1] if not choices.is_empty() else ""
	for entry in choices:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(200, 48)
		button.focus_mode = Control.FOCUS_NONE
		var id: String = entry[1]
		button.pressed.connect(func() -> void: choice.emit(id))
		_buttons.add_child(button)


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
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	_title = _label(30)
	box.add_child(_title)
	_subtitle = _label(22)
	box.add_child(_subtitle)
	_table = _label(16)
	_table.visible = false
	box.add_child(_table)
	_series = _label(19)
	_series.visible = false
	box.add_child(_series)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 24)
	box.add_child(stats_row)
	_stats_left = _label(13)
	_stats_right = _label(13)
	for label in [_stats_left, _stats_right]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_row.add_child(label)

	_questionnaire = VBoxContainer.new()
	_questionnaire.add_theme_constant_override("separation", 6)
	box.add_child(_questionnaire)
	_questionnaire.add_child(_label(17, "¿Cuánto te has divertido?"))
	var rating_row := HBoxContainer.new()
	rating_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for i in range(1, 6):
		var button := Button.new()
		button.text = str(i)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(56, 36)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_rating.bind(i))
		rating_row.add_child(button)
	_questionnaire.add_child(rating_row)
	_questionnaire.add_child(_label(15, "¿Hubo algún momento de tensión?"))
	_questionnaire.add_child(_choice_row("tension", [["Sí", "si"], ["No", "no"]]))
	_questionnaire.add_child(_label(15, "Has ganado o perdido sobre todo por..."))
	_questionnaire.add_child(_choice_row("resultado_por", [["Mis decisiones", "decisiones"], ["Suerte", "suerte"], ["Algo injusto", "injusto"]]))
	_note = LineEdit.new()
	_note.placeholder_text = "¿Qué te ha frustrado o sorprendido? (opcional)"
	_note.custom_minimum_size = Vector2(0, 34)
	_questionnaire.add_child(_note)

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	box.add_child(_buttons)


func _choice_row(key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for option in options:
		var button := Button.new()
		button.text = option[0]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(110, 34)
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
