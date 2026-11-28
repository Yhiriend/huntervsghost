extends Node
## Iconos: todos los que se usan existen, los botones del menú los llevan y cada acción tiene el suyo.

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _ready() -> void:
	var missing := []
	for entry in Icons.BY_TEXT:
		if Icons.get_icon(entry[1]) == null:
			missing.append(entry[1])
	for action in Icons.BY_ACTION:
		if Icons.for_action(action) == null:
			missing.append(Icons.BY_ACTION[action])
	for icon_name in ["red", "caminar", "senuelo", "toque", "unirse"]:
		if Icons.get_icon(icon_name) == null:
			missing.append(icon_name)
	check(missing.is_empty(), "Existen todos los iconos usados %s" % [missing])

	for prompt in ["ABRIR", "CERRAR", "ESCONDERSE", "SALIR", "REGISTRAR", "APAGAR LUZ", "ENCENDER LUZ"]:
		check(Icons.for_action(prompt) != Icons.for_action(""), "La acción %s tiene icono propio" % prompt)

	var menu: Node = load("res://scenes/main/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var without := []
	var total := 0
	for node in menu.find_children("*", "Button", true, false):
		var button := node as Button
		if button.toggle_mode:
			continue  # Fácil / Normal / Difícil: solo texto.
		total += 1
		if button.icon == null:
			without.append(button.text)
	check(total >= 8 and without.is_empty(), "Los %d botones del menú llevan icono %s" % [total, without])
	print("RESULT failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
