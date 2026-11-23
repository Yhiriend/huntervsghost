class_name PlaytestLogger
extends RefCounted
## Guarda una fila por partida en user://playtests.csv para analizar el balance y la diversión.
## Ábrelo con cualquier hoja de cálculo. Ruta real: menú principal -> "Abrir carpeta de datos".

const PATH := "user://playtests.csv"
const COLUMNS: PackedStringArray = [
	"fecha",
	"rol_jugador",
	"ganador",
	"duracion_s",
	"ghosts_total",
	"ghosts_capturados",
	"redes_disparadas",
	"redes_acertadas",
	"escapes_de_red",
	"armarios_registrados",
	"ghosts_encontrados_en_armario",
	"tiempo_escondido_s",
	"puertas_usadas",
	"luces_usadas",
	"diversion_1a5",
	"jugar_otra",
]


static func append(row: Dictionary) -> Error:
	var exists := FileAccess.file_exists(PATH)
	var file := FileAccess.open(PATH, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if exists:
		file.seek_end()
	else:
		file.store_line(",".join(COLUMNS))
	var values := PackedStringArray()
	for column in COLUMNS:
		values.append(str(row.get(column, "")).replace(",", " "))
	file.store_line(",".join(values))
	return OK


static func get_folder() -> String:
	return ProjectSettings.globalize_path("user://")
