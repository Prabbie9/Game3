extends Node
## Renders clips from the shared library in front/side/back views to check how a pose is authored.
## A red block marks the character's forward (-Z of the body). args: OUT.png TIME clip [clip...]
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var a: Array = get_meta("args")
	var out: String = a[0]
	var t := float(a[1])
	var clips: Array = a.slice(2)
	AnimLib.get_library()
	get_tree().root.size = Vector2i(360 * 3, 400 * clips.size())
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.62); e.tonemap_mode = Environment.TONE_MAPPER_AGX; env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); sun.shadow_enabled = true; add_child(sun)
	var img := Image.create(360 * 3, 400 * clips.size(), false, Image.FORMAT_RGBA8)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 45
	for ci in clips.size():
		var body := Node3D.new(); add_child(body)
		var v := HumanoidVisual.new(); body.add_child(v)
		var marker := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.15, 0.05, 0.5); marker.mesh = bm
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.9, 0.1, 0.1); marker.material_override = m
		body.add_child(marker); marker.position = Vector3(0, 0.02, -0.6)
		var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(6, 6); floor.mesh = pm; body.add_child(floor)
		await get_tree().process_frame
		v.tree.active = false
		v.anim_player.play(String(clips[ci]))
		v.anim_player.seek(t, true)
		v.anim_player.pause()
		for view in 3:
			var dir: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)][view]
			cam.look_at_from_position(dir * 3.4 + Vector3(0, 1.4, 0), Vector3(0, 0.85, 0))
			cam.make_current()
			get_tree().root.size = Vector2i(360, 400)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			img.blit_rect(shot, Rect2i(0, 0, 360, 400), Vector2i(360 * view, 400 * ci))
		body.queue_free()
		await get_tree().process_frame
	img.save_png(out)
	print("saved ", out, " (columns: front, right side, back)")
	get_tree().quit()
