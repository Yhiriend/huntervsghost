class_name MatchSeries
extends RefCounted
## Partida de 4 participantes con puntos individuales (humanos o IA, en solitario o en red).
##
## Fase normal: tantas rondas como participantes; cada uno es Cazador una vez y el resto son
## Presas (siempre 1 Cazador y 3 Presas).
##   - Cazador: 1 punto por cada Presa atrapada.
##   - Presa: 1 punto si sobrevive hasta el final de la ronda.
##   - Tiempo (primer desempate): segundos sobrevividos como Presa + segundos que le sobraban al
##     Cazador en cada captura.
## Al terminar una fase se ordena por puntos y luego por tiempo. Si varios siguen empatados:
##   - Tras la fase normal: minidesempate solo entre ellos (cada uno es Cazador una vez; los huecos
##     de Presa los rellena la IA, cuyas capturas no puntúan). El resto mira como espectador.
##   - Tras un minidesempate: votación -> otro minidesempate o terminar en empate.
## Es lógica pura (sin nodos) para poder probarla sola; vive en GameManager.series entre rondas y
## se envía a los clientes con to_dict()/from_dict().

enum Status { PLAYING, TIE_VOTE, FINISHED }

## Cazador + Presas de cada ronda.
const SLOTS := 4
## Los tiempos se comparan redondeados a décimas.
const TIME_PRECISION := 10.0

## Participantes: {"name": String, "peer": int}. peer 0 = IA; otro valor = jugador humano.
var participants: Array = []
## Fase actual: 0 = normal, 1.. = minidesempates.
var stage: int = 0
## Índices de los participantes que compiten en esta fase (en orden de turno de Cazador).
var contenders: Array = []
## Ronda dentro de la fase (0..contenders.size()-1).
var stage_round: int = 0
## Ronda global (1..), para mostrar y registrar.
var round_number: int = 1
## Puntos y tiempo de la fase normal (lo que se muestra como clasificación).
var points: Array = []
var times: Array = []
## Puntos y tiempo de la fase actual (en la normal coinciden con points/times).
var stage_points: Array = []
var stage_times: Array = []
var status: Status = Status.PLAYING
## Ganador(es) al terminar: uno, o varios si se declaró empate.
var winners: Array = []
## Última ronda registrada: {"hunter": i, "captured": [i...], "survived": [i...], "gained": {i: pts}}.
var last_round: Dictionary = {}
## Identificador para agrupar las filas del CSV.
var id: String = ""


## names_and_peers: [{"name": "Ana", "peer": 1}, ...] (SLOTS elementos). El orden es el turno
## de Cazador de la fase normal.
func _init(entries: Array = []) -> void:
	id = Time.get_datetime_string_from_system()
	for entry in entries:
		participants.append({"name": String(entry.get("name", "?")), "peer": int(entry.get("peer", 0))})
	for i in participants.size():
		contenders.append(i)
		points.append(0)
		times.append(0.0)
		stage_points.append(0)
		stage_times.append(0.0)


## Partida en solitario: el jugador (peer 1) + IA hasta completar los puestos.
## Empezando como Cazador el jugador es Cazador en la ronda 1; como Presa, en la última.
static func solo(player_name: String, player_hunts_first: bool) -> MatchSeries:
	var entries := [{"name": player_name, "peer": 1}]
	for i in range(1, SLOTS):
		entries.append({"name": "IA %d" % i, "peer": 0})
	if not player_hunts_first:
		entries.append(entries.pop_front())
	return MatchSeries.new(entries)


func participant_name(index: int) -> String:
	return participants[index]["name"] if index >= 0 and index < participants.size() else "?"


func peer_of(index: int) -> int:
	return participants[index]["peer"]


func is_human(index: int) -> bool:
	return peer_of(index) != 0


## Índice del participante de un jugador (-1 si no está).
func index_of_peer(peer: int) -> int:
	for i in participants.size():
		if participants[i]["peer"] == peer:
			return i
	return -1


## Un jugador se ha ido: su puesto pasa a la IA (conserva nombre y puntos).
func replace_with_ai(index: int) -> void:
	participants[index]["peer"] = 0
	participants[index]["name"] = "%s (IA)" % participants[index]["name"]


func is_over() -> bool:
	return status == Status.FINISHED


func is_tiebreak() -> bool:
	return stage > 0


func rounds_in_stage() -> int:
	return contenders.size()


## Participante que es Cazador en la ronda actual.
func current_hunter() -> int:
	return contenders[stage_round]


## Participantes que son Presa en la ronda actual (los demás competidores de la fase).
func current_prey() -> Array:
	var prey := []
	for i in contenders:
		if i != current_hunter():
			prey.append(i)
	return prey


## Presas de relleno (IA sin puntos) para completar 1 Cazador + 3 Presas.
func filler_count() -> int:
	return SLOTS - 1 - current_prey().size()


## Participantes que no juegan esta ronda (miran).
func spectators() -> Array:
	var out := []
	for i in participants.size():
		if not i in contenders:
			out.append(i)
	return out


func is_playing(index: int) -> bool:
	return index in contenders


## Apunta la ronda actual.
## prey_outcome: {índice de Presa: tiempo de captura en segundos desde el inicio de la caza,
##                o -1 si sobrevivió}. duration: segundos que duraba la ronda.
func record_round(prey_outcome: Dictionary, duration: float) -> Status:
	if status != Status.PLAYING:
		return status
	var hunter := current_hunter()
	var captured := []
	var survived := []
	var gained := {}
	for i in current_prey():
		var t: float = float(prey_outcome.get(i, -1.0))
		if t >= 0.0:
			captured.append(i)
			_add(hunter, 1, maxf(0.0, duration - t))
			_add(i, 0, t)
			gained[hunter] = int(gained.get(hunter, 0)) + 1
		else:
			survived.append(i)
			_add(i, 1, duration)
			gained[i] = 1
	last_round = {"hunter": hunter, "captured": captured, "survived": survived, "gained": gained}
	stage_round += 1
	round_number += 1
	if stage_round >= rounds_in_stage():
		_finish_stage()
	return status


## Votación tras un empate en el minidesempate: jugar otro entre los empatados.
func continue_tiebreak() -> void:
	if status == Status.TIE_VOTE:
		_start_stage(winners)
		winners = []
		status = Status.PLAYING


## Votación tras un empate: terminar en empate entre los que siguen empatados.
func declare_draw() -> void:
	if status == Status.TIE_VOTE:
		status = Status.FINISHED


func is_draw() -> bool:
	return status == Status.FINISHED and winners.size() > 1


## Participantes ordenados por puntos y tiempo de la fase normal (clasificación general).
func standings() -> Array:
	return _ranked(range(participants.size()), points, times)


## "Ronda 2 de 4" o "Desempate 1 · ronda 2 de 2".
func round_label() -> String:
	var n := mini(stage_round + 1, rounds_in_stage())
	if is_tiebreak():
		return "Desempate %d · ronda %d de %d" % [stage, n, rounds_in_stage()]
	return "Ronda %d de %d" % [n, rounds_in_stage()]


## "Ana 3 · IA 1 2 · ..." ordenado por la clasificación.
func score_text() -> String:
	var parts := PackedStringArray()
	for i in standings():
		parts.append("%s %d" % [participant_name(i), points[i]])
	return " · ".join(parts)


## Texto del resultado final para el jugador de ese peer (CSV).
func result_code_for(peer: int) -> String:
	if status != Status.FINISHED:
		return ""
	var me := index_of_peer(peer)
	if me in winners:
		return "empate" if winners.size() > 1 else "gana_jugador"
	return "gana_ia"


func to_dict() -> Dictionary:
	return {
		"participants": participants.duplicate(true), "stage": stage, "contenders": contenders.duplicate(),
		"stage_round": stage_round, "round_number": round_number, "points": points.duplicate(),
		"times": times.duplicate(), "stage_points": stage_points.duplicate(), "stage_times": stage_times.duplicate(),
		"status": status, "winners": winners.duplicate(), "last_round": last_round.duplicate(true), "id": id,
	}


static func from_dict(data: Dictionary) -> MatchSeries:
	var s := MatchSeries.new()
	s.participants = data["participants"]
	s.stage = data["stage"]
	s.contenders = data["contenders"]
	s.stage_round = data["stage_round"]
	s.round_number = data["round_number"]
	s.points = data["points"]
	s.times = data["times"]
	s.stage_points = data["stage_points"]
	s.stage_times = data["stage_times"]
	s.status = data["status"] as Status
	s.winners = data["winners"]
	s.last_round = data["last_round"]
	s.id = data["id"]
	# Las claves de diccionario numéricas llegan bien por la red, pero se normalizan a int.
	var gained := {}
	for key in s.last_round.get("gained", {}):
		gained[int(key)] = s.last_round["gained"][key]
	if s.last_round.has("gained"):
		s.last_round["gained"] = gained
	return s


# --- Interno ---------------------------------------------------------------------

func _add(index: int, pts: int, seconds: float) -> void:
	stage_points[index] += pts
	stage_times[index] += seconds
	if stage == 0:
		points[index] += pts
		times[index] += seconds


func _finish_stage() -> void:
	var ranked := _ranked(contenders, stage_points, stage_times)
	var best: int = ranked[0]
	var tied := []
	for i in ranked:
		if _key(i, stage_points, stage_times) == _key(best, stage_points, stage_times):
			tied.append(i)
	if tied.size() == 1:
		winners = tied
		status = Status.FINISHED
	elif stage == 0:
		_start_stage(tied)
	else:
		winners = tied
		status = Status.TIE_VOTE


func _start_stage(players: Array) -> void:
	stage += 1
	# Mismo orden de turno que en la fase normal.
	var ordered := players.duplicate()
	ordered.sort()
	contenders = ordered
	stage_round = 0
	for i in participants.size():
		stage_points[i] = 0
		stage_times[i] = 0.0


func _ranked(indices: Array, pts: Array, tms: Array) -> Array:
	var out := Array(indices).duplicate()
	out.sort_custom(func(a: int, b: int) -> bool:
		var ka := _key(a, pts, tms)
		var kb := _key(b, pts, tms)
		if ka[0] != kb[0]:
			return ka[0] > kb[0]
		if ka[1] != kb[1]:
			return ka[1] > kb[1]
		return a < b)
	return out


func _key(index: int, pts: Array, tms: Array) -> Array:
	return [pts[index], roundi(tms[index] * TIME_PRECISION)]
