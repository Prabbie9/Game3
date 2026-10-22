class_name InputPrompts
extends RefCounted
## Button prompt text for the active input device (keyboard/mouse or gamepad).

const PAD := {"interact": "Y", "jump": "A", "sprint": "A", "aim": "LT", "fire": "RT", "reload": "B",
	"accelerate": "RT", "brake": "LT", "handbrake": "RB", "pause": "START", "map": "D-PAD DOWN"}


static func prompt(action: String) -> String:
	if Game.using_gamepad:
		return "[%s]" % PAD.get(action, action.to_upper())
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return "[%s]" % OS.get_keycode_string(e.physical_keycode)
		if e is InputEventMouseButton:
			return "[%s]" % ["", "LMB", "RMB", "MMB"][clampi(e.button_index, 0, 3)]
	return "[%s]" % action.to_upper()
