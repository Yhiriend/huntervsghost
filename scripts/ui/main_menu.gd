extends Control
## Menú principal por niveles: en cada pantalla solo las opciones de ese contexto.
##   Inicio -> Contra la IA (bando + dificultad) | Multijugador (Lobby) | Compartir | Más opciones
##   Más opciones -> Resultados de las pruebas | Escenarios de prueba | créditos
## Esc / Atrás de Android vuelven a la pantalla anterior (go_back, lo llama DebugOverlay).

const TEST_SCENES := [
	["Prototype01 · casa libre", "res://scenes/test/Prototype01.tscn"],
	["TestCazador · 5 Presas maniquí", "res://scenes/test/TestHunter.tscn"],
	["TestPresa · Cazadores que patrullan", "res://scenes/test/TestGhost.tscn"],
	["TestAI · IA contra IA (espectador)", "res://scenes/test/TestAI.tscn"],
]
const TITLE_COLOR := Color(0.45, 0.85, 1.0)
const MUTED := Color(0.7, 0.7, 0.8)

var _notice: Label
## nombre -> VBoxContainer; y a qué pantalla vuelve cada una.
var _pages: Dictionary = {}
var _parent: Dictionary = {}
var _current := "inicio"


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(460, 0)
	page.add_theme_constant_override("separation", 6)
	center.add_child(page)
	page.add_child(_label("¿CAZADOR O PRESA?", 48, TITLE_COLOR))
	page.add_child(_spacer(12))

	# Inicio
	var home := _page("inicio", "")
	home.add_child(_button("Jugar contra la IA", _show.bind("ia"), Color(1.0, 0.6, 0.25)))
	home.add_child(_button("Multijugador", func() -> void: get_tree().change_scene_to_file("res://scenes/main/Lobby.tscn"), Color(0.8, 0.6, 1.0)))
	if ApkShare.is_available():
		home.add_child(_button("Compartir el juego por WhatsApp", _share_apk, Color(0.45, 0.95, 0.55)))
	home.add_child(_button("Más opciones", _show.bind("mas")))
	home.add_child(_button("Salir", func() -> void: get_tree().quit(), Color(0.7, 0.7, 0.75)))

	# Contra la IA
	var ai := _page("ia", "inicio")
	ai.add_child(_label("Contra la IA", 22, MUTED))
	ai.add_child(_button("Empezar de CAZADOR", func() -> void: GameManager.start_match(DummySpawn.Role.HUNTER), Color(1.0, 0.6, 0.25)))
	ai.add_child(_button("Empezar de PRESA", func() -> void: GameManager.start_match(DummySpawn.Role.GHOST), TITLE_COLOR))
	ai.add_child(_difficulty_row())
	ai.add_child(_label("Cada uno es Cazador una vez; gana quien más puntos sume.", 14, Color(0.55, 0.55, 0.65)))
	ai.add_child(_back_button())

	# Más opciones
	var more := _page("mas", "inicio")
	more.add_child(_label("Más opciones", 22, MUTED))
	more.add_child(_button("Resultados de las pruebas", func() -> void: get_tree().change_scene_to_file("res://scenes/main/PlaytestSummary.tscn"), Color(0.7, 1.0, 0.7)))
	more.add_child(_button("Escenarios de prueba", _show.bind("pruebas")))
	more.add_child(_label("Música: \"Mystery & Crime Background Music\" — Oak Hill", 13, Color(0.55, 0.55, 0.65)))
	more.add_child(_back_button())

	# Escenarios de prueba (los atajos 1-4 solo existen con teclado).
	var tests := _page("pruebas", "mas")
	tests.add_child(_label("Escenarios de prueba" + ("" if GameManager.is_touch_mode() else "  (teclas 1-4)"), 22, MUTED))
	for entry in TEST_SCENES:
		var path: String = entry[1]
		tests.add_child(_button(entry[0], func() -> void: get_tree().change_scene_to_file(path)))
	tests.add_child(_back_button())

	for name in _pages:
		page.add_child(_pages[name])
	_notice = _label(GameManager.notice, 16, Color(1.0, 0.75, 0.45))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = GameManager.notice != ""
	page.add_child(_notice)
	GameManager.notice = ""
	_show("inicio")


## Vuelve a la pantalla anterior. false si ya está en el inicio.
func go_back() -> bool:
	if _parent.get(_current, "") == "":
		return false
	_show(_parent[_current])
	return true


func current_page() -> String:
	return _current


func _show(name: String) -> void:
	_current = name
	for key in _pages:
		_pages[key].visible = key == name
	if name != "inicio" and _notice:
		_notice.visible = false


func _page(name: String, parent: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_pages[name] = box
	_parent[name] = parent
	return box


func _back_button() -> Button:
	return _button("Volver", go_back, Color(0.7, 0.7, 0.75))


func _share_apk() -> void:
	_notice.text = "Preparando el APK..."
	_notice.visible = true
	await get_tree().process_frame  # Que se vea el aviso antes de la copia (unos 30 MB la primera vez).
	var error := ApkShare.share()
	_notice.text = error
	_notice.visible = error != ""


## Dificultad de la IA rival: Fácil / Normal / Difícil.
func _difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = "IA rival:"
	label.add_theme_color_override("font_color", MUTED)
	row.add_child(label)
	var group := ButtonGroup.new()
	for level in [GameManager.Difficulty.EASY, GameManager.Difficulty.NORMAL, GameManager.Difficulty.HARD]:
		var button := Button.new()
		button.text = ["Fácil", "Normal", "Difícil"][level]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = level == GameManager.difficulty
		button.custom_minimum_size = Vector2(96, 40)
		button.pressed.connect(GameManager.set_difficulty.bind(level))
		row.add_child(button)
	return row


func _button(text: String, callback: Callable, color: Color = Color.WHITE) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 20)
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
