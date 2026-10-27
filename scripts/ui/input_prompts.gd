class_name InputPrompts
extends RefCounted
## Button prompt text for the active input device (keyboard/mouse or gamepad).

const PAD := {"interact": "Y", "jump": "X", "sprint": "A", "aim": "LT", "fire": "RT", "reload": "B",
	"accelerate": "RT", "brake": "LT", "handbrake": "RB", "pause": "MENU", "map": "D-PAD DOWN", "cover": "RB", "crouch": "LS",
	"ui_accept": "A", "ui_cancel": "B", "weapon_wheel": "LB", "weapon_next": "D-PAD RIGHT", "weapon_prev": "D-PAD LEFT",
	"shoulder_swap": "RS", "vehicle_aim": "LB", "vehicle_fire": "X", "radio_next": "D-PAD RIGHT", "radio_prev": "D-PAD LEFT",
	"look_behind": "RS", "headlights": "D-PAD UP", "hazards": "B", "indicator_pad": "A", "horn": "LS", "camera_mode": "VIEW"}


static func prompt(action: String) -> String:
	# the live binding (it follows rebinding in the settings); a few actions only exist on one device
	var name := Settings.binding_name(action, Game.using_gamepad)
	if name == "—":
		if Game.using_gamepad and PAD.has(action):
			return "[%s]" % PAD[action]
		return "[%s]" % action.to_upper()
	return "[%s]" % name
