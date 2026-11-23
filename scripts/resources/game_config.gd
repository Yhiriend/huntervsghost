class_name GameConfig
extends Resource
## Todos los valores de balance del juego.
## Se editan en resources/game_config.tres o en caliente con el panel de depuración (F1).
## En el panel aparecen las variables con @export_range y los @export bool.

@export_group("Hunter")
@export_range(1.0, 10.0, 0.1) var hunter_speed: float = 4.2
@export_range(1.0, 15.0, 0.5) var net_range: float = 6.0
@export_range(0.5, 10.0, 0.1) var net_cooldown: float = 3.0
@export_range(1.0, 10.0, 0.1) var net_immobilize_time: float = 5.0
@export_range(0.5, 4.0, 0.1) var capture_distance: float = 1.5
@export_range(0.5, 5.0, 0.1) var capture_time: float = 1.5
@export_range(4.0, 40.0, 0.5) var net_speed: float = 14.0
## Radio "de grosor" de la red: cuánto puede pasar de lado y aun así acertar.
@export_range(0.0, 1.0, 0.05) var net_hit_radius: float = 0.25
@export_range(30.0, 360.0, 5.0) var hunter_vision_fov: float = 100.0

@export_group("Ghost")
@export_range(1.0, 10.0, 0.1) var ghost_speed: float = 4.6
@export_range(30.0, 360.0, 5.0) var ghost_vision_fov: float = 140.0
@export_range(1.0, 20.0, 0.5) var ghost_vision_radius: float = 10.0

@export_group("Movimiento")
## Multiplicador de velocidad al moverse en sigilo (Shift).
@export_range(0.2, 1.0, 0.05) var sneak_speed_factor: float = 0.55
@export_range(5.0, 100.0, 1.0) var acceleration: float = 35.0
@export_range(5.0, 100.0, 1.0) var deceleration: float = 45.0
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 14.0

@export_group("Visión")
@export_range(1.0, 20.0, 0.5) var vision_radius_lit: float = 9.0
@export_range(1.0, 20.0, 0.5) var vision_radius_dark: float = 4.0
## A esta distancia se detecta a alguien aunque esté fuera del cono (lo "oyes" a tu espalda).
@export_range(0.0, 5.0, 0.1) var vision_proximity_radius: float = 1.5
## Si está activo, jugando como Hunter solo ves a los Ghosts que están en tu visión.
@export var hunter_vision_hides_ghosts: bool = true
## Número de rayos para dibujar el cono de depuración.
@export_range(8, 128, 1) var vision_debug_rays: int = 40

@export_group("Casa")
## Si está activo, un Ghost en una habitación a oscuras solo se ve a vision_radius_dark.
@export var lights_affect_vision: bool = true
## Segundos que el Hunter tarda en registrar un armario.
@export_range(0.2, 5.0, 0.1) var search_time: float = 1.0
## Segundos sin poder esconderse tras ser expulsado de un armario.
@export_range(0.0, 15.0, 0.5) var hide_cooldown: float = 5.0
## El armario ocupado tiembla si un Hunter se acerca.
@export var wardrobe_heartbeat: bool = true
@export_range(0.5, 6.0, 0.1) var heartbeat_distance: float = 2.5

@export_group("Ruido")
@export var noise_enabled: bool = true
## Distancia a la que se oyen los pasos al correr (no en sigilo).
@export_range(0.0, 20.0, 0.5) var run_noise_radius: float = 8.0
@export_range(0.1, 2.0, 0.05) var footstep_interval: float = 0.45
@export_range(0.0, 25.0, 0.5) var door_noise_radius: float = 12.0
@export_range(0.0, 15.0, 0.5) var switch_noise_radius: float = 4.0
@export_range(0.0, 15.0, 0.5) var wardrobe_noise_radius: float = 4.0
## Error máximo (m) de la posición que se muestra al Hunter: el ruido es información imperfecta.
@export_range(0.0, 6.0, 0.25) var noise_position_error: float = 2.0

@export_group("Maniquíes")
## Segundos que un maniquí Hunter "torreta" debe verte antes de disparar.
@export_range(0.0, 3.0, 0.05) var dummy_reaction_time: float = 0.4

@export_group("Partida")
@export_range(30.0, 600.0, 10.0) var match_duration: float = 180.0
@export_range(0.0, 20.0, 1.0) var prep_time: float = 8.0

@export_group("Cámara")
@export_range(30.0, 89.0, 1.0) var camera_pitch: float = 65.0
@export_range(5.0, 50.0, 1.0) var camera_distance: float = 20.0
@export_range(1.0, 20.0, 0.5) var camera_follow_speed: float = 6.0
@export_range(6.0, 30.0, 0.5) var camera_zoom: float = 16.0
@export_range(6.0, 30.0, 0.5) var camera_zoom_min: float = 8.0
@export_range(6.0, 40.0, 0.5) var camera_zoom_max: float = 26.0
@export_range(0.25, 5.0, 0.25) var camera_zoom_step: float = 1.0
