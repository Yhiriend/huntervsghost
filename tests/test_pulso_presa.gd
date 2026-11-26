extends Node
## Pulso de la Presa: late solo jugando como Presa con el Cazador en su misma habitación
## (también escondida en el armario); más cerca = más rápido.

var failures := 0


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
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func place(c: CharacterBase, room: Room, offset: float = 0.0) -> void:
	c.global_position = Vector3(room.global_position.x + offset, c.global_position.y, room.global_position.z)
	c.velocity = Vector3.ZERO


func run() -> void:
	GameManager.selected_role = DummySpawn.Role.GHOST
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	var prey: Ghost = m.get_controlled_character() as Ghost
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	hunter.frozen = true
	var cocina: Room = m.get_node("House/Rooms/Cocina")
	var sala: Room = m.get_node("House/Rooms/Sala")

	place(prey, cocina)
	place(hunter, sala)
	await frames(3)
	check(not m.pulse_active, "Cazador en otra habitación: no hay pulso")

	place(hunter, cocina, 3.0)
	await frames(3)
	check(m.pulse_active, "Cazador en la misma habitación: late el corazón")
	var far_interval := m._pulse_left
	place(hunter, cocina, 1.0)
	m._pulse_left = 0.0
	await frames(2)
	check(m._pulse_left < far_interval, "Más cerca, late más rápido (%.2f s < %.2f s)" % [m._pulse_left, far_interval])

	prey.enter_hiding(m.get_node("House/HidingSpots/WardrobeCocina"), false)
	await frames(3)
	check(prey.state == Ghost.State.HIDDEN and m.pulse_active, "Escondida en el armario: también late")

	GameManager.config.prey_pulse_enabled = false
	await frames(2)
	check(not m.pulse_active, "Se puede desactivar en ajustes")
	GameManager.config.prey_pulse_enabled = true

	m.queue_free()
	await frames(3)
	GameManager.selected_role = DummySpawn.Role.HUNTER
	GameManager.series = null
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	var h: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	for g in get_tree().get_nodes_in_group("ghosts"):
		(g as Node3D).global_position = h.global_position + Vector3(1, 0, 0)
	await frames(3)
	check(not m.pulse_active, "Jugando como Cazador no hay pulso")
