class_name Rocket
extends Node3D
## A launcher rocket: flies straight (a slight wobble), trails smoke, explodes on the first thing it touches
## or after its range. Moved by a ray each physics step so it never tunnels through thin walls.

const SPEED := 55.0
const LIFE := 6.0

var source: Node
var damage := 260.0
var _dir := Vector3.FORWARD
var _t := 0.0
var _trail: GPUParticles3D
var _done := false


func launch(from: Vector3, dir: Vector3) -> void:
	global_position = from
	_dir = dir.normalized()
	look_at(from + _dir, Vector3.UP if absf(_dir.y) < 0.99 else Vector3.RIGHT)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.045
	cm.height = 0.5
	body.mesh = cm
	body.rotation.x = PI * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.27, 0.22)
	m.roughness = 0.6
	body.material_override = m
	add_child(body)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.65, 0.3)
	glow.light_energy = 2.5
	glow.omni_range = 5.0
	glow.position = Vector3(0, 0, 0.35)
	add_child(glow)
	_trail = GPUParticles3D.new()
	_trail.amount = 80
	_trail.lifetime = 1.4
	_trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.5, 0.9))
	g.add_point(0.08, Color(0.75, 0.72, 0.68, 0.55))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.6, 0.6, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_trail.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = VehicleDamage._billboard(false)
	_trail.draw_pass_1 = q
	_trail.position = Vector3(0, 0, 0.3)
	_trail.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	add_child(_trail)
	_trail.emitting = true
	var snd := AudioStreamPlayer3D.new()
	snd.stream = Audio.stream("vehicles/fire_loop.ogg", true)
	snd.bus = &"SFX"
	snd.volume_db = -2.0
	snd.pitch_scale = 1.8
	snd.unit_size = 6.0
	add_child(snd)
	snd.play()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var from := global_position
	var to := from + _dir * SPEED * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, Weapon.SHOT_MASK | 2)
	if source is CollisionObject3D and _t < 0.3:
		q.exclude = [(source as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_explode(hit.position + (hit.normal as Vector3) * 0.2)
		return
	global_position = to
	if _t > LIFE:
		_explode(global_position)


func _explode(at: Vector3) -> void:
	_done = true
	Explosion.blast(get_parent(), at, 8.0, damage, source)
	# the smoke trail hangs in the air a moment after the rocket is gone
	for c in get_children():
		if c != _trail:
			c.queue_free()
	_trail.emitting = false
	var tw := create_tween()
	tw.tween_interval(_trail.lifetime + 0.2)
	tw.tween_callback(queue_free)
