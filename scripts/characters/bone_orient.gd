class_name BoneOrient
extends SkeletonModifier3D
## Turns one bone to a target node's orientation (after an IK solver has placed it): TwoBoneIK3D only
## reaches positions, so a support hand would otherwise keep its animated wrist angle on the fore-end.

var bone_name := "LeftHand"
var target: Node3D
## Follows the IK solver's influence so hand and arm blend in and out together.
var ik: SkeletonModifier3D

var _bone := -1


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if not sk or not target:
		return
	var w := ik.influence if ik else influence
	if w <= 0.001:
		return
	if _bone < 0:
		_bone = sk.find_bone(bone_name)
		if _bone < 0:
			return
	var want := (sk.global_transform.basis.inverse() * target.global_basis).orthonormalized().get_rotation_quaternion()
	var g := sk.get_bone_global_pose(_bone).basis.orthonormalized().get_rotation_quaternion()
	var pg := sk.get_bone_global_pose(sk.get_bone_parent(_bone)).basis.orthonormalized().get_rotation_quaternion()
	sk.set_bone_pose_rotation(_bone, (pg.inverse() * g.slerp(want, w)).normalized())
