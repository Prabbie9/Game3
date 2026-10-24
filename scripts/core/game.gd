extends Node
## Global game state (autoload "Game"). Kept small: references + economy + mode flags.

signal money_changed(amount: int)
signal notify(text: String)
## A line of speech for the subtitles (police radio, a witness on the phone); shown if subtitles are on.
signal subtitle(speaker: String, text: String)
## Something loud happened (gunfire, explosions): pedestrians and police react within `radius` metres.
signal noise_made(pos: Vector3, radius: float, source: Node)
## The player broke the law (kind: "assault", "murder", "shooting", "theft", "carjack", "hit_pedestrian",
## "attack_police", ...): the wanted system (Milestone 7) listens.
signal crime_committed(kind: String, pos: Vector3)
## A witness phoned the police about trouble at `where` (they are calling from `pos`).
signal police_call(pos: Vector3, where: Vector3)

var player: Node3D
var world: Node3D
var hud: CanvasLayer
var money := 500:
	set(v):
		if not loading:
			if v > money:
				stat_add("money_earned", v - money)
			elif v < money:
				stat_add("money_spent", money - v)
		money = v
		money_changed.emit(money)
## Career stats (pause menu → STATS; saved with the game).
var stats := {}
var loading := false   # restoring a save: money changes are not earnings
var pending_load := {}  # a save to apply once the world has loaded (SaveGame)
var autoplay := false   # main menu: go straight into the game (loading a save from the pause menu)
var collected: Array = []   # lucky coins found (Collectibles ids; saved with the game)
const STAT_LABELS := [["time_played", "Time played"], ["distance_foot", "Distance on foot"],
	["distance_driven", "Distance driven"], ["vehicles_stolen", "Vehicles stolen"], ["shots", "Shots fired"],
	["accuracy", "Accuracy"], ["headshots", "Head shots"], ["kills", "People killed"],
	["cops_killed", "Police officers killed"], ["max_wanted", "Highest wanted level"], ["busted", "Times busted"],
	["wasted", "Times wasted"], ["lucky_coins", "Lucky coins found"], ["money_earned", "Money earned"], ["money_spent", "Money spent"]]
var benchmark_mode := false
var controls_enabled := true
var mouse_sensitivity := 0.0025
var gamepad_sensitivity := 3.0
var invert_y := false
var using_gamepad := false
## Gameplay options (settings menu): gamepad aim assist, blood effects.
var aim_assist := true
var blood := true


func _ready() -> void:
	InputSetup.apply_defaults()
	# after the other autoloads (the audio buses exist then)
	Settings.apply.call_deferred()
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
	NPCDriver.release()
	Explosion.release()


func police_called(pos: Vector3, where: Vector3) -> void:
	police_call.emit(pos, where)
	# heard if the player is close to the caller
	if player and world and world.has_method("place_name") and player.global_position.distance_to(pos) < 25.0:
		var lines := ["Police? Someone's shooting on %s! Please hurry!", "Hello? There's a maniac on %s, people are hurt!",
			"I need the police on %s. Somebody just got killed!", "Yes, %s. A guy with a gun. Please come now!"]
		say("Caller", lines[randi() % lines.size()] % world.place_name(where))


func stat_add(key: String, amount: float = 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


func stat_max(key: String, value: float) -> void:
	stats[key] = maxf(float(stats.get(key, 0.0)), value)


## A stat as shown in the stats screen.
func stat_text(key: String) -> String:
	var v := float(stats.get(key, 0.0))
	match key:
		"time_played":
			return "%dh %02dm" % [int(v / 3600.0), int(fmod(v, 3600.0) / 60.0)]
		"distance_foot", "distance_driven":
			return "%.1f km" % (v / 1000.0)
		"accuracy":
			var shots := float(stats.get("shots", 0.0))
			return "%d%%" % int(round(100.0 * float(stats.get("hits", 0.0)) / shots)) if shots > 0.0 else "—"
		"lucky_coins":
			return "%d / %d" % [collected.size(), Collectibles.COUNT]
		"max_wanted":
			return "%d ★" % int(v) if v > 0.0 else "—"
		"money_earned", "money_spent":
			return "$%d" % int(v)
	return "%d" % int(v)


func _process(delta: float) -> void:
	if not get_tree().paused and world != null and controls_enabled:
		stat_add("time_played", delta)


func crime(kind: String, pos: Vector3) -> void:
	crime_committed.emit(kind, pos)


func noise(pos: Vector3, radius: float, source: Node = null) -> void:
	noise_made.emit(pos, radius, source)


## A fresh career (a new world without a save to load): starting money, no stats, no coins found.
func new_career() -> void:
	loading = true
	money = 500
	loading = false
	stats = {}
	collected = []


func message(text: String) -> void:
	notify.emit(text)


func say(speaker: String, text: String) -> void:
	if bool(Settings.gameplay.get("subtitles", true)):
		subtitle.emit(speaker, text)
