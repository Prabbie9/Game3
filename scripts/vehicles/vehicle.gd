class_name Vehicle
extends VehicleBody3D
## Drivable car built from CarLibrary meshes. Arcade-but-weighty handling: speed-sensitive steering,
## handbrake drifts, downforce, low centre of mass. Every vehicle is enterable.

signal driver_changed(driver: Node)

## Handling per body type: mass (kg), engine force (N at the wheels in 1st), top speed (m/s), steering lock,
## tyre grip, suspension stiffness / travel, drive (rwd/fwd/awd), and the name shown on entry.
const SPECS := {
	"compact": {"mass": 1080, "force": 4700, "top": 44.0, "steer": 0.62, "grip": 2.6, "stiff": 40.0, "travel": 0.2, "drive": "fwd", "name": "Minnow"},
	"hatchback": {"mass": 1180, "force": 5100, "top": 47.0, "steer": 0.6, "grip": 2.65, "stiff": 42.0, "travel": 0.2, "drive": "fwd", "name": "Solano Hatch"},
	"sedan": {"mass": 1450, "force": 6300, "top": 52.0, "steer": 0.55, "grip": 2.6, "stiff": 42.0, "travel": 0.22, "drive": "rwd", "name": "Calder Sedan"},
	"wagon": {"mass": 1560, "force": 6100, "top": 49.0, "steer": 0.54, "grip": 2.55, "stiff": 40.0, "travel": 0.22, "drive": "rwd", "name": "Calder Estate"},
	"coupe": {"mass": 1340, "force": 7300, "top": 58.0, "steer": 0.56, "grip": 2.8, "stiff": 48.0, "travel": 0.18, "drive": "rwd", "name": "Vela Coupé"},
	"sport": {"mass": 1290, "force": 9200, "top": 69.0, "steer": 0.52, "grip": 3.05, "stiff": 58.0, "travel": 0.15, "drive": "rwd", "name": "Kestrel GT"},
	"suv": {"mass": 1980, "force": 7900, "top": 50.0, "steer": 0.52, "grip": 2.5, "stiff": 38.0, "travel": 0.28, "drive": "awd", "name": "Vireo Ranger"},
	"minivan": {"mass": 1860, "force": 6600, "top": 46.0, "steer": 0.52, "grip": 2.45, "stiff": 36.0, "travel": 0.24, "drive": "fwd", "name": "Ferro Family"},
	"pickup": {"mass": 1920, "force": 7800, "top": 50.0, "steer": 0.5, "grip": 2.5, "stiff": 40.0, "travel": 0.26, "drive": "rwd", "name": "Hauler 1500"},
	"offroad": {"mass": 1820, "force": 7600, "top": 48.0, "steer": 0.54, "grip": 2.7, "stiff": 32.0, "travel": 0.34, "drive": "awd", "name": "Mesa Trailhound"},
	"muscle": {"mass": 1560, "force": 9400, "top": 62.0, "steer": 0.52, "grip": 2.7, "stiff": 44.0, "travel": 0.2, "drive": "rwd", "name": "Phoenix 455"},
	"police": {"mass": 1720, "force": 8600, "top": 60.0, "steer": 0.53, "grip": 2.8, "stiff": 46.0, "travel": 0.2, "drive": "rwd", "name": "Fairheaven Interceptor", "siren": true},
	"van": {"mass": 1950, "force": 6500, "top": 44.0, "steer": 0.5, "grip": 2.45, "stiff": 38.0, "travel": 0.24, "drive": "rwd", "name": "Shvan Van"},
	"ambulance": {"mass": 2400, "force": 7600, "top": 46.0, "steer": 0.5, "grip": 2.45, "stiff": 40.0, "travel": 0.24, "drive": "rwd", "name": "Shvan Ambulance", "siren": true},
	"boxtruck": {"mass": 4300, "force": 11500, "top": 34.0, "steer": 0.48, "grip": 2.4, "stiff": 46.0, "travel": 0.25, "drive": "rwd", "name": "LCT 3000",
		"sound": "heavy", "seat_z": 1.15, "seat_y": 0.4},
	"bus": {"mass": 11500, "force": 27000, "top": 26.0, "steer": 0.5, "grip": 2.3, "stiff": 50.0, "travel": 0.22, "drive": "rwd", "name": "Town Bus",
		"sound": "heavy", "seat_z": 1.45, "seat_y": 0.33},
	"firetruck": {"mass": 13500, "force": 31000, "top": 30.0, "steer": 0.48, "grip": 2.35, "stiff": 50.0, "travel": 0.24, "drive": "rwd", "name": "Fire Engine",
		"sound": "heavy", "seat_z": 1.35, "seat_y": 0.37, "siren": true},
	"dirtbike": {"mass": 165, "force": 1350, "top": 42.0, "steer": 0.5, "grip": 2.9, "stiff": 30.0, "travel": 0.22, "drive": "rwd",
		"name": "Ridgeback 450", "seat_z": 1.0, "seat_y": 0.72},
	"bicycle": {"mass": 22, "force": 120, "top": 11.0, "steer": 0.55, "grip": 2.6, "stiff": 30.0, "travel": 0.08, "drive": "rwd",
		"name": "Seaside Cruiser", "seat_z": 0.9, "seat_y": 0.78, "sound": "none"},
	"heli": {"mass": 2600, "force": 0, "top": 60.0, "steer": 0.0, "grip": 1.0, "stiff": 40.0, "travel": 0.2, "drive": "rwd",
		"name": "Skywatch Police Helicopter", "seat_z": 3.1, "seat_y": 0.28},
	"speedboat": {"mass": 1800, "force": 0, "top": 24.0, "steer": 0.0, "grip": 1.0, "stiff": 40.0, "travel": 0.2, "drive": "rwd",
		"name": "Squalo Speedboat", "seat_z": 4.75, "seat_y": 0.52},
}
## Engine sound character per body (small engines rev higher); heavy vehicles use the diesel loops.
const ENGINE_PITCH := {"compact": 1.18, "hatchback": 1.12, "sedan": 0.96, "wagon": 0.94, "coupe": 1.05, "sport": 1.08,
	"suv": 0.86, "minivan": 0.92, "pickup": 0.8, "offroad": 0.84, "muscle": 0.8, "police": 0.86, "van": 0.85, "ambulance": 0.86,
	"boxtruck": 1.0, "bus": 0.92, "firetruck": 0.96, "speedboat": 0.74, "dirtbike": 1.35}
const GEARS := [0.2, 0.36, 0.53, 0.7, 0.86, 1.0]   # top speed fraction reached at the redline in each gear
const GEAR_PULL := [1.55, 1.25, 1.05, 0.9, 0.78, 0.68]
const IDLE_RPM := 850.0
const RED_RPM := 6800.0

@export var model := "sedan"
@export var display_name := "Calder Sedan"
## Body colour; transparent keeps the model's factory colour.
@export var paint := Color(0, 0, 0, 0)
@export var max_engine_force := 5200.0
@export var max_brake := 90.0
@export var top_speed := 52.0  # m/s (~187 km/h)
@export var max_steer := 0.55
@export var vehicle_mass := 1450.0

var driver: Node = null
var camera_distance := 6.5
var camera_height := 1.7
var input_enabled := false
var headlights_on := false
enum Blinker { OFF, LEFT, RIGHT, HAZARD }
var indicator := Blinker.OFF
var _blink := 0.0
var _turned := 0.0         # yaw turned since the indicator went on (auto-cancel after the turn)

var _throttle := 0.0
var _steer := 0.0
var _size := Vector3(1.9, 1.5, 4.5)
var _seat := Transform3D()
var _door := Vector3()
var _wheels: Array[VehicleWheel3D] = []
var _lights: Array[Light3D] = []
var _brake_mat: StandardMaterial3D
var rpm := IDLE_RPM
var gear := 1             # 1..6, -1 reverse
var braking_now := false
var reversing := false
var skidding := 0.0       # 0..1, how hard the tyres are sliding (audio/smoke)
var _front_light: ShaderMaterial
var _rear_light: ShaderMaterial
var _smoke: Array[GPUParticles3D] = []
var _last_mark := {}      # wheel -> last skid point
var _driven := 2.0
var _idle := false
var _beacons: Array[ShaderMaterial] = []
var siren_on := false
var _beacon_lights: Array[OmniLight3D] = []
var _beacon_phase := 0.0
var _horn_t := -1.0
var _idle_time := 0.0
var _put_to_sleep := false
var damage: VehicleDamage
var audio: VehicleAudio
var horn_on := false
var engine_dead := false
var _prev_vel := Vector3.ZERO
var _jolt := Vector3.ZERO     # velocity change accumulated over the ticks of one collision
var _jolt_ticks := 0
var _last_strength := 0.0
var _last_jolt := Vector3.ZERO
var _lit_was := false


func _ready() -> void:
	add_to_group("vehicles")
	var spec: Dictionary = SPECS.get(model, SPECS.sedan)
	vehicle_mass = spec.mass
	max_engine_force = spec.force
	top_speed = spec.top
	max_steer = spec.steer
	max_brake *= clampf(float(spec.mass) / 1450.0, 1.0, 10.0)
	if display_name == "" or display_name == "Calder Sedan":
		display_name = spec.name
	mass = vehicle_mass
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8 | 16
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	continuous_cd = true
	_build()


func _build() -> void:
	var data := CarLibrary.get_model(model)
	var aabb: AABB = data.aabb
	_size = aabb.size
	damage = VehicleDamage.new()
	damage.name = "Damage"
	add_child(damage)
	damage.setup(self, aabb)
	for p in data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = p[1]
		var kinds: Array = p[2] if p.size() > 2 else []
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var kind: String = kinds[s] if s < kinds.size() else "body"
			var sm: ShaderMaterial
			match kind:
				"glass":
					sm = _glass_material(m)
					damage.glass.append(sm)
				"beacon":
					sm = _beacon_material(m)
				_:
					sm = _paint_material(m, kind == "paint", kind == "cutout")
			sm.set_shader_parameter("part_xf", Projection(p[1]))
			damage.materials.append(sm)
			mi.set_surface_override_material(s, sm)
		add_child(mi)
	# rotors and other spinning parts: a pivot node per part (the subclass turns it)
	for sp: Dictionary in data.get("spinners", []):
		var pivot := Node3D.new()
		pivot.position = sp.pivot
		pivot.set_meta("spin_axis", sp.axis)
		var smi := MeshInstance3D.new()
		smi.mesh = sp.mesh
		smi.transform = sp.xf
		pivot.add_child(smi)
		add_child(pivot)
	for bb: Array in data.get("beacon_boxes", []):
		var bm := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = bb[1]
		bm.mesh = box_mesh
		bm.position = bb[0]
		var sm := _beacon_material(null)
		sm.set_shader_parameter("part_xf", Projection(Transform3D(Basis.IDENTITY, bb[0])))
		bm.material_override = sm
		damage.materials.append(sm)
		add_child(bm)
	_make_collision(aabb)
	center_of_mass = Vector3(0, aabb.position.y + 0.08, 0)

	for w in data.wheels:
		var wheel := VehicleWheel3D.new()
		var front: bool = w.pos.z < 0.0
		wheel.position = w.pos + Vector3(0, 0.12, 0)
		wheel.wheel_radius = w.radius
		var spec: Dictionary = SPECS.get(model, SPECS.sedan)
		wheel.wheel_rest_length = 0.16 + (float(spec.travel) - 0.22) * 0.5
		wheel.suspension_travel = spec.travel
		wheel.suspension_stiffness = spec.stiff
		wheel.suspension_max_force = vehicle_mass * 12.0
		wheel.damping_compression = 1.9
		wheel.damping_relaxation = 2.4
		wheel.wheel_friction_slip = float(spec.grip) + (0.1 if front else 0.0)
		wheel.wheel_roll_influence = 0.04
		wheel.use_as_steering = front
		wheel.use_as_traction = front if spec.drive == "fwd" else (true if spec.drive == "awd" else not front)
		for part in w.parts:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			wheel.add_child(mi)
		add_child(wheel)
		_wheels.append(wheel)

	camera_distance = clampf(_size.z * 1.35, 5.0, 17.0)
	camera_height = clampf(_size.y * 1.05, 1.5, 4.6)
	# driver sits left of centre (US layout), a bit behind the front axle
	var wheelbase_front := 0.0
	for w in data.wheels:
		wheelbase_front = minf(wheelbase_front, w.pos.z)
	# seat = where the driver's hips sit (Player offsets its root by the drive clip's hip height)
	var spec_s: Dictionary = SPECS.get(model, SPECS.sedan)
	var seat_z: float = aabb.position.z + spec_s.seat_z if spec_s.has("seat_z") else wheelbase_front * 0.18
	var seat_y: float = aabb.position.y + _size.y * float(spec_s.get("seat_y", 0.3))
	_seat = Transform3D(Basis.IDENTITY, Vector3(-_size.x * 0.21, seat_y, seat_z))
	_door = Vector3(-_size.x * 0.5 - 0.55, 0.0, seat_z + 0.02)
	if spec_s.get("siren", false):
		_build_beacon_lights(data)
	_build_lights(aabb)
	_build_optics(data)
	_driven = 0.0
	for w in _wheels:
		if w.use_as_traction:
			_driven += 1.0
	set_meta("hood_cam", Vector3(0, aabb.position.y + _size.y * 0.78, aabb.position.z + _size.z * 0.36))


## Tyre smoke behind the rear wheels, created the first time this car slides (most cars never do).
func _add_smoke() -> void:
	for w in _wheels:
		if not w.use_as_steering:
			var sm := _smoke_emitter()
			sm.position = w.position + Vector3(0, -w.wheel_radius * 0.8, 0.2)
			add_child(sm)
			_smoke.append(sm)


func _build_optics(data: Dictionary) -> void:
	var tex: Texture2D = (data.optics_mat as BaseMaterial3D).albedo_texture if data.get("optics_mat") is BaseMaterial3D else null
	for k: String in data.get("optics", {}):
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/shaders/car_lights.gdshader")
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("rear", k == "rear")
		m.set_shader_parameter("has_amber", data.get("amber", {}).get(k, false))
		var ab: AABB = (data.optics[k] as Mesh).get_aabb()
		m.set_shader_parameter("outer_x", maxf(absf(ab.position.x), absf(ab.end.x)) * 0.55)
		var mi := MeshInstance3D.new()
		mi.mesh = data.optics[k]
		mi.material_override = m
		add_child(mi)
		damage.materials.append(m)
		if k == "rear":
			_rear_light = m
		else:
			_front_light = m


func _smoke_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.35))
	grad.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	return p


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	_dot = ImageTexture.create_from_image(img)
	return _dot


## Dentable stand-in for a model material: paint surfaces take the car's colour, other surfaces keep their look.
func _paint_material(src: Material, paint_surface: bool, cutout := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/car_paint_cutout.gdshader") if cutout else preload("res://assets/shaders/car_paint.gdshader")
	var b := src as BaseMaterial3D
	var tex: Texture2D = b.albedo_texture if b else null
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("base_color", b.albedo_color if b else Color.WHITE)
	m.set_shader_parameter("is_paint", paint_surface)
	if paint_surface:
		if tex == null:
			m.set_shader_parameter("solid", true)
			m.set_shader_parameter("paint", paint if paint.a > 0.0 else (b.albedo_color if b else Color.GRAY))
		else:
			var ref := CarLibrary.paint_ref(tex)
			if paint.a > 0.0 and ref.a > 0.0:
				m.set_shader_parameter("repaint", true)
				m.set_shader_parameter("ref_color", ref)
				m.set_shader_parameter("paint", paint)
	elif b:
		# glTF factors multiply a metal/roughness map we don't sample: use neutral values when there is one
		m.set_shader_parameter("base_metallic", 0.3 if b.metallic_texture else b.metallic)
		m.set_shader_parameter("base_roughness", 0.6 if b.roughness_texture else b.roughness)
	return m


func _glass_material(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/car_glass.gdshader")
	var b := src as BaseMaterial3D
	if b:
		if b.albedo_texture:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
		m.set_shader_parameter("tint", b.albedo_color)
	return m


func _beacon_material(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/car_beacon.gdshader")
	var b := src as BaseMaterial3D
	if b:
		if b.albedo_texture:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
		m.set_shader_parameter("base_color", b.albedo_color)
	else:
		m.set_shader_parameter("base_color", Color(0.85, 0.85, 0.85))
	_beacons.append(m)
	return m


func _build_lights(aabb: AABB) -> void:
	var front_z := aabb.position.z + 0.15
	for side in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(side * aabb.size.x * 0.33, aabb.position.y + aabb.size.y * 0.38, front_z)
		l.rotation_degrees = Vector3(-4, 0, 0)
		l.spot_range = 38.0
		l.spot_angle = 32.0
		l.spot_attenuation = 0.8
		l.light_energy = 6.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)


func set_siren(on: bool) -> void:
	siren_on = on and not damage.wrecked and SPECS.get(model, {}).get("siren", false)
	if not siren_on:
		for m in _beacons:
			m.set_shader_parameter("on", 0.0)
		for l in _beacon_lights:
			l.visible = false


func _build_beacon_lights(data: Dictionary) -> void:
	# where the light bar is: the beacon parts or boxes, else on the roof above the windscreen
	var c := Vector3(0, (data.aabb as AABB).end.y + 0.1, (data.aabb as AABB).position.z + _size.z * 0.4)
	var boxes: Array = data.get("beacon_boxes", [])
	if not boxes.is_empty():
		c = (boxes[0][0] + boxes[-1][0]) * 0.5
	else:
		var got := false
		var bb := AABB()
		for p in data.parts:
			var kinds: Array = p[2] if p.size() > 2 else []
			if "beacon" in kinds:
				var a: AABB = (p[1] as Transform3D) * (p[0] as Mesh).get_aabb()
				bb = a if not got else bb.merge(a)
				got = true
		if got:
			c = bb.get_center()
	for side: float in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.08, 0.05) if side < 0.0 else Color(0.1, 0.25, 1.0)
		l.omni_range = 16.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.position = c + Vector3(side * 0.5, 0.25, 0)
		l.visible = false
		add_child(l)
		_beacon_lights.append(l)


func _process(delta: float) -> void:
	if not siren_on:
		return
	_beacon_phase = fmod(_beacon_phase + delta * 1.5, 1.0)
	for m in _beacons:
		m.set_shader_parameter("on", 1.0)
		m.set_shader_parameter("phase", _beacon_phase)
	var night: float = Game.world.night if Game.world else 0.0
	for i in _beacon_lights.size():
		var ph := fmod(_beacon_phase + (0.0 if i == 0 else 0.5), 1.0)
		var flash := ph < 0.12 or (ph > 0.2 and ph < 0.32)
		_beacon_lights[i].visible = flash
		_beacon_lights[i].light_energy = lerpf(1.5, 5.0, night)


func set_indicator(sig: Blinker) -> void:
	indicator = sig
	_blink = 0.0
	_turned = 0.0
	if sig != Blinker.OFF:
		sleeping = false  # keep ticking so the lamps blink
	_update_lights()


func set_headlights(on: bool) -> void:
	headlights_on = on and not damage.wrecked
	for i in _lights.size():
		# lamps[0] is the left one (-X)
		var b: Vector2 = damage.lamps_broken.front
		_lights[i].visible = headlights_on and (b.x if i == 0 else b.y) < 0.5


## Velocity jumps that aren't the car's own driving are collisions: accumulate one collision's change over its
## ticks, then dent the body where it was hit (opposite the push) and play the impact.
func _detect_impact(delta: float) -> void:
	var dv := linear_velocity - _prev_vel
	_prev_vel = linear_velocity
	dv.y += 9.8 * delta
	dv.y *= 0.35  # landings are mostly suspension work
	if dv.length() > 1.2:
		_jolt += dv
		_jolt_ticks += 1
		if _jolt_ticks < 5:
			return
	if _jolt_ticks == 0:
		return
	var j := _jolt
	_jolt = Vector3.ZERO
	_jolt_ticks = 0
	var strength := j.length()
	_last_strength = strength
	_last_jolt = j
	if strength < 2.5:
		return
	var local := global_basis.inverse() * j
	var d := -local.normalized()
	var c := (CarLibrary.get_model(model).aabb as AABB).get_center()
	var half := _size * 0.5
	var t := INF
	for i in 3:
		if absf(d[i]) > 0.001:
			t = minf(t, half[i] / absf(d[i]))
	var point := c + d * t
	damage.hit(point, local.normalized(), strength)
	var at := global_transform * point
	var vol := clampf(-14.0 + strength * 1.6, -14.0, 4.0)
	Audio.play_at(Audio.pick("vehicles/bump_%d.ogg", 3), at, vol, randf_range(0.85, 1.1))
	if strength > 7.0:
		Audio.play_at(Audio.pick("vehicles/crash_%d.ogg", 4), at, clampf(-8.0 + strength * 0.8, -8.0, 6.0), randf_range(0.85, 1.08))
	if driver == Game.player and Game.player:
		var cam: CameraRig = Game.player.get("cam")
		if cam:
			cam.shake = maxf(cam.shake, clampf(strength / 14.0, 0.0, 1.6))


## Gunfire (Weapon calls this with the hit point and direction).
func bullet_hit(pos: Vector3, dir: Vector3, amount: float, _from: Node = null) -> void:
	sleeping = false
	apply_impulse(dir * 4.0, pos - global_position)
	damage.bullet(global_transform.affine_inverse() * pos, amount)


func take_damage(amount: float, _from: Node = null) -> void:
	damage._damage(amount)


func _on_lamps_broken() -> void:
	if _front_light:
		_front_light.set_shader_parameter("broken", damage.lamps_broken.front)
	if _rear_light:
		_rear_light.set_shader_parameter("broken", damage.lamps_broken.rear)
	set_headlights(headlights_on)


func _on_engine_dead() -> void:
	engine_dead = true
	if audio:
		audio.stop()


func _on_wrecked() -> void:
	engine_dead = true
	set_siren(false)
	# tyres burnt off, rims blackened
	var charred := StandardMaterial3D.new()
	charred.albedo_color = Color(0.025, 0.024, 0.023)
	charred.roughness = 0.95
	for w in _wheels:
		for mi in w.get_children():
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).material_override = charred
		w.wheel_friction_slip = 0.6
	set_headlights(false)
	set_indicator(Blinker.OFF)
	horn_on = false
	if audio:
		audio.stop()
	# whoever is inside is thrown out
	if driver and driver.has_method("bail_out"):
		driver.bail_out(self)


## Car bodies: a box for the lower body (above the wheels, which carry the car) and one for the cabin.
func _make_collision(aabb: AABB) -> void:
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.96, aabb.size.y * 0.55, aabb.size.z * 0.97)
	hull.shape = box
	hull.position = aabb.get_center() + Vector3(0, -aabb.size.y * 0.12, 0)
	add_child(hull)
	var cabin := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(aabb.size.x * 0.8, aabb.size.y * 0.42, aabb.size.z * 0.5)
	cabin.shape = cbox
	cabin.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.25, -aabb.size.z * 0.03)
	add_child(cabin)


func driver_door_position() -> Vector3:
	return global_transform * _door


## Driver hips target (on the seat cushion), facing forward.
func seat_transform() -> Transform3D:
	return global_transform * _seat


func ground_height_at(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2, 0), p + Vector3(0, -4, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else global_position.y


func reserve(who: Node) -> void:
	driver = who
	sleeping = false
	brake = max_brake
	engine_force = 0.0


func set_driver(who: Node) -> void:
	driver = who
	sleeping = false
	input_enabled = who != null
	if who == null:
		engine_force = 0.0
		brake = max_brake * 0.3
		_throttle = 0.0
		horn_on = false
		if audio:
			audio.stop()
	elif not engine_dead and SPECS.get(model, SPECS.sedan).get("sound", "car") != "none":
		if audio == null:
			audio = VehicleAudio.new()
			audio.name = "Audio"
			add_child(audio)
			audio.setup(self, ENGINE_PITCH.get(model, 1.0), SPECS.get(model, SPECS.sedan).get("sound", "car"))
		audio.start()
	driver_changed.emit(who)


func set_driver_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		engine_force = 0.0
		brake = max_brake


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func _physics_process(delta: float) -> void:
	_detect_impact(delta)
	# parked and at rest: apply no forces at all so the physics engine can put the body to sleep
	if indicator != Blinker.OFF:
		_blink += delta
		if indicator != Blinker.HAZARD:
			_turned += angular_velocity.y * delta * (1.0 if indicator == Blinker.LEFT else -1.0)
			# cancel once the turn in the signalled direction is done and the wheel is straight again
			if _turned > 0.9 and absf(_steer) < 0.05:
				set_indicator(Blinker.OFF)
	if driver == null and linear_velocity.length_squared() < 0.0625 and angular_velocity.length_squared() < 0.01:
		if indicator != Blinker.OFF:
			_update_lights()
		if not _idle:
			_go_idle()
		if _put_to_sleep and not sleeping:
			_idle_time = 0.0  # something woke it (a push, a blast): give it time to start moving
			_put_to_sleep = false
		_idle_time += delta
		if _idle_time > 0.5 and not sleeping:
			sleeping = true  # the suspension keeps nudging the body, so it never dozes off on its own
			_put_to_sleep = true
		return
	_idle = false
	_idle_time = 0.0
	var fwd_speed := -global_basis.z.dot(linear_velocity)
	var throttle := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var handbrake := false
	if input_enabled:
		throttle = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake")
		steer_in = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		handbrake = Input.is_action_pressed("handbrake")
		# emergency vehicles: a tap of the horn toggles siren + lights, holding it sounds the horn
		var emergency: bool = SPECS.get(model, {}).get("siren", false)
		if Input.is_action_just_pressed("horn"):
			_horn_t = 0.0
		if Input.is_action_pressed("horn") and _horn_t >= 0.0:
			_horn_t += delta
		elif _horn_t >= 0.0:
			if emergency and _horn_t < 0.25:
				set_siren(not siren_on)
			_horn_t = -1.0
		horn_on = _horn_t > (0.25 if emergency else 0.0)
		if Input.is_action_just_pressed("headlights"):
			set_headlights(not headlights_on)
		if Input.is_action_just_pressed("indicator_left"):
			set_indicator(Blinker.OFF if indicator == Blinker.LEFT else Blinker.LEFT)
		if Input.is_action_just_pressed("indicator_right"):
			set_indicator(Blinker.OFF if indicator == Blinker.RIGHT else Blinker.RIGHT)
		if Input.is_action_just_pressed("hazards"):
			set_indicator(Blinker.OFF if indicator == Blinker.HAZARD else Blinker.HAZARD)

	# brake pedal reverses once (almost) stopped
	if engine_dead:
		throttle = 0.0
		if brake_in > 0.05 and fwd_speed <= 1.0:
			brake_in = 0.0
	var drive := throttle
	var braking := 0.0
	if brake_in > 0.05:
		if fwd_speed > 1.0:
			braking = brake_in
		else:
			drive = -brake_in * 0.55
	if throttle > 0.05 and fwd_speed < -1.0:
		braking = throttle
		drive = 0.0
	_throttle = move_toward(_throttle, drive, delta * 3.0)
	# automatic gearbox: pick the gear for this speed, engine pull falls off with gear and near the redline
	var v := absf(fwd_speed)
	if _throttle < -0.01:
		gear = -1
	elif gear < 1:
		gear = 1
	if gear >= 1:
		var top_g: float = top_speed * GEARS[gear - 1]
		var r := v / top_g
		if r > 0.92 and gear < GEARS.size():
			gear += 1
		elif gear > 1 and v < top_speed * GEARS[gear - 2] * 0.62:
			gear -= 1
		top_g = top_speed * GEARS[gear - 1]
		var target_rpm := IDLE_RPM + (RED_RPM - IDLE_RPM) * clampf(v / top_g, 0.0, 1.0)
		if v < 2.0:
			target_rpm = lerpf(IDLE_RPM + 2200.0 * absf(_throttle), target_rpm, v / 2.0)
		rpm = lerpf(rpm, target_rpm, 1.0 - exp(-delta * 10.0))
	else:
		rpm = lerpf(rpm, IDLE_RPM + 3000.0 * clampf(v / 7.0, 0.0, 1.0) + 800.0 * absf(_throttle), 1.0 - exp(-delta * 8.0))
	var speed_factor := clampf(1.0 - v / top_speed, 0.0, 1.0)
	var pull: float = GEAR_PULL[gear - 1] if gear >= 1 else 1.2
	if _throttle < 0.0:
		speed_factor = clampf(1.0 - v / 7.0, 0.0, 1.0)  # reverse tops out ~25 km/h
	var torque := clampf(0.55 + 0.6 * sin(clampf(rpm / RED_RPM, 0.0, 1.0) * PI * 0.9), 0.4, 1.15)
	# VehicleBody3D drives along +Z; our cars face -Z, so forward thrust is a negative engine force
	# engine_force is applied at every driven wheel: normalise so AWD isn't twice as strong as RWD
	# a badly damaged engine loses power
	var health_k := 1.0 if damage.health > 300.0 else 0.55 + 0.45 * damage.health / 300.0
	engine_force = -_throttle * max_engine_force * health_k * pull * torque * (0.5 + 0.5 * speed_factor) / GEAR_PULL[2] * 2.0 / maxf(_driven, 1.0)
	braking_now = braking > 0.05 or (handbrake and v > 1.0)
	reversing = _throttle < -0.05
	# nobody at the controls (parked, or a driver getting in/out): hold the car firmly
	brake = braking * max_brake if input_enabled else max_brake

	var steer_limit := max_steer / (1.0 + absf(fwd_speed) / 5.5)
	var steer_rate := 2.6 if absf(steer_in) > 0.01 else 4.0
	_steer = move_toward(_steer, steer_in * steer_limit, delta * steer_rate)
	steering = _steer

	for w in _wheels:
		if not w.use_as_steering:
			w.wheel_friction_slip = 1.0 if handbrake else 2.5
			if handbrake:
				w.brake = max_brake * 0.8
	# downforce keeps it planted at speed
	apply_central_force(-global_basis.y * linear_velocity.length_squared() * 1.6)
	var grounded := 0
	for w in _wheels:
		if w.is_in_contact():
			grounded += 1
	_stabilize(delta, grounded, fwd_speed)
	_update_tyres(v, handbrake)
	_update_lights()


## Arcade anti-roll: resist roll/pitch away from upright (weaker when airborne so jumps still tumble).
func _stabilize(_delta: float, grounded: int, _fwd_speed: float) -> void:
	var tilt := global_basis.y.cross(Vector3.UP)
	var k := 16.0 if grounded >= 2 else 1.5
	apply_torque(tilt * mass * k - (angular_velocity - global_basis.y * angular_velocity.dot(global_basis.y)) * mass * 0.6)


func _go_idle() -> void:
	_idle = true
	engine_force = 0.0
	brake = max_brake
	_throttle = 0.0
	rpm = IDLE_RPM
	braking_now = false
	reversing = false
	skidding = 0.0
	_last_mark.clear()
	for sm in _smoke:
		sm.emitting = false
	_update_lights()


## Skid marks and smoke when the tyres slide (handbrake, wheelspin, hard cornering).
func _update_tyres(v: float, handbrake: bool) -> void:
	var slide := 0.0
	var marks := SkidMarks.instance
	for w in _wheels:
		var s := 0.0
		if w.is_in_contact() and v > 3.0:
			s = clampf((0.75 - w.get_skidinfo()) / 0.5, 0.0, 1.0)
			if handbrake and not w.use_as_steering:
				s = maxf(s, 0.8)
		if w.is_in_contact() and absf(engine_force) > max_engine_force * 0.8 and v < 6.0 and w.use_as_traction:
			s = maxf(s, 0.7)  # launch wheelspin
		slide = maxf(slide, s)
		if marks:
			var contact := w.get_contact_point() if w.is_in_contact() else Vector3.INF
			if s > 0.35 and contact != Vector3.INF:
				var last: Vector3 = _last_mark.get(w, Vector3.INF)
				if last != Vector3.INF and last.distance_to(contact) > 0.25:
					marks.add(last, contact, w.get_contact_normal(), s)
					_last_mark[w] = contact
				elif last == Vector3.INF:
					_last_mark[w] = contact
			else:
				_last_mark.erase(w)
	skidding = lerpf(skidding, slide, 0.2)
	if skidding > 0.45 and _smoke.is_empty():
		_add_smoke()
	for sm in _smoke:
		sm.emitting = skidding > 0.45
		sm.amount_ratio = clampf(skidding, 0.2, 1.0)


func _update_lights() -> void:
	var night: float = Game.world.night if Game.world else 0.0
	if driver != null and not headlights_on and night > 0.5:
		set_headlights(true)
	var on := 1.0 if headlights_on else 0.0
	var lit := indicator != Blinker.OFF and fmod(_blink, 0.75) < 0.4 and not damage.wrecked
	if lit != _lit_was:
		_lit_was = lit
		if audio and driver != null and driver == Game.player:
			audio.tick()
	var il := 1.0 if lit and indicator in [Blinker.LEFT, Blinker.HAZARD] else 0.0
	var ir := 1.0 if lit and indicator in [Blinker.RIGHT, Blinker.HAZARD] else 0.0
	for m: ShaderMaterial in [_front_light, _rear_light]:
		if m:
			m.set_shader_parameter("ind_left", il)
			m.set_shader_parameter("ind_right", ir)
	if _front_light:
		_front_light.set_shader_parameter("head", on)
	if _rear_light:
		_rear_light.set_shader_parameter("tail", on)
		_rear_light.set_shader_parameter("brake", 1.0 if braking_now and driver != null else 0.0)
		_rear_light.set_shader_parameter("reverse", 1.0 if reversing and driver != null else 0.0)
