class_name FootIK
extends SkeletonModifier3D
## Ground adaptation, step 1 of 3 (runs before the TwoBoneIK3D leg solver):
## reads the animated pose, raycasts the ground under each ankle, lowers the pelvis so the lower foot can
## reach its ground, and places the leg IK targets/poles. FootAlign (after the solver) tilts the feet.

const FEET := ["LeftFoot", "RightFoot"]
const KNEES := ["LeftLowerLeg", "RightLowerLeg"]
const MAX_DROP := 0.45
const MAX_RAISE := 0.35

## A foot came down on the ground (footstep sounds): foot 0 left / 1 right, ground point, what it stands on.
signal stepped(foot: int, pos: Vector3, collider: Object)

## 0..1, driven by the owner (0 in the air, in vehicles, ragdolled).
var weight := 1.0
var body: Node3D
var targets: Array[Node3D] = []
var poles: Array[Node3D] = []
var ik: TwoBoneIK3D
var ground_normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
## Riding: world transforms the feet must reach (footpegs, pedals) instead of the ground; empty = normal.
var override: Array = []
var override_pole_dir := Vector3.ZERO
var ray_mask := 1 | 8 | 16

var _w := 0.0
var _pelvis := 0.0
var _offsets := [0.0, 0.0]
var _feet := [-1, -1]
var _knees := [-1, -1]
var _hips := -1
var _rest := [0.1, 0.1]      # lowest animated ankle height seen recently (planted)
var _raised := [false, false]


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if not sk or not body:
		return
	if _hips < 0:
		_hips = sk.find_bone("Hips")
		for i in 2:
			_feet[i] = sk.find_bone(FEET[i])
			_knees[i] = sk.find_bone(KNEES[i])
	_w = move_toward(_w, weight, delta * 6.0)
	ik.influence = _w
	if override.size() == 2:
		_pelvis = 0.0
		for i in 2:
			targets[i].global_transform = override[i]
			var knee := (sk.global_transform * sk.get_bone_global_pose(_knees[i])).origin
			var side := body.global_basis.x * (-1.0 if i == 0 else 1.0)
			poles[i].global_position = knee + override_pole_dir * 0.6 + side * 0.25
			ground_normals[i] = Vector3.UP
		return
	if _w <= 0.001:
		_pelvis = 0.0
		return
	var skx := sk.global_transform
	var root_y := body.global_position.y
	var space := sk.get_world_3d().direct_space_state
	var lowest := 0.0
	var anim: Array[Transform3D] = []
	for i in 2:
		var gp := skx * sk.get_bone_global_pose(_feet[i])
		anim.append(gp)
		var q := PhysicsRayQueryParameters3D.create(gp.origin + Vector3(0, 0.6, 0), gp.origin - Vector3(0, 0.75, 0), ray_mask)
		var hit := space.intersect_ray(q)
		var off := 0.0
		var n := Vector3.UP
		if hit:
			off = clampf(hit.position.y - root_y, -MAX_DROP, MAX_RAISE)
			n = hit.normal
		_offsets[i] = lerpf(_offsets[i], off, 1.0 - exp(-delta * 18.0))
		# footstep: the animated ankle drops back to its planted height after lifting
		var h := gp.origin.y - root_y
		_rest[i] = minf(_rest[i] + delta * 0.03, h)
		if h > _rest[i] + 0.06:
			_raised[i] = true
		elif _raised[i] and h < _rest[i] + 0.02 and hit and _w > 0.2:
			_raised[i] = false
			stepped.emit(i, hit.position, hit.collider)
		ground_normals[i] = ground_normals[i].slerp(n, 1.0 - exp(-delta * 12.0))
		lowest = minf(lowest, _offsets[i])
	# lower the pelvis so the foot on lower ground can reach without hyper-extending
	_pelvis = lerpf(_pelvis, lowest * _w, 1.0 - exp(-delta * 12.0))
	var hp := sk.get_bone_pose_position(_hips)
	sk.set_bone_pose_position(_hips, hp + skx.basis.inverse() * Vector3(0, _pelvis, 0))
	var fwd := -body.global_basis.z
	for i in 2:
		var t := anim[i]
		targets[i].global_transform = Transform3D(t.basis, t.origin + Vector3(0, _offsets[i], 0))
		var knee := (skx * sk.get_bone_global_pose(_knees[i])).origin
		poles[i].global_position = knee + fwd * 0.6 + Vector3(0, _pelvis, 0)


## Builds the full foot-IK stack under a skeleton: FootIK -> TwoBoneIK3D (legs) -> FootAlign.
static func install(sk: Skeleton3D, owner_body: Node3D) -> FootIK:
	var f := FootIK.new()
	f.name = "FootIK"
	f.body = owner_body
	sk.add_child(f)
	var ik := TwoBoneIK3D.new()
	ik.name = "LegIK"
	sk.add_child(ik)
	f.ik = ik
	ik.setting_count = 2
	var sides := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
	for i in 2:
		var tgt := Marker3D.new()
		tgt.name = "FootTarget%d" % i
		tgt.top_level = true
		f.add_child(tgt)
		var pole := Marker3D.new()
		pole.name = "KneePole%d" % i
		pole.top_level = true
		f.add_child(pole)
		f.targets.append(tgt)
		f.poles.append(pole)
		ik.set_root_bone_name(i, sides[i][0])
		ik.set_middle_bone_name(i, sides[i][1])
		ik.set_end_bone_name(i, sides[i][2])
		ik.set_target_node(i, ik.get_path_to(tgt))
		ik.set_pole_node(i, ik.get_path_to(pole))
	var align := FootAlign.new()
	align.name = "FootAlign"
	align.foot_ik = f
	sk.add_child(align)
	return f
