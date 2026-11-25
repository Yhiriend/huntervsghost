class_name TestScenario
extends Node3D
## Escenario de prueba con maniquíes.
## Crea un personaje por cada DummySpawn hijo de "Spawns".
##   Tab -> pasar el control al siguiente personaje.
##   R   -> reiniciar el escenario (personajes, puertas, luces y armarios).
##   P   -> modo espectador: soltar el personaje (vuelve a su IA/maniquí); Tab cambia de cámara.
## Jugando como Hunter, solo se ven los Ghosts que están dentro de su visión
## y los ruidos de los Ghosts aparecen como anillos en una posición aproximada.

const HUNTER_SCENE := preload("res://scenes/characters/Hunter.tscn")
const GHOST_SCENE := preload("res://scenes/characters/Ghost.tscn")
const NOISE_COLOR := Color(1, 1, 1, 0.8)
const OWN_NOISE_COLOR := Color(1, 1, 1, 0.25)

## Texto que se muestra al empezar y al reiniciar.
@export_multiline var description: String = ""
## Habitaciones (nombre del nodo Room) que empiezan con la luz apagada.
@export var rooms_dark: PackedStringArray = []
## Puertas (nombre del nodo Door) que empiezan cerradas.
@export var doors_closed: PackedStringArray = []
## Permite cambiar de personaje con Tab y el modo espectador (P).
@export var allow_switch: bool = true
## Empieza en modo espectador (sin controlar a nadie).
@export var start_spectating: bool = false


class Entry:
	var spawn: DummySpawn
	var character: CharacterBase
	## Quien lo controla cuando no lo controla el jugador (maniquí o IA).
	var fallback: CharacterController


var _entries: Array[Entry] = []
var _controlled: int = -1
## Personaje al que sigue la cámara en modo espectador.
var _watched: int = -1
var _player_input := PlayerInput.new()
var _hud := HUD.new()

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _spawns: Node3D = $Spawns
@onready var _characters_root: Node3D = $Characters


func _ready() -> void:
	_player_input.name = "PlayerInput"
	add_child(_player_input)
	_hud.name = "HUD"
	_hud.scenario_buttons = allow_switch
	add_child(_hud)

	var start_index := 0
	for node in _spawns.get_children():
		var spawn := node as DummySpawn
		if spawn == null:
			continue
		if spawn.player_start:
			start_index = _entries.size()
		_entries.append(_spawn_character(spawn))

	for node in get_tree().get_nodes_in_group("hiding_spots"):
		(node as HidingSpot).searched.connect(_on_hiding_spot_searched)
	GameManager.noise_made.connect(_on_noise_made)

	if _entries.is_empty():
		push_warning("El escenario no tiene ningún DummySpawn en 'Spawns'.")
		return
	_apply_initial_state()
	if start_spectating:
		_spectate(start_index, true)
	else:
		_take_control(start_index, true)
	if description != "":
		_hud.show_message(description, 6.0)


func _physics_process(_delta: float) -> void:
	_update_player_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if _entries.is_empty():
		return
	if event.is_action_pressed("reset_scenario"):
		reset_scenario()
		get_viewport().set_input_as_handled()
	elif allow_switch and event.is_action_pressed("switch_character"):
		if _controlled < 0:
			_spectate((_watched + 1) % _entries.size())
		else:
			_take_control((_controlled + 1) % _entries.size())
		get_viewport().set_input_as_handled()
	elif allow_switch and event.is_action_pressed("spectate"):
		if _controlled < 0:
			_take_control(maxi(_watched, 0))
		else:
			_spectate(_controlled)
		get_viewport().set_input_as_handled()


func reset_scenario() -> void:
	for node in get_tree().get_nodes_in_group("resettable"):
		node.reset_state()
	for entry in _entries:
		entry.character.global_transform = entry.spawn.global_transform
		entry.character.reset_state()
		entry.fallback.reset()
	_apply_initial_state()
	_camera_rig.snap()
	_hud.show_message(description if description != "" else "Escenario reiniciado", 3.0)


func get_controlled_character() -> CharacterBase:
	return _entries[_controlled].character if _controlled >= 0 else null


## Aplica lo que el escenario define: luces apagadas, puertas cerradas, Ghosts escondidos.
func _apply_initial_state() -> void:
	for node in get_tree().get_nodes_in_group("rooms"):
		var room := node as Room
		if room.name in rooms_dark:
			room.set_lit(false, false)
	for node in get_tree().get_nodes_in_group("doors"):
		var door := node as Door
		if door.name in doors_closed:
			door.set_open(false, null, false)
	for entry in _entries:
		if entry.spawn.start_hidden_in == "" or not entry.character is Ghost:
			continue
		var spot := _find_hiding_spot(entry.spawn.start_hidden_in)
		if spot:
			(entry.character as Ghost).enter_hiding(spot, false)
		else:
			push_warning("No existe el armario '%s'." % entry.spawn.start_hidden_in)


func _find_hiding_spot(spot_name: String) -> HidingSpot:
	for node in get_tree().get_nodes_in_group("hiding_spots"):
		if node.name == spot_name:
			return node as HidingSpot
	return null


func _spawn_character(spawn: DummySpawn) -> Entry:
	var scene := HUNTER_SCENE if spawn.role == DummySpawn.Role.HUNTER else GHOST_SCENE
	var character := scene.instantiate() as CharacterBase
	character.name = spawn.name
	_characters_root.add_child(character)
	character.global_transform = spawn.global_transform

	var fallback: CharacterController
	if spawn.behavior == DummySpawn.Behavior.AI:
		fallback = HunterAI.new() if character is Hunter else GhostAI.new()
		fallback.name = "AI"
		character.add_child(fallback)
	else:
		var dummy := DummyController.new()
		dummy.name = "DummyController"
		character.add_child(dummy)
		dummy.setup(spawn)
		fallback = dummy
	character.set_controller(fallback, false)

	if character is Ghost:
		(character as Ghost).state_changed.connect(_on_ghost_state_changed)

	var entry := Entry.new()
	entry.spawn = spawn
	entry.character = character
	entry.fallback = fallback
	return entry


func _release_control() -> void:
	if _controlled >= 0:
		var previous := _entries[_controlled]
		previous.character.set_controller(previous.fallback, false)
	_controlled = -1


func _take_control(index: int, snap_camera: bool = false) -> void:
	_release_control()
	_watched = -1
	_controlled = index
	var current := _entries[_controlled]
	current.character.set_controller(_player_input, true)
	_camera_rig.set_target(current.character, snap_camera)
	_hud.set_controlled(current.character)
	_update_player_visibility()


## Modo espectador: nadie es el jugador; la cámara sigue a un personaje y se ve todo.
func _spectate(index: int, snap_camera: bool = false) -> void:
	_release_control()
	_watched = index
	_camera_rig.set_target(_entries[index].character, snap_camera)
	_hud.set_controlled(null)
	_hud.show_message("Espectador: %s  (Tab cambia de cámara, P para controlarlo)" % _entries[index].character.name, 3.0)
	_update_player_visibility()


## Jugando como Hunter, cada Ghost solo se dibuja si el Hunter lo ve.
## Jugando como Ghost se ve todo (ventaja de información del Ghost).
func _update_player_visibility() -> void:
	var player := get_controlled_character()
	var hunter := player as Hunter
	var hide_unseen := hunter != null and GameManager.config.hunter_vision_hides_ghosts
	for node in get_tree().get_nodes_in_group("ghosts"):
		var ghost := node as Ghost
		ghost.set_revealed(not hide_unseen or hunter.vision.can_see(ghost))

	var ghost_player := player as Ghost
	var room_only := ghost_player != null and GameManager.config.ghost_sees_hunter_same_room_only
	for node in get_tree().get_nodes_in_group("hunters"):
		var other := node as Hunter
		other.set_revealed(not room_only or ghost_can_see_hunter(ghost_player, other))


## Jugando como Ghost: ves al Hunter solo si estáis en la misma habitación y no estás en un armario.
## Un Ghost capturado ya no juega: lo ve todo.
func ghost_can_see_hunter(ghost: Ghost, hunter: Hunter) -> bool:
	if ghost.state == Ghost.State.CAPTURED:
		return true
	if ghost.state == Ghost.State.HIDDEN:
		return false
	var room := _area_of(ghost)
	return room != null and room == _area_of(hunter)


## Habitación en la que está un personaje. En un umbral de puerta (fuera de toda habitación)
## cuenta la última en la que estuvo, para que no parpadee al cruzar.
func _area_of(character: CharacterBase) -> Room:
	var room := Room.find_at(get_tree(), character.global_position)
	if room:
		character.set_meta("last_room", room)
		return room
	if character.has_meta("last_room"):
		var last: Variant = character.get_meta("last_room")
		if is_instance_valid(last):
			return last
	return null


# --- Ruido -----------------------------------------------------------------------

## Los ruidos del bando contrario que alcanzan al jugador se muestran en una posición
## aproximada. Los ruidos propios se muestran tenues, para saber cuándo estás haciendo ruido.
func _on_noise_made(noise_position: Vector3, radius: float, source: Node) -> void:
	var player := get_controlled_character()
	if player == null:
		# Espectador: todos los ruidos en su posición real, con el color de quien lo hace.
		if source is CharacterBase:
			var color := Color(1.0, 0.55, 0.2, 0.7) if source is Hunter else Color(0.45, 0.85, 1.0, 0.7)
			_spawn_noise_ring(noise_position, color, 0.8)
		return
	if source == player:
		_spawn_noise_ring(noise_position, OWN_NOISE_COLOR, 0.6)
		return
	# Cada bando oye los ruidos del otro (pasos, puertas, armarios...) en una posición aproximada.
	if not ((player is Hunter and source is Ghost) or (player is Ghost and source is Hunter)):
		return
	var offset := noise_position - player.global_position
	offset.y = 0.0
	if offset.length() > radius:
		return
	var error := GameManager.config.noise_position_error
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0) * error
	_spawn_noise_ring(noise_position + Vector3(jitter.x, 0.0, jitter.y), NOISE_COLOR, 1.0)


func _spawn_noise_ring(at: Vector3, color: Color, size: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Vector3(at.x, 0.1, at.z)
	ring.scale = Vector3.ONE * 0.3 * size
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 1.6 * size, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.8)
	tween.chain().tween_callback(ring.queue_free)


# --- Mensajes --------------------------------------------------------------------

func _on_ghost_state_changed(ghost: Ghost, old_state: Ghost.State, new_state: Ghost.State) -> void:
	_vibrate_for(ghost, new_state)
	match new_state:
		Ghost.State.NETTED:
			_hud.show_message("¡Red! Ghost inmovilizado")
		Ghost.State.CAPTURED:
			if _count_free_ghosts() == 0:
				_hud.show_message("¡Todos capturados!  (R para reiniciar)", 4.0)
			else:
				_hud.show_message("¡Ghost capturado!")
		Ghost.State.FREE:
			if old_state == Ghost.State.NETTED:
				_hud.show_message("El Ghost se ha liberado")


## Vibración en el móvil: fuerte si te atrapan, corta si aciertas o capturas.
func _vibrate_for(ghost: Ghost, new_state: Ghost.State) -> void:
	if not GameManager.is_mobile():
		return
	var controlled := get_controlled_character()
	if controlled == null:
		return
	if controlled == ghost and (new_state == Ghost.State.NETTED or new_state == Ghost.State.CAPTURED):
		Input.vibrate_handheld(350)
	elif controlled is Hunter and (new_state == Ghost.State.NETTED or new_state == Ghost.State.CAPTURED):
		Input.vibrate_handheld(80)


func _on_hiding_spot_searched(_spot: HidingSpot, found: Ghost) -> void:
	_hud.show_message("¡Ghost encontrado en el armario!" if found else "Armario vacío")


func _count_free_ghosts() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("ghosts"):
		if (node as Ghost).state != Ghost.State.CAPTURED:
			count += 1
	return count
