extends Node
## Streaming hitch check (headless): flies a camera along the benchmark route at ~45 m/s and records how long each
## frame's main-thread work takes. Fails if any frame spends too long (cells/terrain must stream without hitches).
## godot --headless --path . res://tests/runner.tscn -- res://tests/stream_check.gd

## Generous for this 4-core software-rendering container; the owner's PC is several times faster.
const P99_MS := 12.0
const SPIKE_MS := 40.0   # frames over this count as spikes...
const MAX_SPIKES := 3    # ...a few isolated ones are tolerated (this container's scheduling jitter shows up as
                         # single 40-100 ms frames outside any script time, run to run, wherever they fall)
const WORST_MS := 150.0

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: World = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	world.time_scale = 0.0
	# streaming only: no traffic or crowd round the (parked) player, whose physics would swamp the numbers
	# (traffic_check measures their cost)
	world.traffic.set_deferred("budget", 0)
	world.population.enabled = false
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	var d := WorldData.get_data()
	var route: Array = preload("res://scripts/core/benchmark.gd").ROUTE
	var pts := []
	for q: Vector3 in route:
		pts.append(Vector3(q.x, d.height_at(q.x, q.z) + q.y, q.z))
	var times := PackedFloat32Array()
	var speed := 45.0
	var dt := 1.0 / 60.0
	var last := Time.get_ticks_usec()
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := maxi(int(a.distance_to(b) / (speed * dt)), 1)
		for k in n:
			cam.global_position = a.lerp(b, float(k) / n)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			if (now - last) > 20000 and times.size() > 30:
				print("STREAM slow frame %.1f ms at %s, phys %.1f ms, process %.1f ms (traffic %.1f, people %.1f, birds %.1f, ambience %.1f, parked %.1f, pushables %.1f, cells %d, objects %d)" % [(now - last) / 1000.0, cam.global_position.snapped(Vector3.ONE), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, world.traffic.cost_ms, world.population.cost_ms, world.birds.cost_ms, world.ambience.cost_ms, world.parked.cost_ms, world.pushables.cost_ms, world.city._cells.size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
			last = now
	times = times.slice(30)
	var sorted := times.duplicate()
	sorted.sort()
	var worst := sorted[-1]
	var p99 := sorted[int(sorted.size() * 0.99)]
	var total := 0.0
	for t in times:
		total += t
	print("STREAM: %d frames, avg %.1f ms, p99 %.1f ms, worst %.1f ms, cells loaded %d" % [times.size(), total / times.size(), p99, worst, world.city._cells.size()])
	var spikes := 0
	for t in times:
		if t > SPIKE_MS:
			spikes += 1
	print("STREAM: %d frames over %.0f ms" % [spikes, SPIKE_MS])
	var ok: bool = p99 < P99_MS and worst < WORST_MS and spikes <= MAX_SPIKES
	print("STREAM CHECK: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
