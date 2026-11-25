class_name MatchSeries
extends RefCounted
## Serie de rondas entre el equipo del jugador ("Tú") y el de la IA.
##
##   - Rondas 1-2: el jugador juega con el bando elegido en el menú; rondas 3-4: bandos cambiados.
##   - Gana la serie el primer equipo con 3 victorias (puede acabar en la ronda 3).
##   - 2-2 tras la ronda 4: desempate de 2 rondas (una con cada bando). Se juegan las dos y se
##     compara al final de la pareja.
##   - Si tras el desempate siguen empatados: votación -> otro desempate o terminar en empate.
## Es lógica pura (sin nodos) para poder probarla sola; vive en GameManager.series entre rondas.

enum Status { PLAYING, PLAYER_WINS, AI_WINS, TIE_VOTE, DRAW }

const REGULAR_ROUNDS := 4
const WINS_NEEDED := 3

## Bando del jugador en la ronda 1 (DummySpawn.Role).
var starting_role: int
## Resultado de cada ronda jugada: true = ganó el jugador.
var results: Array[bool] = []
var status: Status = Status.PLAYING
## Identificador para agrupar las filas del CSV.
var id: String


func _init(first_role: int) -> void:
	starting_role = first_role
	id = Time.get_datetime_string_from_system()


## Número de la ronda que se va a jugar (o la última jugada si la serie terminó). Empieza en 1.
func current_round() -> int:
	return results.size() + (1 if status == Status.PLAYING else 0)


## Bando del jugador en una ronda: 1-2 el inicial, 3-4 el otro; en los desempates,
## la primera ronda de cada pareja con el inicial y la segunda con el otro.
func role_for_round(round_number: int) -> int:
	var swapped: bool
	if round_number <= REGULAR_ROUNDS:
		swapped = round_number > REGULAR_ROUNDS / 2
	else:
		swapped = (round_number - REGULAR_ROUNDS) % 2 == 0
	return other_role(starting_role) if swapped else starting_role


func current_role() -> int:
	return role_for_round(current_round())


static func other_role(role: int) -> int:
	return DummySpawn.Role.GHOST if role == DummySpawn.Role.HUNTER else DummySpawn.Role.HUNTER


func player_wins() -> int:
	return results.count(true)


func ai_wins() -> int:
	return results.count(false)


func is_tiebreak_round(round_number: int) -> bool:
	return round_number > REGULAR_ROUNDS


func is_over() -> bool:
	return status in [Status.PLAYER_WINS, Status.AI_WINS, Status.DRAW]


## La ronda siguiente cambia de bando respecto a la anterior.
func next_round_swaps() -> bool:
	var n := current_round()
	return n > 1 and role_for_round(n) != role_for_round(n - 1)


## Apunta el resultado de la ronda actual y recalcula el estado de la serie.
func record(player_won: bool) -> Status:
	if status != Status.PLAYING:
		return status
	results.append(player_won)
	var played := results.size()
	var p := player_wins()
	var a := ai_wins()
	if played <= REGULAR_ROUNDS:
		if p >= WINS_NEEDED:
			status = Status.PLAYER_WINS
		elif a >= WINS_NEEDED:
			status = Status.AI_WINS
	elif (played - REGULAR_ROUNDS) % 2 == 0:
		# Fin de una pareja de desempate.
		if p > a:
			status = Status.PLAYER_WINS
		elif a > p:
			status = Status.AI_WINS
		else:
			status = Status.TIE_VOTE
	return status


## Votación tras un empate: jugar otra pareja de desempate.
func continue_tiebreak() -> void:
	if status == Status.TIE_VOTE:
		status = Status.PLAYING


## Votación tras un empate: terminar la serie en empate.
func declare_draw() -> void:
	if status == Status.TIE_VOTE:
		status = Status.DRAW


## "Ronda 2 de 4" o "Desempate 1 (ronda 5)".
func round_label(round_number: int = -1) -> String:
	var n := current_round() if round_number < 0 else round_number
	if is_tiebreak_round(n):
		return "Desempate %d · ronda %d" % [n - REGULAR_ROUNDS, n]
	return "Ronda %d de %d" % [n, REGULAR_ROUNDS]


func score_text() -> String:
	return "Tú %d – %d IA" % [player_wins(), ai_wins()]


## Texto del resultado de la serie para el CSV.
func result_code() -> String:
	match status:
		Status.PLAYER_WINS:
			return "gana_jugador"
		Status.AI_WINS:
			return "gana_ia"
		Status.DRAW:
			return "empate"
	return ""
