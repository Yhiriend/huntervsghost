extends Node
## Multijugador en red local: este proceso es el anfitrión y lanza otro Godot como cliente
## (tests/net_client.tscn) que se une por 127.0.0.1. Comprueba la sala, la carga de rondas,
## que los controles del cliente mueven su personaje en el anfitrión, que el cliente recibe
## estados / redes / puertas / sonidos, el fin de ronda, la siguiente ronda (el cliente caza)
## y que la IA ocupa el puesto de un jugador que se va.
## El cliente escribe sus comprobaciones en CLIENT_LOG y aquí se suman.

const CLIENT_LOG := "user://_test_net_client.log"

var failures := 0
var _client_pid := -1


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Espera hasta que cond() sea cierto o pasen max_s segundos. Devuelve si se cumplió.
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
	PlaytestLogger.path = "user://_test_playtests.csv"
	DirAccess.remove_absolute(PlaytestLogger.path)
	DirAccess.remove_absolute(CLIENT_LOG)
	get_tree().create_timer(100.0).timeout.connect(func():
		print("TIMEOUT")
		_kill_client()
		get_tree().quit(1))
	# Las rondas sustituyen la escena actual: este nodo debe sobrevivir.
	var dummy := Node.new()
	dummy.name = "Vacio"
	get_tree().root.add_child.call_deferred(dummy)
	await get_tree().process_frame
	get_tree().current_scene = dummy
	await run()
	_kill_client()
	# La ronda guarda su fila al salir: se cierra antes de borrar el CSV de prueba.
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	await frames(5)
	_read_client_log()
	DirAccess.remove_absolute(PlaytestLogger.path)
	Net.leave()
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	var cfg := GameManager.config
	cfg.prep_time = 1.0
	cfg.match_duration = 7.0
	Net.player_name = "Anfitrión"
	var hosted: bool = await host_session()
	check(hosted, "Se crea la sala")
	check(Net.is_host() and Net.players.size() == 1, "Anfitrión solo en la sala")
	if not hosted:
		return
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/net_client.tscn", "--"] + client_args()
	_client_pid = OS.create_process(OS.get_executable_path(), args)
	check(_client_pid > 0, "Se lanza el cliente")
	var joined := await wait_for(func(): return Net.players.size() == 2, 20.0)
	check(joined, "El cliente entra en la sala")
	if not joined:
		return
	var client_peer: int = Net.player_order[1]
	check(Net.name_of(client_peer) == "Cliente", "Nombre del cliente en la sala")

	# Ronda 1 (orden fijo para la prueba): el anfitrión caza; el cliente es Presa.
	GameManager.series = MatchSeries.new([
		{"name": "Anfitrión", "peer": 1}, {"name": "Cliente", "peer": client_peer},
		{"name": "IA 1", "peer": 0}, {"name": "IA 2", "peer": 0}])
	Net.in_game = true
	Net.load_round()
	await wait_for(func(): return match_scene() != null, 5.0)
	var m := match_scene()
	check(m != null and m.net_role == MatchScenario.NetRole.HOST, "El anfitrión carga la ronda")
	var started := await wait_for(func(): return m.phase != MatchScenario.Phase.WAITING, 8.0)
	check(started and m._wait_left > 0.0, "La ronda empieza cuando el cliente está listo (sin agotar la espera)")
	var client_ghost: Ghost = null
	for node in get_tree().get_nodes_in_group("ghosts"):
		if (node as Ghost).controller is NetInputController:
			client_ghost = node
	check(client_ghost != null and client_ghost.display_name == "Cliente", "La Presa del cliente la controla la red")
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	check(hunter.is_player_controlled, "El anfitrión controla al Cazador")

	await wait_for(func(): return m.phase == MatchScenario.Phase.PLAYING, 3.0)
	var start := client_ghost.global_position
	# El cliente pulsa "derecha" 1,5 s al empezar la caza: basta con que su Presa se mueva.
	var moved := 0.0
	for i in 100:
		await get_tree().physics_frame
		moved = maxf(moved, client_ghost.global_position.distance_to(start))
	check(moved > 0.5, "Los controles del cliente mueven su Presa en el anfitrión (%.1f m)" % moved)

	# Red y captura de la Presa del cliente.
	if client_ghost.state == Ghost.State.HIDDEN:
		client_ghost.expel_from_hiding()
	hunter.global_position = client_ghost.global_position + Vector3(1.0, 0.0, 0.0)
	hunter.fire_net()
	client_ghost.apply_net()
	await frames(30)
	client_ghost.capture()
	await frames(20)
	var door: Door = get_tree().get_nodes_in_group("doors")[0]
	door.set_open(not door.is_open, null, true, true)
	await wait_for(func(): return m.phase == MatchScenario.Phase.ENDED, 9.0)
	check(m.phase == MatchScenario.Phase.ENDED and m.series.points[0] == 1 and m.series.points[1] == 0, "Fin de ronda: anfitrión +1, cliente 0 (%s)" % [m.series.points])
	await frames(30)

	# Ronda 2: caza el cliente.
	m._on_choice("next")
	await wait_for(func(): return match_scene() != null and match_scene() != m and match_scene().phase != MatchScenario.Phase.WAITING, 10.0)
	m = match_scene()
	check(m.round_number == 2 and m.player_role == MatchScenario.ROLE_GHOST, "Ronda 2: el anfitrión es Presa")
	hunter = get_tree().get_nodes_in_group("hunters")[0]
	check(hunter.controller is NetInputController, "El Cazador de la ronda 2 es el cliente")
	var fired := await wait_for(func(): return m._stats["redes_disparadas"] > 0, 8.0)
	check(fired, "El botón de disparo del cliente dispara la red en el anfitrión")

	# El cliente se va: la IA ocupa su puesto.
	var taken := await wait_for(func(): return hunter.controller is HunterAI, 10.0)
	check(taken and m.series.participant_name(1) == "Cliente (IA)" and not m.series.is_human(1), "El cliente se va: la IA toma su Cazador y su puesto")
	check(Net.players.size() == 1, "La sala queda con el anfitrión")


## Crea la sala (aquí, en red local). test_red_online lo cambia por el servidor de salas.
func host_session() -> bool:
	return Net.host_room() == OK


## Argumentos para el cliente (tras "--").
func client_args() -> Array:
	return []


func _kill_client() -> void:
	if _client_pid > 0 and OS.is_process_running(_client_pid):
		# Darle tiempo a escribir su registro.
		for i in 120:
			if not OS.is_process_running(_client_pid):
				break
			OS.delay_msec(50)
		if OS.is_process_running(_client_pid):
			OS.kill(_client_pid)
			print("FAIL El cliente no terminó solo")
			failures += 1


func _read_client_log() -> void:
	if not FileAccess.file_exists(CLIENT_LOG):
		check(false, "El cliente escribió su registro")
		return
	for line in FileAccess.get_file_as_string(CLIENT_LOG).split("\n"):
		if line.begins_with("PASS") or line.begins_with("FAIL"):
			print(line.substr(0, 5) + "[cliente] " + line.substr(5))
			if line.begins_with("FAIL"):
				failures += 1
	DirAccess.remove_absolute(CLIENT_LOG)
	# El cliente guarda su última ronda al cerrarse: su CSV de prueba se borra aquí.
	DirAccess.remove_absolute("user://_test_playtests_client.csv")
