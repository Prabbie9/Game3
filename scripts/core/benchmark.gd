extends Node
## Benchmark: scripted camera fly-through of the heaviest areas. Records every frame time plus render
## stats and writes a report (avg / 1% low / min FPS, frame-time graph, stats) next to the executable.

const DURATION := 90.0
const WARMUP := 3.0
## Route (x, height above ground, z): downtown streets, round the freeway, along the beach, through the port,
## then a high pass back over downtown. Fast enough to stress cell streaming like a car at speed.
const ROUTE := [
	Vector3(12, 2.2, 12), Vector3(40, 2.0, 3), Vector3(75, 2.5, 2), Vector3(160, 3.0, 0), Vector3(400, 3.0, 0), Vector3(560, 3.0, 0),
	Vector3(560, 3.0, -220), Vector3(525, 3.0, -465), Vector3(300, 3.0, -500), Vector3(0, 3.0, -500), Vector3(-300, 3.0, -500),
	Vector3(-525, 3.0, -465), Vector3(-560, 3.0, -240), Vector3(-650, 3.0, -240), Vector3(-745, 4.0, -230), Vector3(-745, 4.0, 0),
	Vector3(-745, 4.0, 240), Vector3(-745, 4.0, 560), Vector3(-500, 4.0, 700), Vector3(-240, 4.0, 690), Vector3(0, 4.0, 612),
	Vector3(300, 6.0, 612), Vector3(500, 25.0, 700), Vector3(600, 40.0, 500), Vector3(300, 60.0, 200), Vector3(100, 30.0, 60),
	Vector3(12, 2.2, 12),
]

var _cam: Camera3D
var _curve: Curve3D
var _t := 0.0
var _frames := PackedFloat32Array()
var _stats := {"draws": 0.0, "shadow_draws": 0.0, "prims": 0.0, "objects": 0.0, "process": 0.0, "physics": 0.0, "n": 0}
var _done := false


func _ready() -> void:
	_curve = Curve3D.new()
	var d := WorldData.get_data()
	var pts := []
	for q: Vector3 in ROUTE:
		pts.append(Vector3(q.x, d.height_at(q.x, q.z) + q.y, q.z))
	for i in pts.size():
		var p: Vector3 = pts[i]
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var tangent := (nxt - prev) * 0.25
		_curve.add_point(p, -tangent, tangent)
	_cam = Camera3D.new()
	_cam.fov = 70
	_cam.far = 4000
	get_parent().add_child.call_deferred(_cam)
	_cam.make_current.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.message("Benchmark running…")


func _process(delta: float) -> void:
	if _done or not _cam.is_inside_tree():
		return
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var len := _curve.get_baked_length()
	var pos := _curve.sample_baked(k * len)
	var ahead := _curve.sample_baked(minf(k * len + 12.0, len))
	_cam.global_position = pos
	if ahead.distance_to(pos) > 0.1:
		_cam.look_at(ahead + Vector3(0, -0.6, 0))
	if _t > WARMUP:
		_frames.append(delta * 1000.0)
		var vp := get_viewport().get_viewport_rid()
		_stats.draws += RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		_stats.shadow_draws += RenderingServer.viewport_get_render_info(vp, 1, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		_stats.prims += RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		_stats.objects += RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		_stats.process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_stats.physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_stats.n += 1
	if _t >= DURATION:
		_done = true
		_write_report()


func _write_report() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for f in _frames:
		total += f
	var avg_ms := total / maxf(n, 1)
	var worst := sorted.slice(int(n * 0.99), n)
	var worst_avg := 0.0
	for f in worst:
		worst_avg += f
	worst_avg /= maxf(worst.size(), 1)
	var lines := PackedStringArray()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	lines.append("PORT SOLANO BENCHMARK  —  %s" % Time.get_datetime_string_from_system())
	lines.append("Version %s   Preset %s   Resolution %s   Render scale %.2f" % [ProjectSettings.get_setting("application/config/version"),
		GraphicsSettings.PRESET_NAMES[GraphicsSettings.preset], str(get_viewport().get_visible_rect().size), GraphicsSettings.values.render_scale])
	lines.append("GPU: %s  (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	lines.append("CPU: %s  x%d" % [OS.get_processor_name(), OS.get_processor_count()])
	lines.append("")
	lines.append("Frames measured: %d over %.1f s" % [n, total / 1000.0])
	lines.append("Average FPS:  %.1f   (%.2f ms)" % [1000.0 / avg_ms, avg_ms])
	lines.append("1%% low FPS:   %.1f   (%.2f ms)" % [1000.0 / maxf(worst_avg, 0.001), worst_avg])
	lines.append("Minimum FPS:  %.1f   (%.2f ms)" % [1000.0 / maxf(sorted[n - 1], 0.001), sorted[n - 1]])
	lines.append("Frames over 16.7 ms: %d (%.2f%%)" % [_count_over(sorted, 16.7), 100.0 * _count_over(sorted, 16.7) / maxf(n, 1)])
	lines.append("")
	var c := maxf(_stats.n, 1)
	lines.append("Average per frame: draw calls %d (+%d shadow), primitives %.2f M, objects %d" % [_stats.draws / c, _stats.shadow_draws / c, _stats.prims / c / 1e6, _stats.objects / c])
	lines.append("Average CPU: process %.2f ms, physics %.2f ms" % [_stats.process / c, _stats.physics / c])
	lines.append("")
	lines.append("Frame time per second of the run (avg ms | worst ms):")
	var per_sec := []
	var acc := 0.0
	var bucket := []
	for f in _frames:
		bucket.append(f)
		acc += f
		if acc >= 1000.0:
			per_sec.append(bucket)
			bucket = []
			acc = 0.0
	for i in per_sec.size():
		var b: Array = per_sec[i]
		var s := 0.0
		var mx := 0.0
		for f in b:
			s += f
			mx = maxf(mx, f)
		var a := s / b.size()
		lines.append("%3ds %6.2f | %6.2f  %s" % [i, a, mx, "#".repeat(clampi(int(a), 0, 60))])
	var dir := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("user://")
	var path := dir.path_join("benchmark_%s.txt" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = ProjectSettings.globalize_path("user://benchmark_%s.txt" % stamp)
		f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	var csv := FileAccess.open(path.get_basename() + "_frametimes.csv", FileAccess.WRITE)
	if csv:
		csv.store_string("frame,ms\n")
		for i in _frames.size():
			csv.store_string("%d,%.3f\n" % [i, _frames[i]])
		csv.close()
	print("BENCHMARK REPORT: ", path)
	print("\n".join(lines.slice(0, 12)))
	Game.message("Benchmark finished. Report saved to:\n%s" % path)
	if "--benchmark" in OS.get_cmdline_user_args() or "--benchmark" in OS.get_cmdline_args():
		get_tree().quit()
	else:
		await get_tree().create_timer(4.0).timeout
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _count_over(sorted: PackedFloat32Array, ms: float) -> int:
	var c := 0
	for f in sorted:
		if f > ms:
			c += 1
	return c
