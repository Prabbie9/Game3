class_name WaterVolume
extends Node3D
## A body of water the player can swim in (box-shaped region; surface at the top). The ocean and pools in
## Milestone 3 use this; it also renders a simple water surface when `show_surface` is on.

@export var size := Vector3(20, 3, 20)
@export var show_surface := true
## The ocean's volume: water only where the terrain dips below the surface.
var sea := false


func _ready() -> void:
	add_to_group("water")
	if show_surface:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size.x, size.z)
		mi.mesh = pm
		mi.position.y = size.y * 0.5
		mi.material_override = _material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


static var _mat: ShaderMaterial


## Shared water material (ripple normal maps generated once from seamless noise).
static func _material() -> ShaderMaterial:
	if _mat:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/water.gdshader")
	for i in 2:
		var noise := FastNoiseLite.new()
		noise.seed = 11 + i * 37
		noise.frequency = 0.02 if i == 0 else 0.035
		noise.fractal_octaves = 3
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 6.0
		tex.generate_mipmaps = true
		tex.noise = noise
		_mat.set_shader_parameter("ripple_a" if i == 0 else "ripple_b", tex)
	return _mat


func surface_y() -> float:
	return global_position.y + size.y * 0.5


## Water depth above a world position (0 if outside the volume).
func depth_at(p: Vector3) -> float:
	var l := p - global_position
	if absf(l.x) > size.x * 0.5 or absf(l.z) > size.z * 0.5 or l.y > size.y * 0.5 or l.y < -size.y * 0.5:
		return 0.0
	# the sea only where the seabed is below the surface (not under the land)
	if sea and WorldData.get_data().height_at(p.x, p.z) > surface_y() - 0.2:
		return 0.0
	return surface_y() - p.y
