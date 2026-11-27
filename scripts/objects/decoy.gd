class_name Decoy
extends Node3D
## Señuelo de la Presa: una pelotita pulsante en el suelo, sin colisión. Solo la ven su dueño
## y los espectadores: si el Cazador la viera, sabría que los pasos son falsos.
## Los pasos los genera la Presa (Ghost.trigger_decoy); aquí solo se dibuja y se marca cada paso.

const RADIUS := 0.13
const COLOR := Color(0.45, 0.85, 1.0)
const PULSE_SPEED := 3.0
## Duración del destello de cada paso falso.
const STEP_FLASH := 0.25

var owner_ghost: Ghost
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _time := 0.0
var _flash := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = 1.2
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.position.y = RADIUS
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func step_flash() -> void:
	_flash = STEP_FLASH


func _process(delta: float) -> void:
	visible = _visible_to_local_player()
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED * TAU / 2.0)
	var flash := _flash / STEP_FLASH
	_mesh.scale = Vector3.ONE * (0.85 + 0.3 * pulse + 0.6 * flash)
	_material.emission_energy_multiplier = 0.8 + 1.2 * pulse + 2.0 * flash


## Lo ve quien controla a su Presa, o un espectador (sin personaje).
func _visible_to_local_player() -> bool:
	# El escenario (partida o prueba) es un antecesor con get_controlled_character().
	var scene := get_parent()
	while scene and not scene.has_method("get_controlled_character"):
		scene = scene.get_parent()
	if scene == null:
		return true
	var viewer: Node = scene.get_controlled_character()
	return viewer == null or viewer == owner_ghost
