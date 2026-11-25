extends Node
## Audio: todos los efectos existen, se sitúan en el mundo y los eventos del juego los disparan.

var failures := 0
const SOUNDS := ["pulse", "step_0", "step_1", "step_2", "step_3", "door_open", "door_close", "switch",
	"wardrobe_enter", "wardrobe_exit", "wardrobe_search", "wardrobe_found", "net_fire", "net_hit",
	"net_miss", "net_escape", "capture", "heartbeat", "beep", "hunt_start", "win", "lose", "ui_click"]


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"
	get_tree().create_timer(60.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	await run()
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func players_3d(scene: Node) -> Array:
	return scene.get_children().filter(func(c): return c is AudioStreamPlayer3D)


func run() -> void:
	var missing := SOUNDS.filter(func(s): return Audio._get_stream(s) == null)
	check(missing.is_empty(), "Existen los %d efectos (faltan: %s)" % [SOUNDS.size(), missing])
	check(AudioServer.get_bus_index("Music") != -1 and AudioServer.get_bus_index("SFX") != -1, "Buses Music y SFX creados")

	var s: TestScenario = load("res://scenes/test/TestHunter.tscn").instantiate()
	await frames(1)  # La raíz no admite hijos mientras termina de preparar la escena.
	# play_at coloca los sonidos en la escena actual, que debe colgar de la raíz.
	get_tree().root.add_child(s)
	var previous := get_tree().current_scene
	get_tree().current_scene = s
	await frames(5)
	check(s.get_node("CameraRig/AudioListener") is AudioListener3D, "El oyente va en el CameraRig")

	var door: Door = get_tree().get_nodes_in_group("doors")[0]
	var before := players_3d(s).size()
	door.set_open(not door.is_open)
	var sounds := players_3d(s)
	check(sounds.size() > before, "Abrir/cerrar una puerta suena")
	if sounds.size() > before:
		var p: AudioStreamPlayer3D = sounds[-1]
		check(is_equal_approx(p.max_distance, GameManager.config.door_noise_radius), "El sonido de la puerta llega hasta su radio de ruido (%.0f m)" % p.max_distance)
		check(p.global_position.distance_to(door.global_position) < 0.1, "El sonido sale de la puerta")

	var hunter := s.get_controlled_character() as Hunter
	before = players_3d(s).size()
	hunter.fire_net()
	check(players_3d(s).size() > before, "Disparar la red suena")

	var ghost: Ghost = get_tree().get_nodes_in_group("ghosts")[0]
	if ghost.state == Ghost.State.HIDDEN:
		ghost.expel_from_hiding()
	ghost.apply_net()
	before = players_3d(s).size()
	ghost.capture()
	check(players_3d(s).size() > before, "Capturar suena")

	GameManager.config.audio_enabled = false
	await frames(2)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Desactivar el audio silencia los buses")
	GameManager.config.audio_enabled = true
	get_tree().current_scene = previous
	s.queue_free()
	await frames(3)
