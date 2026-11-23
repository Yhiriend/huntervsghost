class_name CharacterController
extends Node
## Base de todo lo que puede controlar un personaje: jugador, maniquí, IA o red.
## Cada frame de física rellena las intenciones del personaje.


func update_intent(_character: CharacterBase, _intent: CharacterIntent) -> void:
	pass
