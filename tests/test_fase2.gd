extends Node
## Prueba de la Fase 2 parcial: visión, red, captura y escape.

class TestController extends CharacterController:
	var aim_target: Node3D
	var fire_now := false
	var approach_and_capture := false
	func update_intent(c: CharacterBase, intent: CharacterIntent) -> void:
		if aim_target:
			intent.aim_point = aim_target.global_position
			intent.has_aim = true
		intent.fire = fire_now
		fire_now = false
		if approach_and_capture and aim_target:
			var to := aim_target.global_position - c.global_position
			to.y = 0
			if to.length() > 1.1:
				intent.move_dir = to.normalized()
			else:
				intent.interact_held = true

var scenario: TestScenario
var frame := 0
var failures := 0
var hunter: Hunter
var g_sala: Ghost
var g_cocina: Ghost
var ctrl := TestController.new()


func _ready() -> void:
	scenario = load("res://scenes/test/Prototype01.tscn").instantiate()
	add_child(scenario)


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func place(c: CharacterBase, pos: Vector3, facing: Vector3) -> void:
	c.global_position = pos
	c.rotation.y = atan2(-facing.x, -facing.z)
	c.velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	frame += 1
	match frame:
		5:
			var chars := scenario.get_node("Characters").get_children()
			check(chars.size() == 4, "4 personajes (1 Hunter + 3 Ghosts): %d" % chars.size())
			hunter = chars[0]
			g_sala = chars[1]
			g_cocina = chars[2]
			check(GameManager.debug_vision, "Conos de visión activos por defecto")
			hunter.add_child(ctrl)
			hunter.set_controller(ctrl, true)
			place(hunter, Vector3(-1, 0, -1.5), Vector3.RIGHT)
		8:
			check(not hunter.vision.can_see(g_cocina), "La pared tapa al Ghost de la cocina")
			scenario._update_player_visibility()
			check(not g_cocina.visible, "Ghost tapado no se dibuja para el Hunter")
			place(hunter, Vector3(-1, 0, -4), Vector3.RIGHT)
		11:
			check(hunter.vision.can_see(g_cocina), "A través de la puerta sí lo ve")
			scenario._update_player_visibility()
			check(g_cocina.visible, "Ghost visto sí se dibuja")
			place(hunter, Vector3(-1, 0, -4), Vector3.LEFT)
		13:
			check(not hunter.vision.can_see(g_cocina), "De espaldas no lo ve (fuera del cono)")
			var mesh: ImmediateMesh = hunter.get_node("VisionSensor/VisionDebug").mesh
			check(mesh.get_surface_count() >= 1, "Se dibuja el cono de depuración")
			scenario.reset_scenario()
		15:
			ctrl.aim_target = g_sala
			ctrl.fire_now = true
		17:
			check(not hunter.is_net_ready(), "Recarga activa tras disparar (%.2f s)" % hunter.net_cooldown_left)
		50:
			check(g_sala.state == Ghost.State.NETTED, "La red inmoviliza al Ghost")
			var pos := g_sala.global_position
			g_sala.intent.move_dir = Vector3.RIGHT
			ctrl.approach_and_capture = true
		200:
			check(g_sala.state == Ghost.State.CAPTURED, "Captura completada (estado=%d)" % g_sala.state)
			check(not g_sala.visible, "Ghost capturado desaparece")
			ctrl.approach_and_capture = false
			scenario.reset_scenario()
		203:
			check(g_sala.state == Ghost.State.FREE and g_sala.visible == g_sala._revealed, "R libera al Ghost capturado")
			ctrl.fire_now = true
		240:
			check(g_sala.state == Ghost.State.NETTED, "Segunda red acierta")
		560:
			check(g_sala.state == Ghost.State.FREE, "Sin captura, el Ghost se libera tras 5 s")
			print("RESULT failures=%d" % failures)
			get_tree().quit(1 if failures else 0)
