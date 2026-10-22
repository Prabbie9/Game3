extends Node
## Renders the fixed review shots to PNG (software Vulkan is fine; keep the list short).
## xvfb-run -a godot --path . res://tests/runner.tscn -- res://tests/screenshots.gd OUT_DIR [shot,shot,...]

var out := "tests/output"
var only := []
var world: World


func _ready() -> void:
	var a: Array = get_meta("args", [])
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		only = a[1].split(",")
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	var vp := get_viewport().get_viewport_rid()
	print("shot %s  draws %d (+%d shadow)  prims %.2fM  objects %d" % [name,
		RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, 1, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1e6,
		RenderingServer.viewport_get_render_info(vp, 0, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)])


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func _run() -> void:
	if _want("menu"):
		var menu: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(menu)
		await _frames(40)
		await _snap("menu")
		menu.queue_free()
		await _frames(2)
	var ws: PackedScene = load("res://scenes/world/world.tscn")
	world = ws.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	Game.controls_enabled = false
	await _frames(30)
	var p: Player = world.player
	p.cam.camera.make_current()
	if _want("day"):
		world.time_of_day = 16.9
		world._update_sun()
		p.cam.yaw = deg_to_rad(120)
		p.cam.pitch = -0.1
		await _frames(25)
		await _snap("day_street")
	if _want("aim"):
		p.cam.yaw = deg_to_rad(75)
		p.cam.pitch = -0.02
		Input.action_press("aim")
		await _frames(25)
		await _snap("on_foot_aim")
		Input.action_release("aim")
	if _want("wide"):
		var c := Camera3D.new()
		world.add_child(c)
		c.global_position = Vector3(-30, 28, 45)
		c.look_at(Vector3(20, 6, -10))
		c.make_current()
		await _frames(20)
		await _snap("aerial")
		c.queue_free()
		p.cam.camera.make_current()
	if _want("pool"):
		var pr: Rect2 = world.city.pool_rect
		var pc := Vector3(pr.get_center().x, 0.0, pr.get_center().y)
		var c := Camera3D.new()
		world.add_child(c)
		c.look_at_from_position(pc + Vector3(-9.0, 4.0, 8.0), pc + Vector3(0, -0.5, 0))
		c.make_current()
		await _frames(20)
		await _snap("pool")
		c.queue_free()
		p.cam.camera.make_current()
		var keep := p.global_transform
		p.global_position = pc + Vector3(1.0, -1.2, 0.5)
		p.cam.yaw = deg_to_rad(200)
		p.cam.pitch = -0.25
		await _frames(40)
		await _snap("swim")
		p.state = Player.State.ON_FOOT
		p.global_transform = keep
		p.visual.jump_to("ground")
		await _frames(10)
	if _want("enter"):
		var v: Vehicle = world.get_tree().get_nodes_in_group("vehicles")[0]
		p.global_position = v.driver_door_position() + v.global_basis.x * -0.8
		await _frames(5)
		p.visual.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		p.enter_vehicle(v)
		await _frames(12)
		var c := Camera3D.new()
		world.add_child(c)
		var door := v.driver_door_position()
		c.look_at_from_position(door - v.global_basis.x * 5.5 + v.global_basis.z * 0.6 + Vector3(0, 1.5, 0), door + Vector3(0, 0.9, 0) + v.global_basis.x * 0.8)
		c.fov = 55
		c.make_current()
		var prev := 0.0
		for t in [0.6, 2.0, 3.4, 5.6]:
			p.visual.tree.advance(t - prev)
			prev = t
			await _frames(3)
			await _snap("enter_%02d" % int(t * 10))
		p.visual.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		await _frames(10)
		c.queue_free()
		p.cam.camera.make_current()
	if _want("car"):
		var v: Vehicle = world.get_tree().get_nodes_in_group("vehicles")[0]
		if p.state != Player.State.DRIVING:
			p.debug_seat_in(v)
		p.cam.yaw = v.rotation.y + deg_to_rad(150)
		p.cam.pitch = -0.12
		await _frames(30)
		await _snap("in_car")
	if _want("night"):
		world.time_of_day = 22.0
		world._update_sun()
		await _frames(30)
		await _snap("night")
	if _want("rain"):
		world.time_of_day = 15.0
		world._update_sun()
		RenderingServer.global_shader_parameter_set("wetness", 1.0)
		await _frames(20)
		await _snap("wet")
		RenderingServer.global_shader_parameter_set("wetness", 0.0)
	if _want("pause"):
		var pm: CanvasLayer = load("res://scripts/ui/pause_menu.gd").new()
		world.add_child(pm)
		await _frames(2)
		pm._root.visible = true
		pm._fill_controls()
		pm._set_hud(false)
		await _frames(5)
		await _snap("pause")
	get_tree().quit()
