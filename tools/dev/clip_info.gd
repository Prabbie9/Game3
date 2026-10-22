extends Node
## Prints length, hips displacement (start->end), hips height range and yaw change for clips. args: snake names
func _ready():
	for f in get_meta("args"):
		var src: AnimationLibrary = load("res://assets/source/mixamo/animations/%s.fbx" % f)
		if src == null: print(f, " MISSING"); continue
		var a := src.get_animation(src.get_animation_list()[0])
		var t := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		var r := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_ROTATION_3D)
		var n := a.track_get_key_count(t)
		var p0: Vector3 = a.track_get_key_value(t, 0); var p1: Vector3 = a.track_get_key_value(t, n - 1)
		var ymin := 9.0; var ymax := -9.0
		for i in n:
			var y: float = (a.track_get_key_value(t, i) as Vector3).y; ymin = minf(ymin, y); ymax = maxf(ymax, y)
		var yaw := 0.0
		if r >= 0:
			var q0: Quaternion = a.track_get_key_value(r, 0); var q1: Quaternion = a.track_get_key_value(r, a.track_get_key_count(r) - 1)
			var fv := Basis(q1 * q0.inverse()) * Vector3(0, 0, 1); yaw = rad_to_deg(atan2(fv.x, fv.z))
		print("%-48s len %.2f  disp %s  y %.2f..%.2f (start %.2f end %.2f)  yaw %.0f" % [f, a.length, (p1 - p0).snapped(Vector3.ONE * 0.01), ymin, ymax, p0.y, p1.y, yaw])
	get_tree().quit()
