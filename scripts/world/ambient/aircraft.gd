class_name Aircraft
extends Node3D
## Now and then an airliner crosses the sky high over the island (a simple procedural jet with navigation lights
## and a tail strobe), its engines rumbling as it passes over.

const ALT := Vector2(650.0, 900.0)
const SPEED := 95.0
const GAP := Vector2(150.0, 300.0)   # seconds between flights

var _plane: Node3D
var _snd: AudioStreamPlayer3D
var _strobe: MeshInstance3D
var _dir := Vector3.FORWARD
var _t := 0.0
var _wait := 40.0
var _flying := false
var _sounded := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_plane = _build()
	_plane.visible = false
	add_child(_plane)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = Audio.stream("ambience/plane.ogg")
	_snd.bus = &"Ambience"
	_snd.unit_size = 260.0
	_snd.max_distance = 4000.0
	_snd.attenuation_filter_cutoff_hz = 20500.0
	_snd.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_plane.add_child(_snd)


func _build() -> Node3D:
	var root := Node3D.new()
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.93, 0.95)
	white.metallic = 0.3
	white.roughness = 0.35
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.58, 0.62)
	grey.metallic = 0.6
	grey.roughness = 0.4
	var tailc := StandardMaterial3D.new()
	tailc.albedo_color = Color(0.12, 0.35, 0.55)
	var part := func(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation = rot
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.ignore_occlusion_culling = true   # high in open sky: the street occluders wrongly hide it
		root.add_child(mi)
		return mi
	# fuselage along -Z (nose forward)
	var body := CapsuleMesh.new()
	body.radius = 2.0
	body.height = 38.0
	part.call(body, white, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	# swept wings, tailplane and fin
	for sx in [-1.0, 1.0]:
		var wing := BoxMesh.new()
		wing.size = Vector3(16.0, 0.4, 4.5)
		part.call(wing, grey, Vector3(sx * 9.0, -0.8, 1.5 + 2.5), Vector3(0, sx * deg_to_rad(28.0), 0))
		var eng := CylinderMesh.new()
		eng.top_radius = 0.9
		eng.bottom_radius = 0.8
		eng.height = 4.0
		part.call(eng, grey, Vector3(sx * 6.0, -1.9, 0.5), Vector3(PI * 0.5, 0, 0))
		var stab := BoxMesh.new()
		stab.size = Vector3(6.5, 0.25, 2.5)
		part.call(stab, grey, Vector3(sx * 3.6, 0.4, 17.0), Vector3(0, sx * deg_to_rad(30.0), 0))
	var fin := BoxMesh.new()
	fin.size = Vector3(0.3, 6.0, 4.0)
	part.call(fin, tailc, Vector3(0, 3.6, 16.8), Vector3(deg_to_rad(-30.0), 0, 0))
	# navigation lights: red on the left wing tip, green on the right, a white strobe on the tail
	for nav: Array in [[Vector3(-16.0, -0.8, 8.5), Color(1.0, 0.1, 0.05)], [Vector3(16.0, -0.8, 8.5), Color(0.1, 1.0, 0.3)], [Vector3(0, 6.5, 18.6), Color(1, 1, 1)]]:
		var s := SphereMesh.new()
		s.radius = 0.9
		s.height = 1.8
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = nav[1]
		m.emission_enabled = true
		m.emission = nav[1]
		m.emission_energy_multiplier = 6.0
		var mi: MeshInstance3D = part.call(s, m, nav[0])
		if nav[1] == Color(1, 1, 1):
			_strobe = mi
	return root


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not _flying:
		_wait -= delta
		if _wait > 0.0:
			return
		# a straight track across the sky passing within a few hundred metres of the listener
		var eye := cam.global_position
		var heading := _rng.randf() * TAU
		_dir = Vector3(sin(heading), 0, cos(heading))
		var side := _dir.cross(Vector3.UP) * _rng.randf_range(-450.0, 450.0)
		var start := eye + side - _dir * 3200.0
		start.y = _rng.randf_range(ALT.x, ALT.y)
		_plane.global_position = start
		_plane.look_at(start + _dir, Vector3.UP)
		_plane.visible = true
		_flying = true
		_sounded = false
		_t = 0.0
		return
	_t += delta
	_plane.global_position += _dir * SPEED * delta
	# the recording swells to its peak about 16 s in: start it so the peak meets the closest pass
	var eye2 := cam.global_position
	var to := eye2 - _plane.global_position
	var ahead := to.dot(_dir)
	if not _sounded and ahead < SPEED * 16.0 and ahead > 0.0:
		_sounded = true
		_snd.play()
	if _strobe:
		_strobe.visible = fmod(_t, 1.2) < 0.08
	if ahead < -3200.0:
		_flying = false
		_plane.visible = false
		_wait = _rng.randf_range(GAP.x, GAP.y)


## Starts a flight now (tests and screenshots).
func launch() -> void:
	_flying = false
	_wait = 0.0
