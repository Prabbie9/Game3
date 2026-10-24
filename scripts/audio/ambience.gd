class_name Ambience
extends Node
## The city soundscape around the listener, by district and time of day: distant traffic where it is built up,
## surf near the water, birdsong by day and crickets at night away from the centre, wind up on the hills; gull
## cries along the coast, construction sites working by day, a ship's horn in the port, now and then a siren
## somewhere across town. Indoors the street is muffled, a room tone hums and sounds get a short room reverb.

const GRID := 64.0
## lot kind -> how built-up it makes its surroundings
const URBAN := {"block": 1.0, "midrise": 1.0, "plaza": 0.8, "parking": 0.7, "industrial": 0.7, "container_yard": 0.6,
	"port_sheds": 0.6, "crane": 0.6, "house": 0.3, "mansion": 0.2, "park": 0.3, "boardwalk": 0.4, "beachfront": 0.4}
const BEDS := {"city": -3.0, "surf": -2.0, "birds": -6.0, "crickets": -8.0, "wind": -6.0, "room": -4.0}

var cost_ms := 0.0      # main-thread time of the last frame (perf overlay / stream_check)
var urban := 0.0
var coast := 0.0
var hills := 0.0
var indoors := 0.0
var _beds := {}          # name -> AudioStreamPlayer
var _level := {}         # name -> smoothed linear level
var _grid := {}          # Vector2i -> urban weight
var _sites: Array[Vector3] = []   # construction (crane lots)
var _port: Array[Vector3] = []
var _site_players: Array[AudioStreamPlayer3D] = []
var _far: AudioStreamPlayer3D      # distant one-shots (siren, ship's horn)
var _probe_t := 0.0
var _gull_t := 5.0
var _siren_t := 90.0
var _horn_t := 40.0
var _rng := RandomNumberGenerator.new()
var _amb_bus := -1
var _sfx_bus := -1
var _lowpass: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _data: WorldData


func _ready() -> void:
	_rng.randomize()
	_data = WorldData.get_data()
	var raw := {}
	for l: Dictionary in _data.lots:
		var w: float = URBAN.get(l.kind, 0.0)
		var c := Vector3((float(l.x0) + float(l.x1)) * 0.5, 0, (float(l.z0) + float(l.z1)) * 0.5)
		if l.kind == "crane":
			_sites.append(c)
		elif l.kind in ["container_yard", "port_sheds"]:
			_port.append(c)
		if w > 0.0:
			var k := Vector2i(floori(c.x / GRID), floori(c.z / GRID))
			raw[k] = maxf(float(raw.get(k, 0.0)), w)
	# each cell takes its most built-up lot, spread over the neighbours so the bed fades over a block or two
	for k: Vector2i in raw:
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var kk := k + Vector2i(dx, dz)
				var fall := 1.0 / (1.0 + float(dx * dx + dz * dz))
				_grid[kk] = maxf(float(_grid.get(kk, 0.0)), float(raw[k]) * fall)
	for name: String in BEDS:
		var p := AudioStreamPlayer.new()
		p.stream = Audio.stream("ambience/%s_loop.ogg" % name if name != "room" else "ambience/room_tone.ogg", true)
		p.bus = &"Ambience"
		p.volume_db = -80.0
		add_child(p)
		_beds[name] = p
		_level[name] = 0.0
	for i in 2:
		var s := AudioStreamPlayer3D.new()
		s.stream = Audio.stream("ambience/construction_loop.ogg", true)
		s.bus = &"Ambience"
		s.unit_size = 18.0
		s.max_distance = 260.0
		add_child(s)
		_site_players.append(s)
	_far = AudioStreamPlayer3D.new()
	_far.bus = &"Ambience"
	_far.unit_size = 120.0
	_far.max_distance = 2000.0
	add_child(_far)
	# indoors: the ambience bus is low-passed and the effects get a short room reverb
	_amb_bus = AudioServer.get_bus_index("Ambience")
	_sfx_bus = AudioServer.get_bus_index("SFX")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_amb_bus, _lowpass)
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.3
	_reverb.damping = 0.6
	_reverb.spread = 0.8
	_reverb.dry = 1.0
	_reverb.wet = 0.0
	_reverb.predelay_msec = 12.0
	AudioServer.add_bus_effect(_sfx_bus, _reverb)
	AudioServer.set_bus_effect_enabled(_sfx_bus, AudioServer.get_bus_effect_count(_sfx_bus) - 1, false)


func _exit_tree() -> void:
	for pair: Array in [[_amb_bus, _lowpass], [_sfx_bus, _reverb]]:
		var bus: int = pair[0]
		for i in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus, i) == pair[1]:
				AudioServer.remove_bus_effect(bus, i)


func _urban_at(p: Vector3) -> float:
	var fx := p.x / GRID - 0.5
	var fz := p.z / GRID - 0.5
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - i
	var tz := fz - j
	var g := func(a: int, b: int) -> float: return float(_grid.get(Vector2i(a, b), 0.0))
	var v := lerpf(lerpf(g.call(i, j), g.call(i + 1, j), tx), lerpf(g.call(i, j + 1), g.call(i + 1, j + 1), tx), tz)
	return clampf(v, 0.0, 1.0)


## How close the sea is: 1 within 40 m of the water, 0 beyond ~260 m inland.
func _coast_at(p: Vector3) -> float:
	var best := 400.0
	for r: float in [15.0, 30.0, 60.0, 90.0, 130.0, 180.0, 260.0]:
		for k in 12:
			var a := TAU * k / 12.0
			if _data.height_at(p.x + cos(a) * r, p.z + sin(a) * r) < _data.sea - 0.3:
				best = r
				break
		if best < 400.0:
			break
	if _data.height_at(p.x, p.z) < _data.sea - 0.3:
		best = 0.0
	return clampf(1.0 - (best - 40.0) / 220.0, 0.0, 1.0)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update(delta)
	cost_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _update(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var w := Game.world as World
	if cam == null or w == null:
		return
	var eye := cam.global_position
	_probe_t -= delta
	var inside := false
	for n: Node in get_tree().get_nodes_in_group("interiors"):
		if n.has_method("inside") and n.inside(eye):
			inside = true
			break
	if _probe_t <= 0.0:
		_probe_t = 0.5
		urban = _urban_at(eye)
		coast = _coast_at(eye)
		var ground := _data.height_at(eye.x, eye.z)
		hills = clampf((ground - 25.0) / 70.0, 0.0, 1.0) + clampf((eye.y - maxf(ground, 0.0) - 40.0) / 120.0, 0.0, 1.0)
	indoors = move_toward(indoors, 1.0 if inside else 0.0, delta * 2.5)
	var h := fposmod(w.time_of_day, 24.0)
	var day := clampf(minf((h - 5.5) / 1.5, (20.0 - h) / 1.5), 0.0, 1.0)
	var rain := w.weather.rain if w.weather else 0.0
	var out := 1.0 - indoors
	var want := {
		"city": (0.2 + 0.8 * urban) * (0.55 + 0.45 * day) * (1.0 - 0.75 * indoors),
		"surf": coast * (1.0 - 0.85 * indoors),
		"birds": day * (1.0 - rain) * (0.25 + 0.75 * (1.0 - urban)) * (1.0 - 0.5 * coast) * out,
		"crickets": (1.0 - day) * (1.0 - 0.8 * rain) * (1.0 - 0.85 * urban) * (1.0 - 0.6 * coast) * out,
		"wind": clampf(hills + 0.15 * coast + 0.3 * rain, 0.0, 1.0) * out,
		"room": indoors,
	}
	for name: String in BEDS:
		var lv := move_toward(float(_level[name]), float(want[name]), delta * 0.5)
		_level[name] = lv
		var p: AudioStreamPlayer = _beds[name]
		if lv > 0.01:
			if not p.playing:
				p.play(_rng.randf() * maxf(0.1, p.stream.get_length() - 0.1))
			p.volume_db = linear_to_db(lv) + float(BEDS[name])
		elif p.playing:
			p.stop()
	_lowpass.cutoff_hz = lerpf(20000.0, 650.0, indoors)
	var rev_on := indoors > 0.05
	var ri := AudioServer.get_bus_effect_count(_sfx_bus) - 1
	for i in AudioServer.get_bus_effect_count(_sfx_bus):
		if AudioServer.get_bus_effect(_sfx_bus, i) == _reverb:
			ri = i
	if AudioServer.is_bus_effect_enabled(_sfx_bus, ri) != rev_on:
		AudioServer.set_bus_effect_enabled(_sfx_bus, ri, rev_on)
	_reverb.wet = 0.16 * indoors
	_sites_update(eye, h)
	_one_shots(delta, eye, day, w)


## Construction sites (the crane lots) work 7:00-18:00; the nearest two within earshot play.
func _sites_update(eye: Vector3, h: float) -> void:
	var near := _sites.filter(func(s): return s.distance_to(eye) < 260.0)
	near.sort_custom(func(a, b): return a.distance_to(eye) < b.distance_to(eye))
	var working := h > 7.0 and h < 18.0
	for i in _site_players.size():
		var s := _site_players[i]
		if working and i < near.size():
			var at: Vector3 = near[i]
			at.y = _data.height_at(at.x, at.z) + 6.0
			if not s.playing or s.global_position.distance_to(at) > 1.0:
				s.global_position = at
				if not s.playing:
					s.play(_rng.randf() * 10.0)
		elif s.playing:
			s.stop()


func _one_shots(delta: float, eye: Vector3, day: float, w: World) -> void:
	# gulls: from a wheeling flock if one is in sight, else somewhere above the shore
	_gull_t -= delta
	if _gull_t <= 0.0:
		_gull_t = _rng.randf_range(3.0, 9.0)
		if coast > 0.25 and day > 0.3 and indoors < 0.5:
			var at := w.birds.nearest_gulls(eye, 160.0) if w.birds else Vector3.INF
			if at == Vector3.INF:
				var a := _rng.randf() * TAU
				at = eye + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(25.0, 70.0) + Vector3(0, _rng.randf_range(12.0, 30.0), 0)
			Audio.play_at(Audio.pick("ambience/gull_%d.ogg", 5), at, -4.0, _rng.randf_range(0.92, 1.08), &"Ambience", 180.0)
	# a siren somewhere across town (not while the player has the police's attention)
	_siren_t -= delta
	if _siren_t <= 0.0:
		_siren_t = _rng.randf_range(80.0, 200.0)
		if urban > 0.3 and indoors < 0.5 and (w.wanted == null or w.wanted.stars == 0) and not _far.playing:
			var a := _rng.randf() * TAU
			_far.stream = Audio.stream("ambience/siren_far.ogg")
			_far.global_position = eye + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(300.0, 500.0) + Vector3(0, 20.0, 0)
			_far.volume_db = -6.0
			_far.play()
	# a ship's horn in the port
	_horn_t -= delta
	if _horn_t <= 0.0:
		_horn_t = _rng.randf_range(60.0, 150.0)
		var best := Vector3.INF
		for p in _port:
			if p.distance_to(eye) < best.distance_to(eye):
				best = p
		if best != Vector3.INF and best.distance_to(eye) < 900.0 and not _far.playing:
			_far.stream = Audio.stream("ambience/ship_horn.ogg")
			_far.global_position = best + Vector3(_rng.randf_range(-80.0, 80.0), 15.0, 120.0)
			_far.volume_db = 0.0
			_far.play()
