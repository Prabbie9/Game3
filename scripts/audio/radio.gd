class_name Radio
extends Node
## The car radio: five stations (assets/audio/radio/stations.json, built by tools/audio/build_radio.py) that keep
## playing whether or not you are listening: tune back in and the song has moved on. Every vehicle with an
## engine has its station (random, or the one you left it on, or off); radio_next / radio_prev step through
## the stations and OFF, with a burst of tuning static, and the HUD shows the station and the song. Between
## songs a station plays its ident.

const OFF := -1

var stations: Array = []          # [{id, name, tag, ident, tracks: [{file, title, artist, length}], total}]
var current := OFF                # the station playing now (OFF when not in a vehicle or switched off)
var _player: AudioStreamPlayer
var _fx: AudioStreamPlayer        # static and idents over the music
var _vehicle: Node
var _track := -1
var _offsets: Array[float] = []   # each station's head start on the shared clock
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/radio/stations.json"))
	if j is Array:
		stations = j
	for s: Dictionary in stations:
		var total := 0.0
		for t: Dictionary in s.tracks:
			total += float(t.length)
		s.total = total
		_offsets.append(_rng.randf() * total)
		# decode-ready in the background (a track loads in ~15 ms: a hitch when getting into a car)
		for t: Dictionary in s.tracks:
			ResourceLoader.load_threaded_request(Audio.DIR + String(t.file))
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	_player.finished.connect(_next_track)
	_fx = AudioStreamPlayer.new()
	_fx.bus = &"Music"
	add_child(_fx)
	var p := Game.player as Player
	if p:
		p.vehicle_changed.connect(_on_vehicle)


## True for vehicles with a radio (anything with an engine).
static func has_radio(v: Node) -> bool:
	return v is Vehicle and not (v is Bike and (v as Bike).pedal)


func _clock() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_vehicle(v: Node) -> void:
	_vehicle = v if is_instance_valid(v) and has_radio(v) else null
	if _vehicle == null:
		tune(OFF, false)
		return
	if not _vehicle.has_meta("radio"):
		_vehicle.set_meta("radio", _rng.randi() % stations.size() if stations.size() > 0 and _rng.randf() < 0.85 else OFF)
	tune(int(_vehicle.get_meta("radio")), true)


## Tunes to a station (OFF to switch off); `show` puts the station name up on the HUD.
func tune(index: int, show := true) -> void:
	if index >= stations.size():
		index = OFF
	current = index
	if _vehicle:
		_vehicle.set_meta("radio", index)
	_player.stop()
	_track = -1
	if index == OFF:
		if show and Game.hud and Game.hud.has_method("show_radio"):
			Game.hud.show_radio("RADIO OFF", "")
		return
	# where this station has got to on the shared clock
	var s: Dictionary = stations[index]
	var t := fmod(_clock() + _offsets[index], float(s.total))
	var i := 0
	while i < s.tracks.size() - 1 and t > float(s.tracks[i].length):
		t -= float(s.tracks[i].length)
		i += 1
	_play(i, t)
	if show:
		_announce()


func _play(i: int, at: float) -> void:
	var s: Dictionary = stations[current]
	_track = i
	var tr: Dictionary = s.tracks[i]
	_player.stream = Audio.stream(tr.file)
	_player.play(clampf(at, 0.0, maxf(0.0, float(tr.length) - 0.5)))


func _next_track() -> void:
	if current == OFF:
		return
	var s: Dictionary = stations[current]
	_play((_track + 1) % s.tracks.size(), 0.0)
	_fx.stream = Audio.stream(s.ident)
	_fx.volume_db = -4.0
	_fx.play()
	_announce()


func _announce() -> void:
	if current == OFF or not Game.hud or not Game.hud.has_method("show_radio"):
		return
	var s: Dictionary = stations[current]
	var tr: Dictionary = s.tracks[_track]
	Game.hud.show_radio("%s  ·  %s" % [s.name, s.tag], "%s — %s" % [tr.artist, tr.title])


## The station's name and the song now playing (empty when off).
func now_playing() -> String:
	if current == OFF or _track < 0:
		return ""
	var s: Dictionary = stations[current]
	return "%s: %s — %s" % [s.name, s.tracks[_track].artist, s.tracks[_track].title]


func step(dir: int) -> void:
	if _vehicle == null or stations.is_empty():
		return
	# OFF sits between the last station and the first
	var n := stations.size() + 1
	var i := (current + 1 + dir + n) % n - 1
	_fx.stream = Audio.stream("radio/static.ogg")
	_fx.volume_db = -8.0
	_fx.play()
	tune(i, true)


func _unhandled_input(event: InputEvent) -> void:
	if _vehicle == null or not Game.controls_enabled or get_tree().paused:
		return
	if event.is_action_pressed("radio_next"):
		step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("radio_prev"):
		step(-1)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# off as the player opens the door to get out (or the vehicle is wrecked, or they are thrown out)
	var p := Game.player as Player
	if _vehicle != null and (not is_instance_valid(_vehicle) or p == null or p.vehicle != _vehicle or p.state == Player.State.EXITING):
		_on_vehicle(null)
