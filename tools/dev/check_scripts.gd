extends Node
# Loads every script under res://scripts and res://tests to surface parse/compile errors quickly.
func _ready():
	var bad := 0
	for dir in ["res://scripts", "res://tests"]:
		bad += _scan(dir)
	print("SCRIPT CHECK: %d failing" % bad)
	get_tree().quit(bad)

func _scan(d: String) -> int:
	var bad := 0
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".gd"):
			var s = load(d.path_join(f))
			if s == null or not (s as Script).can_instantiate():
				print("FAIL ", d.path_join(f)); bad += 1
	for sub in DirAccess.get_directories_at(d):
		bad += _scan(d.path_join(sub))
	return bad
