class_name Ragdoll
extends RefCounted
## Builds a PhysicalBoneSimulator3D ragdoll on a humanoid (SkeletonProfileHumanoid bone names) and handles
## going limp and blending back into a get-up animation.

## bone -> [child bone used for length (or "" = fixed length), radius, mass, joint]
const BONES := {
	"Hips": ["Spine", 0.14, 11.0, "cone"],
	"Chest": ["Neck", 0.15, 14.0, "cone"],
	"Head": ["", 0.11, 5.0, "cone"],
	"LeftUpperArm": ["LeftLowerArm", 0.055, 2.5, "cone"],
	"LeftLowerArm": ["LeftHand", 0.045, 1.6, "hinge"],
	"RightUpperArm": ["RightLowerArm", 0.055, 2.5, "cone"],
	"RightLowerArm": ["RightHand", 0.045, 1.6, "hinge"],
	"LeftUpperLeg": ["LeftLowerLeg", 0.075, 8.0, "cone"],
	"LeftLowerLeg": ["LeftFoot", 0.06, 4.0, "hinge"],
	"RightUpperLeg": ["RightLowerLeg", 0.075, 8.0, "cone"],
	"RightLowerLeg": ["RightFoot", 0.06, 4.0, "hinge"],
}

var sim: PhysicalBoneSimulator3D
var skeleton: Skeleton3D
var active := false
var _hips: PhysicalBone3D


func _init(sk: Skeleton3D, collision_layer := 4, collision_mask := 1 | 8 | 16) -> void:
	skeleton = sk
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	sk.add_child(sim)
	sim.active = false
	for bone_name: String in BONES:
		var cfg: Array = BONES[bone_name]
		var bi := sk.find_bone(bone_name)
		if bi < 0:
			continue
		var length := 0.22
		if cfg[0] != "":
			var ci := sk.find_bone(cfg[0])
			if ci >= 0:
				length = sk.get_bone_global_rest(bi).origin.distance_to(sk.get_bone_global_rest(ci).origin)
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bone_name
		pb.bone_name = bone_name
		pb.mass = cfg[2]
		pb.friction = 0.8
		pb.linear_damp = 0.15
		pb.angular_damp = 1.5
		pb.collision_layer = collision_layer
		pb.collision_mask = collision_mask
		pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, -length * 0.5, 0))
		pb.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0, length * 0.5, 0))
		match cfg[3]:
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				pb.set("joint_constraints/angular_limit_enabled", true)
				pb.set("joint_constraints/angular_limit_upper", 0.0)
				pb.set("joint_constraints/angular_limit_lower", -140.0)
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set("joint_constraints/swing_span", 50.0)
				pb.set("joint_constraints/twist_span", 35.0)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = cfg[1]
		cap.height = maxf(length + cfg[1] * 0.6, cfg[1] * 2.2)
		cs.shape = cap
		pb.add_child(cs)
		sim.add_child(pb)
		if bone_name == "Hips":
			_hips = pb


## Go limp, inheriting the current motion (plus an optional impulse at the hips).
func start(velocity: Vector3, impulse := Vector3.ZERO) -> void:
	active = true
	sim.active = true
	sim.influence = 1.0
	sim.physical_bones_start_simulation()
	for pb in sim.get_children():
		if pb is PhysicalBone3D:
			(pb as PhysicalBone3D).linear_velocity = velocity
	if impulse != Vector3.ZERO and _hips:
		_hips.apply_central_impulse(impulse)


func stop() -> void:
	active = false
	sim.physical_bones_stop_simulation()
	sim.active = false


## World transform of the ragdoll's pelvis.
func hips_transform() -> Transform3D:
	return _hips.global_transform if _hips else skeleton.global_transform


## Speed of the pelvis (to decide when the body has come to rest).
func hips_speed() -> float:
	return _hips.linear_velocity.length() if _hips else 0.0


## True if the body lies face down (chest facing the ground).
func face_down() -> bool:
	# Mixamo +Z is the front of the body; the model is rotated 180° so front = -Z of the visual
	var front := -(hips_transform().basis.z)
	return front.y < 0.0
