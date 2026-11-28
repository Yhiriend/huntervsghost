class_name TouchControls
extends Control
## Controles táctiles (multitáctil):
##   - Joystick flotante en la mitad izquierda: aparece donde pones el dedo.
##     Poco inclinado = sigilo; inclinado del todo = correr.
##   - Botón RED (solo Hunter) con el tiempo de recarga dibujado alrededor.
##   - Botón SEÑUELO (solo Presa): deja la pelotita; luego cada toque = pasos falsos allí;
##     mantener = moverla a donde estás.
##   - Botón CAMINAR (mantener): mientras está pulsado se camina aunque el joystick esté a tope.
##   - Botón de acción contextual con el texto de la acción (ABRIR, ESCONDERSE, CAPTURAR...).
##     Las acciones de mantener muestran el progreso alrededor del botón.
##   - En los escenarios de prueba: botones Cambiar (Tab), Espectador (P) y Reiniciar (R).
## PlayerInput lee el estado con las variables estáticas (move, interact_held, take_fire()...).
## En PC se puede probar con el ratón (ajuste "touch controls on pc" en F1).

const BASE_RADIUS := 80.0
const KNOB_RADIUS := 34.0
const FIRE_RADIUS := 68.0
const ACTION_RADIUS := 58.0
const WALK_RADIUS := 44.0
const DECOY_RADIUS := 48.0
const COLOR_DECOY := Color(0.45, 0.75, 1.0, 0.45)
## Los botones aceptan toques un poco fuera de su círculo (dedos imprecisos).
const HIT_SLOP := 1.3
const DEAD_ZONE := 0.15
## Índice de toque que se usa para el ratón al probar en PC.
const MOUSE_INDEX := 1000

const COLOR_BASE := Color(1, 1, 1, 0.12)
const COLOR_RING := Color(1, 1, 1, 0.45)
const COLOR_SNEAK := Color(0.45, 0.75, 1.0, 0.8)
const COLOR_FIRE := Color(1.0, 0.55, 0.2, 0.55)
const COLOR_FIRE_OFF := Color(0.5, 0.5, 0.5, 0.35)
const COLOR_ACTION := Color(0.3, 0.85, 0.5, 0.55)
const COLOR_ACTION_OFF := Color(0.5, 0.5, 0.5, 0.25)
const COLOR_TEXT_OFF := Color(1, 1, 1, 0.4)
## Texto del botón de acción cuando no hay nada que hacer (siempre visible, deshabilitado).
const ACTION_IDLE_TEXT := "ACCIÓN"
const COLOR_PRESSED := Color(1, 1, 1, 0.35)
const COLOR_PROGRESS := Color(1.0, 0.9, 0.3, 0.95)

# --- Estado que lee PlayerInput ---------------------------------------------------
## Dirección del joystick (pantalla: x derecha, y abajo), longitud 0-1.
static var move := Vector2.ZERO
static var interact_held := false
## Botón CAMINAR mantenido.
static var walk_held := false
static var decoy_held := false
static var _decoy_queued := false
static var _fire_queued := false
static var _interact_queued := false

# --- Lo que muestra (lo rellena el HUD) -------------------------------------------
var show_fire := false
## 0 = recién disparada, 1 = lista.
var fire_ready := 1.0
var action_text := ""
var action_hold := false
## Progreso de la acción en curso (0-1) o < 0 si no hay.
var action_progress := -1.0
## Botón SEÑUELO (Presa): visible, ya colocado, y recarga (0 = recién usado, 1 = listo).
var show_decoy := false
var decoy_placed := false
var decoy_ready := 1.0
## Muestra el joystick y los botones (hay un personaje controlado).
var controls_enabled := false

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _fire_index := -1
var _action_index := -1
var _walk_index := -1
var _decoy_index := -1
var _mouse_down := false
var _scenario_bar: HBoxContainer
var _camera_button: Button


## Devuelve true una vez por cada pulsación del botón RED.
static func take_fire() -> bool:
	var value := _fire_queued
	_fire_queued = false
	return value


## Devuelve true una vez por cada pulsación del botón SEÑUELO.
static func take_decoy() -> bool:
	var value := _decoy_queued
	_decoy_queued = false
	return value


## Devuelve true una vez por cada pulsación del botón de acción.
static func take_interact() -> bool:
	var value := _interact_queued
	_interact_queued = false
	return value


static func clear_state() -> void:
	move = Vector2.ZERO
	interact_held = false
	walk_held = false
	decoy_held = false
	_decoy_queued = false
	_fire_queued = false
	_interact_queued = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_scenario_bar = HBoxContainer.new()
	_scenario_bar.anchor_left = 1.0
	_scenario_bar.anchor_right = 1.0
	_scenario_bar.offset_left = -400.0
	_scenario_bar.offset_right = -12.0
	_scenario_bar.offset_top = 64.0
	_scenario_bar.alignment = BoxContainer.ALIGNMENT_END
	_scenario_bar.add_theme_constant_override("separation", 8)
	_scenario_bar.visible = false
	add_child(_scenario_bar)
	_scenario_bar.add_child(_make_action_button("Cambiar", "switch_character"))
	_scenario_bar.add_child(_make_action_button("Espectador", "spectate"))
	_scenario_bar.add_child(_make_action_button("Reiniciar", "reset_scenario"))
	# Espectador en una partida (desempate o Presa capturada): cambiar a quién se mira.
	_camera_button = _make_action_button("Cambiar cámara", "switch_character")
	_camera_button.custom_minimum_size = Vector2(170, 46)
	_camera_button.anchor_left = 1.0
	_camera_button.anchor_right = 1.0
	_camera_button.offset_left = -182.0
	_camera_button.offset_right = -12.0
	_camera_button.offset_top = 64.0
	_camera_button.visible = false
	add_child(_camera_button)
	clear_state()


func _exit_tree() -> void:
	clear_state()


## Botones Cambiar / Espectador / Reiniciar (solo en escenarios de prueba).
func set_scenario_buttons(enabled: bool) -> void:
	_scenario_bar.visible = enabled


## Botón "Cambiar cámara" (espectador en una partida).
func set_camera_button(enabled: bool) -> void:
	_camera_button.visible = enabled and not _scenario_bar.visible


func set_controls_enabled(enabled: bool) -> void:
	if enabled == controls_enabled:
		return
	controls_enabled = enabled
	if not enabled:
		_release_all()


func _process(_delta: float) -> void:
	if not is_visible_in_tree() and (_joy_index >= 0 or _fire_index >= 0 or _action_index >= 0 or _walk_index >= 0 or _decoy_index >= 0):
		_release_all()
	queue_redraw()


# --- Entrada -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not controls_enabled:
		return
	event = make_input_local(event)
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)
	elif not GameManager.is_mobile() and event.device != InputEvent.DEVICE_ID_EMULATION:
		# Pruebas en PC: el ratón hace de dedo (ignorando los clics emulados desde toques reales).
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = event.pressed
			_on_touch(MOUSE_INDEX, event.position, event.pressed)
		elif event is InputEventMouseMotion and _mouse_down:
			_on_drag(MOUSE_INDEX, event.position)


func _on_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if index == _joy_index:
			_joy_index = -1
			move = Vector2.ZERO
		elif index == _fire_index:
			_fire_index = -1
		elif index == _action_index:
			_action_index = -1
			interact_held = false
		elif index == _walk_index:
			_walk_index = -1
			walk_held = false
		elif index == _decoy_index:
			_decoy_index = -1
			decoy_held = false
		return

	if show_fire and _fire_index < 0 and pos.distance_to(_fire_center()) <= FIRE_RADIUS * _scale() * HIT_SLOP:
		_fire_index = index
		_fire_queued = true
		get_viewport().set_input_as_handled()
	elif _action_index < 0 and pos.distance_to(_action_center()) <= ACTION_RADIUS * _scale() * HIT_SLOP:
		# Siempre visible; deshabilitado (sin acción) solo se traga el toque.
		if action_text != "":
			_action_index = index
			_interact_queued = true
			interact_held = true
		get_viewport().set_input_as_handled()
	elif show_decoy and _decoy_index < 0 and pos.distance_to(_decoy_center()) <= DECOY_RADIUS * _scale() * HIT_SLOP:
		_decoy_index = index
		_decoy_queued = true
		decoy_held = true
		get_viewport().set_input_as_handled()
	elif _walk_index < 0 and pos.distance_to(_walk_center()) <= WALK_RADIUS * _scale() * HIT_SLOP:
		_walk_index = index
		walk_held = true
		get_viewport().set_input_as_handled()
	elif _joy_index < 0 and _in_joystick_zone(pos):
		_joy_index = index
		_joy_center = pos
		move = Vector2.ZERO
		get_viewport().set_input_as_handled()


func _on_drag(index: int, pos: Vector2) -> void:
	if index != _joy_index:
		return
	var radius := BASE_RADIUS * _scale()
	var offset := pos - _joy_center
	if offset.length() > radius:
		# La base sigue al dedo: no hace falta volver al centro para cambiar de dirección.
		_joy_center = pos - offset.normalized() * radius
		offset = pos - _joy_center
	var value := offset / radius
	move = Vector2.ZERO if value.length() < DEAD_ZONE else value.limit_length(1.0)
	get_viewport().set_input_as_handled()


func _release_all() -> void:
	_joy_index = -1
	_fire_index = -1
	_action_index = -1
	_walk_index = -1
	_decoy_index = -1
	_mouse_down = false
	clear_state()


# --- Geometría ---------------------------------------------------------------------

func _scale() -> float:
	return GameManager.config.touch_ui_scale


func _in_joystick_zone(pos: Vector2) -> bool:
	return pos.x < size.x * 0.5 and pos.y > size.y * 0.2


func _joy_rest_center() -> Vector2:
	var margin := (BASE_RADIUS + 50.0) * _scale()
	return Vector2(margin, size.y - margin)


func _fire_center() -> Vector2:
	var margin := (FIRE_RADIUS + 40.0) * _scale()
	return Vector2(size.x - margin, size.y - margin)


func _action_center() -> Vector2:
	if not show_fire:
		return _fire_center()
	var s := _scale()
	return _fire_center() + Vector2(-(FIRE_RADIUS + ACTION_RADIUS + 30.0) * s, -40.0 * s)


## Encima del botón de la esquina (RED, o acción si no hay red): a mano del pulgar derecho.
func _walk_center() -> Vector2:
	var s := _scale()
	var below_radius := FIRE_RADIUS if show_fire else ACTION_RADIUS
	return _fire_center() + Vector2(0, -(below_radius + WALK_RADIUS + 34.0) * s)


## A la izquierda del botón de la esquina (sin RED, la Presa tiene ahí el de acción).
func _decoy_center() -> Vector2:
	var s := _scale()
	return _fire_center() + Vector2(-(ACTION_RADIUS + DECOY_RADIUS + 30.0) * s, -30.0 * s)


# --- Dibujo ------------------------------------------------------------------------

func _draw() -> void:
	if not controls_enabled:
		return
	var s := _scale()
	var font := get_theme_default_font()

	# Joystick
	var base := _joy_center if _joy_index >= 0 else _joy_rest_center()
	var radius := BASE_RADIUS * s
	var walking := walk_held and move != Vector2.ZERO
	var sneaking := walking or (move != Vector2.ZERO and move.length() < GameManager.config.touch_sneak_threshold)
	draw_circle(base, radius, COLOR_BASE)
	draw_arc(base, radius, 0.0, TAU, 48, COLOR_SNEAK if sneaking else COLOR_RING, 3.0 * s, true)
	# Marca del límite de sigilo.
	draw_arc(base, radius * GameManager.config.touch_sneak_threshold, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.5 * s, true)
	draw_circle(base + move * radius, KNOB_RADIUS * s, COLOR_SNEAK if sneaking else COLOR_PRESSED)
	if _joy_index >= 0:
		var label := "CAMINAR" if walking else ("SIGILO" if sneaking else ("CORRER" if move != Vector2.ZERO else ""))
		_draw_text(font, base + Vector2(0, -radius - 14.0 * s), label, 16, s)

	# Botón SEÑUELO (Presa)
	if show_decoy:
		var decoy_center := _decoy_center()
		var decoy_r := DECOY_RADIUS * s
		var decoy_is_ready := decoy_ready >= 1.0 or not decoy_placed
		draw_circle(decoy_center, decoy_r, COLOR_PRESSED if _decoy_index >= 0 else (COLOR_DECOY if decoy_is_ready else COLOR_FIRE_OFF))
		draw_arc(decoy_center, decoy_r, 0.0, TAU, 40, COLOR_RING, 3.0 * s, true)
		if not decoy_is_ready:
			draw_arc(decoy_center, decoy_r + 6.0 * s, -PI / 2.0, -PI / 2.0 + TAU * decoy_ready, 40, COLOR_PROGRESS, 5.0 * s, true)
		_draw_icon(Icons.get_icon("senuelo"), decoy_center + Vector2(0, -8.0 * s), 40.0 * s, Color(1, 1, 1, 1.0 if decoy_is_ready else 0.5))
		_draw_text(font, decoy_center + Vector2(0, 30.0 * s), "SEÑUELO", 11, s)
		_draw_text(font, decoy_center + Vector2(0, decoy_r + 18.0 * s), "pasos · mantén: mover" if decoy_placed else "dejar aquí", 10, s, COLOR_TEXT_OFF)

	# Botón CAMINAR
	var walk_center := _walk_center()
	var walk_r := WALK_RADIUS * s
	draw_circle(walk_center, walk_r, COLOR_SNEAK if walk_held else COLOR_BASE)
	draw_arc(walk_center, walk_r, 0.0, TAU, 40, COLOR_SNEAK if walk_held else COLOR_RING, 3.0 * s, true)
	_draw_icon(Icons.get_icon("caminar"), walk_center + Vector2(0, -7.0 * s), 34.0 * s)
	_draw_text(font, walk_center + Vector2(0, 27.0 * s), "CAMINAR", 10, s)

	# Botón RED
	if show_fire:
		var center := _fire_center()
		var r := FIRE_RADIUS * s
		var net_ready := fire_ready >= 1.0
		draw_circle(center, r, (COLOR_PRESSED if _fire_index >= 0 else COLOR_FIRE) if net_ready else COLOR_FIRE_OFF)
		draw_arc(center, r, 0.0, TAU, 48, COLOR_RING, 3.0 * s, true)
		if not net_ready:
			draw_arc(center, r + 6.0 * s, -PI / 2.0, -PI / 2.0 + TAU * fire_ready, 48, COLOR_PROGRESS, 5.0 * s, true)
		_draw_icon(Icons.get_icon("red"), center + Vector2(0, -10.0 * s), 62.0 * s, Color(1, 1, 1, 1.0 if net_ready else 0.5))
		_draw_text(font, center + Vector2(0, 42.0 * s), "RED", 16, s)

	# Botón de acción: siempre visible; gris y sin efecto si no hay nada que hacer.
	var center := _action_center()
	var r := ACTION_RADIUS * s
	if action_text == "":
		draw_circle(center, r, COLOR_ACTION_OFF)
		draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.2), 3.0 * s, true)
		_draw_icon(Icons.for_action(""), center + Vector2(0, -8.0 * s), 40.0 * s, COLOR_TEXT_OFF)
		_draw_text(font, center + Vector2(0, 34.0 * s), ACTION_IDLE_TEXT, 12, s, COLOR_TEXT_OFF)
	else:
		draw_circle(center, r, COLOR_PRESSED if _action_index >= 0 else COLOR_ACTION)
		draw_arc(center, r, 0.0, TAU, 48, COLOR_RING, 3.0 * s, true)
		if action_progress >= 0.0:
			draw_arc(center, r + 6.0 * s, -PI / 2.0, -PI / 2.0 + TAU * clampf(action_progress, 0.0, 1.0), 48, COLOR_PROGRESS, 5.0 * s, true)
		_draw_icon(Icons.for_action(action_text), center + Vector2(0, -9.0 * s), 44.0 * s)
		_draw_text(font, center + Vector2(0, 34.0 * s), action_text, 13 if action_text.length() <= 8 else 11, s)
		if action_hold:
			_draw_text(font, center + Vector2(0, r + 20.0 * s), "mantén", 12, s)


## Icono centrado en pos, con una sombra para que se lea sobre cualquier fondo.
func _draw_icon(icon: Texture2D, pos: Vector2, icon_size: float, color: Color = Color.WHITE) -> void:
	if icon == null:
		return
	var rect := Rect2(pos - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size)
	draw_texture_rect(icon, Rect2(rect.position + Vector2(1.5, 2.0), rect.size), false, Color(0, 0, 0, 0.45 * color.a))
	draw_texture_rect(icon, rect, false, color)


func _draw_text(font: Font, pos: Vector2, text: String, font_size: int, s: float, color: Color = Color.WHITE) -> void:
	if text == "":
		return
	var px := int(font_size * s)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := pos - Vector2(width / 2.0, 0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(4 * s), Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _make_action_button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(118, 46)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(func() -> void:
		for pressed in [true, false]:
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = pressed
			Input.parse_input_event(ev))
	Icons.apply(button)
	return button
