extends Node
## Distribución de la casa: sin muebles que solo estorban, 1-2 armarios por habitación y muros
## sueltos como escondite: tapan la visión de frente, pero asomándose por un extremo se ve a quien
## está detrás, y se puede pasar (escapar) por los dos extremos.

## Muros sueltos de House.tscn: centro, dirección a lo largo y longitud.
const WALLS := [
	{"name": "Sala", "center": Vector3(-7.0, 0, -5.4), "axis": Vector3(0, 0, 1), "length": 2.4},
	{"name": "Cocina", "center": Vector3(5.0, 0, -5.2), "axis": Vector3(1, 0, 0), "length": 2.6},
	{"name": "Dormitorio", "center": Vector3(3.0, 0, 6.0), "axis": Vector3(1, 0, 0), "length": 2.6},
	{"name": "Dormitorio (oeste)", "center": Vector3(-6.0, 0, 5.4), "axis": Vector3(1, 0, 0), "length": 2.6},
]

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


func place(c: CharacterBase, at: Vector3, look_at_point: Vector3 = Vector3.INF) -> void:
	c.global_position = Vector3(at.x, c.global_position.y, at.z)
	c.velocity = Vector3.ZERO
	if look_at_point != Vector3.INF:
		var d := look_at_point - c.global_position
		c.rotation.y = atan2(-d.x, -d.z)


func run() -> void:
	GameManager.selected_role = DummySpawn.Role.HUNTER
	GameManager.series = null
	var m: MatchScenario = load("res://scenes/game/Match.tscn").instantiate()
	add_child(m)
	await frames(5)
	var house: House = m.get_node("House")
	check(not house.has_node("Geometry/Furniture"), "Sin muebles en medio de las habitaciones")

	# Armarios por habitación.
	var per_room := {}
	for spot in get_tree().get_nodes_in_group("hiding_spots"):
		var room := Room.find_at(get_tree(), (spot as Node3D).global_position + (spot as Node3D).global_basis.z * 0.3)
		var key: String = room.name if room else "?"
		per_room[key] = per_room.get(key, 0) + 1
	check(per_room.values().all(func(n): return n >= 1 and n <= 2) and not per_room.has("?"), "1 o 2 armarios por habitación %s" % per_room)

	# Muros sueltos.
	var hunter: Hunter = m.get_controlled_character() as Hunter
	hunter.frozen = true
	var ghosts := get_tree().get_nodes_in_group("ghosts")
	var prey: Ghost = ghosts[0]
	for g in ghosts:
		(g as Ghost).frozen = true
		if (g as Ghost).state == Ghost.State.HIDDEN:
			(g as Ghost).expel_from_hiding()
		if g != prey:
			place(g, Vector3(0, 0, 1.5))  # Al pasillo, lejos.
	await frames(10)
	var map := house.get_world_3d().navigation_map
	for wall in WALLS:
		var center: Vector3 = wall["center"]
		var axis: Vector3 = wall["axis"]
		var half: float = wall["length"] * 0.5
		var normal := Vector3(axis.z, 0, -axis.x)
		var label: String = wall["name"]
		for side in [1.0, -1.0]:
			var behind: Vector3 = normal * side
			place(prey, center + behind * 0.5)
			await frames(2)
			# De frente (aunque esté cerca y desplazado a lo largo del muro): no se ve.
			var hidden := true
			for along in [0.0, half * 0.4, -half * 0.4]:
				place(hunter, center - behind * 2.0 + axis * along, prey.global_position)
				await frames(2)
				if hunter.vision.can_see(prey):
					hidden = false
			check(hidden, "Muro de la %s: de frente no se ve a quien está detrás (lado %+d)" % [label, side])
			# Asomándose por cada extremo, sí.
			for end in [1.0, -1.0]:
				place(hunter, center + axis * end * (half + 0.9) + behind * 0.2, prey.global_position)
				await frames(2)
				check(hunter.vision.can_see(prey), "Muro de la %s: asomándose por un extremo se le ve (lado %+d, extremo %+d)" % [label, side, end])
		# Se puede pasar por los dos extremos (para escapar por el otro lado).
		for end in [1.0, -1.0]:
			var gap: Vector3 = center + axis * end * (half + 0.6)
			var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, 1.5), gap, true)
			var reached := not path.is_empty() and Vector2(path[-1].x - gap.x, path[-1].z - gap.z).length() < 0.5
			check(reached, "Muro de la %s: se puede pasar por el extremo %+d" % [label, end])
