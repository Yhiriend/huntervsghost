extends Node
## Saca capturas para revisar el aspecto sin móvil (no es una prueba). Con ventana, no headless:
##   Godot --path . res://tools/capturas.tscn --resolution 1600x720 -- --out=/ruta/carpeta
## Guarda: cazador.png, presa.png, vista_general.png, menu.png.

var out_dir := "user://capturas"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	PlaytestLogger.path = "user://_test_playtests.csv"
	var cfg := GameManager.config
	cfg.touch_controls_on_pc = true
	cfg.camera_zoom = cfg.camera_zoom_touch
	await _run()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	print("captura ", out_dir.path_join(file))


func _run() -> void:
	var s: Node = load("res://scenes/test/Prototype01.tscn").instantiate()
	add_child(s)
	await _frames(40)
	await _shot("cazador.png")
	s._take_control(1, true)
	await _frames(40)
	await _shot("presa.png")
	s._spectate(0)
	GameManager.config.camera_zoom = 26.0
	s._camera_rig.set_target(s.get_node("House"), true)
	await _frames(60)
	await _shot("vista_general.png")
	s.queue_free()
	GameManager.config.camera_zoom = GameManager.config.camera_zoom_touch
	await _frames(2)
	var menu: Node = load("res://scenes/main/MainMenu.tscn").instantiate()
	add_child(menu)
	await _frames(120)
	var bg := menu.find_children("*", "MenuBackground", true, false)
	if not bg.is_empty():
		print("fondo: tamaño ", bg[0].size, " viewport ", bg[0].get_child(0).size)
	await _shot("menu.png")
