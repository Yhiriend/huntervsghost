extends Node
## Cliente de la prueba test_red (lo lanza ese proceso; no se ejecuta solo).
## Se une al anfitrión en 127.0.0.1, juega la ronda 1 como Presa y la 2 como Cazador,
## y se va. Escribe sus comprobaciones en test_red.CLIENT_LOG.

const CLIENT_LOG := "user://_test_net_client.log"

var lines := PackedStringArray()


func check(cond: bool, msg: String) -> void:
	lines.append(("PASS " if cond else "FAIL ") + msg)


func wait_for(cond: Callable, max_s: float) -> bool:
	var frames_left := int(max_s * 60.0)
	while frames_left > 0:
		if cond.call():
			return true
		await get_tree().physics_frame
		frames_left -= 1
	return cond.call()


func match_scene() -> MatchScenario:
	return get_tree().current_scene as MatchScenario


func _ready() -> void:
	# Con --fixed-fps y sin ventana los frames no esperan al reloj: la red necesita tiempo real.
	Engine.max_fps = 60
	PlaytestLogger.path = "user://_test_playtests_client.csv"
	get_tree().create_timer(80.0).timeout.connect(func():
		check(false, "TIMEOUT del cliente")
		_finish())
	var dummy := Node.new()
	dummy.name = "Vacio"
	get_tree().root.add_child.call_deferred(dummy)
	await get_tree().process_frame
	get_tree().current_scene = dummy
	await run()
	_finish()


func _finish() -> void:
	Input.action_release("move_right")
	Input.action_release("fire")
	Input.action_release("decoy")
	Net.leave()
	var f := FileAccess.open(CLIENT_LOG, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	DirAccess.remove_absolute(PlaytestLogger.path)
	get_tree().quit()


func run() -> void:
	Net.player_name = "Cliente"
	# --online=servidor:puerto:CODIGO -> por el servidor de salas (test_red_online).
	var online := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online="):
			online = arg.trim_prefix("--online=")
	var expected_room := "Sala de Anfitrión"
	if online != "":
		var parts := online.split(":")
		Net.online_server = "%s:%s" % [parts[0], parts[1]]
		check(Net.join_online(parts[2]) == OK, "Conectando con el servidor de salas")
	else:
		Net.start_discovery()
		var found := await wait_for(func(): return not Net.rooms.is_empty(), 3.0)
		# La difusión en el propio ordenador depende del sistema: solo se informa.
		print("Descubrimiento de salas en este equipo: %s" % ("sí" if found else "no"))
		Net.stop_discovery()
		check(Net.join_room("127.0.0.1") == OK, "Conectando con el anfitrión")
	var joined := await wait_for(func(): return Net.is_client() and Net.players.size() >= 2, 10.0)
	check(joined and Net.room_name == expected_room, "Dentro de la sala del anfitrión (estado %d, id %d, jugadores %d, sala '%s')" % [multiplayer.multiplayer_peer.get_connection_status(), multiplayer.get_unique_id(), Net.players.size(), Net.room_name])
	if not joined:
		return
	var pinged := await wait_for(func(): return Net.ping_ms() >= 0, 4.0)
	check(pinged, "Ping con el anfitrión medido (%d ms)" % Net.ping_ms())
	var loaded := await wait_for(func(): return match_scene() != null, 15.0)
	check(loaded, "El cliente carga la ronda que manda el anfitrión")
	if not loaded:
		return
	var m := match_scene()
	check(m.net_role == MatchScenario.NetRole.CLIENT and m.player_role == MatchScenario.ROLE_GHOST, "Ronda 1: soy Presa en un cliente")
	var me := m.get_controlled_character() as Ghost
	check(me != null and me.net_puppet and me.display_name == "Cliente", "Controlo mi Presa (copia del anfitrión)")
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	check(hunter.net_puppet and hunter.display_name == "Anfitrión", "El Cazador es el anfitrión")

	var playing := await wait_for(func(): return m.phase == MatchScenario.Phase.PLAYING, 8.0)
	check(playing, "Las fotos del estado llevan la fase (empieza la caza)")
	Input.action_press("move_right")
	await wait_for(func(): return false, 1.5)
	Input.action_release("move_right")
	Input.action_press("decoy")
	await wait_for(func(): return false, 0.1)
	Input.action_release("decoy")
	var decoy_back := await wait_for(func(): return me.has_decoy() and me._decoy != null and me._decoy.visible, 3.0)
	check(decoy_back, "Mi señuelo llega al anfitrión y vuelve (lo veo)")

	var netted := await wait_for(func(): return me.state == Ghost.State.NETTED, 6.0)
	check(netted, "Me llega la red del anfitrión (estado ATRAPADO)")
	# Los estados (fiables) pueden llegar antes que la siguiente foto de posiciones.
	await wait_for(func(): return hunter.global_position.distance_to(me.global_position) < 3.0, 2.0)
	check(hunter.global_position.distance_to(me.global_position) < 3.0, "La posición del Cazador llega por la red (%.1f m)" % hunter.global_position.distance_to(me.global_position))
	var captured := await wait_for(func(): return me.state == Ghost.State.CAPTURED, 6.0)
	check(captured and not me.visible, "Me llega la captura")
	check(Audio.net_sounds_received > 0, "Llegan los sonidos del anfitrión (%d)" % Audio.net_sounds_received)
	var door: Door = get_tree().get_nodes_in_group("doors")[0]
	var door_start := door.is_open
	var door_changed := await wait_for(func(): return door.is_open != door_start, 4.0)
	check(door_changed, "Me llega el cambio de una puerta")

	var ended := await wait_for(func(): return m.phase == MatchScenario.Phase.ENDED and m._result_screen != null, 10.0)
	check(ended, "Fin de ronda en el cliente")
	if ended:
		check(m._result_screen._subtitle.text.begins_with("Te han atrapado") and m.series.points[0] == 1, "Resultados con los puntos del anfitrión")
		check(m._result_screen.primary_choice == "menu", "El cliente no decide la siguiente ronda")

	# Ronda 2: caza el cliente.
	var next := await wait_for(func(): return match_scene() != null and match_scene() != m, 15.0)
	check(next, "El anfitrión carga la ronda 2")
	if not next:
		return
	m = match_scene()
	check(m.player_role == MatchScenario.ROLE_HUNTER and m.round_number == 2, "Ronda 2: soy el Cazador")
	await wait_for(func(): return m.phase == MatchScenario.Phase.PREP, 8.0)
	await get_tree().process_frame
	check(m._hud._blackout.visible, "Pantalla negra en la preparación del Cazador")
	await wait_for(func(): return m.phase == MatchScenario.Phase.PLAYING, 5.0)
	await wait_for(func(): return false, 0.3)
	Input.action_press("fire")
	await wait_for(func(): return false, 0.2)
	Input.action_release("fire")
	await wait_for(func(): return false, 1.0)
	check(not m._nets.is_empty() or m._stats.is_empty() == false, "Disparo enviado")
