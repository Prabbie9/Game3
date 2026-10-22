extends Node
## Close-up render of the right hand holding the pistol in the aim pose (grip tuning).
## args: OUT.png rx ry rz ox oy oz  (degrees / metres)
func _ready() -> void:
	var a: Array = get_meta("args")
	get_tree().root.size = Vector2i(960, 540)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.4, 0.45, 0.5); e.ambient_light_color = Color(0.6, 0.6, 0.6); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); add_child(sun)
	var v := HumanoidVisual.new(); add_child(v)
	await get_tree().process_frame
	v.set_aim(Vector2.ZERO, 1.0)
	var att := BoneAttachment3D.new(); att.bone_name = "RightHand"; v.skeleton.add_child(att)
	var built := WeaponModel.build("pistol"); var gun: Node3D = built[0]; att.add_child(gun)
	if a.size() >= 4:
		# args: OUT.png ox oy oz [roll_deg]  (basis = WeaponMounts.PISTOL_GRIP basis, rolled about the barrel)
		var b := WeaponMounts.PISTOL_GRIP.basis
		if a.size() >= 5:
			b = b * Basis(Vector3(0, 0, 1), deg_to_rad(float(a[4])))
		gun.transform = Transform3D(b, Vector3(float(a[1]), float(a[2]), float(a[3])))
	else:
		gun.transform = WeaponMounts.PISTOL_GRIP
	for i in 30: await get_tree().process_frame
	var hand := v.bone_global("RightHand").origin
	var cams := [Vector3(0.0, 0.25, -1.0), Vector3(1.0, 0.3, 0.0)]
	var imgs := []
	for cpos in cams:
		var c := Camera3D.new(); add_child(c); c.fov = 30
		c.look_at_from_position(hand + cpos * 0.9, hand + Vector3(0, -0.05, 0)); c.make_current()
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		imgs.append(get_tree().root.get_texture().get_image()); c.queue_free()
	var out := Image.create(960 * 2, 540, false, imgs[0].get_format())
	out.blit_rect(imgs[0], Rect2i(0, 0, 960, 540), Vector2i(0, 0)); out.blit_rect(imgs[1], Rect2i(0, 0, 960, 540), Vector2i(960, 0))
	out.save_png(a[0]); get_tree().quit()
