class_name Settings
extends RefCounted
## Audio, gameplay and control settings, kept in user://settings.cfg next to the graphics/display settings
## (GraphicsSettings). Loaded and applied once at start-up (Game._ready); the settings menu changes values here
## and calls apply() + save().

const PATH := GraphicsSettings.PATH
## bus -> volume offset (dB) at full slider, so the mix stays balanced at any setting
const BUS_BASE := {"Master": 0.0, "Music": 0.0, "SFX": 0.0, "Vehicles": -2.0, "Ambience": -4.0}
const BUS_LABELS := {"Master": "Master volume", "Music": "Radio and music", "SFX": "Effects", "Vehicles": "Vehicles",
	"Ambience": "City ambience"}

static var audio := {"Master": 0.85, "Music": 0.8, "SFX": 1.0, "Vehicles": 1.0, "Ambience": 1.0}
static var gameplay := {"aim_assist": true, "blood": true, "subtitles": true, "invert_y": false, "mouse_sens": 1.0,
	"pad_sens": 1.0, "hud": true}
## action -> {"kb": [event dicts], "pad": [event dicts]} for actions the player has rebound
static var bindings := {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in audio:
		audio[k] = float(cf.get_value("audio", k, audio[k]))
	for k in gameplay:
		gameplay[k] = cf.get_value("gameplay", k, gameplay[k])
	bindings = cf.get_value("controls", "bindings", {})


static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)   # keep the graphics / display sections
	for k in audio:
		cf.set_value("audio", k, audio[k])
	for k in gameplay:
		cf.set_value("gameplay", k, gameplay[k])
	cf.set_value("controls", "bindings", bindings)
	cf.save(PATH)


static func apply() -> void:
	ensure_loaded()
	for b: String in audio:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			var v := clampf(float(audio[b]), 0.0, 1.0)
			AudioServer.set_bus_volume_db(i, float(BUS_BASE.get(b, 0.0)) + linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(i, v <= 0.001)
	Game.aim_assist = bool(gameplay.aim_assist)
	Game.blood = bool(gameplay.blood)
	Game.invert_y = bool(gameplay.invert_y)
	Game.mouse_sensitivity = 0.0025 * float(gameplay.mouse_sens)
	Game.gamepad_sensitivity = 3.0 * float(gameplay.pad_sens)
	if Game.hud and Game.controls_enabled:
		Game.hud.visible = bool(gameplay.hud)
	apply_bindings()


# --- controls ------------------------------------------------------------------

## Defaults, then the player's own bindings on top (keyboard/mouse and gamepad are rebound separately).
static func apply_bindings() -> void:
	InputSetup.apply_defaults()
	for a: String in bindings:
		if not InputMap.has_action(a):
			continue
		var b: Dictionary = bindings[a]
		for kind: String in ["kb", "pad"]:
			if not b.has(kind):
				continue
			for e in InputMap.action_get_events(a):
				if is_pad(e) == (kind == "pad"):
					InputMap.action_erase_event(a, e)
			for d: Dictionary in b[kind]:
				var e := from_dict(d)
				if e:
					InputMap.action_add_event(a, e)


## Bind `event` as the (only) keyboard/mouse or gamepad input of `action`.
static func rebind(action: String, event: InputEvent) -> void:
	var kind := "pad" if is_pad(event) else "kb"
	if not bindings.has(action):
		bindings[action] = {}
	bindings[action][kind] = [to_dict(event)]
	apply_bindings()
	save()


static func reset_bindings() -> void:
	bindings = {}
	apply_bindings()
	save()


static func is_pad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion


static func to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"t": "key", "c": int((e as InputEventKey).physical_keycode)}
	if e is InputEventMouseButton:
		return {"t": "mouse", "b": int((e as InputEventMouseButton).button_index)}
	if e is InputEventJoypadButton:
		return {"t": "pad", "b": int((e as InputEventJoypadButton).button_index)}
	if e is InputEventJoypadMotion:
		return {"t": "axis", "a": int((e as InputEventJoypadMotion).axis), "v": signf((e as InputEventJoypadMotion).axis_value)}
	return {}


static func from_dict(d: Dictionary) -> InputEvent:
	match String(d.get("t", "")):
		"key":
			var e := InputEventKey.new()
			e.physical_keycode = int(d.c)
			return e
		"mouse":
			var e := InputEventMouseButton.new()
			e.button_index = int(d.b)
			return e
		"pad":
			var e := InputEventJoypadButton.new()
			e.button_index = int(d.b)
			return e
		"axis":
			var e := InputEventJoypadMotion.new()
			e.axis = int(d.a)
			e.axis_value = float(d.v)
			return e
	return null


const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_START: "START", JOY_BUTTON_BACK: "VIEW", JOY_BUTTON_GUIDE: "GUIDE",
	JOY_BUTTON_DPAD_UP: "D-PAD UP", JOY_BUTTON_DPAD_DOWN: "D-PAD DOWN", JOY_BUTTON_DPAD_LEFT: "D-PAD LEFT",
	JOY_BUTTON_DPAD_RIGHT: "D-PAD RIGHT"}


## Short label for an input event ("W", "LMB", "RT", "D-PAD DOWN").
static func event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if e is InputEventMouseButton:
		return {1: "LMB", 2: "RMB", 3: "MMB", 4: "WHEEL UP", 5: "WHEEL DOWN", 6: "WHEEL LEFT", 7: "WHEEL RIGHT", 8: "MOUSE 4", 9: "MOUSE 5"}.get(int((e as InputEventMouseButton).button_index), "MOUSE")
	if e is InputEventJoypadButton:
		return PAD_NAMES.get(int((e as InputEventJoypadButton).button_index), "BUTTON %d" % (e as InputEventJoypadButton).button_index)
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
				return "L-STICK"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				return "R-STICK"
	return "?"


## The current keyboard/mouse or gamepad binding of an action, for prompts and the controls list.
static func binding_name(action: String, pad: bool) -> String:
	if not InputMap.has_action(action):
		return "—"
	for e in InputMap.action_get_events(action):
		if is_pad(e) == pad:
			return event_name(e)
	return "—"
