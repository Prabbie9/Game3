extends Node
## Every vehicle with an NPC at the wheel, seen from the front-left: checks that drivers sit inside the cab.
## xvfb-run -a godot --path . res://tests/runner.tscn -- res://tools/dev/driver_lineup.gd OUT.png [character]
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Array = get_meta("args")
	var out: String = args[0]
	var who: String = args[1] if args.size() > 1 else "ch33_nonpbr"
	get_tree().root.size = Vector2i(1800, 1000)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.66, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position.y = -0.5
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	gm.mesh = pm
	ground.add_child(gm)
	add_child(ground)
	NPCDriver.preload_characters()
	while not NPCDriver.is_ready(who):
		await get_tree().process_frame
	var models: Array = Vehicle.SPECS.keys().filter(func(m): return not (m in ["bicycle", "dirtbike", "heli", "speedboat"]))
	for i in models.size():
		var v := Vehicle.new()
		v.model = models[i]
		add_child(v)
		v.global_position = Vector3((i % 6) * 6.0, 1.0, (i / 6) * 14.0)
		v.freeze = true
		NPCDriver.seat_in(v, who)
		var l := Label3D.new()
		l.text = models[i]
		l.font_size = 72
		l.position = Vector3(0, 4.0, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		v.add_child(l)
	for i in 90:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(-10, 9, -16), Vector3(15, 1.0, 12))
	cam.fov = 60
	cam.make_current()
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(out)
	get_tree().quit()
