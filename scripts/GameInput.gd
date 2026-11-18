class_name GameInput
extends RefCounted

## Registers the game's InputMap actions at startup.
## Letter keys bind by *physical* position, so the WASD layout also works on AZERTY/QWERTZ.
## Because everything goes through InputMap, bindings can later be remapped
## (e.g. from a settings menu) without touching gameplay code.

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"guard_low": [KEY_S, KEY_DOWN],
	"dash": [KEY_SHIFT, KEY_UP],
	"slash": [KEY_J],
	"thrust": [KEY_K],
	"kick": [KEY_E],
	"parry": [KEY_SPACE],
	"half_sword": [KEY_Q],
	"throw_weapon": [KEY_F],
	"restart": [KEY_R],
	"pause": [KEY_ESCAPE, KEY_P],
}

const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"guard_low": [JOY_BUTTON_DPAD_DOWN],
	"dash": [JOY_BUTTON_DPAD_UP, JOY_BUTTON_LEFT_STICK],
	"slash": [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
	"thrust": [JOY_BUTTON_Y],
	"kick": [JOY_BUTTON_A],
	"parry": [JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER],
	"half_sword": [JOY_BUTTON_RIGHT_STICK],
	"restart": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}

# [axis, direction]
const PAD_AXES := {
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"guard_low": [[JOY_AXIS_LEFT_Y, 1.0]],
	"dash": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"parry": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
}

const DEADZONES := {
	"move_left": 0.22,
	"move_right": 0.22,
	"guard_low": 0.45,
	"dash": 0.4,
	"parry": 0.35,
}

# Keys that should match by layout-independent physical position.
const PHYSICAL := [KEY_A, KEY_D, KEY_S, KEY_J, KEY_K, KEY_E, KEY_Q, KEY_F, KEY_R, KEY_P]


static func register() -> void:
	var names: Array = []
	for n in KEYS.keys():
		names.append(n)
	for n in PAD_BUTTONS.keys():
		if not names.has(n):
			names.append(n)

	for action in names:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, float(DEADZONES.get(action, 0.2)))
		for kc in KEYS.get(action, []):
			var ev := InputEventKey.new()
			if PHYSICAL.has(kc):
				ev.physical_keycode = kc
			else:
				ev.keycode = kc
			InputMap.action_add_event(action, ev)
		for btn in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			jb.device = -1
			InputMap.action_add_event(action, jb)
		for ax in PAD_AXES.get(action, []):
			var jm := InputEventJoypadMotion.new()
			jm.axis = ax[0]
			jm.axis_value = ax[1]
			jm.device = -1
			InputMap.action_add_event(action, jm)
