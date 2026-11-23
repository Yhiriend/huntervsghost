extends Control
## Resumen de playtests.csv con las señales de la sección 5 del plan de trabajo.
## Cada señal se marca: verde = sano, amarillo = revisar, gris = sin datos suficientes.
## Las partidas abandonadas solo se cuentan aparte.

const GOOD := "#7ee08a"
const WARN := "#f5c451"
const NONE := "#9a9aae"
## Con menos partidas que esto, los porcentajes no son fiables.
const MIN_GAMES := 5

var _text: RichTextLabel


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "RESULTADOS DE LAS PRUEBAS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	box.add_child(title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_font_size_override("bold_font_size", 17)
	box.add_child(_text)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var back := Button.new()
	back.text = "Volver al menú (Esc)"
	back.custom_minimum_size = Vector2(220, 44)
	back.pressed.connect(GameManager.go_to_menu)
	buttons.add_child(back)
	var folder := Button.new()
	folder.text = "Abrir carpeta (playtests.csv)"
	folder.custom_minimum_size = Vector2(260, 44)
	folder.pressed.connect(func() -> void: OS.shell_open(PlaytestLogger.get_folder()))
	buttons.add_child(folder)

	_text.text = build_report(PlaytestLogger.read_rows())


## Construye el informe (BBCode). Es estático para poder probarlo sin interfaz.
static func build_report(rows: Array[Dictionary]) -> String:
	var finished: Array[Dictionary] = []
	var abandoned := 0
	for row in rows:
		if row.get("ganador", "") == "abandonada":
			abandoned += 1
		else:
			finished.append(row)
	if finished.is_empty():
		return "Todavía no hay partidas terminadas.\n\nJuega desde el menú (Hunter y Ghost) y responde al cuestionario del final: aquí aparecerán las señales para saber si el juego es divertido."

	var out := PackedStringArray()
	out.append("Partidas terminadas: [b]%d[/b] · abandonadas: %d" % [finished.size(), abandoned])
	if finished.size() < MIN_GAMES:
		out.append("[color=%s]Con menos de %d partidas los porcentajes aún no son fiables.[/color]" % [WARN, MIN_GAMES])
	out.append("")

	# --- Diversión (lo más importante) ---
	out.append("[b]DIVERSIÓN[/b]")
	out.append(_line("Quiere jugar otra partida", _percent(finished, func(r): return r.get("jugar_otra") == "si"), 60.0, 101.0, "La métrica principal."))
	var ratings := _numbers(finished, "diversion_1a5")
	out.append(_line_value("Diversión media (1-5)", _avg_text(ratings, 1), ratings.size(), _avg(ratings) >= 3.5, "%d valoraciones" % ratings.size()))
	out.append(_line("Hubo un momento de tensión", _percent(_answered(finished, "tension"), func(r): return r.get("tension") == "si"), 50.0, 101.0, ""))
	var by := _answered(finished, "resultado_por")
	out.append(_line("Resultado por mis decisiones", _percent(by, func(r): return r.get("resultado_por") == "decisiones"), 50.0, 101.0,
		"suerte %s · injusto %s" % [_pct_text(_percent(by, func(r): return r.get("resultado_por") == "suerte")), _pct_text(_percent(by, func(r): return r.get("resultado_por") == "injusto"))]))
	out.append("")

	# --- Por bando ---
	for role in ["hunter", "ghost"]:
		var games := finished.filter(func(r): return r.get("rol_jugador") == role)
		out.append("[b]JUGANDO COMO %s[/b]  (%d partidas)" % [role.to_upper(), games.size()])
		if games.is_empty():
			out.append("  [color=%s]Sin partidas.[/color]" % NONE)
			out.append("")
			continue
		var won := func(r): return (r.get("ganador") == "hunter") == (role == "hunter")
		out.append(_line("Victorias del jugador", _percent(games, won), 40.0, 60.0, "Sano: 40-60 %. Si es muy alto o bajo, ajusta la dificultad o el balance."))
		var durations := _numbers(games, "duracion_s")
		out.append(_line_value("Duración media", "%.0f s" % _avg(durations), durations.size(), true, "Debe variar: ni siempre al límite de tiempo ni siempre en segundos."))
		var fired := _sum(games, "redes_disparadas")
		var hit := _sum(games, "redes_acertadas")
		var accuracy := -1.0 if fired == 0 else 100.0 * hit / fired
		var shooter := "tu precisión" if role == "hunter" else "precisión de la IA"
		out.append(_line("Precisión de red (%s)" % shooter, accuracy, 25.0, 50.0, "%d/%d. <15 %% frustra · >70 %% es trivial." % [int(hit), int(fired)]))
		out.append(_line_value("Escapes de la red por partida", "%.1f" % (_sum(games, "escapes_de_red") / games.size()), games.size(), _sum(games, "escapes_de_red") > 0, "Si nunca hay escapes, capturar es demasiado fácil."))
		out.append(_line("Partidas en que se usan armarios", _percent(games, func(r): return float(r.get("armarios_registrados", "0")) > 0 or float(r.get("tiempo_escondido_s", "0")) > 0), 50.0, 101.0, ""))
		out.append(_line("Partidas en que se usan puertas", _percent(games, func(r): return float(r.get("puertas_usadas", "0")) > 0), 50.0, 101.0, ""))
		out.append(_line("Partidas en que se usan luces", _percent(games, func(r): return float(r.get("luces_usadas", "0")) > 0), 50.0, 101.0, "Una mecánica que no se usa no aporta o no se entiende."))
		out.append("")

	# --- Notas ---
	var notes := finished.filter(func(r): return String(r.get("nota", "")) != "")
	if not notes.is_empty():
		out.append("[b]ÚLTIMAS NOTAS[/b]")
		for row in notes.slice(maxi(0, notes.size() - 8)):
			out.append("  • [%s, %s] %s" % [row.get("rol_jugador", ""), row.get("dificultad", ""), row.get("nota", "")])
	return "\n".join(out)


# --- Ayudas ----------------------------------------------------------------------

static func _line(label: String, value: float, good_min: float, good_max: float, hint: String) -> String:
	if value < 0.0:
		return "  [color=%s]%s: sin datos[/color]" % [NONE, label]
	var color := GOOD if value >= good_min and value <= good_max else WARN
	var line := "  [color=%s]●[/color] %s: [b]%.0f %%[/b]" % [color, label, value]
	return line + ("  [color=%s]%s[/color]" % [NONE, hint] if hint != "" else "")


static func _line_value(label: String, value_text: String, samples: int, healthy: bool, hint: String) -> String:
	if samples == 0:
		return "  [color=%s]%s: sin datos[/color]" % [NONE, label]
	var color := GOOD if healthy else WARN
	return "  [color=%s]●[/color] %s: [b]%s[/b]  [color=%s]%s[/color]" % [color, label, value_text, NONE, hint]


static func _percent(rows: Array, predicate: Callable) -> float:
	if rows.is_empty():
		return -1.0
	return 100.0 * rows.filter(predicate).size() / rows.size()


static func _pct_text(value: float) -> String:
	return "—" if value < 0.0 else "%.0f %%" % value


static func _answered(rows: Array, key: String) -> Array:
	return rows.filter(func(r): return String(r.get(key, "")) != "")


static func _numbers(rows: Array, key: String) -> Array[float]:
	var values: Array[float] = []
	for row in rows:
		var text := String(row.get(key, ""))
		if text.is_valid_float():
			values.append(float(text))
	return values


static func _sum(rows: Array, key: String) -> float:
	var total := 0.0
	for value in _numbers(rows, key):
		total += value
	return total


static func _avg(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()


static func _avg_text(values: Array[float], decimals: int) -> String:
	return ("%." + str(decimals) + "f") % _avg(values)
