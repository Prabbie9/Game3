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
	if "--smoke" in OS.get_cmdline_user_args() or "--smoke" in OS.get_cmdline_args():
		_smoke_test.call_deferred()


## Automated boot check for exported builds: main menu -> Play -> world running -> report -> quit.
func _smoke_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var menu := get_tree().current_scene
	printerr("SMOKE: main menu scene = %s" % (menu.name if menu else "none"))
	if menu and menu.has_method("_on_play"):
		menu._on_play()
	await get_tree().create_timer(5.0).timeout
	var ok := player != null and world != null and player.is_inside_tree()
	var cells := 0
	if ok and world.get("city"):
		cells = world.city.ready_cells
		ok = ok and cells >= 6 and player.global_position.y > -1.0
	printerr("SMOKE: world loaded = %s, player at %s, city cells %d, fps = %d, renderer = %s" % [ok, player.global_position if player else Vector3.ZERO,
		cells, Engine.get_frames_per_second(), RenderingServer.get_video_adapter_name()])
	printerr("SMOKE TEST %s" % ("PASSED" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false


## Release static caches while the engine servers still exist (otherwise they are freed after
## RenderingServer shutdown, which crashes on exit).
func _exit_tree() -> void:
	CarLibrary._cache.clear()
	FX.release()
	UITheme._theme = null
	UITheme.heading = null
	UITheme.body = null
	UITheme.body_bold = null
	AnimLib._lib = null
	WaterVolume._mat = null
	WorldData.release()
	PropCatalog.release()
	Audio.release()
	VehicleDamage.release()


func message(text: String) -> void:
	notify.emit(text)
