class_name Icons
## Iconos de los botones (assets/icons/*.svg). Son blancos: se tiñen con el color del botón.
##   Icons.get_icon("red")            -> textura
##   Icons.for_action("ABRIR")        -> icono del botón de acción táctil
##   Icons.apply(button, color)       -> pone el icono que corresponde al texto del botón

const DIR := "res://assets/icons/"

## Texto del botón (en minúsculas) -> icono. Gana la primera entrada que aparezca en el texto.
const BY_TEXT := [
	["contra la ia", "ia"],
	["multijugador", "multijugador"],
	["compartir", "compartir"],
	["whatsapp", "mensaje"],
	["más opciones", "opciones"],
	["ajustes", "opciones"],
	["cazador", "cazador"],
	["presa", "presa"],
	["resultados", "resultados"],
	["escenarios", "pruebas"],
	["prototype", "pruebas"],
	["test", "pruebas"],
	["internet", "internet"],
	["wifi", "wifi"],
	["crear sala", "crear"],
	["unirse", "unirse"],
	["empezar partida", "jugar"],
	["siguiente", "jugar"],
	["nueva partida", "jugar"],
	["desempatar", "cambiar"],
	["volver a la sala", "multijugador"],
	["volver", "volver"],
	["salir", "salir"],
	["abandonar", "salir"],
	["menú", "inicio"],
	["conos", "ojo"],
	["espectador", "ojo"],
	["cambiar", "cambiar"],
	["reiniciar", "reiniciar"],
	["restaurar", "reiniciar"],
]

## Botón de acción táctil: texto de la acción -> icono.
const BY_ACTION := {
	"ABRIR": "abrir",
	"CERRAR": "cerrar",
	"ESCONDERSE": "esconderse",
	"SALIR": "salir",
	"REGISTRAR": "registrar",
	"APAGAR LUZ": "luz_off",
	"ENCENDER LUZ": "luz_on",
}

static var _cache: Dictionary = {}


static func get_icon(icon_name: String) -> Texture2D:
	if not _cache.has(icon_name):
		var path := DIR + icon_name + ".svg"
		_cache[icon_name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[icon_name]


static func for_action(action: String) -> Texture2D:
	return get_icon(BY_ACTION.get(action, "toque"))


static func for_text(text: String) -> Texture2D:
	var lower := text.to_lower()
	for entry in BY_TEXT:
		if lower.contains(entry[0]):
			return get_icon(entry[1])
	return null


## Pone al botón el icono de su texto (si hay uno), del tamaño de la letra y del color dado.
static func apply(button: Button, color: Color = Color.WHITE, icon: Texture2D = null) -> void:
	if icon == null:
		icon = for_text(button.text)
	if icon == null:
		return
	button.icon = icon
	var font_size := button.get_theme_font_size("font_size") if button.has_theme_font_size_override("font_size") else 16
	button.add_theme_constant_override("icon_max_width", int(font_size * 1.5))
	button.add_theme_constant_override("h_separation", 10)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		button.add_theme_color_override(state, color)
	button.add_theme_color_override("icon_disabled_color", Color(color, 0.4))
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
