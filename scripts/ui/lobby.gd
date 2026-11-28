extends Control
## Multijugador por pantallas: elegir (nombre + modo) -> Por internet (crear sala / unirse con
## código) o En tu WiFi (crear / salas encontradas / IP) -> sala de espera (jugadores + IA hasta
## 1 Cazador y 3 Presas). Esc / Atrás vuelven a la pantalla anterior (go_back).

const TITLE_COLOR := Color(0.45, 0.85, 1.0)
const MUTED := Color(0.7, 0.7, 0.8)
## Salas de internet que caben en la pantalla; el resto, con su código.
const ONLINE_ROOMS_SHOWN := 4

## Pantallas de búsqueda: "elegir", "online", "local".
var _pages: Dictionary = {}
var _current := "elegir"
## Modo de la última sala ("online" / "local"): al salir de ella se vuelve a esa pantalla.
var _mode := "elegir"
var _room: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _code_edit: LineEdit
var _server_edit: LineEdit
var _share_code: Button
var _rooms_box: VBoxContainer
var _online_rooms_box: VBoxContainer
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
	Net.online_rooms_changed.connect(_refresh_online_rooms)
	Net.joined.connect(_show_room)
	Net.join_failed.connect(func() -> void:
		_set_status(Net.last_error if Net.last_error != "" else "No se pudo conectar con la sala."))
	Net.session_ended.connect(func(reason: String) -> void:
		_show_page(_mode)
		_set_status(reason))
	if Net.is_active():
		_mode = "online" if Net.online else "local"
		_show_room()  # Vuelta a la sala tras una partida.
	else:
		_show_page("elegir")


func _exit_tree() -> void:
	Net.stop_discovery()
	Net.stop_online_browse()


# --- Buscar / crear ----------------------------------------------------------------

func _build_browse(page: VBoxContainer) -> void:
	# Elegir: nombre y modo.
	var choose := _page("elegir", page)
	choose.add_child(_label("MULTIJUGADOR", 34, TITLE_COLOR))
	choose.add_child(_label("Siempre 1 Cazador y 3 Presas: la IA ocupa los huecos.", 15, MUTED))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	choose.add_child(name_row)
	name_row.add_child(_label("Tu nombre:", 17, Color.WHITE))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = 14
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.text_changed.connect(func(text: String) -> void: Net.set_player_name(text))
	name_row.add_child(_name_edit)
	choose.add_child(_button("Por internet  ·  WiFi o datos", _show_page.bind("online"), Color(0.8, 0.6, 1.0)))
	choose.add_child(_button("En tu WiFi  ·  red local", _show_page.bind("local"), Color(0.5, 1.0, 0.55)))
	choose.add_child(_back_button("Volver al menú"))

	# Por internet: sala con código en el servidor de salas.
	var online := _page("online", page)
	online.add_child(_label("POR INTERNET", 34, Color(0.8, 0.6, 1.0)))
	online.add_child(_button("Crear sala", _on_create_online, Color(1.0, 0.6, 0.25)))
	online.add_child(_label("o toca una sala para unirte:", 15, MUTED))
	_online_rooms_box = VBoxContainer.new()
	_online_rooms_box.add_theme_constant_override("separation", 6)
	online.add_child(_online_rooms_box)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	online.add_child(code_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "o escribe su código (p. ej. KXRT)"
	_code_edit.max_length = 4
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, 48)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join_code())
	code_row.add_child(_code_edit)
	var join_code := _button("Unirse", _on_join_code, TITLE_COLOR)
	join_code.custom_minimum_size = Vector2(140, 48)
	code_row.add_child(join_code)
	# La dirección del servidor solo se pide si el juego no trae una (o se cambió).
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	server_row.visible = Net.DEFAULT_ONLINE_SERVER == "" or Net.online_server != Net.DEFAULT_ONLINE_SERVER
	online.add_child(server_row)
	server_row.add_child(_label("Servidor:", 15, MUTED))
	_server_edit = LineEdit.new()
	_server_edit.text = Net.online_server
	_server_edit.placeholder_text = "IP del VPS"
	_server_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_edit.custom_minimum_size = Vector2(0, 36)
	_server_edit.text_changed.connect(func(text: String) -> void: Net.set_online_server(text))
	_server_edit.text_submitted.connect(func(_t: String) -> void: Net.start_online_browse())
	server_row.add_child(_server_edit)
	online.add_child(_back_button())

	# Red local: misma WiFi.
	var local := _page("local", page)
	local.add_child(_label("EN TU WIFI", 34, Color(0.5, 1.0, 0.55)))
	local.add_child(_button("Crear sala", _on_create, Color(1.0, 0.6, 0.25)))
	local.add_child(_label("o toca una sala para unirte:", 15, MUTED))
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	local.add_child(_rooms_box)
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	local.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "o escribe la IP del anfitrión"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size = Vector2(0, 40)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_ip())
	ip_row.add_child(_ip_edit)
	var join := _button("Unirse", _on_join_ip)
	join.custom_minimum_size = Vector2(140, 40)
	ip_row.add_child(join)
	local.add_child(_back_button())


func _page(name: String, parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)
	_pages[name] = box
	return box


func _show_page(name: String) -> void:
	_current = name
	for key in _pages:
		_pages[key].visible = key == name
	_room.visible = false
	_set_status("")
	if name == "local":
		Net.start_discovery()
		_refresh_rooms()
	else:
		Net.stop_discovery()
	if name == "online":
		Net.start_online_browse()
	else:
		Net.stop_online_browse()


## Vuelve a la pantalla anterior. false en la primera (DebugOverlay vuelve entonces al menú).
func go_back() -> bool:
	if _room.visible:
		Net.leave()
		_show_page(_mode)
		return true
	if _current != "elegir":
		_show_page("elegir")
		return true
	return false


func current_page() -> String:
	return "sala" if _room.visible else _current


func _back_button(text: String = "Volver") -> Button:
	return _button(text, func() -> void:
		if not go_back():
			GameManager.go_to_menu(), Color(0.7, 0.7, 0.75))


func _refresh_rooms() -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	if Net.rooms.is_empty():
		var text := "Buscando salas en la WiFi..." if Net.is_discovering() else "No se pueden buscar salas aquí: únete por IP."
		_rooms_box.add_child(_label(text, 15, Color(0.55, 0.55, 0.65)))
		return
	for ip in Net.rooms:
		var info: Dictionary = Net.rooms[ip]
		var text := "%s   (%d/%d)   %s" % [info["name"], info["players"], Net.MAX_PLAYERS, ip]
		var port: int = info["port"]
		var room_button := _button(text, func() -> void: _join(ip, port), Color(0.45, 0.85, 1.0))
		Icons.apply(room_button, Color(0.45, 0.85, 1.0), Icons.get_icon("unirse"))
		_rooms_box.add_child(room_button)


## Salas de internet que admiten jugadores (se actualiza sola mientras se mira).
func _refresh_online_rooms() -> void:
	for child in _online_rooms_box.get_children():
		child.queue_free()
	var browser := Net.online_browser
	if browser == null:
		return
	if browser.rooms.is_empty():
		var text := "Buscando salas..."
		if browser.state == "ok":
			text = "No hay salas abiertas ahora mismo: crea una."
		elif browser.state == "error":
			text = browser.error_text + " Reintentando..."
		_online_rooms_box.add_child(_label(text, 15, Color(0.55, 0.55, 0.65)))
		return
	var shown := 0
	for room in browser.rooms:
		if shown == ONLINE_ROOMS_SHOWN:
			_online_rooms_box.add_child(_label("y %d más: únete con su código" % (browser.rooms.size() - shown), 14, Color(0.55, 0.55, 0.65)))
			break
		var code: String = room["code"]
		var text := "%s   (%d/%d)" % [room["name"], room["players"], Net.MAX_PLAYERS]
		var room_button := _button(text, func() -> void: _join_online(code), TITLE_COLOR)
		Icons.apply(room_button, TITLE_COLOR, Icons.get_icon("unirse"))
		_online_rooms_box.add_child(room_button)
		shown += 1


func _on_create() -> void:
	Net.set_player_name(_name_edit.text)
	var err := Net.host_room()
	if err != OK:
		_set_status("No se pudo crear la sala (%s). ¿Hay otra abierta en este dispositivo?" % error_string(err))
		return
	_mode = "local"
	_show_room()


func _on_create_online() -> void:
	Net.set_player_name(_name_edit.text)
	Net.set_online_server(_server_edit.text)
	if Net.host_online() != OK:
		_set_status(Net.last_error)
		return
	_mode = "online"
	_set_status("Creando la sala en el servidor...")


func _on_join_code() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Escribe el código de 4 letras que ve el anfitrión en su sala.")
		return
	_join_online(code)


func _join_online(code: String) -> void:
	Net.set_player_name(_name_edit.text)
	Net.set_online_server(_server_edit.text)
	if Net.join_online(code) != OK:
		_set_status(Net.last_error)
		return
	_mode = "online"
	_set_status("Entrando en la sala %s..." % code)


func _on_join_ip() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_valid_ip_address():
		_join(ip, Net.PORT)
	else:
		_set_status("Escribe una IP válida (la muestra el anfitrión en su sala).")


func _join(ip: String, port: int) -> void:
	Net.set_player_name(_name_edit.text)
	var err := Net.join_room(ip, port)
	_mode = "local"
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
	_share_code = _button("Enviar el código por WhatsApp", _on_share_code, Color(0.45, 0.95, 0.55))
	_room.add_child(_share_code)
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
	_room.add_child(_button("Salir de la sala", go_back, Color(0.7, 0.7, 0.75)))


func _show_room() -> void:
	Net.stop_discovery()
	Net.stop_online_browse()
	for key in _pages:
		_pages[key].visible = false
	_room.visible = true
	_set_status("")
	_refresh_room()


func _refresh_room() -> void:
	if not _room.visible:
		return
	_room_title.text = Net.room_name
	_host_box.visible = Net.is_host()
	_client_wait.visible = not Net.is_host()
	_share_code.visible = Net.online and Net.is_host()
	if Net.online:
		_room_info.text = ("Sale en la lista de \"Por internet\"; también pueden entrar con el código %s." if Net.is_host() else "Conectado a la sala %s. Las rondas las decide el anfitrión.") % Net.room_code
	elif Net.is_host():
		var ips := Net.local_ips()
		_room_info.text = "Los demás pueden encontrarla en \"En tu WiFi\" o unirse con la IP: %s" % (", ".join(ips) if not ips.is_empty() else "(sin red local)")
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


func _on_share_code() -> void:
	var text := "¡Juega conmigo a ¿Cazador o Presa?! Entra en Multijugador → Por internet con el código %s" % Net.room_code
	OS.shell_open("https://wa.me/?text=" + text.uri_encode())


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	return column


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
	Icons.apply(button, color)
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
