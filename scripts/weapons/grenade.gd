class_name Grenade
extends RigidBody3D
## A thrown fragmentation grenade: bounces and rolls (clinks on impact) and explodes when its fuse runs out.

const FUSE := 3.0

var source: Node
var damage := 200.0
var _t := 0.0
var _last_clink := 0.0


func _ready() -> void:
	mass = 0.4
	collision_layer = 16
	collision_mask = 1 | 4 | 8 | 16
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	physics_material_override = pm
	angular_damp = 1.2
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.045
	cs.shape = sh
	add_child(cs)
	var model: Node3D = (load("res://assets/models/weapons/grenade.scn") as PackedScene).instantiate()
	add_child(model)
	body_entered.connect(_on_body)


func _on_body(_b: Node) -> void:
	if _t - _last_clink > 0.15 and linear_velocity.length() > 1.5:
		_last_clink = _t
		Audio.play_at(Audio.pick("weapons/bullet_metal_%d.ogg", 2), global_position, -16.0, randf_range(1.6, 1.9), &"SFX", 25.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= FUSE:
		set_physics_process(false)
		Explosion.blast(get_parent(), global_position + Vector3(0, 0.2, 0), 8.0, damage, source, self)
		queue_free()
