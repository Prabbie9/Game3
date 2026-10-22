extends Node
func _ready():
	for p in get_meta("args"):
		var n: Node3D = load(p).instantiate()
		add_child(n)
		var a := _aabb(n, Transform3D.IDENTITY)
		print("%-60s size=%s pos=%s" % [p.get_file(), a.size, a.position])
		n.queue_free()
	get_tree().quit()
func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB(); var first := true
	var t: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is VisualInstance3D: out = t * (n as VisualInstance3D).get_aabb(); first = false
	for ch in n.get_children():
		var b := _aabb(ch, t)
		if b.size != Vector3.ZERO: out = b if first else out.merge(b); first = false
	return out
