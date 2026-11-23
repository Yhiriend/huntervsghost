class_name LightSwitch
extends Interactable
## Interruptor de la luz de su habitación (el nodo padre debe ser un Room).
## Blanco brillante = luz encendida, gris = apagada.

const ON_COLOR := Color(1.0, 0.9, 0.5)
const OFF_COLOR := Color(0.35, 0.35, 0.4)

var room: Room
var _material := StandardMaterial3D.new()


func _ready() -> void:
	super()
	room = get_parent() as Room
	if room == null:
		push_error("LightSwitch '%s' debe ser hijo de un Room." % name)
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.15)
	mesh.material = _material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)
	room.lit_changed.connect(func(_r: Room, _lit: bool) -> void: _update_visual())
	_update_visual()


func get_prompt(_actor: CharacterBase) -> String:
	if room == null:
		return ""
	return "APAGAR LUZ" if room.lit else "ENCENDER LUZ"


func interact(actor: CharacterBase) -> void:
	room.toggle()
	GameManager.make_noise(global_position, GameManager.config.switch_noise_radius, actor)


func _update_visual() -> void:
	var color := ON_COLOR if room.lit else OFF_COLOR
	_material.albedo_color = color
	_material.emission_enabled = room.lit
	_material.emission = color
	_material.emission_energy_multiplier = 1.5
