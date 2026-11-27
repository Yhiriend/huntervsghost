class_name GhostAI
extends AIController
## IA del Ghost. Prioridades (de mayor a menor):
##   NETTED  Atrapado en una red: no puede hacer nada (al liberarse huye: ESCAPE).
##   HIDDEN  Dentro de un armario: sale cuando lleva un rato sin percibir al Hunter.
##   FLEE    Ve (o oye muy cerca) al Hunter: huye hacia el punto más lejano y que el Hunter no ve,
##           cerrando puertas detrás de sí.
##   HIDE    Cuando ya no le ven: va a un armario libre al que llegue antes que el Hunter.
##           Nunca se esconde a la vista del Hunter (sabría dónde buscar).
##   COVER   O se esconde detrás de un muro suelto, en el lado contrario al Hunter. Se queda
##           quieto; si el Hunter se asoma por un extremo (le ve), escapa por el otro.
##   ROAM    Pasea en sigilo (sin ruido) por la casa; a veces se para y a veces apaga luces.
##           Solo corre (y hace ruido) cuando huye.
## Solo usa su visión y su oído: no sabe dónde está el Hunter si no lo percibe. Como el jugador
## Presa, ve al Hunter cuando el Hunter le ve a él.

enum State { ROAM, IDLE, FLEE, HIDE, HIDDEN, NETTED, ESCAPE, COVER }

const STATE_NAMES := ["ROAM", "IDLE", "FLEE", "HIDE", "HIDDEN", "NETTED", "ESCAPE", "COVER"]
const FLEE_SAMPLES := 14
## Cada cuánto se replantea la huida como máximo (cambiar de rumbo a menudo le hace zigzaguear).
const FLEE_REPLAN_TIME := 4.0
## Tras perder de vista al Hunter, sigue huyendo este tiempo antes de calmarse.
const CALM_DOWN_TIME := 3.0
## Tiempo fuera de la vista del Hunter a partir del cual esconderse es seguro.
const UNSEEN_BEFORE_HIDING := 1.0
## Durante este tiempo evita pasear hacia donde percibió al Hunter.
const AVOID_THREAT_TIME := 15.0
const DOOR_CLOSE_DISTANCE := 1.5
## Distancia al muro a la que se pone detrás.
const COVER_DISTANCE := 0.5
## Al escapar de un muro, mantiene la ruta por el extremo libre este tiempo.
const COVER_ESCAPE_TIME := 1.5

var state: State = State.ROAM
var ghost: Ghost

var _threat_position := Vector3.ZERO
var _threat_time: float = -100.0
var _flee_replan: float = 0.0
var _idle_timer: float = 0.0
var _hide_target: HidingSpot = null
var _hidden_since: float = 0.0
var _hide_duration: float = 0.0
var _last_room: Room = null
## Última habitación en la que se decidió si apagar la luz (para decidirlo una vez por visita).
var _light_room: Room = null
## Puerta -> momento en que la cerró (para no abrir y cerrar sin parar).
var _closed_doors: Dictionary = {}
## En esta huida ya se decidió si esconderse (para decidirlo una sola vez).
var _hide_decided: bool = false
## Muro tras el que se esconde: {wall, side, point} (side: lado del muro, +1/-1).
var _cover: Dictionary = {}
var _cover_since: float = -1.0
var _cover_duration: float = 0.0


func _ready() -> void:
	super()
	ghost = character as Ghost
	state_name = STATE_NAMES[state]


func reset() -> void:
	super()
	_release_reservation()
	_release_cover()
	state = State.ROAM
	_threat_time = -100.0
	_closed_doors.clear()
	_last_room = null
	_light_room = null


func think(delta: float, intent: CharacterIntent) -> void:
	match ghost.state:
		Ghost.State.CAPTURED:
			_set_state(State.NETTED)
			return
		Ghost.State.NETTED:
			_set_state(State.NETTED)
			return
	if state == State.NETTED:
		# Se acaba de liberar: huir.
		_set_state(State.ESCAPE)
		_flee_replan = 0.0

	_perceive()
	var threat_age := now - _threat_time
	var threat_distance := flat_distance(_threat_position, character.global_position)

	if ghost.state == Ghost.State.HIDDEN:
		_set_state(State.HIDDEN)
		_do_hidden(intent, threat_age)
		return

	var threatened := threat_age < 0.2 and threat_distance < GameManager.config.ai_ghost_flee_distance
	if threatened and state != State.FLEE and state != State.ESCAPE and state != State.HIDE and state != State.COVER:
		_react_to_threat(threat_distance)
	elif state == State.HIDE and threatened and _hide_target and \
			flat_distance(_threat_position, _hide_target.global_position) < flat_distance(character.global_position, _hide_target.global_position):
		# El Hunter está más cerca del armario que él: mejor huir.
		_release_reservation()
		_set_state(State.FLEE)
		_flee_replan = 0.0

	match state:
		State.ROAM:
			_do_roam(intent, delta)
		State.IDLE:
			_do_idle(intent, delta)
		State.FLEE, State.ESCAPE:
			_do_flee(intent, delta, threat_age)
		State.HIDE:
			_do_hide(intent, delta)
		State.COVER:
			_do_cover(intent, delta, threat_age)


func on_stuck() -> void:
	if state == State.HIDE or state == State.COVER:
		_release_reservation()
		_set_state(State.FLEE)
	_flee_replan = 0.0


func _set_state(new_state: State) -> void:
	if new_state != state and (state == State.HIDE or state == State.HIDDEN) and new_state != State.HIDDEN:
		_release_reservation()
	if new_state != state and state == State.COVER:
		_release_cover()
	state = new_state
	state_name = STATE_NAMES[state]


func _perceive() -> void:
	for node in character.get_tree().get_nodes_in_group("hunters"):
		var hunter := node as Hunter
		# Como el jugador Presa: ve al Hunter si el Hunter le ve a él.
		if ghost.vision.can_see(hunter) or hunter.vision.can_see(ghost):
			_threat_position = hunter.global_position
			_threat_time = now
			return
	var noise := recent_noise(0.5)
	if not noise.is_empty():
		var noise_position: Vector3 = noise["position"]
		if flat_distance(noise_position, character.global_position) < GameManager.config.ai_ghost_flee_distance * 0.7:
			_threat_position = noise_position
			_threat_time = now


## Le están viendo: primero huir. Esconderse a la vista del Hunter sería delatarse.
func _react_to_threat(_threat_distance: float) -> void:
	_set_state(State.FLEE)
	_flee_replan = 0.0
	_hide_decided = false


# --- Estados --------------------------------------------------------------------

func _do_roam(intent: CharacterIntent, delta: float) -> void:
	if not has_destination():
		set_destination(_pick_roam_point())
	if navigate(intent, delta):
		_idle_timer = randf_range(2.0, 6.0)
		_set_state(State.IDLE)
	intent.sneak = true
	_maybe_turn_off_light(intent)


func _do_idle(intent: CharacterIntent, delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		if randf() < 0.3 and now > 5.0 and _choose_hiding_place():
			return
		_set_state(State.ROAM)
	_maybe_turn_off_light(intent)


func _do_flee(intent: CharacterIntent, delta: float, threat_age: float) -> void:
	_flee_replan -= delta
	# Mantiene el rumbo salvo que llegue, pase el tiempo o el Hunter quede más cerca del destino.
	var destination_compromised := has_destination() and \
			flat_distance(_destination, _threat_position) < flat_distance(_destination, character.global_position)
	if _flee_replan <= 0.0 or not has_destination() or destination_compromised:
		_flee_replan = FLEE_REPLAN_TIME
		set_destination(_pick_flee_point())
	navigate(intent, delta)
	_close_doors_behind(intent)
	# Fuera de la vista del Hunter: quizá esconderse (se decide una vez por huida).
	if threat_age > UNSEEN_BEFORE_HIDING and not _hide_decided:
		_hide_decided = true
		if randf() < GameManager.config.ai_ghost_hide_chance and _choose_hiding_place():
			return
	if threat_age > CALM_DOWN_TIME:
		clear_destination()
		_set_state(State.ROAM)


## Esconderse: en un armario o detrás de un muro suelto. false si no hay sitio seguro.
func _choose_hiding_place() -> bool:
	var spot := _best_hiding_spot()
	var cover := _best_cover()
	if not cover.is_empty() and (spot == null or randf() < GameManager.config.ai_ghost_wall_chance):
		_go_cover(cover)
		return true
	if spot:
		_go_hide(spot)
		return true
	return false


func _go_hide(spot: HidingSpot) -> void:
	_release_reservation()
	_hide_target = spot
	spot.set_meta("reserved_by", ghost)
	set_destination(spot.get_interaction_point())
	_set_state(State.HIDE)


func _do_hide(intent: CharacterIntent, delta: float) -> void:
	if _hide_target == null or not _is_spot_available(_hide_target):
		_release_reservation()
		_set_state(State.ROAM)
		return
	var point := _hide_target.get_interaction_point()
	if flat_distance(point, character.global_position) > _hide_target.interact_range * 0.7:
		set_destination(point)
		navigate(intent, delta)
		# Si nadie le persigue, va en silencio.
		intent.sneak = now - _threat_time > CALM_DOWN_TIME
		return
	intent.interact = true
	intent.interact_with = _hide_target
	_hidden_since = now
	_hide_duration = GameManager.config.ai_ghost_min_hide_time * randf_range(1.0, 2.5)


func _do_hidden(intent: CharacterIntent, threat_age: float) -> void:
	# Sale cuando lleva un rato escondido y hace tiempo que no percibe al Hunter.
	var calm_for := minf(threat_age, now - _hidden_since)
	if now - _hidden_since >= _hide_duration and calm_for >= GameManager.config.ai_ghost_min_hide_time * 0.5:
		intent.interact = true
		intent.interact_with = ghost.hiding_spot
		_release_reservation()
		_set_state(State.ROAM)


# --- Muros sueltos -----------------------------------------------------------------

## El lado de un muro suelto contrario a donde percibió al Hunter, si llega antes que él y el
## muro le tapa. Sin amenaza reciente, un lado cualquiera. {} si no hay ninguno bueno.
func _best_cover() -> Dictionary:
	var house := House.find(character.get_tree())
	if house == null:
		return {}
	var threat_known := now - _threat_time < 6.0
	var best: Dictionary = {}
	var best_length := INF
	for wall in house.cover_walls():
		var center: Vector3 = wall["center"]
		var normal: Vector3 = wall["normal"]
		var side := (1.0 if (center - _threat_position).dot(normal) > 0.0 else -1.0) if threat_known else (1.0 if randf() < 0.5 else -1.0)
		var point := center + normal * side * COVER_DISTANCE
		if not _cover_available(wall["node"], side):
			continue
		var length := path_length_to(point)
		if threat_known and (not _blocked_from_threat(point) or flat_distance(_threat_position, point) < length * 0.8):
			continue
		if length < best_length:
			best = {"wall": wall, "side": side, "point": point}
			best_length = length
	return best


func _go_cover(cover: Dictionary) -> void:
	_release_reservation()
	_release_cover()
	_cover = cover
	(cover["wall"]["node"] as Node).set_meta(_cover_key(cover["side"]), ghost)
	_cover_since = -1.0
	set_destination(cover["point"])
	_set_state(State.COVER)


func _do_cover(intent: CharacterIntent, delta: float, threat_age: float) -> void:
	if _cover.is_empty():
		_set_state(State.ROAM)
		return
	var point: Vector3 = _cover["point"]
	if _cover_since < 0.0:
		# De camino. Si el Hunter queda más cerca del muro que él, mejor huir.
		if threat_age < 0.2 and flat_distance(_threat_position, point) < flat_distance(character.global_position, point):
			_set_state(State.FLEE)
			_flee_replan = 0.0
			return
		if flat_distance(point, character.global_position) > 0.25:
			if not has_destination():
				set_destination(point)
			var reached := navigate(intent, delta)
			intent.sneak = now - _threat_time > CALM_DOWN_TIME
			# La navegación da por llegado a ~0,6 m: suficiente detrás del muro.
			if not reached:
				return
		clear_destination()
		_cover_since = now
		_cover_duration = GameManager.config.ai_ghost_min_hide_time * randf_range(1.0, 2.5)
	# Quieto detrás del muro (sin moverse no hace ruido).
	if threat_age < 0.3 and _cover_exposed():
		_escape_cover()
		return
	if now - _cover_since >= _cover_duration and threat_age >= GameManager.config.ai_ghost_min_hide_time * 0.5:
		_set_state(State.ROAM)


## El Hunter está en su lado del muro o tiene línea de visión hasta él.
func _cover_exposed() -> bool:
	var wall: Dictionary = _cover["wall"]
	var threat_side := 1.0 if (_threat_position - wall["center"]).dot(wall["normal"]) > 0.0 else -1.0
	return threat_side == float(_cover["side"]) or not _blocked_from_threat(character.global_position)


## Le han descubierto: escapa por el extremo del muro más alejado del Hunter.
func _escape_cover() -> void:
	var wall: Dictionary = _cover["wall"]
	var center: Vector3 = wall["center"]
	var axis: Vector3 = wall["axis"]
	var half: float = wall["half"]
	var end := 1.0 if flat_distance(center + axis * half, _threat_position) > flat_distance(center - axis * half, _threat_position) else -1.0
	var away := center + axis * end * (half + 2.5) + (wall["normal"] as Vector3) * float(_cover["side"]) * 0.5
	_set_state(State.ESCAPE)
	set_destination(away)
	_flee_replan = COVER_ESCAPE_TIME
	_hide_decided = false


func _cover_key(side: float) -> String:
	return "cover_reserved_%s" % ("a" if side > 0.0 else "b")


func _cover_available(wall_node: Node, side: float) -> bool:
	var key := _cover_key(side)
	if not wall_node.has_meta(key):
		return true
	var reserved: Variant = wall_node.get_meta(key)
	return reserved == ghost or not is_instance_valid(reserved)


func _release_cover() -> void:
	if not _cover.is_empty():
		var node: Node = _cover["wall"]["node"]
		var key := _cover_key(_cover["side"])
		if is_instance_valid(node) and node.has_meta(key) and node.get_meta(key) == ghost:
			node.remove_meta(key)
	_cover = {}
	_cover_since = -1.0


# --- Decisiones -----------------------------------------------------------------

## Punto lejano del Hunter, preferiblemente sin pasar a su lado.
func _pick_flee_point() -> Vector3:
	var me := character.global_position
	var away := Vector3(me.x - _threat_position.x, 0.0, me.z - _threat_position.z).normalized()
	var best := me + away * 4.0
	var best_score := -INF
	for i in FLEE_SAMPLES:
		var point := random_floor_point()
		var to_point := Vector3(point.x - me.x, 0.0, point.z - me.z)
		if to_point.length() < 2.0:
			continue
		var score := flat_distance(point, _threat_position) - 0.3 * to_point.length()
		# Penaliza los puntos que obligan a ir hacia el Hunter.
		if to_point.normalized().dot(-away) > 0.3:
			score -= 12.0
		# Prefiere puntos que el Hunter no ve (detrás de paredes): rompe la línea de visión.
		if _blocked_from_threat(point):
			score += 6.0
		# Y habitaciones a oscuras, donde el Hunter ve mucho menos.
		if Room.is_dark_at(character.get_tree(), point):
			score += 4.0
		if score > best_score:
			best_score = score
			best = point
	return best


func _any_dark_room() -> bool:
	for node in character.get_tree().get_nodes_in_group("rooms"):
		if not (node as Room).lit:
			return true
	return false


func _blocked_from_threat(point: Vector3) -> bool:
	var eye := Vector3.UP * VisionSensor.EYE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(_threat_position + eye, point + eye, 1)
	return not character.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _pick_roam_point() -> Vector3:
	var current := Room.find_at(character.get_tree(), character.global_position)
	var avoid_threat := now - _threat_time < AVOID_THREAT_TIME
	for attempt in 10:
		var point := random_floor_point()
		var room := Room.find_at(character.get_tree(), point)
		if room == _last_room:
			continue
		# Evita acercarse a donde percibió al Hunter hace poco.
		if avoid_threat and flat_distance(point, _threat_position) < flat_distance(character.global_position, _threat_position):
			continue
		# Prefiere las habitaciones a oscuras (allí el Hunter ve mucho menos).
		if room != null and room.lit and attempt < 5 and _any_dark_room():
			continue
		_last_room = current
		return point
	return random_floor_point()


## Armario libre al que llega antes que el Hunter (si lo ha percibido hace poco).
func _best_hiding_spot() -> HidingSpot:
	var best: HidingSpot = null
	var best_length := INF
	var threat_known := now - _threat_time < 6.0
	for node in character.get_tree().get_nodes_in_group("hiding_spots"):
		var spot := node as HidingSpot
		if not _is_spot_available(spot) or not ghost.can_hide():
			continue
		var length := path_length_to(spot.get_interaction_point())
		if threat_known and flat_distance(_threat_position, spot.global_position) < length * 0.8:
			continue
		if length < best_length:
			best = spot
			best_length = length
	return best


func _is_spot_available(spot: HidingSpot) -> bool:
	if spot.occupant != null and spot.occupant != ghost:
		return false
	if not spot.has_meta("reserved_by"):
		return true
	var reserved: Variant = spot.get_meta("reserved_by")
	return reserved == ghost or not is_instance_valid(reserved)


func _release_reservation() -> void:
	if _hide_target and is_instance_valid(_hide_target) and _hide_target.has_meta("reserved_by") \
			and _hide_target.get_meta("reserved_by") == ghost:
		_hide_target.remove_meta("reserved_by")
	_hide_target = null


## Huyendo: cierra la puerta que acaba de cruzar si el Hunter no está justo detrás.
func _close_doors_behind(intent: CharacterIntent) -> void:
	if intent.interact or flat_distance(_threat_position, character.global_position) < 3.0:
		return
	for node in character.get_tree().get_nodes_in_group("doors"):
		var door := node as Door
		if not door.is_open or (_closed_doors.has(door) and now - float(_closed_doors[door]) < 6.0):
			continue
		var to_door := door.global_position - character.global_position
		to_door.y = 0.0
		if to_door.length() > DOOR_CLOSE_DISTANCE or to_door.length() < 0.7:
			continue
		# La puerta queda detrás (entre él y el Hunter).
		var to_threat := (_threat_position - character.global_position).normalized()
		if to_door.normalized().dot(to_threat) > 0.3 and not door.is_doorway_occupied():
			intent.interact = true
			intent.interact_with = door
			_closed_doors[door] = now
			return


## A veces apaga la luz de la habitación por la que pasa (si no está ya a oscuras).
func _maybe_turn_off_light(intent: CharacterIntent) -> void:
	if intent.interact:
		return
	var room := Room.find_at(character.get_tree(), character.global_position)
	if room == null or not room.lit or room == _light_room:
		return
	for child in room.get_children():
		var light_switch := child as LightSwitch
		if light_switch and light_switch.is_in_range(character):
			_light_room = room
			if randf() < GameManager.config.ai_ghost_light_chance:
				intent.interact = true
				intent.interact_with = light_switch
			return
