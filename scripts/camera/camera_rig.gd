class_name CameraRig
extends Node3D
## Cámara ortográfica cenital inclinada que sigue suavemente a un objetivo.
## Inclinación, distancia, seguimiento y zoom se leen de GameConfig cada frame
## para poder ajustarlos en caliente.

const ZOOM_SMOOTHING := 10.0

var target: Node3D

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = GameManager.config.camera_zoom
	_update_camera_offset()


func set_target(new_target: Node3D, snap_now: bool = false) -> void:
	target = new_target
	if snap_now:
		snap()


## Coloca la cámara en el objetivo sin transición.
func snap() -> void:
	if is_instance_valid(target):
		global_position = target.global_position
	camera.size = GameManager.config.camera_zoom


func _process(delta: float) -> void:
	var cfg := GameManager.config
	_update_camera_offset()
	if is_instance_valid(target):
		var weight := 1.0 - exp(-cfg.camera_follow_speed * delta)
		global_position = global_position.lerp(target.global_position, weight)
	camera.size = lerpf(camera.size, cfg.camera_zoom, 1.0 - exp(-ZOOM_SMOOTHING * delta))


func _unhandled_input(event: InputEvent) -> void:
	var cfg := GameManager.config
	if event.is_action_pressed("zoom_in"):
		cfg.camera_zoom = clampf(cfg.camera_zoom - cfg.camera_zoom_step, cfg.camera_zoom_min, cfg.camera_zoom_max)
	elif event.is_action_pressed("zoom_out"):
		cfg.camera_zoom = clampf(cfg.camera_zoom + cfg.camera_zoom_step, cfg.camera_zoom_min, cfg.camera_zoom_max)


func _update_camera_offset() -> void:
	var cfg := GameManager.config
	var pitch := deg_to_rad(cfg.camera_pitch)
	camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * cfg.camera_distance
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
