class_name HunterAI
extends AIController
## IA del Hunter. Prioridades (de mayor a menor):
##   CAPTURE     Hay un Ghost atrapado a la vista: ir y capturarlo.
##   CHASE       Ve a un Ghost libre: perseguirlo y disparar (tiempo de reacción + error de puntería).
##   SEARCH      Registrar armarios: el que "late", o los cercanos a donde perdió/oyó a un Ghost.
##   INVESTIGATE Ir a donde oyó un ruido o vio al Ghost por última vez y mirar alrededor
##               (y a veces asomarse por un extremo de un muro suelto cercano).
##   PATROL      Recorrer habitaciones al azar; a veces registra armarios y enciende luces.
## No conoce la posición de los Ghosts: solo usa su visión y su oído.
## Señuelos: si oye pasos "parados" en el mismo sitio en varias ocasiones distintas, sospecha que
## es un señuelo y casi nunca deja lo que hace por ellos (ni registra armarios por esos pasos).

enum State { PATROL, INVESTIGATE, CHASE, CAPTURE, SEARCH }

const STATE_NAMES := ["PATROL", "INVESTIGATE", "CHASE", "CAPTURE", "SEARCH"]
const LOOK_AROUND_TIME := 1.6
const SEARCH_RADIUS := 5.0
const SPOT_RESEARCH_COOLDOWN := 20.0
const PASSING_SPOT_DISTANCE := 2.2
## Pasos a menos de esta distancia cuentan como el mismo sitio (los pasos de alguien que corre
## están más separados).
const DECOY_SPOT_RADIUS := 1.2
## Silencio mínimo entre dos ocasiones distintas en el mismo sitio.
const DECOY_OCCASION_GAP := 1.5
## Cuánto recuerda un sitio con pasos.
const DECOY_MEMORY := 90.0
const PEEK_TIME := 1.0
const PEEK_COOLDOWN := 20.0
## Distancia, desde el extremo del muro, a la que se asoma.
const PEEK_OFFSET := 0.9

var state: State = State.PATROL
var hunter: Hunter

var _last_seen_position := Vector3.ZERO
var _seen_time: float = 0.0
var _aim_offset := Vector3.ZERO
var _investigate_position := Vector3.ZERO
var _look_timer: float = 0.0
var _search_after_investigate: bool = false
var _search_queue: Array[HidingSpot] = []
var _search_hold: float = 0.0
## HidingSpot -> momento en que se registró o se decidió no registrar.
var _spot_memory: Dictionary = {}
var _last_room: Room = null
## Sitios donde oyó pasos: [{pos, last, occasions, decided, follow}].
var _noise_spots: Array[Dictionary] = []
## La investigación actual es de un sitio que cree que es un señuelo (no registrará armarios).
var _investigating_decoy := false
var _peeking := false
var _peek_look := Vector3.ZERO
var _peek_timer := 0.0
## Muro -> momento en que se asomó.
var _peeked_walls: Dictionary = {}


func _ready() -> void:
	super()
	hunter = character as Hunter
	state_name = STATE_NAMES[state]


func reset() -> void:
	super()
	state = State.PATROL
	_seen_time = 0.0
	_search_queue.clear()
	_spot_memory.clear()
	_last_room = null
	_noise_spots.clear()
	_peeked_walls.clear()
	_peeking = false


func think(delta: float, intent: CharacterIntent) -> void:
	# 1. Capturar a un Ghost atrapado (prioridad máxima).
	var netted := _visible_netted_ghost()
	if netted:
		_set_state(State.CAPTURE)
		_do_capture(netted, intent, delta)
		return

	# 2. Perseguir y disparar a un Ghost libre que ve.
	var seen := _closest_visible_ghost()
	if seen:
		if _seen_time == 0.0:
			_roll_aim_error()
		_last_seen_position = seen.global_position
		_seen_time += delta
		_set_state(State.CHASE)
		_do_chase(seen, intent, delta)
		return
	_seen_time = 0.0
	if state == State.CHASE or state == State.CAPTURE:
		# Lo ha perdido de vista: ir a la última posición conocida y registrar armarios cercanos.
		_start_investigate(_last_seen_position, true)

	# 3. Un armario que tiembla cerca (información visible para cualquier jugador).
	var shaking := _nearby_shaking_spot()
	if shaking and state != State.SEARCH:
		_start_search([shaking])

	# 4. Ruidos.
	var noise := recent_noise()
	if not noise.is_empty() and state != State.SEARCH:
		var noise_position: Vector3 = noise["position"]
		var spot: Dictionary = noise.get("spot", {})
		var decoy := is_decoy_spot(spot)
		if decoy:
			# Probablemente un señuelo: solo a veces, y solo si no estaba haciendo otra cosa.
			if _follow_decoy(spot):
				_start_investigate(noise_position, false)
				_investigating_decoy = true
		elif state != State.INVESTIGATE or flat_distance(noise_position, _investigate_position) > 3.0:
			_start_investigate(noise_position, false)
		forget_noise()

	match state:
		State.PATROL:
			_do_patrol(intent, delta)
		State.INVESTIGATE:
			_do_investigate(intent, delta)
		State.SEARCH:
			_do_search(intent, delta)
	_maybe_turn_on_light(intent)


func on_stuck() -> void:
	if state == State.SEARCH and not _search_queue.is_empty():
		_spot_memory[_search_queue.pop_front()] = now
	elif state == State.INVESTIGATE:
		_set_state(State.PATROL)


func _set_state(new_state: State) -> void:
	if new_state != state:
		if state == State.INVESTIGATE:
			_peeking = false
		state = new_state
		if new_state != State.SEARCH:
			_search_hold = 0.0
	state_name = STATE_NAMES[state]


# --- Estados --------------------------------------------------------------------

func _do_capture(ghost: Ghost, intent: CharacterIntent, delta: float) -> void:
	intent.aim_point = ghost.global_position
	intent.has_aim = true
	if flat_distance(ghost.global_position, character.global_position) > GameManager.config.capture_distance * 0.8:
		set_destination(ghost.global_position)
		navigate(intent, delta)
	else:
		clear_destination()
		intent.interact = true
		intent.interact_held = true


func _do_chase(ghost: Ghost, intent: CharacterIntent, delta: float) -> void:
	var cfg := GameManager.config
	var distance := flat_distance(ghost.global_position, character.global_position)
	# Predicción del movimiento: dónde estará cuando llegue la red.
	var flight_time := distance / maxf(cfg.net_speed, 0.1)
	var lead := Vector3(ghost.velocity.x, 0.0, ghost.velocity.z) * flight_time * cfg.ai_lead_factor
	intent.aim_point = ghost.global_position + lead + _aim_offset
	intent.has_aim = true

	# Acercarse hasta una distancia cómoda de disparo (o hasta él si la red no está lista).
	var desired := cfg.net_range * 0.6 if hunter.is_net_ready() else 1.0
	if distance > desired:
		set_destination(ghost.global_position)
		navigate(intent, delta)
	else:
		clear_destination()

	if hunter.is_net_ready() and distance <= cfg.net_range * 0.95 and _seen_time >= cfg.ai_reaction_time:
		intent.fire = true
		_roll_aim_error()


## Error de puntería aleatorio (dentro de un círculo de radio ai_aim_error), nuevo en cada disparo.
func _roll_aim_error() -> void:
	var error := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * GameManager.config.ai_aim_error
	_aim_offset = Vector3(error.x, 0.0, error.y)


func _start_investigate(point: Vector3, search_after: bool) -> void:
	_investigate_position = point
	_search_after_investigate = search_after
	_investigating_decoy = false
	_peeking = false
	_look_timer = 0.0
	set_destination(point)
	_set_state(State.INVESTIGATE)


func _do_investigate(intent: CharacterIntent, delta: float) -> void:
	if _peeking:
		_do_peek(intent, delta)
		return
	if not navigate(intent, delta):
		return
	# Al llegar: mirar alrededor.
	_look_timer += delta
	var angle := _look_timer / LOOK_AROUND_TIME * TAU
	intent.aim_point = character.global_position + Vector3(sin(angle), 0.0, cos(angle)) * 3.0
	intent.has_aim = true
	if _look_timer < LOOK_AROUND_TIME:
		return
	# Alguien podría estar detrás de un muro cercano: a veces se asoma por un extremo.
	if not _investigating_decoy and randf() < GameManager.config.ai_hunter_peek_chance and _start_peek(_investigate_position):
		return
	_finish_investigate()


func _finish_investigate() -> void:
	var spots := _spots_near(_investigate_position, SEARCH_RADIUS)
	if not _investigating_decoy and not spots.is_empty() and (_search_after_investigate or randf() < 0.5):
		_start_search(spots)
	else:
		_set_state(State.PATROL)
	_investigating_decoy = false


# --- Muros sueltos: asomarse por un extremo --------------------------------------

## Va al extremo (el más cercano) de un muro suelto próximo a `near` para mirar detrás.
func _start_peek(near: Vector3) -> bool:
	var house := House.find(character.get_tree())
	if house == null:
		return false
	var best: Dictionary = {}
	var best_distance := SEARCH_RADIUS + 2.0
	for wall in house.cover_walls():
		var distance := flat_distance(wall["center"], near)
		if distance > best_distance:
			continue
		if _peeked_walls.has(wall["node"]) and now - float(_peeked_walls[wall["node"]]) < PEEK_COOLDOWN:
			continue
		best = wall
		best_distance = distance
	if best.is_empty():
		return false
	_peeked_walls[best["node"]] = now
	var center: Vector3 = best["center"]
	var axis: Vector3 = best["axis"]
	var half: float = best["half"]
	var me := character.global_position
	var end := 1.0 if flat_distance(center + axis * half, me) < flat_distance(center - axis * half, me) else -1.0
	set_destination(center + axis * end * (half + PEEK_OFFSET))
	_peek_look = center
	_peek_timer = 0.0
	_peeking = true
	return true


func _do_peek(intent: CharacterIntent, delta: float) -> void:
	if not navigate(intent, delta):
		return
	# Mira a lo largo del muro: ve los dos lados de este extremo.
	intent.aim_point = _peek_look
	intent.has_aim = true
	_peek_timer += delta
	if _peek_timer >= PEEK_TIME:
		_peeking = false
		_finish_investigate()


# --- Señuelos ---------------------------------------------------------------------

## Recuerda dónde oye pasos. Los de un señuelo suenan "parados" en el mismo sitio; si eso pasa
## en varias ocasiones distintas, ese sitio es sospechoso.
func _on_heard(noise_position: Vector3, radius: float) -> void:
	if absf(radius - GameManager.config.run_noise_radius) > 0.01:
		return  # Solo pasos (las puertas, los armarios... tienen otro alcance).
	_noise_spots = _noise_spots.filter(func(s: Dictionary) -> bool: return now - float(s["last"]) < DECOY_MEMORY)
	var spot: Dictionary = {}
	for candidate in _noise_spots:
		if flat_distance(candidate["pos"], noise_position) < DECOY_SPOT_RADIUS:
			spot = candidate
			break
	if spot.is_empty():
		spot = {"pos": noise_position, "last": -100.0, "occasions": 0, "decided": -1, "follow": false}
		_noise_spots.append(spot)
	if now - float(spot["last"]) > DECOY_OCCASION_GAP:
		spot["occasions"] = int(spot["occasions"]) + 1
	spot["last"] = now
	_last_noise["spot"] = spot


func is_decoy_spot(spot: Dictionary) -> bool:
	return not spot.is_empty() and int(spot["occasions"]) >= GameManager.config.ai_hunter_decoy_occasions


## ¿Cree que en este punto hay un señuelo?
func suspects_decoy_at(point: Vector3) -> bool:
	for spot in _noise_spots:
		if flat_distance(spot["pos"], point) < DECOY_SPOT_RADIUS and is_decoy_spot(spot):
			return true
	return false


## Se decide una vez por ocasión (no por cada paso de la ráfaga).
func _follow_decoy(spot: Dictionary) -> bool:
	if int(spot["decided"]) != int(spot["occasions"]):
		spot["decided"] = int(spot["occasions"])
		spot["follow"] = state == State.PATROL and randf() < GameManager.config.ai_hunter_decoy_follow_chance
	return bool(spot["follow"]) and state == State.PATROL


func _start_search(spots: Array[HidingSpot]) -> void:
	_search_queue = spots
	_search_hold = 0.0
	_set_state(State.SEARCH)


func _do_search(intent: CharacterIntent, delta: float) -> void:
	while not _search_queue.is_empty() and not is_instance_valid(_search_queue[0]):
		_search_queue.pop_front()
	if _search_queue.is_empty():
		_set_state(State.PATROL)
		return
	var spot := _search_queue[0]
	var point := spot.get_interaction_point()
	if flat_distance(point, character.global_position) > spot.interact_range * 0.7:
		set_destination(point)
		navigate(intent, delta)
		return
	clear_destination()
	intent.interact = _search_hold == 0.0
	intent.interact_held = true
	intent.interact_with = spot
	_search_hold += delta
	if _search_hold >= GameManager.config.search_time + 0.15:
		_spot_memory[spot] = now
		_search_queue.pop_front()
		_search_hold = 0.0


func _do_patrol(intent: CharacterIntent, delta: float) -> void:
	if not has_destination():
		set_destination(_pick_patrol_point())
	navigate(intent, delta)
	intent.sneak = GameManager.config.ai_hunter_patrol_sneak
	# Al pasar junto a un armario, a veces lo registra.
	for node in character.get_tree().get_nodes_in_group("hiding_spots"):
		var spot := node as HidingSpot
		if _recently_considered(spot):
			continue
		if flat_distance(spot.get_interaction_point(), character.global_position) < PASSING_SPOT_DISTANCE:
			_spot_memory[spot] = now
			if randf() < GameManager.config.ai_hunter_search_chance:
				_start_search([spot])
				return


## Una habitación distinta de la actual, en un punto del suelo al azar.
func _pick_patrol_point() -> Vector3:
	var current := Room.find_at(character.get_tree(), character.global_position)
	for attempt in 10:
		var point := random_floor_point()
		var room := Room.find_at(character.get_tree(), point)
		if room != current and room != _last_room:
			_last_room = current
			return point
	return random_floor_point()


## Si su habitación está a oscuras y tiene el interruptor a mano, enciende la luz.
func _maybe_turn_on_light(intent: CharacterIntent) -> void:
	if intent.interact or intent.interact_held:
		return
	var room := Room.find_at(character.get_tree(), character.global_position)
	if room == null or room.lit:
		return
	for child in room.get_children():
		var light_switch := child as LightSwitch
		if light_switch and light_switch.is_in_range(character):
			intent.interact = true
			intent.interact_with = light_switch
			return


# --- Percepción -------------------------------------------------------------------

func _closest_visible_ghost() -> Ghost:
	var best: Ghost = null
	var best_distance := INF
	for node in character.get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if ghost.state != Ghost.State.FREE or not hunter.vision.can_see(ghost):
			continue
		var distance := flat_distance(ghost.global_position, character.global_position)
		if distance < best_distance:
			best = ghost
			best_distance = distance
	return best


func _visible_netted_ghost() -> Ghost:
	if hunter.capture_target and hunter.capture_target.state == Ghost.State.NETTED:
		return hunter.capture_target
	for node in character.get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		if ghost.state == Ghost.State.NETTED and hunter.vision.can_see(ghost):
			return ghost
	return null


## El armario tiembla si está ocupado y el Hunter está cerca: es una pista visible.
func _nearby_shaking_spot() -> HidingSpot:
	var cfg := GameManager.config
	if not cfg.wardrobe_heartbeat:
		return null
	for node in character.get_tree().get_nodes_in_group("hiding_spots"):
		var spot := node as HidingSpot
		if spot.occupant and spot.global_position.distance_to(character.global_position) <= cfg.heartbeat_distance + HidingSpot.SIZE.z * 0.5:
			return spot
	return null


func _spots_near(point: Vector3, radius: float) -> Array[HidingSpot]:
	var result: Array[HidingSpot] = []
	for node in character.get_tree().get_nodes_in_group("hiding_spots"):
		var spot := node as HidingSpot
		if flat_distance(spot.global_position, point) <= radius and not _recently_searched(spot):
			result.append(spot)
	result.sort_custom(func(a: HidingSpot, b: HidingSpot) -> bool:
		return flat_distance(a.global_position, character.global_position) < flat_distance(b.global_position, character.global_position))
	return result


func _recently_searched(spot: HidingSpot) -> bool:
	return _spot_memory.has(spot) and now - float(_spot_memory[spot]) < SPOT_RESEARCH_COOLDOWN


func _recently_considered(spot: HidingSpot) -> bool:
	return _spot_memory.has(spot) and now - float(_spot_memory[spot]) < SPOT_RESEARCH_COOLDOWN * 1.5
