class_name CharacterAnimator
extends Node
## Elige la animación del modelo del personaje (hijo del CharacterBase).
## La velocidad se mide con el desplazamiento real, no con `velocity`, para que también funcione
## en las marionetas de red, que solo reciben posiciones del anfitrión.
## Animaciones esperadas (tools/rig_characters.py): Idle, Walk, Run; Netted (Presa); Shoot (Cazador).

const BLEND_TIME := 0.15
const LOOPED: Array[StringName] = [&"Idle", &"Walk", &"Run", &"Netted"]
## Por debajo de esto se considera quieto (m/s).
const IDLE_SPEED := 0.3
## A partir de esta fracción de la velocidad máxima se corre; por debajo (sigilo) se camina.
const RUN_FRACTION := 0.75
## Más rápido que esto es un salto de posición (salir de un armario, reinicio): se ignora.
const TELEPORT_SPEED := 15.0

## Velocidad (m/s) a la que cada animación avanza sin resbalar los pies.
@export var walk_reference_speed: float = 1.2
@export var run_reference_speed: float = 2.6
## Brillo propio del modelo (su textura emite luz teñida de este color) para que destaque en
## las habitaciones oscuras, como pide el GDD. Energía 0 = sin brillo.
@export var glow_color := Color(1, 1, 1)
@export_range(0.0, 2.0, 0.05) var glow_energy: float = 0.6

var _character: CharacterBase
var _player: AnimationPlayer
var _last_position := Vector3.ZERO
var _speed: float = 0.0
var _oneshot_left: float = 0.0


func _ready() -> void:
	_character = get_parent() as CharacterBase
	if _character and glow_energy > 0.0:
		_apply_glow()
	var found :=_character.find_children("*", "AnimationPlayer", true, false) if _character else []
	if found.is_empty():
		set_physics_process(false)
		return
	_player = found[0]
	for anim_name in LOOPED:
		if _player.has_animation(anim_name):
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	if _character.has_signal("net_fired"):
		_character.connect("net_fired", _on_net_fired)
	_last_position = _character.global_position
	_player.play(&"Idle")


func _physics_process(delta: float) -> void:
	var pos := _character.global_position
	var step := pos - _last_position
	step.y = 0.0
	_last_position = pos
	var instant := step.length() / maxf(delta, 0.0001)
	if instant > TELEPORT_SPEED:
		instant = 0.0
	_speed = lerpf(_speed, instant, 1.0 - exp(-12.0 * delta))

	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		return

	var anim := &"Idle"
	var speed_scale := 1.0
	if _character is Ghost and (_character as Ghost).state == Ghost.State.NETTED:
		anim = &"Netted"
	elif _speed > IDLE_SPEED:
		if _speed >= _character.get_base_speed() * RUN_FRACTION:
			anim = &"Run"
			speed_scale = _speed / run_reference_speed
		else:
			anim = &"Walk"
			speed_scale = _speed / walk_reference_speed
	_play(anim, clampf(speed_scale, 0.5, 2.2))


func _play(anim: StringName, speed_scale: float) -> void:
	if not _player.has_animation(anim):
		anim = &"Idle"
	if _player.current_animation != anim:
		_player.play(anim, BLEND_TIME)
	_player.speed_scale = speed_scale


func _apply_glow() -> void:
	for node in _character.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.mesh is PrimitiveMesh:
			continue  # Solo el modelo importado (no la red ni el lanzador).
		for i in mesh_instance.mesh.get_surface_count():
			var base := mesh_instance.get_active_material(i) as StandardMaterial3D
			if base == null:
				continue
			var material := base.duplicate() as StandardMaterial3D
			material.emission_enabled = true
			material.emission = glow_color
			material.emission_texture = base.albedo_texture
			material.emission_energy_multiplier = glow_energy
			mesh_instance.set_surface_override_material(i, material)


func _on_net_fired(_hunter: Node) -> void:
	if not _player.has_animation(&"Shoot"):
		return
	_player.speed_scale = 1.0
	_player.play(&"Shoot", 0.05)
	_oneshot_left = _player.get_animation(&"Shoot").length
