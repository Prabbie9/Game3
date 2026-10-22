extends Node
## All car models in their CarLibrary frames, forward (-Z) facing the camera.
func _ready():
	get_tree().root.size = Vector2i(1600, 600)
	var env := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new(); e.background_mode = Environment.BG_SKY; e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_AGX; env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 20, 0); add_child(sun)
	var models := CarLibrary.MODELS.keys()
	for i in models.size():
		var d := CarLibrary.get_model(models[i])
		var root := Node3D.new(); root.position = Vector3((i % 5 - 2) * 3.2, 0, (i / 5) * 7.0); add_child(root)
		for p in d.parts:
			var mi := MeshInstance3D.new(); mi.mesh = p[0]; mi.transform = p[1]; root.add_child(mi)
		for w in d.wheels:
			for p in w.parts:
				var mi := MeshInstance3D.new(); mi.mesh = p[0]; mi.transform = Transform3D(Basis.IDENTITY, w.pos) * p[1]; root.add_child(mi)
		var l := Label3D.new(); l.text = models[i]; l.position = Vector3(0, 2.2, 0); l.font_size = 64; root.add_child(l)
	var cam := Camera3D.new(); add_child(cam); cam.look_at_from_position(Vector3(-2, 3.5, -1.5), Vector3(0, 0.5, 7)); cam.fov = 70; cam.make_current()
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(get_meta("args")[0])
	get_tree().quit()
