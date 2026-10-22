extends SceneTree
# Usage: godot --headless --path . -s tools/dev/inspect_scene.gd -- res://path.fbx
func _init():
	var path: String = OS.get_cmdline_user_args()[0]
	var s = load(path)
	var root: Node = s.instantiate()
	_dump(root, 0)
	quit()

func _dump(n: Node, d: int):
	var info := ""
	if n is Skeleton3D:
		var sk: Skeleton3D = n
		var names := []
		for i in sk.get_bone_count(): names.append(sk.get_bone_name(i))
		info = " bones=%d motion_scale=%.3f [%s]" % [sk.get_bone_count(), sk.motion_scale, ", ".join(names.slice(0, 70))]
	elif n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var aabb := mi.get_aabb()
		var mats := []
		for i in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(i)
			mats.append(str(m.resource_name if m else "null") + ("(tex)" if m is BaseMaterial3D and m.albedo_texture else ""))
		info = " surfaces=%d verts~%d aabb=%s mats=%s" % [mi.mesh.get_surface_count(), mi.mesh.surface_get_array_len(0), aabb, mats]
	elif n is AnimationPlayer:
		info = " anims=%s" % [n.get_animation_list()]
	elif n is Node3D:
		info = " xf=%s" % [n.transform]
	print("  ".repeat(d), n.name, " <", n.get_class(), ">", info)
	for c in n.get_children(): _dump(c, d + 1)
