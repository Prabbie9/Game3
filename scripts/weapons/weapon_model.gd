class_name WeaponModel
extends RefCounted
## Loads a weapon glTF, keeps only the wanted parts, and re-bases it so the origin is the grip
## (where the palm closes) with the barrel along -Z and the slide/top along +Y.

## kind -> config: path, nodes to drop (name contains), grip offset from the rear-bottom corner
const MODELS := {
	"pistol": {"path": "res://assets/models/sketchfab/pistol/scene.gltf", "drop": [".001", "magazine_empty"],
		"grip": Vector3(0.0, 0.05, 0.045)},
}


## Returns [root Node3D (origin at grip), muzzle position in root space]
static func build(kind: String) -> Array:
	var cfg: Dictionary = MODELS[kind]
	var scene: Node3D = (load(cfg.path) as PackedScene).instantiate()
	for n in scene.find_children("*", "", true, false):
		if not is_instance_valid(n):
			continue
		for d in cfg.drop:
			if String(n.name).contains(d):
				n.get_parent().remove_child(n)
				n.free()
				break
	var aabb := _aabb(scene, Transform3D.IDENTITY)
	var grip_off: Vector3 = cfg.grip
	# rear-bottom of the frame (+Z is the rear, -Z the muzzle)
	var grip := Vector3(aabb.get_center().x, aabb.position.y + grip_off.y, aabb.end.z - grip_off.z)
	var muzzle := Vector3(aabb.get_center().x, aabb.end.y - 0.018, aabb.position.z)
	var root := Node3D.new()
	root.add_child(scene)
	scene.position = -grip
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return [root, muzzle - grip]


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is VisualInstance3D:
		out = t * (n as VisualInstance3D).get_aabb()
		first = false
	for ch in n.get_children():
		var b := _aabb(ch, t)
		if b.size != Vector3.ZERO:
			out = b if first else out.merge(b)
			first = false
	return out
