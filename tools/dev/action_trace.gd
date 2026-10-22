extends Node
## Traces an action's root path and key bones (relative to the action start, metres, +Z = forward).
## args: ACTION
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var a: Array = get_meta("args")
	var act: String = a[0]
	var body := Node3D.new(); add_child(body)
	var v := HumanoidVisual.new(); body.add_child(v)
	for i in 5: await get_tree().process_frame
	v.jump_to(act)
	var len := v.action_duration(act)
	print("%s len %.2f ledge %.2f" % [act, len, v.path_ledge(act)])
	var t := 0.0
	var next := 0.0
	while t <= len:
		body.transform = v.path_transform(act, t)
		await get_tree().process_frame
		t += get_process_delta_time()
		if t >= next:
			next += 0.08
			var s := "t %.2f root(f %.2f y %.2f yaw %.0f)" % [t, -body.position.z, body.position.y, rad_to_deg(body.rotation.y)]
			for b in ["Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				var p: Vector3 = v.bone_global(b).origin
				s += "  %s(f %.2f y %.2f)" % [b.substr(0, 5), -p.z, p.y]
			print(s)
	get_tree().quit()
