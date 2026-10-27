extends Node
## Street lights at night while driving fast: no light pops on or off (each fades) and no lit light jumps to
## another lamp. godot --headless --path . res://tests/runner.tscn -- res://tests/lights_check.gd

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.traffic.budget = 0
	world.population.enabled = false
	world.time_of_day = 23.0
	world.time_scale = 0.0
	world._update_sun()
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	var pool := world.street_lights
	# down 6th Ave (z = 0 runs east-west through downtown) at 40 m/s, eastbound then back
	var a := Vector3(-380, 2.0, 0.0)
	var b := Vector3(380, 2.0, 0.0)
	cam.global_position = a
	world.warm_up(a)
	for i in 60:
		await get_tree().process_frame
	var last_e := {}
	var last_p := {}
	for l: OmniLight3D in pool._lights:
		last_e[l] = l.light_energy if l.visible else 0.0
		last_p[l] = l.global_position
	var worst_step := 0.0
	var worst_at := ""
	var jumps := 0
	var lit_frames := 0
	var t := 0.0
	var dur := a.distance_to(b) / 40.0
	while t < dur * 2.0:
		var dt := get_process_delta_time()
		t += dt
		var k := t / dur
		cam.global_position = a.lerp(b, k) if k <= 1.0 else b.lerp(a, k - 1.0)
		cam.look_at(cam.global_position + (Vector3.RIGHT if k <= 1.0 else Vector3.LEFT), Vector3.UP)
		await get_tree().process_frame
		var on := 0
		for l: OmniLight3D in pool._lights:
			var e := l.light_energy if l.visible else 0.0
			var full := pool.night * 4.5
			if e > 0.0:
				on += 1
			var prev: float = last_e.get(l, 0.0)
			var step := absf(e - prev) / maxf(full, 0.001) / maxf(dt * 60.0, 1.0)
			if step > worst_step:
				worst_step = step
				worst_at = "%.2f s at %s (%.2f -> %.2f)" % [t, l.global_position, prev, e]
			if prev > 0.05 and e > 0.05 and last_p.get(l, l.global_position).distance_to(l.global_position) > 0.5:
				jumps += 1
			last_e[l] = e
			last_p[l] = l.global_position
		if on > 0:
			lit_frames += 1
	_check(lit_frames > 100, "street lights are on at night (%d frames with lights)" % lit_frames)
	_check(worst_step < 0.2, "no light pops on or off: the biggest change in one 60 Hz frame is %.0f%% of full (%s)" % [worst_step * 100.0, worst_at])
	_check(jumps == 0, "no lit light jumps to another lamp (%d)" % jumps)
	print("LIGHTS CHECK %s" % ("PASSED" if fails == 0 else "FAILED (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
