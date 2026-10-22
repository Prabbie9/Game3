class_name CoverSpot
extends RefCounted
## Finds and tracks a wall to take cover against. High cover (>= 1.45 m) or low cover (0.8-1.45 m).

const MASK := 1 | 8 | 16
## Yaw offset of the cover clips relative to the root: Mixamo's cover set is authored with the character turned
## around (front towards the root's back), so the root faces the wall and the body has its back to it. And the
## sign that maps movement along the wall tangent onto the clips' lateral blend axis (cover_right travels to the
## character's right, i.e. along -tangent). Checked with tools/dev/pose_sheet.gd and tests/abilities_check.gd.
const FACING := PI
const SIDE_SIGN := -1.0


## Returns {} or {"point": Vector3 (feet position at the wall), "normal": Vector3, "low": bool}
static func find(world: World3D, feet: Vector3, dir: Vector3, exclude: Array[RID]) -> Dictionary:
	var space := world.direct_space_state
	dir.y = 0
	dir = dir.normalized()
	var waist := _ray(space, feet + Vector3(0, 0.7, 0), feet + Vector3(0, 0.7, 0) + dir * 1.6, exclude)
	if waist.is_empty() or absf((waist.normal as Vector3).y) > 0.3:
		return {}
	var n: Vector3 = waist.normal
	n.y = 0
	n = n.normalized()
	var head := _ray(space, feet + Vector3(0, 1.5, 0), feet + Vector3(0, 1.5, 0) - n * 1.8, exclude)
	var low := head.is_empty()
	var p: Vector3 = waist.position + n * 0.38
	return {"point": Vector3(p.x, feet.y, p.z), "normal": n, "low": low}


## Re-checks the wall at a position (keeps cover glued to curved/long walls; empty if the wall ended).
static func probe(world: World3D, feet: Vector3, normal: Vector3, exclude: Array[RID]) -> Dictionary:
	return find(world, feet, -normal, exclude)


static func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, MASK)
	q.exclude = exclude
	return space.intersect_ray(q)
