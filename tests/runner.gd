extends Node
## Generic runner so test/tool scripts get autoloads: godot --path . res://tests/runner.tscn -- res://tests/xyz.gd [args...]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var s: Script = load(args[0])
	var n: Node = s.new()
	n.set_meta("args", args.slice(1))
	add_child(n)
