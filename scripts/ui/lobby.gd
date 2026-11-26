extends Control
## Multijugador en red local: crear una sala, buscar las de la WiFi o unirse por IP,
## y la sala de espera (jugadores + IA hasta completar 1 Cazador y 3 Presas).

const TITLE_COLOR := Color(0.45, 0.85, 1.0)
const MUTED := Color(0.7, 0.7, 0.8)

var _browse: VBoxContainer
var _room: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _rooms_box: VBoxContainer
var _status: Label
var _room_title: Label
var _room_info: Label
var _slots: VBoxContainer
var _host_box: VBoxContainer
var _client_wait: Label


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(560, 0)
	page.add_theme_constant_override("separation", 8)
	center.add_child(page)
	_build_browse(page)
	_build_room(page)
	_status = _label("", 16, Color(1.0, 0.75, 0.45))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)

	Net.lobby_changed.connect(_refresh_room)
	Net.rooms_changed.connect(_refresh_rooms)
	Net.joined.connect(_show_room)
	Net.join_failed.connect(func() -> void: _set_status("No se pudo conectar con la sala."))
	Net.session_ended.connect(func(reason: String) -> void:
		_show_browse()
		_set_status(reason))
	if Net.is_active():
		_show_room()  # Vuelta a la sala tras una partida.
	else:
		_show_browse()


func _exit_tree() -> void:
	Net.stop_discovery()


# --- Buscar / crear ----------------------------------------------------------------

func _build_browse(page: VBoxContainer) -> void:
	_browse = VBoxContainer.new()
	_browse.add_theme_constant_override("separation", 10)
	page.add_child(_browse)
	_browse.add_child(_label("MULTIJUGADOR · RED LOCAL", 34, TITLE_COLOR))
	_browse.add_child(_label("Todos en la misma WiFi. Siempre 1 Cazador y 3 Presas: la IA ocupa los huecos.", 15, MUTED))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_browse.add_child(name_row)
	name_row.add_child(_label("Tu nombre:", 17, Color.WHITE))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = 14
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, 40)
	_name_edit.text_changed.connect(func(text: String) -> void: Net.set_player_name(text))
	name_row.add_child(_name_edit)

	_browse.add_child(_button("Crear sala", _on_create, Color(1.0, 0.6, 0.25)))
	_browse.add_child(_label("Salas en tu WiFi (toca una para unirte):", 16, MUTED))
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	_browse.add_child(_rooms_box)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	_browse.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP del anfitrión (p. ej. 192.168.1.20)"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size = Vector2(0, 40)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_ip())
	ip_row.add_child(_ip_edit)
	var join := _button("Unirse por IP", _on_join_ip)
	join.custom_minimum_size = Vector2(170, 40)
	ip_row.add_child(join)
	_browse.add_child(_button("Volver al menú (Esc)", GameManager.go_to_menu))


func _show_browse() -> void:
	_browse.visible = true
	_room.visible = false
	Net.start_discovery()
	_refresh_rooms()


func _refresh_rooms() -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	if Net.rooms.is_empty():
		var text := "Buscando salas..." if Net.is_discovering() else "No se pueden buscar salas aquí: únete por IP."
		_rooms_box.add_child(_label(text, 15, Color(0.55, 0.55, 0.65)))
		return
	for ip in Net.rooms:
		var info: Dictionary = Net.rooms[ip]
		var text := "%s   (%d/%d)   %s" % [info["name"], info["players"], Net.MAX_PLAYERS, ip]
		var port: int = info["port"]
		_rooms_box.add_child(_button(text, func() -> void: _join(ip, port), Color(0.45, 0.85, 1.0)))


func _on_create() -> void:
	Net.set_player_name(_name_edit.text)
	var err := Net.host_room()
	if err != OK:
		_set_status("No se pudo crear la sala (%s). ¿Hay otra abierta en este dispositivo?" % error_string(err))
		return
	_show_room()


func _on_join_ip() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_valid_ip_address():
		_join(ip, Net.PORT)
	else:
		_set_status("Escribe una IP válida (la muestra el anfitrión en su sala).")


func _join(ip: String, port: int) -> void:
	Net.set_player_name(_name_edit.text)
	var err := Net.join_room(ip, port)
	_set_status("Conectando con %s..." % ip if err == OK else "No se pudo conectar (%s)." % error_string(err))


# --- Sala de espera ----------------------------------------------------------------

func _build_room(page: VBoxContainer) -> void:
	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 10)
	page.add_child(_room)
	_room_title = _label("", 32, TITLE_COLOR)
	_room.add_child(_room_title)
	_room_info = _label("", 15, MUTED)
	_room_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room.add_child(_room_info)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 4)
	_room.add_child(_slots)
	_host_box = VBoxContainer.new()
	_host_box.add_theme_constant_override("separation", 8)
	_room.add_child(_host_box)
	_host_box.add_child(_difficulty_row())
	_host_box.add_child(_button("Empezar partida", func() -> void: Net.start_match(), Color(0.5, 1.0, 0.55)))
	_client_wait = _label("Esperando a que el anfitrión empiece la partida...", 16, MUTED)
	_room.add_child(_client_wait)
	_room.add_child(_button("Salir de la sala", func() -> void:
		Net.leave()
		_show_browse()))


func _show_room() -> void:
	Net.stop_discovery()
	_browse.visible = false
	_room.visible = true
	_set_status("")
	_refresh_room()


func _refresh_room() -> void:
	if not _room.visible:
		return
	_room_title.text = Net.room_name
	_host_box.visible = Net.is_host()
	_client_wait.visible = not Net.is_host()
	if Net.is_host():
		var ips := Net.local_ips()
		_room_info.text = "Los demás pueden encontrarla en \"Salas en tu WiFi\" o unirse con la IP: %s" % (", ".join(ips) if not ips.is_empty() else "(sin red local)")
	else:
		_room_info.text = "Conectado. Las rondas las decide el anfitrión."
	for child in _slots.get_children():
		child.queue_free()
	for i in Net.MAX_PLAYERS:
		var text := "%d.  IA (puesto libre)" % (i + 1)
		var color := Color(0.55, 0.55, 0.65)
		if i < Net.player_order.size():
			var peer: int = Net.player_order[i]
			text = "%d.  %s%s%s" % [i + 1, Net.name_of(peer), "  (anfitrión)" if peer == 1 else "", "  ← tú" if peer == Net.local_peer() else ""]
			color = Color.WHITE
		_slots.add_child(_label(text, 19, color))


func _difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_label("IA:", 16, MUTED))
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


# --- Utilidades --------------------------------------------------------------------

func _set_status(text: String) -> void:
	_status.text = text


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
