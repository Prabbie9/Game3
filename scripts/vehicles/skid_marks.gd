class_name SkidMarks
extends MultiMeshInstance3D
## Tyre marks laid by sliding wheels: a ring buffer of thin dark quads (one MultiMesh, one draw call).

const MAX := 2400

static var instance: SkidMarks

var _next := 0


func _ready() -> void:
	instance = self
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.04, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.6
	m.vertex_color_use_as_albedo = true
	m.render_priority = -1
	q.material = m
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = q
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true


func _exit_tree() -> void:
	if instance == self:
		instance = null


## One mark segment from a to b on a surface with normal n; strength 0..1 sets darkness.
func add(a: Vector3, b: Vector3, n: Vector3, strength: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var z := d / len
	var x := n.cross(z).normalized()
	var y := z.cross(x)
	var basis := Basis(x * 0.24, y, z * (len + 0.05))
	multimesh.set_instance_transform(_next, Transform3D(basis, (a + b) * 0.5 + n * 0.025))
	multimesh.set_instance_color(_next, Color(1, 1, 1, clampf(strength, 0.3, 1.0)))
	_next = (_next + 1) % MAX
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, mini(_next if _next > 0 else MAX, MAX))
