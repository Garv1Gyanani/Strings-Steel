class_name MobileTouchController
extends Control

## Minimalist, button-free mobile touch controller for Strings & Steel.
##
## Screen stays 100% clean until touched:
## - Left side touch (< 44% width): spawns a translucent floating Movement & Guard wheel
##   at the touch point (fades out when lifted).
##     * Hold center (< 22 px): Parry / Perfect Parry (pull down slightly for Low Guard)
##     * Drag left / right: Analog walk
##     * Quick horizontal flick: Dash
##     * Double-tap: Toggle Half-Sword stance
## - Right side touch (>= 44% width): spawns a translucent floating Blade Wheel that drives
##   the 2-bone IK sword arm 1-to-1 in real time (fades out when lifted).
##     * Swipe an arc: Slash / Cleave (power scales with arc & speed)
##     * Push forward: Point Thrust
##     * Quick tap: Push Kick (or Gauntlet Jab / Buckler Bash when unarmed)
##     * Two-finger flick: Hurl Weapon

var player: FighterController
var enabled: bool = false

const SPLIT_FRAC := 0.44
const TOP_SAFE_Y := 94.0
const LEFT_RADIUS := 58.0
const LEFT_GUARD_DEADZONE := 22.0
const RIGHT_RADIUS := 68.0
const MAX_OPACITY := 0.36

# Left wheel state
var _left_idx: int = -1
var _left_origin: Vector2 = Vector2(180, 520)
var _left_pos: Vector2 = Vector2(180, 520)
var _left_alpha: float = 0.0
var _left_touch_time: float = 0.0
var _left_max_travel: float = 0.0
var _left_dash_cd: float = 0.0
var _last_left_tap_ms: int = -9999

# Right blade wheel state
var _right_idx: int = -1
var _right_origin: Vector2 = Vector2(1040, 480)
var _right_pos: Vector2 = Vector2(1040, 480)
var _right_alpha: float = 0.0
var _right_touch_time: float = 0.0
var _right_max_travel: float = 0.0
var _right_trail: Array[Vector2] = []

# Secondary right finger (for 2-finger weapon throw or 1-handed parry)
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
		if _left_idx != -1 or _right_idx != -1:
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
	# Desktop preview fallback: when Touch mode is enabled on a non-touch PC, let LMB test the wheels.
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
			var now_ms := Time.get_ticks_msec()
			if now_ms - _last_left_tap_ms <= 280 and player != null:
				player.toggle_half_sword()
				_last_left_tap_ms = -9999
			else:
				_last_left_tap_ms = now_ms
			_left_idx = idx
			_left_origin = pos
			_left_pos = pos
			_left_touch_time = 0.0
			_left_max_travel = 0.0
			_sync_left_outputs()
	else:
		if _right_idx == -1:
			_right_idx = idx
			_right_origin = pos
			_right_pos = pos
			_right_touch_time = 0.0
			_right_max_travel = 0.0
			_right_trail.clear()
			_right_trail.append(pos)
			_sync_right_aim()
		elif _right_alt_idx == -1 and idx != _right_idx:
			_right_alt_idx = idx
			_right_alt_origin = pos
			_right_alt_pos = pos
			_right_alt_thrown = false


func _on_finger_drag(idx: int, pos: Vector2, vel: Vector2) -> void:
	if idx == _left_idx:
		_left_pos = pos
		var delta_v := _left_pos - _left_origin
		_left_max_travel = maxf(_left_max_travel, delta_v.length())
		# Quick horizontal flick triggers Dash
		if _left_dash_cd <= 0.0 and absf(vel.x) > 760.0 and absf(delta_v.x) > 28.0 and absf(vel.x) > absf(vel.y) * 1.25:
			if player != null:
				player.start_dash(1.0 if vel.x > 0.0 else -1.0)
				_left_dash_cd = 0.32
		_sync_left_outputs()
	elif idx == _right_idx:
		_right_pos = pos
		var delta_r := _right_pos - _right_origin
		_right_max_travel = maxf(_right_max_travel, delta_r.length())
		_right_trail.append(pos)
		if _right_trail.size() > 9:
			_right_trail.pop_front()
		_sync_right_aim()
	elif idx == _right_alt_idx:
		_right_alt_pos = pos
		var alt_d := _right_alt_pos - _right_alt_origin
		if not _right_alt_thrown and alt_d.length() > 42.0 and vel.length() > 520.0 and player != null:
			_right_alt_thrown = true
			var throw_tgt := player.global_position + Vector2(alt_d.x * 3.0, -110.0 + alt_d.y * 2.2)
			player.throw_weapon(throw_tgt)


func _on_finger_up(idx: int, _pos: Vector2) -> void:
	if idx == _left_idx:
		_left_idx = -1
		if player != null:
			player.touch_move = 0.0
			player.touch_parry = false
			player.touch_low = false
	elif idx == _right_idx:
		# Crisp quick tap on the right side triggers Push Kick (or Gauntlet Jab if unarmed)!
		if _right_touch_time <= 0.19 and _right_max_travel < 20.0 and _right_alt_idx == -1 and player != null:
			if player.can_wield():
				player.start_attack("kick")
			else:
				player.start_jab()
		_right_idx = -1
		_right_trail.clear()
	elif idx == _right_alt_idx:
		_right_alt_idx = -1
		if _left_idx == -1 and player != null:
			player.touch_parry = false


func _sync_left_outputs() -> void:
	if player == null:
		return
	if _left_idx == -1:
		player.touch_move = 0.0
		player.touch_parry = false
		player.touch_low = false
		return
	var d := _left_pos - _left_origin
	var dist := d.length()
	if dist < LEFT_GUARD_DEADZONE and _left_max_travel < LEFT_GUARD_DEADZONE + 8.0:
		# Stationary hold in the wheel core = Parry!
		player.touch_move = 0.0
		player.touch_parry = true
		player.touch_low = d.y > 10.0
	else:
		player.touch_parry = false
		player.touch_low = d.y > 26.0
		var raw_x := 0.0
		if absf(d.x) > 14.0:
			raw_x = (d.x - signf(d.x) * 14.0) / (LEFT_RADIUS - 14.0)
		player.touch_move = clampf(raw_x, -1.0, 1.0)


func _sync_right_aim() -> void:
	if player == null or _right_idx == -1:
		return
	var rel := _right_pos - _right_origin
	var clamped_rel := rel.limit_length(RIGHT_RADIUS * 1.65)
	var base_chest := player.global_position + Vector2(float(player.facing) * 118.0, -112.0)
	var target_w := base_chest + Vector2(clamped_rel.x * 2.15, clamped_rel.y * 2.05)
	target_w.x = clampf(target_w.x, 40.0, 1240.0)
	target_w.y = clampf(target_w.y, 120.0, 565.0)
	player.aim_override_enabled = true
	player.aim_override = target_w


func _process(delta: float) -> void:
	if not enabled:
		return
	_left_dash_cd = maxf(0.0, _left_dash_cd - delta)
	if _left_idx != -1:
		_left_touch_time += delta
		_left_alpha = move_toward(_left_alpha, MAX_OPACITY, 3.2 * delta)
		_sync_left_outputs()
	else:
		_left_alpha = move_toward(_left_alpha, 0.0, 1.8 * delta)

	if _right_idx != -1:
		_right_touch_time += delta
		_right_alpha = move_toward(_right_alpha, MAX_OPACITY + 0.03, 3.4 * delta)
		_sync_right_aim()
		# Holding a second stationary finger on the right side also allows 1-handed Parry
		if _right_alt_idx != -1 and not _right_alt_thrown and _left_idx == -1 and player != null:
			if (_right_alt_pos - _right_alt_origin).length() < 26.0:
				player.touch_parry = true
	else:
		_right_alpha = move_toward(_right_alpha, 0.0, 1.8 * delta)

	if _left_alpha > 0.005 or _right_alpha > 0.005:
		queue_redraw()


func _draw() -> void:
	# 1. Left Translucent Movement & Parry Wheel (only visible while touched / fading)
	if _left_alpha > 0.005:
		var a := _left_alpha
		var is_guard := player != null and player.touch_parry
		var rim_col := Color(1.0, 0.86, 0.44, a * (1.25 if is_guard else 0.85))
		var fill_col := Color(0.08, 0.06, 0.07, a * 0.52)
		draw_circle(_left_origin, LEFT_RADIUS, fill_col)
		draw_arc(_left_origin, LEFT_RADIUS, 0.0, TAU, 40, rim_col, 2.0, true)
		# Inner guard ring
		var guard_col := Color(1.0, 0.88, 0.42, a * 1.35) if is_guard else Color(0.92, 0.84, 0.68, a * 0.48)
		draw_arc(_left_origin, LEFT_GUARD_DEADZONE, 0.0, TAU, 24, guard_col, 1.5, true)
		# Subtle left/right directional ticks
		draw_line(_left_origin + Vector2(-LEFT_RADIUS + 8, 0), _left_origin + Vector2(-LEFT_RADIUS + 16, 0), rim_col, 1.6)
		draw_line(_left_origin + Vector2(LEFT_RADIUS - 16, 0), _left_origin + Vector2(LEFT_RADIUS - 8, 0), rim_col, 1.6)
		var puck_l := _left_origin + (_left_pos - _left_origin).limit_length(LEFT_RADIUS)
		draw_line(_left_origin, puck_l, Color(0.95, 0.86, 0.62, a * 0.65), 1.4, true)
		draw_circle(puck_l, 15.0, Color(0.98, 0.90, 0.68, a * 0.95))
		draw_arc(puck_l, 15.0, 0.0, TAU, 20, rim_col, 1.6, true)

	# 2. Right Translucent Blade Wheel (only visible while touched / fading)
	if _right_alpha > 0.005:
		var a2 := _right_alpha
		var rim2 := Color(0.96, 0.86, 0.56, a2 * 0.90)
		var fill2 := Color(0.08, 0.06, 0.07, a2 * 0.46)
		draw_circle(_right_origin, RIGHT_RADIUS, fill2)
		draw_arc(_right_origin, RIGHT_RADIUS, 0.0, TAU, 44, rim2, 2.0, true)
		draw_arc(_right_origin, RIGHT_RADIUS * 0.42, 0.0, TAU, 24, Color(0.96, 0.86, 0.56, a2 * 0.35), 1.2, true)
		# Cardinal compass ticks around the blade wheel
		for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(_right_origin + dir * (RIGHT_RADIUS - 10.0), _right_origin + dir * (RIGHT_RADIUS - 3.0), rim2, 1.5)
		# Soft swipe ribbon inside the wheel
		if _right_trail.size() >= 2:
			for i in range(_right_trail.size() - 1):
				var f := float(i + 1) / float(_right_trail.size())
				draw_line(_right_trail[i], _right_trail[i + 1], Color(1.0, 0.90, 0.52, a2 * 1.15 * f), 2.8 * f, true)
		var puck_r := _right_origin + (_right_pos - _right_origin).limit_length(RIGHT_RADIUS * 1.15)
		draw_line(_right_origin, puck_r, Color(0.98, 0.90, 0.64, a2 * 0.68), 1.5, true)
		draw_circle(puck_r, 16.0, Color(1.0, 0.92, 0.72, a2 * 0.98))
		draw_arc(puck_r, 16.0, 0.0, TAU, 22, rim2, 1.8, true)
