class_name MobileTouchController
extends Control

## Precision button-free mobile touch controller for Strings & Steel.
##
## Screen stays 100% clean (0 opacity) until touched:
## - Left Wheel (< 45% screen width): Floating-origin analog movement stick
##     * Hold / slide left & right: Smooth analog walk (re-centers dynamically so reversing is instant; NEVER auto-parries!)
##     * Quick horizontal flick & release (or double-tap): Dash
##     * Quick downward flick & release: Push Kick
##     * Quick upward flick & release: Toggle Half-Sword stance
## - Right Wheel (>= 45% screen width): 360-degree Shoulder-Centered Blade Stick
##     * Drag / whip across any arc: Live 2-bone IK sword aim, slash & cleave (with release follow-through!)
##     * Drive / flick toward rival: Point Thrust
##     * Pull into Rear Guard Arc (away from rival, or hold 2nd finger): High / Low Parry -> whip forward to Riposte!
##     * Quick tap: Instant Slash (High / Low by tap height, or Gauntlet Jab when unarmed)
##     * Two-finger flick: Hurl Weapon

var player: FighterController
var enabled: bool = false

const SPLIT_FRAC := 0.45
const TOP_SAFE_Y := 92.0
const LEFT_RADIUS := 78.0
const LEFT_DEADZONE := 14.0
const RIGHT_RADIUS := 88.0
const RIGHT_DEADZONE := 13.0
const MAX_OPACITY := 0.38

# Left floating movement stick state
var _left_idx: int = -1
var _left_start: Vector2 = Vector2.ZERO
var _left_origin: Vector2 = Vector2(200, 520)
var _left_pos: Vector2 = Vector2(200, 520)
var _left_vel: Vector2 = Vector2.ZERO
var _left_alpha: float = 0.0
var _left_touch_time: float = 0.0
var _left_max_travel: float = 0.0
var _last_left_dir_tap_ms: int = -9999
var _last_left_dir_sign: float = 0.0

# Right 360° blade wheel state
var _right_idx: int = -1
var _right_origin: Vector2 = Vector2(1040, 470)
var _right_pos: Vector2 = Vector2(1040, 470)
var _right_vel: Vector2 = Vector2.ZERO
var _right_peak_vel: Vector2 = Vector2.ZERO
var _right_alpha: float = 0.0
var _right_touch_time: float = 0.0
var _right_max_travel: float = 0.0
var _right_engaged: bool = false
var _right_parrying: bool = false
var _right_trail: Array[Vector2] = []

# Post-release blade follow-through so short thumb flicks complete their swing arc
var _follow_timer: float = 0.0
var _follow_vel_world: Vector2 = Vector2.ZERO

# Secondary right finger (2-finger weapon throw or stationary parry hold)
var _right_alt_idx: int = -1
var _right_alt_origin: Vector2 = Vector2.ZERO
var _right_alt_pos: Vector2 = Vector2.ZERO
var _right_alt_thrown: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_active(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	visible = on
	if not on:
		reset_touches()


func reset_touches() -> void:
	_left_idx = -1
	_right_idx = -1
	_right_alt_idx = -1
	_right_parrying = false
	_follow_timer = 0.0
	_right_trail.clear()
	if player != null and is_instance_valid(player):
		player.touch_move = 0.0
		player.touch_parry = false
		player.touch_low = false
		if not enabled:
			player.aim_override_enabled = false


func _can_control() -> bool:
	return enabled and visible and player != null and is_instance_valid(player) and player.input_enabled and not player.is_dead and not get_tree().paused


func _input(event: InputEvent) -> void:
	if not _can_control():
		if _left_idx != -1 or _right_idx != -1 or _right_alt_idx != -1:
			reset_touches()
		return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_on_finger_down(st.index, st.position)
		else:
			_on_finger_up(st.index, st.position)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_on_finger_drag(sd.index, sd.position, sd.velocity)
	# Desktop preview fallback when Touch: ON is tested on a non-touch PC
	elif not DisplayServer.is_touchscreen_available():
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_on_finger_down(99, mb.position)
				else:
					_on_finger_up(99, mb.position)
		elif event is InputEventMouseMotion and (_left_idx == 99 or _right_idx == 99):
			var mm := event as InputEventMouseMotion
			_on_finger_drag(99, mm.position, mm.velocity)


func _on_finger_down(idx: int, pos: Vector2) -> void:
	if pos.y < TOP_SAFE_Y:
		return
	var vp_w := maxf(640.0, get_viewport_rect().size.x)
	if pos.x < vp_w * SPLIT_FRAC:
		if _left_idx == -1:
			_left_idx = idx
			_left_start = pos
			_left_origin = pos
			_left_pos = pos
			_left_vel = Vector2.ZERO
			_left_touch_time = 0.0
			_left_max_travel = 0.0
			_sync_left_outputs()
	else:
		if _right_idx == -1:
			_right_idx = idx
			_right_origin = pos
			_right_pos = pos
			_right_vel = Vector2.ZERO
			_right_peak_vel = Vector2.ZERO
			_right_touch_time = 0.0
			_right_max_travel = 0.0
			_right_engaged = false
			_follow_timer = 0.0
			_right_trail.clear()
			_right_trail.append(pos)
			# Keep current sword posture until thumb moves past deadzone (no touchdown snap!)
			if player != null and not player.aim_override_enabled:
				player.aim_override_enabled = true
				player.aim_override = player.global_position + Vector2(float(player.facing) * 135.0, -116.0)
		elif _right_alt_idx == -1 and idx != _right_idx:
			_right_alt_idx = idx
			_right_alt_origin = pos
			_right_alt_pos = pos
			_right_alt_thrown = false


func _on_finger_drag(idx: int, pos: Vector2, vel: Vector2) -> void:
	if idx == _left_idx:
		_left_pos = pos
		_left_vel = vel
		var total_d := _left_pos - _left_start
		_left_max_travel = maxf(_left_max_travel, total_d.length())
		# Dynamic floating-origin follow: if thumb slides past LEFT_RADIUS, pull the wheel origin along
		# so reversing thumb direction immediately reverses movement with zero dead travel!
		var stick_d := _left_pos - _left_origin
		if stick_d.length() > LEFT_RADIUS:
			_left_origin = _left_pos - stick_d.normalized() * LEFT_RADIUS
		_sync_left_outputs()
	elif idx == _right_idx:
		_right_pos = pos
		_right_vel = vel
		if vel.length_squared() > _right_peak_vel.length_squared():
			_right_peak_vel = vel
		var rel := _right_pos - _right_origin
		_right_max_travel = maxf(_right_max_travel, rel.length())
		if rel.length() >= RIGHT_DEADZONE:
			_right_engaged = true
		# Soft floating follow if thumb sweeps far past wheel rim so continuous figure-8 cuts stay effortless
		var max_rim := RIGHT_RADIUS * 1.30
		if rel.length() > max_rim:
			_right_origin = _right_pos - rel.normalized() * max_rim
		_right_trail.append(pos)
		if _right_trail.size() > 10:
			_right_trail.pop_front()
		_sync_right_aim()
	elif idx == _right_alt_idx:
		_right_alt_pos = pos
		var alt_d := _right_alt_pos - _right_alt_origin
		if not _right_alt_thrown and alt_d.length() > 44.0 and vel.length() > 540.0 and player != null:
			_right_alt_thrown = true
			var throw_tgt := player.global_position + Vector2(alt_d.x * 3.0, -112.0 + alt_d.y * 2.2)
			player.throw_weapon(throw_tgt)


func _on_finger_up(idx: int, pos: Vector2) -> void:
	if idx == _left_idx:
		var total_d := pos - _left_start
		# Deliberate quick flick-and-release gestures on Left Wheel (never triggered while holding to walk!)
		if _left_touch_time <= 0.21 and total_d.length() >= 34.0 and player != null:
			if absf(total_d.x) > absf(total_d.y) * 1.35:
				player.start_dash(1.0 if total_d.x > 0.0 else -1.0)
			elif total_d.y >= 38.0 and total_d.y > absf(total_d.x) * 1.25:
				player.start_attack("kick")
			elif total_d.y <= -38.0 and absf(total_d.y) > absf(total_d.x) * 1.25:
				player.toggle_half_sword()
		elif _left_touch_time <= 0.18 and total_d.length() < 24.0 and player != null:
			# Double-tap left/right half of left zone also dashes cleanly
			var now_ms := Time.get_ticks_msec()
			var tap_sign := 1.0 if pos.x >= _left_origin.x else -1.0
			if now_ms - _last_left_dir_tap_ms <= 260 and tap_sign == _last_left_dir_sign:
				player.start_dash(tap_sign)
				_last_left_dir_tap_ms = -9999
			else:
				_last_left_dir_tap_ms = now_ms
				_last_left_dir_sign = tap_sign
		_left_idx = -1
		if player != null:
			player.touch_move = 0.0
			player.touch_low = _right_parrying and player.touch_low
	elif idx == _right_idx:
		_handle_right_release(pos)
		_right_idx = -1
		_right_parrying = false
		_right_trail.clear()
		if _right_alt_idx == -1 and player != null:
			player.touch_parry = false
	elif idx == _right_alt_idx:
		_right_alt_idx = -1
		if not _right_parrying and player != null:
			player.touch_parry = false


func _handle_right_release(pos: Vector2) -> void:
	if player == null:
		return
	var vp_h := maxf(480.0, get_viewport_rect().size.y)
	# 1. Quick Tap on Right Side -> Intuitive Sword Slash (High / Low by tap height) or Jab when unarmed!
	if _right_touch_time <= 0.20 and _right_max_travel < 22.0 and _right_alt_idx == -1:
		if player.can_wield():
			var low_tap := pos.y > vp_h * 0.66
			player.start_attack("slash_low" if low_tap else "slash_high")
		else:
			player.start_jab()
		return

	# 2. Fast Short Flick & Release -> Carry follow-through momentum, and if IK hadn't armed a cut yet,
	#    fire the matching directional Thrust / High Slash / Low Slash so flicks NEVER feel ignored!
	var flick_d := pos - _right_origin
	var peak_spd := maxf(_right_vel.length(), _right_peak_vel.length())
	if _right_touch_time <= 0.22 and _right_max_travel >= 22.0 and peak_spd >= 420.0 and not _right_parrying:
		var use_v := _right_vel if _right_vel.length() > 240.0 else _right_peak_vel
		_follow_vel_world = use_v.limit_length(1500.0) * 1.55
		_follow_timer = 0.14
		if not player.is_blade_active() and player.current_action == "":
			if not player.can_wield():
				player.start_jab()
			else:
				var fwd := flick_d.x * float(player.facing)
				if fwd > 20.0 and absf(flick_d.y) < fwd * 0.58:
					player.start_attack("thrust")
				elif flick_d.y > 24.0 and pos.y > vp_h * 0.54:
					player.start_attack("slash_low")
				elif fwd > -10.0:
					player.start_attack("slash_high")


func _sync_left_outputs() -> void:
	if player == null:
		return
	if _left_idx == -1:
		player.touch_move = 0.0
		if not _right_parrying:
			player.touch_low = false
		return
	var d := _left_pos - _left_origin
	var raw_x := 0.0
	if absf(d.x) > LEFT_DEADZONE:
		raw_x = (d.x - signf(d.x) * LEFT_DEADZONE) / maxf(16.0, LEFT_RADIUS - LEFT_DEADZONE)
	player.touch_move = clampf(raw_x, -1.0, 1.0)
	if not _right_parrying:
		player.touch_low = d.y > 32.0


func _sync_right_aim() -> void:
	if player == null or _right_idx == -1:
		return
	var rel := _right_pos - _right_origin
	if not _right_engaged and rel.length() < RIGHT_DEADZONE:
		return

	var facing_f := float(player.facing)
	var forward_x := rel.x * facing_f
	var forward_vel := _right_vel.x * facing_f

	# Rear Guard Arc: pulling the right wheel backward (away from the opponent) raises High or Low Parry!
	# Whipping forward immediately releases Parry with zero re-arm delay for an instant Riposte!
	var in_rear_guard := forward_x < -26.0 and absf(rel.y) <= absf(forward_x) * 1.48 and forward_vel < 280.0
	if in_rear_guard and player.can_feint_to_parry():
		_right_parrying = true
		player.touch_parry = true
		player.touch_low = rel.y > 16.0
	else:
		if _right_parrying:
			_right_parrying = false
			player._cursor_rearm_timer = 0.0
		if _right_alt_idx == -1:
			player.touch_parry = false

	var norm := rel / RIGHT_RADIUS
	if norm.length() > 1.30:
		norm = norm.normalized() * 1.30
	# Center of wheel = fighter's upper chest/shoulder so 360° wheel = full 360° sword reach!
	var shoulder_center := player.global_position + Vector2(facing_f * 54.0, -118.0)
	var target_w := shoulder_center + Vector2(norm.x * 192.0, norm.y * 178.0)
	target_w.x = clampf(target_w.x, 40.0, 1240.0)
	target_w.y = clampf(target_w.y, 118.0, 565.0)
	player.aim_override_enabled = true
	player.aim_override = target_w


func _process(delta: float) -> void:
	if not enabled:
		return
	if _left_idx != -1:
		_left_touch_time += delta
		_left_alpha = move_toward(_left_alpha, MAX_OPACITY, 3.6 * delta)
		_sync_left_outputs()
	else:
		_left_alpha = move_toward(_left_alpha, 0.0, 2.0 * delta)

	if _right_idx != -1:
		_right_touch_time += delta
		_right_alpha = move_toward(_right_alpha, MAX_OPACITY + 0.04, 3.8 * delta)
		_sync_right_aim()
		# Holding a second stationary finger on the right side also parries cleanly
		if _right_alt_idx != -1 and not _right_alt_thrown and player != null:
			if (_right_alt_pos - _right_alt_origin).length() < 28.0:
				player.touch_parry = true
	else:
		_right_alpha = move_toward(_right_alpha, 0.0, 2.0 * delta)
		if _follow_timer > 0.0 and player != null and player.aim_override_enabled:
			_follow_timer = maxf(0.0, _follow_timer - delta)
			player.aim_override = Vector2(
				clampf(player.aim_override.x + _follow_vel_world.x * delta, 40.0, 1240.0),
				clampf(player.aim_override.y + _follow_vel_world.y * delta, 118.0, 565.0)
			)
			_follow_vel_world *= exp(-8.0 * delta)

	if _left_alpha > 0.005 or _right_alpha > 0.005:
		queue_redraw()


func _draw() -> void:
	# 1. Left Translucent Floating Movement Stick
	if _left_alpha > 0.005:
		var a := _left_alpha
		var rim_col := Color(0.96, 0.86, 0.56, a * 0.88)
		var fill_col := Color(0.07, 0.05, 0.06, a * 0.48)
		draw_circle(_left_origin, LEFT_RADIUS, fill_col)
		draw_arc(_left_origin, LEFT_RADIUS, 0.0, TAU, 44, rim_col, 2.0, true)
		draw_arc(_left_origin, LEFT_DEADZONE, 0.0, TAU, 20, Color(0.96, 0.86, 0.56, a * 0.30), 1.2, true)
		# Directional notches (left/right walk/dash, up half-sword, down kick)
		for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(_left_origin + dir * (LEFT_RADIUS - 11.0), _left_origin + dir * (LEFT_RADIUS - 3.0), rim_col, 1.6)
		var puck_l := _left_origin + (_left_pos - _left_origin).limit_length(LEFT_RADIUS)
		draw_line(_left_origin, puck_l, Color(0.98, 0.88, 0.62, a * 0.65), 1.6, true)
		draw_circle(puck_l, 18.0, Color(0.98, 0.90, 0.68, a * 0.92))
		draw_arc(puck_l, 18.0, 0.0, TAU, 22, rim_col, 1.8, true)

	# 2. Right Translucent 360° Blade & Rear-Parry Wheel
	if _right_alpha > 0.005:
		var a2 := _right_alpha
		var is_guard := player != null and player.touch_parry
		var rim2 := Color(0.96, 0.86, 0.56, a2 * 0.88)
		var fill2 := Color(0.07, 0.05, 0.06, a2 * 0.44)
		draw_circle(_right_origin, RIGHT_RADIUS, fill2)
		draw_arc(_right_origin, RIGHT_RADIUS, 0.0, TAU, 48, rim2, 2.0, true)
		draw_arc(_right_origin, RIGHT_RADIUS * 0.38, 0.0, TAU, 24, Color(0.96, 0.86, 0.56, a2 * 0.28), 1.2, true)

		# Highlight the Rear Guard (Parry) Arc on the back rim facing away from the opponent!
		var facing_f := float(player.facing) if player != null else 1.0
		var rear_center := PI if facing_f >= 0.0 else 0.0
		var guard_col := Color(1.0, 0.88, 0.36, minf(0.85, a2 * 2.1)) if is_guard else Color(0.68, 0.84, 1.0, a2 * 1.15)
		draw_arc(_right_origin, RIGHT_RADIUS - 3.0, rear_center - 0.92, rear_center + 0.92, 24, guard_col, 4.2 if is_guard else 2.8, true)

		# Swipe velocity ribbon inside the blade wheel
		if _right_trail.size() >= 2:
			for i in range(_right_trail.size() - 1):
				var f := float(i + 1) / float(_right_trail.size())
				draw_line(_right_trail[i], _right_trail[i + 1], Color(1.0, 0.90, 0.52, a2 * 1.2 * f), 3.0 * f, true)

		var puck_r := _right_origin + (_right_pos - _right_origin).limit_length(RIGHT_RADIUS * 1.18)
		draw_line(_right_origin, puck_r, Color(0.98, 0.90, 0.64, a2 * 0.70), 1.6, true)
		draw_circle(puck_r, 19.0, guard_col if is_guard else Color(1.0, 0.92, 0.72, a2 * 0.95))
		draw_arc(puck_r, 19.0, 0.0, TAU, 24, rim2, 1.8, true)
