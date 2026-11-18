class_name GameUI
extends CanvasLayer

## All on-screen UI for Strings & Steel: in-fight HUD, title / character select,
## pause menu, round banners, match results and the touch overlay.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS) so menus keep working.
## Talks to the arena only through signals plus a few update methods.

signal start_requested(config: Dictionary)
signal pause_toggle_requested
signal resume_requested
signal restart_round_requested
signal title_requested
signal rematch_requested
signal setting_changed(key: String, value: Variant)

const GOLD := Color(0.85, 0.66, 0.28)
const INK := Color(0.98, 0.92, 0.76)
const PANEL_BG := Color(0.07, 0.04, 0.05, 0.92)

## The human-controlled fighter (driven by the touch overlay).
var player: FighterController

var _roster: Array = []
var _settings: Dictionary = {}
var _settings_refreshers: Array[Callable] = []

# HUD
var _hud_root: Control
var _p1_name: Label
var _p2_name: Label
var _p1_hp: ProgressBar
var _p2_hp: ProgressBar
var _p1_stam: ProgressBar
var _p2_stam: ProgressBar
var _p1_limbs: Label
var _p2_limbs: Label
var _center_lbl: Label
var _timer_lbl: Label
var _hint_lbl: Label

# Screens
var _title_root: Control
var _pause_root: Control
var _result_root: Control
var _result_title: Label
var _result_sub: Label
var _result_primary: Button
var _banner_lbl: Label
var _banner_sub: Label
var _banner_tween: Tween
var _touch_root: Control

# Title selection state
var _sel_p1: int = 0
var _sel_p2: int = -1 # -1 = random
var _sel_p1_loadout: String = "signature"
var _sel_p2_loadout: String = "signature"
var _sel_mode: String = "duel"
var _best_wave: int = 0
var _p1_card: Dictionary = {}
var _p2_card: Dictionary = {}
var _mode_btns: Dictionary = {}
var _title_best_lbl: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10


func setup(roster: Array, settings: Dictionary) -> void:
	_roster = roster
	_settings = settings
	_build_hud()
	_build_banner()
	_build_touch_controls()
	_build_title()
	_build_pause()
	_build_result()
	Input.joy_connection_changed.connect(func(_id: int, _c: bool): refresh_hint(player != null and player.cursor_aim_enabled))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func update_hud(p1: FighterController, p2: FighterController, limbs1: String, limbs2: String, center: String, timer_text: String) -> void:
	_p1_name.text = "YOU: " + String(p1.stats.get("display_name", ""))
	_p2_name.text = "RIVAL: " + String(p2.stats.get("display_name", ""))
	_p1_hp.max_value = p1.max_hp
	_p1_hp.value = p1.hp
	_p2_hp.max_value = p2.max_hp
	_p2_hp.value = p2.hp
	_p1_stam.value = p1.stamina
	_p2_stam.value = p2.stamina
	_p1_limbs.text = limbs1
	_p2_limbs.text = limbs2
	_center_lbl.text = center
	_timer_lbl.text = timer_text


func show_title(p1_idx: int, p2_idx: int, mode: String, best_wave: int, p1_loadout: String = "signature", p2_loadout: String = "signature") -> void:
	_sel_p1 = p1_idx
	_sel_p2 = -1 if mode == "gauntlet" else p2_idx
	_sel_p1_loadout = p1_loadout if p1_loadout in FighterStats.LOADOUT_ORDER else "signature"
	_sel_p2_loadout = p2_loadout if p2_loadout in FighterStats.LOADOUT_ORDER else "signature"
	_sel_mode = mode
	_best_wave = best_wave
	_refresh_title()
	_refresh_settings()
	_title_root.visible = true
	_hud_root.visible = false
	_touch_root.visible = false


func hide_title() -> void:
	_title_root.visible = false
	_hud_root.visible = true
	set_touch_visible(bool(_settings.get("touch", false)))


func show_pause(on: bool) -> void:
	if on:
		_refresh_settings()
	_pause_root.visible = on


func show_banner(text: String, sub: String, duration: float) -> void:
	_banner_lbl.text = text
	_banner_sub.text = sub
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_lbl.modulate.a = 1.0
	_banner_sub.modulate.a = 1.0
	_banner_lbl.scale = Vector2(1.15, 1.15)
	_banner_tween = create_tween()
	_banner_tween.set_ignore_time_scale(true)
	_banner_tween.tween_property(_banner_lbl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(maxf(0.1, duration - 0.45))
	_banner_tween.tween_property(_banner_lbl, "modulate:a", 0.0, 0.27)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.27)


func show_result(title: String, sub: String, primary_label: String) -> void:
	_result_title.text = title
	_result_sub.text = sub
	_result_primary.text = primary_label
	_result_root.visible = true


func hide_result() -> void:
	if _result_root != null:
		_result_root.visible = false


func set_touch_visible(on: bool) -> void:
	if _touch_root != null:
		_touch_root.visible = on and not _title_root.visible


func refresh_hint(cursor_aim: bool) -> void:
	if _hint_lbl == null:
		return
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		_hint_lbl.text = "CONTROLLER [%s]:  L-Stick Move  |  R-Stick Aim  |  X/RB Slash  |  Y Thrust  |  A Kick  |  R3 Half-Sword  |  B/LB/LT Parry  |  RT Dash" % Input.get_joy_name(pads[0]).left(20)
	elif cursor_aim:
		_hint_lbl.text = "A/D Move  |  Mouse: aim & swing  |  RMB/Space Parry  |  Q Half-Sword  |  F/MMB Throw  |  J Slash  K Thrust  E Kick  |  Shift Dash  |  S Low  |  Esc"
	else:
		_hint_lbl.text = "A/D Move  |  LMB/J Slash  |  K Thrust  |  E Kick  |  Q Half-Sword  |  F Throw  |  RMB/Space Parry  |  S Low  |  Shift Dash  |  Esc Pause"


# ---------------------------------------------------------------------------
# Input (works while paused)
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if _title_root != null and _title_root.visible:
		if event.is_action_pressed("ui_accept"):
			_emit_start()
		elif event.is_action_pressed("ui_left"):
			_cycle_p1(-1)
		elif event.is_action_pressed("ui_right"):
			_cycle_p1(1)
		elif event.is_action_pressed("ui_up"):
			_cycle_p2(-1)
		elif event.is_action_pressed("ui_down"):
			_cycle_p2(1)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if _result_root != null and _result_root.visible:
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			rematch_requested.emit()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_toggle_requested.emit()


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _box(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(txt: String, size: int, col: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	return l


func _button(txt: String, on_press: Callable, size: int = 12) -> Button:
	var b := Button.new()
	b.text = txt
	# Buttons never take keyboard focus: otherwise Space (parry) / Enter would
	# re-trigger the last clicked button mid-fight.
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _box(Color(0.12, 0.08, 0.09, 0.95), Color(0.45, 0.35, 0.20, 0.8), 5))
	b.add_theme_stylebox_override("hover", _box(Color(0.20, 0.13, 0.14, 1.0), Color(0.82, 0.64, 0.30, 0.95), 5))
	b.add_theme_stylebox_override("pressed", _box(Color(0.28, 0.08, 0.09, 1.0), Color(1.0, 0.82, 0.38, 1.0), 5))
	b.add_theme_color_override("font_color", INK)
	b.pressed.connect(func(): on_press.call(b))
	return b


func _bar(col: Color, h: float, max_v: float = 100.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, h)
	bar.max_value = max_v
	bar.value = max_v
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _overlay_panel(min_size: Vector2) -> Array:
	var root := Control.new()
	_full_rect(root)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_full_rect(dim)
	root.add_child(dim)
	var center := CenterContainer.new()
	_full_rect(center)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, GOLD, 12))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	return [root, vb]


func _build_hud() -> void:
	_hud_root = Control.new()
	_full_rect(_hud_root)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 10
	top.add_theme_stylebox_override("panel", _box(Color(0.07, 0.04, 0.05, 0.88), Color(0.68, 0.52, 0.24, 0.85), 10))
	_hud_root.add_child(top)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	top.add_child(hb)

	var c1 := VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(c1)
	_p1_name = _label("YOU", 13, Color(0.6, 0.78, 1.0))
	c1.add_child(_p1_name)
	_p1_hp = _bar(Color(0.28, 0.56, 0.96), 14.0)
	c1.add_child(_p1_hp)
	_p1_stam = _bar(Color(0.88, 0.68, 0.22), 7.0)
	c1.add_child(_p1_stam)
	_p1_limbs = _label("", 11)
	c1.add_child(_p1_limbs)

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size = Vector2(260, 0)
	hb.add_child(mid)
	_center_lbl = _label("", 15, INK, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(_center_lbl)
	_timer_lbl = _label("", 24, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(_timer_lbl)
	var menu_btn := _button("II  MENU (Esc)", func(_b): pause_toggle_requested.emit(), 11)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(menu_btn)

	var c2 := VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(c2)
	_p2_name = _label("RIVAL", 13, Color(1.0, 0.6, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	c2.add_child(_p2_name)
	_p2_hp = _bar(Color(0.88, 0.22, 0.24), 14.0)
	_p2_hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	c2.add_child(_p2_hp)
	_p2_stam = _bar(Color(0.88, 0.68, 0.22), 7.0)
	_p2_stam.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	c2.add_child(_p2_stam)
	_p2_limbs = _label("", 11, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	c2.add_child(_p2_limbs)

	_hint_lbl = _label("", 11, Color(0.85, 0.8, 0.7, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_lbl.offset_top = -26
	_hint_lbl.offset_bottom = -6
	_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hint_lbl)


func _build_banner() -> void:
	var holder := VBoxContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	holder.offset_top = 190
	holder.offset_left = -400
	holder.offset_right = 400
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_banner_lbl = _label("", 64, Color(1.0, 0.86, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_banner_lbl.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.03))
	_banner_lbl.add_theme_constant_override("outline_size", 10)
	_banner_lbl.pivot_offset = Vector2(400, 40)
	_banner_lbl.modulate.a = 0.0
	holder.add_child(_banner_lbl)
	_banner_sub = _label("", 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02))
	_banner_sub.add_theme_constant_override("outline_size", 6)
	_banner_sub.modulate.a = 0.0
	holder.add_child(_banner_sub)


# --- Settings grid (shared by title & pause) ---

func _build_settings_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	for key in ["difficulty", "stage", "gore", "one_hit_sever", "cursor_aim", "touch", "strings", "sound"]:
		var b := _button(_setting_label(key), func(_b): _toggle_setting(key), 11)
		b.custom_minimum_size = Vector2(150, 0)
		grid.add_child(b)
		_settings_refreshers.append(func(): b.text = _setting_label(key))
	return grid


func _on_off(key: String) -> String:
	return "ON" if bool(_settings.get(key, false)) else "OFF"


func _setting_label(key: String) -> String:
	match key:
		"difficulty":
			return "AI: " + String(_settings["difficulty"]).capitalize()
		"stage":
			return "Stage: " + ("COURTYARD" if String(_settings.get("stage", "courtyard")) != "theatre" else "THEATRE")
		"gore":
			return "Gore: " + ("BLOOD" if bool(_settings["gore"]) else "SPARKS")
		"one_hit_sever":
			return "1-Hit Sever: " + _on_off(key)
		"cursor_aim":
			return "Aim: " + ("CURSOR" if bool(_settings["cursor_aim"]) else "KEYS")
		"touch":
			return "Touch: " + _on_off(key)
		"strings":
			return "Strings: " + _on_off(key)
		"sound":
			return "Sound: " + _on_off(key)
	return key


func _toggle_setting(key: String) -> void:
	if key == "difficulty":
		var order := ["normal", "hard", "brutal"]
		var i := (order.find(String(_settings["difficulty"])) + 1) % order.size()
		_change_setting(key, order[i])
	elif key == "stage":
		var nxt := "theatre" if String(_settings.get("stage", "courtyard")) != "theatre" else "courtyard"
		_change_setting(key, nxt)
	else:
		_change_setting(key, not bool(_settings.get(key, false)))


func _change_setting(key: String, value: Variant) -> void:
	_settings[key] = value
	setting_changed.emit(key, value)
	_refresh_settings()


func _refresh_settings() -> void:
	for r in _settings_refreshers:
		r.call()


# --- Title / character select ---

func _build_title() -> void:
	_title_root = Control.new()
	_full_rect(_title_root)
	add_child(_title_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.02, 0.62)
	_full_rect(dim)
	_title_root.add_child(dim)
	var center := CenterContainer.new()
	_full_rect(center)
	_title_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, GOLD, 14))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title := _label("STRINGS & STEEL", 46, Color(1.0, 0.84, 0.48), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.03, 0.04))
	title.add_theme_constant_override("outline_size", 8)
	vb.add_child(title)
	vb.add_child(_label("A marionette duel to the last string", 14, Color(0.85, 0.75, 0.6), HORIZONTAL_ALIGNMENT_CENTER))

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 24)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(cards)
	_p1_card = _build_fighter_card("YOU", Color(0.6, 0.78, 1.0), func(d): _cycle_p1(d), func(): _cycle_loadout(true))
	cards.add_child(_p1_card["root"])
	cards.add_child(_label("VS", 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_p2_card = _build_fighter_card("RIVAL", Color(1.0, 0.6, 0.6), func(d): _cycle_p2(d), func(): _cycle_loadout(false))
	cards.add_child(_p2_card["root"])

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 10)
	vb.add_child(modes)
	_mode_btns["duel"] = _button("DUEL · BEST OF 3", func(_b): _set_mode("duel"), 14)
	_mode_btns["gauntlet"] = _button("GAUNTLET · ENDLESS", func(_b): _set_mode("gauntlet"), 14)
	modes.add_child(_mode_btns["duel"])
	modes.add_child(_mode_btns["gauntlet"])

	var settings_center := CenterContainer.new()
	settings_center.add_child(_build_settings_grid())
	vb.add_child(settings_center)

	var fight := _button("FIGHT!", func(_b): _emit_start(), 22)
	fight.custom_minimum_size = Vector2(260, 52)
	fight.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(fight)

	_title_best_lbl = _label("", 12, Color(0.85, 0.75, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_title_best_lbl)
	vb.add_child(_label("←/→ pick fighter   ↑/↓ pick rival   Enter / A to fight", 11, Color(0.7, 0.65, 0.55), HORIZONTAL_ALIGNMENT_CENTER))


func _build_fighter_card(header: String, col: Color, on_cycle: Callable, on_loadout: Callable) -> Dictionary:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(330, 0)
	root.add_theme_constant_override("separation", 6)
	root.add_child(_label(header, 13, col, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	row.add_child(_button(" < ", func(_b): on_cycle.call(-1), 16))
	var name_lbl := _label("", 20, INK, HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.custom_minimum_size = Vector2(230, 0)
	row.add_child(name_lbl)
	row.add_child(_button(" > ", func(_b): on_cycle.call(1), 16))
	var blurb := _label("", 12, Color(0.85, 0.78, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(320, 34)
	root.add_child(blurb)
	var lo_btn := _button("Weapon: SIGNATURE", func(_b): on_loadout.call(), 11)
	lo_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lo_btn.custom_minimum_size = Vector2(230, 0)
	root.add_child(lo_btn)
	var bars := {}
	for stat_name in ["HEALTH", "SPEED", "POWER", "ARMOUR"]:
		var line := HBoxContainer.new()
		var l := _label(stat_name, 10, Color(0.8, 0.72, 0.6))
		l.custom_minimum_size = Vector2(64, 0)
		line.add_child(l)
		var bar := _bar(GOLD, 8.0, 1.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		root.add_child(line)
		bars[stat_name] = bar
	return {"root": root, "name": name_lbl, "blurb": blurb, "loadout": lo_btn, "bars": bars}


func _fill_card(card: Dictionary, idx: int, loadout_id: String) -> void:
	var bars: Dictionary = card["bars"]
	var lo_btn: Button = card["loadout"]
	var lo_lbl: String = String(FighterStats.LOADOUT_LABELS.get(loadout_id, "SIGNATURE"))
	if idx < 0 or idx >= _roster.size():
		card["name"].text = "RANDOM"
		card["blurb"].text = "A random challenger steps onto the stage." if _sel_mode == "duel" else "Gauntlet rivals & loadouts scale each wave."
		lo_btn.text = "Weapon: MIXED" if _sel_mode == "gauntlet" else ("Weapon: " + lo_lbl)
		for k in bars.keys():
			bars[k].value = 0.0
		return
	var s: Dictionary = _roster[idx]
	card["name"].text = String(s["display_name"])
	card["blurb"].text = String(s["blurb"])
	lo_btn.text = "Weapon: " + lo_lbl
	var pwr_bonus := 0.14 if loadout_id == "pollaxe" else (-0.04 if loadout_id in ["buckler", "katzbalger"] else 0.0)
	var spd_bonus := 0.14 if loadout_id == "katzbalger" else (-0.10 if loadout_id == "pollaxe" else 0.0)
	var arm_bonus := 0.18 if loadout_id == "buckler" else 0.0
	bars["HEALTH"].value = clampf((float(s["max_hp"]) - 70.0) / 60.0, 0.05, 1.0)
	bars["SPEED"].value = clampf((float(s["move_speed"]) - 220.0) / 140.0 + spd_bonus, 0.05, 1.0)
	bars["POWER"].value = clampf((float(s["damage_mult"]) * float(s["attack_speed"]) - 0.8) / 0.5 + pwr_bonus, 0.05, 1.0)
	var slots: Array = s["armored_slots"]
	bars["ARMOUR"].value = clampf((1.0 - float(s["armor_mult"])) * float(slots.size()) / 2.5 + arm_bonus, 0.0, 1.0)


func _refresh_title() -> void:
	_fill_card(_p1_card, _sel_p1, _sel_p1_loadout)
	_fill_card(_p2_card, _sel_p2, _sel_p2_loadout)
	for k in _mode_btns.keys():
		var b: Button = _mode_btns[k]
		var base := "DUEL · BEST OF 3" if k == "duel" else "GAUNTLET · ENDLESS"
		b.text = ("▶ " + base + " ◀") if k == _sel_mode else base
	_title_best_lbl.text = "Gauntlet best: wave %d cleared" % _best_wave if _best_wave > 0 else ""


func _cycle_loadout(is_p1: bool) -> void:
	if not is_p1 and _sel_mode == "gauntlet":
		return
	var order := FighterStats.LOADOUT_ORDER
	var cur := _sel_p1_loadout if is_p1 else _sel_p2_loadout
	var nxt: String = order[(order.find(cur) + 1) % order.size()]
	if is_p1:
		_sel_p1_loadout = nxt
	else:
		_sel_p2_loadout = nxt
	_refresh_title()


func _cycle_p1(d: int) -> void:
	_sel_p1 = posmod(_sel_p1 + d, _roster.size())
	_refresh_title()


func _cycle_p2(d: int) -> void:
	if _sel_mode == "gauntlet":
		_sel_p2 = -1
	else:
		# Cycle through RANDOM (-1) and every roster entry.
		_sel_p2 = posmod(_sel_p2 + 1 + d, _roster.size() + 1) - 1
	_refresh_title()


func _set_mode(m: String) -> void:
	_sel_mode = m
	if m == "gauntlet":
		_sel_p2 = -1
	_refresh_title()


func _emit_start() -> void:
	start_requested.emit({"p1": _sel_p1, "p2": _sel_p2, "p1_loadout": _sel_p1_loadout, "p2_loadout": _sel_p2_loadout, "mode": _sel_mode})


# --- Pause ---

func _build_pause() -> void:
	var parts := _overlay_panel(Vector2(660, 0))
	_pause_root = parts[0]
	var vb: VBoxContainer = parts[1]
	vb.add_child(_label("PAUSED", 40, Color(1.0, 0.84, 0.48), HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(_button("RESUME", func(_b): resume_requested.emit(), 15))
	row.add_child(_button("RESTART ROUND", func(_b): restart_round_requested.emit(), 15))
	row.add_child(_button("CHANGE FIGHTERS", func(_b): title_requested.emit(), 15))
	var settings_center := CenterContainer.new()
	settings_center.add_child(_build_settings_grid())
	vb.add_child(settings_center)
	var help := _label("Swing through a wide arc for heavy limb-chopping cuts (gold trail); drive the point forward to thrust.\nPress Q to HALF-SWORD against plate armour; press F / Middle-Click to HURL your blade & scramble for dropped steel!\nHigh slashes snap marionette strings; kicks & guard-breaks against stage walls trigger CORNER CRUSH.", 12, Color(0.8, 0.74, 0.62), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(help)


# --- Result ---

func _build_result() -> void:
	var parts := _overlay_panel(Vector2(560, 0))
	_result_root = parts[0]
	var vb: VBoxContainer = parts[1]
	_result_title = _label("", 48, Color(1.0, 0.84, 0.48), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_result_title)
	_result_sub = _label("", 16, INK, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_result_sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	_result_primary = _button("REMATCH", func(_b): rematch_requested.emit(), 16)
	row.add_child(_result_primary)
	row.add_child(_button("CHANGE FIGHTERS", func(_b): title_requested.emit(), 16))


# --- Touch overlay ---

func _build_touch_controls() -> void:
	_touch_root = Control.new()
	_full_rect(_touch_root)
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_root.visible = false
	add_child(_touch_root)

	var add_hold_btn := func(anchor_right: bool, pos: Vector2, lbl: String, on_down: Callable, on_up: Callable):
		var b := Button.new()
		b.text = lbl
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(82, 58)
		if anchor_right:
			b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		else:
			b.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		b.position = pos
		b.button_down.connect(on_down)
		b.button_up.connect(on_up)
		_touch_root.add_child(b)

	add_hold_btn.call(false, Vector2(28, 610), "< LEFT", func(): if _touch_ok(): player.touch_move = -1.0, func(): if player: player.touch_move = 0.0)
	add_hold_btn.call(false, Vector2(122, 610), "RIGHT >", func(): if _touch_ok(): player.touch_move = 1.0, func(): if player: player.touch_move = 0.0)
	add_hold_btn.call(false, Vector2(76, 544), "DASH", func(): if _touch_ok(): player.start_dash(player.touch_move if absf(player.touch_move) > 0.1 else float(player.facing)), func(): pass)
	add_hold_btn.call(false, Vector2(216, 610), "LOW", func(): if player: player.touch_low = true, func(): if player: player.touch_low = false)
	add_hold_btn.call(true, Vector2(980, 610), "PARRY", func(): if player: player.touch_parry = true, func(): if player: player.touch_parry = false)
	add_hold_btn.call(true, Vector2(980, 544), "HALF-SWD", func(): if _touch_ok(): player.toggle_half_sword(), func(): pass)
	add_hold_btn.call(true, Vector2(1076, 544), "THROW", func(): if _touch_ok(): player.throw_weapon(), func(): pass)
	add_hold_btn.call(true, Vector2(1076, 610), "SLASH", func(): if _touch_ok():
		if player.can_wield():
			player.start_attack("slash_low" if player.touch_low else "slash_high")
		else:
			player.start_jab(), func(): pass)
	add_hold_btn.call(true, Vector2(1170, 610), "THRUST", func(): if _touch_ok():
		if player.can_wield():
			player.start_attack("thrust")
		else:
			player.start_jab(), func(): pass)
	add_hold_btn.call(true, Vector2(1170, 544), "KICK", func(): if _touch_ok(): player.start_attack("kick"), func(): pass)


func _touch_ok() -> bool:
	return player != null and is_instance_valid(player) and player.input_enabled and not player.is_dead
