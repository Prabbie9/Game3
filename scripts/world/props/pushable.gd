class_name Pushable
extends RigidBody3D
## One loose object from Pushables: knocks about with a sound to match, takes kicks and bullets in proportion to
## its weight (a football flies, a crate barely shifts).

var kind := ""
var sound := ""
var _quiet_until := 0


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_contact)


func _on_contact(_other: Node) -> void:
	var now := Time.get_ticks_msec()
	if now < _quiet_until:
		return
	var v := linear_velocity.length()
	if v < 1.4:
		return
	_quiet_until = now + 250
	Audio.play_at(Audio.pick(sound, 2), global_position, clampf(-14.0 + v * 2.0, -14.0, 0.0), randf_range(0.9, 1.12), &"SFX", 40.0)


func bullet_hit(pos: Vector3, dir: Vector3, amount: float, _from: Node = null, _zone := "") -> void:
	sleeping = false
	apply_impulse(dir * minf(amount * 0.2, mass * 10.0), pos - global_position)


func melee_hit(_dmg: float, _from: Node, dir: Vector3) -> void:
	sleeping = false
	apply_central_impulse(dir * minf(80.0, mass * 12.0) + Vector3.UP * minf(15.0, mass * 4.0))
	Audio.play_at(Audio.pick(sound, 2), global_position, -4.0, randf_range(0.9, 1.1))
