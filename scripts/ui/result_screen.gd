class_name ResultScreen
extends CanvasLayer
## Pantalla de resultados: ganador, estadísticas, "¿cuánto te has divertido?" y siguiente paso.

## play_again = true -> "Jugar otra vez"; false -> menú principal.
signal finished(play_again: bool)
signal rating_changed(rating: int)

var rating: int = 0

var _title: Label
var _subtitle: Label
var _stats: Label


func _ready() -> void:
	layer = 20
	_build_ui()


func show_result(title: String, player_won: bool, stats_text: String) -> void:
	_title.text = title
	_subtitle.text = "¡Has ganado!" if player_won else "Has perdido"
	_subtitle.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if player_won else Color(1.0, 0.5, 0.45))
	_stats.text = stats_text


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
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_title = _label(36)
	box.add_child(_title)
	_subtitle = _label(24)
	box.add_child(_subtitle)
	_stats = _label(16)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_stats)

	box.add_child(_label(18, "¿Cuánto te has divertido?"))
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
