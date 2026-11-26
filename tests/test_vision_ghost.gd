extends Node
## Jugando como Ghost: el Hunter solo se ve en tu misma habitación; escondido, nunca.
## Sus ruidos (pasos al correr) se ven como anillos aunque no se le vea.

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"  # Nunca tocar los datos reales.
	get_tree().create_timer(60.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	await run()
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func rings(m: Node) -> int:
	return m.get_children().filter(func(c): return c is MeshInstance3D and c.mesh is TorusMesh).size()


func place(c: CharacterBase, room: Room) -> void:
	c.global_position = Vector3(room.global_position.x, c.global_position.y, room.global_position.z)
	c.velocity = Vector3.ZERO


func run() -> void:
	GameManager.selected_role = DummySpawn.Role.GHOST
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	var ghost: Ghost = m.get_controlled_character() as Ghost
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	hunter.frozen = true
	var rooms := m.get_node("House/Rooms")
	var cocina: Room = rooms.get_node("Cocina")
	var sala: Room = rooms.get_node("Sala")

	place(ghost, cocina)
	place(hunter, sala)
	await frames(3)
	check(not hunter.visible, "Hunter en otra habitación: no se ve")
	place(hunter, cocina)
	hunter.global_position.x += 1.5
	await frames(3)
	check(hunter.visible, "Hunter en la misma habitación: se ve")

	var wardrobe: HidingSpot = m.get_node("House/HidingSpots/WardrobeCocina")
	ghost.enter_hiding(wardrobe, false)
	await frames(3)
	check(ghost.state == Ghost.State.HIDDEN and not hunter.visible, "Escondido en el armario: el Hunter no se ve aunque esté en la habitación")

	place(hunter, sala)
	await frames(3)
	var before := rings(m)
	GameManager.make_noise(hunter.global_position, 30.0, hunter)
	await frames(1)
	check(rings(m) > before, "Escondido: los pasos del Hunter sí se ven (anillo)")

	ghost.exit_hiding()
	place(hunter, sala)
	await frames(3)
	before = rings(m)
	GameManager.make_noise(hunter.global_position, 30.0, hunter)
	await frames(1)
	check(not hunter.visible and rings(m) > before, "Otra habitación: no se ve al Hunter pero sí sus pasos")

	# El Cazador está en otra habitación pero ve a la Presa (por una puerta abierta): la Presa le ve.
	var found := false
	for door in get_tree().get_nodes_in_group("doors"):
		(door as Door).set_open(true, null, false)
	await frames(2)
	for room in get_tree().get_nodes_in_group("rooms"):
		if found:
			break
		for other in get_tree().get_nodes_in_group("rooms"):
			if room == other or found:
				continue
			for i in range(-4, 5):
				for j in range(-4, 5):
					var p := (other as Room).global_position + Vector3(i * 0.8, 0, j * 0.8)
					if Room.find_at(get_tree(), p) != other:
						continue
					place(hunter, room)
					ghost.global_position = Vector3(p.x, ghost.global_position.y, p.z)
					var d := ghost.global_position - hunter.global_position
					hunter.rotation.y = atan2(-d.x, -d.z)
					if hunter.vision.can_see(ghost):
						found = true
						break
				if found:
					break
	check(found, "Hay una posición en otra habitación desde la que el Cazador ve a la Presa")
	await frames(3)
	check(found and hunter.vision.can_see(ghost) and hunter.visible, "El Cazador te ve desde otra habitación: tú también le ves")
	var d2 := ghost.global_position - hunter.global_position
	hunter.rotation.y = atan2(d2.x, d2.z)  # Mira hacia el otro lado.
	await frames(3)
	check(not hunter.vision.can_see(ghost) and not hunter.visible, "Si deja de verte (te da la espalda) vuelve a ocultarse")

	GameManager.config.ghost_sees_hunter_same_room_only = false
	await frames(2)
	check(hunter.visible, "Con el ajuste desactivado se ve al Hunter siempre")
	GameManager.config.ghost_sees_hunter_same_room_only = true

	# Jugando como Hunter, el Hunter siempre se ve.
	m.queue_free()
	await frames(3)
	GameManager.selected_role = DummySpawn.Role.HUNTER
	GameManager.series = null
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	check((get_tree().get_nodes_in_group("hunters")[0] as Hunter).visible, "Jugando como Hunter te ves a ti mismo")
