extends Node2D
class_name FighterController

## Full Combat Puppet Fighter Controller for Strings & Steel (Godot 4.x).
## Drives AnimationPlayer combat moves, real-time 2-Bone Off-Hand IK,
## sword ribbon trails, dynamic head expressions, directional guard/parries,
## multi-limb dismemberment with dangling marionette physics, and arterial stumps.

signal request_spawn_debris(debris: PhysicsDebris)
signal request_spawn_weapon_proj(proj: WeaponProjectile)
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

## Gameplay tuning for this fighter (see FighterStats.gd). Loaded in _ready from fighter_id.
var stats: Dictionary = {}
## Multiplier on stats.max_hp (Gauntlet waves raise it for the rival).
var hp_scale: float = 1.0
## Multiplier on limb HP pools (Gauntlet waves raise it so limbs don't stay paper-thin).
var limb_hp_scale: float = 1.0
## When true, player input is ignored (title screen, round intro, round end).
var input_enabled: bool = true
## When true, bleeding no longer drains HP (set once a round is decided).
var combat_frozen: bool = false

var hp: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
## Current bleed in HP/s. Decays (clots) toward bleed_floor over time.
var bleed_rate: float = 0.0
## Permanent bleed from severed limbs that never clots.
var bleed_floor: float = 0.0
var is_dead: bool = false
var has_weapon: bool = true
var loadout_id: String = "signature"
var weapon_part_id: String = ""
var _native_weapon_id: String = ""
var has_buckler: bool = false
var half_swording: bool = false
var headgear_lost: bool = false
var rig_scale: float = 0.68

var current_action: String = ""
## Animation-time seconds since the current action started (scaled by attack speed).
var action_elapsed: float = 0.0
var _action_speed: float = 1.0
var _stamina_regen_delay: float = 0.0
var _buffered_move: String = ""
var _buffer_timer: float = 0.0
var _lmb_prev: bool = false
var _mmb_prev: bool = false
var _jab_timer: float = 0.0
var _jab_cd: float = 0.0
var _pad_aim_frame: int = -1
var _pad_aim_cache: Vector2 = Vector2.ZERO

const INPUT_BUFFER_TIME := 0.18
const STAMINA_REGEN_DELAY := 0.35
const ATTACK_MOVES := ["slash_high", "slash_low", "thrust"]
const COMBO_WINDOW := 1.1
const WINDUP_SPEED := 0.55
const TIMED_ACTIONS := ["slash_high", "slash_low", "thrust", "kick", "hurt", "parry_recoil"]
const VITAL_SLOTS := ["head", "torso"]
const STAGGER_IMMUNITY := 0.6
## Minimum blade-tip speed (px/s), swing arc (px), and recovery between cursor cuts.
const CURSOR_CUT_SPEED := 520.0
const CURSOR_CUT_MIN_ARC := 52.0
const CURSOR_CUT_RECOVERY := 0.38
const HEAVY_POWER_THRESHOLD := 0.78
const RIPOSTE_WINDOW := 0.42

var _combo_hits: int = 0
var _combo_timer: float = 0.0
var _stagger_immunity: float = 0.0
var riposte_timer: float = 0.0
var _riposte_active_attack: bool = false
var _swing_arc_px: float = 0.0
var _swing_arc_dir: Vector2 = Vector2.ZERO
var _cursor_strike_mode: String = "cut" # "cut" | "thrust"
var _rebound_ua: float = 0.0
var _rebound_wpn: float = 0.0

## Scripted aim (used by bots / tests instead of the mouse).
var aim_override_enabled: bool = false
var aim_override: Vector2 = Vector2.ZERO
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
## Blocks cursor cuts briefly after the IK re-engages (after an animated move or a parry),
## so the arm snapping back to the cursor is not mistaken for a fast committed swing.
var _cursor_rearm_timer: float = 0.0
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

# Virtual touch inputs (driven by MobileTouchController translucent wheels)
var touch_mode_active: bool = false
var touch_move: float = 0.0
var touch_parry: bool = false
var touch_low: bool = false

# Limb HP & Dismemberment state
var limb_hp: Dictionary = {}
var max_limb_hp: Dictionary = {}
var _limb_warned: Dictionary = {}
var severed: Dictionary = {}
var severed_strings: Dictionary = {}
var wounds: Array[Dictionary] = []

# Preloaded textures from rig_metadata.json
var _meta_parts: Dictionary = {}
var _fighter_parts: Dictionary = {}
var _head_textures: Dictionary = {}
var _head_part_ids: Dictionary = {}
var _unhelmed_part_id: String = ""
var _unhelmed_tex: Texture2D
var _buckler_sprite: Sprite2D
var _gore_stump_tex: Texture2D
var _stump_sprites: Array[Sprite2D] = []

# Active blade trail history [[guard_world, tip_world], ...]
var _blade_trail: Array = []
var _prev_blade_seg: Array = []

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
	GameInput.register()
	stats = FighterStats.get_stats(fighter_id)
	move_speed = float(stats["move_speed"])
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
	if stats.is_empty():
		stats = FighterStats.get_stats(fighter_id)
	max_hp = float(stats["max_hp"]) * hp_scale
	hp = max_hp
	stamina = max_stamina
	bleed_rate = 0.0
	bleed_floor = 0.0
	combat_frozen = false
	is_dead = false
	has_weapon = true
	half_swording = false
	headgear_lost = false
	_jab_timer = 0.0
	_jab_cd = 0.0
	current_action = ""
	action_elapsed = 0.0
	_action_speed = 1.0
	_stamina_regen_delay = 0.0
	_buffered_move = ""
	_buffer_timer = 0.0
	_combo_hits = 0
	_combo_timer = 0.0
	_stagger_immunity = 0.0
	riposte_timer = 0.0
	_riposte_active_attack = false
	_swing_arc_px = 0.0
	_swing_arc_dir = Vector2.ZERO
	_cursor_strike_mode = "cut"
	_rebound_ua = 0.0
	_rebound_wpn = 0.0
	aim_override_enabled = false
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
	_prev_blade_seg.clear()
	wounds.clear()

	limb_hp = {
		"head": 96.0, "torso": 150.0,
		"arm_r": 74.0, "forearm_r": 64.0,
		"arm_l": 68.0, "forearm_l": 58.0,
		"thigh_l": 76.0, "shin_l": 62.0,
		"thigh_r": 76.0, "shin_r": 62.0,
	}
	for k in limb_hp.keys():
		limb_hp[k] = float(limb_hp[k]) * limb_hp_scale
	max_limb_hp = limb_hp.duplicate()
	_limb_warned.clear()
	severed = {
		"head": false, "torso": false,
		"arm_r": false, "forearm_r": false,
		"arm_l": false, "forearm_l": false,
		"thigh_l": false, "shin_l": false,
		"thigh_r": false, "shin_r": false,
	}
	severed_strings = {"head": false, "arm_r": false, "arm_l": false, "leg_l": false, "leg_r": false}

	for b in [bone_torso, bone_head, bone_hat, bone_ua_r, bone_fa_r, bone_hand_r, bone_weapon, bone_ua_l, bone_fa_l, bone_hand_l, bone_thigh_l, bone_shin_l, bone_boot_l, bone_thigh_r, bone_shin_r, bone_boot_r]:
		if b != null:
			b.visible = true
	for st in _stump_sprites:
		if st != null and is_instance_valid(st):
			st.queue_free()
	_stump_sprites.clear()
	_reset_sprite_tints(skeleton)
	apply_loadout(loadout_id)
	if skeleton != null:
		skeleton.position = Vector2.ZERO
	if anim_player != null and anim_player.has_animation("idle"):
		anim_player.play("idle")
		anim_player.advance(0.0)
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
	_native_weapon_id = String(_fighter_parts.get("weapon", "p1_sword_long"))
	weapon_part_id = _native_weapon_id

	var map: Dictionary = stats.get("heads", FighterStats.DEFAULT["heads"])
	for k in map.keys():
		var pid: String = map[k]
		_head_part_ids[k] = pid
		if _meta_parts.has(pid):
			var tex_path: String = _meta_parts[pid].get("texture", "")
			if ResourceLoader.exists(tex_path):
				_head_textures[k] = ResourceLoader.load(tex_path)
	_unhelmed_part_id = String(stats.get("unhelmed_head", ""))
	if _unhelmed_part_id != "" and _meta_parts.has(_unhelmed_part_id):
		var u_path: String = _meta_parts[_unhelmed_part_id].get("texture", "")
		if ResourceLoader.exists(u_path):
			_unhelmed_tex = ResourceLoader.load(u_path)
	if bone_hand_l != null and _buckler_sprite == null and _meta_parts.has("p2_buckler"):
		var b_spec: Dictionary = _meta_parts["p2_buckler"]
		var b_path: String = b_spec.get("texture", "")
		if ResourceLoader.exists(b_path):
			_buckler_sprite = Sprite2D.new()
			_buckler_sprite.name = "BucklerSprite"
			_buckler_sprite.texture = ResourceLoader.load(b_path)
			_buckler_sprite.centered = false
			var b_piv: Array = b_spec.get("pivot", [60, 60])
			_buckler_sprite.offset = -Vector2(float(b_piv[0]), float(b_piv[1]))
			var b_sc := float(b_spec.get("scale", 0.72))
			_buckler_sprite.scale = Vector2(b_sc, b_sc)
			_buckler_sprite.z_index = 49
			_buckler_sprite.visible = false
			bone_hand_l.add_child(_buckler_sprite)
	if ResourceLoader.exists("res://assets/parts_v2/p1_gore_0.png"):
		_gore_stump_tex = ResourceLoader.load("res://assets/parts_v2/p1_gore_0.png")


func _meta_vec2(arr: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return fallback


func apply_loadout(id: String) -> void:
	loadout_id = id if id in FighterStats.LOADOUT_ORDER else "signature"
	half_swording = false
	match loadout_id:
		"pollaxe":
			has_buckler = false
			equip_weapon_part("p2_pollaxe")
		"buckler":
			has_buckler = true
			var sidearm := "p5_sword_rapier" if _native_weapon_id == "p5_sword_rapier" else "p1_sword_katz"
			equip_weapon_part(sidearm)
		"katzbalger":
			has_buckler = false
			equip_weapon_part("p1_sword_katz")
		_:
			has_buckler = false
			equip_weapon_part(_native_weapon_id if _native_weapon_id != "" else "p1_sword_long")
	_sync_buckler_visibility()


func equip_weapon_part(part_id: String) -> bool:
	var target_id := part_id if _meta_parts.has(part_id) else _native_weapon_id
	if target_id == "" or not _meta_parts.has(target_id) or weapon_sprite == null:
		has_weapon = true
		if weapon_sprite != null:
			weapon_sprite.visible = true
		return false
	var sw_spec: Dictionary = _meta_parts[target_id]
	var tex_path: String = sw_spec.get("texture", "")
	if not ResourceLoader.exists(tex_path):
		return false
	var sw_sockets: Dictionary = sw_spec.get("sockets", {})
	var sw_scale := float(sw_spec.get("scale", 1.0))
	var sw_pivot := _meta_vec2(sw_spec.get("pivot", [0, 0]))
	var sw_grip_front := _meta_vec2(sw_sockets.get("gripFront", sw_spec.get("pivot", [0, 0])), sw_pivot)
	var sw_grip_back := _meta_vec2(sw_sockets.get("gripBack", sw_sockets.get("pommel", [0, 0])))
	var sw_guard := _meta_vec2(sw_sockets.get("guard", [110, 52]))
	var sw_tip := _meta_vec2(sw_sockets.get("tip", [300, 52]))

	weapon_sprite.texture = ResourceLoader.load(tex_path)
	weapon_sprite.centered = false
	weapon_sprite.offset = -sw_grip_front
	weapon_sprite.scale = Vector2(sw_scale, sw_scale)
	weapon_sprite.visible = true
	if pommel_target != null:
		pommel_target.position = (sw_grip_back - sw_grip_front) * sw_scale
	if blade_guard_marker != null:
		blade_guard_marker.position = (sw_guard - sw_grip_front) * sw_scale
	if blade_tip_marker != null:
		blade_tip_marker.position = (sw_tip - sw_grip_front) * sw_scale
	weapon_part_id = target_id
	has_weapon = true
	blade_blood = 0.0
	_blade_trail.clear()
	_prev_blade_seg.clear()
	if not weapon_is_two_handed():
		half_swording = false
	limb_state_changed.emit(self)
	return true


func _sync_buckler_visibility() -> void:
	if _buckler_sprite != null:
		_buckler_sprite.visible = has_buckler and not bool(severed.get("arm_l", false)) and not bool(severed.get("forearm_l", false))


func _apply_facing() -> void:
	if skeleton != null:
		skeleton.scale = Vector2(rig_scale * float(facing), rig_scale)


func set_facing(new_facing: int) -> void:
	if new_facing == 0 or is_dead:
		return
	facing = 1 if new_facing > 0 else -1
	_apply_facing()


func play_anim(anim_name: String, blend: float = 0.08, speed: float = 1.0) -> void:
	if anim_player == null or not anim_player.has_animation(anim_name):
		return
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name, blend, speed)


func stat(key: String) -> float:
	return float(stats.get(key, FighterStats.DEFAULT.get(key, 0.0)))


## Attack wind-ups play slower than the rest of the swing so they can be read and
## reacted to (by players and the AI). Without this a slash was live 0.13 s after
## the button press, faster than human reaction time.
func _windup_mult() -> float:
	match current_action:
		"slash_high", "slash_low":
			return WINDUP_SPEED if action_elapsed < 0.13 else 1.0
		"thrust":
			return WINDUP_SPEED if action_elapsed < 0.11 else 1.0
		"kick":
			return 0.75 if action_elapsed < 0.10 else 1.0
	return 1.0


func is_armored_slot(slot: String) -> bool:
	if slot == "head" and headgear_lost:
		return false
	var slots: Array = stats.get("armored_slots", [])
	return slots.has(slot)


func is_winded() -> bool:
	return stamina < 8.0


## Fraction of normal walking speed left after leg wounds (1.0 = intact).
func get_mobility() -> float:
	var m := 1.0
	for side in ["l", "r"]:
		if bool(severed.get("thigh_" + side, false)):
			m *= 0.45
		elif bool(severed.get("shin_" + side, false)):
			m *= 0.7
	return maxf(0.2, m)


func get_move_speed() -> float:
	return move_speed * get_mobility() * (0.82 if is_winded() else 1.0)


func can_dash() -> bool:
	return not bool(severed.get("thigh_l", false)) and not bool(severed.get("thigh_r", false))


func can_kick() -> bool:
	return not bool(severed.get("thigh_r", false)) and not bool(severed.get("shin_r", false))


func can_wield() -> bool:
	return has_weapon and not bool(severed.get("arm_r", false)) and not bool(severed.get("forearm_r", false))


func _offhand_usable() -> bool:
	return not bool(severed.get("arm_l", false)) and not bool(severed.get("forearm_l", false)) and not bool(severed.get("torso", false)) and not bool(severed_strings.get("arm_l", false))


func can_jab() -> bool:
	var r_ok := not bool(severed.get("arm_r", false)) and not bool(severed.get("forearm_r", false))
	var l_ok := not bool(severed.get("arm_l", false)) and not bool(severed.get("forearm_l", false))
	return not bool(severed.get("torso", false)) and (r_ok or l_ok)


func weapon_is_two_handed() -> bool:
	if has_buckler:
		return false
	var ws: Dictionary = FighterStats.WEAPON_SPECS.get(weapon_part_id, {})
	return bool(ws.get("two_handed", true))


func _weapon_spec_val(key: String, default_val: float) -> float:
	if weapon_part_id == "" or weapon_part_id == _native_weapon_id:
		return default_val
	var ws: Dictionary = FighterStats.WEAPON_SPECS.get(weapon_part_id, {})
	return float(ws.get(key, default_val))


func get_weapon_damage_mult() -> float:
	return _weapon_spec_val("dmg", 1.0)


func get_guard_crush_mult() -> float:
	return _weapon_spec_val("guard_crush", 1.0)


func get_cut_armor_pierce() -> float:
	return clampf(_weapon_spec_val("ap_cut", 0.0) + (0.42 if half_swording else 0.0), 0.0, 0.85)


func get_thrust_armor_pierce() -> float:
	return clampf(stat("armor_pierce_thrust") + _weapon_spec_val("ap_thrust", 0.0) + (0.42 if half_swording else 0.0), 0.0, 0.88)


func get_limb_damage_mult() -> float:
	return stat("limb_damage_mult") * (0.75 if half_swording else 1.0)


func can_half_sword() -> bool:
	return not is_dead and can_wield() and weapon_is_two_handed() and _offhand_usable()


func set_half_sword(on: bool, announce: bool = true) -> bool:
	if on and not can_half_sword():
		return false
	if half_swording == on:
		return false
	half_swording = on
	if announce:
		request_sfx.emit("grip", 0.08)
		request_cut_flash.emit(global_position + Vector2(0, -145), "HALF-SWORD!" if half_swording else "LONG-POINT!", Color(0.86, 0.92, 1.0))
	limb_state_changed.emit(self)
	return true


func toggle_half_sword() -> bool:
	return set_half_sword(not half_swording, true)


## Early in an attack wind-up (before the blade commits at ~0.11-0.13), a fighter can
## abort the swing into a parry (feint-to-guard) instead of eating an incoming blow.
func can_feint_to_parry() -> bool:
	return can_wield() and (current_action == "" or (current_action in ATTACK_MOVES and action_elapsed < 0.095))


func abort_windup() -> void:
	if current_action in ATTACK_MOVES and action_elapsed < 0.095:
		current_action = ""
		_action_speed = 1.0
		_blade_trail.clear()


## Losing the off-hand means one-handed blocking: guards cost more stamina.
func get_guard_cost_mult() -> float:
	if has_buckler and _offhand_usable():
		return 0.62
	if half_swording and _offhand_usable():
		return 0.70
	if bool(severed.get("arm_l", false)) or bool(severed.get("forearm_l", false)):
		return 1.5
	if bool(severed_strings.get("arm_l", false)):
		return 1.32
	return 1.0


func effective_blade_weight() -> float:
	var w := maxf(0.42, stat("blade_weight") * _weapon_spec_val("weight", 1.0) * (0.80 if half_swording else 1.0))
	if bool(severed_strings.get("arm_r", false)):
		w *= 1.32
	if weapon_is_two_handed() and (bool(severed.get("arm_l", false)) or bool(severed.get("forearm_l", false)) or bool(severed_strings.get("arm_l", false))):
		w *= 1.16
	return w


func effective_attack_speed() -> float:
	var s := stat("attack_speed") * _weapon_spec_val("speed", 1.0) * (1.15 if half_swording else 1.0)
	if bool(severed_strings.get("arm_r", false)):
		s *= 0.82
	return s


func _spawn_weapon_projectile(flying_mode: bool, init_vel: Vector2) -> WeaponProjectile:
	if not has_weapon or weapon_sprite == null or weapon_sprite.texture == null:
		return null
	var proj := WeaponProjectile.new()
	proj.weapon_part_id = weapon_part_id if weapon_part_id != "" else _native_weapon_id
	proj.thrower = self
	var guard_w := blade_guard_marker.global_position if blade_guard_marker != null else global_position + Vector2(float(facing) * 45.0, -110.0)
	var tip_w := blade_tip_marker.global_position if blade_tip_marker != null else guard_w + Vector2(float(facing) * 120.0, 0.0)
	proj.position = guard_w.lerp(tip_w, 0.35)
	proj.rotation = (tip_w - guard_w).angle()
	var half_l := maxf(48.0, guard_w.distance_to(tip_w) * 0.55)
	var center_local := (blade_guard_marker.position + blade_tip_marker.position) * 0.35 if (blade_guard_marker != null and blade_tip_marker != null) else Vector2.ZERO
	var sc_x := maxf(0.1, weapon_sprite.scale.x)
	proj.setup_visual(weapon_sprite.texture, weapon_sprite.scale * rig_scale, weapon_sprite.offset - center_local / sc_x, half_l)
	if flying_mode:
		proj.flying = true
		proj.vel = init_vel
		proj.ang_vel = 21.0 * (1.0 if init_vel.x >= 0.0 else -1.0)
	else:
		proj.drop_from_impact(init_vel)
	has_weapon = false
	half_swording = false
	parrying = false
	_blade_trail.clear()
	weapon_sprite.visible = false
	request_spawn_weapon_proj.emit(proj)
	limb_state_changed.emit(self)
	return proj


func throw_weapon(aim_target: Vector2 = Vector2.INF) -> bool:
	if is_dead or not can_wield() or current_action != "" or stamina < 12.0:
		return false
	spend_stamina(12.0)
	var origin := global_position + Vector2(float(facing) * 55.0, -115.0)
	var tgt := aim_target
	if tgt == Vector2.INF:
		tgt = cursor_aim_world if cursor_aim_enabled else (origin + Vector2(float(facing) * 280.0, -10.0))
	var dir := tgt - origin
	if dir.x * float(facing) < 40.0:
		dir.x = float(facing) * maxf(180.0, absf(dir.x))
	dir.y = clampf(dir.y, -190.0, 140.0)
	var proj := _spawn_weapon_projectile(true, dir.normalized() * 940.0 + Vector2(0, -55.0))
	if proj == null:
		return false
	request_sfx.emit("whoosh", 0.12)
	request_cut_flash.emit(origin, "BLADE HURLED!", Color(1.0, 0.86, 0.44))
	return true


func drop_weapon(impulse: Vector2) -> WeaponProjectile:
	if is_dead or not can_wield():
		return null
	return _spawn_weapon_projectile(false, impulse)


func start_jab() -> bool:
	if is_dead or current_action != "" or _jab_cd > 0.0 or stamina < 8.0 or not can_jab():
		return false
	spend_stamina(8.0)
	parrying = false
	_jab_timer = 0.22
	_jab_cd = 0.42
	attack_serial += 1
	request_sfx.emit("whoosh", 0.22)
	return true


func is_jab_active() -> bool:
	return not is_dead and _jab_timer > 0.04 and _jab_timer <= 0.205 and can_jab()


func grant_riposte() -> void:
	riposte_timer = RIPOSTE_WINDOW


func is_riposte_ready() -> bool:
	return riposte_timer > 0.0 or _riposte_active_attack


## Physical deflection bounce when a swing clangs off a parry or heavy plate armour.
func apply_blade_rebound(strength: float = 1.0) -> void:
	var s := clampf(strength, 0.25, 1.5)
	_rebound_ua = clampf(_rebound_ua + 0.44 * s, -0.7, 0.85)
	_rebound_wpn = clampf(_rebound_wpn - 0.38 * s, -0.85, 0.7)
	_cursor_sweep_timer = 0.0
	_swing_arc_px = 0.0
	_swing_arc_dir = Vector2.ZERO
	_cursor_rearm_timer = maxf(_cursor_rearm_timer, 0.24 * s)


func spend_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_regen_delay = STAMINA_REGEN_DELAY


func start_attack(move_name: String) -> bool:
	if is_dead or current_action != "":
		return false
	if (move_name in ATTACK_MOVES) and not can_wield():
		return false
	if move_name == "kick" and not can_kick():
		return false
	var is_rip := riposte_timer > 0.0 and move_name in ATTACK_MOVES
	var cost := (12.0 if move_name != "kick" else 10.0) * stat("stamina_cost_mult") * (0.70 if is_rip else 1.0)
	if stamina < cost:
		return false

	spend_stamina(cost)
	parrying = false
	_riposte_active_attack = is_rip
	if is_rip:
		riposte_timer = 0.0
	current_action = move_name
	action_elapsed = 0.0
	_action_speed = effective_attack_speed() * (1.24 if is_rip else 1.0)
	attack_serial += 1
	play_anim(move_name, 0.05, _action_speed)
	request_sfx.emit("whoosh", 0.14)
	_update_head_expression()
	return true


func start_dash(dir_sign: float) -> void:
	if is_dead or dash_cooldown > 0.0 or stamina < 15.0 or not can_dash():
		return
	spend_stamina(15.0)
	dash_dir = 1.0 if dir_sign >= 0.0 else -1.0
	dash_timer = 0.14
	dash_cooldown = stat("dash_cooldown")
	request_sfx.emit("whoosh", 0.2)


func trigger_hurt(heavy: bool = false) -> void:
	if is_dead:
		return
	parrying = false
	riposte_timer = 0.0
	_riposte_active_attack = false
	_swing_arc_px = 0.0
	current_action = "parry_recoil" if heavy else "hurt"
	action_elapsed = 0.0
	_action_speed = 1.0
	_buffered_move = ""
	play_anim(current_action, 0.04)
	_update_head_expression()


func kill_fighter() -> void:
	if is_dead:
		return
	is_dead = true
	parrying = false
	current_action = "death"
	_action_speed = 1.0
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
		if String(anim_name) in ["hurt", "parry_recoil"]:
			_stagger_immunity = STAGGER_IMMUNITY
		current_action = ""
		_riposte_active_attack = false
		_blade_trail.clear()
		play_anim("idle")
		_update_head_expression()


func _process(delta: float) -> void:
	_prev_blade_seg = get_blade_segment()
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	_stamina_regen_delay = maxf(0.0, _stamina_regen_delay - delta)
	if _stamina_regen_delay <= 0.0:
		var regen := stat("stamina_regen")
		if parrying:
			regen *= 0.36
		elif current_action != "" or _cursor_sweep_timer > 0.0:
			regen *= 0.35
		stamina = minf(max_stamina, stamina + regen * delta)

	# Bleeding: fresh wounds clot exponentially toward the permanent stump bleed.
	if bleed_rate > bleed_floor:
		bleed_rate = bleed_floor + (bleed_rate - bleed_floor) * exp(-0.35 * delta)
	if bleed_rate > 0.0 and not is_dead:
		if not combat_frozen:
			hp = maxf(0.0, hp - bleed_rate * delta)
		bleed_emit_timer -= delta
		if gore_enabled and bleed_emit_timer <= 0.0:
			bleed_emit_timer = randf_range(0.06, 0.14)
			for w in wounds:
				var m: Node2D = w.get("node", null)
				if m != null and is_instance_valid(m):
					request_blood_spray.emit(m.global_position, Vector2(randf_range(-90, 90), randf_range(-120, -20)), 2, false)
		if hp <= 0.0:
			if head_sprite != null:
				request_cut_flash.emit(head_sprite.global_position, "BLED OUT", Color(0.85, 0.2, 0.22))
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
		position.x = clampf(position.x + dash_dir * stat("dash_speed") * get_mobility() * delta, 120.0, 1160.0)
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
		action_elapsed += delta * _action_speed * _windup_mult()
	if anim_player != null:
		anim_player.speed_scale = _windup_mult()

	_cursor_sweep_timer = maxf(0.0, _cursor_sweep_timer - delta)
	_cursor_whoosh_cd = maxf(0.0, _cursor_whoosh_cd - delta)
	_cursor_slash_cd = maxf(0.0, _cursor_slash_cd - delta)
	_cursor_rearm_timer = maxf(0.0, _cursor_rearm_timer - delta)
	_buffer_timer = maxf(0.0, _buffer_timer - delta)
	_stagger_immunity = maxf(0.0, _stagger_immunity - delta)
	riposte_timer = maxf(0.0, riposte_timer - delta)
	_jab_timer = maxf(0.0, _jab_timer - delta)
	_jab_cd = maxf(0.0, _jab_cd - delta)
	if half_swording and not can_half_sword():
		half_swording = false
	_sync_buckler_visibility()
	var reb_decay := exp(-9.5 * delta)
	_rebound_ua *= reb_decay
	_rebound_wpn *= reb_decay
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_hits = 0

	if not is_dead and is_player and input_enabled:
		_process_player_input(delta)
	elif is_player and not is_dead and not input_enabled and current_action == "":
		parrying = false
		play_anim("idle", 0.1)

	# Advance AnimationPlayer BEFORE procedural IK so animations never overwrite cursor/pommel IK!
	if anim_player != null:
		anim_player.advance(delta)
		# Watchdog: an action whose animation was replaced (or stopped) can never receive
		# animation_finished, which would freeze the fighter forever. Recover instead.
		if current_action in TIMED_ACTIONS and String(anim_player.current_animation) != current_action:
			current_action = ""
			_action_speed = 1.0
			_blade_trail.clear()

	var use_ik_arm := (is_player and cursor_aim_enabled and input_enabled) or (not is_player and aim_override_enabled)
	if not is_dead:
		if use_ik_arm and can_wield() and current_action == "":
			_solve_sword_arm_to_cursor(delta)
		elif bone_ua_r != null and bone_fa_r != null and bone_weapon != null:
			_cursor_rearm_timer = 0.22
			_cursor_sweep_timer = 0.0
			_swing_arc_px = 0.0
			_riposte_active_attack = _riposte_active_attack and current_action != ""
			_ik_ua_r = bone_ua_r.rotation
			_ik_fa_r = bone_fa_r.rotation
			_ik_wpn_r = bone_weapon.rotation
		if bool(severed_strings.get("head", false)) and bone_head != null:
			bone_head.rotation += deg_to_rad(22.0)

	# Maintain Off-hand 2-bone IK unless dead, one-handed without buckler, or left arm injured/severed
	var use_offhand_ik: bool = _offhand_usable() and (has_buckler or (has_weapon and weapon_is_two_handed() and not bool(severed.get("arm_r", false))))
	if enable_offhand_ik and use_offhand_ik and not is_dead and current_action != "hurt" and current_action != "parry_recoil":
		_solve_offhand_two_bone_ik()
	elif not is_dead and not bool(severed.get("arm_l", false)) and bone_ua_l != null:
		# Natural counterbalance guard behind torso when one-handed or disarmed
		bone_ua_l.rotation = lerp_angle(bone_ua_l.rotation, deg_to_rad(-28.0), 8.0 * delta)
		if bone_fa_l != null:
			bone_fa_l.rotation = lerp_angle(bone_fa_l.rotation, deg_to_rad(-34.0), 8.0 * delta)

	# Quick gauntlet jab / buckler bash arm extension when disarmed or bashing
	if _jab_timer > 0.0 and not is_dead:
		var jab_ext := sin(clampf(1.0 - _jab_timer / 0.22, 0.0, 1.0) * PI)
		var use_left_jab := (has_buckler and _offhand_usable()) or bool(severed.get("arm_r", false)) or bool(severed.get("forearm_r", false))
		if use_left_jab and bone_ua_l != null and bone_fa_l != null:
			bone_ua_l.rotation = lerpf(bone_ua_l.rotation, deg_to_rad(-84.0), jab_ext)
			bone_fa_l.rotation = lerpf(bone_fa_l.rotation, deg_to_rad(-8.0), jab_ext)
		elif bone_ua_r != null and bone_fa_r != null:
			bone_ua_r.rotation = lerpf(bone_ua_r.rotation, deg_to_rad(-86.0), jab_ext)
			bone_fa_r.rotation = lerpf(bone_fa_r.rotation, deg_to_rad(-6.0), jab_ext)

	# Sword trail tracking during active attacks
	if is_blade_active() and has_weapon and blade_guard_marker != null and blade_tip_marker != null:
		_blade_trail.append([blade_guard_marker.global_position, blade_tip_marker.global_position])
		if _blade_trail.size() > 8:
			_blade_trail.pop_front()
	elif _blade_trail.size() > 0:
		_blade_trail.pop_front()

	_update_head_expression()
	queue_redraw()


## Right-stick aim (calibrated against the stick's resting offset). Cached once per frame.
func _read_pad_aim() -> Vector2:
	var frame := Engine.get_process_frames()
	if frame == _pad_aim_frame:
		return _pad_aim_cache
	_pad_aim_frame = frame
	var res := Vector2.ZERO
	for pid in Input.get_connected_joypads():
		var rx := Input.get_joy_axis(pid, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(pid, JOY_AXIS_RIGHT_Y)
		if not _pad_rest_calibrated:
			_pad_rest_calibrated = true
			_pad_rest_rx = rx
			_pad_rest_ry = ry
		if absf(rx - _pad_rest_rx) > 0.28:
			res.x = clampf(rx - _pad_rest_rx, -1.0, 1.0)
		if absf(ry - _pad_rest_ry) > 0.28:
			res.y = clampf(ry - _pad_rest_ry, -1.0, 1.0)
	_pad_aim_cache = res
	return res


func _mouse_in_stage() -> bool:
	return get_viewport().get_mouse_position().y >= 106.0


func _process_player_input(delta: float) -> void:
	var pad_aim := _read_pad_aim()
	var low_held := touch_low or Input.is_action_pressed("guard_low") or pad_aim.y > 0.45
	if cursor_aim_enabled and (not touch_mode_active or aim_override_enabled):
		var m_y := aim_override.y if aim_override_enabled else get_global_mouse_position().y
		if m_y > position.y - 60.0 and m_y >= 110.0:
			low_held = true
	guard_zone = "low" if low_held else "high"

	var mouse_in_stage := not touch_mode_active and _mouse_in_stage()
	var lmb := mouse_in_stage and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var lmb_edge := lmb and not _lmb_prev
	_lmb_prev = lmb
	var mmb := mouse_in_stage and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var mmb_edge := mmb and not _mmb_prev
	_mmb_prev = mmb

	if Input.is_action_just_pressed("half_sword"):
		toggle_half_sword()
	if Input.is_action_just_pressed("throw_weapon") or mmb_edge:
		if throw_weapon():
			return

	# Queue one-shot moves on the press edge; the buffer lets a press made slightly
	# before the current action ends still come out, instead of being swallowed.
	if Input.is_action_just_pressed("slash") or (not cursor_aim_enabled and lmb_edge) or (not can_wield() and lmb_edge):
		_buffered_move = "slash" if can_wield() else "jab"
		_buffer_timer = INPUT_BUFFER_TIME
	elif Input.is_action_just_pressed("thrust"):
		_buffered_move = "thrust" if can_wield() else "jab"
		_buffer_timer = INPUT_BUFFER_TIME
	elif Input.is_action_just_pressed("kick"):
		_buffered_move = "kick"
		_buffer_timer = INPUT_BUFFER_TIME

	var parry_held := touch_parry or Input.is_action_pressed("parry") or (mouse_in_stage and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if parry_held and can_feint_to_parry():
		abort_windup()
		if not parrying:
			parry_hold_time = 0.0
		else:
			parry_hold_time += delta
		parrying = true
		play_anim("parry_low" if guard_zone == "low" else "parry", 0.06)
		return
	else:
		parrying = false
		parry_hold_time = 99.0

	var mv := clampf(touch_move + Input.get_axis("move_left", "move_right"), -1.0, 1.0)

	if Input.is_action_just_pressed("dash"):
		start_dash(mv if absf(mv) >= 0.2 else float(facing))

	if _buffer_timer > 0.0 and _buffered_move != "" and current_action == "":
		var move_name := _buffered_move
		if move_name == "jab":
			if start_jab():
				_buffered_move = ""
				_buffer_timer = 0.0
		else:
			if move_name == "slash":
				move_name = "slash_low" if low_held else "slash_high"
			if start_attack(move_name):
				_buffered_move = ""
				_buffer_timer = 0.0

	if current_action == "":
		bar_tilt = lerpf(bar_tilt, mv * 0.08, 8.0 * delta)
		if absf(mv) > 0.12:
			position.x = clampf(position.x + mv * get_move_speed() * delta, 120.0, 1160.0)
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


func is_thrust_strike() -> bool:
	if current_action == "thrust":
		return true
	return current_action == "" and _cursor_sweep_timer > 0.0 and _cursor_strike_mode == "thrust"


func get_strike_power() -> float:
	var pwr := 1.0
	match current_action:
		"slash_high", "slash_low", "thrust":
			pwr = 1.0
		_:
			pwr = _cursor_power_now()
	# Without the off-hand on the pommel, two-handed cuts lose leverage.
	if bool(severed.get("arm_l", false)) or bool(severed.get("forearm_l", false)):
		pwr *= 0.80
	elif bool(severed_strings.get("arm_l", false)):
		pwr *= 0.90
	# Exhausted fighters swing weakly.
	if stamina < 10.0:
		pwr *= 0.78
	return pwr


func _step_angle_capped(cur: float, tgt: float, k_blend: float, max_step: float) -> float:
	var d := wrapf(tgt - cur, -PI, PI)
	return cur + clampf(d * k_blend, -max_step, max_step)


func _solve_sword_arm_to_cursor(delta: float) -> void:
	if bone_torso == null or bone_ua_r == null or bone_fa_r == null or bone_hand_r == null or bone_weapon == null:
		return

	var dt_safe := maxf(0.005, delta)
	var pad_aim := _read_pad_aim()
	var rx := pad_aim.x
	var ry := pad_aim.y
	var vp_mouse := get_viewport().get_mouse_position()
	if vp_mouse.distance_to(_last_mouse_vp_pos) > 1.5:
		_last_mouse_vp_pos = vp_mouse
		_using_pad_aim = false
	elif absf(rx) > 0.28 or absf(ry) > 0.28:
		_using_pad_aim = true

	var raw_tgt := cursor_aim_world
	if aim_override_enabled:
		raw_tgt = aim_override
	elif touch_mode_active:
		raw_tgt = global_position + Vector2(float(facing) * 122.0, -114.0)
	elif _using_pad_aim and (absf(rx) > 0.28 or absf(ry) > 0.28):
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
	var weight := effective_blade_weight()
	var rip_mult := 1.22 if riposte_timer > 0.0 else 1.0
	var max_aim_step := (1950.0 / weight) * rip_mult * delta
	var aim_delta := (raw_tgt - cursor_aim_world) * minf(1.0, 25.0 * delta)
	cursor_aim_world += aim_delta.limit_length(max_aim_step)

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

	var k := minf(1.0, 23.0 * delta)
	var slew_scale := (rip_mult / weight) * delta
	_ik_ua_r = _step_angle_capped(_ik_ua_r, ua_target_rot, k, 12.6 * slew_scale)
	_ik_fa_r = _step_angle_capped(_ik_fa_r, fa_target_rot, k, 15.2 * slew_scale)
	_ik_wpn_r = _step_angle_capped(_ik_wpn_r, wrist_cock, k, 17.6 * slew_scale)

	bone_ua_r.rotation = _ik_ua_r + _rebound_ua
	bone_fa_r.rotation = _ik_fa_r
	bone_hand_r.rotation = 0.0
	bone_weapon.rotation = _ik_wpn_r + _rebound_wpn

	# Measure true fighter-local blade-tip velocity & swing arc AFTER applying IK!
	if blade_tip_marker != null:
		var cur_tip_local := to_local(blade_tip_marker.global_position)
		if _prev_tip_local == Vector2.ZERO:
			_prev_tip_local = cur_tip_local
		var tip_delta := cur_tip_local - _prev_tip_local
		var inst_tip_spd := tip_delta.length() / dt_safe
		_prev_tip_local = cur_tip_local
		var spd_blend := 22.0 if inst_tip_spd > _blade_tip_speed else 12.0
		_blade_tip_speed = lerpf(_blade_tip_speed, inst_tip_spd, minf(1.0, spd_blend * delta))

		# Accumulate continuous swing arc so tiny wrist splashes cannot masquerade as cleaves.
		if inst_tip_spd >= 300.0 and not parrying and _cursor_rearm_timer <= 0.0:
			var step_dir := tip_delta.normalized()
			if _swing_arc_dir.length_squared() < 0.1 or _swing_arc_dir.dot(step_dir) >= 0.22:
				_swing_arc_px = minf(320.0, _swing_arc_px + tip_delta.length())
				_swing_arc_dir = (_swing_arc_dir * 0.65 + step_dir * 0.35).normalized()
			else:
				_swing_arc_px = tip_delta.length()
				_swing_arc_dir = step_dir
		else:
			_swing_arc_px = maxf(0.0, _swing_arc_px - 540.0 * delta)
			if _swing_arc_px <= 1.0:
				_swing_arc_dir = Vector2.ZERO

		if parrying:
			_cursor_rearm_timer = maxf(_cursor_rearm_timer, 0.18)
		if is_player and inst_tip_spd >= 340.0 and not parrying and _cursor_rearm_timer <= 0.0:
			var tip_dir := tip_delta.normalized()
			var blade_dir_local := Vector2.RIGHT
			if blade_guard_marker != null:
				var bv := cur_tip_local - to_local(blade_guard_marker.global_position)
				if bv.length_squared() > 4.0:
					blade_dir_local = bv.normalized()
			var axial := tip_dir.dot(blade_dir_local)
			var perp := sqrt(maxf(0.0, 1.0 - axial * axial))
			# Pulling the sword backward toward our own body is a withdrawal, not an attack!
			var withdrawing := axial < -0.38 and perp < 0.72
			if withdrawing:
				_cursor_sweep_timer = 0.0
			else:
				var fresh_swing := _cursor_sweep_timer <= 0.0 or _cursor_last_dir.dot(tip_dir) < 0.25
				if fresh_swing and inst_tip_spd >= CURSOR_CUT_SPEED and _swing_arc_px >= CURSOR_CUT_MIN_ARC and _cursor_slash_cd <= 0.0:
					_cursor_strike_mode = "thrust" if (axial > 0.72 and perp < 0.68) else "cut"
					var is_rip := riposte_timer > 0.0
					var est_pwr := _cursor_power_now()
					var cost := (5.0 + 9.0 * est_pwr) * stat("stamina_cost_mult") * (0.70 if is_rip else 1.0)
					if stamina >= cost:
						spend_stamina(cost)
						_riposte_active_attack = is_rip
						if is_rip:
							riposte_timer = 0.0
						attack_serial += 1
						_cursor_slash_cd = CURSOR_CUT_RECOVERY
						_cursor_last_dir = tip_dir
						_cursor_sweep_timer = 0.15
						if _cursor_whoosh_cd <= 0.0:
							_cursor_whoosh_cd = 0.22
							request_sfx.emit("whoosh", 0.16)
				elif _cursor_sweep_timer > 0.0 and _cursor_last_dir.dot(tip_dir) >= 0.25:
					_cursor_sweep_timer = 0.14


func _cursor_power_now() -> float:
	var spd_f := clampf((_blade_tip_speed - 380.0) / 920.0, 0.18, 1.0)
	var arc_f := clampf((_swing_arc_px - 42.0) / 105.0, 0.18, 1.0)
	var pwr := clampf(spd_f * (0.28 + 0.72 * arc_f), 0.18, 1.0)
	if _riposte_active_attack or riposte_timer > 0.0:
		pwr = minf(1.0, pwr * 1.20)
	return pwr


func _cursor_power_for_speed(spd: float) -> float:
	return clampf((spd - 380.0) / 920.0, 0.18, 1.0)


func get_blade_tip_speed() -> float:
	return _blade_tip_speed


func is_kick_active() -> bool:
	return not is_dead and current_action == "kick" and action_elapsed >= 0.10 and action_elapsed <= 0.28 and can_kick()


func is_perfect_parry() -> bool:
	var win := (stat("perfect_parry_window") + (0.06 if has_buckler and _offhand_usable() else 0.0)) * (0.65 if bool(severed_strings.get("head", false)) else 1.0)
	return parrying and parry_hold_time <= win


## True while this fighter's attack is visibly coming (windup or active frames).
## For cursor fighters this includes the blade visibly picking up speed, so the AI
## can read a mouse swing the way a human reads a wind-up.
func is_attack_threat() -> bool:
	if is_dead:
		return false
	if current_action in ATTACK_MOVES and action_elapsed <= 0.36:
		return true
	if is_blade_active() or is_jab_active():
		return true
	return is_player and cursor_aim_enabled and current_action == "" and can_wield() and _blade_tip_speed > 320.0 and _swing_arc_px >= 38.0 and stamina >= 5.0 * stat("stamina_cost_mult")


func get_blade_segment() -> Array:
	if not has_weapon or severed.get("arm_r", false) or severed.get("forearm_r", false) or severed.get("torso", false):
		return []
	if blade_guard_marker == null or blade_tip_marker == null:
		return []
	var g := blade_guard_marker.global_position
	var t := blade_tip_marker.global_position
	if half_swording:
		g = g.lerp(t, 0.36)
	return [g, t]


## Current blade segment plus the swept path from the previous frame, so a fast mouse
## flick (3000+ px/s) cannot tunnel across a defender's sword in a single frame.
func get_swept_blade_segments() -> Array:
	var cur := get_blade_segment()
	if cur.size() != 2:
		return []
	if _prev_blade_seg.size() != 2:
		return [cur]
	var g0: Vector2 = _prev_blade_seg[0]
	var t0: Vector2 = _prev_blade_seg[1]
	var g1: Vector2 = cur[0]
	var t1: Vector2 = cur[1]
	if t0.distance_squared_to(t1) < 324.0 and g0.distance_squared_to(g1) < 324.0:
		return [cur]
	return [cur, [t0, t1], [(g0 + t0) * 0.5, (g1 + t1) * 0.5], [g0, g1]]


func get_body_segments() -> Array:
	var segs: Array = []
	if bone_pelvis == null:
		return segs
	if not severed.get("torso", false) and bone_torso != null:
		var neck_pt := bone_head.global_position if bone_head != null else bone_torso.to_global(Vector2(0, -85))
		segs.append(["torso", bone_pelvis.global_position, neck_pt, 21.0])
		if not severed.get("head", false) and bone_head != null:
			var crown_pt := str_head.global_position if str_head != null else bone_head.to_global(Vector2(0, -45))
			segs.append(["head", bone_head.global_position, crown_pt, 19.0])
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


## Overhead live marionette strings exposed to high slashes (above the crown / hands).
func get_live_string_segments() -> Array:
	var out: Array = []
	if is_dead or not show_strings:
		return out
	var bar_y := -345.0
	for item in [
		["head", str_head, Vector2(0.0, bar_y)],
		["arm_l", str_hand_l, Vector2(-58.0, bar_y)],
		["arm_r", str_hand_r, Vector2(58.0, bar_y)],
	]:
		var skey: String = item[0]
		var marker: Node2D = item[1]
		var bar_local: Vector2 = item[2]
		if bool(severed_strings.get(skey, false)) or marker == null or not marker.is_visible_in_tree():
			continue
		var top_w := to_global(bar_local)
		var bot_w := marker.global_position + Vector2(0, -32.0)
		if bot_w.y > top_w.y + 24.0:
			out.append([skey, top_w, bot_w])
	return out


func cut_live_string(skey: String, hit_pt: Vector2) -> bool:
	if is_dead or bool(severed_strings.get(skey, false)):
		return false
	severed_strings[skey] = true
	request_sfx.emit("snap", 0.10)
	var label := "STRING CUT!"
	match skey:
		"arm_l": label = "OFF-STRING CUT!"
		"arm_r": label = "SWORD STRING CUT!"
		"head": label = "HEAD STRING CUT!"
	request_cut_flash.emit(hit_pt, label, Color(0.96, 0.86, 0.50))
	limb_state_changed.emit(self)
	return true


func apply_blade_damage(slot: String, dmg: float, hit_pt: Vector2, swing_dir: Vector2, one_hit_sever: bool, attacker_heavy: bool = false, impact_power: float = 1.0, attacker_limb_mult: float = 1.0, blade_pos_frac: float = 0.75, is_thrust: bool = false, armor_pierce: float = 0.0) -> bool:
	if is_dead:
		return false

	# Armoured slots mitigate hits unless staggered by a parry; thrusts, pollaxes & half-swording pierce gaps.
	var armored_slot: bool = is_armored_slot(slot)
	var is_counter: bool = current_action == "parry_recoil"
	var armor_mult: float = 1.0
	if armored_slot and not is_counter:
		armor_mult = stat("armor_mult")
		if armor_pierce > 0.0:
			armor_mult = lerpf(armor_mult, 1.0, clampf(armor_pierce, 0.0, 0.88))
	var counter_mult: float = 1.28 if is_counter else 1.0
	var pwr: float = clampf(impact_power, 0.15, 1.0)
	# Blade sweet-spot: outer half of blade cuts cleanly; hilt/ricasso bumps only bruise.
	var sweet_mult: float = 1.0
	var limb_sweet: float = 1.0
	if not is_thrust:
		if blade_pos_frac < 0.28:
			sweet_mult = 0.35
			limb_sweet = 0.22
		elif blade_pos_frac < 0.42:
			sweet_mult = 0.72
			limb_sweet = 0.65

	# Combo scaling: each extra hit landing inside the combo window does less damage.
	var combo_mult: float = maxf(0.4, 1.0 - 0.2 * float(_combo_hits))
	_combo_hits += 1
	_combo_timer = COMBO_WINDOW
	var final_dmg: float = dmg * armor_mult * counter_mult * pwr * sweet_mult * combo_mult
	var limb_dmg: float = dmg * (1.08 if attacker_heavy else 0.75) * armor_mult * counter_mult * pwr * limb_sweet * attacker_limb_mult * combo_mult
	if is_thrust:
		limb_dmg *= 0.45

	hp = maxf(0.0, hp - final_dmg)
	bleed_rate += final_dmg * (0.075 if is_thrust else 0.045)
	knockback_vx += swing_dir.x * (215.0 * pwr * pwr * sweet_mult)
	limb_hp[slot] = maxf(0.0, float(limb_hp.get(slot, 80.0)) - limb_dmg)
	if is_counter:
		request_cut_flash.emit(hit_pt, "COUNTER!", Color(1.0, 0.78, 0.32))

	var node_ref: Node2D = _slot_stump_anchor(slot)
	if node_ref != null and wounds.size() < 10 and pwr >= 0.55:
		wounds.append({"node": node_ref, "radius": 8.0})
	_stain_limb_bloody(node_ref)

	request_sfx.emit("flesh", 0.14)
	var drop_cnt := maxi(3, int(round((22.0 if gore_enabled else 6.0) * pwr * sweet_mult)))
	request_blood_spray.emit(hit_pt, swing_dir * (320.0 * pwr) + Vector2(0, -130.0 * pwr), drop_cnt, false)

	var staggered: bool = current_action in ["parry_recoil", "hurt"]
	var wounded_exec: bool = staggered and hp < 0.40 * max_hp
	var cur_lhp: float = float(limb_hp.get(slot, 1.0))
	var max_lhp: float = maxf(1.0, float(max_limb_hp.get(slot, 80.0)))
	var limb_frac: float = cur_lhp / max_lhp
	var limb_depleted: bool = cur_lhp <= 0.0
	var lethal_finish: bool = hp <= 0.0

	# Earned dismemberment rules:
	# - Thrusts pierce rather than chopping limbs off.
	# - Hilt bumps & small splashes NEVER pop limbs or slice fighters in half (even in 1-Hit Sever mode).
	# - Torso bisection ("slice in half") is reserved for true full-momentum sweet-spot killing cleaves!
	# - Headshot blows can knock off hats / crack off helmets first, leaving the bare neck open to decapitation!
	var should_sever := false
	if not is_thrust and not bool(severed.get(slot, false)):
		if one_hit_sever:
			should_sever = pwr >= 0.65 and blade_pos_frac >= 0.32
		else:
			var can_chop := attacker_heavy and pwr >= HEAVY_POWER_THRESHOLD and blade_pos_frac >= 0.38
			if slot == "torso":
				should_sever = can_chop and lethal_finish and pwr >= 0.92 and blade_pos_frac >= 0.45
			elif slot == "head":
				var bare_neck_chop := limb_depleted and not is_armored_slot("head") and pwr >= 0.84
				should_sever = can_chop and ((lethal_finish and pwr >= 0.82) or (staggered and hp < 0.20 * max_hp and pwr >= 0.85) or bare_neck_chop)
			else:
				should_sever = can_chop and (limb_depleted or (lethal_finish and pwr >= 0.82) or (wounded_exec and limb_frac < 0.55))

	if not should_sever and slot == "head" and _has_removable_headgear() and pwr >= 0.58 and limb_frac <= 0.62 and hp > 0.0:
		_pop_headgear(swing_dir)

	if should_sever:
		if lethal_finish and slot == "torso" and randf() < 0.40 and not bool(severed.get("head", false)):
			slot = "head"
		sever_limb(slot, hit_pt, swing_dir)
		return true
	else:
		if hp <= 0.0:
			if is_thrust and pwr >= 0.65:
				request_cut_flash.emit(hit_pt, "IMPALED!", Color(0.96, 0.24, 0.26))
			kill_fighter()
		else:
			if not (slot in VITAL_SLOTS) and limb_frac <= 0.38 and not bool(_limb_warned.get(slot, false)):
				_limb_warned[slot] = true
				_stain_limb_bloody(node_ref)
				request_cut_flash.emit(hit_pt, _limb_wound_label(slot), Color(1.0, 0.56, 0.28))
			if pwr * sweet_mult >= 0.68 and _stagger_immunity <= 0.0 and current_action != "hurt" and current_action != "parry_recoil":
				trigger_hurt(false)
		return false


func _limb_wound_label(slot: String) -> String:
	match slot:
		"arm_r", "forearm_r": return "SWORD ARM MANGLED!"
		"arm_l", "forearm_l": return "OFF-ARM MANGLED!"
		"thigh_l", "shin_l", "thigh_r", "shin_r": return "LEG CRIPPLED!"
	return "WOUNDED!"


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
	# Fresh arterial gush that clots over ~10 s, plus a small permanent stump bleed.
	bleed_rate += 5.0
	bleed_floor += 0.9
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


func _has_removable_headgear() -> bool:
	if headgear_lost or bool(severed.get("head", false)):
		return false
	if bone_hat != null and bone_hat.get_child_count() > 0:
		return true
	return _unhelmed_tex != null


func _pop_headgear(swing_dir: Vector2) -> void:
	if not _has_removable_headgear() or bone_head == null:
		return
	headgear_lost = true
	var deb := PhysicsDebris.new()
	deb.vel = swing_dir * 270.0 + Vector2(-float(facing) * 60.0, -245.0)
	deb.ang_vel = randf_range(-11.5, 11.5)
	deb.floor_y = 560.0
	deb.dangling = false
	deb.gore_enabled = false
	deb.scale = Vector2(float(facing) * rig_scale, rig_scale)
	var label := "HAT KNOCKED OFF!"

	if bone_hat != null and bone_hat.get_child_count() > 0:
		deb.position = bone_hat.global_position
		_clone_bone_tree_visuals(bone_hat, deb, true, false)
		bone_hat.visible = false
		if fighter_id == "fechtmeister":
			label = "BURGONET KNOCKED OFF!"
	elif head_sprite != null and _unhelmed_tex != null:
		deb.position = bone_head.global_position
		var helm_sp := head_sprite.duplicate() as Sprite2D
		deb.add_child(helm_sp)
		label = "HELMET CRACKED!" if fighter_id == "black_knight" else "MASK TORN OFF!"
		_update_head_expression()

	request_spawn_debris.emit(deb)
	request_sfx.emit("clatter", 0.12)
	request_cut_flash.emit(bone_head.global_position + Vector2(0, -28), label, Color(0.96, 0.84, 0.44))
	limb_state_changed.emit(self)


func _apply_head_part_transform(sp: Sprite2D, part_id: String) -> void:
	if sp == null or part_id == "" or not _meta_parts.has(part_id):
		return
	var spec: Dictionary = _meta_parts[part_id]
	var piv := _meta_vec2(spec.get("pivot", [0, 0]))
	var sc := float(spec.get("scale", 1.0))
	sp.offset = -piv
	sp.scale = Vector2(sc, sc)


func _clone_bone_tree_visuals(src_node: Node2D, dst_parent: Node2D, is_root: bool, force_dead_head: bool) -> void:
	for c in src_node.get_children():
		if not c is Node2D or not (c as Node2D).visible:
			continue
		if c is Sprite2D:
			var sp := (c as Sprite2D).duplicate() as Sprite2D
			if force_dead_head and c == head_sprite:
				if headgear_lost and _unhelmed_tex != null:
					sp.texture = _unhelmed_tex
					_apply_head_part_transform(sp, _unhelmed_part_id)
				elif _head_textures.has("dead"):
					sp.texture = _head_textures["dead"]
					_apply_head_part_transform(sp, String(_head_part_ids.get("dead", "")))
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
	if headgear_lost and _unhelmed_tex != null:
		head_sprite.texture = _unhelmed_tex
		_apply_head_part_transform(head_sprite, _unhelmed_part_id)
		return
	var expr := "calm"
	if is_dead:
		expr = "dead"
	elif current_action == "hurt" or current_action == "parry_recoil":
		expr = "pain"
	elif current_action in ["slash_high", "slash_low", "thrust", "kick"]:
		expr = "yell"
	elif hp < 0.55 * max_hp:
		expr = "bloody"
	if _head_textures.has(expr):
		head_sprite.texture = _head_textures[expr]
		_apply_head_part_transform(head_sprite, String(_head_part_ids.get(expr, "")))


func _solve_offhand_two_bone_ik() -> void:
	if bone_torso == null or bone_ua_l == null or bone_fa_l == null or bone_hand_l == null:
		return

	var sh_pos := bone_ua_l.position
	var tgt_pos := Vector2.ZERO
	if has_buckler:
		var buckler_y := -30.0 if guard_zone == "low" else (-88.0 if parrying else -68.0)
		var buckler_x := 104.0 if parrying else 90.0
		tgt_pos = Vector2(buckler_x, buckler_y)
	elif half_swording and blade_guard_marker != null and blade_tip_marker != null:
		tgt_pos = bone_torso.to_local(blade_guard_marker.global_position.lerp(blade_tip_marker.global_position, 0.42))
	elif pommel_target != null:
		tgt_pos = bone_torso.to_local(pommel_target.global_position)
	else:
		return
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
	# 1. Weapon Motion Slash Ribbon (intensity & colour reflect real strike power!)
	if _blade_trail.size() >= 2:
		var pwr_vis := get_strike_power()
		var heavy_vis := pwr_vis >= HEAVY_POWER_THRESHOLD or is_riposte_ready()
		var weak_vis := pwr_vis < 0.45
		for i in range(_blade_trail.size() - 1):
			var a_pts: Array = _blade_trail[i]
			var b_pts: Array = _blade_trail[i + 1]
			if Vector2(a_pts[1]).distance_squared_to(Vector2(b_pts[1])) < 16.0:
				continue
			var frac := float(i + 1) / float(_blade_trail.size())
			var rib_alpha := (0.12 if weak_vis else (0.36 if heavy_vis else 0.25)) * frac * frac
			var col := Color(1.0, 0.90, 0.58, rib_alpha) if heavy_vis else (Color(0.75, 0.78, 0.84, rib_alpha) if weak_vis else Color(0.92, 0.95, 1.0, rib_alpha))
			var pts := PackedVector2Array([
				to_local(a_pts[0]), to_local(a_pts[1]),
				to_local(b_pts[1]), to_local(b_pts[0])
			])
			if Geometry2D.triangulate_polygon(pts).size() > 0:
				draw_colored_polygon(pts, col)
			var edge_col := Color(1.0, 0.94, 0.68, 0.85 * frac) if heavy_vis else (Color(0.82, 0.84, 0.88, 0.35 * frac) if weak_vis else Color(1.0, 0.98, 0.90, 0.65 * frac))
			var edge_w := 3.4 if heavy_vis else (1.4 if weak_vis else 2.4)
			draw_line(to_local(a_pts[1]), to_local(b_pts[1]), edge_col, edge_w, true)

	# 1a. Golden Riposte Gleam along the blade right after a successful block/parry
	if riposte_timer > 0.0 and has_weapon and blade_guard_marker != null and blade_tip_marker != null:
		var rg := to_local(blade_guard_marker.global_position)
		var rt := to_local(blade_tip_marker.global_position)
		var r_alpha := clampf(riposte_timer / RIPOSTE_WINDOW, 0.0, 1.0) * 0.7
		draw_line(rg, rt, Color(1.0, 0.88, 0.42, r_alpha), 3.2, true)
	elif half_swording and has_weapon and blade_guard_marker != null and blade_tip_marker != null:
		var hg := to_local(blade_guard_marker.global_position.lerp(blade_tip_marker.global_position, 0.36))
		var ht := to_local(blade_tip_marker.global_position)
		draw_line(hg, ht, Color(0.72, 0.88, 1.0, 0.45), 2.6, true)

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
