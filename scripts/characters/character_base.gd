class_name CharacterBase
extends CharacterBody3D
## Movimiento y propiedades comunes de Hunter y Ghost.
## Obedece al controlador asignado (PlayerInput, DummyController, futura IA...).

const PLAYER_LABEL_COLOR := Color(1.0, 0.95, 0.4)
const DUMMY_LABEL_COLOR := Color(0.75, 0.75, 0.8)

@export var display_name: String = "Personaje"

var controller: CharacterController
var intent := CharacterIntent.new()
var is_player_controlled: bool = false
## Congelado: ignora a su controlador (preparación de la partida, partida terminada).
var frozen: bool = false
var vision: VisionSensor
## Objeto que se está usando manteniendo E (p. ej. registrar un armario).
var interact_target: Interactable = null
var interact_progress: float = 0.0
## En red, en un cliente: el personaje no simula nada; su posición y estado llegan del anfitrión
## (net_target_*) y aquí solo se suavizan. El controlador sigue calculando intenciones (para
## enviar las del jugador local).
var net_puppet: bool = false
var net_target_position := Vector3.ZERO
var net_target_yaw: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _footstep_timer: float = 0.0

@onready var _label: Label3D = get_node_or_null("NameLabel")


func _ready() -> void:
	vision = VisionSensor.new()
	vision.name = "VisionSensor"
	add_child(vision)
	_update_label()


# --- Métodos que Hunter y Ghost sobrescriben ----------------------------------

## Velocidad máxima sin sigilo.
func get_base_speed() -> float:
	return 4.0


## Ángulo total del cono de visión, en grados.
func get_vision_fov() -> float:
	return 90.0


func get_vision_radius() -> float:
	return 8.0


## Radio con el que se ve a alguien situado en target_position (la oscuridad lo puede reducir).
func get_vision_radius_at(_target_position: Vector3) -> float:
	return get_vision_radius()


## Radio mínimo posible (se dibuja como zona interior del cono de depuración).
func get_min_vision_radius() -> float:
	return get_vision_radius()


## Personajes que este personaje intenta ver (el bando contrario).
func get_vision_targets() -> Array[Node]:
	return []


## Color del cono de visión de depuración.
func get_debug_color() -> Color:
	return Color(1, 1, 1, 0.15)


## ¿Puede ser visto por el bando contrario? (Un Ghost capturado o escondido, no.)
func is_detectable() -> bool:
	return true


## ¿Puede desplazarse ahora mismo? (Atrapado en una red, capturando o registrando, no.)
func can_move() -> bool:
	return interact_target == null


## Si es falso, el personaje no procesa física ni acciones (p. ej. un Ghost capturado).
func is_active() -> bool:
	return true


## Acciones propias del personaje (disparar, capturar...). Se llama antes de moverse.
func _process_actions(delta: float) -> void:
	_update_interaction(delta)


## Hacia dónde mirar. Por defecto, hacia donde se mueve.
func _get_facing_dir(move_dir: Vector3) -> Vector3:
	return move_dir


# --- Lógica común --------------------------------------------------------------

func set_controller(new_controller: CharacterController, player_controlled: bool) -> void:
	controller = new_controller
	is_player_controlled = player_controlled
	intent.reset()
	_update_label()


## Vuelve al estado inicial (se usa al reiniciar el escenario).
func reset_state() -> void:
	velocity = Vector3.ZERO
	intent.reset()
	cancel_interaction()
	_footstep_timer = 0.0


# --- Interacción contextual (E) -------------------------------------------------

## El objeto interactivo más cercano que este personaje puede usar ahora (o null).
func find_interactable() -> Interactable:
	var best: Interactable = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("interactables"):
		var item := node as Interactable
		if item == null or not item.is_in_range(self) or item.get_prompt(self) == "":
			continue
		var distance := global_position.distance_to(item.get_interaction_point())
		if distance < best_distance:
			best = item
			best_distance = distance
	return best


func cancel_interaction() -> void:
	interact_target = null
	interact_progress = 0.0


## Pulsar E usa el objeto; si requiere mantener, avanza mientras se mantenga y se esté cerca.
func _update_interaction(delta: float) -> void:
	if interact_target == null:
		if not intent.interact:
			return
		# Si se indica un objeto concreto (IA) y no se puede usar ahora, no se usa otro en su lugar.
		var item := intent.interact_with
		if item == null:
			item = find_interactable()
		elif not item.is_in_range(self) or item.get_prompt(self) == "":
			return
		if item == null:
			return
		if item.get_hold_time(self) <= 0.0:
			item.interact(self)
		else:
			interact_target = item
			interact_progress = 0.0
		return
	if not intent.interact_held or not is_instance_valid(interact_target) or not interact_target.is_in_range(self) or interact_target.get_prompt(self) == "":
		cancel_interaction()
		return
	interact_progress += delta
	if interact_progress >= interact_target.get_hold_time(self):
		var item := interact_target
		cancel_interaction()
		item.interact(self)


func _physics_process(delta: float) -> void:
	intent.reset()
	if controller:
		controller.update_intent(self, intent)
	if frozen:
		intent.reset()
	if net_puppet:
		_puppet_process(delta)
		return
	if not is_active():
		return
	_process_actions(delta)
	_apply_movement(delta)


func _apply_movement(delta: float) -> void:
	var cfg := GameManager.config
	var dir := Vector3(intent.move_dir.x, 0.0, intent.move_dir.z)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	if not can_move():
		dir = Vector3.ZERO

	var speed := get_base_speed()
	if intent.sneak:
		speed *= cfg.sneak_speed_factor

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := cfg.acceleration if dir != Vector3.ZERO else cfg.deceleration
	horizontal = horizontal.move_toward(dir * speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not is_on_floor():
		velocity.y -= _gravity * delta

	move_and_slide()
	_update_footsteps(delta, horizontal.length(), speed)

	if not can_move():
		return
	# El "frente" del personaje es -Z (donde está la nariz/lanzador).
	var facing := _get_facing_dir(dir)
	if facing.length_squared() > 0.01:
		var target_yaw := atan2(-facing.x, -facing.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-cfg.turn_speed * delta))


## Cliente de red: acercarse suavemente a la posición que manda el anfitrión.
const PUPPET_SMOOTHING := 18.0
## Más lejos que esto se salta directamente (p. ej. al salir de un armario).
const PUPPET_SNAP_DISTANCE := 2.5


func set_net_target(target_position: Vector3, yaw: float, snap: bool = false) -> void:
	net_target_position = target_position
	net_target_yaw = yaw
	if snap or global_position.distance_to(target_position) > PUPPET_SNAP_DISTANCE:
		global_position = target_position
		rotation.y = yaw


func _puppet_process(delta: float) -> void:
	var weight := 1.0 - exp(-PUPPET_SMOOTHING * delta)
	global_position = global_position.lerp(net_target_position, weight)
	rotation.y = lerp_angle(rotation.y, net_target_yaw, weight)


## Correr (no en sigilo) hace ruido de pasos cada footstep_interval segundos.
func _update_footsteps(delta: float, current_speed: float, max_speed: float) -> void:
	var cfg := GameManager.config
	if intent.sneak or current_speed < max_speed * 0.6:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = cfg.footstep_interval
		GameManager.make_noise(global_position, cfg.run_noise_radius, self)
		Audio.play_random_at("step", 4, global_position, cfg.run_noise_radius, -4.0)


func _update_label() -> void:
	if not _label:
		return
	var tag := "TÚ" if is_player_controlled else (controller.get_tag() if controller else "")
	_label.text = "%s\n%s" % [display_name, tag]
	_label.modulate = PLAYER_LABEL_COLOR if is_player_controlled else DUMMY_LABEL_COLOR
