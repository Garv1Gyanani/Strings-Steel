class_name MobileTouchController
extends Control

## Ultra-snappy (<40 ms response), button-free mobile touch controller for Strings & Steel.
##
## Screen stays 100% clean (0 opacity) until touched:
## - Left Stick (< 45% screen width): Snappy 38 px full-speed analog walk + floating follow
##     * Slide left & right: Instant full-speed response & zero-lag direction reversal (never auto-parries!)
##     * Fast fresh horizontal flick (fires MID-SWIPE in ~35 ms, no finger lift needed!): Dash
##     * Fast fresh downward flick (fires MID-SWIPE): Push Kick
##     * Fast fresh upward flick (fires MID-SWIPE): Toggle Half-Sword stance
## - Right 360° Blade Wheel (>= 45% screen width): Hybrid Instant Whip Strikes + 1-to-1 Live IK + Rear Parry
##     * Fast whip forward / diagonal / high / low (fires MID-SWIPE in ~35 ms!): Instant Thrust / High Slash / Low Slash
##       (re-anchors automatically so you can chain combos without lifting your thumb!)
##     * Smooth drag (< 680 px/s): Zero-lag 1-to-1 live 2-bone IK sword aiming & sweeping cuts
##     * Pull or flick into Rear Guard Arc (away from rival, or hold 2nd finger): Instant High / Low Parry -> whip forward to Riposte!
##     * Quick tap: Instant Sword Slash (High / Low by tap height, or Gauntlet Jab when unarmed)
##     * Two-finger flick: Hurl Weapon

var player: FighterController
var enabled: bool = false

const SPLIT_FRAC := 0.45
const TOP_SAFE_Y := 92.0
const LEFT_DEADZONE := 7.0
const LEFT_FULL_SPAN := 32.0
const LEFT_FOLLOW_RADIUS := 42.0
const LEFT_DRAW_RADIUS := 68.0
const RIGHT_RADIUS := 82.0
const RIGHT_AIM_SPAN := 40.0
const RIGHT_DEADZONE := 6.0
const WHIP_SPEED_THRESHOLD := 960.0
const WHIP_DIST_THRESHOLD := 30.0
const MAX_OPACITY := 0.38

# Left stick state
var _left_idx: int = -1
var _left_start: Vector2 = Vector2.ZERO
var _left_origin: Vector2 = Vector2(200, 520)
var _left_pos: Vector2 = Vector2(200, 520)
var _left_prev_pos: Vector2 = Vector2(200, 520)
var _left_vel: Vector2 = Vector2.ZERO
var _left_alpha: float = 0.0
var _left_touch_time: float = 0.0
var _left_gesture_fired: bool = false
var _last_left_dir_tap_ms: int = -9999
var _last_left_dir_sign: float = 0.0

# Right 360° blade wheel state
var _right_idx: int = -1
var _right_origin: Vector2 = Vector2(1040, 470)
var _right_whip_anchor: Vector2 = Vector2(1040, 470)
var _right_pos: Vector2 = Vector2(1040, 470)
var _right_prev_pos: Vector2 = Vector2(1040, 470)
var _right_vel: Vector2 = Vector2.ZERO
var _right_alpha: float = 0.0
var _right_touch_time: float = 0.0
var _right_max_travel: float = 0.0
var _right_engaged: bool = false
var _right_parrying: bool = false
var _right_whip_cd: float = 0.0
var _right_fired_strike: bool = false
var _right_trail: Array[Vector2] = []

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
			_left_prev_pos = pos
			_left_vel = Vector2.ZERO
			_left_touch_time = 0.0
			_left_gesture_fired = false
			_sync_left_outputs()
	else:
		if _right_idx == -1:
			_right_idx = idx
			_right_origin = pos
			_right_whip_anchor = pos
			_right_pos = pos
			_right_prev_pos = pos
			_right_vel = Vector2.ZERO
			_right_touch_time = 0.0
			_right_max_travel = 0.0
			_right_engaged = false
			_right_fired_strike = false
			_right_trail.clear()
			_right_trail.append(pos)
			if player != null and not player.aim_override_enabled:
				player.aim_override_enabled = true
				player.aim_override = player.global_position + Vector2(float(player.facing) * 135.0, -116.0)
		elif _right_alt_idx == -1 and idx != _right_idx:
			_right_alt_idx = idx
			_right_alt_origin = pos
			_right_alt_pos = pos
			_right_alt_thrown = false


func _on_finger_drag(idx: int, pos: Vector2, raw_vel: Vector2) -> void:
	var dt := maxf(0.008, get_process_delta_time())
	if idx == _left_idx:
		var inst_v := (pos - _left_prev_pos) / dt
		_left_prev_pos = pos
		_left_pos = pos
		_left_vel = raw_vel if raw_vel.length_squared() > 1.0 else inst_v
		var total_d := _left_pos - _left_start

		# Instant mid-flick gestures on fresh touch (<= 0.13s) — fires in ~35ms WITHOUT waiting for finger lift!
		# Once holding > 0.13s to walk, sliding NEVER triggers accidental dashes!
		if not _left_gesture_fired and _left_touch_time > 0.001 and _left_touch_time <= 0.13 and player != null:
			var face_f := float(player.facing)
			if total_d.y <= -26.0 and total_d.x * face_f >= 24.0 and _left_vel.length() >= 680.0:
				player.start_attack("jump_slash")
				_left_gesture_fired = true
			elif total_d.y >= 26.0 and total_d.x * face_f >= 24.0 and _left_vel.length() >= 680.0:
				player.start_attack("leg_sweep")
				_left_gesture_fired = true
			elif absf(total_d.x) >= 28.0 and absf(_left_vel.x) >= 780.0 and absf(total_d.x) > absf(total_d.y) * 1.35:
				player.start_dash(1.0 if total_d.x > 0.0 else -1.0)
				_left_gesture_fired = true
			elif total_d.y >= 32.0 and _left_vel.y >= 700.0 and total_d.y > absf(total_d.x) * 1.25:
				player.start_attack("kick")
				_left_gesture_fired = true
			elif total_d.y <= -32.0 and _left_vel.y <= -700.0 and absf(total_d.y) > absf(total_d.x) * 1.25:
				player.toggle_half_sword()
				_left_gesture_fired = true

		# Tight floating-origin follow (44 px) so reversing thumb direction reverses walking on frame 1!
		var stick_d := _left_pos - _left_origin
		if stick_d.length() > LEFT_FOLLOW_RADIUS:
			_left_origin = _left_pos - stick_d.normalized() * LEFT_FOLLOW_RADIUS
		_sync_left_outputs()

	elif idx == _right_idx:
		var inst_rv := (pos - _right_prev_pos) / dt
		_right_prev_pos = pos
		_right_pos = pos
		_right_vel = raw_vel if raw_vel.length_squared() > 1.0 else inst_rv
		var rel := _right_pos - _right_origin
		_right_max_travel = maxf(_right_max_travel, rel.length())
		if rel.length() >= RIGHT_DEADZONE:
			_right_engaged = true
		var max_rim := RIGHT_RADIUS * 1.25
		if rel.length() > max_rim:
			_right_origin = _right_pos - rel.normalized() * max_rim
		_right_trail.append(pos)
		if _right_trail.size() > 10:
			_right_trail.pop_front()
		_sync_right_aim()
		_check_instant_right_whip()

	elif idx == _right_alt_idx:
		_right_alt_pos = pos
		var alt_d := _right_alt_pos - _right_alt_origin
		if not _right_alt_thrown and alt_d.length() > 40.0 and raw_vel.length() > 500.0 and player != null:
			_right_alt_thrown = true
			var throw_tgt := player.global_position + Vector2(alt_d.x * 3.0, -112.0 + alt_d.y * 2.2)
			player.throw_weapon(throw_tgt)


func _check_instant_right_whip() -> void:
	if player == null or _right_parrying or _right_whip_cd > 0.0:
		return
	var whip_d := _right_pos - _right_whip_anchor
	var spd := _right_vel.length()
	if spd < 220.0:
		# Re-anchor smoothly whenever the thumb pauses so chained whips stay crisp!
		_right_whip_anchor = _right_whip_anchor.lerp(_right_pos, 0.35)
		return
	if whip_d.length() < WHIP_DIST_THRESHOLD or spd < WHIP_SPEED_THRESHOLD:
		return
	var facing_f := float(player.facing)
	var fwd_d := whip_d.x * facing_f
	var fwd_v := _right_vel.x * facing_f
	# Backward flicks are Parries (handled in _sync_right_aim), never wasted attacks!
	if fwd_v < -220.0 and absf(whip_d.y) < absf(whip_d.x) * 1.3:
		return
	if player.current_action != "":
		return
	# Vertical & diagonal swipes stay in zero-windup (0 ms!) 1-to-1 Live 2-Bone IK so the sword
	# never detaches from your thumb! Pure horizontal forward whips trigger a lunging Thrust
	# (or Gauntlet Jab when unarmed) mid-swipe without waiting for finger lift.
	var fired := false
	if not player.can_wield():
		if fwd_d > 14.0 or absf(whip_d.y) > 22.0:
			fired = player.start_jab()
	elif fwd_d >= 28.0 and absf(whip_d.y) < fwd_d * 0.22 and fwd_v >= 920.0:
		fired = player.start_attack("thrust")
	if fired:
		_right_fired_strike = true
		_right_whip_cd = 0.22
		_right_whip_anchor = _right_pos


func _on_finger_up(idx: int, pos: Vector2) -> void:
	if idx == _left_idx:
		var total_d := pos - _left_start
		# Fallback on finger release (for low-rate touchscreens or deliberate flick-lifts)
		if not _left_gesture_fired and _left_touch_time <= 0.21 and total_d.length() >= 30.0 and player != null:
			if absf(total_d.x) > absf(total_d.y) * 1.35:
				player.start_dash(1.0 if total_d.x > 0.0 else -1.0)
			elif total_d.y >= 34.0 and total_d.y > absf(total_d.x) * 1.25:
				player.start_attack("kick")
			elif total_d.y <= -34.0 and absf(total_d.y) > absf(total_d.x) * 1.25:
				player.toggle_half_sword()
		elif not _left_gesture_fired and _left_touch_time <= 0.18 and total_d.length() < 22.0 and player != null:
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
		# Quick Tap on Right Side -> Dash-Cleave / Spin-Slash when dashing, or Instant 3-Hit Combo Slash / Jab!
		if not _right_fired_strike and _right_touch_time <= 0.21 and _right_max_travel < 22.0 and _right_alt_idx == -1 and player != null:
			var vp_h := maxf(480.0, get_viewport_rect().size.y)
			if player.can_wield():
				if player.dash_timer > 0.0:
					player.start_attack("jump_slash" if player.dash_dir * float(player.facing) > 0.0 else "backstep_cut")
				else:
					player.start_attack("slash_low" if pos.y > vp_h * 0.65 else "slash_high")
			else:
				player.start_jab()
		_right_idx = -1
		_right_parrying = false
		_right_trail.clear()
		if _right_alt_idx == -1 and player != null:
			player.touch_parry = false
	elif idx == _right_alt_idx:
		if not _right_alt_thrown and (pos - _right_alt_origin).length() < 24.0 and _right_parrying and player != null and player.can_wield():
			player.touch_parry = false
			_right_parrying = false
			player.start_attack("mordhau_smash" if player.half_swording else "pommel_strike")
		_right_alt_idx = -1
		if not _right_parrying and player != null:
			player.touch_parry = false


func _sync_left_outputs() -> void:
	if player == null:
		return
	if _left_idx == -1:
		player.touch_move = 0.0
		if not _right_parrying:
			player.touch_low = false
		return
	var d := _left_pos - _left_origin
	var mv := 0.0
	if absf(d.x) > LEFT_DEADZONE:
		var lin := clampf((absf(d.x) - LEFT_DEADZONE) / LEFT_FULL_SPAN, 0.0, 1.0)
		# Snappy power curve: small thumb shifts give crisp immediate movement, ~38px hits 100% run speed!
		mv = signf(d.x) * pow(lin, 0.70)
	player.touch_move = mv
	if not _right_parrying:
		player.touch_low = d.y > 28.0


func _sync_right_aim() -> void:
	if player == null or _right_idx == -1:
		return
	var rel := _right_pos - _right_origin
	if not _right_engaged and rel.length() < RIGHT_DEADZONE:
		return

	var facing_f := float(player.facing)
	var forward_x := rel.x * facing_f
	var forward_vel := _right_vel.x * facing_f

	# Rear Guard Arc + Reflex Pull-Back Parry:
	# Pulling straight backward (away from rival) snaps into Parry, NEVER hijacking vertical/diagonal slashes!
	var held_rear := forward_x < -26.0 and absf(rel.y) <= absf(forward_x) * 0.85 and absf(_right_vel.y) < 220.0 and forward_vel < 160.0
	var reflex_pull := forward_vel < -460.0 and forward_x < -12.0 and absf(_right_vel.y) < absf(_right_vel.x) * 0.90
	if (held_rear or reflex_pull) and player.can_feint_to_parry():
		_right_parrying = true
		player.touch_parry = true
		player.touch_low = rel.y > 14.0
		_right_whip_anchor = _right_pos
	else:
		if _right_parrying:
			_right_parrying = false
			player._cursor_rearm_timer = 0.0
			_right_whip_anchor = _right_pos
		if _right_alt_idx == -1:
			player.touch_parry = false

	var norm := rel / RIGHT_AIM_SPAN
	if norm.length() > 1.55:
		norm = norm.normalized() * 1.55
	var guard_center := player.global_position + Vector2(facing_f * 132.0, -122.0)
	var vert_commit := minf(1.0, absf(norm.y) * 0.95)
	var eff_nx := maxf(-0.20 * facing_f, norm.x) if (facing_f > 0.0 and not _right_parrying and absf(norm.y) > 0.45 and forward_x < 0.0) else (minf(0.20, norm.x) if (facing_f < 0.0 and not _right_parrying and absf(norm.y) > 0.45 and forward_x < 0.0) else norm.x)
	var reach_x := eff_nx * (168.0 if forward_x >= 0.0 else 92.0) + (facing_f * 96.0 * vert_commit if not _right_parrying else 0.0)
	var target_w := guard_center + Vector2(reach_x, norm.y * 228.0)
	target_w.x = clampf(target_w.x, 40.0, 1240.0)
	target_w.y = clampf(target_w.y, 75.0, 585.0)
	player.aim_override_enabled = true
	player.aim_override = target_w


func _process(delta: float) -> void:
	if not enabled:
		return
	_right_whip_cd = maxf(0.0, _right_whip_cd - delta)
	if _left_idx != -1:
		_left_touch_time += delta
		_left_alpha = move_toward(_left_alpha, MAX_OPACITY, 4.2 * delta)
		_sync_left_outputs()
	else:
		_left_alpha = move_toward(_left_alpha, 0.0, 2.2 * delta)

	if _right_idx != -1:
		_right_touch_time += delta
		_right_alpha = move_toward(_right_alpha, MAX_OPACITY + 0.04, 4.2 * delta)
		_sync_right_aim()
		if _right_alt_idx != -1 and not _right_alt_thrown and player != null:
			if (_right_alt_pos - _right_alt_origin).length() < 28.0:
				player.touch_parry = true
	else:
		_right_alpha = move_toward(_right_alpha, 0.0, 2.2 * delta)

	if _left_alpha > 0.005 or _right_alpha > 0.005:
		queue_redraw()


func _draw() -> void:
	# 1. Left Translucent Floating Movement Stick
	if _left_alpha > 0.005:
		var a := _left_alpha
		var rim_col := Color(0.96, 0.86, 0.56, a * 0.88)
		var fill_col := Color(0.07, 0.05, 0.06, a * 0.48)
		draw_circle(_left_origin, LEFT_DRAW_RADIUS, fill_col)
		draw_arc(_left_origin, LEFT_DRAW_RADIUS, 0.0, TAU, 44, rim_col, 2.0, true)
		draw_arc(_left_origin, LEFT_DEADZONE, 0.0, TAU, 20, Color(0.96, 0.86, 0.56, a * 0.30), 1.2, true)
		for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(_left_origin + dir * (LEFT_DRAW_RADIUS - 10.0), _left_origin + dir * (LEFT_DRAW_RADIUS - 3.0), rim_col, 1.6)
		var puck_l := _left_origin + (_left_pos - _left_origin).limit_length(LEFT_DRAW_RADIUS * 0.85)
		draw_line(_left_origin, puck_l, Color(0.98, 0.88, 0.62, a * 0.65), 1.6, true)
		draw_circle(puck_l, 17.0, Color(0.98, 0.90, 0.68, a * 0.94))
		draw_arc(puck_l, 17.0, 0.0, TAU, 22, rim_col, 1.8, true)

	# 2. Right Translucent 360° Blade & Rear-Parry Wheel
	if _right_alpha > 0.005:
		var a2 := _right_alpha
		var is_guard := player != null and player.touch_parry
		var rim2 := Color(0.96, 0.86, 0.56, a2 * 0.88)
		var fill2 := Color(0.07, 0.05, 0.06, a2 * 0.44)
		draw_circle(_right_origin, RIGHT_RADIUS, fill2)
		draw_arc(_right_origin, RIGHT_RADIUS, 0.0, TAU, 48, rim2, 2.0, true)
		draw_arc(_right_origin, RIGHT_RADIUS * 0.38, 0.0, TAU, 24, Color(0.96, 0.86, 0.56, a2 * 0.28), 1.2, true)

		var facing_f := float(player.facing) if player != null else 1.0
		var rear_center := PI if facing_f >= 0.0 else 0.0
		var guard_col := Color(1.0, 0.88, 0.36, minf(0.88, a2 * 2.2)) if is_guard else Color(0.68, 0.84, 1.0, a2 * 1.18)
		draw_arc(_right_origin, RIGHT_RADIUS - 3.0, rear_center - 0.98, rear_center + 0.98, 24, guard_col, 4.4 if is_guard else 3.0, true)

		if _right_trail.size() >= 2:
			for i in range(_right_trail.size() - 1):
				var f := float(i + 1) / float(_right_trail.size())
				draw_line(_right_trail[i], _right_trail[i + 1], Color(1.0, 0.90, 0.52, a2 * 1.25 * f), 3.0 * f, true)

		var puck_r := _right_origin + (_right_pos - _right_origin).limit_length(RIGHT_RADIUS * 1.18)
		draw_line(_right_origin, puck_r, Color(0.98, 0.90, 0.64, a2 * 0.70), 1.6, true)
		draw_circle(puck_r, 18.0, guard_col if is_guard else Color(1.0, 0.92, 0.72, a2 * 0.96))
		draw_arc(puck_r, 18.0, 0.0, TAU, 24, rim2, 1.8, true)
