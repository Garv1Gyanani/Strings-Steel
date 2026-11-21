class_name AIController
extends RefCounted

## Rival AI for Strings & Steel.
##
## - Perceives threats (both button wind-ups and fast mouse-blade accelerations) with a
##   human-like reaction delay.
## - Uses real-time 2-bone sword-arm IK in neutral and guard so its blade visibly shadows
##   the opponent's weapon and physically meets incoming cuts on high/low lines.
## - Continuous footwork every frame: yields ground against live flurries, closes in on
##   whiffs/staggers, and kicks or cuts around held cursor guards.
## - Spacing, tempo and attack preferences come from the piloted fighter's FighterStats.

enum State { NEUTRAL, DEFEND, RETREAT }

const DIFFICULTY := {
	"normal": {
		"reaction": 0.24, "reaction_jitter": 0.09,
		"parry_skill": 0.48, "perfect_chance": 0.12, "zone_read": 0.62,
		"attack_cd": Vector2(0.62, 1.05), "think": Vector2(0.18, 0.34),
		"speed": 0.92, "punish": 0.44, "anti_turtle": 0.38, "dash_use": 0.14,
		"retreat_hp": 0.0, "riposte": 0.46, "whiff_bait": 0.16,
	},
	"hard": {
		"reaction": 0.135, "reaction_jitter": 0.045,
		"parry_skill": 0.80, "perfect_chance": 0.32, "zone_read": 0.84,
		"attack_cd": Vector2(0.32, 0.62), "think": Vector2(0.10, 0.20),
		"speed": 1.02, "punish": 0.82, "anti_turtle": 0.75, "dash_use": 0.46,
		"retreat_hp": 0.26, "riposte": 0.82, "whiff_bait": 0.40,
	},
	"brutal": {
		"reaction": 0.095, "reaction_jitter": 0.035,
		"parry_skill": 0.90, "perfect_chance": 0.50, "zone_read": 0.93,
		"attack_cd": Vector2(0.22, 0.44), "think": Vector2(0.07, 0.15),
		"speed": 1.08, "punish": 0.95, "anti_turtle": 0.92, "dash_use": 0.64,
		"retreat_hp": 0.30, "riposte": 0.94, "whiff_bait": 0.58,
	},
}

const THREAT_RANGE := 305.0
const EPISODE_GAP := 0.28
const DEFEND_MAX := 1.25

var difficulty: String = "hard"
var state: State = State.NEUTRAL

var _cfg: Dictionary = DIFFICULTY["hard"]
var _think: float = 0.2
var _attack_cd: float = 0.45
var _spacing_bias: float = 0.0
var _stalk_bias: float = 0.0
var _state_timer: float = 0.0
var _defend_total: float = 0.0
var _zone_retrack: float = 0.0
var _guard_shadow_y: float = -125.0

# Perception
var _threat_time: float = 0.0
var _calm_time: float = 0.0
var _reaction_needed: float = 0.18
var _episode_decided: bool = false
var _redecide_timer: float = 0.0
var _last_button_serial: int = -1
var _punish_time: float = 0.0
var _punish_decided: bool = false
var _turtle_decided: bool = false
var _foe_spin_habit: float = 0.0
var _foe_spinning_multi: bool = false

# Queued follow-up (riposte / dash-in strike)
var _pending_attack: String = ""
var _pending_delay: float = 0.0
var _last_chosen_move: String = ""
var _stance_cd: float = 0.0


func set_difficulty(d: String) -> void:
	difficulty = d if DIFFICULTY.has(d) else "hard"
	_cfg = DIFFICULTY[difficulty]


func reset() -> void:
	state = State.NEUTRAL
	_think = 0.18
	_attack_cd = 0.42
	_spacing_bias = 0.0
	_stalk_bias = 0.0
	_state_timer = 0.0
	_defend_total = 0.0
	_guard_shadow_y = -125.0
	_threat_time = 0.0
	_calm_time = 0.0
	_episode_decided = false
	_redecide_timer = 0.0
	_last_button_serial = -1
	_punish_time = 0.0
	_punish_decided = false
	_turtle_decided = false
	_foe_spin_habit = 0.0
	_foe_spinning_multi = false
	_pending_attack = ""
	_pending_delay = 0.0
	_last_chosen_move = ""
	_stance_cd = 0.0
	_roll_reaction()


## Called by the arena when this AI's guard stopped an attack.
func notify_blocked(perfect: bool) -> void:
	# If the foe is mid-chained whirlwind (Hit #2 still coming!), keep guard up until both hits pass!
	if _foe_spinning_multi and not perfect:
		_state_timer = maxf(_state_timer, 0.24)
		return
	if perfect or randf() < float(_cfg["riposte"]):
		state = State.NEUTRAL
		_state_timer = 0.0
		# Riposte immediately; _pending_attack=="auto" picks the open line at launch time.
		_pending_attack = "auto"
		_pending_delay = randf_range(0.03, 0.09) if perfect else randf_range(0.06, 0.15)


func _roll_reaction() -> void:
	_reaction_needed = float(_cfg["reaction"]) + randf() * float(_cfg["reaction_jitter"])


func _rand_range_v(v: Vector2) -> float:
	return randf_range(v.x, v.y)


func step(delta: float, me: FighterController, foe: FighterController) -> void:
	if me == null or foe == null or me.is_dead:
		return
	var dist := absf(foe.position.x - me.position.x)
	var dir_to_foe := 1.0 if foe.position.x > me.position.x else -1.0

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_think -= delta
	_state_timer = maxf(0.0, _state_timer - delta)
	_redecide_timer = maxf(0.0, _redecide_timer - delta)
	_stance_cd = maxf(0.0, _stance_cd - delta)
	_foe_spin_habit = maxf(0.0, _foe_spin_habit - 0.16 * delta)
	_foe_spinning_multi = foe.current_action == "spin_slash" and not foe._spin_second_armed

	# Drive smooth 2-bone IK guard posture whenever the AI isn't in a committed animation.
	_update_guard_ik(delta, me, foe, dist, dir_to_foe)

	# --- 0. Deflect incoming hurled weapon & manage Half-Sword stance / weapon scramble ---
	var wlayer := me.get_parent().get_node_or_null("WeaponsLayer") if me.get_parent() != null else null
	var flying_threat := false
	var nearest_drop: WeaponProjectile = null
	var nearest_drop_d := 99999.0
	if wlayer != null:
		for c in wlayer.get_children():
			if c is WeaponProjectile:
				var wp := c as WeaponProjectile
				if wp.flying and wp.thrower != me:
					var to_me := me.position.x - wp.position.x
					if absf(to_me) < 270.0 and to_me * wp.vel.x > 0.0:
						flying_threat = true
				elif wp.can_be_picked_up():
					var wd := absf(wp.position.x - me.position.x)
					if wd < nearest_drop_d:
						nearest_drop_d = wd
						nearest_drop = wp

	if difficulty != "normal" and _stance_cd <= 0.0 and me.current_action == "" and me.can_wield():
		var foe_heavily_armored := foe.stat("armor_mult") <= 0.74
		if not me.half_swording and me.can_half_sword() and ((foe_heavily_armored and dist < 192.0) or dist < 146.0):
			if me.set_half_sword(true, true):
				_stance_cd = 1.35
		elif me.half_swording and dist > 224.0:
			if me.set_half_sword(false, true):
				_stance_cd = 1.10

	# --- Perception: threat episodes with a reaction delay ---
	var threat := flying_threat or (not foe.is_dead and foe.is_attack_threat() and dist < THREAT_RANGE)
	if threat:
		_threat_time += delta
		_calm_time = 0.0
	else:
		_calm_time += delta
		if _calm_time > EPISODE_GAP:
			_threat_time = 0.0
			_episode_decided = false
	if foe.current_action in FighterController.ATTACK_MOVES and foe.attack_serial != _last_button_serial:
		_last_button_serial = foe.attack_serial
		_threat_time = 0.0
		_episode_decided = false
		if foe.current_action == "spin_slash" and not foe._spin_second_armed:
			_foe_spin_habit = minf(4.0, _foe_spin_habit + 1.0)

	# --- 1. React to a perceived threat (and adapt fast against predictable U/spin spammers!) ---
	var style := String(me.stats.get("ai_style", "balanced"))
	var reading_spin_spam := foe.current_action == "spin_slash" and _foe_spin_habit >= 1.1
	var foe_waggling := foe.is_player and foe._waggle_streak >= 2
	var parry_p := clampf(float(_cfg["parry_skill"]) + (0.08 if style == "master" else 0.0) + (0.26 if reading_spin_spam else 0.0), 0.0, 0.98)
	var bait_p := float(_cfg["whiff_bait"]) * (1.45 if style == "duelist" else 1.0) + (0.42 if reading_spin_spam else 0.0) + (0.35 if foe_waggling else 0.0)
	var can_act := me.current_action == "" or (difficulty != "normal" and me.can_feint_to_parry())
	var eff_reaction := _reaction_needed * (0.62 if reading_spin_spam else 1.0)
	var under_fire := threat and _threat_time >= eff_reaction
	if under_fire and can_act and (not _episode_decided or _redecide_timer <= 0.0) and state != State.DEFEND:
		_episode_decided = true
		_redecide_timer = 0.24
		_roll_reaction()
		# Back-dash to make a committed spin/swing whiff, then skewer recovery with Lunge Thrust!
		var bait_chance := bait_p * (0.72 if reading_spin_spam else 0.24)
		if me.current_action == "" and dist > 158.0 and dist < 248.0 and me.dash_cooldown <= 0.0 and foe.current_action in FighterController.ATTACK_MOVES and randf() < bait_chance:
			me.start_dash(-dir_to_foe)
			_pending_attack = "thrust"
			_pending_delay = 0.20 if foe.current_action == "spin_slash" else 0.16
			return
		# Close-range read on predictable raw spin startup: boot them out of it before blade comes around!
		if reading_spin_spam and me.current_action == "" and dist < 158.0 and foe.action_elapsed < 0.09 and me.can_kick() and randf() < 0.42:
			if _try_attack(me, "kick"):
				return
		if me.can_wield() and randf() < parry_p:
			me.abort_windup()
			_begin_defend(me, foe)
			if reading_spin_spam:
				me.guard_zone = "high"
		elif me.current_action == "" and me.dash_cooldown <= 0.0 and dist < 210.0 and randf() < float(_cfg["dash_use"]):
			me.start_dash(-dir_to_foe)
			_attack_cd = maxf(_attack_cd, 0.16)
			return

	# --- 2. Hold the guard while the flurry continues, tracking the blade line ---
	if state == State.DEFEND:
		_defend_total += delta
		var foe_spent := foe.stamina < 12.0 or foe.current_action in ["hurt", "parry_recoil"]
		if me.current_action == "" and me.can_wield() and not foe_spent and _defend_total < DEFEND_MAX and (_state_timer > 0.0 or threat):
			if threat:
				_state_timer = maxf(_state_timer, 0.15)
			_zone_retrack -= delta
			if _zone_retrack <= 0.0:
				_zone_retrack = _reaction_needed
				_set_guard_zone(me, foe)
			me.parry_hold_time += delta
			me.parrying = true
			# Gently give ground if the attacker crowds inside guard distance while swinging.
			if dist < 148.0:
				me.position.x = clampf(me.position.x - dir_to_foe * me.get_move_speed() * 0.55 * delta, 120.0, 1160.0)
			me.play_anim("parry_low" if me.guard_zone == "low" else "parry", 0.05)
			return
		state = State.NEUTRAL
		me.parrying = false
		me.parry_hold_time = 99.0
		# Exiting a maxed-out guard while the opponent is still swinging: back-dash or kick!
		if threat and _defend_total >= DEFEND_MAX:
			if dist < 178.0 and me.can_kick() and randf() < float(_cfg["anti_turtle"]):
				if _try_attack(me, "kick"):
					return
			if me.dash_cooldown <= 0.0 and randf() < float(_cfg["dash_use"]) + 0.25:
				me.start_dash(-dir_to_foe)
				return
		elif dist < me.stat("ai_spacing") + 50.0 and randf() < float(_cfg["riposte"]) * 0.75:
			_pending_attack = "auto"
			_pending_delay = 0.04
	me.parrying = false
	me.parry_hold_time = 99.0

	if me.current_action != "":
		return

	# --- 3. Queued riposte / dash-in strike ---
	if _pending_attack != "":
		_pending_delay -= delta
		if _pending_delay <= 0.0:
			var mv := _choose_attack(me, foe, dist) if _pending_attack == "auto" else _pending_attack
			_pending_attack = ""
			if dist > me.stat("ai_spacing") + 45.0 and dist < me.stat("ai_spacing") + 135.0 and mv != "thrust" and me.can_wield():
				mv = "thrust"
			if dist < me.stat("ai_spacing") + 110.0:
				if _try_attack(me, mv):
					return
		else:
			# Step into range during the brief riposte delay so the counter connects!
			if dist > 185.0:
				_walk(me, dir_to_foe, delta)
			return

	# --- 4. Punish a staggered / exhausted / whiff-recovering foe ---
	var foe_recovering := foe.current_action in FighterController.ATTACK_MOVES and foe.action_elapsed > 0.35
	var foe_open := foe.current_action in ["hurt", "parry_recoil"] or foe.stamina < 12.0 or foe_recovering
	if foe_open and not foe.is_dead:
		_punish_time += delta
		if dist > 190.0 and dist < 295.0:
			_walk(me, dir_to_foe, delta)
		if not _punish_decided and _punish_time >= _reaction_needed * 0.75:
			_punish_decided = true
			if _attack_cd <= 0.22 and randf() < float(_cfg["punish"]):
				if dist < me.stat("ai_spacing") + 55.0:
					var punish_mv := "thrust" if dist > 195.0 else ("slash_low" if _foe_blade_line(foe) == "high" else "slash_high")
					if _try_attack(me, punish_mv):
						return
				elif dist < me.stat("ai_spacing") + 145.0 and me.dash_cooldown <= 0.0 and me.can_wield():
					me.start_dash(dir_to_foe)
					_pending_attack = "thrust"
					_pending_delay = 0.11
					return
	else:
		_punish_time = 0.0
		_punish_decided = false

	# --- 5. Break a turtling foe with a push kick ---
	if foe.parrying and foe.parry_hold_time > 0.28 + _reaction_needed:
		if not _turtle_decided:
			_turtle_decided = true
			if dist < 185.0 and me.can_kick() and randf() < float(_cfg["anti_turtle"]):
				if _try_attack(me, "kick"):
					return
	else:
		_turtle_decided = false

	# --- 6. Crowded clinch or corner-trap: shove them into the timber or create space ---
	var foe_cornered := foe.position.x <= 155.0 or foe.position.x >= 1125.0
	if foe_cornered and dist < 182.0 and _attack_cd <= 0.14 and me.can_kick() and randf() < 0.78:
		if _try_attack(me, "kick"):
			return
	if dist < 138.0 and _attack_cd <= 0.12:
		if me.can_kick() and randf() < 0.72:
			if _try_attack(me, "kick"):
				return
		elif not me.can_wield() and me.can_jab():
			if _try_attack(me, "jab"):
				return

	# --- 6b. Disarmed scramble: sprint to recover a dropped blade on the floorboards! ---
	if not me.has_weapon and nearest_drop != null and not bool(me.severed.get("arm_r", false)) and not bool(me.severed.get("forearm_r", false)):
		var drop_dir := 1.0 if nearest_drop.position.x > me.position.x else -1.0
		if nearest_drop_d > 140.0 and me.dash_cooldown <= 0.0 and randf() < 0.65:
			me.start_dash(drop_dir)
			return
		_walk(me, drop_dir, delta)
		return

	# --- 7. Self-preservation: back off briefly when badly hurt and low on stamina ---
	var hp_frac := me.hp / maxf(1.0, me.max_hp)
	if style != "bully" and state == State.NEUTRAL and hp_frac < float(_cfg["retreat_hp"]) and me.stamina < 35.0 and dist < 210.0 and randf() < 0.9 * delta:
		state = State.RETREAT
		_state_timer = randf_range(0.45, 0.8)
		if randf() < float(_cfg["dash_use"]):
			me.start_dash(-dir_to_foe)
	if state == State.RETREAT:
		if _state_timer <= 0.0:
			state = State.NEUTRAL
		else:
			_walk(me, -dir_to_foe, delta)
			return

	# --- 8. Neutral offense & continuous fencing footwork ---
	var spacing := me.stat("ai_spacing")
	if not me.can_wield():
		spacing = 148.0 if me.can_kick() else 330.0

	if _think <= 0.0:
		_think = _rand_range_v(_cfg["think"])
		_spacing_bias = randf_range(-22.0, 18.0)
		if style == "bully":
			_stalk_bias = dir_to_foe * 0.80
		elif style == "duelist":
			_stalk_bias = -dir_to_foe * 0.35 if _attack_cd > 0.15 else dir_to_foe * 0.45
		elif style == "master":
			_stalk_bias = 0.0
		else:
			_stalk_bias = dir_to_foe * 0.55 if randf() < 0.55 else 0.0

	# Attack immediately whenever cooldown is ready and we are in striking measure
	# (don't start a slow windup if the opponent's shoulders are already swinging toward us).
	var incoming_glint := threat and _threat_time >= 0.05
	if _attack_cd <= 0.0 and not under_fire and not incoming_glint and not foe.is_dead:
		if dist < spacing + 38.0:
			if _try_attack(me, _choose_attack(me, foe, dist)):
				return
		elif dist < spacing + 145.0 and me.can_wield() and me.dash_cooldown <= 0.0 and randf() < float(_cfg["dash_use"]) * delta * 3.5:
			me.start_dash(dir_to_foe)
			_pending_attack = "thrust" if randf() < 0.55 + 0.3 * me.stat("ai_thrust_bias") else "slash_high"
			_pending_delay = 0.11
			return

	# Continuous spacing every frame so the AI never walks blindly into a swinging sword.
	var target_dist := spacing + _spacing_bias + (65.0 if under_fire else 0.0)
	var move_dir := 0.0
	if dist > target_dist + 18.0:
		move_dir = dir_to_foe
	elif dist < target_dist - 24.0:
		move_dir = -dir_to_foe
	else:
		move_dir = _stalk_bias if not under_fire else -dir_to_foe * 0.7

	if absf(move_dir) > 0.1:
		_walk(me, move_dir, delta)
	else:
		me.play_anim("idle", 0.1)


func _update_guard_ik(delta: float, me: FighterController, foe: FighterController, dist: float, dir_to_foe: float) -> void:
	if not me.can_wield() or foe.is_dead:
		me.aim_override_enabled = false
		return
	me.aim_override_enabled = true
	var foe_seg := foe.get_blade_segment()
	var desired_y := -128.0
	if me.parrying:
		desired_y = -152.0 if me.guard_zone == "high" else -22.0
	elif foe_seg.size() == 2:
		var foe_tip_rel_y := clampf(Vector2(foe_seg[1]).y - me.position.y, -210.0, -25.0)
		var weave := sin(Time.get_ticks_msec() * 0.0045) * 14.0
		desired_y = lerpf(-122.0 + weave, foe_tip_rel_y, 0.55)
	var track_rate := 18.0 if me.parrying else (6.0 + 6.0 * float(_cfg["zone_read"]))
	_guard_shadow_y = lerpf(_guard_shadow_y, desired_y, minf(1.0, track_rate * delta))
	# Pull hands closer to chest in tight measure so the crossguard stays between the fighters.
	var reach_x := clampf(dist * 0.62, 92.0, 178.0)
	if me.parrying:
		reach_x = clampf(dist * 0.54, 86.0, 142.0)
	me.aim_override = me.position + Vector2(dir_to_foe * reach_x, _guard_shadow_y)


func _walk(me: FighterController, dir: float, delta: float) -> void:
	if me.current_action != "":
		return
	me.position.x = clampf(me.position.x + dir * me.get_move_speed() * float(_cfg["speed"]) * delta, 120.0, 1160.0)
	var retreating := dir * float(me.facing) < -0.05
	me.play_anim("walk_back" if retreating and me.anim_player.has_animation("walk_back") else "walk", 0.07)


func _begin_defend(me: FighterController, foe: FighterController) -> void:
	state = State.DEFEND
	_state_timer = randf_range(0.26, 0.38)
	_defend_total = 0.0
	_zone_retrack = _reaction_needed
	_set_guard_zone(me, foe)
	me.parrying = true
	var perf_p := float(_cfg["perfect_chance"]) + (0.12 if String(me.stats.get("ai_style", "")) == "master" else 0.0)
	me.parry_hold_time = 0.0 if randf() < perf_p else me.stat("perfect_parry_window") + 0.01


func _set_guard_zone(me: FighterController, foe: FighterController) -> void:
	var true_zone := _foe_attack_zone(foe)
	if randf() < float(_cfg["zone_read"]):
		me.guard_zone = true_zone
	else:
		me.guard_zone = "high" if true_zone == "low" else "low"


func _foe_attack_zone(foe: FighterController) -> String:
	if foe.current_action in ["slash_low", "leg_sweep"]:
		return "low"
	if foe.current_action in ["slash_high", "thrust", "jump_slash", "mordhau_smash", "spin_slash", "riposte_cleave", "backstep_cut"]:
		return "high"
	return _foe_blade_line(foe)


## Which line the foe's blade tip currently occupies ("high" / "low").
func _foe_blade_line(foe: FighterController) -> String:
	var seg := foe.get_blade_segment()
	if seg.size() == 2 and Vector2(seg[1]).y > foe.position.y - 58.0:
		return "low"
	return "high"


func _choose_attack(me: FighterController, foe: FighterController, dist: float) -> String:
	if not me.can_wield():
		if me.can_jab() and dist < 145.0 and (not me.can_kick() or randf() < 0.58):
			return "jab"
		return "kick" if me.can_kick() and dist < 190.0 else ""
	var read := float(_cfg["zone_read"])
	var style := String(me.stats.get("ai_style", "balanced"))
	# Close clinch: bash visor with Pommel Strike or Mordhau!
	if dist < 150.0 and randf() < (0.34 if style in ["bully", "master"] else 0.22):
		return "mordhau_smash" if me.half_swording else "pommel_strike"
	# Attack the line the foe is NOT guarding!
	if foe.parrying and randf() < read * 0.85:
		if dist < 162.0 and randf() < 0.30:
			return "pommel_strike"
		var kick_p := 0.55 if style == "bully" else 0.35
		if me.can_kick() and dist < 185.0 and randf() < kick_p:
			return "leg_sweep" if (foe.guard_zone == "high" and randf() < 0.52) else "kick"
		if foe.guard_zone == "low" and me.can_dash() and randf() < 0.38:
			return "jump_slash"
		return "slash_low" if foe.guard_zone == "high" else "slash_high"
	# Vault over enemy low sweeps!
	if foe.current_action == "leg_sweep" and me.can_dash() and randf() < read:
		return "jump_slash"
	# Half-Sword Mordhau vs plate armour!
	if me.half_swording and dist < 188.0 and randf() < 0.36:
		return "mordhau_smash"
	# A cursor fighter holding the blade out is fishing for a passive block: kick/pommel it or cut around it!
	var foe_blade_held := foe.is_player and foe.cursor_aim_enabled and foe.current_action == "" and foe.can_wield() and foe.get_blade_tip_speed() < 260.0
	if foe_blade_held and randf() < read * 0.82:
		if dist < 156.0 and randf() < 0.35:
			return "pommel_strike"
		var kick_p2 := 0.62 if style == "bully" else 0.45
		if me.can_kick() and dist < 182.0 and randf() < kick_p2:
			return "leg_sweep" if (_foe_blade_line(foe) == "high" and randf() < 0.45) else "kick"
		return "slash_low" if _foe_blade_line(foe) == "high" else ("thrust" if dist > 195.0 else "slash_high")
	# Signature style specials: Vaulting Plunge Cleaves & Zwerchhau Whirlwinds!
	if dist >= 165.0 and dist <= 238.0 and me.can_dash() and style in ["executioner", "pressure", "bully"] and randf() < 0.16:
		return "jump_slash"
	if dist <= 198.0 and style in ["pressure", "duelist", "master"] and randf() < 0.16:
		return "spin_slash"
	# Landsknecht "pressure" style alternates high/low lines so it rarely repeats a slash line!
	if style == "pressure" and _last_chosen_move in ["slash_high", "slash_low"] and randf() < 0.72:
		return "slash_low" if _last_chosen_move == "slash_high" else "slash_high"
	# At longer measure, favour thrusts; up close, mix high/low cuts and kicks.
	var thrust_w := clampf(0.24 + 0.20 * me.stat("ai_thrust_bias") + (0.22 if dist > 205.0 else 0.0), 0.06, 0.72)
	var kick_w := (0.24 if style == "bully" else 0.14) if (me.can_kick() and dist < 178.0) else 0.0
	var slash_w := 1.0 - thrust_w - kick_w
	var roll := randf()
	if roll < slash_w * 0.52:
		return "slash_high"
	if roll < slash_w:
		return "slash_low"
	if roll < slash_w + thrust_w:
		return "thrust"
	return "kick" if kick_w > 0.0 else "slash_high"


func _try_attack(me: FighterController, move_name: String) -> bool:
	if move_name == "":
		return false
	if move_name == "jab":
		if me.start_jab():
			_last_chosen_move = "jab"
			_attack_cd = _next_attack_cd(me) * 0.72
			return true
		return false
	if me.start_attack(move_name):
		_last_chosen_move = move_name
		_attack_cd = _next_attack_cd(me)
		return true
	return false


func _next_attack_cd(me: FighterController) -> float:
	var aggr := clampf(me.stat("ai_aggression"), 0.0, 1.0)
	return _rand_range_v(_cfg["attack_cd"]) * lerpf(1.25, 0.72, aggr)
