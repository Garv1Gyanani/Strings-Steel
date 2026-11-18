extends SceneTree

## Headless smoke test for Strings & Steel.
## Drives real matches through the Arena scene and checks the core rules.
##
## Usage:
##   godot --headless --path . --script res://tools/SmokeTest.gd
## Exit code = number of failed checks. Any "SCRIPT ERROR" lines in the output also mean failure.

const TITLE := 0
const INTRO := 1
const FIGHT := 2
const ROUND_END := 3
const MATCH_END := 4
const INTRO_S := 1.4
const ROUND_END_S := 2.8
const TEST_SETTINGS := "user://smoke_test_settings.cfg"


## An AI that does nothing, so rule checks are deterministic.
class NullAI extends AIController:
	func step(_delta: float, _me: FighterController, _foe: FighterController) -> void:
		pass


var arena: Node
var failures: Array[String] = []
var passes: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  PASS  ", msg)
	else:
		failures.append(msg)
		print("  FAIL  ", msg)


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func frames(n: int) -> void:
	for i in range(n):
		await process_frame


func p1() -> FighterController:
	return arena.p1


func p2() -> FighterController:
	return arena.p2


func _start(mode: String, a: int, b: int) -> void:
	arena._on_start_requested({"p1": a, "p2": b, "mode": mode})
	await wait(INTRO_S + 0.2)


func _run() -> void:
	var ps := load("res://scenes/Arena.tscn") as PackedScene
	arena = ps.instantiate()
	arena.settings_path = TEST_SETTINGS
	root.add_child(arena)
	await frames(5)
	arena.settings["sound"] = false
	arena.sfx.muted = true

	print("== Title screen")
	check(arena.phase == TITLE, "game boots into the title screen")
	check(arena._stage_tex != null and arena._use_courtyard_stage(), "moonlit courtyard background texture loaded & active by default")
	check(not p1().input_enabled, "player input is disabled on the title screen")
	check(InputMap.has_action("slash") and InputMap.has_action("pause"), "InputMap actions registered")

	print("== Fighter stats")
	arena._on_start_requested({"p1": 4, "p2": 3, "mode": "duel"})
	await frames(2)
	check(p1().fighter_id == "venetian_bravo" and p2().fighter_id == "black_knight", "fighters swapped from title selection")
	check(is_equal_approx(p1().max_hp, 88.0) and is_equal_approx(p2().max_hp, 125.0), "max HP comes from FighterStats")
	check(p1().move_speed > p2().move_speed, "Bravo is faster than the Black Knight")
	check(p1()._head_textures.has("dead") and p2()._head_textures.has("dead"), "head expression sprites load from FighterStats")
	check(arena.phase == INTRO and not p1().input_enabled, "round intro locks input")
	await wait(INTRO_S + 0.2)
	check(arena.phase == FIGHT and p1().input_enabled, "FIGHT phase enables input")

	arena.ai = NullAI.new()

	print("== Input buffer & stamina")
	p1().reset_fighter()
	await frames(2)
	Input.action_press("slash")
	await frames(2)
	Input.action_release("slash")
	check(p1().current_action in ["slash_high", "slash_low"], "pressing slash starts a slash via InputMap")
	var serial_before := p1().attack_serial
	await wait(0.9)
	check(p1().attack_serial == serial_before, "a single press does not auto-repeat attacks")
	p1().reset_fighter()
	p1().stamina = 5.0
	check(not p1().start_attack("slash_high"), "cannot attack without stamina")
	p1().reset_fighter()

	print("== Blade clash rules")
	_prime_attack(p2())
	p1().parrying = true
	p1().parry_hold_time = 0.0
	arena._handle_blade_clash(p2(), p1(), Vector2(640, 380))
	check(p2().current_action == "parry_recoil", "perfect parry staggers the attacker")

	_reset_both()
	_prime_attack(p2())
	p1().parrying = true
	p1().parry_hold_time = 1.0
	arena._handle_blade_clash(p2(), p1(), Vector2(640, 380))
	check(is_equal_approx(p1().stamina, 86.0), "normal parry costs 14 stamina")
	check(p2().hit_registered_serial == p2().attack_serial, "normal parry stops the cut")

	_reset_both()
	_prime_attack(p2())
	p1().parrying = true
	p1().parry_hold_time = 1.0
	p1().stamina = 3.0
	arena._handle_blade_clash(p2(), p1(), Vector2(640, 380))
	check(p1().current_action == "hurt", "guard breaks when out of stamina")
	check(p2().hit_registered_serial != p2().attack_serial, "a broken guard lets the cut carry through")

	_reset_both()
	_prime_attack(p2())
	p1().cursor_aim_enabled = true
	arena._handle_blade_clash(p2(), p1(), Vector2(640, 380))
	check(is_equal_approx(p1().stamina, 80.0), "passive cursor block costs 20 stamina")

	print("== Damage, armour, dismemberment")
	_reset_both()
	var hp0 := p2().hp
	p2().apply_blade_damage("torso", 20.0, Vector2(840, 340), Vector2(1, 0), false, false, 1.0)
	check(is_equal_approx(hp0 - p2().hp, 20.0 * 0.58), "Black Knight plate reduces torso damage")
	var hp1 := p1().hp
	p1().apply_blade_damage("torso", 20.0, Vector2(440, 340), Vector2(-1, 0), false, false, 1.0)
	check(is_equal_approx(hp1 - p1().hp, 20.0), "unarmoured Bravo takes full damage")

	_reset_both()
	p1().sever_limb("thigh_l", Vector2(440, 480), Vector2(-1, 0))
	check(is_equal_approx(p1().get_mobility(), 0.45), "losing a thigh slows movement")
	check(not p1().can_dash(), "cannot dash on one leg")
	check(is_equal_approx(p1().bleed_floor, 0.9), "sever adds permanent stump bleed")
	p1().sever_limb("shin_r", Vector2(440, 520), Vector2(-1, 0))
	check(not p1().can_kick(), "cannot kick without a right shin")
	check(not p1().start_attack("kick"), "kick refused (and free) with a missing leg")
	p1().sever_limb("arm_l", Vector2(440, 330), Vector2(-1, 0))
	check(is_equal_approx(p1().get_guard_cost_mult(), 1.5), "lost off-hand makes guarding costlier")
	p1().hp = 500.0
	var bleed_start := p1().bleed_rate
	await wait(3.0)
	check(p1().bleed_rate < bleed_start * 0.6 and p1().bleed_rate >= p1().bleed_floor, "fresh bleeding clots toward the stump floor")

	print("== Blood canvas")
	arena._on_blood_spray(Vector2(640, 420), Vector2(0, 160), 40, true)
	await wait(1.2)
	var wet := 0.0
	for x in range(400, 900, 8):
		wet = maxf(wet, arena.blood.floor_wetness_at(float(x)))
	check(wet > 0.0, "landing blood soaks the floor (bootprint wetness)")

	print("== Round flow (duel, best of 3)")
	_reset_both()
	p2().kill_fighter()
	await frames(2)
	check(arena.phase == ROUND_END and arena.wins_p1 == 1, "KO ends the round and scores it")
	check(p1().combat_frozen, "bleeding is frozen once the round is decided")
	p1().bleed_rate = 10.0
	var hp_frozen := p1().hp
	await wait(0.5)
	check(is_equal_approx(p1().hp, hp_frozen), "winner cannot bleed out after the KO")
	await wait(ROUND_END_S + INTRO_S + 0.3)
	check(arena.round_num == 2 and arena.phase == FIGHT, "round 2 starts automatically")
	check(not p2().is_dead and is_equal_approx(p2().hp, p2().max_hp), "fighters are restored for the next round")

	arena.round_time_left = 0.01
	p2().hp = p2().max_hp * 0.5
	await frames(3)
	check(arena.phase == ROUND_END and arena.wins_p1 == 2, "time-out awards the round to the healthier fighter")
	await wait(ROUND_END_S + 0.3)
	check(arena.phase == MATCH_END, "two round wins end the match")
	check(arena.ui._result_root.visible and arena.ui._result_title.text == "VICTORY", "victory screen shown")

	print("== Pause")
	arena._on_rematch()
	await wait(INTRO_S + 0.2)
	arena.ai = NullAI.new()
	arena._toggle_pause()
	check(paused and arena.ui._pause_root.visible, "Esc/Start pauses the tree and shows the pause menu")
	var x_before := p1().position.x
	p1().knockback_vx = 500.0
	await frames(10)
	check(is_equal_approx(p1().position.x, x_before), "fighters are frozen while paused")
	arena._toggle_pause()
	check(not paused and not arena.ui._pause_root.visible, "resume unpauses")
	p1().knockback_vx = 0.0

	print("== Gauntlet")
	await _start("gauntlet", 0, -1)
	arena.ai = NullAI.new()
	var first_rival := p2().fighter_id
	p2().kill_fighter()
	await wait(ROUND_END_S + 0.3)
	check(arena.gauntlet_wave == 2, "winning a gauntlet round advances the wave")
	check(p2().fighter_id != first_rival, "a new challenger is drawn")
	check(is_equal_approx(p2().hp_scale, 1.12) and p2().limb_hp_scale > 1.0, "rival HP and limb HP scale with the wave")
	await wait(INTRO_S + 0.2)
	arena.ai = NullAI.new()
	p1().kill_fighter()
	await wait(ROUND_END_S + 0.3)
	check(arena.phase == MATCH_END and arena.ui._result_title.text == "RUN OVER", "losing ends the gauntlet run")
	check(arena.best_wave >= 1, "best wave recorded")
	var cfg := ConfigFile.new()
	check(cfg.load(TEST_SETTINGS) == OK and int(cfg.get_value("records", "best_wave", 0)) >= 1, "record persisted to disk")

	print("== Regression: parry geometry, anti-tunneling & no 1-hit full-HP cleave")
	_reset_both()
	p2().anim_player.play("parry", 0.0)
	p2().anim_player.seek(0.15, true)
	var parry_seg := p2().get_blade_segment()
	check(parry_seg.size() == 2 and (Vector2(parry_seg[1]).x - p2().position.x) * float(p2().facing) > 60.0, "high parry holds the sword out in front of the fighter (not behind the head)")

	_reset_both()
	p2().trigger_hurt(true) # parry_recoil at 100% HP
	var did_chop_head := p2().apply_blade_damage("head", 26.0, p2().position + Vector2(0, -140), Vector2(1, 0), false, true, 1.0, 1.45)
	check(not did_chop_head and not p2().is_dead, "first-clash parry recoil at full HP never one-shot decapitates")
	_reset_both()
	p2().trigger_hurt(true)
	var did_chop_torso := p2().apply_blade_damage("torso", 26.0, p2().position + Vector2(0, -90), Vector2(1, 0), false, true, 1.0, 1.45)
	check(not did_chop_torso and not p2().is_dead, "first-clash parry recoil at full HP never one-shot cleaves torso")
	check(is_equal_approx(p2().max_hp - p2().hp, 26.0 * 1.28), "riposte on parry_recoil awards Counter-Hit bonus damage")

	_reset_both()
	p1().position.x = 460.0
	p2().position.x = 630.0
	p2().parrying = true
	p2().parry_hold_time = 0.5
	p2().guard_zone = "high"
	p2().anim_player.play("parry", 0.0)
	p2().anim_player.seek(0.15, true)
	# Simulate a huge single-frame mouse flick jumping from above p2's blade straight into p2's chest.
	p1()._prev_blade_seg = [Vector2(540, 200), Vector2(650, 180)]
	p1().current_action = "slash_high"
	p1().action_elapsed = 0.25
	p1().attack_serial += 1
	var hp_pre_flick := p2().hp
	arena._resolve_combat()
	check(is_equal_approx(p2().hp, hp_pre_flick), "swept parry catches fast single-frame flicks without tunneling")

	print("== Momentum, sweet-spot, thrusts, rebound, riposte & live strings")
	_reset_both()
	# 1. Small splash (low power) never slices torso or pops limbs, even with 1-Hit Sever ON!
	var splash_sever := p2().apply_blade_damage("torso", 20.0, p2().position + Vector2(0, -90), Vector2(1, 0), true, false, 0.25, 1.25, 0.75, false, 0.0)
	check(not splash_sever and not p2().is_dead, "low-intensity splash never slices torso even in 1-Hit Sever mode")

	# 2. Hilt / ricasso bump deals reduced blunt chip and never chops limbs.
	_reset_both()
	var hp_pre_hilt := p1().hp
	var hilt_sever := p1().apply_blade_damage("forearm_r", 20.0, p1().position + Vector2(40, -90), Vector2(-1, 0), true, true, 1.0, 1.25, 0.15, false, 0.0)
	check(not hilt_sever and is_equal_approx(hp_pre_hilt - p1().hp, 20.0 * 0.35), "hilt bump deals 0.35x blunt chip and never severs")

	# 3. Limb HP survives single heavy hits and warns before severing.
	_reset_both()
	var sev1 := p1().apply_blade_damage("forearm_r", 24.0, p1().position + Vector2(40, -90), Vector2(-1, 0), false, true, 0.90, 1.25, 0.75, false, 0.0)
	check(not sev1 and p1().can_wield(), "sword forearm survives an opening heavy slash without instant disarm")
	p1()._combo_hits = 0
	var sev2 := p1().apply_blade_damage("forearm_r", 24.0, p1().position + Vector2(40, -90), Vector2(-1, 0), false, true, 0.95, 1.25, 0.75, false, 0.0)
	check(not sev2 and bool(p1()._limb_warned.get("forearm_r", false)), "second heavy hit triggers progressive mangled-limb warning")
	p1()._combo_hits = 0
	var sev3 := p1().apply_blade_damage("forearm_r", 24.0, p1().position + Vector2(40, -90), Vector2(-1, 0), false, true, 0.95, 1.25, 0.75, false, 0.0)
	check(sev3 and not p1().can_wield(), "sustained heavy focus on the mangled forearm earns the disarming sever")

	# 4. Thrusts pierce plate armour gaps and never bisect/chop limbs on kill.
	_reset_both()
	var bk_hp0 := p2().hp
	p2().apply_blade_damage("torso", 20.0, p2().position + Vector2(0, -90), Vector2(1, 0), false, false, 1.0, 1.0, 0.85, true, 0.45)
	var thrust_dmg_taken := bk_hp0 - p2().hp
	check(thrust_dmg_taken > 20.0 * 0.58 + 1.5, "rapier point thrust partially bypasses plate armour")
	p2().hp = 5.0
	var thrust_kill_sever := p2().apply_blade_damage("torso", 24.0, p2().position + Vector2(0, -90), Vector2(1, 0), true, true, 1.0, 1.25, 0.90, true, 0.45)
	check(p2().is_dead and not thrust_kill_sever and not bool(p2().severed.get("torso", false)), "killing thrust impales without slicing torso in half")

	# 5. Rebound & riposte window on parry.
	_reset_both()
	_prime_attack(p2())
	p1().parrying = true
	p1().parry_hold_time = 0.8
	arena._handle_blade_clash(p2(), p1(), Vector2(550, 360))
	check(p1().riposte_timer > 0.2 and p2()._rebound_ua > 0.1, "blocking grants riposte window to defender and rebounds attacker's arm")

	# 6. Live marionette string cutting ("Strings & Steel").
	_reset_both()
	check(p2().get_live_string_segments().size() == 3, "living fighter exposes 3 overhead marionette strings")
	var base_w := p2().effective_blade_weight()
	p2().cut_live_string("arm_r", p2().position + Vector2(0, -260))
	check(p2().effective_blade_weight() > base_w * 1.2, "cutting sword-arm string makes the blade sag heavier")
	p2().cut_live_string("arm_l", p2().position + Vector2(0, -260))
	check(p2().get_guard_cost_mult() > 1.25, "cutting off-hand string weakens two-handed guard")

	print("== AI perception")
	arena._on_start_requested({"p1": 0, "p2": 1, "mode": "duel"})
	await wait(INTRO_S + 0.2)
	var real_ai := AIController.new()
	real_ai.set_difficulty("brutal")
	arena.ai = real_ai
	var parries := 0
	var trials := 12
	for t in range(trials):
		_reset_both()
		real_ai.reset()
		p1().position.x = 500.0
		p2().position.x = 680.0
		p1().start_attack("slash_high")
		var saw_parry := false
		var reacted_instantly := false
		var elapsed_real := 0.0
		for f in range(35):
			await process_frame
			elapsed_real += arena.get_process_delta_time()
			if p2().parrying:
				saw_parry = true
				if elapsed_real < 0.08:
					reacted_instantly = true
				break
		if saw_parry and not reacted_instantly:
			parries += 1
	check(parries >= 6, "brutal AI parries telegraphed attacks after a reaction delay (%d/%d)" % [parries, trials])
	arena.ai = NullAI.new()

	print("== Combat expansion: Half-Swording, Helmet Crack, Loadouts, Sword Throw & Corner Crush")
	arena._on_start_requested({"p1": 0, "p2": 3, "p1_loadout": "signature", "p2_loadout": "signature", "mode": "duel"})
	await wait(INTRO_S + 0.2)
	arena.ai = NullAI.new()
	_reset_both()

	# 1. Half-Swording stance
	var full_seg := p1().get_blade_segment()
	var full_len := Vector2(full_seg[0]).distance_to(Vector2(full_seg[1]))
	check(p1().toggle_half_sword() and p1().half_swording, "two-handed fighter can enter Half-Sword stance")
	var hs_seg := p1().get_blade_segment()
	var hs_len := Vector2(hs_seg[0]).distance_to(Vector2(hs_seg[1]))
	check(hs_len < full_len * 0.72, "Half-Swording shortens active blade segment for close-quarters leverage")
	check(is_equal_approx(p1().get_guard_cost_mult(), 0.70), "Half-Swording discounts guard stamina cost")
	check(p1().get_cut_armor_pierce() >= 0.40, "Half-Swording grants armour-piercing leverage on cuts")
	p1().cut_live_string("arm_l", p1().position + Vector2(0, -260))
	await frames(2)
	check(not p1().half_swording, "snapping off-hand string automatically cancels Half-Sword grip")

	# 2. Knock-off helmet -> bare head armour strip -> earned mid-fight decapitation
	_reset_both()
	check(p2().is_armored_slot("head") and not p2().headgear_lost, "Black Knight starts with armoured Gothic helmet")
	p2().limb_hp["head"] = p2().max_limb_hp["head"] * 0.55
	p2().apply_blade_damage("head", 18.0, p2().position + Vector2(0, -140), Vector2(1, 0), false, true, 0.85, 1.0, 0.75, false, 0.42)
	check(p2().headgear_lost and not p2().is_armored_slot("head"), "solid headshot cracks off Black Knight's helmet and strips head armour")
	p2()._combo_hits = 0
	p2().hp = 95.0 # well above 50% max HP!
	p2().limb_hp["head"] = 4.0
	var decap_mid := p2().apply_blade_damage("head", 24.0, p2().position + Vector2(0, -140), Vector2(1, 0), false, true, 0.90, 1.15, 0.78, false, 0.0)
	check(decap_mid and bool(p2().severed.get("head", false)) and p2().is_dead, "depleting an unhelmeted head earns a mid-fight decapitation")

	# 3. Pollaxe, Sword+Buckler & Katzbalger loadouts + Guard-Break Disarm
	_reset_both()
	p1().apply_loadout("pollaxe")
	check(p1().weapon_part_id == "p2_pollaxe" and p1().get_guard_crush_mult() > 1.4, "Pollaxe loadout equips p2_pollaxe with heavy guard-crush")
	p2().parrying = true
	p2().parry_hold_time = 1.0
	p2().stamina = 15.0 # enough for normal sword (14), NOT enough for Pollaxe (14 * 1.48 = 20.72)!
	_prime_attack(p1())
	arena._handle_blade_clash(p1(), p2(), Vector2(580, 360))
	check(not p2().has_weapon and arena.weapons_layer.get_child_count() >= 1, "Pollaxe guard-break smashes through block and disarms defender's sword")

	_reset_both()
	p1().apply_loadout("buckler")
	check(p1().has_buckler and is_equal_approx(p1().get_guard_cost_mult(), 0.62), "Sword+Buckler loadout mounts buckler and reduces block cost")
	p1().apply_loadout("katzbalger")
	check(p1().weapon_part_id == "p1_sword_katz" and not p1().weapon_is_two_handed(), "Katzbalger loadout equips nimble one-handed sidearm")
	p1().apply_loadout("signature")

	# 4. Sword Throw, Parry Deflection, Unarmed Jab & Ground Weapon Swap
	_reset_both()
	for w in arena.weapons_layer.get_children():
		w.queue_free()
	await frames(2)
	p1().position.x = 420.0
	p2().position.x = 660.0
	p2().parrying = true
	p2().parry_hold_time = 0.4
	check(p1().throw_weapon(p2().position + Vector2(0, -110)) and not p1().has_weapon, "throwing weapon launches projectile and leaves thrower unarmed")
	for i in range(25):
		await process_frame
		arena._resolve_combat()
		if p2().riposte_timer > 0.0:
			break
	check(p2().riposte_timer > 0.0, "parrying a hurled sword deflects it and grants Riposte")

	# Unarmed jab while disarmed
	for w in arena.weapons_layer.get_children():
		w.queue_free()
	arena.hitstop_timer = 0.0
	Engine.time_scale = 1.0
	p1().position.x = 540.0
	p2().position.x = 640.0
	p2().parrying = false
	var hp_pre_jab := p2().hp
	check(p1().start_jab(), "unarmed fighter can throw a gauntlet jab")
	p1()._jab_timer = 0.14
	arena._resolve_combat()
	check(p2().hp < hp_pre_jab, "gauntlet jab lands close-range blunt damage")

	# Pick up rival's dropped greatsword off the stage floor!
	var dropped := p2().drop_weapon(Vector2(-80, -60))
	check(dropped != null and dropped.weapon_part_id == "p4_sword_flam", "dropped weapon retains its exact part id (p4_sword_flam)")
	dropped.position = Vector2(p1().position.x + 12.0, 556.0)
	dropped.grounded = true
	dropped.pickup_cooldown = 0.0
	arena._resolve_combat()
	check(p1().has_weapon and p1().weapon_part_id == "p4_sword_flam", "unarmed Landsknecht recovers Black Knight's dropped greatsword")

	# 5. Stage-Corner Wall Crush
	_reset_both()
	arena.hitstop_timer = 0.0
	Engine.time_scale = 1.0
	p2().position.x = 1148.0
	p1().position.x = 1020.0
	p1().set_facing(1)
	var hp_pre_crush := p2().hp
	p1().start_attack("kick")
	p1().action_elapsed = 0.16
	p1().anim_player.stop()
	p1().anim_player.play("kick", 0.0)
	p1().anim_player.advance(0.16)
	arena._resolve_combat()
	check(p2().hp < hp_pre_crush - 9.5 and p2().current_action == "parry_recoil", "kicking a rival pinned against the stage wall triggers Corner Crush damage & heavy stagger")

	print("== Minimalist translucent touch-wheel & gesture controls")
	_reset_both()
	p1().input_enabled = true
	arena._on_setting_changed("touch", true)
	var tc: MobileTouchController = arena.ui._touch_ctrl
	check(tc != null and tc.get_child_count() == 0, "touch controller has zero permanent HUD buttons")
	check(p1().cursor_aim_enabled and p1().touch_mode_active, "touch mode keeps live 2-bone IK blade aiming active")
	check(is_equal_approx(tc._left_alpha, 0.0) and is_equal_approx(tc._right_alpha, 0.0), "touch wheels are completely invisible (0 opacity) until touched")

	# 1. Left wheel: resting thumb NEVER auto-parries or locks out sword; dynamic floating origin reverses instantly
	tc._on_finger_down(0, Vector2(180, 500))
	tc._process(0.10)
	check(tc._left_alpha > 0.15 and not p1().touch_parry and is_equal_approx(p1().touch_move, 0.0), "resting left thumb shows translucent stick without accidentally parrying")
	tc._on_finger_drag(0, Vector2(330, 500), Vector2(1100, 0)) # slide 150 px fast (> LEFT_RADIUS) while still holding!
	check(p1().touch_move > 0.9 and is_equal_approx(p1().dash_timer, 0.0), "fast thumb slide while holding walks at full speed without accidental stamina dash")
	tc._on_finger_drag(0, Vector2(230, 500), Vector2(-400, 0)) # reverse 100 px left -> floating origin followed so we immediately walk left!
	check(p1().touch_move < -0.1, "floating-origin left stick reverses walking direction immediately without dead travel")
	tc._on_finger_up(0, Vector2(230, 500))

	# 2. Intentional Left Flick & Release gestures: Horizontal = Dash, Up = Half-Sword, Down = Kick
	tc._on_finger_down(0, Vector2(180, 500))
	tc._process(0.06)
	tc._on_finger_drag(0, Vector2(235, 500), Vector2(900, 0))
	tc._on_finger_up(0, Vector2(235, 500))
	check(p1().dash_timer > 0.0, "quick horizontal flick-and-release on left stick triggers Dash")
	p1().dash_timer = 0.0
	p1().dash_cooldown = 0.0

	tc._on_finger_down(0, Vector2(180, 500))
	tc._process(0.06)
	tc._on_finger_drag(0, Vector2(180, 445), Vector2(0, -800))
	tc._on_finger_up(0, Vector2(180, 445))
	check(p1().half_swording, "upward flick-and-release on left stick toggles Half-Sword stance")
	p1().set_half_sword(false, false)

	tc._on_finger_down(0, Vector2(180, 500))
	tc._process(0.06)
	tc._on_finger_drag(0, Vector2(180, 555), Vector2(0, 800))
	tc._on_finger_up(0, Vector2(180, 555))
	check(p1().current_action == "kick", "downward flick-and-release on left stick triggers Push Kick")
	p1().current_action = ""

	# 3. Right 360° Blade Wheel: no touchdown snap, Rear Guard Arc parries + guard-walks + instant Riposte, thumb arc cuts enemy!
	p1().position.x = 460.0
	p2().position.x = 635.0
	p1().set_facing(1)
	p2().set_facing(-1)
	p1().aim_override_enabled = true
	var pre_touch_aim := Vector2(610.0, 290.0)
	p1().aim_override = pre_touch_aim
	tc._on_finger_down(1, Vector2(980, 460))
	tc._process(0.04)
	check(p1().aim_override.distance_to(pre_touch_aim) < 1.0, "touching right blade wheel inside deadzone never teleports sword back to mid-chest")

	# Pull into Rear Guard Arc (away from p2) while walking back with left stick -> Parry + Guard-Walk!
	tc._on_finger_drag(1, Vector2(932, 452), Vector2(-200, 0))
	tc._on_finger_down(0, Vector2(180, 500))
	tc._on_finger_drag(0, Vector2(120, 500), Vector2(-300, 0))
	var x_pre_gwalk := p1().position.x
	p1()._process(0.05)
	check(p1().parrying and p1().position.x < x_pre_gwalk - 2.0, "pulling right wheel into Rear Guard Arc parries while still allowing left-thumb footwork")
	tc._on_finger_up(0, Vector2(120, 500))

	# Whip right thumb forward out of Rear Guard Arc across p2 -> instant zero-delay live cut that deals real damage!
	p1().position.x = 465.0
	p2().position.x = 625.0
	var hp_pre_swipe := p2().hp
	var swipe_pts := [
		Vector2(955, 395),
		Vector2(995, 415),
		Vector2(1035, 445),
		Vector2(1068, 485),
		Vector2(1090, 520),
	]
	for sp in swipe_pts:
		tc._on_finger_drag(1, sp, Vector2(850, 720))
		tc._process(0.016)
		p1()._process(0.016)
		arena._resolve_combat()
	tc._on_finger_up(1, Vector2(1090, 520))
	check(not p1().parrying and p2().hp < hp_pre_swipe, "whipping right thumb forward out of Rear Guard Arc activates live IK blade and cuts the rival")

	# 4. Quick Right Tap -> Intuitive Sword Slash (not an accidental whiffing kick!)
	p1().current_action = ""
	p1()._cursor_sweep_timer = 0.0
	tc._on_finger_down(2, Vector2(980, 420))
	tc._process(0.05)
	tc._on_finger_up(2, Vector2(982, 421))
	check(p1().current_action == "slash_high", "quick tap on right side fires an intuitive Sword Slash")
	tc._process(0.6)
	check(tc._left_alpha < 0.05 and tc._right_alpha < 0.05, "lifting fingers fades both translucent wheels back out to a clean screen")
	arena._on_setting_changed("touch", false)

	print("== Back to title")
	arena._go_to_title()
	await frames(3)
	check(arena.phase == TITLE and arena.ui._title_root.visible, "Change Fighters returns to the title screen")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	print("")
	print("SMOKE TEST: %d passed, %d failed" % [passes, failures.size()])
	for f in failures:
		print("   - ", f)
	paused = false
	Engine.time_scale = 1.0
	arena.ai = null
	arena.queue_free()
	await frames(3)
	quit(failures.size())


func _reset_both() -> void:
	for f in [p1(), p2()]:
		f.loadout_id = "signature"
		f.reset_fighter()
		f.cursor_aim_enabled = false
	p1().position = Vector2(440, 445)
	p2().position = Vector2(640, 445)


func _prime_attack(f: FighterController) -> void:
	f.current_action = "slash_high"
	f.action_elapsed = 0.2
	f.attack_serial += 1
