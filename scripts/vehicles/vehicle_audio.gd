class_name VehicleAudio
extends Node3D
## Engine and tyre sound for one Vehicle. Three recorded engine loops (idle / low / high) are crossfaded by rpm
## and pitched with it; on-throttle is louder and brighter than coasting. Heavy vehicles use the diesel set.
## Also: tyre squeal from slip, horn, the indicator relay click (player's car only), start/stop.

const LAYERS := {
	"car": [["vehicles/engine_idle.wav", 900.0], ["vehicles/engine_low.wav", 2600.0], ["vehicles/engine_high.wav", 5200.0]],
	"heavy": [["vehicles/heavy_slow.wav", 800.0], ["vehicles/heavy_mid.wav", 1500.0], ["vehicles/heavy_fast.wav", 2300.0]],
}

var vehicle: Vehicle
var pitch := 1.0            # per-class engine character (small engines higher)
var kind := "car"
var running := false
var _layers: Array[AudioStreamPlayer3D] = []
var _refs: Array[float] = []
var _squeal: AudioStreamPlayer3D
var _horn: AudioStreamPlayer3D
var _tick: AudioStreamPlayer3D
var _level := 0.0           # engine master fade 0..1 (start-up / shut-down)
var _start_delay := 0.0


func setup(v: Vehicle, engine_pitch: float, sound_kind: String) -> void:
	vehicle = v
	pitch = engine_pitch
	kind = sound_kind
	for l: Array in LAYERS[kind]:
		var p := _player(Audio.stream(l[0], true), 8.0, 120.0)
		p.volume_db = -80.0
		_layers.append(p)
		_refs.append(l[1])
	_squeal = _player(Audio.stream("vehicles/tyre_squeal.wav", true), 6.0, 90.0)
	_squeal.volume_db = -80.0
	_horn = _player(Audio.stream("vehicles/horn.wav", true), 10.0, 160.0)
	_horn.position = Vector3(0, 0.5, v._size.z * -0.4)
	_tick = _player(Audio.stream("vehicles/indicator.wav"), 1.5, 8.0)


func _player(s: AudioStream, unit: float, range_m: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = &"Vehicles"
	p.unit_size = unit
	p.max_distance = range_m
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -10.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(p)
	return p


func start() -> void:
	if running:
		return
	running = true
	Audio.play_at(Audio.stream("vehicles/engine_start.ogg"), global_position, -2.0, pitch * randf_range(0.95, 1.05), &"Vehicles")
	_start_delay = 0.55


func stop() -> void:
	if not running:
		return
	running = false
	Audio.play_at(Audio.stream("vehicles/engine_stop.ogg"), global_position, -4.0, pitch, &"Vehicles")


func tick() -> void:
	_tick.pitch_scale = randf_range(0.98, 1.02)
	_tick.play()


func _process(delta: float) -> void:
	if not vehicle:
		return
	# engine
	_start_delay -= delta
	var target := 1.0 if running and _start_delay <= 0.0 else 0.0
	_level = move_toward(_level, target, delta * (2.5 if target > 0.0 else 1.5))
	var rpm: float = vehicle.rpm
	var thr := clampf(absf(vehicle._throttle), 0.0, 1.0)
	var idle_w := 1.0 - smoothstep(_refs[0], _refs[0] * 2.3, rpm)
	var high_w := smoothstep(_refs[1] * 1.1, _refs[2] * 0.95, rpm)
	var low_w := maxf(1.0 - idle_w - high_w, 0.0)
	var ws := [idle_w, low_w, high_w]
	for i in _layers.size():
		var p := _layers[i]
		var w: float = ws[i] * _level
		if w < 0.01:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(randf() * p.stream.get_length())
		# compressed pitch curve: the recordings cover a narrow rpm band, so don't stretch them to chipmunk
		p.pitch_scale = clampf(pow(rpm / _refs[i], 0.72) * pitch, 0.45, 2.4)
		var loud := lerpf(-7.0, 0.0, thr) if i > 0 else lerpf(-2.0, 0.0, thr)
		p.volume_db = linear_to_db(sqrt(w)) + loud
	# tyres
	var sk: float = vehicle.skidding
	var spd := vehicle.linear_velocity.length()
	if sk > 0.2 and spd > 2.0:
		if not _squeal.playing:
			_squeal.play(randf() * 2.0)
		_squeal.volume_db = linear_to_db(clampf((sk - 0.2) * 1.4, 0.05, 1.0)) - 3.0
		_squeal.pitch_scale = clampf(0.85 + spd / 60.0, 0.85, 1.15)
	elif _squeal.playing:
		_squeal.volume_db -= delta * 60.0
		if _squeal.volume_db < -40.0:
			_squeal.stop()
	# horn
	var honk: bool = vehicle.horn_on
	if honk and not _horn.playing:
		_horn.play()
	elif not honk and _horn.playing:
		_horn.stop()
