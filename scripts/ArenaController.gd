extends Node2D

## Strings & Steel: arena / match controller.
##
## Owns the match flow (title, round intro, fight, round end, match end), combat
## resolution between the two fighters, the theatre stage, particles and camera.
## Other responsibilities live in their own scripts:
##   AIController.gd   - rival AI
##   BloodCanvas.gd    - persistent GPU blood layers
##   GameUI.gd         - HUD, title / pause / result screens, touch controls
##   FighterStats.gd   - per-fighter tuning
##   GameInput.gd      - InputMap registration

enum Phase { TITLE, INTRO, FIGHT, ROUND_END, MATCH_END }

const FIGHTER_ROSTER := [
	{"id": "landsknecht", "scene": "res://scenes/fighters/Landsknecht.tscn"},
	{"id": "fechtmeister", "scene": "res://scenes/fighters/Fechtmeister.tscn"},
	{"id": "plague_executioner", "scene": "res://scenes/fighters/PlagueExecutioner.tscn"},
	{"id": "black_knight", "scene": "res://scenes/fighters/BlackKnight.tscn"},
	{"id": "venetian_bravo", "scene": "res://scenes/fighters/VenetianBravo.tscn"},
]

const ROUNDS_TO_WIN := 2
const ROUND_TIME := 90.0
const INTRO_TIME := 1.4
const ROUND_END_TIME := 2.8
const FLOOR_Y := 562.0
const MIN_FIGHTER_GAP := 116.0
const SETTINGS_PATH := "user://settings.cfg"

@onready var cam: Camera2D = $Camera2D
@onready var p1: FighterController = $Landsknecht
@onready var p2: FighterController = $Fechtmeister

var p1_roster_idx: int = 0
var p2_roster_idx: int = 1
## Where settings & records are persisted (tests point this elsewhere).
var settings_path: String = SETTINGS_PATH

# Systems
var sfx: SoundFX
var blood: BloodCanvas
var ui: GameUI
var ai := AIController.new()

# Theatre & FX layers
var stage_layer: Node2D
var candle_layer: Node2D
var debris_layer: Node2D
var fx_layer: Node2D
var particles_blood: Array[Dictionary] = []
var particles_sparks: Array[Dictionary] = []
var particles_chunks: Array[Dictionary] = []
var particles_mist: Array[Dictionary] = []
var arterial_jets: Array[Dictionary] = []
var slash_flashes: Array[Dictionary] = []
var callouts: Array[Dictionary] = []
var candles: Array[Dictionary] = []
var blood_flash_alpha: float = 0.0

const MAX_BLOOD_PARTICLES := 340
const MAX_SPARKS := 260
const MAX_CHUNKS := 120
const MAX_MIST := 60

# Settings (persisted to user://settings.cfg)
var settings := {
	"difficulty": "hard",
	"gore": true,
	"one_hit_sever": false,
	"cursor_aim": true,
	"touch": false,
	"strings": true,
	"sound": true,
}

# Match state
var phase: Phase = Phase.TITLE
var match_mode: String = "duel" # "duel" | "gauntlet"
var round_num: int = 1
var wins_p1: int = 0
var wins_p2: int = 0
var round_time_left: float = ROUND_TIME
var phase_timer: float = 0.0
var last_round_winner: int = 0 # 0 draw, 1 p1, 2 p2
var gauntlet_wave: int = 1
var best_wave: int = 0
var paused: bool = false

# Feel
var slow_mo_timer: float = 0.0
var hitstop_timer: float = 0.0
var shake_mag: float = 0.0
var cam_zoom_target: float = 1.0
var cam_focus: Vector2 = Vector2(640, 360)
var _last_clash_serial: Dictionary = {}
## Debug counters (read by tools/BalanceSim.gd).
var debug_blocks: Array[int] = [0, 0]


func _ready() -> void:
	GameInput.register()
	_load_settings()

	sfx = SoundFX.new()
	add_child(sfx)

	stage_layer = Node2D.new()
	stage_layer.name = "StageLayer"
	stage_layer.z_index = -35
	stage_layer.draw.connect(_draw_stage)
	add_child(stage_layer)

	blood = BloodCanvas.new()
	blood.name = "BloodCanvas"
	add_child(blood)

	candle_layer = Node2D.new()
	candle_layer.name = "CandleLayer"
	candle_layer.z_index = -10
	candle_layer.draw.connect(_draw_candles)
	add_child(candle_layer)

	debris_layer = Node2D.new()
	debris_layer.name = "DebrisLayer"
	debris_layer.z_index = 60
	add_child(debris_layer)

	fx_layer = Node2D.new()
	fx_layer.name = "FXLayer"
	fx_layer.z_index = 80
	fx_layer.draw.connect(_draw_fx)
	add_child(fx_layer)

	_init_candles()

	ui = GameUI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.setup(_roster_info(), settings)
	ui.start_requested.connect(_on_start_requested)
	ui.pause_toggle_requested.connect(_toggle_pause)
	ui.resume_requested.connect(func(): _set_paused(false))
	ui.restart_round_requested.connect(func():
		_set_paused(false)
		_begin_round())
	ui.title_requested.connect(_go_to_title)
	ui.rematch_requested.connect(_on_rematch)
	ui.setting_changed.connect(_on_setting_changed)

	_wire_fighter(p1, true)
	_wire_fighter(p2, false)
	_apply_settings()
	_go_to_title()


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("game", k, settings[k])
	best_wave = int(cfg.get_value("records", "best_wave", 0))
	p1_roster_idx = clampi(int(cfg.get_value("game", "p1_idx", 0)), 0, FIGHTER_ROSTER.size() - 1)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("game", k, settings[k])
	cfg.set_value("game", "p1_idx", p1_roster_idx)
	cfg.set_value("records", "best_wave", best_wave)
	cfg.save(settings_path)


func _on_setting_changed(key: String, value: Variant) -> void:
	settings[key] = value
	_apply_settings()
	_save_settings()


func _apply_settings() -> void:
	sfx.muted = not bool(settings["sound"])
	ai.set_difficulty(_effective_difficulty())
	for f in [p1, p2]:
		if f != null:
			f.gore_enabled = bool(settings["gore"])
			f.show_strings = bool(settings["strings"])
	if p1 != null:
		# Touch input emulates the mouse, which would yank the cursor-aim IK around.
		p1.cursor_aim_enabled = bool(settings["cursor_aim"]) and not bool(settings["touch"])
	if ui != null:
		ui.player = p1
		ui.set_touch_visible(bool(settings["touch"]))
		ui.refresh_hint(p1 != null and p1.cursor_aim_enabled)


func _effective_difficulty() -> String:
	var base: String = settings["difficulty"]
	if match_mode != "gauntlet":
		return base
	var order := ["normal", "hard", "brutal"]
	var lvl := order.find(base)
	if gauntlet_wave >= 7:
		lvl = maxi(lvl, 2)
	elif gauntlet_wave >= 4:
		lvl = maxi(lvl, 1)
	return order[lvl]


# ---------------------------------------------------------------------------
# Fighters
# ---------------------------------------------------------------------------

func _roster_info() -> Array:
	var out: Array = []
	for e in FIGHTER_ROSTER:
		out.append(FighterStats.get_stats(String(e["id"])))
	return out


func _wire_fighter(f: FighterController, is_p1: bool) -> void:
	if f == null:
		return
	f.is_player = is_p1
	f.request_spawn_debris.connect(_on_spawn_debris)
	f.request_blood_spray.connect(_on_blood_spray)
	f.request_sfx.connect(func(k: String, j: float): sfx.play_sfx(k, j))
	f.request_cut_flash.connect(_on_cut_flash)
	f.request_sever_fx.connect(_on_sever_fx)


func _set_fighter(is_p1: bool, new_idx: int) -> void:
	var count: int = FIGHTER_ROSTER.size()
	var idx: int = ((new_idx % count) + count) % count
	var current := p1 if is_p1 else p2
	if current != null and current.fighter_id == String(FIGHTER_ROSTER[idx]["id"]):
		if is_p1:
			p1_roster_idx = idx
		else:
			p2_roster_idx = idx
		return
	var ps := load(String(FIGHTER_ROSTER[idx]["scene"])) as PackedScene
	if ps == null:
		return
	var new_f := ps.instantiate() as FighterController
	if new_f == null:
		return
	if current != null:
		current.queue_free()
	if is_p1:
		p1_roster_idx = idx
		p1 = new_f
	else:
		p2_roster_idx = idx
		p2 = new_f
	add_child(new_f)
	_wire_fighter(new_f, is_p1)
	_apply_settings()


# ---------------------------------------------------------------------------
# Match flow
# ---------------------------------------------------------------------------

func _go_to_title() -> void:
	_set_paused(false)
	phase = Phase.TITLE
	_reset_stage()
	_freeze_fighters(true)
	ui.hide_result()
	ui.show_title(p1_roster_idx, p2_roster_idx, match_mode, best_wave)


func _on_start_requested(cfg: Dictionary) -> void:
	match_mode = String(cfg.get("mode", "duel"))
	var p1_idx := int(cfg.get("p1", 0))
	var p2_idx := int(cfg.get("p2", -1))
	if p2_idx < 0:
		p2_idx = randi() % FIGHTER_ROSTER.size()
	_set_fighter(true, p1_idx)
	_set_fighter(false, p2_idx)
	_save_settings()
	ui.hide_title()
	_start_match()


func _start_match() -> void:
	wins_p1 = 0
	wins_p2 = 0
	round_num = 1
	gauntlet_wave = 1
	ai.set_difficulty(_effective_difficulty())
	ui.hide_result()
	_begin_round()


func _on_rematch() -> void:
	if match_mode == "gauntlet":
		_set_fighter(false, randi() % FIGHTER_ROSTER.size())
	_start_match()


func _begin_round() -> void:
	_reset_stage()
	phase = Phase.INTRO
	phase_timer = INTRO_TIME
	round_time_left = ROUND_TIME
	_freeze_fighters(true)
	var vs := "%s  vs  %s" % [String(p1.stats["display_name"]), String(p2.stats["display_name"])]
	if match_mode == "gauntlet":
		ui.show_banner("WAVE %d" % gauntlet_wave, vs, INTRO_TIME)
	else:
		var final_round := wins_p1 == ROUNDS_TO_WIN - 1 and wins_p2 == ROUNDS_TO_WIN - 1
		ui.show_banner("FINAL ROUND" if final_round else "ROUND %d" % round_num, vs, INTRO_TIME)


func _reset_stage() -> void:
	slow_mo_timer = 0.0
	hitstop_timer = 0.0
	Engine.time_scale = 1.0
	cam_zoom_target = 1.0
	cam_focus = Vector2(640, 360)
	shake_mag = 0.0
	_last_clash_serial.clear()
	particles_blood.clear()
	particles_sparks.clear()
	particles_chunks.clear()
	particles_mist.clear()
	arterial_jets.clear()
	slash_flashes.clear()
	callouts.clear()
	blood_flash_alpha = 0.0
	blood.clear()
	for c in debris_layer.get_children():
		c.queue_free()
	ai.reset()

	if p1 != null:
		p1.position = Vector2(440, 445)
		p1.hp_scale = 1.0
		p1.limb_hp_scale = 1.0
		p1.reset_fighter()
		p1.set_facing(1)
	if p2 != null:
		p2.position = Vector2(840, 445)
		var wave_bonus := float(gauntlet_wave - 1) if match_mode == "gauntlet" else 0.0
		p2.hp_scale = 1.0 + 0.12 * wave_bonus
		p2.limb_hp_scale = 1.0 + 0.08 * wave_bonus
		p2.reset_fighter()
		p2.set_facing(-1)
	_apply_settings()


func _freeze_fighters(frozen: bool) -> void:
	for f in [p1, p2]:
		if f != null:
			f.input_enabled = not frozen
			if frozen:
				f.parrying = false
				f.parry_hold_time = 99.0


func _end_round(winner: int, by_timeout: bool) -> void:
	phase = Phase.ROUND_END
	phase_timer = ROUND_END_TIME
	last_round_winner = winner
	_freeze_fighters(true)
	for f in [p1, p2]:
		f.combat_frozen = true
	if not by_timeout:
		slow_mo_timer = 1.65
		sfx.play_sfx("ko_boom", 0.05)

	if winner == 1:
		wins_p1 += 1
	elif winner == 2:
		wins_p2 += 1

	var title := "DOUBLE K.O." if winner == 0 else ("TIME!" if by_timeout else "K.O.")
	var sub := ""
	if winner == 1:
		sub = "%s wins the round" % String(p1.stats["display_name"])
	elif winner == 2:
		sub = "%s wins the round" % String(p2.stats["display_name"])
	else:
		sub = "Round is replayed"
	ui.show_banner(title, sub, ROUND_END_TIME * 0.8)


func _advance_after_round() -> void:
	if match_mode == "gauntlet":
		if last_round_winner == 1:
			gauntlet_wave += 1
			var next_idx := p2_roster_idx
			if FIGHTER_ROSTER.size() > 1:
				while next_idx == p2_roster_idx:
					next_idx = randi() % FIGHTER_ROSTER.size()
			_set_fighter(false, next_idx)
			ai.set_difficulty(_effective_difficulty())
			_begin_round()
		elif last_round_winner == 0:
			_begin_round()
		else:
			var cleared := gauntlet_wave - 1
			var new_best := cleared > best_wave
			best_wave = maxi(best_wave, cleared)
			_save_settings()
			phase = Phase.MATCH_END
			ui.show_result("RUN OVER", "Waves cleared: %d    Best: %d%s" % [cleared, best_wave, "   NEW RECORD!" if new_best else ""], "RETRY GAUNTLET")
		return

	if wins_p1 >= ROUNDS_TO_WIN or wins_p2 >= ROUNDS_TO_WIN:
		phase = Phase.MATCH_END
		var won := wins_p1 > wins_p2
		ui.show_result("VICTORY" if won else "DEFEAT", "%s  %d - %d  %s" % [String(p1.stats["display_name"]), wins_p1, wins_p2, String(p2.stats["display_name"])], "REMATCH")
		return
	round_num += 1
	_begin_round()


func _toggle_pause() -> void:
	if phase == Phase.TITLE or phase == Phase.MATCH_END:
		return
	_set_paused(not paused)


func _set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	if ui != null:
		ui.show_pause(on)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var unscaled_dt := delta / maxf(0.05, Engine.time_scale)

	# Hitstop / slow-motion
	if hitstop_timer > 0.0:
		hitstop_timer -= unscaled_dt
		Engine.time_scale = 0.06
	elif slow_mo_timer > 0.0:
		slow_mo_timer -= unscaled_dt
		Engine.time_scale = 0.24
	else:
		Engine.time_scale = lerpf(Engine.time_scale, 1.0, minf(1.0, 10.0 * unscaled_dt))

	if p1 == null or p2 == null:
		return

	_update_camera(unscaled_dt)

	# Auto-face while alive
	var dir := 1 if p2.position.x >= p1.position.x else -1
	if not p1.is_dead:
		p1.set_facing(dir)
	if not p2.is_dead:
		p2.set_facing(-dir)

	match phase:
		Phase.INTRO:
			_idle_ai_fighter()
			phase_timer -= unscaled_dt
			if phase_timer <= 0.0:
				phase = Phase.FIGHT
				_freeze_fighters(false)
				ui.show_banner("FIGHT!", "", 0.6)
		Phase.FIGHT:
			ai.step(delta, p2, p1)
			_separate_fighters()
			_resolve_combat()
			round_time_left -= delta
			if p1.is_dead or p2.is_dead:
				var w := 0 if (p1.is_dead and p2.is_dead) else (1 if p2.is_dead else 2)
				_end_round(w, false)
			elif round_time_left <= 0.0 and match_mode == "duel":
				var f1 := p1.hp / maxf(1.0, p1.max_hp)
				var f2 := p2.hp / maxf(1.0, p2.max_hp)
				var w := 0 if absf(f1 - f2) < 0.01 else (1 if f1 > f2 else 2)
				_end_round(w, true)
		Phase.ROUND_END:
			_idle_ai_fighter()
			phase_timer -= unscaled_dt
			if phase_timer <= 0.0:
				_advance_after_round()
		_:
			_idle_ai_fighter()

	_step_particles(delta)
	_step_bootprints(delta)
	_step_callouts(unscaled_dt)
	_refresh_hud()
	if candle_layer != null:
		candle_layer.queue_redraw()
	if fx_layer != null:
		fx_layer.queue_redraw()


func _update_camera(unscaled_dt: float) -> void:
	var mid := (p1.position + p2.position) * 0.5 + Vector2(0, -105)
	var sep := absf(p1.position.x - p2.position.x)
	var base_zoom := clampf(lerpf(1.16, 0.94, sep / 700.0), 0.92, 1.22)
	var ko_focus := phase == Phase.ROUND_END and (p1.is_dead or p2.is_dead)
	if ko_focus or slow_mo_timer > 0.0:
		cam_zoom_target = 1.38
		var target := p2 if p2.is_dead else p1
		cam_focus = cam_focus.lerp(target.position + Vector2(0, -110), minf(1.0, 6.0 * unscaled_dt))
	else:
		cam_zoom_target = base_zoom
		cam_focus = cam_focus.lerp(Vector2(clampf(mid.x, 420.0, 860.0), clampf(mid.y, 280.0, 380.0)), minf(1.0, 6.0 * unscaled_dt))
	if cam != null:
		cam.zoom = cam.zoom.lerp(Vector2(cam_zoom_target, cam_zoom_target), minf(1.0, 5.5 * unscaled_dt))
		var jitter := Vector2(randf_range(-shake_mag, shake_mag), randf_range(-shake_mag, shake_mag))
		cam.position = cam_focus + jitter
	shake_mag = maxf(0.0, shake_mag - 42.0 * unscaled_dt)


func _idle_ai_fighter() -> void:
	if p2 != null and not p2.is_dead:
		p2.parrying = false
		p2.aim_override_enabled = false
		if p2.current_action == "":
			p2.play_anim("idle", 0.1)


## Fighters are solid: living fighters can't walk through each other.
func _separate_fighters() -> void:
	if p1.is_dead or p2.is_dead:
		return
	var dx := p2.position.x - p1.position.x
	var gap := absf(dx)
	if gap >= MIN_FIGHTER_GAP:
		return
	var push := (MIN_FIGHTER_GAP - gap) * 0.5
	var s := 1.0 if dx >= 0.0 else -1.0
	if gap < 0.5:
		s = 1.0 if p1.facing > 0 else -1.0
	p1.position.x = clampf(p1.position.x - s * push, 120.0, 1160.0)
	p2.position.x = clampf(p2.position.x + s * push, 120.0, 1160.0)
	# If one is pinned against the wall, push the other the full distance.
	var remaining := MIN_FIGHTER_GAP - absf(p2.position.x - p1.position.x)
	if remaining > 0.5:
		if p1.position.x <= 120.5 or p1.position.x >= 1159.5:
			p2.position.x = clampf(p2.position.x + s * remaining, 120.0, 1160.0)
		else:
			p1.position.x = clampf(p1.position.x - s * remaining, 120.0, 1160.0)


# ---------------------------------------------------------------------------
# Combat resolution
# ---------------------------------------------------------------------------

func _resolve_combat() -> void:
	# 1. Blade vs blade (clash / parry / block), using swept paths so fast flicks never tunnel.
	var s1 := p1.get_swept_blade_segments()
	var s2 := p2.get_swept_blade_segments()
	if s1.size() > 0 and s2.size() > 0:
		var best_d := 9999.0
		var best_pt := Vector2.ZERO
		for seg_a in s1:
			for seg_b in s2:
				var info := _closest_segments(seg_a[0], seg_a[1], seg_b[0], seg_b[1])
				if float(info["dist"]) < best_d:
					best_d = float(info["dist"])
					best_pt = info["pt"]
		if best_d < 28.0:
			_handle_blade_clash(p1, p2, best_pt)
			_handle_blade_clash(p2, p1, best_pt)

	# 2. Kicks
	_check_kick(p1, p2)
	_check_kick(p2, p1)

	# 3. Blade vs live overhead marionette strings ("Strings & Steel"!)
	_check_live_string_cut(p1, p2)
	_check_live_string_cut(p2, p1)

	# 4. Blade vs body capsules
	_check_blade_vs_body(p1, p2)
	_check_blade_vs_body(p2, p1)

	# 5. Blade vs dangling marionette ropes
	_check_debris_rope_cut(p1)
	_check_debris_rope_cut(p2)


func _handle_blade_clash(atk: FighterController, def: FighterController, pt: Vector2) -> void:
	if not atk.is_blade_active():
		return
	var key := "%d:%d" % [atk.get_instance_id(), atk.attack_serial]
	if _last_clash_serial.has(key):
		return
	var explicit_guard: bool = def.parrying
	var blades_meet: bool = def.is_blade_active()
	# A player holding the blade still in cursor mode can block with it, but it is a
	# clumsy, expensive block (no perfect parry, high stamina cost, can be broken).
	var passive_guard: bool = def.is_player and def.cursor_aim_enabled and def.can_wield() and def.current_action == ""
	if not (explicit_guard or blades_meet or passive_guard):
		return
	_last_clash_serial[key] = true
	_spawn_sparks(pt, 24)
	if explicit_guard:
		debug_blocks[0 if def == p1 else 1] += 1

	if explicit_guard and def.is_perfect_parry():
		atk.hit_registered_serial = atk.attack_serial
		hitstop_timer = 0.08
		shake_mag = maxf(shake_mag, 14.0)
		sfx.play_sfx("perfect_parry", 0.06, 2.0)
		_rumble(0.75, 0.90, 0.22)
		atk.trigger_hurt(true)
		atk.apply_blade_rebound(1.25)
		atk.spend_stamina(20.0)
		def.stamina = minf(def.max_stamina, def.stamina + 10.0)
		def.grant_riposte()
		atk.knockback_vx = -float(atk.facing) * 320.0
		_spawn_sparks(pt, 36)
		_on_cut_flash(pt, "PERFECT PARRY!", Color(1.0, 0.88, 0.35))
		if def == p2:
			ai.notify_blocked(true)
		return

	var cost := 14.0 if explicit_guard else (8.0 if blades_meet else 20.0)
	cost *= def.get_guard_cost_mult()
	if def.stamina < cost:
		# Guard broken: the defender is staggered and the cut carries through.
		def.spend_stamina(def.stamina)
		def.trigger_hurt(false)
		shake_mag = maxf(shake_mag, 10.0)
		sfx.play_sfx("clang", 0.12, -4.0)
		_on_cut_flash(pt, "GUARD BROKEN!", Color(1.0, 0.55, 0.3))
		return

	atk.hit_registered_serial = atk.attack_serial
	atk.apply_blade_rebound(0.95)
	def.spend_stamina(cost)
	if explicit_guard:
		def.grant_riposte()
	if blades_meet:
		atk.spend_stamina(8.0)
		def.apply_blade_rebound(0.80)
	hitstop_timer = 0.065
	shake_mag = maxf(shake_mag, 12.0)
	sfx.play_sfx("clang", 0.12)
	_rumble(0.45, 0.35, 0.12)
	atk.knockback_vx = -float(atk.facing) * 140.0
	def.knockback_vx = -float(def.facing) * 110.0
	_on_cut_flash(pt, "CLANG!" if not passive_guard or explicit_guard else "BLOCKED", Color(0.95, 0.92, 0.72))
	if def == p2 and explicit_guard:
		ai.notify_blocked(false)


func _check_kick(atk: FighterController, def: FighterController) -> void:
	if not atk.is_kick_active() or def.is_dead:
		return
	var key := "kick:%d:%d" % [atk.get_instance_id(), atk.attack_serial]
	if _last_clash_serial.has(key):
		return
	if atk.bone_boot_r == null:
		return
	var foot_pt := atk.bone_boot_r.global_position
	if foot_pt.distance_to(def.position + Vector2(0, -100)) < 110.0:
		_last_clash_serial[key] = true
		sfx.play_sfx("thud", 0.15)
		def.knockback_vx = float(atk.facing) * 420.0
		def.spend_stamina(22.0)
		def.parrying = false
		def.trigger_hurt(false)
		shake_mag = maxf(shake_mag, 10.0)
		_on_cut_flash(foot_pt, "PUSH KICK!", Color(0.92, 0.76, 0.38))


func _check_blade_vs_body(atk: FighterController, def: FighterController) -> void:
	if def.is_dead:
		return
	var blade := atk.get_blade_segment()
	if blade.size() < 2:
		return

	# A blade merely held in place gently pushes an enemy who walks onto the point.
	if not atk.is_blade_active():
		var torso_pt := def.position + Vector2(0, -105.0)
		var passive_info := _closest_segments(blade[0], blade[1], torso_pt, torso_pt + Vector2(0, -45.0))
		if float(passive_info["dist"]) < 22.0 and absf(def.knockback_vx) < 40.0:
			def.knockback_vx = float(atk.facing) * 65.0
		return

	if atk.hit_registered_serial == atk.attack_serial:
		return

	var swept := atk.get_swept_blade_segments()
	var segs := def.get_body_segments()
	var best_slot := ""
	var best_score := 9999.0
	var best_pt := Vector2.ZERO
	for s in segs:
		var slot: String = s[0]
		# Exposed sword/off arms sit in front of the torso: prefer them on shallow grazes
		# instead of letting torso's wider capsule swallow every brush.
		var outer_bias := 5.0 if slot in ["forearm_r", "arm_r", "forearm_l", "arm_l"] else 0.0
		for b_seg in swept:
			var info := _closest_segments(b_seg[0], b_seg[1], s[1], s[2])
			var d: float = float(info["dist"]) - float(s[3])
			if d < 0.0 and (d - outer_bias) < best_score:
				best_score = d - outer_bias
				best_slot = slot
				best_pt = info["pt"]

	if best_slot == "":
		return

	# Explicit directional guard: if the defender is actively parrying the attacked line,
	# catch the blow on their crossguard even in close measure (unless their guard breaks!).
	if _is_covered_by_parry(atk, def, best_slot, best_pt):
		var def_b := def.get_blade_segment()
		var spark_pt: Vector2 = (Vector2(def_b[0]) + best_pt) * 0.5 if def_b.size() == 2 else best_pt
		_handle_blade_clash(atk, def, spark_pt)
		if atk.hit_registered_serial == atk.attack_serial:
			return

	atk.hit_registered_serial = atk.attack_serial
	var pwr := atk.get_strike_power()
	var b_guard: Vector2 = blade[0]
	var b_vec: Vector2 = Vector2(blade[1]) - b_guard
	var blade_pos_frac := clampf((best_pt - b_guard).dot(b_vec) / maxf(1.0, b_vec.length_squared()), 0.0, 1.0)
	var swing_dir := Vector2(float(atk.facing), -0.35 if atk.current_action == "slash_low" else 0.25).normalized()
	if atk.current_action == "" and atk._cursor_last_dir.length() > 0.1:
		var cx := float(atk.facing) * absf(atk._cursor_last_dir.x) if absf(atk._cursor_last_dir.x) > 0.2 else float(atk.facing)
		swing_dir = Vector2(cx, atk._cursor_last_dir.y).normalized()
	var is_thrust := atk.is_thrust_strike()
	var attacker_heavy := pwr >= FighterController.HEAVY_POWER_THRESHOLD and blade_pos_frac >= 0.38 and not is_thrust
	var is_rip := atk._riposte_active_attack
	atk._riposte_active_attack = false
	var dmg := (24.0 if is_thrust else 20.0) * atk.stat("damage_mult") * (atk.stat("thrust_mult") if is_thrust else 1.0)
	if atk.current_action == "":
		# Free-form cursor cuts have less body-weight behind them than full animated lunges.
		dmg *= 0.85 if is_thrust else 0.78
	if is_rip:
		dmg *= 1.18
		_on_cut_flash(best_pt, "RIPOSTE!", Color(1.0, 0.88, 0.42))
	var did_sever := def.apply_blade_damage(best_slot, dmg, best_pt, swing_dir, bool(settings["one_hit_sever"]), attacker_heavy, pwr, atk.stat("limb_damage_mult"), blade_pos_frac, is_thrust, atk.stat("armor_pierce_thrust"))
	atk.blade_blood = minf(1.0, atk.blade_blood + (0.65 if did_sever else 0.24 * pwr))

	if def.is_armored_slot(best_slot):
		_spawn_sparks(best_pt, maxi(4, int(10.0 * pwr)))
		sfx.play_sfx("clang", 0.2, -5.0)
		if not did_sever and not is_thrust:
			atk.apply_blade_rebound(0.60)

	if did_sever or pwr >= 0.68:
		hitstop_timer = 0.105 if did_sever else 0.042
		shake_mag = maxf(shake_mag, 22.0 if did_sever else 9.0)
		_rumble(0.85 if did_sever else 0.35, 0.95 if did_sever else 0.25, 0.26 if did_sever else 0.10)
	if did_sever:
		slow_mo_timer = maxf(slow_mo_timer, 0.95)


func _is_covered_by_parry(atk: FighterController, def: FighterController, slot: String, hit_pt: Vector2) -> bool:
	if not def.parrying or not def.can_wield() or def.is_dead:
		return false
	var facing_atk := (atk.position.x - def.position.x) * float(def.facing) >= -20.0
	if not facing_atk:
		return false
	var is_low_leg := slot in ["thigh_r", "shin_r", "thigh_l", "shin_l"]
	var is_low_strike := atk.current_action == "slash_low" or is_low_leg or (atk.current_action == "" and hit_pt.y > def.position.y - 36.0)
	if def.guard_zone == "low":
		return is_low_strike or (slot == "torso" and hit_pt.y > def.position.y - 68.0)
	return not is_low_strike


func _check_live_string_cut(atk: FighterController, def: FighterController) -> void:
	if not atk.is_blade_active() or def.is_dead or atk.is_thrust_strike():
		return
	if atk.hit_registered_serial == atk.attack_serial:
		return
	if atk.get_strike_power() < 0.52:
		return
	# High parry protects the overhead strings!
	if def.parrying and def.can_wield() and def.guard_zone == "high":
		return
	var swept := atk.get_swept_blade_segments()
	var strings := def.get_live_string_segments()
	for s_entry in strings:
		var skey: String = s_entry[0]
		for b_seg in swept:
			# Only outer half of blade slicing high above the puppet's shoulders snaps strings.
			var mid_tip := Vector2(b_seg[0]).lerp(Vector2(b_seg[1]), 0.35)
			var info := _closest_segments(mid_tip, b_seg[1], s_entry[1], s_entry[2])
			if float(info["dist"]) < 12.0:
				if def.cut_live_string(skey, info["pt"]):
					atk.hit_registered_serial = atk.attack_serial
					_spawn_sparks(info["pt"], 10)
					hitstop_timer = 0.04
					return


func _check_debris_rope_cut(atk: FighterController) -> void:
	if not atk.is_blade_active() or debris_layer == null:
		return
	var blade := atk.get_blade_segment()
	if blade.size() < 2:
		return
	for c in debris_layer.get_children():
		if c is PhysicsDebris:
			var deb := c as PhysicsDebris
			var seg := deb.get_string_segment()
			if seg.size() == 2:
				var info := _closest_segments(blade[0], blade[1], seg[0], seg[1])
				if float(info["dist"]) < 14.0:
					deb.cut_string(Vector2(float(atk.facing) * 140.0, -40.0))
					sfx.play_sfx("snap", 0.12)
					_on_cut_flash(info["pt"], "STRING SNAPPED!", Color(0.95, 0.84, 0.52))


func _closest_segments(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	var u := b - a
	var v := d - c
	var w := a - c
	var aa := u.dot(u)
	var bb := u.dot(v)
	var cc := v.dot(v)
	var dd := u.dot(w)
	var ee := v.dot(w)
	var denom := aa * cc - bb * bb
	var sc := 0.0
	var tc := 0.0
	if denom > 1e-5:
		sc = clampf((bb * ee - cc * dd) / denom, 0.0, 1.0)
	var t_nom := bb * sc + ee
	if t_nom < 0.0:
		tc = 0.0
		sc = clampf(-dd / maxf(1e-5, aa), 0.0, 1.0)
	elif t_nom > cc:
		tc = 1.0
		sc = clampf((bb - dd) / maxf(1e-5, aa), 0.0, 1.0)
	else:
		tc = t_nom / maxf(1e-5, cc)
	var pa := a + u * sc
	var pb := c + v * tc
	return {"dist": pa.distance_to(pb), "pt": (pa + pb) * 0.5}


func _rumble(weak: float, strong: float, dur: float) -> void:
	for jid in Input.get_connected_joypads():
		Input.start_joy_vibration(jid, weak, strong, dur)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("restart"):
		match phase:
			Phase.INTRO, Phase.FIGHT:
				_begin_round()
			Phase.ROUND_END:
				_advance_after_round()
			Phase.MATCH_END:
				_on_rematch()
		return
	# Skip the round-end pause with the primary attack buttons.
	if phase == Phase.ROUND_END and phase_timer < ROUND_END_TIME - 0.8:
		if event.is_action_pressed("slash") or event.is_action_pressed("kick"):
			_advance_after_round()


# ---------------------------------------------------------------------------
# FX: debris, blood, sparks, callouts
# ---------------------------------------------------------------------------

func _on_spawn_debris(deb: PhysicsDebris) -> void:
	deb.floor_bounced.connect(func(pos: Vector2, spd: float):
		if spd > 120.0:
			sfx.play_sfx("thud", 0.15, -4.0)
		if bool(settings["gore"]):
			blood.paint_floor_splat(pos.x, randf_range(12.0, 24.0)))
	deb.blood_drip.connect(func(pos: Vector2, vel: Vector2):
		_on_blood_spray(pos, vel, 2, false))
	debris_layer.add_child(deb)


func _on_blood_spray(world_pos: Vector2, impulse: Vector2, count: int, heavy: bool) -> void:
	if not bool(settings["gore"]):
		if heavy:
			_spawn_sparks(world_pos, 16)
		return
	for i in range(count):
		if particles_blood.size() > MAX_BLOOD_PARTICLES:
			break
		var spread := Vector2(randf_range(-210, 210), randf_range(-270, 90))
		var vel := impulse * randf_range(0.45, 1.25) + spread
		# Blood palette: dark venous burgundy -> arterial crimson -> near-black clot
		var tone := randf()
		var col := Color(0.28, 0.012, 0.025, 0.94) if tone < 0.35 else (Color(0.54, 0.028, 0.05, 0.92) if tone < 0.80 else Color(0.74, 0.055, 0.08, 0.90))
		particles_blood.append({
			"pos": world_pos,
			"prev_pos": world_pos - vel * 0.015,
			"vel": vel,
			"r": randf_range(1.6, 5.2 if heavy else 3.6),
			"col": col,
			"life": randf_range(0.65, 1.65),
		})
	if heavy:
		blood.paint_wall_splat(world_pos.x + randf_range(-34, 34), world_pos.y + randf_range(-34, 34), randf_range(12, 24))


func _spawn_sparks(world_pos: Vector2, count: int) -> void:
	for i in range(count):
		if particles_sparks.size() >= MAX_SPARKS:
			break
		var ang := randf_range(0.0, TAU)
		var spd := randf_range(180.0, 620.0)
		particles_sparks.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd + Vector2(0, -110.0),
			"life": randf_range(0.16, 0.38),
			"max_life": 0.38,
		})


func _on_cut_flash(world_pos: Vector2, label_text: String, col: Color) -> void:
	var pos := world_pos + Vector2(0, -25)
	# Stack fresh callouts instead of drawing them on top of each other.
	for c in callouts:
		var cp: Vector2 = c["pos"]
		if float(c["life"]) > 0.6 and absf(cp.x - pos.x) < 150.0 and absf(cp.y - pos.y) < 22.0:
			pos.y = cp.y - 24.0
	callouts.append({
		"pos": pos,
		"text": label_text,
		"color": col,
		"life": 1.1,
		"max_life": 1.1,
	})


func _on_sever_fx(world_pos: Vector2, cut_dir: Vector2) -> void:
	var dir_n := cut_dir.normalized() if cut_dir.length() > 0.1 else Vector2(1.0, -0.3).normalized()
	slash_flashes.append({
		"pos": world_pos,
		"dir": dir_n,
		"len": 165.0,
		"life": 0.24,
		"max_life": 0.24,
	})
	if not bool(settings["gore"]):
		_spawn_sparks(world_pos, 26)
		return

	blood_flash_alpha = 0.22
	arterial_jets.append({
		"pos": world_pos,
		"dir": Vector2(dir_n.x * 0.65, -0.85).normalized(),
		"life": 2.4,
		"pulse": 0.0,
		"emit_acc": 0.0,
	})
	for i in range(7):
		if particles_mist.size() >= MAX_MIST:
			break
		particles_mist.append({
			"pos": world_pos + Vector2(randf_range(-18, 18), randf_range(-18, 18)),
			"vel": dir_n * randf_range(35.0, 120.0) + Vector2(randf_range(-40, 40), randf_range(-70, 10)),
			"r": randf_range(16.0, 36.0),
			"life": randf_range(0.38, 0.78),
			"max_life": 0.78,
		})
	for i in range(10):
		if particles_chunks.size() >= MAX_CHUNKS:
			break
		var w := randf_range(5.0, 12.0)
		var h := randf_range(3.5, 8.0)
		var pts := PackedVector2Array([
			Vector2(-w * 0.55, -h * 0.35),
			Vector2(0.0, -h * 0.62),
			Vector2(w * 0.52, -h * 0.22),
			Vector2(w * 0.38, h * 0.55),
			Vector2(-w * 0.42, h * 0.48),
		])
		particles_chunks.append({
			"pos": world_pos,
			"vel": dir_n * randf_range(180.0, 440.0) + Vector2(randf_range(-160, 160), randf_range(-270, -40)),
			"poly": pts,
			"rot": randf_range(0.0, TAU),
			"ang_vel": randf_range(-13.0, 13.0),
			"life": randf_range(2.0, 3.8),
		})


func _step_particles(delta: float) -> void:
	blood_flash_alpha = maxf(0.0, blood_flash_alpha - 1.15 * delta)

	# Rhythmic arterial spurts
	for i in range(arterial_jets.size() - 1, -1, -1):
		var j: Dictionary = arterial_jets[i]
		j["life"] = float(j["life"]) - delta
		if float(j["life"]) <= 0.0:
			arterial_jets.remove_at(i)
			continue
		j["pulse"] = float(j["pulse"]) + delta * 18.0
		var beat := maxf(0.15, sin(float(j["pulse"])))
		j["emit_acc"] = float(j["emit_acc"]) + delta * (38.0 * beat)
		while float(j["emit_acc"]) >= 1.0:
			j["emit_acc"] = float(j["emit_acc"]) - 1.0
			if particles_blood.size() > MAX_BLOOD_PARTICLES:
				continue
			var jdir := Vector2(j["dir"]).rotated(randf_range(-0.28, 0.28))
			var spd := randf_range(260.0, 520.0) * (0.55 + 0.55 * beat)
			var jpos := Vector2(j["pos"]) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
			particles_blood.append({
				"pos": jpos,
				"prev_pos": jpos,
				"vel": jdir * spd,
				"r": randf_range(1.8, 3.8),
				"col": Color(0.68, 0.04, 0.07, 0.94) if beat > 0.6 else Color(0.36, 0.015, 0.03, 0.95),
				"life": randf_range(0.7, 1.3),
			})

	for i in range(particles_blood.size() - 1, -1, -1):
		var p: Dictionary = particles_blood[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			particles_blood.remove_at(i)
			continue
		var vel: Vector2 = p["vel"]
		vel.x *= maxf(0.0, 1.0 - 0.85 * delta)
		vel.y += 1020.0 * delta
		var old_pos: Vector2 = p["pos"]
		var pos := old_pos + vel * delta
		p["prev_pos"] = old_pos
		p["vel"] = vel
		p["pos"] = pos
		if pos.y >= FLOOR_Y:
			blood.paint_floor_splat(pos.x, float(p["r"]) * 2.8)
			particles_blood.remove_at(i)

	for i in range(particles_chunks.size() - 1, -1, -1):
		var ch: Dictionary = particles_chunks[i]
		ch["life"] = float(ch["life"]) - delta
		if float(ch["life"]) <= 0.0:
			particles_chunks.remove_at(i)
			continue
		var cvel: Vector2 = ch["vel"]
		cvel.y += 1080.0 * delta
		var cpos: Vector2 = Vector2(ch["pos"]) + cvel * delta
		ch["rot"] = float(ch["rot"]) + float(ch["ang_vel"]) * delta
		if cpos.y >= FLOOR_Y:
			cpos.y = FLOOR_Y
			if absf(cvel.y) > 80.0:
				blood.paint_floor_splat(cpos.x, 12.0)
				cvel.y = -absf(cvel.y) * 0.34
				cvel.x *= 0.68
			else:
				if absf(cvel.x) > 18.0 and randf() < 0.3:
					blood.paint_floor_splat(cpos.x, 6.0)
				cvel = Vector2(cvel.x * maxf(0.0, 1.0 - 7.5 * delta), 0.0)
				ch["ang_vel"] = 0.0
		ch["vel"] = cvel
		ch["pos"] = cpos

	for i in range(particles_mist.size() - 1, -1, -1):
		var m: Dictionary = particles_mist[i]
		m["life"] = float(m["life"]) - delta
		if float(m["life"]) <= 0.0:
			particles_mist.remove_at(i)
			continue
		m["pos"] = Vector2(m["pos"]) + Vector2(m["vel"]) * delta
		m["r"] = float(m["r"]) + 24.0 * delta

	for i in range(slash_flashes.size() - 1, -1, -1):
		var sf: Dictionary = slash_flashes[i]
		sf["life"] = float(sf["life"]) - delta
		if float(sf["life"]) <= 0.0:
			slash_flashes.remove_at(i)

	for i in range(particles_sparks.size() - 1, -1, -1):
		var s: Dictionary = particles_sparks[i]
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			particles_sparks.remove_at(i)
			continue
		var sv: Vector2 = s["vel"]
		sv.y += 650.0 * delta
		s["vel"] = sv
		s["pos"] = Vector2(s["pos"]) + sv * delta


func _step_bootprints(delta: float) -> void:
	if not bool(settings["gore"]):
		return
	for raw_f in [p1, p2]:
		var f := raw_f as FighterController
		if f == null or f.is_dead:
			continue
		if blood.floor_wetness_at(f.position.x) > 0.25:
			f.bloody_boots = 2.4
		if f.bloody_boots > 0.0:
			f.bloody_boots = maxf(0.0, f.bloody_boots - delta)
			var is_moving: bool = f.anim_player != null and f.anim_player.current_animation == "walk"
			if is_moving:
				f.bootprint_timer -= delta
				if f.bootprint_timer <= 0.0:
					f.bootprint_timer = 0.19
					blood.paint_bootprint(f.position.x + randf_range(-18, 18), clampf(f.bloody_boots * 0.22, 0.08, 0.42))


func _step_callouts(dt: float) -> void:
	for i in range(callouts.size() - 1, -1, -1):
		var c: Dictionary = callouts[i]
		c["life"] = float(c["life"]) - dt
		c["pos"] = Vector2(c["pos"]) + Vector2(0, -34.0 * dt)
		if float(c["life"]) <= 0.0:
			callouts.remove_at(i)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _init_candles() -> void:
	candles.clear()
	for cx in [160.0, 400.0, 640.0, 880.0, 1120.0]:
		candles.append({"x": cx, "y": 546.0, "phase": randf_range(0.0, TAU)})


## Static: drawn once (no per-frame queue_redraw).
func _draw_stage() -> void:
	# Full bleed dark velvet backdrop (covers camera shake / zoom-out margins)
	stage_layer.draw_rect(Rect2(-500, -300, 2280, 1300), Color(0.07, 0.03, 0.04, 1.0))

	# Velvet curtain folds
	for i in range(-5, 22):
		var fx := float(i) * 80.0
		var shade := 0.03 if i % 2 == 0 else 0.015
		stage_layer.draw_rect(Rect2(fx, -120, 80, 680), Color(0.11 + shade, 0.04 + shade * 0.4, 0.05 + shade * 0.5, 1.0))

	# Warm centre-stage spotlight
	stage_layer.draw_circle(Vector2(640, 420), 380.0, Color(0.95, 0.62, 0.28, 0.045))
	stage_layer.draw_circle(Vector2(640, 460), 220.0, Color(1.0, 0.72, 0.35, 0.04))

	# Side drapes
	stage_layer.draw_rect(Rect2(-400, -120, 468, 680), Color(0.16, 0.03, 0.05, 0.96))
	stage_layer.draw_rect(Rect2(1212, -120, 468, 680), Color(0.16, 0.03, 0.05, 0.96))

	# Timber stage floor & plank grain
	stage_layer.draw_rect(Rect2(-500, 560, 2280, 400), Color(0.17, 0.12, 0.09, 1.0))
	stage_layer.draw_rect(Rect2(-500, 558, 2280, 6), Color(0.38, 0.26, 0.14, 1.0))
	for k in range(6):
		var py := 566.0 + float(k) * 32.0
		stage_layer.draw_line(Vector2(-500, py), Vector2(1780, py), Color(0.09, 0.06, 0.04, 0.65), 2.0)


func _draw_candles() -> void:
	var now := Time.get_ticks_msec() * 0.008
	for c in candles:
		var cx := float(c["x"])
		var cy := float(c["y"])
		var ph := float(c["phase"])
		var flick := 0.85 + 0.18 * sin(now + ph) + 0.09 * cos(now * 2.1 + ph)
		candle_layer.draw_circle(Vector2(cx, cy - 12), 46.0 * flick, Color(1.0, 0.62, 0.22, 0.09))
		candle_layer.draw_circle(Vector2(cx, cy - 12), 20.0 * flick, Color(1.0, 0.78, 0.35, 0.16))
		candle_layer.draw_rect(Rect2(cx - 3, cy - 4, 6, 16), Color(0.84, 0.78, 0.66, 0.95))
		candle_layer.draw_circle(Vector2(cx, cy - 8), 3.6 * flick, Color(1.0, 0.86, 0.42, 0.98))


func _draw_fx() -> void:
	if blood_flash_alpha > 0.01:
		fx_layer.draw_rect(Rect2(-500, -300, 2280, 1300), Color(0.65, 0.02, 0.04, blood_flash_alpha))

	for m in particles_mist:
		var a := clampf(float(m["life"]) / float(m["max_life"]), 0.0, 1.0)
		fx_layer.draw_circle(Vector2(m["pos"]), float(m["r"]), Color(0.38, 0.015, 0.03, 0.28 * a))

	for ch in particles_chunks:
		var cpos: Vector2 = ch["pos"]
		var a := clampf(float(ch["life"]), 0.0, 1.0)
		fx_layer.draw_set_transform(cpos, float(ch["rot"]))
		var poly: PackedVector2Array = ch["poly"]
		fx_layer.draw_colored_polygon(poly, Color(0.36, 0.02, 0.035, a))
		fx_layer.draw_circle(Vector2(1.0, -1.0), 1.8, Color(0.84, 0.72, 0.62, 0.65 * a))
		fx_layer.draw_set_transform(Vector2.ZERO, 0.0)

	for b in particles_blood:
		var bpos: Vector2 = b["pos"]
		var prev: Vector2 = b["prev_pos"]
		var br := float(b["r"])
		var col: Color = b["col"]
		var stretch := bpos - prev
		if stretch.length_squared() > 4.0:
			var tail := bpos - stretch.limit_length(22.0)
			fx_layer.draw_line(tail, bpos, Color(col.r, col.g, col.b, col.a * 0.72), maxf(1.2, br * 1.15), true)
		fx_layer.draw_circle(bpos, br, col)
		if br >= 3.2:
			fx_layer.draw_circle(bpos + Vector2(-0.6, -0.6), br * 0.32, Color(0.92, 0.42, 0.45, 0.45))

	for sf in slash_flashes:
		var spos: Vector2 = sf["pos"]
		var sdir: Vector2 = sf["dir"]
		var slen := float(sf["len"])
		var a := clampf(float(sf["life"]) / float(sf["max_life"]), 0.0, 1.0)
		fx_layer.draw_line(spos - sdir * slen * 0.5, spos + sdir * slen * 0.5, Color(0.95, 0.12, 0.16, 0.85 * a), 8.0 * a, true)
		fx_layer.draw_line(spos - sdir * slen * 0.42, spos + sdir * slen * 0.42, Color(1.0, 0.96, 0.88, a), 3.0 * a, true)

	for sp in particles_sparks:
		var spos: Vector2 = sp["pos"]
		var svel: Vector2 = sp["vel"]
		var frac := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		fx_layer.draw_line(spos, spos - svel * 0.025, Color(1.0, 0.85, 0.35, frac), 2.2, true)

	var font := ThemeDB.fallback_font
	if font != null:
		for c in callouts:
			var a := clampf(float(c["life"]) / float(c["max_life"]), 0.0, 1.0)
			var col: Color = c["color"]
			col.a = a
			fx_layer.draw_string(font, Vector2(c["pos"]) - Vector2(70, 0), String(c["text"]), HORIZONTAL_ALIGNMENT_CENTER, 160, 18, col)


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _refresh_hud() -> void:
	if ui == null or p1 == null or p2 == null:
		return
	var center := ""
	var timer_text := ""
	if phase == Phase.TITLE:
		center = "STRINGS & STEEL"
	elif match_mode == "gauntlet":
		center = "WAVE %d   ·   BEST %d" % [gauntlet_wave, best_wave]
	else:
		center = "%s  ROUND %d  %s" % [_pips(wins_p1), round_num, _pips(wins_p2)]
		timer_text = str(ceili(maxf(0.0, round_time_left)))
	if phase != Phase.TITLE and bool(settings["one_hit_sever"]):
		center += "   ·   1-HIT SEVER"
	ui.update_hud(p1, p2, _format_limbs(p1), _format_limbs(p2), center, timer_text)


func _pips(wins: int) -> String:
	var s := ""
	for i in range(ROUNDS_TO_WIN):
		s += "●" if i < wins else "○"
	return s


func _format_limbs(f: FighterController) -> String:
	var tags: Array[String] = []
	for item in [["head", "HEAD"], ["arm_r", "SWD-ARM"], ["forearm_r", "FORE"], ["arm_l", "OFF-ARM"], ["thigh_l", "L-LEG"], ["thigh_r", "R-LEG"]]:
		var s: String = item[0]
		var lbl: String = item[1]
		tags.append("[X %s]" % lbl if f.severed.get(s, false) else lbl)
	return "  ".join(tags)
