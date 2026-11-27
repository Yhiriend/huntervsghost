extends SceneTree
## Arranque del servidor de salas en el VPS (sin ventana, sin cargar el juego):
##   godot --headless --path <proyecto> --script res://server/relay_main.gd -- --port=24680

const RelayServer := preload("res://server/relay_server.gd")
const P := preload("res://server/relay_protocol.gd")

var relay


func _initialize() -> void:
	var port := P.DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	randomize()
	relay = RelayServer.new()
	var err: Error = relay.start(port)
	if err != OK:
		printerr("No se pudo abrir el puerto UDP %d: %s" % [port, error_string(err)])
		quit(1)


func _process(_delta: float) -> bool:
	relay.poll()
	# Sin ventana el bucle no espera: evita usar el 100 % de la CPU. (La espera de
	# ENetConnection.service(ms) no duerme en Linux: gastaba ~70 % de un núcleo.)
	OS.delay_msec(1)
	return false
