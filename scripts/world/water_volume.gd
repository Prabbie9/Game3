class_name WaterVolume
extends Node3D
## A body of water the player can swim in (box-shaped region; surface at the top). The ocean and pools in
## Milestone 3 use this; it also renders a simple water surface when `show_surface` is on.

@export var size := Vector3(20, 3, 20)
@export var show_surface := true


func _ready() -> void:
	add_to_group("water")
	if show_surface:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size.x, size.z)
		mi.mesh = pm
		mi.position.y = size.y * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.32, 0.38, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.2
		mi.material_override = m
		add_child(mi)


func surface_y() -> float:
	return global_position.y + size.y * 0.5


## Water depth above a world position (0 if outside the volume).
func depth_at(p: Vector3) -> float:
	var l := p - global_position
	if absf(l.x) > size.x * 0.5 or absf(l.z) > size.z * 0.5 or l.y > size.y * 0.5 or l.y < -size.y * 0.5:
		return 0.0
	return surface_y() - p.y
