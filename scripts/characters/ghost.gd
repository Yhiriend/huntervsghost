class_name Ghost
extends CharacterBase
## Fantasma: huye, se esconde en armarios y manipula la casa (puertas, luces).
## Si le alcanza una red queda inmovilizado; si el Hunter no completa la captura a tiempo, se libera.

signal state_changed(ghost: Ghost, old_state: State, new_state: State)

enum State { FREE, NETTED, HIDDEN, CAPTURED }

const DEBUG_COLOR := Color(0.4, 0.8, 1.0, 0.1)
## Últimos segundos de red en los que la red parpadea (aviso de que se va a liberar).
const BLINK_WARNING_TIME := 1.5

var state: State = State.FREE
## Segundos que le quedan atrapado en la red.
var net_time_left: float = 0.0
## Armario en el que está escondido (o null).
var hiding_spot: HidingSpot = null
## Segundos que faltan para poder volver a esconderse tras ser expulsado.
var hide_cooldown_left: float = 0.0

var _revealed: bool = true
var _net_visual: MeshInstance3D

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	super()
	add_to_group("ghosts")
	_build_net_visual()


func get_base_speed() -> float:
	return GameManager.config.ghost_speed


func get_vision_fov() -> float:
	return GameManager.config.ghost_vision_fov


func get_vision_radius() -> float:
	return GameManager.config.ghost_vision_radius


func get_vision_targets() -> Array[Node]:
	return get_tree().get_nodes_in_group("hunters")


func get_debug_color() -> Color:
	return DEBUG_COLOR


func is_detectable() -> bool:
	return state == State.FREE or state == State.NETTED


func can_move() -> bool:
	return state == State.FREE and super()


func is_active() -> bool:
	return state != State.CAPTURED


func can_hide() -> bool:
	return hide_cooldown_left <= 0.0


## Lo llama la red al impactar.
func apply_net() -> void:
	if state != State.FREE:
		return
	cancel_interaction()
	net_time_left = GameManager.config.net_immobilize_time
	velocity = Vector3(0.0, velocity.y, 0.0)
	_set_state(State.NETTED)


## Lo llama el Hunter al completar la captura.
func capture() -> void:
	if state != State.NETTED:
		return
	velocity = Vector3.ZERO
	_set_state(State.CAPTURED)


func enter_hiding(spot: HidingSpot, make_sound: bool = true) -> void:
	if spot.occupant != null:
		return
	cancel_interaction()
	hiding_spot = spot
	spot.occupant = self
	global_position = spot.global_position
	velocity = Vector3.ZERO
	_set_state(State.HIDDEN)
	if make_sound:
		GameManager.make_noise(spot.global_position, GameManager.config.wardrobe_noise_radius, self)


func exit_hiding() -> void:
	if _leave_spot():
		GameManager.make_noise(global_position, GameManager.config.wardrobe_noise_radius, self)


## Un Hunter ha registrado el armario: sale y no puede volver a esconderse durante un rato.
func expel_from_hiding() -> void:
	if _leave_spot():
		hide_cooldown_left = GameManager.config.hide_cooldown


func reset_state() -> void:
	super()
	if hiding_spot and hiding_spot.occupant == self:
		hiding_spot.occupant = null
	hiding_spot = null
	net_time_left = 0.0
	hide_cooldown_left = 0.0
	_set_state(State.FREE)


## Controla si el jugador ve a este Ghost (lo decide el sistema de visión).
func set_revealed(revealed: bool) -> void:
	if _revealed == revealed:
		return
	_revealed = revealed
	_update_visibility()


func _process_actions(delta: float) -> void:
	hide_cooldown_left = maxf(0.0, hide_cooldown_left - delta)
	match state:
		State.FREE, State.HIDDEN:
			_update_interaction(delta)
		State.NETTED:
			net_time_left -= delta
			if net_time_left <= 0.0:
				_set_state(State.FREE)
				return
			# Parpadeo de aviso en los últimos segundos.
			_net_visual.visible = net_time_left > BLINK_WARNING_TIME or fmod(net_time_left, 0.3) > 0.12


func _apply_movement(delta: float) -> void:
	if state == State.HIDDEN:
		return  # Dentro del armario: sin física (la colisión está desactivada).
	super(delta)


func _leave_spot() -> bool:
	if hiding_spot == null:
		return false
	var spot := hiding_spot
	spot.occupant = null
	hiding_spot = null
	global_position = spot.get_exit_position()
	var out := spot.global_basis.z
	rotation.y = atan2(-out.x, -out.z)
	velocity = Vector3.ZERO
	_set_state(State.FREE)
	return true


func _set_state(new_state: State) -> void:
	var old_state := state
	state = new_state
	_net_visual.visible = state == State.NETTED
	_collision.set_deferred("disabled", state == State.CAPTURED or state == State.HIDDEN)
	_update_visibility()
	if old_state != new_state:
		state_changed.emit(self, old_state, new_state)


func _update_visibility() -> void:
	visible = _revealed and (state == State.FREE or state == State.NETTED)


func _build_net_visual() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.35)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.9
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh.material = material
	_net_visual = MeshInstance3D.new()
	_net_visual.name = "NetVisual"
	_net_visual.mesh = mesh
	_net_visual.position = Vector3(0.0, 0.85, 0.0)
	_net_visual.visible = false
	add_child(_net_visual)
