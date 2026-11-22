class_name GameUI
extends CanvasLayer

## All on-screen UI for Strings & Steel: in-fight HUD, title / character select,
## pause menu, round banners, match results and the touch overlay.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS) so menus keep working.
## Talks to the arena only through signals plus a few update methods.

signal start_requested(config: Dictionary)
signal preview_changed(config: Dictionary)
signal preview_flourish_requested(is_p1: bool)
signal practice_dummy_cycled
signal practice_reset_requested
signal pause_toggle_requested
signal resume_requested
signal restart_round_requested
signal title_requested
signal change_fighters_requested
signal quit_requested
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
var _practice_row: HBoxContainer
var _practice_info_lbl: Label
var _practice_dummy_btn: Button
var _center_lbl: Label
var _timer_lbl: Label
var _hint_lbl: Label

# Screens
var _title_root: Control
var _title_page: String = "main" # "main" | "select" | "controls" | "settings"
var _main_menu_view: Control
var _select_view: Control
var _controls_view: Control
var _settings_view: Control
var _main_menu_items: Array[Dictionary] = []
var _main_focus_idx: int = 0
var _main_gauntlet_btn: Button
var _select_mode_lbl: Label
var _title_p1_badge: PanelContainer
var _title_p2_badge: PanelContainer
var _vs_lbl: Label
var _fight_btn: Button
var _pause_root: Control
var _result_root: Control
var _result_title: Label
var _result_sub: Label
var _result_primary: Button
var _banner_lbl: Label
var _banner_sub: Label
var _banner_tween: Tween
var _touch_ctrl: MobileTouchController

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

func update_hud(p1: FighterController, p2: FighterController, limbs1: String, limbs2: String, center: String, timer_text: String, practice_info: Dictionary = {}) -> void:
	_p1_name.text = "YOU: " + String(p1.stats.get("display_name", ""))
	_p1_hp.max_value = p1.max_hp
	_p1_hp.value = p1.hp
	_p1_stam.value = p1.stamina
	_p1_limbs.text = limbs1
	_center_lbl.text = center
	_timer_lbl.text = timer_text

	var in_practice := bool(practice_info.get("active", false))
	var dummy_mode := String(practice_info.get("dummy_mode", "off"))
	var solo_stage := in_practice and dummy_mode == "off"
	_p2_hp.visible = not solo_stage
	_p2_stam.visible = not solo_stage
	_p2_limbs.visible = not in_practice
	if _practice_row != null:
		_practice_row.visible = in_practice
	if in_practice:
		if solo_stage:
			_p2_name.text = "SOLO DOJO · SINGLE CHARACTER"
		else:
			_p2_name.text = "DUMMY [%s]: %s" % [dummy_mode.to_upper(), String(p2.stats.get("display_name", ""))]
			_p2_hp.max_value = p2.max_hp
			_p2_hp.value = p2.hp
			_p2_stam.value = p2.stamina
		if _practice_info_lbl != null:
			var sig_txt := "READY" if p1.signature_cd <= 0.05 else ("%.1fs" % p1.signature_cd)
			var pwr_pct := int(round(p1.last_strike_power * 100.0))
			var mv_str := p1.last_performed_move if pwr_pct <= 0 else ("%s (%d%%)" % [p1.last_performed_move, pwr_pct])
			_practice_info_lbl.text = "LAST: %s  ·  SIG [G]: %s" % [mv_str, sig_txt]
		if _practice_dummy_btn != null:
			var d_lbl := "OFF (Solo)" if dummy_mode == "off" else dummy_mode.to_upper()
			_practice_dummy_btn.text = "Dummy: " + d_lbl
	else:
		_p2_name.text = "RIVAL: " + String(p2.stats.get("display_name", ""))
		_p2_hp.max_value = p2.max_hp
		_p2_hp.value = p2.hp
		_p2_stam.value = p2.stamina
		_p2_limbs.text = limbs2


func get_title_page() -> String:
	return _title_page


func show_title(p1_idx: int, p2_idx: int, mode: String, best_wave: int, p1_loadout: String = "signature", p2_loadout: String = "signature", page: String = "main") -> void:
	_sel_p1 = p1_idx
	_sel_p2 = -1 if mode == "gauntlet" else p2_idx
	_sel_p1_loadout = p1_loadout if p1_loadout in FighterStats.LOADOUT_ORDER else "signature"
	_sel_p2_loadout = p2_loadout if p2_loadout in FighterStats.LOADOUT_ORDER else "signature"
	_sel_mode = mode if mode in ["duel", "gauntlet", "practice"] else "duel"
	_best_wave = best_wave
	_refresh_title()
	_refresh_settings()
	_title_root.visible = true
	_hud_root.visible = false
	if _touch_ctrl != null:
		_touch_ctrl.set_active(false)
	show_title_page(page)


func show_title_page(page: String) -> void:
	_title_page = page if page in ["main", "select", "controls", "settings"] else "main"
	if _main_menu_view != null:
		_main_menu_view.visible = _title_page == "main"
	if _select_view != null:
		_select_view.visible = _title_page == "select"
	if _controls_view != null:
		_controls_view.visible = _title_page == "controls"
	if _settings_view != null:
		_settings_view.visible = _title_page == "settings"
	if _title_p1_badge != null:
		_title_p1_badge.visible = _title_page == "select"
	if _title_p2_badge != null:
		_title_p2_badge.visible = _title_page == "select" and _sel_mode != "practice"
	_refresh_main_menu()
	_refresh_title()
	_refresh_settings()
	_emit_preview("init")


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
	if _touch_ctrl != null:
		_touch_ctrl.player = player
		_touch_ctrl.set_active(on and not _title_root.visible)


func refresh_hint(cursor_aim: bool) -> void:
	if _hint_lbl == null:
		return
	if bool(_settings.get("touch", false)):
		_hint_lbl.text = "TOUCH:  Left = Move · Flick L/R = Dash · Up+Fwd = Leap · Down+Fwd = Sweep · Down = Kick · Up = Half-Sword  |  Right = 360° Swing · 2x Tap = ★ Signature · Pull Back = Parry"
		return
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		_hint_lbl.text = "PAD [%s]:  L-Stick Move  |  R-Stick Swing  |  X Slash  Y Thrust  B+A ★Signature  L3 Pommel  A Kick  R3 Half-Sword  |  B/LB Parry  RT Dash" % Input.get_joy_name(pads[0]).left(16)
	elif cursor_aim:
		_hint_lbl.text = "A/D Move (2x/Shift Dash)  |  Mouse Swing or LMB Click  |  G/Tab ★Signature  |  RMB/Space Parry  WheelUp/V Thrust  WheelDn/X Spin  C Pommel  W Leap  E Kick  Q Half-Sword  F Throw"
	else:
		_hint_lbl.text = "A/D Move (2x/Shift Dash)  |  LMB/J Slash  G/Tab ★Signature  V/K Thrust  X/U Spin  C/L Pommel  W Leap  E Kick (S+E Sweep)  Q Half-Sword  F Throw  |  RMB/Space Parry"


# ---------------------------------------------------------------------------
# Input (works while paused)
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if _title_root != null and _title_root.visible:
		if _title_page == "main":
			if event.is_action_pressed("ui_up") or event.is_action_pressed("jump_attack"):
				_move_main_focus(-1)
			elif event.is_action_pressed("ui_down") or event.is_action_pressed("guard_low"):
				_move_main_focus(1)
			elif event.is_action_pressed("ui_accept"):
				_activate_main_focus()
			else:
				return
			get_viewport().set_input_as_handled()
			return
		elif _title_page in ["controls", "settings"]:
			if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
				show_title_page("main")
				get_viewport().set_input_as_handled()
			return
		else:
			if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
				show_title_page("main")
			elif event.is_action_pressed("ui_accept"):
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
	var safe_margin := 22.0
	if OS.get_name() in ["Android", "iOS"]:
		var win_sz := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if win_sz.x > 100.0 and safe.size.x > 100.0:
			var sc := 720.0 / maxf(360.0, win_sz.y)
			safe_margin = maxf(24.0, maxf(safe.position.x, win_sz.x - safe.end.x) * sc + 8.0)
	top.offset_left = safe_margin
	top.offset_right = -safe_margin
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
	var menu_btn := _button("II  MENU", func(_b): pause_toggle_requested.emit(), 11)
	menu_btn.custom_minimum_size = Vector2(98, 28)
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

	_practice_row = HBoxContainer.new()
	_practice_row.alignment = BoxContainer.ALIGNMENT_END
	_practice_row.add_theme_constant_override("separation", 6)
	_practice_row.visible = false
	c2.add_child(_practice_row)
	_practice_info_lbl = _label("LAST: READY  ·  SIG [G]: READY", 10, Color(1.0, 0.86, 0.48), HORIZONTAL_ALIGNMENT_RIGHT)
	_practice_info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_row.add_child(_practice_info_lbl)
	_practice_dummy_btn = _button("Dummy: OFF (Solo)", func(_b): practice_dummy_cycled.emit(), 10)
	_practice_dummy_btn.custom_minimum_size = Vector2(128, 24)
	_practice_row.add_child(_practice_dummy_btn)
	var reset_btn := _button("Reset [R]", func(_b): practice_reset_requested.emit(), 10)
	reset_btn.custom_minimum_size = Vector2(74, 24)
	_practice_row.add_child(reset_btn)

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

func _build_settings_grid(btn_w: float = 150.0) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)

	for key in ["difficulty", "stage", "gore", "one_hit_sever", "cursor_aim", "touch", "strings", "sound"]:
		var b := _button(_setting_label(key), func(_b): _toggle_setting(key), 10 if btn_w < 140.0 else 11)
		b.custom_minimum_size = Vector2(btn_w, 0)
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
			return "Sever: " + ("BRUTAL" if bool(_settings["one_hit_sever"]) else "NORMAL")
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


# --- Main Menu, Character Select, Controls Codex & Settings ---

func _build_stage_wing_badge(title_txt: String, col: Color, left_side: bool, on_flourish: Callable) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _box(Color(0.06, 0.03, 0.04, 0.80), Color(col.r, col.g, col.b, 0.72), 8))
	badge.position = Vector2(28.0 if left_side else 972.0, 14.0)
	badge.custom_minimum_size = Vector2(280, 0)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	badge.add_child(hb)
	var lbl := _label(title_txt, 11, col, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	var fl_btn := _button("★ FLOURISH", func(_b): on_flourish.call(), 10)
	fl_btn.custom_minimum_size = Vector2(92, 24)
	hb.add_child(fl_btn)
	return badge


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.85, 0.66, 0.28, 0.36)
	line.custom_minimum_size = Vector2(0, 2)
	return line


func _add_main_menu_item(parent: VBoxContainer, label_txt: String, action: Callable, font_sz: int = 16, min_h: float = 44.0) -> Button:
	var idx := _main_menu_items.size()
	var btn := _button(label_txt, func(_b):
		_main_focus_idx = idx
		_refresh_main_menu()
		action.call(), font_sz)
	btn.custom_minimum_size = Vector2(336, min_h)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.mouse_entered.connect(func():
		_main_focus_idx = idx
		_refresh_main_menu())
	parent.add_child(btn)
	_main_menu_items.append({"btn": btn, "base": label_txt, "action": action})
	return btn


func _move_main_focus(delta_idx: int) -> void:
	if _main_menu_items.is_empty():
		return
	_main_focus_idx = posmod(_main_focus_idx + delta_idx, _main_menu_items.size())
	_refresh_main_menu()


func _activate_main_focus() -> void:
	if _main_menu_items.is_empty():
		return
	var idx := clampi(_main_focus_idx, 0, _main_menu_items.size() - 1)
	var act: Callable = _main_menu_items[idx]["action"]
	act.call()


func _refresh_main_menu() -> void:
	if _main_menu_items.is_empty():
		return
	for i in range(_main_menu_items.size()):
		var item: Dictionary = _main_menu_items[i]
		var btn: Button = item["btn"]
		var base: String = String(item["base"])
		if btn == _main_gauntlet_btn and _best_wave > 0:
			base = "☠   ENDLESS GAUNTLET   (Best: %d)" % _best_wave
		var focused := i == _main_focus_idx
		btn.text = ("▶  " + base + "  ◀") if focused else base
		var bg := Color(0.22, 0.11, 0.13, 0.98) if focused else Color(0.11, 0.07, 0.08, 0.94)
		var bd := Color(1.0, 0.84, 0.38, 0.98) if focused else Color(0.48, 0.36, 0.20, 0.78)
		btn.add_theme_stylebox_override("normal", _box(bg, bd, 6))
		btn.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72) if focused else INK)


func _open_mode_select(mode_id: String) -> void:
	_sel_mode = mode_id
	if mode_id == "gauntlet":
		_sel_p2 = -1
	show_title_page("select")


func _build_title() -> void:
	_title_root = Control.new()
	_full_rect(_title_root)
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_root)

	# Split-stage theatre layout: NO full-screen dark dimmer so the live breathing marionettes
	# stand illuminated in left & right stage spotlights behind the Main Menu & Character Select!
	_title_p1_badge = _build_stage_wing_badge("◀ YOU · LIVE STAGE", Color(0.62, 0.82, 1.0), true, func(): preview_flourish_requested.emit(true))
	_title_root.add_child(_title_p1_badge)
	_title_p2_badge = _build_stage_wing_badge("RIVAL · LIVE STAGE ▶", Color(1.0, 0.62, 0.62), false, func(): preview_flourish_requested.emit(false))
	_title_root.add_child(_title_p2_badge)

	_build_main_menu_view()
	_build_select_view()
	_build_controls_view()
	_build_settings_view()


func _build_main_menu_view() -> void:
	_main_menu_view = CenterContainer.new()
	_full_rect(_main_menu_view)
	_main_menu_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(_main_menu_view)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(444, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.03, 0.04, 0.88), GOLD, 14))
	_main_menu_view.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	panel.add_child(vb)

	vb.add_child(_label("✦  ROYAL MARIONETTE ARENA  ✦", 11, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var title := _label("STRINGS & STEEL", 48, Color(1.0, 0.85, 0.48), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.03, 0.04))
	title.add_theme_constant_override("outline_size", 8)
	vb.add_child(title)
	vb.add_child(_label("A physical HEMA blade duel to the last string", 13, Color(0.86, 0.77, 0.62), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_divider())

	var menu_vb := VBoxContainer.new()
	menu_vb.add_theme_constant_override("separation", 8)
	vb.add_child(menu_vb)
	_main_menu_items.clear()
	_add_main_menu_item(menu_vb, "⚔   DUEL  ·  BEST OF 3", func(): _open_mode_select("duel"), 16, 44.0)
	_main_gauntlet_btn = _add_main_menu_item(menu_vb, "☠   ENDLESS GAUNTLET", func(): _open_mode_select("gauntlet"), 16, 44.0)
	_add_main_menu_item(menu_vb, "★   SOLO PRACTICE DOJO", func(): _open_mode_select("practice"), 16, 44.0)
	_add_main_menu_item(menu_vb, "📖   CONTROLS & MOVESET", func(): show_title_page("controls"), 14, 38.0)
	_add_main_menu_item(menu_vb, "⚙   SETTINGS", func(): show_title_page("settings"), 14, 38.0)
	if not (OS.get_name() in ["Android", "iOS", "Web"]):
		_add_main_menu_item(menu_vb, "✕   QUIT GAME", func(): quit_requested.emit(), 13, 36.0)

	vb.add_child(_divider())
	vb.add_child(_label("↑/↓ Navigate   ·   Enter / A Select   ·   Click Any Mode", 10, Color(0.72, 0.66, 0.56), HORIZONTAL_ALIGNMENT_CENTER))


func _build_select_view() -> void:
	_select_view = CenterContainer.new()
	_full_rect(_select_view)
	_select_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_view.visible = false
	_title_root.add_child(_select_view)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(576, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.03, 0.04, 0.88), GOLD, 12))
	_select_view.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	_select_mode_lbl = _label("CHOOSE YOUR FIGHTER", 26, Color(1.0, 0.84, 0.48), HORIZONTAL_ALIGNMENT_CENTER)
	_select_mode_lbl.add_theme_color_override("font_outline_color", Color(0.25, 0.03, 0.04))
	_select_mode_lbl.add_theme_constant_override("outline_size", 6)
	vb.add_child(_select_mode_lbl)

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 8)
	vb.add_child(modes)
	_mode_btns["duel"] = _button("DUEL · BEST OF 3", func(_b): _set_mode("duel"), 11)
	_mode_btns["gauntlet"] = _button("GAUNTLET · ENDLESS", func(_b): _set_mode("gauntlet"), 11)
	_mode_btns["practice"] = _button("PRACTICE · SOLO", func(_b): _set_mode("practice"), 11)
	modes.add_child(_mode_btns["duel"])
	modes.add_child(_mode_btns["gauntlet"])
	modes.add_child(_mode_btns["practice"])

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(cards)
	_p1_card = _build_fighter_card("YOU", Color(0.6, 0.78, 1.0), func(d): _cycle_p1(d), func(): _cycle_loadout(true))
	cards.add_child(_p1_card["root"])
	_vs_lbl = _label("VS", 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	cards.add_child(_vs_lbl)
	_p2_card = _build_fighter_card("RIVAL", Color(1.0, 0.6, 0.6), func(d): _cycle_p2(d), func(): _cycle_loadout(false))
	cards.add_child(_p2_card["root"])

	var act_row := HBoxContainer.new()
	act_row.alignment = BoxContainer.ALIGNMENT_CENTER
	act_row.add_theme_constant_override("separation", 14)
	vb.add_child(act_row)
	var back_btn := _button("←  MAIN MENU", func(_b): show_title_page("main"), 13)
	back_btn.custom_minimum_size = Vector2(148, 44)
	act_row.add_child(back_btn)
	_fight_btn = _button("FIGHT!", func(_b): _emit_start(), 20)
	_fight_btn.custom_minimum_size = Vector2(248, 44)
	act_row.add_child(_fight_btn)

	_title_best_lbl = _label("", 11, Color(0.85, 0.75, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_title_best_lbl)
	vb.add_child(_label("←/→ pick fighter   ↑/↓ pick rival   Enter / A start   Esc Main Menu", 10, Color(0.7, 0.65, 0.55), HORIZONTAL_ALIGNMENT_CENTER))


func _build_controls_view() -> void:
	_controls_view = CenterContainer.new()
	_full_rect(_controls_view)
	_controls_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_view.visible = false
	_title_root.add_child(_controls_view)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.03, 0.04, 0.92), GOLD, 12))
	_controls_view.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	vb.add_child(_label("CONTROLS & HEMA MOVESET", 28, Color(1.0, 0.84, 0.48), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_divider())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	vb.add_child(cols)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	cols.add_child(left_col)
	left_col.add_child(_label("SWORDPLAY & DEFENCE", 13, Color(0.62, 0.82, 1.0)))
	var left_txt := (
		"• Mouse / R-Stick:  210° Live 2-Bone IK Swing\n" +
		"  (Wide arc = gold limb-chopping power)\n" +
		"• LMB / J / Pad X:  Slash & Mixup Chains\n" +
		"• RMB / Space / Pad B:  High Parry (+ S = Low)\n" +
		"• Perfect Parry:  Staggers foe + Zornhau Riposte\n" +
		"• Q / R3:  Half-Sword (+ V/C = Mordhau vs plate)\n" +
		"• F / Middle-Click:  Hurl Blade & Pick Up Steel"
	)
	var l_body := _label(left_txt, 12, INK)
	l_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_col.add_child(l_body)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 6)
	cols.add_child(right_col)
	right_col.add_child(_label("SPECIALS, FOOTWORK & TOUCH", 13, Color(1.0, 0.82, 0.44)))
	var right_txt := (
		"• G / Tab / Parry+E:  ★ Fighter Signature Move\n" +
		"• W / Fwd-Dash+LMB:  Vaulting Leap Cleave\n" +
		"• E (or S + E):  Push Kick (S+E = Ankle Sweep)\n" +
		"• C / L / Parry+LMB:  Visor Pommel Bash\n" +
		"• WheelUp/V · WheelDn/X:  Thrust · Whirlwind\n" +
		"• 2x A/D or Shift:  Dash & Recovery Cancel\n" +
		"• Mobile Touch:  L-Stick Move · R-Wheel Swing · 2x Tap = ★Sig"
	)
	var r_body := _label(right_txt, 12, INK)
	r_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(r_body)

	vb.add_child(_divider())
	var back := _button("←  BACK TO MAIN MENU", func(_b): show_title_page("main"), 14)
	back.custom_minimum_size = Vector2(220, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(back)


func _build_settings_view() -> void:
	_settings_view = CenterContainer.new()
	_full_rect(_settings_view)
	_settings_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_view.visible = false
	_title_root.add_child(_settings_view)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.03, 0.04, 0.92), GOLD, 12))
	_settings_view.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	vb.add_child(_label("ARENA & GAMEPLAY SETTINGS", 28, Color(1.0, 0.84, 0.48), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("Changes apply live and save automatically", 12, Color(0.84, 0.76, 0.62), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_divider())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	vb.add_child(grid_center)

	for key in ["difficulty", "stage", "gore", "one_hit_sever", "cursor_aim", "touch", "strings", "sound"]:
		var b := _button(_setting_label(key), func(_b): _toggle_setting(key), 13)
		b.custom_minimum_size = Vector2(236, 38)
		grid.add_child(b)
		_settings_refreshers.append(func(): b.text = _setting_label(key))

	vb.add_child(_divider())
	var back := _button("←  BACK TO MAIN MENU", func(_b): show_title_page("main"), 14)
	back.custom_minimum_size = Vector2(220, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(back)


func _build_fighter_card(header: String, col: Color, on_cycle: Callable, on_loadout: Callable) -> Dictionary:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(258, 0)
	root.add_theme_constant_override("separation", 4)
	root.add_child(_label(header, 12, col, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	row.add_child(_button(" < ", func(_b): on_cycle.call(-1), 14))
	var name_lbl := _label("", 16, INK, HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.custom_minimum_size = Vector2(174, 0)
	row.add_child(name_lbl)
	row.add_child(_button(" > ", func(_b): on_cycle.call(1), 14))
	var blurb := _label("", 10, Color(0.85, 0.78, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(252, 28)
	root.add_child(blurb)
	var sig_name := _label("", 11, Color(1.0, 0.85, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(sig_name)
	var sig_desc := _label("", 10, Color(0.78, 0.86, 0.96), HORIZONTAL_ALIGNMENT_CENTER)
	sig_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sig_desc.custom_minimum_size = Vector2(252, 28)
	root.add_child(sig_desc)
	var lo_btn := _button("Weapon: SIGNATURE", func(_b): on_loadout.call(), 10)
	lo_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lo_btn.custom_minimum_size = Vector2(204, 0)
	root.add_child(lo_btn)
	var bars := {}
	for stat_name in ["HEALTH", "SPEED", "POWER", "ARMOUR"]:
		var line := HBoxContainer.new()
		var l := _label(stat_name.left(4), 9, Color(0.8, 0.72, 0.6))
		l.custom_minimum_size = Vector2(40, 0)
		line.add_child(l)
		var bar := _bar(GOLD, 6.0, 1.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		root.add_child(line)
		bars[stat_name] = bar
	return {"root": root, "name": name_lbl, "blurb": blurb, "sig_name": sig_name, "sig_desc": sig_desc, "loadout": lo_btn, "bars": bars}


func _fill_card(card: Dictionary, idx: int, loadout_id: String, is_solo_practice_slot: bool = false) -> void:
	var bars: Dictionary = card["bars"]
	var lo_btn: Button = card["loadout"]
	var lo_lbl: String = String(FighterStats.LOADOUT_LABELS.get(loadout_id, "SIGNATURE"))
	if is_solo_practice_slot:
		card["name"].text = "SOLO DOJO"
		card["blurb"].text = "Practice footwork, mouse arcs & combos alone with a single character."
		card["sig_name"].text = "★ OPEN SOLO STAGE"
		card["sig_desc"].text = "Optional Dummy toggle (Off/Static/Guard/Spar) & [R] instant reset in-game."
		lo_btn.text = "Dummy Weapon: " + lo_lbl
		for k in bars.keys():
			bars[k].value = 0.0
		return
	if idx < 0 or idx >= _roster.size():
		card["name"].text = "RANDOM"
		card["blurb"].text = "A mystery challenger steps onto the stage." if _sel_mode == "duel" else "Gauntlet rivals & loadouts scale each wave."
		card["sig_name"].text = "★ MYSTERY SIGNATURE"
		card["sig_desc"].text = "Each fighter wields a unique signature technique & combat passive."
		lo_btn.text = "Weapon: MIXED" if _sel_mode == "gauntlet" else ("Weapon: " + lo_lbl)
		for k in bars.keys():
			bars[k].value = 0.0
		return
	var s: Dictionary = _roster[idx]
	card["name"].text = String(s["display_name"])
	card["blurb"].text = String(s["blurb"])
	card["sig_name"].text = "★ " + String(s.get("signature_name", "SIGNATURE [G]"))
	card["sig_desc"].text = String(s.get("signature_desc", ""))
	lo_btn.text = "Weapon: " + lo_lbl
	var pwr_bonus := 0.14 if loadout_id in ["pollaxe", "warhammer", "halberd"] else (-0.04 if loadout_id in ["buckler", "katzbalger"] else 0.0)
	var spd_bonus := 0.14 if loadout_id == "katzbalger" else (-0.10 if loadout_id in ["pollaxe", "warhammer"] else 0.0)
	var arm_bonus := 0.18 if loadout_id == "buckler" else 0.0
	bars["HEALTH"].value = clampf((float(s["max_hp"]) - 70.0) / 60.0, 0.05, 1.0)
	bars["SPEED"].value = clampf((float(s["move_speed"]) - 220.0) / 140.0 + spd_bonus, 0.05, 1.0)
	bars["POWER"].value = clampf((float(s["damage_mult"]) * float(s["attack_speed"]) - 0.8) / 0.5 + pwr_bonus, 0.05, 1.0)
	var slots: Array = s["armored_slots"]
	bars["ARMOUR"].value = clampf((1.0 - float(s["armor_mult"])) * float(slots.size()) / 2.5 + arm_bonus, 0.0, 1.0)


func _refresh_title() -> void:
	_fill_card(_p1_card, _sel_p1, _sel_p1_loadout, false)
	_fill_card(_p2_card, _sel_p2, _sel_p2_loadout, _sel_mode == "practice")
	if _select_mode_lbl != null:
		if _sel_mode == "practice":
			_select_mode_lbl.text = "★  SOLO PRACTICE DOJO"
		elif _sel_mode == "gauntlet":
			_select_mode_lbl.text = "☠  ENDLESS GAUNTLET"
		else:
			_select_mode_lbl.text = "⚔  DUEL · BEST OF 3"
	if _title_p1_badge != null:
		_title_p1_badge.visible = _title_page == "select"
	if _title_p2_badge != null:
		_title_p2_badge.visible = _title_page == "select" and _sel_mode != "practice"
	if _vs_lbl != null:
		_vs_lbl.text = "★" if _sel_mode == "practice" else "VS"
	if _fight_btn != null:
		_fight_btn.text = "ENTER SOLO DOJO!" if _sel_mode == "practice" else "FIGHT!"
	for k in _mode_btns.keys():
		var b: Button = _mode_btns[k]
		var base := "DUEL · BEST OF 3"
		if k == "gauntlet":
			base = "GAUNTLET · ENDLESS"
		elif k == "practice":
			base = "PRACTICE · SOLO"
		b.text = ("▶ " + base + " ◀") if k == _sel_mode else base
	_title_best_lbl.text = "Gauntlet best: wave %d cleared" % _best_wave if _best_wave > 0 else ""
	_refresh_main_menu()


func _emit_preview(changed_tag: String) -> void:
	var preview_mode := "duel" if (_title_page != "select" and changed_tag == "init") else _sel_mode
	preview_changed.emit({
		"p1": _sel_p1,
		"p2": _sel_p2,
		"p1_loadout": _sel_p1_loadout,
		"p2_loadout": _sel_p2_loadout,
		"mode": preview_mode,
		"changed": changed_tag,
	})


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
	_emit_preview("p1" if is_p1 else "p2")


func _cycle_p1(d: int) -> void:
	_sel_p1 = posmod(_sel_p1 + d, _roster.size())
	_refresh_title()
	_emit_preview("p1")


func _cycle_p2(d: int) -> void:
	if _sel_mode == "gauntlet":
		_sel_p2 = -1
	else:
		# Cycle through RANDOM (-1) and every roster entry.
		_sel_p2 = posmod(_sel_p2 + 1 + d, _roster.size() + 1) - 1
	_refresh_title()
	_emit_preview("p2")


func _set_mode(m: String) -> void:
	_sel_mode = m
	if m == "gauntlet":
		_sel_p2 = -1
	_refresh_title()
	_emit_preview("mode")


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
	row.add_child(_button("RESUME", func(_b): resume_requested.emit(), 14))
	row.add_child(_button("RESTART ROUND", func(_b): restart_round_requested.emit(), 14))
	row.add_child(_button("CHANGE FIGHTERS", func(_b): change_fighters_requested.emit(), 14))
	row.add_child(_button("MAIN MENU", func(_b): title_requested.emit(), 14))
	var settings_center := CenterContainer.new()
	settings_center.add_child(_build_settings_grid())
	vb.add_child(settings_center)
	var help := _label("Swing through a wide arc for heavy limb-chopping cuts (gold trail); drive the point forward to thrust.\nPress G / Tab for your fighter's ★ SIGNATURE MOVE; Q to HALF-SWORD; F / Middle-Click to HURL your blade!\nHigh slashes snap marionette strings; kicks & guard-breaks against stage walls trigger CORNER CRUSH.", 12, Color(0.8, 0.74, 0.62), HORIZONTAL_ALIGNMENT_CENTER)
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
	_result_primary = _button("REMATCH", func(_b): rematch_requested.emit(), 15)
	row.add_child(_result_primary)
	row.add_child(_button("CHANGE FIGHTERS", func(_b): change_fighters_requested.emit(), 15))
	row.add_child(_button("MAIN MENU", func(_b): title_requested.emit(), 15))


# --- Clean translucent touch-wheel controller (no permanent buttons) ---

func _build_touch_controls() -> void:
	_touch_ctrl = MobileTouchController.new()
	_touch_ctrl.name = "MobileTouchController"
	_touch_ctrl.visible = false
	add_child(_touch_ctrl)
