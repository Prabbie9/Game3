class_name AimPose
extends SkeletonModifier3D
## Upper-body aiming and weapon placement, run after the animation and before the left-hand IK:
## bends the spine so the aim follows the camera pitch, then places the held weapon on the right hand
## (grip mount) and the left-hand IK target on the weapon's support point, all from this frame's pose
## (a BoneAttachment would lag the hand by a frame and the support hand would swim).

const SPINE := ["Spine", "Chest", "UpperChest"]

## Camera pitch in radians (+ looks up) and how much of it the spine follows (0..1).
var pitch := 0.0
var weight := 0.0
## World-space axis to pitch around (the character's right).
var axis := Vector3.RIGHT
## Held weapon root and its transform relative to the RightHand bone.
var model: Node3D
var mount := Transform3D.IDENTITY
## Left-hand IK target (top-level) and its transform relative to the weapon root.
var support_target: Node3D
var support_local := Transform3D.IDENTITY
## Drive-by: the gun's transform in skeleton space (the arm IK has already brought the hand there) and its
## weight; the hand is turned to hold it.
var drive_xf := Transform3D.IDENTITY
var drive_w := 0.0

var _bones: Array[int] = []
var _hand := -1


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if not sk:
		return
	if _hand < 0:
		_hand = sk.find_bone("RightHand")
		for b in SPINE:
			var i := sk.find_bone(b)
			if i >= 0:
				_bones.append(i)
	var skx := sk.global_transform
	if weight > 0.001 and not _bones.is_empty():
		var a := pitch * weight / float(_bones.size())
		var ax := (skx.basis.inverse() * axis).normalized()
		for i in _bones:
			var g := sk.get_bone_global_pose(i)
			var parent := sk.get_bone_parent(i)
			var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
			var rot := Basis(ax, a) * g.basis
			sk.set_bone_pose_rotation(i, (pg.basis.inverse() * rot).get_rotation_quaternion())
	if drive_w > 0.001 and _hand >= 0:
		var want := (drive_xf * mount.affine_inverse()).basis.orthonormalized()
		var g := sk.get_bone_global_pose(_hand)
		var pg := sk.get_bone_global_pose(sk.get_bone_parent(_hand))
		var rot := g.basis.orthonormalized().get_rotation_quaternion().slerp(want.get_rotation_quaternion(), drive_w)
		sk.set_bone_pose_rotation(_hand, (pg.basis.orthonormalized().get_rotation_quaternion().inverse() * rot).normalized())
	if model and _hand >= 0:
		var hand := skx * sk.get_bone_global_pose(_hand)
		hand.basis = hand.basis.orthonormalized()
		model.global_transform = hand * mount
		if support_target:
			support_target.global_transform = model.global_transform * support_local
