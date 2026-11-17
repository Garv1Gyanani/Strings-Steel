class_name AIController
extends RefCounted

## Rival AI for Strings & Steel.
##
## Unlike the old frame-perfect version, this AI *perceives* threats with a
## human-like reaction delay, guesses the guard line imperfectly, only lands
## perfect parries with a difficulty-based probability, and reacts to cursor
## slings as well as button attacks (it watches is_attack_threat(), not just
## current_action). Spacing and aggression come from the piloted fighter's
## FighterStats, so each rival plays differently.

enum State { NEUTRAL, DEFEND, RETREAT }

const DIFFICULTY := {
	"normal": {
		"reaction": 0.30, "reaction_jitter": 0.12,
		"parry_skill": 0.42, "perfect_chance": 0.12, "zone_read": 0.6,
		"attack_cd": Vector2(0.85, 1.40), "think": Vector2(0.24, 0.45),
		"speed": 0.85, "punish": 0.25, "anti_turtle": 0.25, "dash_use": 0.0,
		"retreat_hp": 0.0,
	},
	"hard": {
		"reaction": 0.21, "reaction_jitter": 0.08,
		"parry_skill": 0.62, "perfect_chance": 0.30, "zone_read": 0.75,
		"attack_cd": Vector2(0.55, 1.00), "think": Vector2(0.16, 0.32),
		"speed": 0.96, "punish": 0.6, "anti_turtle": 0.6, "dash_use": 0.3,
		"retreat_hp": 0.28,
	},
	"brutal": {
		"reaction": 0.15, "reaction_jitter": 0.05,
		"parry_skill": 0.80, "perfect_chance": 0.50, "zone_read": 0.88,
		"attack_cd": Vector2(0.38, 0.75), "think": Vector2(0.11, 0.24),
		"speed": 1.04, "punish": 0.85, "anti_turtle": 0.85, "dash_use": 0.5,
		"retreat_hp": 0.32,
	},
}

const THREAT_RANGE := 275.0

var difficulty: String = "hard"
var state: State = State.NEUTRAL

var _cfg: Dictionary = DIFFICULTY["hard"]
var _think: float = 0.25
var _attack_cd: float = 0.6
var _move_dir: float = 0.0
var _desired_dist: float = 200.0
var _state_timer: float = 0.0

# Perception
var _threat_time: float = 0.0
var _reaction_needed: float = 0.2
var _decided_serial: int = -1
var _punish_time: float = 0.0
var _punish_decided: bool = false
var _turtle_decided: bool = false

# Dash-in followed by an attack
var _pending_attack: String = ""
var _pending_delay: float = 0.0


func set_difficulty(d: String) -> void:
	difficulty = d if DIFFICULTY.has(d) else "hard"
	_cfg = DIFFICULTY[difficulty]


func reset() -> void:
	state = State.NEUTRAL
	_think = 0.25
	_attack_cd = 0.6
	_move_dir = 0.0
	_state_timer = 0.0
	_threat_time = 0.0
	_decided_serial = -1
	_punish_time = 0.0
	_punish_decided = false
	_turtle_decided = false
	_pending_attack = ""
	_pending_delay = 0.0
	_roll_reaction()


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

	# --- Perception: how long has the foe's attack been visibly coming? ---
	var threat := not foe.is_dead and foe.is_attack_threat() and dist < THREAT_RANGE
	if threat:
		_threat_time += delta
	else:
		_threat_time = 0.0

	# --- 1. React to a perceived attack (once per foe attack serial) ---
	if threat and _threat_time >= _reaction_needed and foe.attack_serial != _decided_serial:
		_decided_serial = foe.attack_serial
		_roll_reaction()
		if me.current_action == "" and me.can_wield() and randf() < float(_cfg["parry_skill"]):
			_begin_defend(me, foe)
		elif me.current_action == "" and foe.current_action == "thrust" and dist < 190.0 and randf() < float(_cfg["dash_use"]):
			me.start_dash(-dir_to_foe)
			_attack_cd = maxf(_attack_cd, 0.22)
			return

	# --- 2. Hold an active guard ---
	if state == State.DEFEND:
		if _state_timer > 0.0 and me.current_action == "" and me.can_wield():
			# Keep guarding while the threat continues, up to a cap.
			if threat and _state_timer < 0.12:
				_state_timer = 0.12
			me.parry_hold_time += delta
			me.parrying = true
			me.play_anim("parry_low" if me.guard_zone == "low" else "parry", 0.05)
			return
		state = State.NEUTRAL
	me.parrying = false
	me.parry_hold_time = 99.0

	if me.current_action != "":
		return

	# --- 3. Pending follow-up after a dash-in ---
	if _pending_attack != "":
		_pending_delay -= delta
		if _pending_delay <= 0.0:
			me.start_attack(_pending_attack)
			_pending_attack = ""
			_attack_cd = _next_attack_cd(me)
		return

	# --- 4. Punish a staggered / exhausted foe (after reaction time) ---
	var foe_open := foe.current_action in ["hurt", "parry_recoil"] or foe.stamina < 12.0
	if foe_open and not foe.is_dead:
		_punish_time += delta
		if not _punish_decided and _punish_time >= _reaction_needed:
			_punish_decided = true
			if dist < me.stat("ai_spacing") + 45.0 and _attack_cd <= 0.15 and randf() < float(_cfg["punish"]):
				if _try_attack(me, "thrust" if dist > 180.0 else "slash_high"):
					return
	else:
		_punish_time = 0.0
		_punish_decided = false

	# --- 5. Break a turtling foe with a push kick ---
	if foe.parrying and foe.parry_hold_time > 0.34 + _reaction_needed:
		if not _turtle_decided:
			_turtle_decided = true
			if dist < 185.0 and me.can_kick() and randf() < float(_cfg["anti_turtle"]):
				if _try_attack(me, "kick"):
					return
	else:
		_turtle_decided = false

	# --- 6. Self-preservation: back off when badly hurt ---
	var hp_frac := me.hp / maxf(1.0, me.max_hp)
	if state == State.NEUTRAL and hp_frac < float(_cfg["retreat_hp"]) and dist < 210.0 and randf() < 0.9 * delta:
		state = State.RETREAT
		_state_timer = randf_range(0.5, 0.9)
		if randf() < float(_cfg["dash_use"]):
			me.start_dash(-dir_to_foe)
	if state == State.RETREAT:
		if _state_timer <= 0.0:
			state = State.NEUTRAL
		else:
			_walk(me, -dir_to_foe, delta)
			return

	# --- 7. Neutral game: spacing + attack choice ---
	if _think <= 0.0:
		_think = _rand_range_v(_cfg["think"])
		var spacing := me.stat("ai_spacing")
		if not me.can_wield():
			spacing = 150.0 if me.can_kick() else 320.0
		_desired_dist = spacing + randf_range(-28.0, 22.0)
		if dist > _desired_dist + 22.0:
			_move_dir = dir_to_foe
		elif dist < _desired_dist - 42.0:
			_move_dir = -dir_to_foe
		else:
			_move_dir = dir_to_foe * 0.45 if randf() < 0.5 else 0.0

		if _attack_cd <= 0.0:
			if dist < spacing + 40.0:
				_try_attack(me, _choose_attack(me, foe, dist))
			elif dist < spacing + 150.0 and me.can_wield() and me.dash_cooldown <= 0.0 and randf() < float(_cfg["dash_use"]) * 0.5:
				# Close the gap with a dash, then strike.
				me.start_dash(dir_to_foe)
				_pending_attack = "thrust" if randf() < 0.5 + 0.3 * me.stat("ai_thrust_bias") else "slash_high"
				_pending_delay = 0.12
				return

	if absf(_move_dir) > 0.1:
		_walk(me, _move_dir, delta)
	else:
		me.play_anim("idle", 0.1)


func _walk(me: FighterController, dir: float, delta: float) -> void:
	me.position.x = clampf(me.position.x + dir * me.get_move_speed() * float(_cfg["speed"]) * delta, 120.0, 1160.0)
	me.play_anim("walk", 0.08)


func _begin_defend(me: FighterController, foe: FighterController) -> void:
	state = State.DEFEND
	_state_timer = randf_range(0.30, 0.42)
	var true_zone := _foe_attack_zone(foe)
	if randf() < float(_cfg["zone_read"]):
		me.guard_zone = true_zone
	else:
		me.guard_zone = "high" if true_zone == "low" else "low"
	me.parrying = true
	# Only a fraction of AI guards are raised in the perfect-parry window.
	me.parry_hold_time = 0.0 if randf() < float(_cfg["perfect_chance"]) else me.stat("perfect_parry_window") + 0.01


func _foe_attack_zone(foe: FighterController) -> String:
	if foe.current_action == "slash_low":
		return "low"
	if foe.current_action in ["slash_high", "thrust"]:
		return "high"
	# Cursor sling: judge by where the blade tip is relative to the hips.
	var seg := foe.get_blade_segment()
	if seg.size() == 2 and Vector2(seg[1]).y > foe.position.y - 70.0:
		return "low"
	return "high"


func _choose_attack(me: FighterController, foe: FighterController, dist: float) -> String:
	if not me.can_wield():
		return "kick" if me.can_kick() and dist < 190.0 else ""
	# Attack the line the foe is NOT guarding, but only as often as the AI reads it correctly.
	if foe.parrying and randf() < float(_cfg["zone_read"]) * 0.8:
		return "slash_low" if foe.guard_zone == "high" else "slash_high"
	var thrust_w := clampf(0.22 + 0.18 * me.stat("ai_thrust_bias"), 0.05, 0.6)
	var kick_w := 0.12 if (me.can_kick() and dist < 190.0) else 0.0
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
	if me.start_attack(move_name):
		_attack_cd = _next_attack_cd(me)
		return true
	return false


func _next_attack_cd(me: FighterController) -> float:
	var aggr := clampf(me.stat("ai_aggression"), 0.0, 1.0)
	return _rand_range_v(_cfg["attack_cd"]) * lerpf(1.3, 0.75, aggr)
