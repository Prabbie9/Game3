extends Node
func _ready():
	for f in get_meta("args"):
		var src: AnimationLibrary = load("res://assets/source/mixamo/animations/%s.fbx" % f)
		var a := src.get_animation(src.get_animation_list()[0])
		var t := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		var out := []
		for i in range(0, a.track_get_key_count(t), 3):
			out.append("%.2f:%.2f" % [a.track_get_key_time(t, i), (a.track_get_key_value(t, i) as Vector3).y])
		print(f, " ", " ".join(out))
	get_tree().quit()
