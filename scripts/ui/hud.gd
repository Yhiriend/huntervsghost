class_name HUD
extends CanvasLayer
## HUD mínimo: Ghosts libres, estado de la red / del Ghost, botón contextual,
## barra de progreso (captura / registro) y mensajes temporales.

const MESSAGE_FADE_TIME := 0.5

var _controlled: CharacterBase
var _timer_label: Label
var _round_label: Label
var _blackout: ColorRect
var _blackout_label: Label
var _ghosts_label: Label
var _status_label: Label
var _prompt_label: Label
var _capture_bar: ProgressBar
var _message_label: Label
var _message_time_left: float = 0.0
## Joystick y botones táctiles (visibles en el móvil o con touch_controls_on_pc).
var touch: TouchControls
## Muestra en táctil los botones Cambiar / Espectador / Reiniciar.
var scenario_buttons: bool = false


func _ready() -> void:
	layer = 10
	_build_ui()


func set_controlled(character: CharacterBase) -> void:
	_controlled = character


## Ronda y marcador de la serie ("" lo oculta).
func set_round_text(text: String) -> void:
	_round_label.text = text


## Temporizador de la partida ("" lo oculta).
func set_timer_text(text: String, urgent: bool = false) -> void:
	_timer_label.text = text
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if urgent else Color.WHITE)


## Pantalla negra (preparación del Hunter: no puede ver dónde se esconden los Ghosts).
func set_blackout(enabled: bool, text: String = "") -> void:
	_blackout.visible = enabled
	_blackout_label.text = text


func show_message(text: String, duration: float = 2.0) -> void:
	_message_label.text = text
	_message_time_left = duration


func _process(delta: float) -> void:
	_update_ghost_count()
	touch.visible = GameManager.is_touch_mode()
	touch.set_scenario_buttons(scenario_buttons)
	touch.show_fire = false
	touch.action_text = ""
	touch.action_progress = -1.0
	touch.set_controls_enabled(_controlled != null and not _controlled.frozen and _controlled.is_active())
	_update_status()
	_message_time_left = maxf(0.0, _message_time_left - delta)
	_message_label.modulate.a = clampf(_message_time_left / MESSAGE_FADE_TIME, 0.0, 1.0)


func _update_ghost_count() -> void:
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	var free_count := 0
	for node in ghosts:
		if (node as Ghost).state != Ghost.State.CAPTURED:
			free_count += 1
	_ghosts_label.text = "Presas libres: %d / %d" % [free_count, ghosts.size()]


func _update_status() -> void:
	_prompt_label.text = ""
	_capture_bar.visible = false
	_status_label.text = ""
	if _controlled == null:
		return
	if _controlled.frozen:
		return

	if _controlled is Hunter:
		var hunter := _controlled as Hunter
		_status_label.text = "Red: LISTA" if hunter.is_net_ready() else "Red: %.1f s" % hunter.net_cooldown_left
		touch.show_fire = true
		touch.fire_ready = 1.0 - hunter.net_cooldown_left / maxf(GameManager.config.net_cooldown, 0.001)
		if hunter.capture_target:
			_show_progress("CAPTURANDO...", hunter.capture_progress / GameManager.config.capture_time, "CAPTURAR")
			return
		if hunter.interact_target == null and hunter.find_capturable_ghost():
			_show_prompt("CAPTURAR", true)
			return
	elif _controlled is Ghost:
		var ghost := _controlled as Ghost
		match ghost.state:
			Ghost.State.FREE:
				_status_label.text = "Libre" if ghost.can_hide() else "Libre · no puedes esconderte (%.1f s)" % ghost.hide_cooldown_left
			Ghost.State.NETTED:
				_status_label.text = "¡ATRAPADO! Te liberas en %.1f s" % ghost.net_time_left
			Ghost.State.HIDDEN:
				_status_label.text = "Escondido en el armario"
			Ghost.State.CAPTURED:
				_status_label.text = "Capturado (Tab para cambiar de personaje)"

	_update_interaction_prompt()


## Botón contextual: "[E] ABRIR", "Mantén [E] · REGISTRAR" y su barra de progreso.
func _update_interaction_prompt() -> void:
	var target := _controlled.interact_target
	if target:
		var hold := target.get_hold_time(_controlled)
		var prompt := target.get_prompt(_controlled)
		_show_progress("%s..." % prompt, _controlled.interact_progress / maxf(hold, 0.001), prompt)
		return
	var item := _controlled.find_interactable()
	if item == null:
		return
	_show_prompt(item.get_prompt(_controlled), item.get_hold_time(_controlled) > 0.0)


## Acción disponible: texto con la tecla en PC; en táctil, el texto va en el botón.
func _show_prompt(action: String, hold: bool) -> void:
	touch.action_text = action
	touch.action_hold = hold
	if not touch.visible:
		_prompt_label.text = ("Mantén [E] · %s" if hold else "[E] %s") % action


func _show_progress(text: String, progress: float, action: String) -> void:
	_prompt_label.text = text
	_capture_bar.visible = true
	_capture_bar.value = clampf(progress, 0.0, 1.0)
	touch.action_text = action
	touch.action_hold = true
	touch.action_progress = clampf(progress, 0.0, 1.0)


# --- Construcción --------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_blackout = ColorRect.new()
	_blackout.color = Color(0.01, 0.01, 0.03, 0.97)
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.visible = false
	root.add_child(_blackout)
	_blackout_label = _make_label(40)
	_blackout_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_blackout.add_child(_blackout_label)

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -300.0
	top.offset_right = 300.0
	top.offset_top = 10.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_round_label = _make_label(18)
	_round_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	top.add_child(_round_label)
	_timer_label = _make_label(34)
	top.add_child(_timer_label)
	_ghosts_label = _make_label(24)
	top.add_child(_ghosts_label)
	_status_label = _make_label(18)
	top.add_child(_status_label)
	_message_label = _make_label(26)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	top.add_child(_message_label)

	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -200.0
	bottom.offset_right = 200.0
	bottom.offset_top = -130.0
	bottom.offset_bottom = -50.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_prompt_label = _make_label(22)
	bottom.add_child(_prompt_label)
	_capture_bar = ProgressBar.new()
	_capture_bar.max_value = 1.0
	_capture_bar.show_percentage = false
	_capture_bar.custom_minimum_size = Vector2(0, 18)
	_capture_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_bar.visible = false
	bottom.add_child(_capture_bar)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.visible = false
	root.add_child(touch)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
