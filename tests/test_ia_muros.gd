extends Node
## IA y muros sueltos / señuelos:
##  - La Presa IA se esconde detrás de un muro, en el lado contrario al Cazador, y si el Cazador
##    se asoma por un extremo, escapa por el otro.
##  - El Cazador IA, al investigar cerca de un muro, se asoma por un extremo.
##  - El Cazador IA reacciona a unos pasos nuevos, pero si vuelven a sonar "parados" en el mismo
##    sitio en otra ocasión, lo toma por un señuelo y no deja lo que hace.

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


func _ready() -> void:
	PlaytestLogger.path = "user://_test_playtests.csv"
	get_tree().create_timer(120.0).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(1))
	var cfg := GameManager.config
	var saved := [cfg.ai_ghost_wall_chance, cfg.ai_hunter_peek_chance, cfg.ai_hunter_decoy_follow_chance, cfg.decoy_cooldown, cfg.prep_time, cfg.match_duration]
	cfg.prep_time = 0.3
	cfg.match_duration = 120.0
	await ghost_cover()
	await hunter_peek()
	await hunter_decoy()
	cfg.ai_ghost_wall_chance = saved[0]
	cfg.ai_hunter_peek_chance = saved[1]
	cfg.ai_hunter_decoy_follow_chance = saved[2]
	cfg.decoy_cooldown = saved[3]
	cfg.prep_time = saved[4]
	cfg.match_duration = saved[5]
	for c in get_children():
		c.queue_free()
	await frames(3)
	DirAccess.remove_absolute(PlaytestLogger.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func place(c: CharacterBase, at: Vector3, look_at_point: Vector3 = Vector3.INF) -> void:
	c.global_position = Vector3(at.x, c.global_position.y, at.z)
	c.velocity = Vector3.ZERO
	if look_at_point != Vector3.INF:
		var d := look_at_point - c.global_position
		c.rotation.y = atan2(-d.x, -d.z)


func new_match(role: int) -> MatchScenario:
	GameManager.selected_role = role
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(30)
	var house: House = m.get_node("House")
	await wait_for(func(): return house.nav_ready, 5.0)
	for g in get_tree().get_nodes_in_group("ghosts"):
		if (g as Ghost).state == Ghost.State.HIDDEN:
			(g as Ghost).expel_from_hiding()
	return m


func ai_of(c: CharacterBase) -> AIController:
	for node in c.get_children():
		if node is AIController:
			return node
	return null


# --- La Presa IA y los muros ------------------------------------------------------

func ghost_cover() -> void:
	GameManager.config.ai_ghost_wall_chance = 1.0
	var m: MatchScenario = await new_match(DummySpawn.Role.HUNTER)
	var hunter := m.get_controlled_character() as Hunter
	hunter.frozen = true
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	var prey: Ghost = ghosts[0]
	for g in ghosts:
		if g != prey:
			(g as Ghost).frozen = true
			place(g, Vector3(0, 0, 1.5))
	var ai := ai_of(prey) as GhostAI
	# Muro de la Cocina (horizontal en z = -5.2). El Cazador "estaba" al sur del muro.
	var wall_center := Vector3(5.0, 0, -5.2)
	place(prey, Vector3(7.5, 0, -6.8))
	place(hunter, Vector3(5.0, 0, -2.5), wall_center)
	ai._threat_position = hunter.global_position
	ai._threat_time = ai.now - 2.0
	var cover := ai._best_cover()
	check(not cover.is_empty() and (cover["wall"]["center"] as Vector3).distance_to(wall_center) < 0.1, "Elige el muro de la cocina (%s)" % [cover.get("point")])
	if cover.is_empty():
		m.queue_free()
		await frames(3)
		return
	ai._go_cover(cover)
	var arrived := await wait_for(func(): return ai._cover_since >= 0.0, 8.0)
	check(arrived and ai.state == GhostAI.State.COVER, "Llega detrás del muro (estado %s)" % ai.state_name)
	check(prey.global_position.z < wall_center.z and absf(prey.global_position.z - wall_center.z) < 1.0, "Está en el lado contrario al Cazador (z %.2f)" % prey.global_position.z)
	await frames(10)
	check(not hunter.vision.can_see(prey), "El Cazador, de frente, no la ve")
	check(ai.state == GhostAI.State.COVER, "Se queda escondida mientras no la ven")

	# El Cazador se asoma por el extremo oeste: la ve; ella escapa por el este.
	place(hunter, Vector3(5.0 - 1.3 - 0.9, 0, -5.6), prey.global_position)
	await frames(3)
	check(hunter.vision.can_see(prey), "Asomándose por un extremo el Cazador la ve")
	var start := prey.global_position
	await frames(60)
	check(ai.state == GhostAI.State.ESCAPE or ai.state == GhostAI.State.FLEE, "Al verse descubierta escapa (estado %s)" % ai.state_name)
	check(prey.global_position.x > start.x + 0.8, "Escapa por el otro extremo (x %.1f -> %.1f)" % [start.x, prey.global_position.x])
	m.queue_free()
	await frames(3)


# --- El Cazador IA se asoma tras los muros ------------------------------------------

func hunter_peek() -> void:
	GameManager.config.ai_hunter_peek_chance = 1.0
	var m: MatchScenario = await new_match(DummySpawn.Role.GHOST)
	var me := m.get_controlled_character() as Ghost
	place(me, Vector3(-8.0, 0, 1.5))  # Lejos, en el pasillo.
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g != me:
			(g as Ghost).frozen = true
			place(g, Vector3(-9.0, 0, 1.5))
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	var ai := ai_of(hunter) as HunterAI
	place(hunter, Vector3(5.0, 0, -1.5))
	# Investiga un ruido delante del muro de la cocina.
	ai._start_investigate(Vector3(5.0, 0, -3.0), false)
	var peeking := await wait_for(func(): return ai._peeking, 10.0)
	check(peeking, "Tras mirar alrededor va a asomarse por un extremo del muro")
	var at_end := await wait_for(func():
		var p := hunter.global_position
		return ai._peek_timer > 0.0 and (Vector2(p.x - 7.2, p.z + 5.2).length() < 0.9 or Vector2(p.x - 2.8, p.z + 5.2).length() < 0.9), 10.0)
	check(at_end, "Se asoma desde un extremo del muro (%s)" % hunter.global_position)
	m.queue_free()
	await frames(3)


# --- El Cazador IA y los señuelos ---------------------------------------------------

func hunter_decoy() -> void:
	var cfg := GameManager.config
	cfg.ai_hunter_decoy_follow_chance = 0.0
	cfg.ai_hunter_peek_chance = 0.0
	var m: MatchScenario = await new_match(DummySpawn.Role.GHOST)
	var me := m.get_controlled_character() as Ghost
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g != me:
			(g as Ghost).frozen = true
			place(g, Vector3(9.0, 0, 7.5))
	var hunter: Hunter = get_tree().get_nodes_in_group("hunters")[0]
	hunter.frozen = true
	var ai := ai_of(hunter) as HunterAI
	# Señuelo en la Sala; el Cazador en el pasillo, a pocos metros (lo oye); la Presa lejos.
	place(me, Vector3(-3.0, 0, -2.0))
	await frames(2)
	me.place_decoy()
	place(me, Vector3(8.5, 0, 7.5))
	place(hunter, Vector3(-3.0, 0, 1.5))
	await frames(5)
	ai._set_state(HunterAI.State.PATROL)
	ai.clear_destination()

	me.trigger_decoy()
	var reacted := await wait_for(func(): return ai.state == HunterAI.State.INVESTIGATE, 3.0)
	check(reacted, "Pasos nuevos: el Cazador IA va a investigar")
	check(not ai.suspects_decoy_at(me.decoy_position), "Una sola vez no le parece un señuelo")

	# Otra ocasión en el mismo sitio, con el Cazador ya patrullando.
	await frames(int(cfg.decoy_steps * cfg.decoy_step_interval * 60.0) + 120)
	ai._set_state(HunterAI.State.PATROL)
	ai.clear_destination()
	me.decoy_cooldown_left = 0.0
	me.trigger_decoy()
	await frames(int(cfg.decoy_steps * cfg.decoy_step_interval * 60.0) + 10)
	check(ai.suspects_decoy_at(me.decoy_position), "Pasos parados otra vez en el mismo sitio: sospecha que es un señuelo")
	check(ai.state == HunterAI.State.PATROL, "No deja lo que hacía por un señuelo (estado %s)" % ai.state_name)

	# Unos pasos en otro sitio sí le interesan.
	# (La Presa sigue lejos: si el Cazador la viera, la perseguiría en vez de investigar.)
	GameManager.make_noise(Vector3(-6.0, 0, 1.5), cfg.run_noise_radius, me)
	var other := await wait_for(func(): return ai.state == HunterAI.State.INVESTIGATE, 2.0)
	check(other, "Pasos en otro sitio sí los investiga")
	m.queue_free()
	await frames(3)
