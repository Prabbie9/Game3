class_name GlassPane
extends StaticBody3D
## A window pane (shop fronts, the diner, the safehouse, the gun shop) that shatters when it is shot, punched,
## rammed by a car or caught in a blast: the glass drops out in a shower of shards with the sound of breaking
## glass. It is glazed again a few minutes later, once the player has moved off.

const REGLAZE := 180.0
const REGLAZE_DIST := 45.0

var size := Vector3.ONE
var broken := false
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _since := 0.0
static var _shard_mat: StandardMaterial3D
static var _shard_mesh: QuadMesh


## A pane of `size` centred at `center` (in `parent`'s space), drawn with `mat`.
static func make(parent: Node3D, center: Vector3, pane_size: Vector3, mat: Material) -> GlassPane:
	var g := GlassPane.new()
	g.size = pane_size
	g.position = center
	g._mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = pane_size
	g._mesh.mesh = bm
	g._mesh.material_override = mat
	g._mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(g._mesh)
	g._shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = pane_size
	g._shape.shape = bs
	g.add_child(g._shape)
	parent.add_child(g)
	return g


func _ready() -> void:
	collision_layer = 1 | 16     # world (blocks), props (cars ploughing ahead and blasts find it)
	collision_mask = 0
	set_meta("surface", FX.Surface.GLASS)
	add_to_group("glass_panes")
	set_process(false)


func bullet_hit(pos: Vector3, dir: Vector3, _amount: float, _from: Node = null, _zone := "") -> void:
	shatter(pos, dir)


func melee_hit(_dmg: float, _from: Node, dir: Vector3) -> void:
	shatter(global_position, dir)


func blast_hit(at: Vector3, _damage: float, _source: Node = null) -> void:
	shatter(global_position, (global_position - at).normalized())


## Breaks the pane: shards fly out along `dir` (the way the hit was going) and fall.
func shatter(at: Vector3, dir: Vector3) -> void:
	if broken:
		return
	broken = true
	_mesh.visible = false
	_shape.set_deferred("disabled", true)
	_since = 0.0
	set_process(true)
	_shards(dir)
	Audio.play_at(Audio.pick("world/window_%d.ogg", 2), at, 0.0, randf_range(0.92, 1.08), &"SFX", 70.0)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_inside_tree():
			Audio.play_at(Audio.stream("world/glass_fall.ogg"), global_position - Vector3(0, size.y * 0.5, 0), -6.0, randf_range(0.9, 1.1)))
	Game.noise(at, 20.0, Game.player)


func _shards(dir: Vector3) -> void:
	if _shard_mat == null:
		_shard_mat = StandardMaterial3D.new()
		_shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shard_mat.albedo_color = Color(0.82, 0.9, 0.94, 0.55)
		_shard_mat.metallic = 0.6
		_shard_mat.roughness = 0.05
		_shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shard_mesh = QuadMesh.new()
		_shard_mesh.size = Vector2(0.09, 0.07)
		_shard_mesh.material = _shard_mat
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = clampi(int(size.x * size.y * 22.0), 16, 90)
	p.lifetime = 1.4
	p.mesh = _shard_mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size.x, size.y, size.z) * 0.5
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	p.direction = global_basis.inverse() * d
	p.spread = 40.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 3.2
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.particle_flag_align_y = false
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _process(delta: float) -> void:
	_since += delta
	if _since < REGLAZE:
		return
	var pl := Game.player as Node3D
	if pl and pl.global_position.distance_to(global_position) < REGLAZE_DIST:
		return
	broken = false
	_mesh.visible = true
	_shape.set_deferred("disabled", false)
	set_process(false)
