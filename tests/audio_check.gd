extends Node
## Audio hooks: footsteps fire at a walking/running cadence and know the surface; the ground-kind lookup tells
## town from beach and boardwalk; every sound file the game asks for loads.
## godot --headless --path . res://tests/runner.tscn -- res://tests/audio_check.gd

var fails := 0
var steps := []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	for f in ["vehicles/engine_idle.wav", "vehicles/engine_low.wav", "vehicles/engine_high.wav", "vehicles/tyre_squeal.wav",
			"vehicles/horn.wav", "vehicles/indicator.wav", "vehicles/fire_loop.ogg", "world/rain_loop.ogg"]:
		var s := Audio.stream(f, true)
		_check(s != null and s.get_length() > 0.1, "loads %s (%.2f s)" % [f, s.get_length() if s else 0.0])
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.time_scale = 0.0
	await _frames(60)
	var p: Player = world.player
	p.foot_ik.stepped.connect(func(foot: int, pos: Vector3, col: Object): steps.append([foot, pos, col]))
	Game.controls_enabled = true
	p.cam.yaw = p.rotation.y
	for mode: Array in [["run", false, 2.0, 3.4], ["sprint", true, 2.4, 4.2]]:
		steps.clear()
		Input.action_press("move_forward")
		if mode[1]:
			Input.action_press("sprint")
		await _frames(60)
		steps.clear()
		await _frames(180)
		Input.action_release("move_forward")
		Input.action_release("sprint")
		var rate := steps.size() / 3.0
		var alternate := true
		for i in range(1, steps.size()):
			if steps[i][0] == steps[i - 1][0]:
				alternate = false
		_check(rate >= mode[2] and rate <= mode[3], "%s: %.1f steps/s" % [mode[0], rate])
		_check(alternate, "%s: feet alternate" % mode[0])
		await _frames(40)
	var d := WorldData.get_data()
	_check(d.ground_kind(26, 9, false) == "concrete", "street is concrete")
	var beach := ""
	var wood := ""
	for l: Dictionary in d.lots:
		if l.kind == "boardwalk" and wood == "":
			wood = d.ground_kind((l.x0 + l.x1) * 0.5, (l.z0 + l.z1) * 0.5, true)
	_check(wood == "wood", "boardwalk is wood (%s)" % wood)
	# beach: a natural sample near sea level on the west coast
	for x in range(-900, -700, 4):
		var h := d.height_at(x, 60)
		if h > d.sea + 0.3 and h < d.sea + 2.0:
			beach = d.ground_kind(x, 60, true)
			break
	_check(beach == "sand", "beach is sand (%s)" % beach)
	print("AUDIO CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
