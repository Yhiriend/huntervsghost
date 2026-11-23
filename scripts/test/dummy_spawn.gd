class_name DummySpawn
extends Marker3D
## Punto de aparición de un personaje en un escenario de prueba.
## Colócalo en el editor y elige rol, comportamiento y si lo controla el jugador al empezar.
## El personaje mira hacia -Z del marcador.

enum Role { HUNTER, GHOST }
## STATIC: quieto. ROUTE: recorre en bucle los puntos de un Path3D (abre las puertas que encuentre).
enum Behavior { STATIC, ROUTE }

@export var role: Role = Role.GHOST
@export var behavior: Behavior = Behavior.STATIC
## Path3D a recorrer si behavior = ROUTE (se usan sus puntos, en bucle).
@export_node_path("Path3D") var route: NodePath
## Recorrer la ruta en sigilo (sin ruido de pasos).
@export var route_sneak: bool = false
## Solo Hunter: dispara la red a cualquier Ghost que vea a tiro (tras dummy_reaction_time).
@export var shoots_on_sight: bool = false
## Solo Ghost: nombre del armario (HidingSpot) en el que empieza escondido.
@export var start_hidden_in: String = ""
## El jugador empieza controlando este personaje.
@export var player_start: bool = false
