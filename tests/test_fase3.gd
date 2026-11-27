extends Node
## Prueba de la Fase 3: puertas, luces, armarios, ruido, maniquíes en ruta y torreta.

class TestController extends CharacterController:
	var press := false
	var hold := false
	func update_intent(_c: CharacterBase, intent: CharacterIntent) -> void:
		intent.interact = press
		intent.interact_held = hold or press
		press = false

var failures := 0
var noises: Array = []


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func load_scenario(path: String) -> TestScenario:
	for c in get_children():
		c.queue_free()
	await frames(2)
	var s: TestScenario = load(path).instantiate()
	add_child(s)
	await frames(3)
	return s


func place(c: CharacterBase, x: float, z: float, facing: Vector3) -> void:
	c.global_position = Vector3(x, 0, z)
	c.rotation.y = atan2(-facing.x, -facing.z)
	c.velocity = Vector3.ZERO


func control(c: CharacterBase) -> TestController:
	var t := TestController.new()
	c.add_child(t)
	c.set_controller(t, true)
	return t


func find(group: String, node_name: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if n.name == node_name:
			return n
	return null


func _ready() -> void:
	GameManager.noise_made.connect(func(p, r, src): noises.append(src))
	await run()
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func run() -> void:
	# ---------------- TestHunter ----------------
	var s := await load_scenario("res://scenes/test/TestHunter.tscn")
	var chars := s.get_node("Characters").get_children()
	check(chars.size() == 6, "TestHunter: 6 personajes (%d)" % chars.size())
	var hunter: Hunter = chars[0]
	var g_armario: Ghost = chars[1]
	var g_luz: Ghost = chars[2]
	var g_puerta: Ghost = chars[3]
	var g_oscuro: Ghost = chars[4]
	var g_ruta: Ghost = chars[5]
	var dorm: Room = find("rooms", "Dormitorio")
	var door_cp: Door = find("doors", "DoorCocinaPasillo")
	check(g_armario.state == Ghost.State.HIDDEN and not g_armario.visible, "Ghost empieza escondido en el armario")
	check(not dorm.lit, "Dormitorio empieza a oscuras")
	check(not door_cp.is_open, "Puerta cocina-pasillo empieza cerrada")
	var ruta_start := g_ruta.global_position
	var t := control(hunter)

	# Oscuridad
	place(hunter, -3.2, 6.0, Vector3.LEFT)
	await frames(2)
	check(not hunter.vision.can_see(g_oscuro), "A 6 m en la oscuridad no ve al Ghost")
	dorm.set_lit(true)
	check(hunter.vision.can_see(g_oscuro), "Con la luz encendida sí lo ve")

	# Puerta cerrada tapa la visión
	place(hunter, 5, 2.0, Vector3.FORWARD)
	await frames(2)
	check(not hunter.vision.can_see(g_puerta), "La puerta cerrada tapa la visión")
	door_cp.set_open(true, hunter)
	await frames(20)
	check(hunter.vision.can_see(g_puerta), "Con la puerta abierta sí lo ve")
	check(g_ruta.global_position.distance_to(ruta_start) > 1.0, "El maniquí en ruta se mueve (%.1f m)" % g_ruta.global_position.distance_to(ruta_start))
	check(noises.has(g_ruta), "Correr hace ruido de pasos")

	# Registrar armario
	place(hunter, -8.5, -2.0, Vector3.LEFT)
	await frames(2)
	check(hunter.find_interactable() is HidingSpot, "Junto al armario se ofrece REGISTRAR")
	t.press = true
	t.hold = true
	await frames(30)
	check(g_armario.state == Ghost.State.HIDDEN, "Registrar requiere mantener (aún no ha terminado)")
	await frames(40)
	t.hold = false
	check(g_armario.state == Ghost.State.FREE, "Registrar expulsa al Ghost")
	check(not g_armario.can_hide(), "Tras ser expulsado no puede esconderse enseguida")

	# Puerta e interruptor
	var door_sp: Door = find("doors", "DoorSalaPasillo")
	place(hunter, -5, -1.2, Vector3.BACK)
	await frames(2)
	t.press = true
	await frames(25)
	check(not door_sp.is_open, "[E] cierra la puerta sala-pasillo")
	var sala: Room = find("rooms", "Sala")
	place(hunter, -6.8, -1.0, Vector3.FORWARD)
	await frames(2)
	check(hunter.find_interactable() is LightSwitch, "Junto al interruptor se ofrece APAGAR LUZ (%s)" % hunter.find_interactable())
	t.press = true
	await frames(2)
	check(not sala.lit, "[E] apaga la luz de la sala")

	# Ghost se esconde y sale
	var tg := control(g_luz)
	place(g_luz, 8.5, -5.0, Vector3.RIGHT)
	await frames(2)
	tg.press = true
	await frames(3)
	check(g_luz.state == Ghost.State.HIDDEN and not g_luz.is_detectable(), "El Ghost se esconde en el armario de la cocina")
	tg.press = true
	await frames(3)
	check(g_luz.state == Ghost.State.FREE and g_luz.global_position.x < 8.95, "El Ghost sale del armario")

	# Reset restaura la casa
	s.reset_scenario()
	await frames(3)
	check(sala.lit and not dorm.lit and door_sp.is_open and not door_cp.is_open, "R restaura luces y puertas del escenario")
	check(g_armario.state == Ghost.State.HIDDEN, "R vuelve a esconder al Ghost del armario")

	# ---------------- TestGhost ----------------
	s = await load_scenario("res://scenes/test/TestGhost.tscn")
	chars = s.get_node("Characters").get_children()
	var ghost: Ghost = chars[0]
	var vigia: Hunter = chars[1]
	var patrulla: Hunter = chars[2]
	var p_start := patrulla.global_position
	await frames(240)
	check(patrulla.global_position.distance_to(p_start) > 5.0, "El Hunter patrulla (%.1f m)" % patrulla.global_position.distance_to(p_start))
	var tgh := control(ghost)
	place(ghost, -4.5, 1.5, Vector3.RIGHT)
	await frames(90)
	check(ghost.state == Ghost.State.NETTED, "El Hunter torreta dispara al verte (estado=%d)" % ghost.state)

	# ---------------- Prototype01 ----------------
	s = await load_scenario("res://scenes/test/Prototype01.tscn")
	check(get_tree().get_nodes_in_group("doors").size() == 5, "Prototype01: 5 puertas")
	check(get_tree().get_nodes_in_group("hiding_spots").size() == 4, "Prototype01: 4 armarios (2 en el dormitorio)")
	check(get_tree().get_nodes_in_group("rooms").size() == 4, "Prototype01: 4 habitaciones con luz")
