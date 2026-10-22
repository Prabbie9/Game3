extends Node
func _ready():
	var v := HumanoidVisual.new()
	add_child(v)
	await get_tree().process_frame
	v.set_locomotion(v.run_speed)
	for i in 20:
		await get_tree().process_frame
		if i % 5 == 0:
			var sk := v.skeleton
			var b := sk.find_bone("LeftUpperLeg")
			print("state=", v.current_state(), " active=", v.tree.active, " pose_rot=", sk.get_bone_pose_rotation(b), " toes_y=", v.bone_global("LeftToes").origin.y, " hips=", sk.get_bone_pose_position(sk.find_bone("Hips")))
	print("tree root_node=", v.tree.root_node, " anim_player=", v.tree.anim_player, " has GeneralSkeleton unique: ", v.model.get_node_or_null("%GeneralSkeleton"))
	print("walk/run/sprint speeds ", v.walk_speed, " ", v.run_speed, " ", v.sprint_speed)
	get_tree().quit()
