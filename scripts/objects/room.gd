class_name Room
extends Node3D
## Habitación: zona rectangular con una luz (hijo "Light") que se enciende y apaga.
## Si está a oscuras, el Hunter solo ve a los Ghosts que hay dentro a vision_radius_dark.
## El rectángulo (size) está centrado en el nodo.

signal lit_changed(room: Room, lit: bool)

@export var size: Vector3 = Vector3(10, 3, 8)
@export var start_lit: bool = true

var lit: bool = true

var _light: OmniLight3D
var _light_energy: float = 1.0
var _tween: Tween


func _ready() -> void:
	add_to_group("rooms")
	add_to_group("resettable")
	_light = get_node_or_null("Light") as OmniLight3D
	if _light:
		_light_energy = _light.light_energy
	set_lit(start_lit, false)


## Habitación que contiene el punto, o null.
static func find_at(tree: SceneTree, point: Vector3) -> Room:
	for node in tree.get_nodes_in_group("rooms"):
		var room := node as Room
		if room.contains_point(point):
			return room
	return null


## ¿Este punto está a oscuras? (Fuera de cualquier habitación cuenta como iluminado.)
static func is_dark_at(tree: SceneTree, point: Vector3) -> bool:
	var room := find_at(tree, point)
	return room != null and not room.lit


func contains_point(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5


func toggle() -> void:
	set_lit(not lit)


func set_lit(value: bool, animate: bool = true) -> void:
	var changed := value != lit
	lit = value
	if _light:
		var target := _light_energy if lit else 0.0
		if _tween:
			_tween.kill()
		if animate:
			_tween = create_tween()
			_tween.tween_property(_light, "light_energy", target, 0.15)
		else:
			_light.light_energy = target
	if changed:
		lit_changed.emit(self, lit)


func reset_state() -> void:
	set_lit(start_lit, false)
