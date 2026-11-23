class_name HidingSpot
extends Interactable
## Armario. La parte delantera es +Z local (ahí está el tirador y desde ahí se interactúa).
##   Ghost:  ESCONDERSE (si está vacío y no tiene penalización) / SALIR.
##   Hunter: REGISTRAR manteniendo E search_time segundos. Si hay un Ghost, lo expulsa
##           (no lo captura: el Hunter aún tiene que atraparlo con la red).
## Si un Hunter se acerca a un armario ocupado, el armario tiembla ("latido").

signal searched(spot: HidingSpot, found: Ghost)

const SIZE := Vector3(1.4, 1.6, 0.9)
const COLOR := Color(0.45, 0.25, 0.65)

var occupant: Ghost = null

var _visual: Node3D
var _time: float = 0.0


func _ready() -> void:
	super()
	add_to_group("hiding_spots")
	_build()


func get_interaction_point() -> Vector3:
	return to_global(Vector3(0.0, 0.0, SIZE.z * 0.5 + 0.5))


## Donde aparece el Ghost al salir o ser expulsado.
func get_exit_position() -> Vector3:
	return to_global(Vector3(0.0, 0.0, SIZE.z * 0.5 + 0.6))


func get_prompt(actor: CharacterBase) -> String:
	if actor is Ghost:
		var ghost := actor as Ghost
		if occupant == ghost:
			return "SALIR"
		if occupant == null and ghost.state == Ghost.State.FREE and ghost.can_hide():
			return "ESCONDERSE"
		return ""
	if actor is Hunter:
		return "REGISTRAR"
	return ""


func get_hold_time(actor: CharacterBase) -> float:
	return GameManager.config.search_time if actor is Hunter else 0.0


func interact(actor: CharacterBase) -> void:
	if actor is Ghost:
		var ghost := actor as Ghost
		if occupant == ghost:
			ghost.exit_hiding()
		elif occupant == null:
			ghost.enter_hiding(self)
	elif actor is Hunter:
		var found := occupant
		if found:
			found.expel_from_hiding()
		searched.emit(self, found)


func reset_state() -> void:
	occupant = null
	_visual.position = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_time += delta
	var shaking := occupant != null and GameManager.config.wardrobe_heartbeat and _hunter_nearby()
	if shaking:
		# Dos golpes cortos cada segundo, como un latido.
		var beat := fmod(_time, 1.0)
		var strength := 0.04 if beat < 0.1 or (beat > 0.2 and beat < 0.3) else 0.0
		_visual.position = Vector3(randf_range(-strength, strength), 0.0, randf_range(-strength, strength))
	else:
		_visual.position = Vector3.ZERO


func _hunter_nearby() -> bool:
	var max_distance := GameManager.config.heartbeat_distance
	for node in get_tree().get_nodes_in_group("hunters"):
		var hunter := node as Node3D
		if hunter.global_position.distance_to(global_position) <= max_distance + SIZE.z * 0.5:
			return true
	return false


func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, SIZE.y * 0.5, 0.0)
	body.add_child(collision)
	add_child(body)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	mesh.material = material
	var cabinet := MeshInstance3D.new()
	cabinet.mesh = mesh
	cabinet.position = Vector3(0.0, SIZE.y * 0.5, 0.0)
	_visual.add_child(cabinet)

	# Tiradores blancos en el frente.
	var handle_material := StandardMaterial3D.new()
	handle_material.albedo_color = Color.WHITE
	handle_material.emission_enabled = true
	handle_material.emission = Color.WHITE
	handle_material.emission_energy_multiplier = 0.6
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.08, 0.35, 0.08)
	handle_mesh.material = handle_material
	for x in [-0.12, 0.12]:
		var handle := MeshInstance3D.new()
		handle.mesh = handle_mesh
		handle.position = Vector3(x, SIZE.y * 0.6, SIZE.z * 0.5 + 0.03)
		_visual.add_child(handle)
