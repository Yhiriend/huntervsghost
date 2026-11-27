extends "res://tests/test_red.gd"
## Multijugador por internet: la misma partida que test_red, pero pasando por el servidor de
## salas (server/relay_server.gd, aquí dentro del mismo proceso): el anfitrión crea la sala,
## recibe un código y el cliente (otro Godot) se une con él. Además: código inexistente,
## servidor caído y que el servidor cierre la sala cuando se va el anfitrión.

const RelayServer := preload("res://server/relay_server.gd")
const RELAY_PORT := 24690

var relay


func _process(_delta: float) -> void:
	if relay:
		relay.poll()


func host_session() -> bool:
	# Sin servidor: el anfitrión recibe un error claro.
	Net.online_server = "127.0.0.1:%d" % RELAY_PORT
	var failed := [false]
	var on_fail := func() -> void: failed[0] = true
	Net.join_failed.connect(on_fail)
	check(Net.host_online() == OK, "Conectando con un servidor apagado")
	await wait_for(func(): return failed[0], 15.0)
	check(failed[0] and Net.last_error != "", "Servidor apagado: falla con aviso (%s)" % Net.last_error)

	relay = RelayServer.new()
	relay.verbose = false
	check(relay.start(RELAY_PORT) == OK, "Arranca el servidor de salas")

	# Código que no existe.
	failed[0] = false
	check(Net.join_online("ZZZZ") == OK, "Probando un código inexistente")
	await wait_for(func(): return failed[0], 8.0)
	check(failed[0] and Net.last_error.contains("ZZZZ"), "Código inexistente: '%s'" % Net.last_error)
	Net.join_failed.disconnect(on_fail)

	check(Net.host_online() == OK, "Pidiendo sala al servidor")
	var ok := await wait_for(func(): return Net.is_host() and Net.room_code.length() == 4, 8.0)
	check(ok and relay.room_count() == 1 and Net.room_name == "Sala %s" % Net.room_code, "El servidor da un código de sala (%s)" % Net.room_code)
	return ok


func client_args() -> Array:
	return ["--online=127.0.0.1:%d:%s" % [RELAY_PORT, Net.room_code]]


func run() -> void:
	await super.run()
	if relay == null:
		return
	# El anfitrión se va: el servidor cierra la sala.
	Net.leave()
	var closed := await wait_for(func(): return relay.room_count() == 0, 5.0)
	check(closed, "Al irse el anfitrión el servidor cierra la sala")
	relay.stop()
