extends SceneTree

## Headless balance simulator: pits bots against the rival AI and reports results.
##
## Usage (runs faster than real time):
##   godot --headless --fixed-fps 60 --path . --script res://tools/BalanceSim.gd -- --rounds=8
##
## Bots:
##   waggler - frantic mouse waggling (cursor aim) while walking in: the old exploit
##   swinger - deliberate big mouse swings with pauses, and parries when attacked
##   masher  - spams button attacks (slash/thrust/kick) while walking in
##   ai      - another AIController (mirror match)

const FIGHT := 2
const ROUND_END := 3

var arena: Node
var rounds := 8
var bot_ai := AIController.new()
var t := 0.0
var trace_bot := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
		if a.begins_with("--trace="):
			trace_bot = a.substr(8)
	_run.call_deferred()


func _run() -> void:
	var ps := load("res://scenes/Arena.tscn") as PackedScene
	arena = ps.instantiate()
	arena.settings_path = "user://balance_sim_settings.cfg"
	root.add_child(arena)
	await process_frame
	arena.settings["gore"] = false # fewer particles, faster sim
	arena.settings["sound"] = false

	if trace_bot != "":
		rounds = 1
		await _run_matchup(trace_bot, "brutal")
	else:
		print("bot      | AI diff | bot wins | AI wins | draws | avg round s | AI guards/rd | AI blocks/rd | bot hits/rd | bot severs/rd")
		for bot in ["splasher", "waggler", "swinger", "masher", "ai"]:
			for diff in ["normal", "hard", "brutal"]:
				await _run_matchup(bot, diff)

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://balance_sim_settings.cfg"))
	arena.queue_free()
	await process_frame
	quit(0)


func _run_matchup(bot: String, diff: String) -> void:
	arena.settings["difficulty"] = diff
	arena.settings["cursor_aim"] = bot in ["splasher", "waggler", "swinger"]
	arena._on_start_requested({"p1": 1, "p2": 1, "mode": "duel"}) # Fechtmeister mirror
	bot_ai.set_difficulty(diff)
	var bot_wins := 0
	var ai_wins := 0
	var draws := 0
	var total_time := 0.0
	var parries := 0
	var hits := 0
	var bot_severs := 0
	arena.debug_blocks.assign([0, 0])
	for r in range(rounds):
		arena.wins_p1 = 0
		arena.wins_p2 = 0
		arena._begin_round()
		bot_ai.reset()
		var p1: FighterController = arena.p1
		var p2: FighterController = arena.p2
		p1.is_player = bot != "ai"
		p1.aim_override_enabled = bot in ["splasher", "waggler", "swinger"]
		# Skip the intro.
		arena.phase_timer = 0.0
		await process_frame
		var last_p2_serial_blocked := {}
		var last_hp2 := p2.hp
		t = 0.0
		while arena.phase == FIGHT:
			await process_frame
			var dt: float = arena.get_process_delta_time()
			t += dt
			_drive_bot(bot, p1, p2, dt)
			if p2.parrying and p1.is_attack_threat() and not last_p2_serial_blocked.has(p1.attack_serial):
				last_p2_serial_blocked[p1.attack_serial] = true
				parries += 1
			if p2.hp < last_hp2 - 0.5:
				hits += 1
			if trace_bot != "" and (Engine.get_process_frames() % 4 == 0 or p2.hp < last_hp2 - 0.5):
				var ai: AIController = arena.ai
				print("t=%5.2f dist=%4d tip=%5d thr=%s blade=%s ser=%d | AI st=%d act=%-12s par=%s zone=%-4s thr_t=%.2f dec=%s | hp1=%5.1f hp2=%5.1f st1=%4.1f st2=%4.1f | a1=%s@%.2f %s a2=%s@%.2f %s ts=%.2f" % [t, int(absf(p1.position.x - p2.position.x)), int(p1.get_blade_tip_speed()), p1.is_attack_threat(), p1.is_blade_active(), p1.attack_serial, ai.state, p2.current_action, p2.parrying, p2.guard_zone, ai._threat_time, ai._episode_decided, p1.hp, p2.hp, p1.stamina, p2.stamina, p1.anim_player.current_animation, p1.anim_player.current_animation_position if p1.anim_player.current_animation != "" else -1.0, p1.anim_player.is_playing(), p2.anim_player.current_animation, p2.anim_player.current_animation_position if p2.anim_player.current_animation != "" else -1.0, p2.anim_player.is_playing(), Engine.time_scale])
			last_hp2 = p2.hp
			if t > 95.0:
				break
		total_time += 90.0 - arena.round_time_left
		for sv in p2.severed.values():
			if bool(sv):
				bot_severs += 1
		match arena.last_round_winner:
			1: bot_wins += 1
			2: ai_wins += 1
			_: draws += 1
		p1.aim_override_enabled = false
		p1.touch_move = 0.0
		p1.touch_parry = false
		p1.is_player = true
	print("%-8s | %-7s | %8d | %7d | %5d | %11.1f | %12.1f | %12.1f | %11.1f | %13.2f" % [bot, diff, bot_wins, ai_wins, draws, total_time / rounds, float(parries) / rounds, float(arena.debug_blocks[1]) / rounds, float(hits) / rounds, float(bot_severs) / rounds])


func _drive_bot(bot: String, me: FighterController, foe: FighterController, dt: float) -> void:
	var dist := absf(foe.position.x - me.position.x)
	var dir := 1.0 if foe.position.x > me.position.x else -1.0
	match bot:
		"ai":
			bot_ai.step(dt, me, foe)
		"splasher":
			# Small micro-wiggles (+-26 px) right on top of the opponent's chest/arms.
			me.touch_move = dir if dist > 165.0 else 0.0
			var center_s := foe.position + Vector2(-dir * 35.0, -135.0)
			me.aim_override = center_s + Vector2(0, 26.0 * sin(TAU * 5.0 * t))
		"waggler":
			# Walk in to ~165 px and waggle the blade up/down at 4 Hz across the foe.
			me.touch_move = dir if dist > 175.0 else (-dir if dist < 140.0 else 0.0)
			var center := foe.position + Vector2(-dir * 30.0, -150.0)
			me.aim_override = center + Vector2(0, 120.0 * sin(TAU * 4.0 * t))
		"swinger":
			# Deliberate swings: big arc every ~0.9 s, rest in guard between; parry threats.
			me.touch_move = dir if dist > 185.0 else (-dir if dist < 145.0 else 0.0)
			var phase := fmod(t, 0.9)
			var center := foe.position + Vector2(-dir * 20.0, -160.0)
			if phase < 0.18:
				me.aim_override = center + Vector2(0, lerpf(-140.0, 140.0, phase / 0.18))
			else:
				me.aim_override = me.position + Vector2(dir * 120.0, -170.0)
			me.touch_parry = foe.current_action in FighterController.ATTACK_MOVES and foe.action_elapsed > 0.05 and foe.action_elapsed < 0.3 and randf() < 0.85
		"masher":
			me.touch_move = dir if dist > 190.0 else 0.0
			if me.current_action == "" and dist < 240.0:
				var roll := randf()
				if roll < 0.06:
					me.start_attack("slash_high")
				elif roll < 0.10:
					me.start_attack("slash_low")
				elif roll < 0.13:
					me.start_attack("thrust")
				elif roll < 0.14:
					me.start_attack("kick")
