extends Node
## Sound playback (autoload "Audio"): buses, a stream cache, and pooled 3D one-shots so nothing is created in
## hot paths. Looping streams (engine layers, squeal, fire, rain) get their loop flags set once on load.

const DIR := "res://assets/audio/"
const POOL := 32
const BUSES := ["SFX", "Vehicles", "Ambience", "Music"]

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	# vehicles and ambience sit a little under the effects; a gentle limiter keeps crashes from clipping
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Vehicles"), -2.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), -4.0)
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 6.0
		p.max_distance = 90.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -12.0
		add_child(p)
		_pool.append(p)


## Stream for a file under assets/audio ("vehicles/horn.wav"). `loop` makes it loop seamlessly.
func stream(path: String, loop := false) -> AudioStream:
	var key := path + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = load(DIR + path)
	if loop:
		s = s.duplicate()
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	_streams[key] = s
	return s


## One of several variations: "vehicles/crash_%d.ogg" with n = 4 picks crash_0..crash_3.
func pick(pattern: String, n: int) -> AudioStream:
	return stream(pattern % (randi() % n))


## Fire-and-forget positional sound from the pool (the oldest voice is reused when all are busy).
func play_at(s: AudioStream, pos: Vector3, volume_db := 0.0, pitch := 1.0, bus := &"SFX", range_m := 90.0) -> void:
	if s == null or not is_inside_tree():
		return
	var p: AudioStreamPlayer3D = null
	for i in POOL:
		var c := _pool[(_next + i) % POOL]
		if not c.playing:
			p = c
			_next = (_next + i + 1) % POOL
			break
	if p == null:
		p = _pool[_next]
		_next = (_next + 1) % POOL
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	p.max_distance = range_m
	p.play()


func release() -> void:
	_streams.clear()
