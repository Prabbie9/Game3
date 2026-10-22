extends Node
## Global game state (autoload "Game"). Kept small: references + economy + mode flags.

signal money_changed(amount: int)
signal notify(text: String)

var player: Node3D
var world: Node3D
var hud: CanvasLayer
var money := 500:
	set(v):
		money = v
		money_changed.emit(money)
var benchmark_mode := false
var controls_enabled := true
var mouse_sensitivity := 0.0025
var gamepad_sensitivity := 3.0
var invert_y := false
var using_gamepad := false


func _ready() -> void:
	InputSetup.apply_defaults()
	process_mode = Node.PROCESS_MODE_ALWAYS
	benchmark_mode = "--benchmark" in OS.get_cmdline_user_args() or "--benchmark" in OS.get_cmdline_args()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false


func message(text: String) -> void:
	notify.emit(text)
