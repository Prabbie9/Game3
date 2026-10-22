extends Node
func _ready():
	for f in ["male_standard_walk", "running_fast", "running_forward", "slow_run_forward", "jump_up", "jumping_while_running", "mid_air_falling_idle", "landing_from_falling_idle", "shooting_handgun", "entering_into_the_driverside_of_a_car", "exiting_out_of_the_driverside_of_a_car", "male_driving_a_car"]:
		var src: AnimationLibrary = load("res://assets/source/mixamo/animations/%s.fbx" % f)
		print(f, " list=", src.get_animation_list())
		for an in src.get_animation_list():
			var a := src.get_animation(an)
			var t := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
			print("  ", an, " len=", a.length, " hips_pos_track=", t, " keys=", a.track_get_key_count(t) if t >= 0 else -1, " first=", a.track_get_key_value(t, 0) if t >= 0 else null, " last=", a.track_get_key_value(t, a.track_get_key_count(t)-1) if t >= 0 else null)
	get_tree().quit()
