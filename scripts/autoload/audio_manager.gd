extends Node
## Autoload "Audio": música de fondo y efectos de sonido.
##
## - Música: el primer archivo de res://audio/music/ (.ogg recomendado, también .mp3 o .wav),
##   en bucle y sin cortarse al cambiar de escena.
## - Efectos: res://audio/sfx/<nombre>.wav. play_at() los sitúa en el mundo (3D) y solo se oyen
##   hasta max_distance, que coincide con el radio del ruido en la jugabilidad: lo que oyes es lo
##   mismo que "oye" la IA. play() los reproduce sin posición (interfaz, avisos de la partida).
## - El oyente (AudioListener3D) va en el CameraRig, a la altura del personaje que sigue la cámara.
## - Volumen: GameConfig (grupo Audio), ajustable en F1.

const MUSIC_DIR := "res://audio/music/"
const SFX_DIR := "res://audio/sfx/"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
## Variación aleatoria de tono para que los sonidos repetidos (pasos) no suenen idénticos.
const PITCH_VARIATION := 0.08

## Red: en el anfitrión recibe cada sonido del mundo para reenviarlo a los clientes.
var world_sound_hook: Callable
## Red: en un cliente, los sonidos del mundo solo llegan del anfitrión (los locales se ignoran).
var remote_world_sounds: bool = false
## Sonidos recibidos del anfitrión (para las pruebas).
var net_sounds_received: int = 0

var _streams: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	_apply_volumes()
	play_music()
	# Clic en todos los botones de la interfaz.
	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	_apply_volumes()


## Empieza la música de fondo (si hay un archivo en audio/music/).
func play_music() -> void:
	var stream := _find_music()
	if stream == null:
		return
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * (stream as AudioStreamWAV).mix_rate)
	_music.stream = stream
	_music.play()


func has_music() -> bool:
	return _music.stream != null


## Efecto sin posición (interfaz, cuenta atrás, victoria...).
func play(sound: String, volume_db: float = 0.0) -> void:
	var stream := _get_stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## Efecto situado en el mundo; solo se oye a menos de max_distance metros del oyente.
func play_at(sound: String, position: Vector3, max_distance: float, volume_db: float = 0.0, vary_pitch: bool = true, from_net: bool = false) -> void:
	if remote_world_sounds and not from_net:
		return
	if from_net:
		net_sounds_received += 1
	if world_sound_hook.is_valid():
		world_sound_hook.call(sound, position, max_distance, volume_db, vary_pitch)
	var stream := _get_stream(sound)
	var scene := get_tree().current_scene
	if stream == null or scene == null or not scene is Node3D:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.volume_db = volume_db
	player.max_distance = max_distance
	# Atenuación suave hasta max_distance (más allá, silencio).
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = maxf(max_distance * 0.35, 1.0)
	player.panning_strength = 0.6
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	if vary_pitch:
		player.pitch_scale = randf_range(1.0 - PITCH_VARIATION, 1.0 + PITCH_VARIATION)
	player.finished.connect(player.queue_free)
	scene.add_child(player)
	player.global_position = position
	player.play()


## Uno de varios efectos numerados al azar (p. ej. "step" -> step_0..step_3).
func play_random_at(prefix: String, count: int, position: Vector3, max_distance: float, volume_db: float = 0.0) -> void:
	play_at("%s_%d" % [prefix, randi() % count], position, max_distance, volume_db)


# --- Interno -----------------------------------------------------------------------

func _get_stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := SFX_DIR + sound + ".wav"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
		if _streams[sound] == null:
			push_warning("Falta el sonido %s" % path)
	return _streams[sound]


func _find_music() -> AudioStream:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return null
	var files := Array(dir.get_files())
	files.sort()
	for file: String in files:
		# En el juego exportado los archivos aparecen como .import; se carga por el nombre original.
		var name := file.trim_suffix(".import")
		if name.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
			var stream := load(MUSIC_DIR + name) as AudioStream
			if stream:
				return stream
	return null


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _apply_volumes() -> void:
	var cfg := GameManager.config
	_set_bus_volume(MUSIC_BUS, cfg.music_volume if cfg.audio_enabled else 0.0)
	_set_bus_volume(SFX_BUS, cfg.sfx_volume if cfg.audio_enabled else 0.0)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("ui_click", -6.0))
