class_name PlaytestLogger
extends RefCounted
## Guarda una fila por partida en user://playtests.csv para analizar el balance y la diversión.
## Ábrelo con cualquier hoja de cálculo. Ruta real: menú principal -> "Abrir carpeta de datos".

const DEFAULT_PATH := "user://playtests.csv"
## Se puede cambiar (las pruebas automáticas usan otro archivo para no tocar tus datos).
static var path: String = DEFAULT_PATH
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
	"dificultad",
	"tension",
	"resultado_por",
	"nota",
]


static func append(row: Dictionary) -> Error:
	_migrate_if_outdated()
	var exists := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if exists:
		file.seek_end()
	else:
		file.store_line(",".join(COLUMNS))
	var values := PackedStringArray()
	for column in COLUMNS:
		values.append(str(row.get(column, "")).replace(",", " ").replace("\n", " "))
	file.store_line(",".join(values))
	return OK


## Todas las filas como diccionarios (columna -> texto). Vacío si no hay archivo.
static func read_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return rows
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return rows
	var header := file.get_csv_line()
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.size() < 2:
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = values[i] if i < values.size() else ""
		rows.append(row)
	return rows


## Si el CSV es de una versión anterior (otras columnas), se convierte al formato actual
## conservando todas las filas (las columnas nuevas quedan vacías). El original se guarda
## como copia de seguridad (playtests_anterior_<fecha>.csv).
static func _migrate_if_outdated() -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var header := file.get_line()
	file = null
	if header == ",".join(COLUMNS):
		return
	var rows := read_rows()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup := path.get_basename() + "_anterior_%s.csv" % stamp
	if DirAccess.copy_absolute(path, backup) != OK:
		push_warning("No se pudo hacer copia de %s; no se migra." % path)
		return
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_line(",".join(COLUMNS))
	for row in rows:
		var values := PackedStringArray()
		for column in COLUMNS:
			values.append(String(row.get(column, "")))
		out.store_line(",".join(values))


static func get_folder() -> String:
	return ProjectSettings.globalize_path("user://")
