extends Node2D
class_name FighterController

## Full Combat Puppet Fighter Controller for Strings & Steel (Godot 4.x).
## Drives AnimationPlayer combat moves, real-time 2-Bone Off-Hand IK,
## sword ribbon trails, dynamic head expressions, directional guard/parries,
## multi-limb dismemberment with dangling marionette physics, and arterial stumps.

signal request_spawn_debris(debris: PhysicsDebris)
signal request_blood_spray(world_pos: Vector2, impulse: Vector2, count: int, heavy: bool)
signal request_sfx(key: String, jitter: float)
signal request_cut_flash(world_pos: Vector2, label_text: String, color: Color)
signal request_sever_fx(world_pos: Vector2, cut_dir: Vector2)
signal limb_state_changed(fighter: FighterController)

@export var fighter_id: String = "landsknecht"
@export var is_player: bool = true
@export var facing: int = 1
@export var move_speed: float = 300.0
@export var show_strings: bool = true
@export var enable_offhand_ik: bool = true
@export var cursor_aim_enabled: bool = true
@export var gore_enabled: bool = true
@export var max_hp: float = 100.0

var hp: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var bleed_rate: float = 0.0
var is_dead: bool = false
var has_weapon: bool = true
var rig_scale: float = 0.68

var current_action: String = ""
var action_elapsed: float = 0.0
var attack_serial: int = 0
var hit_registered_serial: int = -1
var parrying: bool = false
var parry_hold_time: float = 99.0
var guard_zone: String = "high"

var dash_cooldown: float = 0.0
var dash_timer: float = 0.0
var dash_dir: float = 0.0
var bar_tilt: float = 0.0
var knockback_vx: float = 0.0
var bleed_emit_timer: float = 0.0
var blade_blood: float = 0.0
var blade_drip_timer: float = 0.0
var bloody_boots: float = 0.0
var bootprint_timer: float = 0.0
var extra_pelvis_drop: float = 0.0

var cursor_aim_world: Vector2 = Vector2(560, 320)
var _prev_cursor_aim_world: Vector2 = Vector2(560, 320)
var _cursor_sweep_timer: float = 0.0
var _cursor_whoosh_cd: float = 0.0
var _cursor_slash_cd: float = 0.0
var _cursor_last_dir: Vector2 = Vector2.ZERO
var _cursor_initialized: bool = false
var _last_mouse_vp_pos: Vector2 = Vector2.ZERO
var _prev_tip_local: Vector2 = Vector2.ZERO
var _blade_tip_speed: float = 0.0
var _pad_rest_calibrated: bool = false
var _pad_rest_rx: float = 0.0
var _pad_rest_ry: float = 0.0
var _using_pad_aim: bool = false
var _ik_ua_r: float = deg_to_rad(-52.0)
var _ik_fa_r: float = deg_to_rad(-55.0)
var _ik_wpn_r: float = deg_to_rad(-18.0)
var _ik_torso_lean: float = 0.0

# Virtual touch inputs (driven by UI overlay on mobile/touch)
var touch_move: float = 0.0
var touch_parry: bool = false
var touch_low: bool = false
var _pad_dash_prev: bool = false

# Limb HP & Dismemberment state
var limb_hp: Dictionary = {}
var severed: Dictionary = {}
var severed_strings: Dictionary = {}
var wounds: Array[Dictionary] = []

# Preloaded textures from rig_metadata.json
var _meta_parts: Dictionary = {}
var _fighter_parts: Dictionary = {}
var _head_textures: Dictionary = {}
var _gore_stump_tex: Texture2D
var _stump_sprites: Array[Sprite2D] = []

# Active blade trail history [[guard_world, tip_world], ...]
var _blade_trail: Array = []

@onready var skeleton: Skeleton2D = $Skeleton2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

@onready var bone_pelvis: Bone2D = $Skeleton2D/Pelvis
@onready var bone_torso: Bone2D = $Skeleton2D/Pelvis/Torso
@onready var bone_head: Bone2D = $Skeleton2D/Pelvis/Torso/Head
@onready var bone_hat: Bone2D = get_node_or_null("Skeleton2D/Pelvis/Torso/Head/Hat")

@onready var bone_ua_r: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_R
@onready var bone_fa_r: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R
@onready var bone_hand_r: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R
@onready var bone_weapon: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/WeaponBone

@onready var bone_ua_l: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_L
@onready var bone_fa_l: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_L/Forearm_L
@onready var bone_hand_l: Bone2D = $Skeleton2D/Pelvis/Torso/UpperArm_L/Forearm_L/Hand_L

@onready var bone_thigh_l: Bone2D = $Skeleton2D/Pelvis/Thigh_L
@onready var bone_shin_l: Bone2D = $Skeleton2D/Pelvis/Thigh_L/Shin_L
@onready var bone_boot_l: Bone2D = $Skeleton2D/Pelvis/Thigh_L/Shin_L/Boot_L

@onready var bone_thigh_r: Bone2D = $Skeleton2D/Pelvis/Thigh_R
@onready var bone_shin_r: Bone2D = $Skeleton2D/Pelvis/Thigh_R/Shin_R
@onready var bone_boot_r: Bone2D = $Skeleton2D/Pelvis/Thigh_R/Shin_R/Boot_R

@onready var head_sprite: Sprite2D = $Skeleton2D/Pelvis/Torso/Head/HeadSprite
@onready var weapon_sprite: Sprite2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/WeaponBone/WeaponSprite
@onready var pommel_target: Marker2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/WeaponBone/PommelGripTarget
@onready var blade_guard_marker: Marker2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/WeaponBone/BladeGuardMarker
@onready var blade_tip_marker: Marker2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/WeaponBone/BladeTipMarker

@onready var str_head: Marker2D = $Skeleton2D/Pelvis/Torso/Head/StringHead
@onready var str_hand_r: Marker2D = $Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/StringHandR
@onready var str_hand_l: Marker2D = $Skeleton2D/Pelvis/Torso/UpperArm_L/Forearm_L/StringHandL


func _ready() -> void:
	_load_character_assets()
	reset_fighter()
	if skeleton != null:
		rig_scale = absf(skeleton.scale.y)
		_apply_facing()
	if anim_player != null:
		anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim_player.animation_finished.connect(_on_animation_finished)
		if anim_player.has_animation("idle"):
			anim_player.play("idle")
			anim_player.advance(0.0)


func reset_fighter() -> void:
	hp = max_hp
	stamina = max_stamina
	bleed_rate = 0.0
	is_dead = false
	has_weapon = true
	current_action = ""
	action_elapsed = 0.0
	hit_registered_serial = -1
	parrying = false
	parry_hold_time = 99.0
	dash_cooldown = 0.0
	dash_timer = 0.0
	knockback_vx = 0.0
	blade_blood = 0.0
	blade_drip_timer = 0.0
	bloody_boots = 0.0
	bootprint_timer = 0.0
	extra_pelvis_drop = 0.0
	_ik_ua_r = deg_to_rad(-52.0)
	_ik_fa_r = deg_to_rad(-55.0)
	_ik_wpn_r = deg_to_rad(-18.0)
	_blade_trail.clear()
	wounds.clear()

	limb_hp = {
		"head": 58.0, "torso": 100.0,
		"arm_r": 44.0, "forearm_r": 32.0,
		"arm_l": 42.0, "forearm_l": 30.0,
		"thigh_l": 50.0, "shin_l": 38.0,
		"thigh_r": 50.0, "shin_r": 38.0,
	}
	severed = {
		"head": false, "torso": false,
		"arm_r": false, "forearm_r": false,
		"arm_l": false, "forearm_l": false,
		"thigh_l": false, "shin_l": false,
		"thigh_r": false, "shin_r": false,
	}
	severed_strings = {"head": false, "arm_r": false, "arm_l": false, "leg_l": false, "leg_r": false}

	for b in [bone_torso, bone_head, bone_ua_r, bone_fa_r, bone_hand_r, bone_weapon, bone_ua_l, bone_fa_l, bone_hand_l, bone_thigh_l, bone_shin_l, bone_boot_l, bone_thigh_r, bone_shin_r, bone_boot_r]:
		if b != null:
			b.visible = true
	for st in _stump_sprites:
		if st != null and is_instance_valid(st):
			st.queue_free()
	_stump_sprites.clear()
	_reset_sprite_tints(skeleton)
	if weapon_sprite != null:
		weapon_sprite.visible = true
	if skeleton != null:
		skeleton.position = Vector2.ZERO
	_update_head_expression()
	limb_state_changed.emit(self)


func _reset_sprite_tints(n: Node) -> void:
	if n == null:
		return
	if n is Sprite2D:
		(n as Sprite2D).modulate = Color(1, 1, 1, 1)
	for c in n.get_children():
		_reset_sprite_tints(c)


func _load_character_assets() -> void:
	var file := FileAccess.open("res://data/rig_metadata.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_meta_parts = parsed.get("parts", {})
	var fighters: Dictionary = parsed.get("fighters", {})
	var f_cfg: Dictionary = fighters.get(fighter_id, {})
	_fighter_parts = f_cfg.get("parts", {})

	var map := {}
	match fighter_id:
		"landsknecht":
			map = {"calm": "p1_head_calm", "yell": "p1_head_yell", "pain": "p1_head_grimace", "bloody": "p1_head_bloody", "dead": "p1_head_dead"}
		"fechtmeister":
			map = {"calm": "p2_head_calm", "yell": "p2_head_yell", "pain": "p2_head_pain", "bloody": "p2_head_bloody", "dead": "p2_head_dead"}
		"plague_executioner":
			map = {"calm": "p3_head_mask", "yell": "p3_head_mask", "pain": "p3_head_bloody", "bloody": "p3_head_bloody", "dead": "p3_head_dead"}
		"black_knight":
			map = {"calm": "p4_head_helm", "yell": "p4_head_helm", "pain": "p4_head_bloody", "bloody": "p4_head_bloody", "dead": "p4_head_dead"}
		"venetian_bravo":
			map = {"calm": "p5_head_calm", "yell": "p5_head_yell", "pain": "p5_head_yell", "bloody": "p5_head_bloody", "dead": "p5_head_dead"}
		_:
			map = {"calm": "p1_head_calm", "yell": "p1_head_yell", "pain": "p1_head_grimace", "bloody": "p1_head_bloody", "dead": "p1_head_dead"}
	for k in map.keys():
		var pid: String = map[k]
		if _meta_parts.has(pid):
			var tex_path: String = _meta_parts[pid].get("texture", "")
			if ResourceLoader.exists(tex_path):
				_head_textures[k] = ResourceLoader.load(tex_path)
	if ResourceLoader.exists("res://assets/parts_v2/p1_gore_0.png"):
		_gore_stump_tex = ResourceLoader.load("res://assets/parts_v2/p1_gore_0.png")


func _apply_facing() -> void:
	if skeleton != null:
		skeleton.scale = Vector2(rig_scale * float(facing), rig_scale)


func set_facing(new_facing: int) -> void:
	if new_facing == 0 or is_dead:
		return
	facing = 1 if new_facing > 0 else -1
	_apply_facing()


func play_anim(anim_name: String, blend: float = 0.08) -> void:
	if anim_player == null or not anim_player.has_animation(anim_name):
		return
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name, blend)


func start_attack(move_name: String) -> bool:
	if is_dead or current_action != "":
		return false
	if (move_name in ["slash_high", "slash_low", "thrust"]) and (not has_weapon or severed.get("arm_r", false) or severed.get("forearm_r", false)):
		return false
	var cost := 12.0 if move_name != "kick" else 10.0
	if stamina < cost:
		return false

	stamina = maxf(0.0, stamina - cost)
	parrying = false
	current_action = move_name
	action_elapsed = 0.0
	attack_serial += 1
	play_anim(move_name, 0.05)
	request_sfx.emit("whoosh", 0.14)
	_update_head_expression()
	return true


func start_dash(dir_sign: float) -> void:
	if is_dead or dash_cooldown > 0.0 or stamina < 15.0:
		return
	stamina -= 15.0
	dash_dir = 1.0 if dir_sign >= 0.0 else -1.0
	dash_timer = 0.14
	dash_cooldown = 0.55
	request_sfx.emit("whoosh", 0.2)


func trigger_hurt(heavy: bool = false) -> void:
	if is_dead:
		return
	parrying = false
	current_action = "parry_recoil" if heavy else "hurt"
	action_elapsed = 0.0
	play_anim(current_action, 0.04)
	_update_head_expression()


func kill_fighter() -> void:
	if is_dead:
		return
	is_dead = true
	parrying = false
	current_action = "death"
	# Snap 1-2 strings asymmetrically so the fallen marionette collapses naturally
	severed_strings["arm_l"] = true
	if randf() < 0.6:
		severed_strings["elbow_l"] = true
	if randf() < 0.55:
		severed_strings["leg_r"] = true
	play_anim("death", 0.06)
	_update_head_expression()
	limb_state_changed.emit(self)


func _on_animation_finished(anim_name: StringName) -> void:
	if is_dead:
		return
	if String(anim_name) in ["slash_high", "slash_low", "thrust", "kick", "hurt", "parry_recoil"]:
		current_action = ""
		_blade_trail.clear()
		play_anim("idle")
		_update_head_expression()


func _process(delta: float) -> void:
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	stamina = minf(max_stamina, stamina + (22.0 if not parrying else 8.0) * delta)

	# Arterial blood bleed over time
	if bleed_rate > 0.0 and not is_dead:
		hp = maxf(0.0, hp - bleed_rate * delta)
		bleed_emit_timer -= delta
		if gore_enabled and bleed_emit_timer <= 0.0:
			bleed_emit_timer = randf_range(0.06, 0.14)
			for w in wounds:
				var m: Node2D = w.get("node", null)
				if m != null and is_instance_valid(m):
					request_blood_spray.emit(m.global_position, Vector2(randf_range(-90, 90), randf_range(-120, -20)), 2, false)
		if hp <= 0.0:
			kill_fighter()

	if is_dead and gore_enabled and wounds.size() > 0:
		bleed_emit_timer -= delta
		if bleed_emit_timer <= 0.0:
			bleed_emit_timer = randf_range(0.04, 0.11)
			var w: Dictionary = wounds[randi() % wounds.size()]
			var m: Node2D = w.get("node", null)
			if m != null and is_instance_valid(m):
				request_blood_spray.emit(m.global_position, Vector2(randf_range(-75, 75), randf_range(-130, -25)), 2, false)

	# Coated sword blade blood slowly drips off the tip
	if gore_enabled and blade_blood > 0.05 and has_weapon and blade_tip_marker != null:
		blade_blood = maxf(0.0, blade_blood - 0.018 * delta)
		blade_drip_timer -= delta
		if blade_drip_timer <= 0.0:
			blade_drip_timer = randf_range(0.18, 0.45)
			request_blood_spray.emit(blade_tip_marker.global_position, Vector2(randf_range(-25, 25), randf_range(10, 45)), 1, false)

	# Knockback & Dash Physics
	if dash_timer > 0.0:
		dash_timer -= delta
		position.x = clampf(position.x + dash_dir * 760.0 * delta, 120.0, 1160.0)
	if absf(knockback_vx) > 2.0:
		position.x = clampf(position.x + knockback_vx * delta, 120.0, 1160.0)
		knockback_vx *= maxf(0.0, 1.0 - 9.0 * delta)

	# Leg sever pelvis drop
	var target_drop := 0.0
	if severed.get("thigh_l", false) and severed.get("thigh_r", false):
		target_drop = 68.0
	elif severed.get("shin_l", false) and severed.get("shin_r", false):
		target_drop = 45.0
	elif severed.get("thigh_l", false) or severed.get("thigh_r", false):
		target_drop = 14.0
	extra_pelvis_drop = lerpf(extra_pelvis_drop, target_drop, minf(1.0, 10.0 * delta))
	if skeleton != null:
		skeleton.position.y = extra_pelvis_drop

	if current_action != "":
		action_elapsed += delta

	_cursor_sweep_timer = maxf(0.0, _cursor_sweep_timer - delta)
	_cursor_whoosh_cd = maxf(0.0, _cursor_whoosh_cd - delta)
	_cursor_slash_cd = maxf(0.0, _cursor_slash_cd - delta)

	if not is_dead and is_player:
		_process_player_input(delta)

	# Advance AnimationPlayer BEFORE procedural IK so animations never overwrite cursor/pommel IK!
	if anim_player != null:
		anim_player.advance(delta)

	if not is_dead and is_player:
		if cursor_aim_enabled and has_weapon and not bool(severed.get("arm_r", false)) and not bool(severed.get("forearm_r", false)) and current_action == "":
			_solve_sword_arm_to_cursor(delta)
		elif bone_ua_r != null and bone_fa_r != null and bone_weapon != null:
			_ik_ua_r = bone_ua_r.rotation
			_ik_fa_r = bone_fa_r.rotation
			_ik_wpn_r = bone_weapon.rotation

	# Maintain Off-hand 2-bone IK unless dead or left arm injured/severed
	var offhand_intact: bool = has_weapon and not bool(severed.get("arm_r", false)) and not bool(severed.get("arm_l", false)) and not bool(severed.get("forearm_l", false)) and not bool(severed.get("torso", false)) and not bool(severed_strings.get("arm_l", false))
	if enable_offhand_ik and offhand_intact and not is_dead and current_action != "hurt" and current_action != "parry_recoil":
		_solve_offhand_two_bone_ik()
	elif not is_dead and (severed_strings.get("arm_l", false) or not has_weapon or bool(severed.get("arm_r", false))) and not bool(severed.get("arm_l", false)) and bone_ua_l != null:
		# Natural relaxed far-arm guard behind torso when disarmed
		bone_ua_l.rotation = lerp_angle(bone_ua_l.rotation, deg_to_rad(-28.0), 8.0 * delta)
		if bone_fa_l != null:
			bone_fa_l.rotation = lerp_angle(bone_fa_l.rotation, deg_to_rad(-32.0), 8.0 * delta)

	# Sword trail tracking during active attacks
	if is_blade_active() and has_weapon and blade_guard_marker != null and blade_tip_marker != null:
		_blade_trail.append([blade_guard_marker.global_position, blade_tip_marker.global_position])
		if _blade_trail.size() > 8:
			_blade_trail.pop_front()
	elif _blade_trail.size() > 0:
		_blade_trail.pop_front()

	_update_head_expression()
	queue_redraw()


func _read_gamepad() -> Dictionary:
	var res := {
		"move": 0.0, "low": false, "parry": false,
		"slash": false, "thrust": false, "kick": false, "dash": false,
		"rx": 0.0, "ry": 0.0,
	}
	var pads := Input.get_connected_joypads()
	for pid in pads:
		var lx := Input.get_joy_axis(pid, JOY_AXIS_LEFT_X)
		if absf(lx) > 0.22:
			res["move"] = clampf(float(res["move"]) + lx, -1.0, 1.0)
		if Input.is_joy_button_pressed(pid, JOY_BUTTON_DPAD_RIGHT):
			res["move"] = 1.0
		if Input.is_joy_button_pressed(pid, JOY_BUTTON_DPAD_LEFT):
			res["move"] = -1.0

		var ly := Input.get_joy_axis(pid, JOY_AXIS_LEFT_Y)
		var ry := Input.get_joy_axis(pid, JOY_AXIS_RIGHT_Y)
		var rx := Input.get_joy_axis(pid, JOY_AXIS_RIGHT_X)
		if not _pad_rest_calibrated:
			_pad_rest_calibrated = true
			_pad_rest_rx = rx
			_pad_rest_ry = ry
		if absf(rx - _pad_rest_rx) > 0.28:
			res["rx"] = clampf(rx - _pad_rest_rx, -1.0, 1.0)
		if absf(ry - _pad_rest_ry) > 0.28:
			res["ry"] = clampf(ry - _pad_rest_ry, -1.0, 1.0)
		if ly > 0.45 or float(res["ry"]) > 0.45 or Input.is_joy_button_pressed(pid, JOY_BUTTON_DPAD_DOWN):
			res["low"] = true

		if Input.is_joy_button_pressed(pid, JOY_BUTTON_B) or Input.is_joy_button_pressed(pid, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(pid, JOY_AXIS_TRIGGER_LEFT) > 0.35:
			res["parry"] = true
		if Input.is_joy_button_pressed(pid, JOY_BUTTON_X) or Input.is_joy_button_pressed(pid, JOY_BUTTON_RIGHT_SHOULDER):
			res["slash"] = true
		if Input.is_joy_button_pressed(pid, JOY_BUTTON_Y):
			res["thrust"] = true
		if Input.is_joy_button_pressed(pid, JOY_BUTTON_A):
			res["kick"] = true
		if Input.get_joy_axis(pid, JOY_AXIS_TRIGGER_RIGHT) > 0.40 or Input.is_joy_button_pressed(pid, JOY_BUTTON_DPAD_UP) or Input.is_joy_button_pressed(pid, JOY_BUTTON_LEFT_STICK):
			res["dash"] = true
	return res


func _process_player_input(delta: float) -> void:
	var pad := _read_gamepad()
	var low_held := touch_low or Input.is_key_pressed(KEY_S) or bool(pad["low"])
	if cursor_aim_enabled:
		var m_y := get_global_mouse_position().y
		if m_y > position.y - 60.0 and m_y >= 110.0:
			low_held = true
	guard_zone = "low" if low_held else "high"

	var mouse_in_stage := get_viewport().get_mouse_position().y >= 106.0
	var parry_held := touch_parry or Input.is_key_pressed(KEY_SPACE) or (mouse_in_stage and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or bool(pad["parry"])
	if parry_held and current_action == "" and has_weapon and not severed.get("arm_r", false):
		if not parrying:
			parry_hold_time = 0.0
		else:
			parry_hold_time += delta
		parrying = true
		play_anim("parry_low" if guard_zone == "low" else "parry", 0.06)
		_pad_dash_prev = bool(pad["dash"])
		return
	else:
		parrying = false
		parry_hold_time = 99.0

	var pad_dash_now := bool(pad["dash"])
	var pad_dash_edge := pad_dash_now and not _pad_dash_prev
	_pad_dash_prev = pad_dash_now

	if Input.is_action_just_pressed("ui_up") or Input.is_key_pressed(KEY_SHIFT) or pad_dash_edge:
		var d_dir := touch_move + float(pad["move"])
		if absf(d_dir) < 0.2:
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				d_dir = 1.0
			elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				d_dir = -1.0
			else:
				d_dir = float(facing)
		start_dash(d_dir)

	if Input.is_key_pressed(KEY_J) or bool(pad["slash"]) or (not cursor_aim_enabled and mouse_in_stage and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		start_attack("slash_low" if low_held else "slash_high")
	elif Input.is_key_pressed(KEY_K) or bool(pad["thrust"]):
		start_attack("thrust")
	elif Input.is_key_pressed(KEY_E) or bool(pad["kick"]):
		start_attack("kick")

	if current_action == "":
		var mv := clampf(touch_move + float(pad["move"]), -1.0, 1.0)
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			mv += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			mv -= 1.0
		mv = clampf(mv, -1.0, 1.0)
		bar_tilt = lerpf(bar_tilt, mv * 0.08, 8.0 * delta)
		if absf(mv) > 0.12:
			position.x = clampf(position.x + mv * move_speed * delta, 120.0, 1160.0)
			play_anim("walk", 0.08)
		else:
			play_anim("idle", 0.1)


func is_blade_active() -> bool:
	if is_dead or not has_weapon:
		return false
	match current_action:
		"slash_high", "slash_low":
			return action_elapsed >= 0.13 and action_elapsed <= 0.34
		"thrust":
			return action_elapsed >= 0.11 and action_elapsed <= 0.30
		_:
			return cursor_aim_enabled and _cursor_sweep_timer > 0.0 and not parrying


func get_strike_power() -> float:
	match current_action:
		"slash_high", "slash_low", "thrust":
			return 1.0
		_:
			return clampf((_blade_tip_speed - 280.0) / 620.0, 0.38, 1.0)


func _solve_sword_arm_to_cursor(delta: float) -> void:
	if bone_torso == null or bone_ua_r == null or bone_fa_r == null or bone_hand_r == null or bone_weapon == null:
		return

	var dt_safe := maxf(0.005, delta)
	var pad := _read_gamepad()
	var rx := float(pad["rx"])
	var ry := float(pad["ry"])
	var vp_mouse := get_viewport().get_mouse_position()
	if vp_mouse.distance_to(_last_mouse_vp_pos) > 1.5:
		_last_mouse_vp_pos = vp_mouse
		_using_pad_aim = false
	elif absf(rx) > 0.28 or absf(ry) > 0.28:
		_using_pad_aim = true

	var raw_tgt := cursor_aim_world
	if _using_pad_aim and (absf(rx) > 0.28 or absf(ry) > 0.28):
		raw_tgt = global_position + Vector2(float(facing) * (95.0 + rx * 145.0), -110.0 + ry * 145.0)
	else:
		var mouse_pos := get_global_mouse_position()
		if vp_mouse.y >= 106.0:
			raw_tgt = Vector2(clampf(mouse_pos.x, 40.0, 1240.0), clampf(mouse_pos.y, 120.0, 565.0))

	if not _cursor_initialized:
		_cursor_initialized = true
		_last_mouse_vp_pos = vp_mouse
		cursor_aim_world = raw_tgt
		_prev_cursor_aim_world = raw_tgt

	_prev_cursor_aim_world = raw_tgt
	cursor_aim_world = cursor_aim_world.lerp(raw_tgt, minf(1.0, 25.0 * delta))

	var sh_pos := bone_ua_r.position
	var l1 := bone_fa_r.position.length()
	var l2 := bone_hand_r.position.length()
	if l1 < 1.0 or l2 < 1.0:
		return

	# Subtle torso & head lean into the cursor aim height/reach
	var cursor_local_pre := bone_torso.to_local(cursor_aim_world)
	var chest_origin := Vector2(12.0, -78.0)
	var raw_aim_vec := cursor_local_pre - chest_origin
	var raw_aim_ang := clampf(raw_aim_vec.angle(), deg_to_rad(-80.0), deg_to_rad(65.0))
	var target_lean := clampf((raw_aim_ang + 0.25) * 0.18, deg_to_rad(-10.0), deg_to_rad(14.0))
	_ik_torso_lean = lerpf(_ik_torso_lean, target_lean, minf(1.0, 14.0 * delta))
	bone_torso.rotation += _ik_torso_lean
	if bone_head != null:
		bone_head.rotation += clampf(raw_aim_ang * 0.16, deg_to_rad(-12.0), deg_to_rad(12.0))

	# Re-evaluate cursor in Torso local space after torso lean
	var cursor_local := bone_torso.to_local(cursor_aim_world)
	var aim_from_chest := cursor_local - chest_origin
	var aim_dist := aim_from_chest.length()
	var aim_dir := aim_from_chest / maxf(1.0, aim_dist)

	# Move the hands 1-to-1 along the cursor vector inside the 2-handed reach envelope:
	# - Pull cursor close -> hands pull in close to chest/head guard
	# - Push cursor far -> arms extend out toward the cursor while keeping blade tip on cursor!
	var desired_hand_dist := clampf(aim_dist - 95.0, 82.0, 148.0)
	var hand_tgt := chest_origin + aim_dir * desired_hand_dist
	# Offset hands slightly below the blade line when aiming high/mid so elbow hangs naturally beneath wrist
	hand_tgt.y += clampf(22.0 * (1.0 - absf(aim_dir.y)), 6.0, 22.0)
	var low_factor := clampf(aim_dir.y, 0.0, 1.0)
	var min_hand_x := 74.0 + 48.0 * low_factor
	hand_tgt.x = clampf(hand_tgt.x, min_hand_x, 154.0)
	hand_tgt.y = clampf(hand_tgt.y, sh_pos.y - 22.0, sh_pos.y + 158.0)

	# Keep within left-shoulder (sh_far) reach so the off-hand stays locked to the pommel
	if bone_ua_l != null:
		var sh_far := bone_ua_l.position
		var to_far := hand_tgt - sh_far
		var max_far_r := 152.0
		if to_far.length() > max_far_r:
			hand_tgt = sh_far + to_far.normalized() * max_far_r

	var diff := hand_tgt - sh_pos
	var dist := diff.length()
	var max_r := (l1 + l2) * 0.95
	var min_r := maxf(40.0, absf(l1 - l2) + 8.0)
	var d := clampf(dist, min_r, max_r)
	var base_ang := diff.angle()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var a := acos(cos_a)

	# Choose natural downward-hanging elbow (+Y in Torso local space)
	var ang_a := base_ang + a
	var ang_b := base_ang - a
	var elbow_a := sh_pos + Vector2(cos(ang_a), sin(ang_a)) * l1
	var elbow_b := sh_pos + Vector2(cos(ang_b), sin(ang_b)) * l1
	var score_a := elbow_a.y - maxf(0.0, elbow_a.x - sh_pos.x - 18.0) * 0.65
	var score_b := elbow_b.y - maxf(0.0, elbow_b.x - sh_pos.x - 18.0) * 0.65
	var chosen_upper := ang_a if score_a >= score_b else ang_b
	var elbow_pt := elbow_a if score_a >= score_b else elbow_b
	var clamped_hand := sh_pos + Vector2(cos(base_ang), sin(base_ang)) * d
	var chosen_lower := (clamped_hand - elbow_pt).angle()

	var ua_target_rot := chosen_upper - PI * 0.5
	var fa_target_rot := chosen_lower - chosen_upper

	# Point the sword blade directly from the hand through the cursor!
	var blade_vec := cursor_local - clamped_hand
	var desired_blade_ang := blade_vec.angle() if blade_vec.length() > 20.0 else aim_dir.angle()
	if parrying:
		desired_blade_ang = -1.22 if guard_zone == "high" else 0.68
	var neutral_blade_ang := chosen_lower - PI * 0.5
	var wrist_cock := clampf(wrapf(desired_blade_ang - neutral_blade_ang, -PI, PI), deg_to_rad(-48.0), deg_to_rad(84.0))

	var k := minf(1.0, 24.0 * delta)
	_ik_ua_r = lerp_angle(_ik_ua_r, ua_target_rot, k)
	_ik_fa_r = lerp_angle(_ik_fa_r, fa_target_rot, k)
	_ik_wpn_r = lerp_angle(_ik_wpn_r, wrist_cock, k)

	bone_ua_r.rotation = _ik_ua_r
	bone_fa_r.rotation = _ik_fa_r
	bone_hand_r.rotation = 0.0
	bone_weapon.rotation = _ik_wpn_r

	# Measure true fighter-local blade-tip speed AFTER applying the new IK rotations!
	if blade_tip_marker != null:
		var cur_tip_local := to_local(blade_tip_marker.global_position)
		if _prev_tip_local == Vector2.ZERO:
			_prev_tip_local = cur_tip_local
		var tip_delta := cur_tip_local - _prev_tip_local
		var inst_tip_spd := tip_delta.length() / dt_safe
		_prev_tip_local = cur_tip_local
		_blade_tip_speed = maxf(inst_tip_spd, lerpf(_blade_tip_speed, inst_tip_spd, minf(1.0, 14.0 * delta)))

		# Activate cursor slash when slinging the blade fast (>= 340 px/s in fighter-local space);
		# holding the sword still or slowly aiming (< 340 px/s) does NOT trigger hits!
		if inst_tip_spd >= 340.0 and not parrying:
			var tip_dir := tip_delta.normalized()
			if _cursor_sweep_timer <= 0.0 or (_cursor_slash_cd <= 0.0 and _cursor_last_dir.dot(tip_dir) < 0.25):
				attack_serial += 1
				_cursor_slash_cd = 0.18
				_cursor_last_dir = tip_dir
				if _cursor_whoosh_cd <= 0.0 and inst_tip_spd >= 480.0:
					_cursor_whoosh_cd = 0.22
					request_sfx.emit("whoosh", 0.16)
			_cursor_sweep_timer = 0.14


func is_kick_active() -> bool:
	return not is_dead and current_action == "kick" and action_elapsed >= 0.10 and action_elapsed <= 0.28 and not severed.get("thigh_r", false) and not severed.get("shin_r", false)


func is_perfect_parry() -> bool:
	return parrying and parry_hold_time <= 0.25


func get_blade_segment() -> Array:
	if not has_weapon or severed.get("arm_r", false) or severed.get("forearm_r", false) or severed.get("torso", false):
		return []
	if blade_guard_marker == null or blade_tip_marker == null:
		return []
	return [blade_guard_marker.global_position, blade_tip_marker.global_position]


func get_body_segments() -> Array:
	var segs: Array = []
	if bone_pelvis == null:
		return segs
	if not severed.get("torso", false) and bone_torso != null:
		segs.append(["torso", bone_pelvis.global_position, bone_torso.global_position + Vector2(0, -65), 24.0])
		if not severed.get("head", false) and bone_head != null:
			segs.append(["head", bone_head.global_position, bone_head.global_position + Vector2(0, -48), 20.0])
		if not severed.get("arm_r", false) and bone_ua_r != null and bone_fa_r != null:
			segs.append(["arm_r", bone_ua_r.global_position, bone_fa_r.global_position, 15.0])
			if not severed.get("forearm_r", false) and bone_hand_r != null:
				segs.append(["forearm_r", bone_fa_r.global_position, bone_hand_r.global_position, 14.0])
		if not severed.get("arm_l", false) and bone_ua_l != null and bone_fa_l != null:
			segs.append(["arm_l", bone_ua_l.global_position, bone_fa_l.global_position, 15.0])
			if not severed.get("forearm_l", false) and bone_hand_l != null:
				segs.append(["forearm_l", bone_fa_l.global_position, bone_hand_l.global_position, 14.0])
	if not severed.get("thigh_r", false) and bone_thigh_r != null and bone_shin_r != null:
		segs.append(["thigh_r", bone_thigh_r.global_position, bone_shin_r.global_position, 18.0])
		if not severed.get("shin_r", false) and bone_boot_r != null:
			segs.append(["shin_r", bone_shin_r.global_position, bone_boot_r.global_position, 15.0])
	if not severed.get("thigh_l", false) and bone_thigh_l != null and bone_shin_l != null:
		segs.append(["thigh_l", bone_thigh_l.global_position, bone_shin_l.global_position, 18.0])
		if not severed.get("shin_l", false) and bone_boot_l != null:
			segs.append(["shin_l", bone_shin_l.global_position, bone_boot_l.global_position, 15.0])
	return segs


func apply_blade_damage(slot: String, dmg: float, hit_pt: Vector2, swing_dir: Vector2, one_hit_sever: bool, attacker_heavy: bool = false, impact_power: float = 1.0) -> bool:
	if is_dead:
		return false

	# Armored fighters mitigate glancing hits on plate/brigandine armor until staggered or chipped
	var is_plate_fighter: bool = fighter_id in ["fechtmeister", "black_knight"]
	var is_brigandine_fighter: bool = fighter_id == "plague_executioner"
	var armored_slot: bool = (is_plate_fighter and (slot in ["torso", "head", "shin_r", "shin_l"])) or (is_brigandine_fighter and (slot in ["torso", "head"]))
	var armor_mult: float = 0.72 if (armored_slot and current_action != "parry_recoil") else 1.0
	var pwr: float = clampf(impact_power, 0.20, 1.0)
	var final_dmg: float = dmg * armor_mult * pwr
	var limb_dmg: float = dmg * (1.25 if attacker_heavy else 0.92) * armor_mult * pwr

	hp = maxf(0.0, hp - final_dmg)
	bleed_rate += final_dmg * 0.045
	knockback_vx += swing_dir.x * (215.0 * pwr * pwr)
	limb_hp[slot] = maxf(0.0, float(limb_hp.get(slot, 40.0)) - limb_dmg)

	var node_ref: Node2D = _slot_stump_anchor(slot)
	if node_ref != null and wounds.size() < 10 and pwr >= 0.55:
		wounds.append({"node": node_ref, "radius": 8.0})
	_stain_limb_bloody(node_ref)

	request_sfx.emit("flesh", 0.14)
	var drop_cnt := maxi(3, int(round((22.0 if gore_enabled else 6.0) * pwr)))
	request_blood_spray.emit(hit_pt, swing_dir * (320.0 * pwr) + Vector2(0, -130.0 * pwr), drop_cnt, false)

	# Earned dismemberment: only full-power committed strikes (pwr >= 0.70) or fatal blows can chop limbs!
	var execution_window: bool = (current_action == "parry_recoil") or (current_action == "hurt" and hp < 48.0)
	var limb_depleted: bool = float(limb_hp.get(slot, 1.0)) <= 0.0
	var lethal_finish: bool = hp <= 0.0
	var can_chop_power: bool = pwr >= 0.70 or lethal_finish
	var should_sever: bool = can_chop_power and (not bool(severed.get(slot, false))) and (one_hit_sever or limb_depleted or lethal_finish or (attacker_heavy and execution_window))

	if should_sever:
		if lethal_finish and slot == "torso" and randf() < 0.45 and not bool(severed.get("head", false)):
			slot = "head"
		sever_limb(slot, hit_pt, swing_dir)
		return true
	else:
		if hp <= 0.0:
			kill_fighter()
		elif pwr >= 0.68:
			trigger_hurt(false)
		return false


func _stain_limb_bloody(root_node: Node2D) -> void:
	if not gore_enabled or root_node == null:
		return
	for c in root_node.get_children():
		if c is Sprite2D:
			var sp := c as Sprite2D
			sp.modulate = sp.modulate.lerp(Color(0.76, 0.36, 0.38, 1.0), 0.38)


func _attach_gore_stump_sprite(parent_node: Node2D, local_pos: Vector2, rot_rad: float, sc: float = 0.46) -> void:
	if not gore_enabled or _gore_stump_tex == null or parent_node == null:
		return
	var st := Sprite2D.new()
	st.texture = _gore_stump_tex
	st.centered = true
	st.position = local_pos
	st.rotation = rot_rad
	st.scale = Vector2(sc, sc)
	st.z_index = 48
	parent_node.add_child(st)
	_stump_sprites.append(st)


func sever_limb(slot: String, hit_pt: Vector2, swing_dir: Vector2) -> void:
	if severed.get(slot, false):
		return
	severed[slot] = true
	bleed_rate += 7.5
	request_sfx.emit("sever", 0.1)
	request_blood_spray.emit(hit_pt, swing_dir * 480.0 + Vector2(0, -240), 48, true)
	request_sever_fx.emit(hit_pt, swing_dir)

	match slot:
		"head":
			if bone_head != null:
				_spawn_severed_head(swing_dir)
				bone_head.visible = false
				wounds.append({"node": bone_head, "radius": 12.0})
				if bone_torso != null:
					_attach_gore_stump_sprite(bone_torso, bone_head.position + Vector2(0, -4), 0.0, 0.42)
			request_cut_flash.emit(hit_pt, "DECAPITATION!", Color(1.0, 0.22, 0.24))
			hp = 0.0
			kill_fighter()
		"torso":
			_spawn_bisected_upper_torso(hit_pt, swing_dir)
			if bone_torso != null:
				bone_torso.visible = false
				_attach_gore_stump_sprite(bone_pelvis, bone_torso.position + Vector2(0, -6), randf_range(-0.25, 0.25), 0.72)
			wounds.append({"node": bone_torso, "radius": 22.0})
			request_cut_flash.emit(hit_pt, "DIAGONAL CLEAVE!", Color(1.0, 0.18, 0.22))
			hp = 0.0
			kill_fighter()
		"arm_r":
			has_weapon = false
			if bone_ua_r != null:
				_spawn_severed_subtree(bone_ua_r, swing_dir * 260.0 + Vector2(0, -180), 10.0, true, false, Vector2(0, 145))
				bone_ua_r.visible = false
				wounds.append({"node": bone_ua_r, "radius": 10.0})
				_attach_gore_stump_sprite(bone_torso, bone_ua_r.position, deg_to_rad(110.0), 0.44)
			request_cut_flash.emit(hit_pt, "SWORD ARM SEVERED!", Color(1.0, 0.42, 0.22))
			hp = minf(hp, 26.0)
			trigger_hurt(true)
		"forearm_r":
			has_weapon = false
			if bone_fa_r != null:
				_spawn_severed_subtree(bone_fa_r, swing_dir * 280.0 + Vector2(0, -170), 9.0, true, false, Vector2(0, 95))
				bone_fa_r.visible = false
				wounds.append({"node": bone_fa_r, "radius": 9.0})
				_attach_gore_stump_sprite(bone_ua_r, bone_fa_r.position, PI, 0.36)
			request_cut_flash.emit(hit_pt, "DISARMING SEVER!", Color(1.0, 0.52, 0.22))
			trigger_hurt(true)
		"arm_l":
			if bone_ua_l != null:
				_spawn_severed_subtree(bone_ua_l, swing_dir * 250.0 + Vector2(0, -170), 10.0, true, false, Vector2(0, 145))
				bone_ua_l.visible = false
				wounds.append({"node": bone_ua_l, "radius": 10.0})
				_attach_gore_stump_sprite(bone_torso, bone_ua_l.position, deg_to_rad(70.0), 0.44)
			request_cut_flash.emit(hit_pt, "ARM SEVERED!", Color(1.0, 0.38, 0.26))
			trigger_hurt(true)
		"forearm_l":
			if bone_fa_l != null:
				_spawn_severed_subtree(bone_fa_l, swing_dir * 260.0 + Vector2(0, -160), 8.0, true, false, Vector2(0, 95))
				bone_fa_l.visible = false
				wounds.append({"node": bone_fa_l, "radius": 8.0})
				_attach_gore_stump_sprite(bone_ua_l, bone_fa_l.position, PI, 0.34)
			request_cut_flash.emit(hit_pt, "FOREARM SEVERED!", Color(1.0, 0.48, 0.26))
			trigger_hurt(false)
		"thigh_r":
			if bone_thigh_r != null:
				_spawn_severed_subtree(bone_thigh_r, swing_dir * 240.0 + Vector2(0, -160), 12.0, true, false, Vector2(0, 180))
				bone_thigh_r.visible = false
				wounds.append({"node": bone_thigh_r, "radius": 12.0})
				_attach_gore_stump_sprite(bone_pelvis, bone_thigh_r.position, PI, 0.50)
			request_cut_flash.emit(hit_pt, "LEG SEVERED!", Color(1.0, 0.32, 0.28))
			trigger_hurt(true)
		"shin_r":
			if bone_shin_r != null:
				_spawn_severed_subtree(bone_shin_r, swing_dir * 250.0 + Vector2(0, -150), 9.0, true, false, Vector2(0, 95))
				bone_shin_r.visible = false
				wounds.append({"node": bone_shin_r, "radius": 9.0})
				_attach_gore_stump_sprite(bone_thigh_r, bone_shin_r.position, PI, 0.38)
			request_cut_flash.emit(hit_pt, "SHIN SEVERED!", Color(1.0, 0.42, 0.28))
			trigger_hurt(false)
		"thigh_l":
			if bone_thigh_l != null:
				_spawn_severed_subtree(bone_thigh_l, swing_dir * 240.0 + Vector2(0, -160), 12.0, true, false, Vector2(0, 180))
				bone_thigh_l.visible = false
				wounds.append({"node": bone_thigh_l, "radius": 12.0})
				_attach_gore_stump_sprite(bone_pelvis, bone_thigh_l.position, PI, 0.50)
			request_cut_flash.emit(hit_pt, "LEG SEVERED!", Color(1.0, 0.32, 0.28))
			trigger_hurt(true)
		"shin_l":
			if bone_shin_l != null:
				_spawn_severed_subtree(bone_shin_l, swing_dir * 250.0 + Vector2(0, -150), 9.0, true, false, Vector2(0, 95))
				bone_shin_l.visible = false
				wounds.append({"node": bone_shin_l, "radius": 9.0})
				_attach_gore_stump_sprite(bone_thigh_l, bone_shin_l.position, PI, 0.38)
			request_cut_flash.emit(hit_pt, "SHIN SEVERED!", Color(1.0, 0.42, 0.28))
			trigger_hurt(false)

	limb_state_changed.emit(self)


func _spawn_severed_head(swing_dir: Vector2) -> void:
	if bone_head == null:
		return
	var deb := PhysicsDebris.new()
	deb.position = bone_head.global_position
	deb.vel = swing_dir * 220.0 + Vector2(0, -210.0)
	deb.floor_y = 562.0
	deb.gore_enabled = gore_enabled
	deb.stump_radius = 11.0
	deb.stump_local = Vector2(0, 4.0)
	deb.scale = Vector2(float(facing) * rig_scale, rig_scale)

	# Clone intact Head + Hat alignment cleanly, forcing dead face expression
	_clone_bone_tree_visuals(bone_head, deb, true, true)

	# Add bloody protruding neck stump bone upside-down below the jaw
	if gore_enabled and _gore_stump_tex != null:
		var gsp := Sprite2D.new()
		gsp.texture = _gore_stump_tex
		gsp.position = Vector2(0, 10.0)
		gsp.rotation = PI
		gsp.scale = Vector2(0.42, 0.42)
		gsp.z_index = 34
		deb.add_child(gsp)

	# Hang upright from the skull/crown marionette string!
	if show_strings and not bool(severed_strings.get("head", false)):
		deb.dangling = true
		deb.upright_bias = 22.0
		deb.rest_dangle_angle = float(facing) * 0.12
		var crown_off := (bone_hat.position + Vector2(0, -34.0)) if bone_hat != null else Vector2(0, -86.0)
		deb.hang_offset_local = crown_off
		deb.string_anchor = Vector2(bone_head.global_position.x + swing_dir.x * 26.0, position.y - 345.0)
		var crown_world := bone_head.global_position + crown_off * rig_scale
		deb.rope_length = clampf(crown_world.y - deb.string_anchor.y + 42.0, 140.0, 320.0)
		deb.ang_vel = randf_range(-1.8, 1.8)
	else:
		deb.ang_vel = randf_range(-9.0, 9.0)

	request_spawn_debris.emit(deb)


func _spawn_severed_subtree(src_bone: Node2D, launch_vel: Vector2, stump_r: float, allow_dangle: bool, flip_stump_up: bool, hang_off: Vector2 = Vector2(0, 95)) -> void:
	if src_bone == null:
		return
	var deb := PhysicsDebris.new()
	deb.position = src_bone.global_position
	deb.vel = launch_vel
	deb.floor_y = 562.0
	deb.gore_enabled = gore_enabled
	deb.stump_radius = stump_r
	deb.stump_local = Vector2.ZERO
	deb.scale = Vector2(float(facing) * rig_scale, rig_scale)

	_clone_bone_tree_visuals(src_bone, deb, true, false)

	if gore_enabled and _gore_stump_tex != null:
		var gsp := Sprite2D.new()
		gsp.texture = _gore_stump_tex
		gsp.position = Vector2.ZERO
		gsp.rotation = 0.0 if flip_stump_up else PI
		gsp.scale = Vector2(0.42, 0.42)
		gsp.z_index = 48
		deb.add_child(gsp)

	if allow_dangle and show_strings:
		deb.dangling = true
		deb.upright_bias = 16.0
		deb.rest_dangle_angle = randf_range(-0.24, 0.24)
		# Tie rope neatly to the cloth/armor cuff below the severed bone stump
		deb.hang_offset_local = Vector2(0, minf(34.0, hang_off.y * 0.28))
		deb.string_anchor = Vector2(src_bone.global_position.x + randf_range(-34, 34), position.y - 345.0)
		var target_y := clampf(src_bone.global_position.y - 32.0, deb.string_anchor.y + 155.0, 410.0)
		deb.rope_length = clampf(target_y - deb.string_anchor.y, 155.0, 315.0)
		deb.rotation = randf_range(-0.35, 0.35)
		deb.ang_vel = randf_range(-3.2, 3.2)
	else:
		deb.ang_vel = randf_range(-10.5, 10.5)

	request_spawn_debris.emit(deb)


func _spawn_bisected_upper_torso(hit_pt: Vector2, swing_dir: Vector2) -> void:
	if bone_torso == null:
		return
	var deb := PhysicsDebris.new()
	deb.position = bone_torso.global_position
	deb.vel = swing_dir * 260.0 + Vector2(0, -210.0)
	deb.ang_vel = randf_range(-2.6, 2.6)
	deb.floor_y = 562.0
	deb.gore_enabled = gore_enabled
	deb.stump_radius = 18.0
	deb.stump_local = Vector2(0, 12.0)
	deb.scale = Vector2(float(facing) * rig_scale, rig_scale)

	_clone_bone_tree_visuals(bone_torso, deb, true, true)

	if gore_enabled and _gore_stump_tex != null:
		var gsp := Sprite2D.new()
		gsp.texture = _gore_stump_tex
		gsp.position = Vector2(0, 10.0)
		gsp.rotation = PI
		gsp.scale = Vector2(0.68, 0.68)
		gsp.z_index = 28
		deb.add_child(gsp)

	if show_strings:
		deb.dangling = true
		deb.upright_bias = 14.0
		deb.rest_dangle_angle = float(facing) * 0.25
		deb.string_anchor = Vector2(position.x + swing_dir.x * 30.0, position.y - 345.0)
		deb.hang_offset_local = bone_head.position + Vector2(0, -70.0) if bone_head != null else Vector2(0, -190.0)
		deb.rope_length = 265.0

	request_spawn_debris.emit(deb)


func _clone_bone_tree_visuals(src_node: Node2D, dst_parent: Node2D, is_root: bool, force_dead_head: bool) -> void:
	for c in src_node.get_children():
		if not c is Node2D or not (c as Node2D).visible:
			continue
		if c is Sprite2D:
			var sp := (c as Sprite2D).duplicate() as Sprite2D
			if force_dead_head and c == head_sprite and _head_textures.has("dead"):
				sp.texture = _head_textures["dead"]
			dst_parent.add_child(sp)
		elif c is Bone2D:
			var b := c as Bone2D
			var piv := Node2D.new()
			piv.position = b.position
			piv.rotation = b.rotation
			dst_parent.add_child(piv)
			_clone_bone_tree_visuals(b, piv, false, force_dead_head)


func _slot_stump_anchor(slot: String) -> Node2D:
	match slot:
		"head": return bone_head
		"torso": return bone_torso
		"arm_r": return bone_ua_r
		"forearm_r": return bone_fa_r
		"arm_l": return bone_ua_l
		"forearm_l": return bone_fa_l
		"thigh_r": return bone_thigh_r
		"shin_r": return bone_shin_r
		"thigh_l": return bone_thigh_l
		"shin_l": return bone_shin_l
		_: return bone_pelvis


func _update_head_expression() -> void:
	if head_sprite == null or _head_textures.is_empty():
		return
	var expr := "calm"
	if is_dead:
		expr = "dead"
	elif current_action == "hurt" or current_action == "parry_recoil":
		expr = "pain"
	elif current_action in ["slash_high", "slash_low", "thrust", "kick"]:
		expr = "yell"
	elif hp < 55.0:
		expr = "bloody"
	if _head_textures.has(expr):
		head_sprite.texture = _head_textures[expr]


func _solve_offhand_two_bone_ik() -> void:
	if bone_torso == null or bone_ua_l == null or bone_fa_l == null or bone_hand_l == null or pommel_target == null:
		return

	var sh_pos := bone_ua_l.position
	var tgt_pos := bone_torso.to_local(pommel_target.global_position)
	var l1 := bone_fa_l.position.length()
	var l2 := bone_hand_l.position.length()
	var grip_marker := bone_hand_l.get_node_or_null("GripCenter") as Marker2D
	if grip_marker != null:
		l2 += grip_marker.position.length()
	if l1 < 1.0 or l2 < 1.0:
		return

	var diff := tgt_pos - sh_pos
	var dist := diff.length()
	var max_r := (l1 + l2) * 0.995
	var min_r := maxf(2.0, absf(l1 - l2) + 2.0)
	var d := clampf(dist, min_r, max_r)
	var base_ang := diff.angle()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var a := acos(cos_a)

	var ang_a := base_ang + a
	var ang_b := base_ang - a
	var elbow_a := sh_pos + Vector2(cos(ang_a), sin(ang_a)) * l1
	var elbow_b := sh_pos + Vector2(cos(ang_b), sin(ang_b)) * l1
	var score_a := elbow_a.y - maxf(0.0, elbow_a.x - sh_pos.x - 18.0) * 0.65
	var score_b := elbow_b.y - maxf(0.0, elbow_b.x - sh_pos.x - 18.0) * 0.65
	var chosen_upper := ang_a if score_a >= score_b else ang_b
	var elbow_pt := elbow_a if score_a >= score_b else elbow_b

	var chosen_lower := (tgt_pos - elbow_pt).angle()
	var ua_rest_dir := bone_fa_l.position.angle()
	var fa_rest_dir := bone_hand_l.position.angle()

	bone_ua_l.rotation = chosen_upper - ua_rest_dir
	bone_fa_l.rotation = chosen_lower - chosen_upper - (fa_rest_dir - ua_rest_dir)
	bone_hand_l.rotation = 0.0


func _draw() -> void:
	# 1. Weapon Motion Slash Ribbon
	if _blade_trail.size() >= 2:
		for i in range(_blade_trail.size() - 1):
			var a_pts: Array = _blade_trail[i]
			var b_pts: Array = _blade_trail[i + 1]
			if Vector2(a_pts[1]).distance_squared_to(Vector2(b_pts[1])) < 16.0:
				continue
			var frac := float(i + 1) / float(_blade_trail.size())
			var col := Color(0.92, 0.95, 1.0, 0.28 * frac * frac)
			var pts := PackedVector2Array([
				to_local(a_pts[0]), to_local(a_pts[1]),
				to_local(b_pts[1]), to_local(b_pts[0])
			])
			if Geometry2D.triangulate_polygon(pts).size() > 0:
				draw_colored_polygon(pts, col)
			draw_line(to_local(a_pts[1]), to_local(b_pts[1]), Color(1.0, 0.98, 0.90, 0.65 * frac), 2.4, true)

	# 1b. Wet Blood Coating Along Sword Blade
	if gore_enabled and blade_blood > 0.04 and has_weapon and blade_guard_marker != null and blade_tip_marker != null:
		var bg := to_local(blade_guard_marker.global_position)
		var bt := to_local(blade_tip_marker.global_position)
		var b_mid := bg.lerp(bt, 0.72)
		var a_b := clampf(blade_blood, 0.0, 1.0)
		draw_line(bg, b_mid, Color(0.32, 0.015, 0.03, 0.65 * a_b), 4.2, true)
		draw_line(bg.lerp(bt, 0.12), bt, Color(0.62, 0.04, 0.07, 0.75 * a_b), 2.4, true)

	# 1c. Subtle Cursor Aim Reticle
	if is_player and cursor_aim_enabled and not is_dead and has_weapon and not bool(severed.get("arm_r", false)):
		var aim_loc := to_local(cursor_aim_world)
		var r_col := Color(1.0, 0.84, 0.42, 0.65 if parrying else 0.42)
		draw_arc(aim_loc, 10.0, 0.0, TAU, 16, r_col, 1.4, true)
		draw_circle(aim_loc, 2.2, r_col)

	# 2. Exposed Crimson Stumps on Severed Bones
	if gore_enabled:
		for w in wounds:
			var m: Node2D = w.get("node", null)
			if m != null and is_instance_valid(m):
				var p := to_local(m.global_position)
				var r := float(w.get("radius", 9.0))
				draw_circle(p, r, Color(0.24, 0.01, 0.025, 0.94))
				draw_circle(p, r * 0.65, Color(0.64, 0.04, 0.07, 0.96))
				draw_circle(p + Vector2(1.0, 0.0), maxf(2.0, r * 0.25), Color(0.90, 0.84, 0.72, 1.0))

	# 3. Overhead Marionette Control Bar & Strings
	if not show_strings:
		return
	var string_col := Color(0.86, 0.78, 0.62, 0.44)
	var bar_col := Color(0.34, 0.22, 0.13, 0.96)
	var bar_y := -345.0
	var bar_l := Vector2(-78.0, bar_y - sin(bar_tilt) * 14.0)
	var bar_r := Vector2(78.0, bar_y + sin(bar_tilt) * 14.0)
	draw_line(bar_l, bar_r, bar_col, 7.0, true)

	var attachments := [
		["head", str_head, Vector2(0.0, bar_y)],
		["torso", bone_torso, Vector2(0.0, bar_y)],
		["arm_l", str_hand_l, Vector2(-58.0, bar_y)],
		["arm_r", str_hand_r, Vector2(58.0, bar_y)],
		["elbow_l", bone_fa_l, Vector2(-36.0, bar_y)],
		["elbow_r", bone_fa_r, Vector2(36.0, bar_y)],
		["leg_l", bone_boot_l, Vector2(-24.0, bar_y)],
		["leg_r", bone_boot_r, Vector2(24.0, bar_y)],
	]
	for item in attachments:
		var skey: String = item[0]
		var marker: Node2D = item[1]
		var bar_pt: Vector2 = item[2]
		if severed_strings.get(skey, false) or marker == null or not marker.is_visible_in_tree():
			continue
		var attach_local := to_local(marker.global_position)
		draw_line(bar_pt, attach_local, string_col, 1.35, true)
