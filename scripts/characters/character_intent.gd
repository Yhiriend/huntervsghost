class_name CharacterIntent
extends RefCounted
## Lo que un controlador (jugador, maniquí, IA o red) quiere que haga el personaje este frame.
## El personaje solo lee intenciones: nunca lee el teclado directamente.

## Dirección de movimiento en el plano XZ (longitud 0..1).
var move_dir: Vector3 = Vector3.ZERO
## Moverse despacio y sin hacer ruido.
var sneak: bool = false
## Punto del mundo hacia el que se apunta (Hunter).
var aim_point: Vector3 = Vector3.ZERO
var has_aim: bool = false
## Pulsado este frame.
var fire: bool = false
var interact: bool = false
## Mantenido (para capturar o registrar).
var interact_held: bool = false
## Señuelo (Presa): pulsado este frame / mantenido.
var decoy: bool = false
var decoy_held: bool = false
## Objeto concreto a usar (la IA lo indica; el jugador usa el más cercano).
var interact_with: Interactable = null


func reset() -> void:
	move_dir = Vector3.ZERO
	sneak = false
	aim_point = Vector3.ZERO
	has_aim = false
	fire = false
	interact = false
	interact_held = false
	decoy = false
	decoy_held = false
	interact_with = null
