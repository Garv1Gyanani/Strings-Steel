extends Node2D

## Main Strings & Steel Arena Combat & Theater Stage Controller.
## Features:
## - Segment-to-segment blade clash & directional parry + perfect parry recoil
## - Multi-level dismemberment with dangling marionette debris & arterial stumps
## - Persistent dynamic ImageTexture floor puddles & velvet backdrop blood splatters
## - Dramatic slow-motion KO zoom, screen shake, floating callouts & procedural SoundFX
## - 1v1 Duel + Endless Gauntlet + reactive AI + On-screen mobile touch controls

@onready var cam: Camera2D = $Camera2D
@onready var p1: FighterController = $Landsknecht
@onready var p2: FighterController = $Fechtmeister

const FIGHTER_ROSTER := [
	{"id": "landsknecht", "name": "LANDSKNECHT", "scene": "res://scenes/fighters/Landsknecht.tscn"},
	{"id": "fechtmeister", "name": "FECHTMEISTER", "scene": "res://scenes/fighters/Fechtmeister.tscn"},
	{"id": "plague_executioner", "name": "PLAGUE EXECUTIONER", "scene": "res://scenes/fighters/PlagueExecutioner.tscn"},
	{"id": "black_knight", "name": "BLACK KNIGHT", "scene": "res://scenes/fighters/BlackKnight.tscn"},
	{"id": "venetian_bravo", "name": "VENETIAN BRAVO", "scene": "res://scenes/fighters/VenetianBravo.tscn"},
]
var p1_roster_idx: int = 0
var p2_roster_idx: int = 1
var p1_title_btn: Button
var p2_title_btn: Button

# Theater & FX Layers
var floor_blood_img: Image
var floor_blood_tex: ImageTexture
var floor_blood_sp: Sprite2D

var wall_blood_img: Image
var wall_blood_tex: ImageTexture
var wall_blood_sp: Sprite2D

var sfx: SoundFX
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

# Game & Mode State
var game_mode: String = "duel" # "duel" | "gauntlet"
var ai_difficulty: String = "hard" # "normal" | "hard" | "brutal"
var one_hit_sever: bool = false
var gore_enabled: bool = true
var show_strings: bool = true
var show_touch_controls: bool = false

var score_p1: int = 0
var score_p2: int = 0
var gauntlet_wave: int = 1
var round_over: bool = false
var slow_mo_timer: float = 0.0
var hitstop_timer: float = 0.0
var shake_mag: float = 0.0
var cam_zoom_target: float = 1.0
var cam_focus: Vector2 = Vector2(640, 360)

var ai_think_timer: float = 0.25
var ai_desired_dist: float = 205.0
var ai_move_dir: float = 0.0
var ai_attack_cd: float = 0.6
var ai_parry_timer: float = 0.0
var _last_clash_serial: Dictionary = {}

# UI References built cleanly in _build_hud()
var ui_layer: CanvasLayer
var p1_hp_bar: ProgressBar
var p1_stam_bar: ProgressBar
var p2_hp_bar: ProgressBar
var p2_stam_bar: ProgressBar
var p1_limb_lbl: Label
var p2_limb_lbl: Label
var center_lbl: Label
var hint_lbl: Label
var next_fight_btn: Button
var touch_root: Control


func _ready() -> void:
	sfx = SoundFX.new()
	add_child(sfx)

	stage_layer = Node2D.new()
	stage_layer.name = "StageLayer"
	stage_layer.z_index = -35
	stage_layer.draw.connect(_draw_stage)
	add_child(stage_layer)

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

	_init_blood_canvases()
	_init_candles()
	_build_hud()
	Input.joy_connection_changed.connect(func(_id: int, _conn: bool): _update_hint_text())
	_update_hint_text()
	_wire_fighter(p1, true)
	_wire_fighter(p2, false)
	reset_round()


func _wire_fighter(f: FighterController, is_p1: bool) -> void:
	if f == null:
		return
	f.is_player = is_p1
	f.gore_enabled = gore_enabled
	f.show_strings = show_strings
	f.request_spawn_debris.connect(_on_spawn_debris)
	f.request_blood_spray.connect(_on_blood_spray)
	f.request_sfx.connect(func(k: String, j: float): sfx.play_sfx(k, j))
	f.request_cut_flash.connect(_on_cut_flash)
	f.request_sever_fx.connect(_on_sever_fx)
	f.limb_state_changed.connect(func(_who): _refresh_hud())


func _swap_fighter(is_p1: bool, new_idx: int) -> void:
	var count: int = FIGHTER_ROSTER.size()
	var idx: int = ((new_idx % count) + count) % count
	var entry: Dictionary = FIGHTER_ROSTER[idx]
	var scene_path: String = entry["scene"]
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var new_f := ps.instantiate() as FighterController
	if new_f == null:
		return

	var cur_aim: bool = p1.cursor_aim_enabled if p1 != null else true
	if is_p1:
		p1_roster_idx = idx
		if p1 != null:
			p1.queue_free()
		p1 = new_f
		p1.cursor_aim_enabled = cur_aim
		add_child(p1)
		_wire_fighter(p1, true)
		if p1_title_btn != null:
			p1_title_btn.text = "YOU: %s [C]" % String(entry["name"])
	else:
		p2_roster_idx = idx
		if p2 != null:
			p2.queue_free()
		p2 = new_f
		add_child(p2)
		_wire_fighter(p2, false)
		if p2_title_btn != null:
			p2_title_btn.text = "RIVAL: %s [V]" % String(entry["name"])

	reset_round()


func _init_blood_canvases() -> void:
	wall_blood_img = Image.create(1280, 560, false, Image.FORMAT_RGBA8)
	wall_blood_img.fill(Color(0, 0, 0, 0))
	wall_blood_tex = ImageTexture.create_from_image(wall_blood_img)
	wall_blood_sp = Sprite2D.new()
	wall_blood_sp.texture = wall_blood_tex
	wall_blood_sp.centered = false
	wall_blood_sp.position = Vector2(0, 0)
	wall_blood_sp.z_index = -25
	add_child(wall_blood_sp)

	floor_blood_img = Image.create(1280, 160, false, Image.FORMAT_RGBA8)
	floor_blood_img.fill(Color(0, 0, 0, 0))
	floor_blood_tex = ImageTexture.create_from_image(floor_blood_img)
	floor_blood_sp = Sprite2D.new()
	floor_blood_sp.texture = floor_blood_tex
	floor_blood_sp.centered = false
	floor_blood_sp.position = Vector2(0, 560)
	floor_blood_sp.z_index = -15
	add_child(floor_blood_sp)


func _clear_blood_canvases() -> void:
	if wall_blood_img != null:
		wall_blood_img.fill(Color(0, 0, 0, 0))
		wall_blood_tex.update(wall_blood_img)
	if floor_blood_img != null:
		floor_blood_img.fill(Color(0, 0, 0, 0))
		floor_blood_tex.update(floor_blood_img)


func _init_candles() -> void:
	candles.clear()
	for cx in [160.0, 400.0, 640.0, 880.0, 1120.0]:
		candles.append({"x": cx, "y": 546.0, "phase": randf_range(0.0, TAU)})


func reset_round() -> void:
	round_over = false
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
	_clear_blood_canvases()

	for c in debris_layer.get_children():
		c.queue_free()

	if p1 != null:
		p1.position = Vector2(440, 445)
		p1.gore_enabled = gore_enabled
		p1.show_strings = show_strings
		p1.reset_fighter()
		p1.set_facing(1)
	if p2 != null:
		p2.position = Vector2(840, 445)
		p2.gore_enabled = gore_enabled
		p2.show_strings = show_strings
		p2.max_hp = 100.0 + (float(gauntlet_wave - 1) * 15.0 if game_mode == "gauntlet" else 0.0)
		p2.reset_fighter()
		p2.set_facing(-1)

	if next_fight_btn != null:
		next_fight_btn.visible = false
	_refresh_hud()


func _process(delta: float) -> void:
	var unscaled_dt := delta / maxf(0.05, Engine.time_scale)

	# Hitstop / Slow-Motion Controller
	if hitstop_timer > 0.0:
		hitstop_timer -= unscaled_dt
		Engine.time_scale = 0.06
	elif slow_mo_timer > 0.0:
		slow_mo_timer -= unscaled_dt
		Engine.time_scale = 0.24
	else:
		Engine.time_scale = lerpf(Engine.time_scale, 1.0, minf(1.0, 10.0 * unscaled_dt))

	# Dynamic Camera Zoom & Screen Shake
	if p1 != null and p2 != null:
		var mid := (p1.position + p2.position) * 0.5 + Vector2(0, -105)
		var sep := absf(p1.position.x - p2.position.x)
		var base_zoom := clampf(lerpf(1.16, 0.94, sep / 700.0), 0.92, 1.22)
		if round_over or slow_mo_timer > 0.0:
			cam_zoom_target = 1.38
			var winner_or_loser := p2 if (p2 != null and p2.is_dead) else p1
			cam_focus = cam_focus.lerp(winner_or_loser.position + Vector2(0, -110), minf(1.0, 6.0 * unscaled_dt))
		else:
			cam_zoom_target = base_zoom
			cam_focus = cam_focus.lerp(Vector2(clampf(mid.x, 420.0, 860.0), clampf(mid.y, 280.0, 380.0)), minf(1.0, 6.0 * unscaled_dt))

		if cam != null:
			cam.zoom = cam.zoom.lerp(Vector2(cam_zoom_target, cam_zoom_target), minf(1.0, 5.5 * unscaled_dt))
			var jitter := Vector2(randf_range(-shake_mag, shake_mag), randf_range(-shake_mag, shake_mag))
			cam.position = cam_focus + jitter
		shake_mag = maxf(0.0, shake_mag - 42.0 * unscaled_dt)

		# Auto-face while alive
		var dir := 1 if p2.position.x >= p1.position.x else -1
		if not p1.is_dead:
			p1.set_facing(dir)
		if not p2.is_dead:
			p2.set_facing(-dir)

		if not round_over:
			_step_ai(delta)
			_resolve_combat()

			if p1.is_dead or p2.is_dead:
				_trigger_round_over()

	_step_particles(delta)
	_step_bootprints(delta)
	_step_callouts(unscaled_dt)
	_refresh_hud()
	if stage_layer != null: stage_layer.queue_redraw()
	if candle_layer != null: candle_layer.queue_redraw()
	if fx_layer != null: fx_layer.queue_redraw()


func _step_ai(delta: float) -> void:
	if p2 == null or p1 == null or p2.is_dead:
		return
	var dist := absf(p1.position.x - p2.position.x)
	var dir_to_p1 := 1.0 if p1.position.x > p2.position.x else -1.0

	ai_attack_cd = maxf(0.0, ai_attack_cd - delta)
	ai_parry_timer = maxf(0.0, ai_parry_timer - delta)
	ai_think_timer -= delta

	var brutal := ai_difficulty == "brutal"
	var hard := ai_difficulty == "hard" or brutal

	# 1. Tactical backdash or directional parry when player winds up in range
	if p1.current_action in ["slash_high", "slash_low", "thrust"] and dist < 260.0 and p2.current_action == "":
		if p1.current_action == "thrust" and dist < 175.0 and p2.dash_cooldown <= 0.0 and hard and randf() < 0.48:
			p2.start_dash(-dir_to_p1)
			ai_attack_cd = 0.22
			return
		elif ai_parry_timer <= 0.0:
			var chance := 0.85 if brutal else (0.66 if hard else 0.40)
			if randf() < chance * delta * 18.0:
				ai_parry_timer = 0.30 if brutal else 0.40
				p2.guard_zone = "low" if p1.current_action == "slash_low" else "high"

	if ai_parry_timer > 0.0 and p2.current_action == "" and p2.has_weapon:
		if not p2.parrying:
			p2.parry_hold_time = 0.0
		else:
			p2.parry_hold_time += delta
		p2.parrying = true
		p2.play_anim("parry_low" if p2.guard_zone == "low" else "parry", 0.05)
		return
	else:
		p2.parrying = false
		p2.parry_hold_time = 99.0

	# 2. Punish player guard-turtling with push kick -> heavy follow-up
	if p1.parrying and p1.parry_hold_time > 0.34 and dist < 185.0 and p2.current_action == "" and hard:
		p2.start_attack("kick")
		ai_attack_cd = 0.28
		return

	# 3. Punish player recovery / stagger immediately
	if (p1.current_action in ["hurt", "parry_recoil"] or p1.stamina < 16.0) and dist < 240.0 and p2.current_action == "" and ai_attack_cd <= 0.15 and hard:
		p2.start_attack("thrust" if dist > 180.0 else "slash_high")
		ai_attack_cd = 0.45 if brutal else 0.65
		return

	if ai_think_timer <= 0.0:
		ai_think_timer = randf_range(0.11, 0.26) if brutal else (randf_range(0.16, 0.34) if hard else randf_range(0.24, 0.48))
		ai_desired_dist = randf_range(165.0, 215.0)
		if dist > ai_desired_dist + 22.0:
			ai_move_dir = dir_to_p1
		elif dist < ai_desired_dist - 42.0:
			ai_move_dir = -dir_to_p1
		else:
			ai_move_dir = dir_to_p1 * 0.45 if randf() < 0.5 else 0.0

		if dist < 235.0 and ai_attack_cd <= 0.0 and p2.current_action == "":
			var roll := randf()
			if roll < 0.36:
				p2.start_attack("slash_high")
			elif roll < 0.66:
				p2.start_attack("slash_low")
			elif roll < 0.88:
				p2.start_attack("thrust")
			else:
				p2.start_attack("kick")
			ai_attack_cd = randf_range(0.36, 0.72) if brutal else (randf_range(0.52, 0.96) if hard else randf_range(0.80, 1.35))

	if p2.current_action == "":
		if absf(ai_move_dir) > 0.1:
			var spd_mult := 1.04 if brutal else (0.96 if hard else 0.85)
			p2.position.x = clampf(p2.position.x + ai_move_dir * p2.move_speed * spd_mult * delta, 120.0, 1160.0)
			p2.play_anim("walk", 0.08)
		else:
			p2.play_anim("idle", 0.1)


func _resolve_combat() -> void:
	# 1. Check Blade vs Blade Clash / Parry
	var b1 := p1.get_blade_segment()
	var b2 := p2.get_blade_segment()
	if b1.size() == 2 and b2.size() == 2:
		var clash_info := _closest_segments(b1[0], b1[1], b2[0], b2[1])
		if clash_info["dist"] < 26.0:
			_handle_blade_clash(p1, p2, clash_info["pt"])
			_handle_blade_clash(p2, p1, clash_info["pt"])

	# 2. Check Kick Knockbacks
	_check_kick(p1, p2)
	_check_kick(p2, p1)

	# 3. Check Blade vs Body Capsules
	_check_blade_vs_body(p1, p2)
	_check_blade_vs_body(p2, p1)

	# 4. Check Blade vs Dangling Marionette Ropes
	_check_debris_rope_cut(p1)
	_check_debris_rope_cut(p2)


func _handle_blade_clash(atk: FighterController, def: FighterController, pt: Vector2) -> void:
	if not atk.is_blade_active():
		return
	var key := "%s:%d" % [atk.name, atk.attack_serial]
	if _last_clash_serial.has(key):
		return
	var passive_cursor_guard: bool = def.is_player and def.cursor_aim_enabled and def.has_weapon and def.current_action == ""
	if not (def.parrying or def.is_blade_active() or passive_cursor_guard):
		return

	_last_clash_serial[key] = true
	atk.hit_registered_serial = atk.attack_serial
	hitstop_timer = 0.065
	shake_mag = maxf(shake_mag, 12.0)
	_spawn_sparks(pt, 24)

	if def.is_perfect_parry():
		sfx.play_sfx("perfect_parry", 0.06, 2.0)
		_rumble(0.75, 0.90, 0.22)
		atk.trigger_hurt(true)
		atk.knockback_vx = -float(atk.facing) * 320.0
		_spawn_sparks(pt, 36)
		_on_cut_flash(pt, "PERFECT PARRY!", Color(1.0, 0.88, 0.35))
	else:
		sfx.play_sfx("clang", 0.12)
		_rumble(0.45, 0.35, 0.12)
		atk.knockback_vx = -float(atk.facing) * 140.0
		def.knockback_vx = -float(def.facing) * 110.0
		def.stamina = maxf(0.0, def.stamina - 14.0)
		_on_cut_flash(pt, "CLANG!", Color(0.95, 0.92, 0.72))


func _check_kick(atk: FighterController, def: FighterController) -> void:
	if not atk.is_kick_active() or def.is_dead:
		return
	var key := "kick:%s:%d" % [atk.name, atk.attack_serial]
	if _last_clash_serial.has(key):
		return
	if atk.bone_boot_r == null:
		return
	var foot_pt := atk.bone_boot_r.global_position
	if foot_pt.distance_to(def.position + Vector2(0, -100)) < 110.0:
		_last_clash_serial[key] = true
		sfx.play_sfx("thud", 0.15)
		def.knockback_vx = float(atk.facing) * 420.0
		def.stamina = maxf(0.0, def.stamina - 22.0)
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

	# When the sword is simply held in position (not actively swinging) and enemy walks onto the point,
	# apply a gentle physical spacing pushback without dealing fake slash damage or stagger!
	if not atk.is_blade_active():
		var torso_pt := def.position + Vector2(0, -105.0)
		var passive_info := _closest_segments(blade[0], blade[1], torso_pt, torso_pt + Vector2(0, -45.0))
		if float(passive_info["dist"]) < 22.0 and absf(def.knockback_vx) < 40.0:
			def.knockback_vx = float(atk.facing) * 65.0
		return

	if atk.hit_registered_serial == atk.attack_serial:
		return

	var segs := def.get_body_segments()
	var best_slot := ""
	var best_dist := 9999.0
	var best_pt := Vector2.ZERO
	for s in segs:
		var slot: String = s[0]
		var info := _closest_segments(blade[0], blade[1], s[1], s[2])
		var d: float = info["dist"] - float(s[3])
		if d < 0.0 and d < best_dist:
			best_dist = d
			best_slot = slot
			best_pt = info["pt"]

	if best_slot == "":
		return

	atk.hit_registered_serial = atk.attack_serial
	var pwr := atk.get_strike_power()
	var swing_dir := Vector2(float(atk.facing), -0.35 if atk.current_action == "slash_low" else 0.25).normalized()
	if atk.current_action == "" and atk._cursor_last_dir.length() > 0.1:
		swing_dir = Vector2(float(atk.facing) * absf(atk._cursor_last_dir.x) if absf(atk._cursor_last_dir.x) > 0.2 else float(atk.facing), atk._cursor_last_dir.y).normalized()
	var attacker_heavy := pwr >= 0.72
	var dmg := 24.0 if atk.current_action == "thrust" else 20.0
	var did_sever := def.apply_blade_damage(best_slot, dmg, best_pt, swing_dir, one_hit_sever, attacker_heavy, pwr)
	atk.blade_blood = minf(1.0, atk.blade_blood + (0.65 if did_sever else 0.24 * pwr))

	# Metallic sparks when striking armored steel/brigandine
	if (def.fighter_id in ["fechtmeister", "black_knight", "plague_executioner"]) and (best_slot in ["torso", "head", "shin_r", "shin_l"]):
		_spawn_sparks(best_pt, maxi(4, int(10.0 * pwr)))
		sfx.play_sfx("clang", 0.2, -5.0)

	if did_sever or pwr >= 0.68:
		hitstop_timer = 0.105 if did_sever else 0.042
		shake_mag = maxf(shake_mag, 22.0 if did_sever else 9.0)
		_rumble(0.85 if did_sever else 0.35, 0.95 if did_sever else 0.25, 0.26 if did_sever else 0.10)
	if did_sever:
		slow_mo_timer = maxf(slow_mo_timer, 0.95)


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


func _trigger_round_over() -> void:
	round_over = true
	slow_mo_timer = 1.65
	sfx.play_sfx("ko_boom", 0.05)
	if p2.is_dead:
		score_p1 += 1
		if game_mode == "gauntlet":
			gauntlet_wave += 1
			if next_fight_btn != null:
				next_fight_btn.text = "NEXT CHALLENGER — WAVE %d (R)" % gauntlet_wave
		elif next_fight_btn != null:
			next_fight_btn.text = "FIGHT AGAIN (R)"
	else:
		score_p2 += 1
		if next_fight_btn != null:
			next_fight_btn.text = "RETRY DUEL (R)"
	if next_fight_btn != null:
		next_fight_btn.visible = true


func _on_spawn_debris(deb: PhysicsDebris) -> void:
	deb.floor_bounced.connect(func(pos: Vector2, spd: float):
		if spd > 120.0:
			sfx.play_sfx("thud", 0.15, -4.0)
		if gore_enabled:
			_paint_floor_splat(pos.x, randf_range(12.0, 24.0)))
	deb.blood_drip.connect(func(pos: Vector2, vel: Vector2):
		_on_blood_spray(pos, vel, 2, false))
	debris_layer.add_child(deb)


func _on_blood_spray(world_pos: Vector2, impulse: Vector2, count: int, heavy: bool) -> void:
	if not gore_enabled:
		if heavy:
			_spawn_sparks(world_pos, 16)
		return
	for i in range(count):
		if particles_blood.size() > 340:
			break
		var spread := Vector2(randf_range(-210, 210), randf_range(-270, 90))
		var vel := impulse * randf_range(0.45, 1.25) + spread
		# Realistic blood palette: dark venous burgundy -> arterial crimson -> near-black clot core
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
		_paint_wall_splat(world_pos.x + randf_range(-34, 34), world_pos.y + randf_range(-34, 34), randf_range(12, 24))


func _spawn_sparks(world_pos: Vector2, count: int) -> void:
	for i in range(count):
		var ang := randf_range(0.0, TAU)
		var spd := randf_range(180.0, 620.0)
		particles_sparks.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd + Vector2(0, -110.0),
			"life": randf_range(0.16, 0.38),
			"max_life": 0.38,
		})


func _on_cut_flash(world_pos: Vector2, label_text: String, col: Color) -> void:
	callouts.append({
		"pos": world_pos + Vector2(0, -25),
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
	if not gore_enabled:
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
		particles_mist.append({
			"pos": world_pos + Vector2(randf_range(-18, 18), randf_range(-18, 18)),
			"vel": dir_n * randf_range(35.0, 120.0) + Vector2(randf_range(-40, 40), randf_range(-70, 10)),
			"r": randf_range(16.0, 36.0),
			"life": randf_range(0.38, 0.78),
			"max_life": 0.78,
		})
	for i in range(10):
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
	var dirty_floor := false

	# Rhythmic systolic arterial spurts
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
			var jdir := Vector2(j["dir"]).rotated(randf_range(-0.28, 0.28))
			var spd := randf_range(260.0, 520.0) * (0.55 + 0.55 * beat)
			var jpos := Vector2(j["pos"]) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
			var jvel := jdir * spd
			particles_blood.append({
				"pos": jpos,
				"prev_pos": jpos,
				"vel": jvel,
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
		if pos.y >= 562.0:
			_paint_floor_splat_raw(pos.x, float(p["r"]) * 2.8)
			dirty_floor = true
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
		if cpos.y >= 562.0:
			cpos.y = 562.0
			if absf(cvel.y) > 80.0:
				_paint_floor_splat_raw(cpos.x, 12.0)
				dirty_floor = true
				cvel.y = -absf(cvel.y) * 0.34
				cvel.x *= 0.68
			else:
				if absf(cvel.x) > 18.0:
					_paint_floor_splat_raw(cpos.x, 6.0)
					dirty_floor = true
				cvel = Vector2(cvel.x * maxf(0.0, 1.0 - 7.5 * delta), 0.0)
				ch["ang_vel"] = 0.0
		ch["vel"] = cvel
		ch["pos"] = cpos

	if dirty_floor:
		floor_blood_tex.update(floor_blood_img)

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
	if not gore_enabled or floor_blood_img == null:
		return
	var dirty := false
	for raw_f in [p1, p2]:
		var f := raw_f as FighterController
		if f == null or f.is_dead:
			continue
		var px := clampi(int(f.position.x), 4, 1275)
		if floor_blood_img.get_pixel(px, 14).a > 0.25 or floor_blood_img.get_pixel(px, 22).a > 0.25:
			f.bloody_boots = 2.4
		if f.bloody_boots > 0.0:
			f.bloody_boots = maxf(0.0, f.bloody_boots - delta)
			var is_moving: bool = f.anim_player != null and f.anim_player.current_animation == "walk"
			if is_moving:
				f.bootprint_timer -= delta
				if f.bootprint_timer <= 0.0:
					f.bootprint_timer = 0.19
					var foot_x := clampi(int(f.position.x + randf_range(-18, 18)), 4, 1274)
					var foot_y := randi_range(12, 26)
					var alpha := clampf(f.bloody_boots * 0.22, 0.08, 0.42)
					for dx in range(-4, 5):
						for dy in range(-1, 2):
							_blend_px(floor_blood_img, clampi(foot_x + dx, 0, 1279), clampi(foot_y + dy, 0, 159), Color(0.36, 0.015, 0.03, alpha))
					dirty = true
	if dirty:
		floor_blood_tex.update(floor_blood_img)


func _step_callouts(dt: float) -> void:
	for i in range(callouts.size() - 1, -1, -1):
		var c: Dictionary = callouts[i]
		c["life"] = float(c["life"]) - dt
		c["pos"] = Vector2(c["pos"]) + Vector2(0, -34.0 * dt)
		if float(c["life"]) <= 0.0:
			callouts.remove_at(i)


func _blend_px(img: Image, x: int, y: int, src: Color) -> void:
	var dst := img.get_pixel(x, y)
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a < 0.001:
		return
	var out_rgb := (src * src.a + dst * dst.a * (1.0 - src.a)) / out_a
	out_rgb.a = minf(0.96, out_a)
	img.set_pixel(x, y, out_rgb)


func _paint_floor_splat(wx: float, rad: float) -> void:
	_paint_floor_splat_raw(wx, rad)
	floor_blood_tex.update(floor_blood_img)


func _paint_floor_splat_raw(wx: float, rad: float) -> void:
	var cx := clampi(int(wx), 4, 1275)
	var cy := randi_range(6, 38)
	var rx := clampi(int(rad * randf_range(1.4, 2.4)), 4, 32)
	var ry := clampi(int(rad * 0.42), 2, 11)
	var base_col := Color(0.28, 0.012, 0.025, 0.62) if randf() < 0.5 else Color(0.46, 0.024, 0.045, 0.56)
	for dy in range(-ry, ry + 1):
		var py := cy + dy
		if py < 0 or py >= 160:
			continue
		for dx in range(-rx, rx + 1):
			var px := cx + dx
			if px < 0 or px >= 1280:
				continue
			var norm_d := float(dx * dx) / float(rx * rx) + float(dy * dy) / float(ry * ry)
			if norm_d <= 1.0:
				var edge_fade := clampf((1.0 - norm_d) * 1.4, 0.15, 1.0)
				var px_col := base_col
				px_col.a *= edge_fade
				_blend_px(floor_blood_img, px, py, px_col)
	# Subtle candle-lit wet specular gleam on larger puddles
	if rx >= 12 and randf() < 0.45:
		var sx := clampi(cx + randi_range(-rx / 3, rx / 3), 2, 1277)
		_blend_px(floor_blood_img, sx, cy, Color(0.88, 0.34, 0.38, 0.42))
		_blend_px(floor_blood_img, sx + 1, cy, Color(0.88, 0.34, 0.38, 0.28))


func _paint_wall_splat(wx: float, wy: float, rad: float) -> void:
	var cx := clampi(int(wx), 8, 1270)
	var cy := clampi(int(wy), 8, 540)
	var r := clampi(int(rad), 5, 26)
	var col := Color(0.32, 0.015, 0.03, 0.44)
	for dy in range(-r, r + 1):
		var py := cy + dy
		if py < 0 or py >= 560:
			continue
		for dx in range(-r, r + 1):
			var px := cx + dx
			if px < 0 or px >= 1280:
				continue
			var d2 := float(dx * dx + dy * dy) / float(r * r)
			if d2 <= 1.0:
				var c := col
				c.a *= (1.0 - d2 * 0.7)
				_blend_px(wall_blood_img, px, py, c)
	# Fine mist spray satellites around impact
	for _s in range(14):
		var sx := clampi(cx + randi_range(-r * 2, r * 2), 2, 1277)
		var sy := clampi(cy + randi_range(-r * 2, r * 2), 2, 557)
		_blend_px(wall_blood_img, sx, sy, Color(0.45, 0.02, 0.04, 0.45))
	# Long vertical tapered gravity blood runs down the velvet backdrop
	for _run in range(randi_range(2, 4)):
		var rx := clampi(cx + randi_range(-r / 2, r / 2), 2, 1277)
		var run_len := randi_range(45, 130)
		for step_y in range(run_len):
			var py := cy + step_y
			if py >= 560:
				break
			var a := 0.42 * (1.0 - float(step_y) / float(run_len))
			_blend_px(wall_blood_img, rx, py, Color(0.30, 0.012, 0.025, a))
	wall_blood_tex.update(wall_blood_img)


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
	var pad_btn := event as InputEventJoypadButton
	if pad_btn != null and pad_btn.pressed:
		if pad_btn.button_index == JOY_BUTTON_START or pad_btn.button_index == JOY_BUTTON_BACK:
			reset_round()
			return
		elif round_over and pad_btn.button_index == JOY_BUTTON_A:
			reset_round()
			return

	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_R:
		if round_over and game_mode == "gauntlet" and p2 != null and p2.is_dead:
			_swap_fighter(false, p2_roster_idx + 1)
		else:
			reset_round()
	elif key_event.keycode == KEY_C:
		_swap_fighter(true, p1_roster_idx + 1)
	elif key_event.keycode == KEY_V or key_event.keycode == KEY_TAB:
		_swap_fighter(false, p2_roster_idx + 1)
	elif key_event.keycode == KEY_1:
		_swap_fighter(true, 0)
	elif key_event.keycode == KEY_2:
		_swap_fighter(true, 1)
	elif key_event.keycode == KEY_3:
		_swap_fighter(true, 2)
	elif key_event.keycode == KEY_4:
		_swap_fighter(true, 3)
	elif key_event.keycode == KEY_5:
		_swap_fighter(true, 4)
	elif key_event.keycode == KEY_ESCAPE and next_fight_btn != null:
		reset_round()


func _draw_stage() -> void:
	# Full bleed dark velvet backdrop (covers any camera shake / zoom-out margins)
	stage_layer.draw_rect(Rect2(-500, -300, 2280, 1300), Color(0.07, 0.03, 0.04, 1.0))

	# Theater velvet curtain vertical folds across wide stage wall
	for i in range(-5, 22):
		var fx := float(i) * 80.0
		var shade := 0.03 if i % 2 == 0 else 0.015
		stage_layer.draw_rect(Rect2(fx, -120, 80, 680), Color(0.11 + shade, 0.04 + shade * 0.4, 0.05 + shade * 0.5, 1.0))

	# Warm center-stage theater spotlight glow
	stage_layer.draw_circle(Vector2(640, 420), 380.0, Color(0.95, 0.62, 0.28, 0.045))
	stage_layer.draw_circle(Vector2(640, 460), 220.0, Color(1.0, 0.72, 0.35, 0.04))

	# Side framing drapes & gilded wood proscenium trim
	stage_layer.draw_rect(Rect2(-400, -120, 468, 680), Color(0.16, 0.03, 0.05, 0.96))
	stage_layer.draw_rect(Rect2(1212, -120, 468, 680), Color(0.16, 0.03, 0.05, 0.96))

	# Wide timber stage floor & plank grain
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


func _make_medieval_box(bg_col: Color, border_col: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _build_hud() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var top_panel := PanelContainer.new()
	top_panel.position = Vector2(20, 10)
	top_panel.size = Vector2(1240, 92)
	top_panel.add_theme_stylebox_override("panel", _make_medieval_box(Color(0.07, 0.04, 0.05, 0.88), Color(0.68, 0.52, 0.24, 0.85), 10))
	ui_layer.add_child(top_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	top_panel.add_child(hbox)

	# Player 1 Card
	var p1_box := VBoxContainer.new()
	p1_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p1_box)
	p1_title_btn = _make_toggle_btn("YOU: LANDSKNECHT [C]", func(_b: Button):
		_swap_fighter(true, p1_roster_idx + 1))
	p1_box.add_child(p1_title_btn)
	p1_hp_bar = _make_bar(Color(0.28, 0.56, 0.96), 14.0)
	p1_box.add_child(p1_hp_bar)
	p1_stam_bar = _make_bar(Color(0.88, 0.68, 0.22), 7.0)
	p1_box.add_child(p1_stam_bar)
	p1_limb_lbl = Label.new()
	p1_limb_lbl.add_theme_font_size_override("font_size", 11)
	p1_box.add_child(p1_limb_lbl)

	# Center Controls + Score
	var mid_box := VBoxContainer.new()
	mid_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(mid_box)
	center_lbl = Label.new()
	center_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_box.add_child(center_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	mid_box.add_child(btn_row)

	btn_row.add_child(_make_toggle_btn("1v1 Duel", func(btn: Button):
		game_mode = "gauntlet" if game_mode == "duel" else "duel"
		btn.text = "Gauntlet W%d" % gauntlet_wave if game_mode == "gauntlet" else "1v1 Duel"
		reset_round()))
	btn_row.add_child(_make_toggle_btn("AI: Hard", func(btn: Button):
		ai_difficulty = "brutal" if ai_difficulty == "hard" else ("normal" if ai_difficulty == "brutal" else "hard")
		btn.text = "AI: " + ai_difficulty.capitalize()))
	btn_row.add_child(_make_toggle_btn("1-Hit Sever: OFF", func(btn: Button):
		one_hit_sever = not one_hit_sever
		btn.text = "1-Hit Sever: %s" % ("ON" if one_hit_sever else "OFF")))
	btn_row.add_child(_make_toggle_btn("Gore: BLOOD", func(btn: Button):
		gore_enabled = not gore_enabled
		if p1 != null: p1.gore_enabled = gore_enabled
		if p2 != null: p2.gore_enabled = gore_enabled
		btn.text = "Gore: BLOOD" if gore_enabled else "Gore: SPARKS"))
	btn_row.add_child(_make_toggle_btn("Touch: OFF", func(btn: Button):
		show_touch_controls = not show_touch_controls
		if touch_root != null: touch_root.visible = show_touch_controls
		btn.text = "Touch: ON" if show_touch_controls else "Touch: OFF"))
	btn_row.add_child(_make_toggle_btn("Aim: CURSOR", func(btn: Button):
		if p1 != null:
			p1.cursor_aim_enabled = not p1.cursor_aim_enabled
			btn.text = "Aim: CURSOR" if p1.cursor_aim_enabled else "Aim: KEYS"))
	btn_row.add_child(_make_toggle_btn("Reset (R)", func(_btn: Button):
		reset_round()))

	# Player 2 Card
	var p2_box := VBoxContainer.new()
	p2_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p2_box)
	p2_title_btn = _make_toggle_btn("RIVAL: FECHTMEISTER [V]", func(_b: Button):
		_swap_fighter(false, p2_roster_idx + 1))
	p2_box.add_child(p2_title_btn)
	p2_hp_bar = _make_bar(Color(0.88, 0.22, 0.24), 14.0)
	p2_box.add_child(p2_hp_bar)
	p2_stam_bar = _make_bar(Color(0.88, 0.68, 0.22), 7.0)
	p2_box.add_child(p2_stam_bar)
	p2_limb_lbl = Label.new()
	p2_limb_lbl.add_theme_font_size_override("font_size", 11)
	p2_limb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_box.add_child(p2_limb_lbl)

	# Sleek Upper-Center KO Plaque (Keeps Stage Floor & Fallen Corpses 100% Unobstructed!)
	next_fight_btn = Button.new()
	next_fight_btn.text = "FIGHT AGAIN (R)"
	next_fight_btn.position = Vector2(465, 112)
	next_fight_btn.size = Vector2(350, 44)
	next_fight_btn.visible = false
	next_fight_btn.add_theme_stylebox_override("normal", _make_medieval_box(Color(0.18, 0.05, 0.06, 0.92), Color(0.85, 0.66, 0.28, 0.95), 8))
	next_fight_btn.add_theme_stylebox_override("hover", _make_medieval_box(Color(0.28, 0.08, 0.09, 0.98), Color(1.0, 0.82, 0.38, 1.0), 8))
	next_fight_btn.add_theme_color_override("font_color", Color(0.98, 0.92, 0.76))
	next_fight_btn.pressed.connect(func():
		if round_over and game_mode == "gauntlet" and p2 != null and p2.is_dead:
			_swap_fighter(false, p2_roster_idx + 1)
		else:
			reset_round())
	ui_layer.add_child(next_fight_btn)

	# Bottom Hint Strip
	hint_lbl = Label.new()
	hint_lbl.position = Vector2(20, 694)
	hint_lbl.size = Vector2(1240, 22)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 11)
	ui_layer.add_child(hint_lbl)
	_update_hint_text()

	_build_touch_controls()


func _update_hint_text() -> void:
	if hint_lbl == null:
		return
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var pname := Input.get_joy_name(pads[0])
		hint_lbl.text = "CONTROLLER [%s]:  L-Stick Move  |  X/RB Slash  |  Y Thrust  |  A Kick  |  B/LB Parry  |  RT Dash  |  C/V Swap Fighters" % pname.left(20)
	else:
		hint_lbl.text = "A/D Move  |  Shift Dash  |  Mouse Sling / LMB Slash  |  K Thrust  |  RMB/Space Parry  |  E Kick  |  C/V or 1-5 Swap Fighters  |  R Reset"


func _build_touch_controls() -> void:
	touch_root = Control.new()
	touch_root.size = Vector2(1280, 720)
	touch_root.visible = show_touch_controls
	ui_layer.add_child(touch_root)

	var add_hold_btn := func(pos: Vector2, lbl: String, on_down: Callable, on_up: Callable):
		var b := Button.new()
		b.text = lbl
		b.position = pos
		b.size = Vector2(82, 58)
		b.button_down.connect(on_down)
		b.button_up.connect(on_up)
		touch_root.add_child(b)

	add_hold_btn.call(Vector2(28, 610), "< LEFT", func(): if p1: p1.touch_move = -1.0, func(): if p1: p1.touch_move = 0.0)
	add_hold_btn.call(Vector2(122, 610), "RIGHT >", func(): if p1: p1.touch_move = 1.0, func(): if p1: p1.touch_move = 0.0)
	add_hold_btn.call(Vector2(76, 544), "DASH", func(): if p1: p1.start_dash(p1.touch_move if absf(p1.touch_move) > 0.1 else float(p1.facing)), func(): pass)
	add_hold_btn.call(Vector2(216, 610), "LOW", func(): if p1: p1.touch_low = true, func(): if p1: p1.touch_low = false)

	add_hold_btn.call(Vector2(980, 610), "PARRY", func(): if p1: p1.touch_parry = true, func(): if p1: p1.touch_parry = false)
	add_hold_btn.call(Vector2(1076, 610), "SLASH", func(): if p1: p1.start_attack("slash_low" if p1.touch_low else "slash_high"), func(): pass)
	add_hold_btn.call(Vector2(1170, 610), "THRUST", func(): if p1: p1.start_attack("thrust"), func(): pass)
	add_hold_btn.call(Vector2(1170, 544), "KICK", func(): if p1: p1.start_attack("kick"), func(): pass)


func _make_bar(col: Color, h: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, h)
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.03, 0.03, 0.9)
	bg.border_color = Color(0.32, 0.25, 0.14, 0.7)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", sb)
	return bar


func _make_toggle_btn(txt: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_stylebox_override("normal", _make_medieval_box(Color(0.12, 0.08, 0.09, 0.95), Color(0.45, 0.35, 0.20, 0.8), 5))
	b.add_theme_stylebox_override("hover", _make_medieval_box(Color(0.20, 0.13, 0.14, 1.0), Color(0.82, 0.64, 0.30, 0.95), 5))
	b.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	b.pressed.connect(func(): on_press.call(b))
	return b


func _refresh_hud() -> void:
	if p1 != null and p1_hp_bar != null:
		p1_hp_bar.value = p1.hp
		p1_stam_bar.value = p1.stamina
		p1_limb_lbl.text = _format_limbs(p1)
	if p2 != null and p2_hp_bar != null:
		p2_hp_bar.max_value = p2.max_hp
		p2_hp_bar.value = p2.hp
		p2_stam_bar.value = p2.stamina
		p2_limb_lbl.text = _format_limbs(p2)
	if center_lbl != null:
		if game_mode == "gauntlet":
			center_lbl.text = "%d — %d   (WAVE %d)" % [score_p1, score_p2, gauntlet_wave]
		else:
			center_lbl.text = "%d — %d   STRINGS & STEEL" % [score_p1, score_p2]


func _format_limbs(f: FighterController) -> String:
	var tags: Array[String] = []
	for item in [["head", "HEAD"], ["arm_r", "SWD-ARM"], ["forearm_r", "FORE"], ["arm_l", "OFF-ARM"], ["thigh_l", "L-LEG"], ["thigh_r", "R-LEG"]]:
		var s: String = item[0]
		var lbl: String = item[1]
		tags.append("[X %s]" % lbl if f.severed.get(s, false) else lbl)
	return "  ".join(tags)
