extends Node
## Simulación IA contra IA (escenario TestAI) más rápida que el tiempo real, para equilibrar la IA.
## El Hunter queda congelado 8 s al principio, como en una partida.
## Uso (desde la carpeta del proyecto):
##   SIM_SEED=1 <ruta a Godot> --headless --fixed-fps 60 --path . res://tools/ai_simulation.tscn
## Imprime una línea de tiempo (estados, disparos, capturas, puertas, luces, armarios) y un resumen.

const SIM_SECONDS := 180.0  # Duración de una partida por defecto.

var s: TestScenario
var t := 0.0
var events: Array[String] = []
var counts := {}
var last_states := {}
var last_pos := {}
var still_time := {}
var max_still := {}
var travelled := {}


func ev(text: String) -> void:
	events.append("[%5.1f] %s" % [t, text])


func count(key: String) -> void:
	counts[key] = counts.get(key, 0) + 1


func _ready() -> void:
	seed(int(OS.get_environment("SIM_SEED")) if OS.get_environment("SIM_SEED") != "" else 1)
	s = load("res://scenes/test/TestAI.tscn").instantiate()
	add_child(s)
	await get_tree().physics_frame
	for c in s.get_node("Characters").get_children():
		var ch := c as CharacterBase
		if ch == null:
			continue
		last_pos[ch] = ch.global_position
		still_time[ch] = 0.0
		max_still[ch] = 0.0
		travelled[ch] = 0.0
		if ch is Hunter:
			(ch as Hunter).net_fired.connect(func(h):
				count("redes")
				var info := ""
				for g in get_tree().get_nodes_in_group("ghosts"):
					var gg := g as Ghost
					if gg.state == Ghost.State.FREE:
						info += " | %s d=%.1f v=%.1f ve=%s" % [gg.name, AIController.flat_distance(gg.global_position, h.global_position), Vector2(gg.velocity.x, gg.velocity.z).length(), h.vision.can_see(gg)]
				ev("Hunter dispara red" + info))
		if ch is Ghost:
			(ch as Ghost).state_changed.connect(func(g, o, n):
				var names := ["FREE", "NETTED", "HIDDEN", "CAPTURED"]
				ev("%s: %s -> %s" % [g.name, names[o], names[n]])
				count("ghost_" + names[n]))
	for d in get_tree().get_nodes_in_group("doors"):
		(d as Door).open_changed.connect(func(door, open): count("puertas"); ev("%s %s" % [door.name, "abierta" if open else "cerrada"]))
	for r in get_tree().get_nodes_in_group("rooms"):
		(r as Room).lit_changed.connect(func(room, lit): count("luces"); ev("Luz %s %s" % [room.name, "ON" if lit else "OFF"]))
	for h in get_tree().get_nodes_in_group("hiding_spots"):
		(h as HidingSpot).searched.connect(func(spot, found): count("registros"); ev("Registro %s: %s" % [spot.name, "ENCONTRADO" if found else "vacío"]))


func _physics_process(delta: float) -> void:
	if s == null or last_pos.is_empty():
		return
	t += delta
	for h in get_tree().get_nodes_in_group("hunters"):
		(h as CharacterBase).frozen = t < 8.0
	for c in s.get_node("Characters").get_children():
		var ch := c as CharacterBase
		if ch == null:
			continue
		var ai := ch.controller as AIController
		if ai and last_states.get(ch, "") != ai.state_name:
			ev("%s estado %s" % [ch.name, ai.state_name])
			count("%s_%s" % ["hunter" if ch is Hunter else "ghost", ai.state_name])
			last_states[ch] = ai.state_name
		var moved := Vector2(ch.global_position.x - last_pos[ch].x, ch.global_position.z - last_pos[ch].z).length()
		travelled[ch] += moved
		last_pos[ch] = ch.global_position
		var parked := ch is Ghost and (ch as Ghost).state != Ghost.State.FREE
		var idle_ok := ai != null and ai.state_name in ["IDLE", "HIDDEN", "NETTED", "CAPTURE", "SEARCH", "INVESTIGATE"]
		if moved < 0.005 and not parked and not idle_ok:
			still_time[ch] += delta
			max_still[ch] = maxf(max_still[ch], still_time[ch])
		else:
			still_time[ch] = 0.0
	var free := 0
	for g in get_tree().get_nodes_in_group("ghosts"):
		if (g as Ghost).state != Ghost.State.CAPTURED:
			free += 1
	if t >= SIM_SECONDS or free == 0:
		finish(free)


func finish(free: int) -> void:
	set_physics_process(false)
	print("=== TIMELINE (primeros 70 eventos) ===")
	for e in events.slice(0, 70):
		print(e)
	print("=== RESUMEN t=%.1f s, ghosts libres=%d ===" % [t, free])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %s: %d" % [k, counts[k]])
	for ch in travelled:
		print("  %s recorrió %.0f m, máx. tiempo quieto sin motivo %.1f s" % [ch.name, travelled[ch], max_still[ch]])
	get_tree().quit()
