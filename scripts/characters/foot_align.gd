class_name FootAlign
extends SkeletonModifier3D
## Ground adaptation, step 3 of 3 (after the leg solver): tilts each foot to match the ground slope.

const FEET := ["LeftFoot", "RightFoot"]
const MAX_TILT := deg_to_rad(28.0)

var foot_ik: FootIK
var _feet := [-1, -1]


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if not sk or not foot_ik or foot_ik._w <= 0.001:
		return
	if _feet[0] < 0:
		for i in 2:
			_feet[i] = sk.find_bone(FEET[i])
	var skx := sk.global_transform
	var inv := skx.affine_inverse()
	for i in 2:
		var n: Vector3 = foot_ik.ground_normals[i]
		var ang := Vector3.UP.angle_to(n)
		if ang < 0.01:
			continue
		var axis := Vector3.UP.cross(n).normalized()
		var tilt := Basis(axis, minf(ang, MAX_TILT) * foot_ik._w)
		var g := skx * sk.get_bone_global_pose(_feet[i])
		g.basis = tilt * g.basis
		sk.set_bone_global_pose(_feet[i], inv * g)
