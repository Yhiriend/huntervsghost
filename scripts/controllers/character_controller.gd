class_name CharacterController
extends Node
## Base de todo lo que puede controlar un personaje: jugador, maniquí, IA o red.
## Cada frame de física rellena las intenciones del personaje.


func update_intent(_character: CharacterBase, _intent: CharacterIntent) -> void:
	pass


## Vuelve al estado inicial (al reiniciar el escenario).
func reset() -> void:
	pass


## Texto bajo el nombre del personaje ("DUMMY", "IA"...).
func get_tag() -> String:
	return ""
