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

	print("== Title screen")
	check(arena.phase == TITLE, "game boots into the title screen")
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
		for f in range(30):
			await process_frame
			if p2().parrying:
				saw_parry = true
				if p1().action_elapsed < 0.1:
					reacted_instantly = true
				break
		if saw_parry and not reacted_instantly:
			parries += 1
	check(parries >= 4, "brutal AI parries telegraphed attacks after a reaction delay (%d/%d)" % [parries, trials])
	arena.ai = NullAI.new()

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
		f.reset_fighter()
		f.cursor_aim_enabled = false
	p1().position = Vector2(440, 445)
	p2().position = Vector2(640, 445)


func _prime_attack(f: FighterController) -> void:
	f.current_action = "slash_high"
	f.action_elapsed = 0.2
	f.attack_serial += 1
