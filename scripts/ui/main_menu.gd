extends Node
## Boot scene: loads the world behind a slow orbiting camera with the title menu on top.

const WORLD := preload("res://scenes/world/world.tscn")

var world: World
var _orbit: Camera3D
var _menu: CanvasLayer
var _t := 0.0
var _col: VBoxContainer
var _slots: VBoxContainer
var _menu_root: Control


func _ready() -> void:
	Game.controls_enabled = false
	# window mode / size / v-sync / frame cap from the settings (only on the real boot path, not in tests)
	if not Game.autoplay and OS.has_feature("template"):
		GraphicsSettings.apply_display()
	if Game.benchmark_mode:
		get_tree().change_scene_to_file.call_deferred("res://scenes/world/world.tscn")
		return
	world = WORLD.instantiate()
	add_child(world)
	_orbit = Camera3D.new()
	_orbit.fov = 55
	_orbit.far = 2500
	add_child(_orbit)
	_orbit.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_menu()
	if Game.autoplay:
		# loading a save from the pause menu: straight back into the game (World applied Game.pending_load)
		Game.autoplay = false
		_on_play.call_deferred()
	if world.has_node("HUD"):
		pass
	for c in world.get_children():
		if c is CanvasLayer:
			c.visible = false


func _build_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 20
	add_child(_menu)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	_menu.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.material = _gradient_material()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(110, 150)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var title := UITheme.label("PORT SOLANO", 96, UITheme.heading, UITheme.PAPER)
	col.add_child(title)
	var sub := UITheme.label("AN OPEN CITY ON THE PACIFIC COAST", 18, UITheme.body_bold, UITheme.CORAL)
	col.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	col.add_child(spacer)
	GraphicsSettings.ensure_loaded()
	var latest := SaveGame.latest_slot()
	var first: Button
	if latest > 0:
		first = UITheme.menu_button(col, "CONTINUE", _load_slot.bind(latest))
	var play := UITheme.menu_button(col, "NEW GAME", _on_play)
	if first == null:
		first = play
	UITheme.menu_button(col, "LOAD GAME", _show_slots)
	UITheme.menu_button(col, "SETTINGS", _open_settings)
	UITheme.menu_button(col, "BENCHMARK", _on_benchmark)
	UITheme.menu_button(col, "QUIT", func(): get_tree().quit())
	_col = col
	first.grab_focus.call_deferred()
	_slots = VBoxContainer.new()
	_slots.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_slots.position = Vector2(-820, 330)
	_slots.add_theme_constant_override("separation", 8)
	root.add_child(_slots)
	_menu_root = root
	var foot := UITheme.label("v%s  ·  F3 performance overlay  ·  credits in ASSET_CREDITS.md" % ProjectSettings.get_setting("application/config/version"), 14, UITheme.body, UITheme.MUTED)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 110
	foot.offset_top = -60
	root.add_child(foot)


func _show_slots() -> void:
	for c in _slots.get_children():
		c.queue_free()
	_slots.add_child(UITheme.label("LOAD GAME", 30, UITheme.heading, UITheme.SAND))
	var first: Button = null
	for slot in range(1, SaveGame.SLOTS + 1):
		var desc := SaveGame.describe(slot)
		var b := Button.new()
		b.text = "SLOT %d   %s" % [slot, desc if desc != "" else "— empty —"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(720, 50)
		b.add_theme_font_size_override("font_size", 20)
		b.disabled = desc == ""
		b.focus_entered.connect(func(): Audio.play_ui("click"))
		b.pressed.connect(_load_slot.bind(slot))
		_slots.add_child(b)
		if first == null and not b.disabled:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _load_slot(slot: int) -> void:
	var d := SaveGame.load_data(slot)
	if d.is_empty():
		return
	Audio.play_ui("select")
	_on_play()
	SaveGame.apply(d)


func _open_settings() -> void:
	_col.visible = false
	_slots.visible = false
	var sm := SettingsMenu.new()
	sm.world = world
	_menu_root.add_child(sm)
	sm.closed.connect(func():
		_col.visible = true
		_slots.visible = true
		_col.get_child(3).grab_focus.call_deferred())


func _gradient_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ float k = smoothstep(0.75, 0.0, UV.x); COLOR = vec4(0.078, 0.086, 0.102, 0.88 * k + 0.12 * (1.0 - UV.y)); }"
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _on_benchmark() -> void:
	Game.benchmark_mode = true
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_play() -> void:
	_menu.queue_free()
	_orbit.queue_free()
	set_process(false)
	world.player.cam.camera.make_current()
	for c in world.get_children():
		if c is CanvasLayer:
			c.visible = c.name != "PerfOverlay" or c.visible
	if Game.hud:
		Game.hud.visible = bool(Settings.gameplay.hud)
	Game.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_child(preload("res://scripts/ui/pause_menu.gd").new())


func _process(delta: float) -> void:
	if not _orbit:
		return
	_t += delta * 0.04
	var c := Vector3(10, 0, 0)
	_orbit.global_position = c + Vector3(cos(_t) * 70.0, 34.0 + sin(_t * 0.7) * 6.0, sin(_t) * 70.0)
	_orbit.look_at(c + Vector3(0, 12, 0))
