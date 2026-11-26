class_name Door
extends Interactable
## Puerta corredera. El nodo se coloca en el centro del hueco; el eje X local va a lo largo de la pared.
## Abierta, la hoja se desliza dentro de la pared (slide_direction indica hacia qué lado).
## Cerrada bloquea el paso, la visión y las redes. Abrir y cerrar hace ruido.
## No se puede cerrar si hay alguien en el hueco.

signal open_changed(door: Door, is_open: bool)

const HEIGHT := 1.15  # Un poco menos que la pared (1,2 m) para que no parpadee la parte de arriba.
const THICKNESS := 0.12
const SLIDE_TIME := 0.25
const DOOR_COLOR := Color(0.78, 0.62, 0.42)

@export var width: float = 2.0
@export var start_open: bool = true
## 1 = se desliza hacia +X local; -1 = hacia -X.
@export var slide_direction: float = 1.0

var is_open: bool = true

var _panel: AnimatableBody3D
var _tween: Tween


func _ready() -> void:
	super()
	add_to_group("doors")
	interact_range = maxf(interact_range, width * 0.5 + 0.6)
	_build_panel()
	set_open(start_open, null, false)


func get_prompt(_actor: CharacterBase) -> String:
	if _tween and _tween.is_running():
		return ""
	return "CERRAR" if is_open else "ABRIR"


func interact(actor: CharacterBase) -> void:
	set_open(not is_open, actor)


## Devuelve false si no se pudo (alguien en el hueco al cerrar). force: sin comprobarlo (red).
func set_open(value: bool, actor: CharacterBase = null, animate: bool = true, force: bool = false) -> bool:
	if not value and not force and is_doorway_occupied():
		return false
	var changed := value != is_open
	is_open = value
	var target := _panel_position()
	if _tween:
		_tween.kill()
	if animate:
		_tween = create_tween()
		_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_tween.tween_property(_panel, "position", target, SLIDE_TIME)
	else:
		_panel.position = target
	if animate and changed:
		GameManager.make_noise(global_position, GameManager.config.door_noise_radius, actor)
		Audio.play_at("door_open" if is_open else "door_close", global_position, GameManager.config.door_noise_radius)
	if changed:
		open_changed.emit(self, is_open)
	return true


func is_doorway_occupied() -> bool:
	for group in ["hunters", "ghosts"]:
		for node in get_tree().get_nodes_in_group(group):
			var character := node as CharacterBase
			if character == null or not character.is_active():
				continue
			var local := to_local(character.global_position)
			if absf(local.x) < width * 0.5 + 0.1 and absf(local.z) < 0.55:
				return true
	return false


func reset_state() -> void:
	if _tween:
		_tween.kill()
	is_open = start_open
	_panel.position = _panel_position()


func _panel_position() -> Vector3:
	return Vector3(slide_direction * width if is_open else 0.0, HEIGHT * 0.5, 0.0)


func _build_panel() -> void:
	_panel = AnimatableBody3D.new()
	_panel.name = "Panel"
	_panel.collision_layer = 1
	_panel.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(width - 0.04, HEIGHT, THICKNESS)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_panel.add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = DOOR_COLOR
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	_panel.add_child(visual)

	# Tirador blanco para reconocerla como objeto interactivo.
	var handle_material := StandardMaterial3D.new()
	handle_material.albedo_color = Color.WHITE
	handle_material.emission_enabled = true
	handle_material.emission = Color.WHITE
	handle_material.emission_energy_multiplier = 0.6
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.12, 0.12, THICKNESS + 0.06)
	handle_mesh.material = handle_material
	var handle := MeshInstance3D.new()
	handle.mesh = handle_mesh
	handle.position = Vector3(-width * 0.5 + 0.25, HEIGHT * 0.5 - 0.15, 0.0)
	_panel.add_child(handle)
	add_child(_panel)
