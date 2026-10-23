class_name Pickup
extends Area3D
## Something lying around to collect by walking over it: a weapon (with ammo), a health pack, body armour or
## a bundle of cash. It turns slowly above the ground with a soft halo, and comes back a while after it is taken.

enum Kind { WEAPON, HEALTH, ARMOR, CASH }

const RESPAWN := 150.0

var kind := Kind.WEAPON
var weapon_id := "pistol"
var amount := 0
var _visual: Node3D
var _t := 0.0
var _gone := -1.0
var _settled := false
var _base_y := 0.0

static var _halo_mat: StandardMaterial3D


static func make(k: Kind, id := "", amt := 0) -> Pickup:
	var p := Pickup.new()
	p.kind = k
	p.weapon_id = id
	p.amount = amt
	return p


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		Kind.WEAPON:
			var m: Node3D = WeaponModel.build("pistol")[0] if weapon_id == "pistol" \
					else (load("res://assets/models/weapons/%s.scn" % weapon_id) as PackedScene).instantiate()
			_visual.add_child(m)
			# centre long guns over the spot (their origin is the grip)
			var len := 0.0
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				len = maxf(len, absf((mi as MeshInstance3D).get_aabb().position.z))
			m.position.z = len * 0.35
			if weapon_id == "grenade":
				m.scale = Vector3.ONE * 2.0
		Kind.HEALTH:
			_visual.add_child(_box(Vector3(0.36, 0.26, 0.2), Color(0.95, 0.95, 0.93)))
			for s: Vector3 in [Vector3(0.2, 0.06, 0.21), Vector3(0.06, 0.2, 0.21)]:
				_visual.add_child(_box(s, Color(0.85, 0.1, 0.1)))
		Kind.ARMOR:
			var vest := _box(Vector3(0.42, 0.5, 0.12), Color(0.16, 0.22, 0.3))
			_visual.add_child(vest)
			var strap := _box(Vector3(0.44, 0.08, 0.14), Color(0.08, 0.09, 0.1))
			strap.position.y = -0.08
			_visual.add_child(strap)
		Kind.CASH:
			for i in 3:
				var bill := _box(Vector3(0.16, 0.035, 0.07), Color(0.36, 0.62, 0.36))
				bill.position = Vector3(randf_range(-0.03, 0.03), i * 0.036, randf_range(-0.03, 0.03))
				bill.rotation.y = randf_range(-0.3, 0.3)
				_visual.add_child(bill)
			_visual.scale = Vector3.ONE * 1.6
	# soft glow disc on the ground so pickups read from a distance
	if _halo_mat == null:
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.albedo_texture = Vehicle._soft_dot()
		_halo_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.55)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	q.orientation = PlaneMesh.FACE_Y
	halo.mesh = q
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position.y = -0.55
	halo.name = "Halo"
	add_child(halo)
	body_entered.connect(_on_body)
	_base_y = global_position.y


func _box(s: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	mi.material_override = m
	return mi


func _physics_process(delta: float) -> void:
	_t += delta
	var p := Game.player as Node3D
	if not _settled and p and p.global_position.distance_to(global_position) < 120.0:
		# sit on whatever is really below once the ground around here is loaded
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 3.0, 0), global_position + Vector3(0, -12.0, 0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			global_position.y = hit.position.y + 0.6
			_base_y = global_position.y
			_settled = true
	if _gone >= 0.0:
		_gone += delta
		if _gone > RESPAWN and (p == null or p.global_position.distance_to(global_position) > 30.0):
			_gone = -1.0
			visible = true
			set_deferred("monitoring", true)
		return
	_visual.rotation.y = _t * 1.4
	_visual.position.y = sin(_t * 2.0) * 0.06


func _on_body(b: Node) -> void:
	var pl := b as Player
	if pl == null or _gone >= 0.0 or pl.state == Player.State.DEAD:
		return
	var took := false
	var text := ""
	match kind:
		Kind.WEAPON:
			var had := pl.weapon.has(weapon_id)
			took = pl.weapon.give(weapon_id, amount if amount > 0 else -1)
			var nm := String(WeaponDefs.def_of(weapon_id).name).to_upper()
			text = ("Picked up %s" % nm) if not had else ("%s ammo" % nm)
			if took and not had and pl.weapon.is_melee() and not WeaponDefs.def_of(weapon_id).kind == "melee":
				pl.weapon.select(weapon_id)
		Kind.HEALTH:
			took = pl.health < 100.0
			if took:
				pl.heal(amount if amount > 0 else 50.0)
				text = "Health"
		Kind.ARMOR:
			took = pl.armor < 100.0
			if took:
				pl.add_armor(amount if amount > 0 else 100.0)
				text = "Body armour"
		Kind.CASH:
			took = true
			Game.money += amount
			text = "$%d" % amount
	if not took:
		return
	Game.message(text)
	Audio.play_at(Audio.stream("weapons/reload_pistol.ogg" if kind == Kind.WEAPON else "player/punch_0.ogg"), global_position, -6.0, 1.3 if kind != Kind.WEAPON else 1.0)
	_gone = 0.0
	visible = false
	set_deferred("monitoring", false)
	if kind == Kind.CASH:
		queue_free()
