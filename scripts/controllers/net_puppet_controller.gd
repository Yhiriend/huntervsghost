class_name NetPuppetController
extends CharacterController
## En un cliente de red: el personaje no tiene cerebro aquí (lo mueve el anfitrión).
## Solo aporta la etiqueta bajo el nombre ("IA" o vacío para jugadores).

var tag: String = ""


func get_tag() -> String:
	return tag
