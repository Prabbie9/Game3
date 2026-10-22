extends Node
func _ready():
	var lib := AnimLib.get_library()
	print("anims: ", lib.get_animation_list())
	for k in AnimLib.velocity: print("vel ", k, " ", AnimLib.velocity[k], " len=", lib.get_animation(k).length)
	for k in AnimLib.displacement: print("disp ", k, " ", AnimLib.displacement[k], " yaw=", AnimLib.yaw_change.get(k))
	for n in ["walk", "sprint", "idle"]:
		var a := lib.get_animation(n)
		if a:
			var paths := []
			for i in mini(a.get_track_count(), 4): paths.append(str(a.track_get_path(i)) + ":" + str(a.track_get_type(i)))
			print(n, " tracks=", a.get_track_count(), " ", paths)
	get_tree().quit()
