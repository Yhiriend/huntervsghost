extends Node
## La Presa IA usa el señuelo: lo deja al pasear por las habitaciones, lo hace sonar (lejos de
## sí) cuando el Cazador anda cerca y no la ve, el Cazador IA va hacia él, no lo usa si lo tiene
## pegado, y lo cambia de sitio cuando ya lo ha usado varias veces.

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func wait_for(cond: Callable, max_s: float) -> bool:
	for i in int(max_s * 60.0):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func place(c: CharacterBase, at: Vector3) -> void:
	c.global_position = Vector3(at.x, c.global_position.y, at.z)
	c.velocity = Vector3.ZERO


func ai_of(c: CharacterBase) -> AIController:
	for node in c.get_children():
		if node is AIController:
			return node
	return null


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"
	get_tree().create_timer(120.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	var cfg := GameManager.config
	var saved := [cfg.ai_ghost_decoy_place_chance, cfg.prep_time, cfg.match_duration, cfg.ai_ghost_hide_chance]
	cfg.prep_time = 0.3
	cfg.match_duration = 120.0
	await run()
	cfg.ai_ghost_decoy_place_chance = saved[0]
	cfg.prep_time = saved[1]
	cfg.match_duration = saved[2]
	cfg.ai_ghost_hide_chance = saved[3]
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	var cfg := GameManager.config
	cfg.ai_ghost_decoy_place_chance = 1.0
	cfg.ai_ghost_hide_chance = 0.0
	# Jugador Cazador (quieto y lejos): las Presas son IA.
	GameManager.selected_role = DummySpawn.Role.HUNTER
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(30)
	var house: House = m.get_node("House")
	await wait_for(func(): return house.nav_ready, 5.0)
	var hunter := m.get_controlled_character() as Hunter
	hunter.frozen = true
	# Fuera de la casa: la IA solo sabe del Cazador lo que la prueba le dice.
	hunter.global_position = Vector3(0, -50, 0)
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	var prey: Ghost = ghosts[0]
	for g in ghosts:
		if (g as Ghost).state == Ghost.State.HIDDEN:
			(g as Ghost).expel_from_hiding()
		if g != prey:
			(g as Ghost).frozen = true
			place(g, Vector3(-9.0, 0, 8.0))
	var ai := ai_of(prey) as GhostAI
	await frames(int(4.5 * 60))  # La IA no deja el señuelo en los primeros segundos.

	# 1. Paseando deja el señuelo al entrar en una habitación.
	ai._set_state(GhostAI.State.ROAM)
	ai._decoy_room = null
	var placed := await wait_for(func(): return prey.has_decoy(), 20.0)
	check(placed, "Paseando, deja el señuelo (%s)" % prey.decoy_position)
	if not placed:
		return

	# 2. Escondida en un armario lejos del señuelo; el Cazador anda cerca del señuelo y no la ve.
	var decoy := prey.decoy_position
	var far_spot: HidingSpot = null
	for node in get_tree().get_nodes_in_group("hiding_spots"):
		if (node as Node3D).global_position.distance_to(decoy) > 7.0 and (node as HidingSpot).occupant == null:
			far_spot = node
	prey.enter_hiding(far_spot, false)
	# Como si se hubiera escondido ella: se queda un buen rato.
	ai._hidden_since = ai.now
	ai._hide_duration = 30.0
	prey.decoy_cooldown_left = 0.0
	ai._threat_position = decoy + Vector3(4.0, 0, 0)
	ai._threat_time = ai.now
	var used := await wait_for(func(): return prey.decoy_cooldown_left > 0.0, 2.0)
	check(used, "Escondida, hace sonar el señuelo cuando el Cazador anda cerca")
	check(prey.state == Ghost.State.HIDDEN, "Sin salir del armario")

	# 3. Si el señuelo está pegado a ella, no lo usa (delataría su posición).
	prey.exit_hiding()
	ai._set_state(GhostAI.State.IDLE)
	ai._idle_timer = 10.0
	place(prey, decoy + Vector3(1.0, 0, 0))
	prey.decoy_cooldown_left = 0.0
	ai._threat_position = decoy + Vector3(4.5, 0, 0)
	ai._threat_time = ai.now
	await frames(30)
	check(prey.decoy_cooldown_left <= 0.0, "Con el señuelo pegado a ella no lo usa")

	# 4. Ya usado varias veces (el Cazador sospecharía): lo cambia de sitio en otra habitación.
	ai._threat_time = -100.0
	ai._decoy_uses = cfg.ai_hunter_decoy_occasions
	ai._decoy_known_position = prey.decoy_position
	ai._decoy_room = null
	ai._set_state(GhostAI.State.ROAM)
	ai.clear_destination()
	# Paseando por otra habitación, lejos del señuelo.
	var far_room_point := Vector3(6.0, 0, 7.0) if decoy.x < 0.0 else Vector3(-6.0, 0, 7.5)
	place(prey, far_room_point)
	var moved := await wait_for(func(): return prey.decoy_position.distance_to(decoy) > 4.0, 5.0)
	check(moved, "Ya usado varias veces, lo cambia de sitio (%s -> %s)" % [decoy, prey.decoy_position])
	m.queue_free()
	await frames(3)

	# 5. De punta a punta: el Cazador IA oye el señuelo de la Presa IA y va hacia él.
	GameManager.selected_role = DummySpawn.Role.GHOST
	GameManager.series = null
	m = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(30)
	house = m.get_node("House")
	await wait_for(func(): return house.nav_ready, 5.0)
	var me := m.get_controlled_character() as Ghost
	place(me, Vector3(9.0, 0, 8.0))
	var ai_prey: Ghost = null
	for g in get_tree().get_nodes_in_group("ghosts"):
		if (g as Ghost).state == Ghost.State.HIDDEN:
			(g as Ghost).expel_from_hiding()
		if g != me and ai_prey == null:
			ai_prey = g
		elif g != me:
			(g as Ghost).frozen = true
			place(g, Vector3(9.0, 0, 7.0))
	var hunter_ai_char: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	var hai := ai_of(hunter_ai_char) as HunterAI
	var gai := ai_of(ai_prey) as GhostAI
	# Señuelo en la Sala; la Presa IA escondida en el armario del dormitorio; el Cazador en el pasillo.
	place(ai_prey, Vector3(-6.0, 0, -5.0))
	await frames(2)
	ai_prey.place_decoy()
	var wardrobe: HidingSpot = m.get_node("House/HidingSpots/WardrobeDormitorio2")
	ai_prey.enter_hiding(wardrobe, false)
	gai._hidden_since = gai.now
	gai._hide_duration = 30.0
	place(hunter_ai_char, Vector3(-5.0, 0, 1.5))
	await frames(5)
	hai._set_state(HunterAI.State.PATROL)
	hai.clear_destination()
	gai._threat_position = hunter_ai_char.global_position
	gai._threat_time = gai.now
	var heard := await wait_for(func(): return hai.state == HunterAI.State.INVESTIGATE and \
		AIController.flat_distance(hai._investigate_position, ai_prey.decoy_position) <= GameManager.config.noise_position_error + 0.7, 3.0)
	check(heard, "El Cazador IA va a investigar el señuelo de la Presa IA (estado %s, señuelo sonó: %s, investiga %s, señuelo en %s)" % [hai.state_name, ai_prey.decoy_cooldown_left > 0.0, hai._investigate_position, ai_prey.decoy_position])
	check(ai_prey.state == Ghost.State.HIDDEN, "Mientras, la Presa IA sigue escondida lejos")
