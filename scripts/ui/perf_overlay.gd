extends CanvasLayer
## F3 performance overlay: FPS, frame time graph, draw calls, primitives, objects, memory, physics.

var _label: Label
var _graph: Control
var _times := PackedFloat32Array()
var _accum := 0.0


func _ready() -> void:
	layer = 50
	visible = false
	var panel := PanelContainer.new()
	panel.theme = UITheme.get_theme()
	panel.position = Vector2(20, 120)
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	_label = UITheme.label("", 15, UITheme.body_bold)
	vb.add_child(_label)
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(300, 70)
	_graph.draw.connect(_draw_graph)
	vb.add_child(_graph)
	_times.resize(240)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("perf_overlay"):
		visible = not visible


func _process(delta: float) -> void:
	_times.remove_at(0)
	_times.append(delta * 1000.0)
	if not visible:
		return
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	var vp := get_viewport().get_viewport_rid()
	var draws := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	var sdraws := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_label.text = "%d FPS   %.1f ms\nCPU process %.2f ms   physics %.2f ms\nDraw calls %d  (+%d shadow)\nPrimitives %.2f M   Objects %d\nVRAM %d MB   Static mem %d MB\nPhysics bodies %d   Nodes %d\nPreset %s" % [
		Engine.get_frames_per_second(), delta * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		draws, sdraws, prims / 1e6, objs,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		GraphicsSettings.PRESET_NAMES[GraphicsSettings.preset]]
	_graph.queue_redraw()


func _draw_graph() -> void:
	var s := _graph.size
	_graph.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.35))
	for ms: float in [16.67, 33.3]:
		var y := s.y - ms / 40.0 * s.y
		_graph.draw_line(Vector2(0, y), Vector2(s.x, y), Color(1, 1, 1, 0.25), 1.0)
	var n := _times.size()
	for i in n:
		var ms := _times[i]
		var h := clampf(ms / 40.0, 0.0, 1.0) * s.y
		var col := UITheme.TEAL if ms <= 16.8 else (UITheme.SAND if ms <= 33.4 else UITheme.CORAL)
		_graph.draw_line(Vector2(i * s.x / n, s.y), Vector2(i * s.x / n, s.y - h), col, s.x / n + 0.5)
