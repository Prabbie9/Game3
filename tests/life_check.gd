extends Node
## Ambient life and the radio: the soundscape follows the place and the hour (traffic downtown, surf on the beach,
## crickets at night out of town, a muffled street and room reverb indoors), pigeons scatter from the player and
## from gunfire and come back, gulls wheel over the shore, an airliner crosses the sky, and the car radio tunes,
## steps through its stations and goes quiet when the player gets out.
## godot --headless --path . res://tests/runner.tscn -- res://tests/life_check.gd

var fails := 0
var world: World
var p: Player


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	_run.call_deferred()


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _go(pos: Vector3) -> void:
	var data := WorldData.get_data()
	p._respawn(Transform3D(Basis(), Vector3(pos.x, maxf(data.height_at(pos.x, pos.z), 0.0) + 1.0, pos.z)), "")
	await _secs(2.5)


func _bed(name: String) -> float:
	return float(world.ambience._level[name]) if (world.ambience._beds[name] as AudioStreamPlayer).playing else 0.0


func _lot(kind: String) -> Dictionary:
	for l: Dictionary in WorldData.get_data().lots:
		if l.kind == kind:
			return l
	return {}


func _run() -> void:
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	world.time_of_day = 12.0
	world.traffic.budget = 0
	world.wanted.process_mode = Node.PROCESS_MODE_DISABLED
	Game.controls_enabled = true
	p = world.player
	await _secs(3.0)
	var amb := world.ambience
	# --- soundscape by place and hour
	await _go(Vector3(0, 0, 0))
	await _secs(2.0)
	_check(amb.urban > 0.5 and _bed("city") > 0.5 and _bed("crickets") == 0.0, "downtown at noon: traffic (urban %.2f, city %.2f)" % [amb.urban, _bed("city")])
	var lg := _lot("lifeguard")
	await _go(Vector3((lg.x0 + lg.x1) * 0.5, 0, (lg.z0 + lg.z1) * 0.5))
	await _secs(2.0)
	_check(amb.coast > 0.7 and _bed("surf") > 0.5, "on the beach: surf (coast %.2f, surf %.2f)" % [amb.coast, _bed("surf")])
	var gulls := world.birds.nearest_gulls(p.global_position, 200.0)
	_check(gulls != Vector3.INF and gulls.y > p.global_position.y + 6.0, "gulls wheel over the shore (%s)" % gulls)
	world.time_of_day = 23.0
	await _go(Vector3(-260, 0, -820))
	await _secs(3.0)
	_check(_bed("crickets") > 0.3 and _bed("birds") == 0.0, "Las Lomas at night: crickets %.2f, birds %.2f" % [_bed("crickets"), _bed("birds")])
	world.time_of_day = 12.0
	var sh := world.safehouse
	p._respawn(Transform3D(Basis(), sh.world(Vector3(2.0, 0.2, -6.0))), "")
	await _secs(2.5)
	var sfx := AudioServer.get_bus_index("SFX")
	var rev := false
	for i in AudioServer.get_bus_effect_count(sfx):
		if AudioServer.get_bus_effect(sfx, i) is AudioEffectReverb:
			rev = AudioServer.is_bus_effect_enabled(sfx, i)
	_check(amb.indoors > 0.9 and _bed("room") > 0.5 and amb._lowpass.cutoff_hz < 1500.0 and rev,
		"indoors: room tone, street muffled (%.0f Hz), reverb %s" % [amb._lowpass.cutoff_hz, rev])
	# --- pigeons on the plaza
	var flock: Dictionary = {}
	for f: Dictionary in world.birds.flocks:
		if f.kind == "pigeon" and Vector2(f.anchor.x, f.anchor.z).length() < 120.0:
			flock = f
			break
	_check(not flock.is_empty(), "pigeons downtown")
	if not flock.is_empty():
		var a: Vector3 = flock.anchor
		await _go(a + Vector3(25.0, 0, 0))
		await _secs(1.0)
		var grounded := (flock.birds as Array).all(func(b): return b.state == "ground")
		_check(flock.active and grounded and flock.ground > -INF, "they peck about on the ground (ground %.1f)" % flock.ground)
		var b0: Dictionary = flock.birds[0]
		p._respawn(Transform3D(Basis(), b0.pos + Vector3(1.0, 0.5, 0)), "")
		await _secs(1.5)
		var up := (flock.birds as Array).filter(func(b): return b.state in ["flee", "circle"] and b.pos.y > flock.ground + 2.0).size()
		_check(up >= flock.birds.size() - 1, "walk up and they take off (%d of %d in the air)" % [up, flock.birds.size()])
		await _go(a + Vector3(40.0, 0, 0))
		await _secs(30.0)
		var down := (flock.birds as Array).filter(func(b): return b.state == "ground").size()
		_check(down == flock.birds.size(), "they settle again once left alone (%d of %d down)" % [down, flock.birds.size()])
		Game.noise(a + Vector3(10.0, 0, 0), 60.0, p)
		await _secs(1.0)
		up = (flock.birds as Array).filter(func(b): return b.state != "ground").size()
		_check(up == flock.birds.size(), "a gunshot scatters them (%d up)" % up)
	# --- an airliner overhead
	var ac := world.aircraft
	ac.launch()
	await _secs(0.2)
	var cam := get_viewport().get_camera_3d()
	ac._plane.global_position = cam.global_position - ac._dir * 1300.0 + Vector3(0, 700.0 - cam.global_position.y, 0)
	var start := ac._plane.global_position
	await _secs(2.0)
	_check(ac._plane.visible and ac._plane.global_position.distance_to(start) > 150.0 and ac._plane.global_position.y > 600.0,
		"an airliner crosses the sky (%.0f m in 2 s at %.0f m)" % [ac._plane.global_position.distance_to(start), ac._plane.global_position.y])
	_check(ac._sounded and ac._snd.playing, "its engines rumble as it comes over")
	# --- the radio
	await _go(Vector3(0, 0, 30))
	var car := Vehicle.new()
	car.model = "sedan"
	world.add_child(car)
	car.global_position = p.global_position + Vector3(4, 0.5, 0)
	car.set_meta("radio", 2)
	await _secs(0.5)
	p.debug_seat_in(car)
	await _secs(0.5)
	var radio := world.radio
	_check(radio.current == 2 and radio._player.playing, "getting in: the car's station plays (%s)" % radio.now_playing())
	var hud_text := (Game.hud._radio.get_child(0) as Label).text
	_check(hud_text.begins_with(radio.stations[2].name), "the HUD shows the station (%s)" % hud_text)
	var ev := InputEventAction.new()
	ev.action = "radio_next"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _secs(0.2)
	_check(radio.current == 3, "next station (%s)" % radio.now_playing())
	for i in radio.stations.size() - radio.current:
		radio.step(1)
	_check(radio.current == Radio.OFF and not radio._player.playing, "stepping past the last station switches it off")
	radio.step(1)
	_check(radio.current == 0 and radio._player.playing, "and on again from the first (%s)" % radio.now_playing())
	# the stations keep playing while you are away
	radio.tune(1, false)
	var t0: int = radio._track
	var pos0 := radio._player.get_playback_position()
	var clock0 := radio._clock()
	radio._offsets[1] += 30.0   # as if half a minute had gone by
	radio.tune(1, false)
	var moved := (radio._track != t0) or absf(radio._player.get_playback_position() - pos0 - 30.0) < 2.0
	_check(moved, "a station moves on while you're away (track %d -> %d, %.1f s -> %.1f s, clock %.1f)" % [t0, radio._track, pos0, radio._player.get_playback_position(), clock0])
	p.exit_vehicle()
	await _secs(2.0)
	_check(radio.current == Radio.OFF and not radio._player.playing, "getting out: the radio stops")
	print("LIFE CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
