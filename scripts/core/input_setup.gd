class_name InputSetup
extends RefCounted
## Default keyboard/mouse + gamepad bindings (defined in code so the rebinding menu can rewrite them).
## Gamepad: Xbox layout (Godot's JOY_BUTTON_A is the bottom face button, B right, X left, Y top). One button can
## serve both on foot and at the wheel: the game only reads each action where it applies.

const KEYS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "crouch": [KEY_C], "walk_toggle": [KEY_ALT],
	"interact": [KEY_F], "reload": [KEY_R], "cover": [KEY_Q], "shoulder_swap": [],
	"accelerate": [KEY_W], "brake": [KEY_S], "steer_left": [KEY_A], "steer_right": [KEY_D],
	"handbrake": [KEY_SPACE], "horn": [KEY_H], "headlights": [KEY_L], "camera_mode": [KEY_V],
	"indicator_left": [KEY_Z], "indicator_right": [KEY_X], "hazards": [KEY_B], "look_behind": [KEY_E],
	"ascend": [KEY_SPACE], "descend": [KEY_CTRL], "radio_next": [KEY_PERIOD], "radio_prev": [KEY_COMMA],
	"pause": [KEY_ESCAPE], "perf_overlay": [KEY_F3], "god_mode": [KEY_F1], "map": [KEY_M],
	"weapon_next": [], "weapon_prev": [], "weapon_wheel": [KEY_TAB],
}
const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT], "aim": [MOUSE_BUTTON_RIGHT], "vehicle_fire": [MOUSE_BUTTON_LEFT], "vehicle_aim": [MOUSE_BUTTON_RIGHT], "shoulder_swap": [MOUSE_BUTTON_MIDDLE],
	"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN], "weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}
const PAD_BUTTONS := {
	# on foot
	"jump": [JOY_BUTTON_X], "sprint": [JOY_BUTTON_A], "crouch": [JOY_BUTTON_LEFT_STICK],
	"interact": [JOY_BUTTON_Y], "reload": [JOY_BUTTON_B], "shoulder_swap": [JOY_BUTTON_RIGHT_STICK], "cover": [JOY_BUTTON_RIGHT_SHOULDER],
	"weapon_next": [JOY_BUTTON_DPAD_RIGHT], "weapon_prev": [JOY_BUTTON_DPAD_LEFT], "weapon_wheel": [JOY_BUTTON_LEFT_SHOULDER],
	# at the wheel (Y gets out, RT / LT drive)
	"handbrake": [JOY_BUTTON_RIGHT_SHOULDER], "horn": [JOY_BUTTON_LEFT_STICK], "look_behind": [JOY_BUTTON_RIGHT_STICK],
	"headlights": [JOY_BUTTON_DPAD_UP], "radio_prev": [JOY_BUTTON_DPAD_LEFT], "radio_next": [JOY_BUTTON_DPAD_RIGHT],
	"hazards": [JOY_BUTTON_B], "indicator_pad": [JOY_BUTTON_A], "camera_mode": [JOY_BUTTON_BACK],
	"vehicle_aim": [JOY_BUTTON_LEFT_SHOULDER], "vehicle_fire": [JOY_BUTTON_X],
	"ascend": [JOY_BUTTON_RIGHT_SHOULDER], "descend": [JOY_BUTTON_LEFT_SHOULDER],
	# anywhere
	"pause": [JOY_BUTTON_START], "map": [JOY_BUTTON_DPAD_DOWN],
}
## action -> [axis, direction]
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"steer_left": [JOY_AXIS_LEFT_X, -1.0], "steer_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0], "fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}


static func apply_defaults() -> void:
	var actions := {}
	for d in [KEYS, MOUSE, PAD_BUTTONS, PAD_AXES]:
		for a in d:
			actions[a] = true
	for a in actions:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		else:
			InputMap.action_erase_events(a)
		for k in KEYS.get(a, []):
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for b in MOUSE.get(a, []):
			var e := InputEventMouseButton.new()
			e.button_index = b
			InputMap.action_add_event(a, e)
		for b in PAD_BUTTONS.get(a, []):
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(a, e)
		if PAD_AXES.has(a):
			var e := InputEventJoypadMotion.new()
			e.axis = PAD_AXES[a][0]
			e.axis_value = PAD_AXES[a][1]
			InputMap.action_add_event(a, e)
