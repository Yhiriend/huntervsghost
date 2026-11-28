extends Node
## Prueba de rendimiento (no es un test automático). Mide cuánto tarda cada fotograma en el
## menú, la partida y la IA, y con cada efecto apagado, para saber qué cuesta más.
##   Móvil: Más opciones > Escenarios de prueba > Prueba de rendimiento. Condiciones reales
##          (pantalla del móvil, sin límite de FPS). Muestra la tabla y la guarda en
##          user://rendimiento.txt (adb: run-as <paquete> cat files/rendimiento.txt).
##   PC, GPU: Godot --path . res://scenes/test/Rendimiento.tscn
##          Dibuja en una imagen enorme (7680x3456, ~10 veces un móvil) para que el ordenador
##          quede limitado por la GPU. Compara filas entre sí, no con el móvil.
##   PC, CPU: Godot --headless --fixed-fps 60 --path . res://scenes/test/Rendimiento.tscn
##          Sin dibujar: scripts, física, IA y navegación (un paso de física por fotograma).
## Opciones: -- --frames=300 --px=7680x3456 --real (en PC, medir en la ventana como un móvil)

const REPORT_PATH := "user://rendimiento.txt"

var frames := 300
var warmup := 90
var px := Vector2i(7680, 3456)
var headless := false
## Condiciones reales: se dibuja en la pantalla (móvil, o --real en PC).
var real := false
var _results: Array = []
var _box: Node
var _status: Label
var _saved := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--px="):
			var parts := arg.trim_prefix("--px=").split("x")
			px = Vector2i(parts[0].to_int(), parts[1].to_int())
		elif arg == "--real":
			real = true
	headless = DisplayServer.get_name() == "headless"
	real = real or GameManager.is_mobile()
	PlaytestLogger.path = "user://_test_playtests.csv"
	var cfg := GameManager.config
	_saved = {"max_fps": Engine.max_fps, "low": cfg.graphics_low, "scale": cfg.render_scale_mobile,
		"touch": cfg.touch_controls_on_pc, "zoom": cfg.camera_zoom,
		"vsync": DisplayServer.window_get_vsync_mode() if not headless else 0}
	cfg.touch_controls_on_pc = true
	cfg.camera_zoom = cfg.camera_zoom_touch
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if real:
		_box = Node.new()
		add_child(_box)
	else:
		var view := SubViewport.new()
		view.size = px
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		_box = view
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.position = Vector2(20, 80)
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(_status)
	add_child(layer)
	await _run()
	_restore()
	var report := _report()
	print(report)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(report)
	if real and not headless and GameManager.is_mobile():
		_show_report(report, layer)
	else:
		get_tree().quit()


func _run() -> void:
	var cfg := GameManager.config
	# --- Menú ---
	var menu := await _load("res://scenes/main/MainMenu.tscn")
	var bg: MenuBackground = menu.find_children("*", "MenuBackground", true, false)[0]
	var bg_view := bg.get_child(0) as SubViewport
	await _measure("Menú")
	if not headless:
		_set_low(true)
		await _measure("Menú · gráficos bajos")
		_set_low(false)
	bg.visible = false
	bg.process_mode = Node.PROCESS_MODE_DISABLED
	bg_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await _measure("Menú · sin fondo 3D")
	menu.queue_free()

	# --- Partida: casa libre con el jugador ---
	var proto := await _load("res://scenes/test/Prototype01.tscn")
	await _measure("Juego")
	if not headless:
		_set_low(true)
		await _measure("Juego · gráficos bajos")
		_set_low(false)
		if real and get_tree().root.scaling_3d_scale < 1.0:
			var scale := get_tree().root.scaling_3d_scale
			_set_scale(1.0)
			await _measure("Juego · 3D a resolución nativa")
			_set_scale(scale)
		proto.get_node("House/Decor").visible = false
		await _measure("Juego · sin jardín/alfombras")
		proto.get_node("House/Decor").visible = true
	proto.queue_free()

	# --- IA contra IA (4 personajes con IA) ---
	var ai := await _load("res://scenes/test/TestAI.tscn")
	await _measure("IA contra IA")
	ai.queue_free()


func _set_low(low: bool) -> void:
	GameManager.config.graphics_low = low
	GameManager.apply_graphics()
	Engine.max_fps = 0


func _set_scale(value: float) -> void:
	var root := get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = value


func _restore() -> void:
	var cfg := GameManager.config
	cfg.graphics_low = _saved["low"]
	cfg.render_scale_mobile = _saved["scale"]
	cfg.touch_controls_on_pc = _saved["touch"]
	cfg.camera_zoom = _saved["zoom"]
	GameManager.apply_graphics()
	Engine.max_fps = _saved["max_fps"]
	if not headless:
		DisplayServer.window_set_vsync_mode(_saved["vsync"])


func _load(path: String) -> Node:
	_status.text = "Prueba de rendimiento: cargando %s..." % path.get_file()
	var node: Node = load(path).instantiate()
	_box.add_child(node)
	for i in warmup:
		await get_tree().process_frame
	return node


func _measure(label: String) -> void:
	_status.text = "Prueba de rendimiento: %s (%d/%d)..." % [label, _results.size() + 1, 11]
	for i in 20:
		await get_tree().process_frame
	var times := PackedFloat32Array()
	var draws := 0
	var prims := 0
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	_results.append([label, avg, 1000.0 / avg, sorted[int(sorted.size() * 0.95)], draws / frames, prims / frames])


func _report() -> String:
	var lines := []
	var size := DisplayServer.window_get_size() if not headless else Vector2i.ZERO
	if headless:
		lines.append("RENDIMIENTO CPU (sin dibujar) · %d fotogramas por medida" % frames)
	elif real:
		lines.append("RENDIMIENTO REAL · %s · %s · pantalla %dx%d · 3D al %d%% · %d fotogramas por medida" % [OS.get_model_name(), RenderingServer.get_video_adapter_name(), size.x, size.y, roundi(get_tree().root.scaling_3d_scale * 100.0), frames])
	else:
		lines.append("RENDIMIENTO GPU · %s · imagen %dx%d · %d fotogramas por medida" % [RenderingServer.get_video_adapter_name(), px.x, px.y, frames])
	lines.append("%-32s %7s %6s %7s %6s %8s" % ["escena", "ms/fot", "FPS", "p95", "draws", "triáng."])
	for r in _results:
		lines.append("%-32s %7.2f %6.0f %7.2f %6d %8d" % r)
	return "\n".join(lines)


func _show_report(report: String, layer: CanvasLayer) -> void:
	_status.visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var text := Label.new()
	text.text = report + "\n\nGuardado en %s" % ProjectSettings.globalize_path(REPORT_PATH)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Roboto Mono", "Droid Sans Mono", "monospace"])
	text.add_theme_font_override("font", mono)
	text.add_theme_font_size_override("font_size", 18)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var back := Button.new()
	back.text = "Volver al menú"
	back.custom_minimum_size = Vector2(0, 56)
	back.pressed.connect(GameManager.go_to_menu)
	Icons.apply(back)
	box.add_child(back)
