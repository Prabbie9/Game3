extends Node
## Each car alone, camera front-left (car forward = -Z should face the camera). Saves a 5x2 contact sheet.
func _ready():
	get_tree().root.size = Vector2i(480, 300)
	var env := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new(); e.background_mode = Environment.BG_SKY; e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_AGX; env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 160, 0); add_child(sun)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 50
	cam.look_at_from_position(Vector3(-3.5, 1.8, -6.5), Vector3(0, 0.6, 0)); cam.make_current()
	var models := CarLibrary.MODELS.keys()
	var sheet := Image.create(480 * 5, 300 * 2, false, Image.FORMAT_RGBA8)
	for i in models.size():
		var d := CarLibrary.get_model(models[i])
		var root := Node3D.new(); add_child(root)
		for p in d.parts:
			var mi := MeshInstance3D.new(); mi.mesh = p[0]; mi.transform = p[1]; root.add_child(mi)
		var l := Label3D.new(); l.text = models[i]; l.position = Vector3(0, 2.0, 0); l.font_size = 48; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; root.add_child(l)
		for k in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_tree().root.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, 480, 300), Vector2i((i % 5) * 480, (i / 5) * 300))
		root.free()
	sheet.save_png(get_meta("args")[0])
	get_tree().quit()
