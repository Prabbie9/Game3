extends Node
## Lines up vehicles on a pad and photographs them (front-left and rear-right), sirens and lights on.
## xvfb-run -a godot --path . res://tests/runner.tscn -- res://tests/showroom.gd OUT_DIR [model,model,...]

var out := "tests/output"
var models := ["muscle", "police", "van", "ambulance", "boxtruck", "bus", "firetruck", "heli", "speedboat"]


func _ready() -> void:
	var a: Array = get_meta("args", [])
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		models = Array(a[1].split(","))
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	root.add_child(sun)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(400, 2, 400)
	cs.shape = b
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.32, 0.33)
	gm.roughness = 0.9
	pm.material = gm
	mi.mesh = pm
	mi.position.y = 1.0
	sb.add_child(mi)
	sb.position.y = -1.0
	root.add_child(sb)
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	cam.make_current()
	for m: String in models:
		var v: Vehicle
		match m:
			"heli":
				v = Helicopter.new()
			"speedboat":
				v = Boat.new()
				v.freeze = true
			_:
				v = Vehicle.new()
				v.model = m
		v.position = Vector3(0, 0.05 if m != "speedboat" else 0.0, 0)
		root.add_child(v)
		for i in 40:
			await get_tree().physics_frame
		v.set_headlights(true)
		v.set_siren(true)
		var d: float = maxf(v._size.z, v._size.x) * 1.15 + 2.5
		for view: Array in [["fl", Vector3(-0.75, 0.32, -1.0)], ["rr", Vector3(0.8, 0.3, 0.9)]]:
			var dir: Vector3 = (view[1] as Vector3).normalized()
			cam.look_at_from_position(v.global_position + dir * d + Vector3(0, 0.6, 0), v.global_position + Vector3(0, v._size.y * 0.45, 0))
			for i in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [m, view[0]]))
		if OS.get_environment("HIDE_WHEELS") != "":
			for w: VehicleWheel3D in v._wheels:
				for ch in w.get_children():
					if ch is Node3D:
						(ch as Node3D).visible = false
		# close-up of the front-left wheel (cut-out wheels, arches)
		for w: VehicleWheel3D in v._wheels:
			if w.use_as_steering and w.position.x < 0.0:
				var wp := w.global_position
				cam.look_at_from_position(wp - v.global_basis.x * 2.2 + v.global_basis.z * 0.6 + Vector3(0, 0.25, 0), wp)
				for i in 8:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_tree().root.get_texture().get_image().save_png(out.path_join("%s_wheel.png" % m))
				break
		print("shot ", m)
		v.queue_free()
		await get_tree().process_frame
	get_tree().quit()
