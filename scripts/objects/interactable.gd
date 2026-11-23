class_name Interactable
extends Node3D
## Base de todo objeto que se usa con el botón contextual (E): puertas, interruptores, armarios.
## El personaje elige el más cercano cuyo get_prompt() no esté vacío.

## Distancia máxima (en el plano XZ) desde get_interaction_point().
@export var interact_range: float = 1.4


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("resettable")


## Punto desde el que se mide la distancia.
func get_interaction_point() -> Vector3:
	return global_position


## Texto del botón contextual ("ABRIR", "ESCONDERSE"...). Vacío = este actor no puede usarlo ahora.
func get_prompt(_actor: CharacterBase) -> String:
	return ""


## 0 = acción instantánea al pulsar. >0 = hay que mantener E ese tiempo.
func get_hold_time(_actor: CharacterBase) -> float:
	return 0.0


func interact(_actor: CharacterBase) -> void:
	pass


## Vuelve al estado inicial (al reiniciar el escenario).
func reset_state() -> void:
	pass


func is_in_range(actor: CharacterBase) -> bool:
	var offset := actor.global_position - get_interaction_point()
	offset.y = 0.0
	return offset.length() <= interact_range
