@tool
class_name CharacterRigBuilder
extends RefCounted

## Procedural 2D Skeletal Rig & Animation Builder for Strings and Steel (Godot 4.x).
## Reads res://data/rig_metadata.json and builds complete reusable .tscn fighter scenes
## with Skeleton2D, Bone2D hierarchy, exact socket pivots, joint caps, z-ordering,
## PommelGripTarget for 2-bone off-hand IK, and an AnimationLibrary of combat moves.

const METADATA_PATH := "res://data/rig_metadata.json"
const OUTPUT_DIR := "res://scenes/fighters"


static func load_metadata() -> Dictionary:
	var file := FileAccess.open(METADATA_PATH, FileAccess.READ)
	if file == null:
		push_error("CharacterRigBuilder: Cannot open %s" % METADATA_PATH)
		return {}
	var json_text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CharacterRigBuilder: Invalid JSON in %s" % METADATA_PATH)
		return {}
	return parsed


static func build_all_fighters() -> Array[String]:
	var meta := load_metadata()
	if meta.is_empty():
		return []

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var fighters: Dictionary = meta.get("fighters", {})
	var parts: Dictionary = meta.get("parts", {})
	var saved_paths: Array[String] = []

	for fighter_key in fighters.keys():
		var fighter_cfg: Dictionary = fighters[fighter_key]
		var scene_path := "%s/%s.tscn" % [OUTPUT_DIR, _pascal_case(fighter_key)]
		var root := build_fighter_node(fighter_key, fighter_cfg, parts)
		if root == null:
			continue

		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err != OK:
			push_error("CharacterRigBuilder: Failed to pack %s (err=%d)" % [fighter_key, err])
			root.free()
			continue

		err = ResourceSaver.save(packed, scene_path)
		root.free()
		if err != OK:
			push_error("CharacterRigBuilder: Failed to save %s (err=%d)" % [scene_path, err])
			continue

		print("Built reusable character scene: ", scene_path)
		saved_paths.append(scene_path)

	return saved_paths


static func build_fighter_node(fighter_key: String, cfg: Dictionary, parts: Dictionary) -> Node2D:
	var root := Node2D.new()
	root.name = _pascal_case(fighter_key)

	var controller_script := load("res://scripts/FighterController.gd")
	if controller_script != null:
		root.set_script(controller_script)
	root.set("fighter_id", fighter_key)

	var part_ids: Dictionary = cfg.get("parts", {})
	var rig_scale: float = float(cfg.get("rig_scale", 0.68))
	var hand_baked: bool = bool(cfg.get("hand_baked", false))

	var skeleton := Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	skeleton.scale = Vector2(rig_scale, rig_scale)
	root.add_child(skeleton)
	skeleton.owner = root

	# ------------------------------------------------------------------
	# 1. PELVIS ROOT
	# ------------------------------------------------------------------
	var pelvis_spec := _spec(parts, part_ids.get("pelvis", ""))
	var torso_spec := _spec(parts, part_ids.get("torso", ""))
	var waist_vec := _socket_offset(pelvis_spec, "waist")
	var hip_l_vec := _socket_offset(pelvis_spec, "hipL")
	var hip_r_vec := _socket_offset(pelvis_spec, "hipR")
	var belt_vec := _socket_offset(pelvis_spec, "belt")

	var bone_pelvis := _create_bone(root, skeleton, "Pelvis", Vector2.ZERO, waist_vec)
	_attach_sprite(root, bone_pelvis, "PelvisSprite", pelvis_spec, 28)

	var scabbard_id: String = part_ids.get("scabbard", "")
	if scabbard_id != "" and parts.has(scabbard_id):
		var scabbard_spec := _spec(parts, scabbard_id)
		var scabbard_sp := _attach_sprite(root, bone_pelvis, "ScabbardSprite", scabbard_spec, 20)
		if scabbard_sp != null:
			scabbard_sp.position = belt_vec + Vector2(-2.0, -2.0)
			scabbard_sp.rotation = deg_to_rad(28.0)
			PuppetVisuals.set_base_tint(scabbard_sp, PuppetVisuals.SCABBARD_TINT)

	# ------------------------------------------------------------------
	# 2. LEGS (Thigh -> Shin -> Boot + Knee Cap)
	# ------------------------------------------------------------------
	var thigh_spec := _spec(parts, part_ids.get("thigh", ""))
	var shin_spec := _spec(parts, part_ids.get("shin", ""))
	var boot_spec := _spec(parts, part_ids.get("boot", ""))
	var poleyn_id: String = part_ids.get("poleyn", "")
	var poleyn_spec := _spec(parts, poleyn_id) if poleyn_id != "" else {}

	var thigh_end := _socket_offset(thigh_spec, "end")
	var shin_end := _socket_offset(shin_spec, "end")

	for side_cfg in [
		{"suffix": "L", "hip": hip_l_vec, "z_base": 10},
		{"suffix": "R", "hip": hip_r_vec, "z_base": 14},
	]:
		var suf: String = side_cfg["suffix"]
		var zb: int = int(side_cfg["z_base"])
		var is_rear := suf == "L"
		var b_thigh := _create_bone(root, bone_pelvis, "Thigh_" + suf, side_cfg["hip"], thigh_end)
		var sp_th := _attach_sprite(root, b_thigh, "ThighSprite_" + suf, thigh_spec, zb)

		var b_shin := _create_bone(root, b_thigh, "Shin_" + suf, thigh_end, shin_end)
		var sp_sh := _attach_sprite(root, b_shin, "ShinSprite_" + suf, shin_spec, zb + 2)

		var sp_pol: Sprite2D = null
		if not poleyn_spec.is_empty():
			sp_pol = _attach_sprite(root, b_shin, "PoleynSprite_" + suf, poleyn_spec, zb + 3)

		var knee_m := Marker2D.new()
		knee_m.name = "StringKnee" + suf
		knee_m.position = Vector2(0.0, 10.0)
		b_shin.add_child(knee_m)
		knee_m.owner = root

		var b_boot := _create_bone(root, b_shin, "Boot_" + suf, shin_end, Vector2(28.0, 0.0))
		var sp_bt := _attach_sprite(root, b_boot, "BootSprite_" + suf, boot_spec, zb + 1)

		if is_rear:
			for rsp in [sp_th, sp_sh, sp_pol, sp_bt]:
				PuppetVisuals.set_base_tint(rsp, PuppetVisuals.REAR_LIMB_TINT)

	# ------------------------------------------------------------------
	# 3. TORSO & HEAD & HAT
	# ------------------------------------------------------------------
	var neck_vec := _socket_offset(torso_spec, "neck")
	var sh_far_vec := _socket_offset(torso_spec, "shFar")
	var sh_near_vec := _socket_offset(torso_spec, "shNear")

	var bone_torso := _create_bone(root, bone_pelvis, "Torso", waist_vec, neck_vec)
	_attach_sprite(root, bone_torso, "TorsoSprite", torso_spec, 30)

	var head_spec := _spec(parts, part_ids.get("head", ""))
	var hat_vec := _socket_offset(head_spec, "hat")
	var bone_head := _create_bone(root, bone_torso, "Head", neck_vec, hat_vec)
	_attach_sprite(root, bone_head, "HeadSprite", head_spec, 36)

	var hat_id: String = part_ids.get("hat", "")
	var bone_hat := _create_bone(root, bone_head, "Hat", hat_vec, Vector2(0.0, -32.0))
	if hat_id != "" and parts.has(hat_id):
		var hat_spec := _spec(parts, hat_id)
		_attach_sprite(root, bone_hat, "HatSprite", hat_spec, 37)

	# ------------------------------------------------------------------
	# 4. ARMS (Left = Rear/Far, Right = Front/Near Sword Arm)
	# ------------------------------------------------------------------
	var ua_spec := _spec(parts, part_ids.get("upperarm", ""))
	var fa_spec := _spec(parts, part_ids.get("forearm", ""))
	var pauldron_id: String = part_ids.get("pauldron", "")
	var couter_id: String = part_ids.get("couter", "")
	var pauldron_spec := _spec(parts, pauldron_id) if pauldron_id != "" else {}
	var couter_spec := _spec(parts, couter_id) if couter_id != "" else {}

	var ua_end := _socket_offset(ua_spec, "end")
	var fa_end := _socket_offset(fa_spec, "grip") if hand_baked and fa_spec.get("sockets", {}).has("grip") else _socket_offset(fa_spec, "end")

	# Left Arm (far shoulder, behind torso & pelvis so elbow never pokes through stomach)
	var b_ua_l := _create_bone(root, bone_torso, "UpperArm_L", sh_far_vec, ua_end)
	var sp_ual := _attach_sprite(root, b_ua_l, "UpperArmSprite_L", ua_spec, 22)
	PuppetVisuals.set_base_tint(sp_ual, PuppetVisuals.REAR_LIMB_TINT)
	if not pauldron_spec.is_empty():
		var p_l := _attach_sprite(root, bone_torso, "PauldronSprite_L", pauldron_spec, 23)
		if p_l != null:
			p_l.position = sh_far_vec
			PuppetVisuals.set_base_tint(p_l, PuppetVisuals.REAR_LIMB_TINT)

	var b_fa_l := _create_bone(root, b_ua_l, "Forearm_L", ua_end, fa_end)
	var sp_fal := _attach_sprite(root, b_fa_l, "ForearmSprite_L", fa_spec, 24)
	PuppetVisuals.set_base_tint(sp_fal, PuppetVisuals.REAR_LIMB_TINT)
	if not couter_spec.is_empty():
		var sp_cl := _attach_sprite(root, b_fa_l, "CouterSprite_L", couter_spec, 25)
		PuppetVisuals.set_base_tint(sp_cl, PuppetVisuals.REAR_LIMB_TINT)

	var hand_l_id: String = part_ids.get("hand_l", "")
	var hand_l_len := 24.0
	var b_hand_l: Bone2D
	if not hand_baked and hand_l_id != "" and parts.has(hand_l_id):
		var h_l_spec := _spec(parts, hand_l_id)
		var g_off := _socket_offset(h_l_spec, "grip")
		hand_l_len = maxf(16.0, g_off.length())
		b_hand_l = _create_bone(root, b_fa_l, "Hand_L", fa_end, g_off)
		var sp_hl := _attach_sprite(root, b_hand_l, "HandSprite_L", h_l_spec, 46)
		PuppetVisuals.set_base_tint(sp_hl, PuppetVisuals.REAR_LIMB_TINT)
		var grip_m := Marker2D.new()
		grip_m.name = "GripCenter"
		grip_m.position = g_off
		b_hand_l.add_child(grip_m)
		grip_m.owner = root
	else:
		b_hand_l = _create_bone(root, b_fa_l, "Hand_L", fa_end, Vector2(0.0, hand_l_len))
		if hand_baked and not fa_spec.is_empty():
			# Crop just the cuff + fist region of the baked forearm sprite so the left fist wraps
			# cleanly over the pommel/blade (z=46) without duplicating a second bare hand or fake hilt!
			var fa_grip := _vec2(fa_spec.get("sockets", {}).get("grip", [22.0, 119.2]))
			var sp_hl_crop := _attach_sprite_with_pivot(root, b_hand_l, "HandSprite_L", fa_spec, 46, Vector2(fa_grip.x, fa_grip.y - 92.0))
			if sp_hl_crop != null:
				sp_hl_crop.region_enabled = true
				sp_hl_crop.region_rect = Rect2(0.0, 92.0, 43.0, 50.0)
				PuppetVisuals.set_base_tint(sp_hl_crop, PuppetVisuals.REAR_LIMB_TINT)
		var grip_m := Marker2D.new()
		grip_m.name = "GripCenter"
		grip_m.position = Vector2(0.0, 4.0)
		b_hand_l.add_child(grip_m)
		grip_m.owner = root

	# Right Arm (near shoulder, primary sword arm)
	var b_ua_r := _create_bone(root, bone_torso, "UpperArm_R", sh_near_vec, ua_end)
	_attach_sprite(root, b_ua_r, "UpperArmSprite_R", ua_spec, 40)
	if not pauldron_spec.is_empty():
		var p_r := _attach_sprite(root, bone_torso, "PauldronSprite_R", pauldron_spec, 43)
		if p_r != null:
			p_r.position = sh_near_vec

	var b_fa_r := _create_bone(root, b_ua_r, "Forearm_R", ua_end, fa_end)
	_attach_sprite(root, b_fa_r, "ForearmSprite_R", fa_spec, 48)
	if not couter_spec.is_empty():
		_attach_sprite(root, b_fa_r, "CouterSprite_R", couter_spec, 50)

	var hand_r_id: String = part_ids.get("hand_r", "")
	var weapon_mount_pos := Vector2.ZERO
	var b_hand_r: Bone2D
	if not hand_baked and hand_r_id != "" and parts.has(hand_r_id):
		var h_r_spec := _spec(parts, hand_r_id)
		var grip_off := _socket_offset(h_r_spec, "grip")
		b_hand_r = _create_bone(root, b_fa_r, "Hand_R", fa_end, grip_off)
		_attach_sprite(root, b_hand_r, "HandSprite_R", h_r_spec, 46)
		weapon_mount_pos = grip_off
	else:
		b_hand_r = _create_bone(root, b_fa_r, "Hand_R", fa_end, Vector2(0.0, 20.0))
		weapon_mount_pos = Vector2.ZERO

	# ------------------------------------------------------------------
	# 5. WEAPON, SWEPT-HILT / CROSSGUARD OVERLAY & POMMEL TARGET SOCKET
	# ------------------------------------------------------------------
	var sword_id: String = part_ids.get("weapon", "")
	if sword_id != "" and parts.has(sword_id):
		var sw_spec := _spec(parts, sword_id)
		var sw_sockets: Dictionary = sw_spec.get("sockets", {})
		var sw_scale := float(sw_spec.get("scale", 1.0))
		var sw_grip_front := _vec2(sw_sockets.get("gripFront", sw_spec.get("pivot", [0, 0])))
		var sw_grip_back := _vec2(sw_sockets.get("gripBack", sw_sockets.get("pommel", [0, 0])))
		var sw_guard := _vec2(sw_sockets.get("guard", [110, 52]))
		var sw_tip := _vec2(sw_sockets.get("tip", [300, 52]))

		var tip_vec := (sw_tip - sw_grip_front) * sw_scale
		var bone_weapon := _create_bone(root, b_hand_r, "WeaponBone", weapon_mount_pos, tip_vec)

		var sw_sprite := _attach_sprite_with_pivot(root, bone_weapon, "WeaponSprite", sw_spec, 45, sw_grip_front)
		if sw_sprite != null:
			var guard_sp := _attach_sprite_with_pivot(root, bone_weapon, "WeaponGuardSprite", sw_spec, 49, sw_grip_front)
			if guard_sp != null:
				var grect: Array = sw_spec.get("guardOverlayRect", [])
				if grect.size() >= 4:
					var rx := float(grect[0])
					var ry := float(grect[1])
					guard_sp.region_enabled = true
					guard_sp.region_rect = Rect2(rx, ry, float(grect[2]), float(grect[3]))
					guard_sp.offset = Vector2(rx, ry) - sw_grip_front
					guard_sp.visible = true
				else:
					guard_sp.visible = false

			var pommel_marker := Marker2D.new()
			pommel_marker.name = "PommelGripTarget"
			pommel_marker.position = (sw_grip_back - sw_grip_front) * sw_scale
			bone_weapon.add_child(pommel_marker)
			pommel_marker.owner = root

			var guard_marker := Marker2D.new()
			guard_marker.name = "BladeGuardMarker"
			guard_marker.position = (sw_guard - sw_grip_front) * sw_scale
			bone_weapon.add_child(guard_marker)
			guard_marker.owner = root

			var tip_marker := Marker2D.new()
			tip_marker.name = "BladeTipMarker"
			tip_marker.position = tip_vec
			bone_weapon.add_child(tip_marker)
			tip_marker.owner = root

	# ------------------------------------------------------------------
	# 6. MARIONETTE ATTACHMENT MARKERS
	# ------------------------------------------------------------------
	for marker_cfg in [
		["StringHead", bone_head, Vector2(0.0, -45.0)],
		["StringHandR", b_hand_r, Vector2.ZERO],
		["StringHandL", b_fa_l, fa_end],
	]:
		var m := Marker2D.new()
		m.name = marker_cfg[0]
		m.position = marker_cfg[2]
		marker_cfg[1].add_child(m)
		m.owner = root

	# ------------------------------------------------------------------
	# 7. PROCEDURAL ANIMATION LIBRARY
	# ------------------------------------------------------------------
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	anim_player.owner = root
	_build_animation_library(anim_player)

	return root


static func _create_bone(owner_root: Node, parent: Node, bone_name: String, pos: Vector2, tip_vec: Vector2) -> Bone2D:
	var bone := Bone2D.new()
	bone.name = bone_name
	bone.position = pos
	bone.set_autocalculate_length_and_angle(false)
	var len_val := maxf(14.0, tip_vec.length())
	var ang_val := tip_vec.angle() if tip_vec.length() > 0.5 else PI * 0.5
	bone.set_length(len_val)
	bone.set_bone_angle(ang_val)
	parent.add_child(bone)
	bone.owner = owner_root
	bone.set_rest(bone.transform)
	return bone


static func _attach_sprite(owner_root: Node, parent: Node, node_name: String, spec: Dictionary, z_idx: int) -> Sprite2D:
	if spec.is_empty():
		return null
	var pivot := _vec2(spec.get("pivot", [0, 0]))
	return _attach_sprite_with_pivot(owner_root, parent, node_name, spec, z_idx, pivot)


static func _attach_sprite_with_pivot(owner_root: Node, parent: Node, node_name: String, spec: Dictionary, z_idx: int, custom_pivot: Vector2) -> Sprite2D:
	var tex_path: String = spec.get("texture", "")
	if tex_path == "":
		return null

	var tex := _load_texture(tex_path)
	if tex == null:
		push_warning("CharacterRigBuilder: Could not load texture %s" % tex_path)
		return null

	var sp := Sprite2D.new()
	sp.name = node_name
	sp.texture = tex
	sp.centered = false
	sp.offset = -custom_pivot
	var s := float(spec.get("scale", 1.0))
	sp.scale = Vector2(s, s)
	sp.z_index = z_idx
	PuppetVisuals.apply_ink_material(sp)
	parent.add_child(sp)
	sp.owner = owner_root
	return sp


static func _load_texture(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res := ResourceLoader.load(res_path)
		if res is Texture2D:
			return res
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs_path)
	if img != null and not img.is_empty():
		return ImageTexture.create_from_image(img)
	return null


static func _build_animation_library(anim_player: AnimationPlayer) -> void:
	var lib := AnimationLibrary.new()

	# IDLE (Living Coiled HEMA Guard with figure-8 point weave, breathing & ankle weight shift)
	lib.add_animation("idle", _make_pose_anim(1.20, Animation.LOOP_LINEAR, [
		[0.0, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.5),
			"Torso:rotation": deg_to_rad(-5.5), "Head:rotation": deg_to_rad(3.5), "Hat:rotation": deg_to_rad(-2.0),
			"Thigh_L:rotation": deg_to_rad(25.0), "Shin_L:rotation": deg_to_rad(-19.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-25.0), "Shin_R:rotation": deg_to_rad(23.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-54.0), "Forearm_R:rotation": deg_to_rad(-54.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
		[0.30, {
			"Pelvis:position:y": 5.5, "Pelvis:rotation": deg_to_rad(4.8),
			"Torso:rotation": deg_to_rad(-3.2), "Head:rotation": deg_to_rad(1.2), "Hat:rotation": deg_to_rad(1.8),
			"Thigh_L:rotation": deg_to_rad(27.5), "Shin_L:rotation": deg_to_rad(-22.0), "Boot_L:rotation": deg_to_rad(-5.5),
			"Thigh_R:rotation": deg_to_rad(-27.5), "Shin_R:rotation": deg_to_rad(25.5), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-50.0), "Forearm_R:rotation": deg_to_rad(-58.0), "Hand_R:rotation": deg_to_rad(12.0), "WeaponBone:rotation": deg_to_rad(-24.0),
		}],
		[0.60, {
			"Pelvis:position:y": 8.5, "Pelvis:rotation": deg_to_rad(5.4),
			"Torso:rotation": deg_to_rad(-1.5), "Head:rotation": deg_to_rad(-1.5), "Hat:rotation": deg_to_rad(4.5),
			"Thigh_L:rotation": deg_to_rad(30.0), "Shin_L:rotation": deg_to_rad(-25.0), "Boot_L:rotation": deg_to_rad(-5.0),
			"Thigh_R:rotation": deg_to_rad(-30.0), "Shin_R:rotation": deg_to_rad(28.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-46.0), "Forearm_R:rotation": deg_to_rad(-61.0), "Hand_R:rotation": deg_to_rad(13.5), "WeaponBone:rotation": deg_to_rad(-20.0),
		}],
		[0.90, {
			"Pelvis:position:y": 4.8, "Pelvis:rotation": deg_to_rad(4.0),
			"Torso:rotation": deg_to_rad(-4.2), "Head:rotation": deg_to_rad(1.8), "Hat:rotation": deg_to_rad(0.5),
			"Thigh_L:rotation": deg_to_rad(26.5), "Shin_L:rotation": deg_to_rad(-20.5), "Boot_L:rotation": deg_to_rad(-5.8),
			"Thigh_R:rotation": deg_to_rad(-26.5), "Shin_R:rotation": deg_to_rad(24.5), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-51.0), "Forearm_R:rotation": deg_to_rad(-56.0), "Hand_R:rotation": deg_to_rad(11.0), "WeaponBone:rotation": deg_to_rad(-26.0),
		}],
		[1.20, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.5),
			"Torso:rotation": deg_to_rad(-5.5), "Head:rotation": deg_to_rad(3.5), "Hat:rotation": deg_to_rad(-2.0),
			"Thigh_L:rotation": deg_to_rad(25.0), "Shin_L:rotation": deg_to_rad(-19.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-25.0), "Shin_R:rotation": deg_to_rad(23.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-54.0), "Forearm_R:rotation": deg_to_rad(-54.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# WALK (Crisp Aggressive Fencing Advance — 5-pose heel plant, weight drop, push-off & knee pass)
	lib.add_animation("walk", _make_pose_anim(0.50, Animation.LOOP_LINEAR, [
		[0.0, {
			"Pelvis:position:y": 5.0, "Pelvis:rotation": deg_to_rad(7.0),
			"Torso:rotation": deg_to_rad(5.5), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(-7.5),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-24.0),
			"Thigh_R:rotation": deg_to_rad(-40.0), "Shin_R:rotation": deg_to_rad(28.0), "Boot_R:rotation": deg_to_rad(8.0),
			"UpperArm_R:rotation": deg_to_rad(-43.0), "Forearm_R:rotation": deg_to_rad(-65.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-22.0),
		}],
		[0.125, {
			"Pelvis:position:y": -6.0, "Pelvis:rotation": deg_to_rad(5.0),
			"Torso:rotation": deg_to_rad(7.5), "Head:rotation": deg_to_rad(-7.5), "Hat:rotation": deg_to_rad(7.0),
			"Thigh_L:rotation": deg_to_rad(2.0), "Shin_L:rotation": deg_to_rad(-42.0), "Boot_L:rotation": deg_to_rad(26.0),
			"Thigh_R:rotation": deg_to_rad(-10.0), "Shin_R:rotation": deg_to_rad(10.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-53.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.5), "WeaponBone:rotation": deg_to_rad(-30.0),
		}],
		[0.25, {
			"Pelvis:position:y": 5.0, "Pelvis:rotation": deg_to_rad(7.0),
			"Torso:rotation": deg_to_rad(5.5), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(-7.5),
			"Thigh_L:rotation": deg_to_rad(-36.0), "Shin_L:rotation": deg_to_rad(26.0), "Boot_L:rotation": deg_to_rad(8.0),
			"Thigh_R:rotation": deg_to_rad(34.0), "Shin_R:rotation": deg_to_rad(-12.0), "Boot_R:rotation": deg_to_rad(-22.0),
			"UpperArm_R:rotation": deg_to_rad(-41.0), "Forearm_R:rotation": deg_to_rad(-63.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-21.0),
		}],
		[0.375, {
			"Pelvis:position:y": -6.0, "Pelvis:rotation": deg_to_rad(5.0),
			"Torso:rotation": deg_to_rad(7.5), "Head:rotation": deg_to_rad(-7.5), "Hat:rotation": deg_to_rad(7.0),
			"Thigh_L:rotation": deg_to_rad(-8.0), "Shin_L:rotation": deg_to_rad(8.0), "Boot_L:rotation": deg_to_rad(0.0),
			"Thigh_R:rotation": deg_to_rad(4.0), "Shin_R:rotation": deg_to_rad(-44.0), "Boot_R:rotation": deg_to_rad(26.0),
			"UpperArm_R:rotation": deg_to_rad(-53.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.5), "WeaponBone:rotation": deg_to_rad(-30.0),
		}],
		[0.50, {
			"Pelvis:position:y": 5.0, "Pelvis:rotation": deg_to_rad(7.0),
			"Torso:rotation": deg_to_rad(5.5), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(-7.5),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-24.0),
			"Thigh_R:rotation": deg_to_rad(-40.0), "Shin_R:rotation": deg_to_rad(28.0), "Boot_R:rotation": deg_to_rad(8.0),
			"UpperArm_R:rotation": deg_to_rad(-43.0), "Forearm_R:rotation": deg_to_rad(-65.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-22.0),
		}],
	]))

	# WALK_BACK (5-Keyframe Coiled Fencing Retreat — back-toe reach, low hips & front-heel draw!)
	lib.add_animation("walk_back", _make_pose_anim(0.50, Animation.LOOP_LINEAR, [
		[0.0, {
			"Pelvis:position:y": 7.0, "Pelvis:rotation": deg_to_rad(-4.0),
			"Torso:rotation": deg_to_rad(-8.0), "Head:rotation": deg_to_rad(7.5), "Hat:rotation": deg_to_rad(6.0),
			"Thigh_L:rotation": deg_to_rad(42.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-12.0),
			"Thigh_R:rotation": deg_to_rad(-16.0), "Shin_R:rotation": deg_to_rad(14.0), "Boot_R:rotation": deg_to_rad(10.0),
			"UpperArm_R:rotation": deg_to_rad(-58.0), "Forearm_R:rotation": deg_to_rad(-50.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-18.0),
		}],
		[0.125, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(-2.5),
			"Torso:rotation": deg_to_rad(-6.0), "Head:rotation": deg_to_rad(5.5), "Hat:rotation": deg_to_rad(-2.0),
			"Thigh_L:rotation": deg_to_rad(26.0), "Shin_L:rotation": deg_to_rad(-38.0), "Boot_L:rotation": deg_to_rad(14.0),
			"Thigh_R:rotation": deg_to_rad(-28.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(-8.0),
			"UpperArm_R:rotation": deg_to_rad(-53.0), "Forearm_R:rotation": deg_to_rad(-54.0), "Hand_R:rotation": deg_to_rad(9.0), "WeaponBone:rotation": deg_to_rad(-23.0),
		}],
		[0.25, {
			"Pelvis:position:y": 7.0, "Pelvis:rotation": deg_to_rad(-3.5),
			"Torso:rotation": deg_to_rad(-7.5), "Head:rotation": deg_to_rad(7.0), "Hat:rotation": deg_to_rad(-5.0),
			"Thigh_L:rotation": deg_to_rad(8.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(8.0),
			"Thigh_R:rotation": deg_to_rad(-38.0), "Shin_R:rotation": deg_to_rad(32.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-50.0), "Forearm_R:rotation": deg_to_rad(-57.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-27.0),
		}],
		[0.375, {
			"Pelvis:position:y": 1.5, "Pelvis:rotation": deg_to_rad(-2.5),
			"Torso:rotation": deg_to_rad(-6.0), "Head:rotation": deg_to_rad(5.5), "Hat:rotation": deg_to_rad(3.0),
			"Thigh_L:rotation": deg_to_rad(28.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-14.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(36.0), "Boot_R:rotation": deg_to_rad(12.0),
			"UpperArm_R:rotation": deg_to_rad(-55.0), "Forearm_R:rotation": deg_to_rad(-52.0), "Hand_R:rotation": deg_to_rad(9.0), "WeaponBone:rotation": deg_to_rad(-21.0),
		}],
		[0.50, {
			"Pelvis:position:y": 7.0, "Pelvis:rotation": deg_to_rad(-4.0),
			"Torso:rotation": deg_to_rad(-8.0), "Head:rotation": deg_to_rad(7.5), "Hat:rotation": deg_to_rad(6.0),
			"Thigh_L:rotation": deg_to_rad(42.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-12.0),
			"Thigh_R:rotation": deg_to_rad(-16.0), "Shin_R:rotation": deg_to_rad(14.0), "Boot_R:rotation": deg_to_rad(10.0),
			"UpperArm_R:rotation": deg_to_rad(-58.0), "Forearm_R:rotation": deg_to_rad(-50.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-18.0),
		}],
	]))

	# DASH_FWD & DASH_BACK (3-Keyframe Explosive Low-Profile Jet & Plant)
	lib.add_animation("dash_fwd", _make_pose_anim(0.20, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(10.0),
			"Torso:rotation": deg_to_rad(16.0), "Head:rotation": deg_to_rad(-14.0), "Hat:rotation": deg_to_rad(-18.0),
			"Thigh_L:rotation": deg_to_rad(40.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-18.0),
			"Thigh_R:rotation": deg_to_rad(-44.0), "Shin_R:rotation": deg_to_rad(42.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-38.0), "Forearm_R:rotation": deg_to_rad(-64.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-34.0),
		}],
		[0.07, {
			"Pelvis:position:y": 24.0, "Pelvis:rotation": deg_to_rad(17.0),
			"Torso:rotation": deg_to_rad(25.0), "Head:rotation": deg_to_rad(-22.0), "Hat:rotation": deg_to_rad(-26.0),
			"Thigh_L:rotation": deg_to_rad(58.0), "Shin_L:rotation": deg_to_rad(-12.0), "Boot_L:rotation": deg_to_rad(-32.0),
			"Thigh_R:rotation": deg_to_rad(-62.0), "Shin_R:rotation": deg_to_rad(58.0), "Boot_R:rotation": deg_to_rad(8.0),
			"UpperArm_R:rotation": deg_to_rad(-28.0), "Forearm_R:rotation": deg_to_rad(-72.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(-42.0),
		}],
		[0.20, {
			"Pelvis:position:y": 6.0, "Pelvis:rotation": deg_to_rad(6.0),
			"Torso:rotation": deg_to_rad(6.0), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(10.0),
			"Thigh_L:rotation": deg_to_rad(28.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-8.0),
			"Thigh_R:rotation": deg_to_rad(-28.0), "Shin_R:rotation": deg_to_rad(24.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	lib.add_animation("dash_back", _make_pose_anim(0.20, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 12.0, "Pelvis:rotation": deg_to_rad(-9.0),
			"Torso:rotation": deg_to_rad(-14.0), "Head:rotation": deg_to_rad(12.0), "Hat:rotation": deg_to_rad(14.0),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-32.0), "Boot_L:rotation": deg_to_rad(4.0),
			"Thigh_R:rotation": deg_to_rad(-16.0), "Shin_R:rotation": deg_to_rad(12.0), "Boot_R:rotation": deg_to_rad(-12.0),
			"UpperArm_R:rotation": deg_to_rad(-64.0), "Forearm_R:rotation": deg_to_rad(-50.0), "Hand_R:rotation": deg_to_rad(6.0), "WeaponBone:rotation": deg_to_rad(10.0),
		}],
		[0.07, {
			"Pelvis:position:y": 20.0, "Pelvis:rotation": deg_to_rad(-15.0),
			"Torso:rotation": deg_to_rad(-22.0), "Head:rotation": deg_to_rad(18.0), "Hat:rotation": deg_to_rad(24.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-44.0), "Boot_L:rotation": deg_to_rad(10.0),
			"Thigh_R:rotation": deg_to_rad(-6.0), "Shin_R:rotation": deg_to_rad(4.0), "Boot_R:rotation": deg_to_rad(-24.0),
			"UpperArm_R:rotation": deg_to_rad(-72.0), "Forearm_R:rotation": deg_to_rad(-46.0), "Hand_R:rotation": deg_to_rad(6.0), "WeaponBone:rotation": deg_to_rad(22.0),
		}],
		[0.20, {
			"Pelvis:position:y": 4.0, "Pelvis:rotation": deg_to_rad(-2.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(4.0), "Hat:rotation": deg_to_rad(-6.0),
			"Thigh_L:rotation": deg_to_rad(25.0), "Shin_L:rotation": deg_to_rad(-19.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-25.0), "Shin_R:rotation": deg_to_rad(23.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SLASH_HIGH (6-Keyframe Explosive Oberhau Cleave: Coil -> Whip Snap -> Overshoot -> Settle)
	lib.add_animation("slash_high", _make_pose_anim(0.46, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
		[0.105, {
			"Pelvis:position:y": -6.0, "Pelvis:rotation": deg_to_rad(-10.0),
			"Torso:rotation": deg_to_rad(-24.0), "Head:rotation": deg_to_rad(20.0), "Hat:rotation": deg_to_rad(-18.0),
			"Thigh_L:rotation": deg_to_rad(34.0), "Shin_L:rotation": deg_to_rad(-28.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-12.0), "Shin_R:rotation": deg_to_rad(14.0), "Boot_R:rotation": deg_to_rad(-6.0),
			"UpperArm_R:rotation": deg_to_rad(-138.0), "Forearm_R:rotation": deg_to_rad(-50.0), "Hand_R:rotation": deg_to_rad(-18.0), "WeaponBone:rotation": deg_to_rad(-64.0),
		}],
		[0.175, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(11.0),
			"Torso:rotation": deg_to_rad(19.0), "Head:rotation": deg_to_rad(-15.0), "Hat:rotation": deg_to_rad(14.0),
			"Thigh_L:rotation": deg_to_rad(40.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-22.0),
			"Thigh_R:rotation": deg_to_rad(-44.0), "Shin_R:rotation": deg_to_rad(40.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-58.0), "Forearm_R:rotation": deg_to_rad(-8.0), "Hand_R:rotation": deg_to_rad(14.0), "WeaponBone:rotation": deg_to_rad(38.0),
		}],
		[0.235, {
			"Pelvis:position:y": 21.0, "Pelvis:rotation": deg_to_rad(15.0),
			"Torso:rotation": deg_to_rad(24.0), "Head:rotation": deg_to_rad(-20.0), "Hat:rotation": deg_to_rad(24.0),
			"Thigh_L:rotation": deg_to_rad(45.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-28.0),
			"Thigh_R:rotation": deg_to_rad(-52.0), "Shin_R:rotation": deg_to_rad(48.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-34.0), "Forearm_R:rotation": deg_to_rad(-5.0), "Hand_R:rotation": deg_to_rad(20.0), "WeaponBone:rotation": deg_to_rad(58.0),
		}],
		[0.32, {
			"Pelvis:position:y": 15.0, "Pelvis:rotation": deg_to_rad(10.0),
			"Torso:rotation": deg_to_rad(15.0), "Head:rotation": deg_to_rad(-11.0), "Hat:rotation": deg_to_rad(8.0),
			"Thigh_L:rotation": deg_to_rad(35.0), "Shin_L:rotation": deg_to_rad(-15.0), "Boot_L:rotation": deg_to_rad(-16.0),
			"Thigh_R:rotation": deg_to_rad(-39.0), "Shin_R:rotation": deg_to_rad(35.0), "Boot_R:rotation": deg_to_rad(3.0),
			"UpperArm_R:rotation": deg_to_rad(-44.0), "Forearm_R:rotation": deg_to_rad(-18.0), "Hand_R:rotation": deg_to_rad(14.0), "WeaponBone:rotation": deg_to_rad(38.0),
		}],
		[0.46, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# THRUST (5-Keyframe Explosive Split-Lunge Point Drive with Extension Lock)
	lib.add_animation("thrust", _make_pose_anim(0.42, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
		[0.085, {
			"Pelvis:position:y": 9.0, "Pelvis:rotation": deg_to_rad(-7.0),
			"Torso:rotation": deg_to_rad(-14.0), "Head:rotation": deg_to_rad(14.0), "Hat:rotation": deg_to_rad(-12.0),
			"Thigh_L:rotation": deg_to_rad(32.0), "Shin_L:rotation": deg_to_rad(-28.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-16.0), "Shin_R:rotation": deg_to_rad(16.0), "Boot_R:rotation": deg_to_rad(-2.0),
			"UpperArm_R:rotation": deg_to_rad(26.0), "Forearm_R:rotation": deg_to_rad(-108.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(90.0),
		}],
		[0.165, {
			"Pelvis:position:y": 24.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(21.0), "Head:rotation": deg_to_rad(-20.0), "Hat:rotation": deg_to_rad(16.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-34.0),
			"Thigh_R:rotation": deg_to_rad(-56.0), "Shin_R:rotation": deg_to_rad(52.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-106.0), "Forearm_R:rotation": deg_to_rad(-6.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(80.0),
		}],
		[0.24, {
			"Pelvis:position:y": 28.0, "Pelvis:rotation": deg_to_rad(16.0),
			"Torso:rotation": deg_to_rad(23.0), "Head:rotation": deg_to_rad(-22.0), "Hat:rotation": deg_to_rad(20.0),
			"Thigh_L:rotation": deg_to_rad(52.0), "Shin_L:rotation": deg_to_rad(-8.0), "Boot_L:rotation": deg_to_rad(-38.0),
			"Thigh_R:rotation": deg_to_rad(-60.0), "Shin_R:rotation": deg_to_rad(56.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-110.0), "Forearm_R:rotation": deg_to_rad(-4.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(82.0),
		}],
		[0.42, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# PARRY (Forward High Cross-Guard Block covering torso, throat & head)
	lib.add_animation("parry", _make_pose_anim(0.40, Animation.LOOP_LINEAR, [
		[0.0, {
			"Pelvis:position:y": 8.0, "Pelvis:rotation": deg_to_rad(-2.0),
			"Torso:rotation": deg_to_rad(-4.0), "Head:rotation": deg_to_rad(5.0), "Hat:rotation": deg_to_rad(-4.0),
			"Thigh_L:rotation": deg_to_rad(28.0), "Shin_L:rotation": deg_to_rad(-26.0), "Boot_L:rotation": deg_to_rad(-2.0),
			"Thigh_R:rotation": deg_to_rad(-28.0), "Shin_R:rotation": deg_to_rad(28.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-42.0), "Forearm_R:rotation": deg_to_rad(-42.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(34.0),
		}],
		[0.2, {
			"Pelvis:position:y": 10.0, "Pelvis:rotation": deg_to_rad(-3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(6.0), "Hat:rotation": deg_to_rad(-2.0),
			"Thigh_L:rotation": deg_to_rad(30.0), "Shin_L:rotation": deg_to_rad(-28.0), "Boot_L:rotation": deg_to_rad(-2.0),
			"Thigh_R:rotation": deg_to_rad(-30.0), "Shin_R:rotation": deg_to_rad(30.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-45.0), "Forearm_R:rotation": deg_to_rad(-44.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(36.0),
		}],
		[0.40, {
			"Pelvis:position:y": 8.0, "Pelvis:rotation": deg_to_rad(-2.0),
			"Torso:rotation": deg_to_rad(-4.0), "Head:rotation": deg_to_rad(5.0), "Hat:rotation": deg_to_rad(-4.0),
			"Thigh_L:rotation": deg_to_rad(28.0), "Shin_L:rotation": deg_to_rad(-26.0), "Boot_L:rotation": deg_to_rad(-2.0),
			"Thigh_R:rotation": deg_to_rad(-28.0), "Shin_R:rotation": deg_to_rad(28.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-42.0), "Forearm_R:rotation": deg_to_rad(-42.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(34.0),
		}],
	]))

	# HURT (Snappy Hit Stagger)
	lib.add_animation("hurt", _make_pose_anim(0.28, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
		[0.08, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(-18.0),
			"Torso:rotation": deg_to_rad(-24.0), "Head:rotation": deg_to_rad(-26.0), "Hat:rotation": deg_to_rad(-24.0),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-30.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-10.0), "Shin_R:rotation": deg_to_rad(20.0), "Boot_R:rotation": deg_to_rad(-10.0),
			"UpperArm_R:rotation": deg_to_rad(-16.0), "Forearm_R:rotation": deg_to_rad(-74.0), "Hand_R:rotation": deg_to_rad(22.0), "WeaponBone:rotation": deg_to_rad(-62.0),
		}],
		[0.28, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# DEATH (Marionette Strings Slump Collapse)
	lib.add_animation("death", _make_pose_anim(0.85, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 0.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
			"UpperArm_L:rotation": deg_to_rad(-42.0), "Forearm_L:rotation": deg_to_rad(-48.0),
		}],
		[0.32, {
			"Pelvis:position:y": 68.0, "Pelvis:rotation": deg_to_rad(-38.0),
			"Torso:rotation": deg_to_rad(-28.0), "Head:rotation": deg_to_rad(-32.0), "Hat:rotation": deg_to_rad(-25.0),
			"Thigh_L:rotation": deg_to_rad(-12.0), "Shin_L:rotation": deg_to_rad(65.0), "Boot_L:rotation": deg_to_rad(25.0),
			"Thigh_R:rotation": deg_to_rad(-48.0), "Shin_R:rotation": deg_to_rad(88.0), "Boot_R:rotation": deg_to_rad(18.0),
			"UpperArm_R:rotation": deg_to_rad(12.0), "Forearm_R:rotation": deg_to_rad(-25.0), "Hand_R:rotation": deg_to_rad(15.0), "WeaponBone:rotation": deg_to_rad(25.0),
			"UpperArm_L:rotation": deg_to_rad(-55.0), "Forearm_L:rotation": deg_to_rad(-30.0),
		}],
		[0.85, {
			"Pelvis:position:y": 128.0, "Pelvis:rotation": deg_to_rad(-84.0),
			"Torso:rotation": deg_to_rad(-10.0), "Head:rotation": deg_to_rad(24.0), "Hat:rotation": deg_to_rad(14.0),
			"Thigh_L:rotation": deg_to_rad(10.0), "Shin_L:rotation": deg_to_rad(18.0), "Boot_L:rotation": deg_to_rad(26.0),
			"Thigh_R:rotation": deg_to_rad(-8.0), "Shin_R:rotation": deg_to_rad(30.0), "Boot_R:rotation": deg_to_rad(20.0),
			"UpperArm_R:rotation": deg_to_rad(46.0), "Forearm_R:rotation": deg_to_rad(22.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(18.0),
			"UpperArm_L:rotation": deg_to_rad(28.0), "Forearm_L:rotation": deg_to_rad(18.0),
		}],
	]))

	# SLASH_LOW (5-Keyframe Explosive Unterhau Rising Scythe Cut)
	lib.add_animation("slash_low", _make_pose_anim(0.45, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
		[0.105, {
			"Pelvis:position:y": 21.0, "Pelvis:rotation": deg_to_rad(-11.0),
			"Torso:rotation": deg_to_rad(-16.0), "Head:rotation": deg_to_rad(12.0), "Hat:rotation": deg_to_rad(-12.0),
			"Thigh_L:rotation": deg_to_rad(38.0), "Shin_L:rotation": deg_to_rad(-34.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-34.0), "Shin_R:rotation": deg_to_rad(34.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(30.0), "Forearm_R:rotation": deg_to_rad(-20.0), "Hand_R:rotation": deg_to_rad(16.0), "WeaponBone:rotation": deg_to_rad(60.0),
		}],
		[0.18, {
			"Pelvis:position:y": 6.0, "Pelvis:rotation": deg_to_rad(10.0),
			"Torso:rotation": deg_to_rad(14.0), "Head:rotation": deg_to_rad(-10.0), "Hat:rotation": deg_to_rad(12.0),
			"Thigh_L:rotation": deg_to_rad(35.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-14.0),
			"Thigh_R:rotation": deg_to_rad(-42.0), "Shin_R:rotation": deg_to_rad(38.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-68.0), "Forearm_R:rotation": deg_to_rad(-14.0), "Hand_R:rotation": deg_to_rad(4.0), "WeaponBone:rotation": deg_to_rad(36.0),
		}],
		[0.245, {
			"Pelvis:position:y": -2.0, "Pelvis:rotation": deg_to_rad(15.0),
			"Torso:rotation": deg_to_rad(18.0), "Head:rotation": deg_to_rad(-14.0), "Hat:rotation": deg_to_rad(20.0),
			"Thigh_L:rotation": deg_to_rad(34.0), "Shin_L:rotation": deg_to_rad(-16.0), "Boot_L:rotation": deg_to_rad(-18.0),
			"Thigh_R:rotation": deg_to_rad(-46.0), "Shin_R:rotation": deg_to_rad(42.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-108.0), "Forearm_R:rotation": deg_to_rad(-22.0), "Hand_R:rotation": deg_to_rad(-2.0), "WeaponBone:rotation": deg_to_rad(18.0),
		}],
		[0.45, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# PARRY_LOW (Alber / Lower Hanging Block covering pelvis, thighs & shins)
	lib.add_animation("parry_low", _make_pose_anim(0.40, Animation.LOOP_LINEAR, [
		[0.0, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(-2.0),
			"Torso:rotation": deg_to_rad(6.0), "Head:rotation": deg_to_rad(-4.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(34.0), "Shin_L:rotation": deg_to_rad(-30.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-32.0), "Shin_R:rotation": deg_to_rad(32.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-36.0), "Forearm_R:rotation": deg_to_rad(-34.0), "Hand_R:rotation": deg_to_rad(6.0), "WeaponBone:rotation": deg_to_rad(96.0),
		}],
		[0.40, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(-2.0),
			"Torso:rotation": deg_to_rad(6.0), "Head:rotation": deg_to_rad(-4.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(34.0), "Shin_L:rotation": deg_to_rad(-30.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-32.0), "Shin_R:rotation": deg_to_rad(32.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-36.0), "Forearm_R:rotation": deg_to_rad(-34.0), "Hand_R:rotation": deg_to_rad(6.0), "WeaponBone:rotation": deg_to_rad(96.0),
		}],
	]))

	# PARRY_RECOIL (Wide Open Stagger After Blocked Swing)
	lib.add_animation("parry_recoil", _make_pose_anim(0.55, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 4.0, "Pelvis:rotation": deg_to_rad(-6.0),
			"Torso:rotation": deg_to_rad(-16.0), "Head:rotation": deg_to_rad(-12.0), "Hat:rotation": deg_to_rad(-18.0),
			"UpperArm_R:rotation": deg_to_rad(-128.0), "Forearm_R:rotation": deg_to_rad(-22.0), "WeaponBone:rotation": deg_to_rad(-55.0),
		}],
		[0.20, {
			"Pelvis:position:y": 10.0, "Pelvis:rotation": deg_to_rad(-18.0),
			"Torso:rotation": deg_to_rad(-24.0), "Head:rotation": deg_to_rad(-18.0), "Hat:rotation": deg_to_rad(-24.0),
			"UpperArm_R:rotation": deg_to_rad(-136.0), "Forearm_R:rotation": deg_to_rad(-15.0), "WeaponBone:rotation": deg_to_rad(-68.0),
		}],
		[0.55, {
			"Pelvis:position:y": 0.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# KICK (Push Kick Guard Breaker)
	lib.add_animation("kick", _make_pose_anim(0.38, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0), "Torso:rotation": deg_to_rad(-5.0),
			"Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0),
		}],
		[0.13, {
			"Pelvis:position:y": -4.0, "Pelvis:rotation": deg_to_rad(-14.0), "Torso:rotation": deg_to_rad(-18.0),
			"Head:rotation": deg_to_rad(14.0), "Hat:rotation": deg_to_rad(-10.0),
			"Thigh_L:rotation": deg_to_rad(14.0), "Shin_L:rotation": deg_to_rad(-12.0),
			"Thigh_R:rotation": deg_to_rad(-90.0), "Shin_R:rotation": deg_to_rad(10.0), "Boot_R:rotation": deg_to_rad(-14.0),
			"UpperArm_R:rotation": deg_to_rad(-88.0), "Forearm_R:rotation": deg_to_rad(-62.0), "WeaponBone:rotation": deg_to_rad(-42.0),
		}],
		[0.38, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0), "Torso:rotation": deg_to_rad(-5.0),
			"Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# JUMP_SLASH (Vaulting Marionette Plunge Cleave — leaps over low sweeps & crashes down!)
	lib.add_animation("jump_slash", _make_pose_anim(0.52, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 16.0, "Pelvis:rotation": deg_to_rad(-6.0),
			"Torso:rotation": deg_to_rad(-12.0), "Head:rotation": deg_to_rad(10.0), "Hat:rotation": deg_to_rad(-8.0),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-34.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-36.0), "Shin_R:rotation": deg_to_rad(36.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-96.0), "Forearm_R:rotation": deg_to_rad(-58.0), "Hand_R:rotation": deg_to_rad(-10.0), "WeaponBone:rotation": deg_to_rad(-48.0),
		}],
		[0.16, {
			"Pelvis:position:y": -106.0, "Pelvis:rotation": deg_to_rad(-14.0),
			"Torso:rotation": deg_to_rad(-24.0), "Head:rotation": deg_to_rad(20.0), "Hat:rotation": deg_to_rad(-24.0),
			"Thigh_L:rotation": deg_to_rad(16.0), "Shin_L:rotation": deg_to_rad(56.0), "Boot_L:rotation": deg_to_rad(22.0),
			"Thigh_R:rotation": deg_to_rad(-68.0), "Shin_R:rotation": deg_to_rad(78.0), "Boot_R:rotation": deg_to_rad(18.0),
			"UpperArm_R:rotation": deg_to_rad(-146.0), "Forearm_R:rotation": deg_to_rad(-46.0), "Hand_R:rotation": deg_to_rad(-20.0), "WeaponBone:rotation": deg_to_rad(-66.0),
		}],
		[0.29, {
			"Pelvis:position:y": 22.0, "Pelvis:rotation": deg_to_rad(16.0),
			"Torso:rotation": deg_to_rad(26.0), "Head:rotation": deg_to_rad(-22.0), "Hat:rotation": deg_to_rad(26.0),
			"Thigh_L:rotation": deg_to_rad(46.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-28.0),
			"Thigh_R:rotation": deg_to_rad(-54.0), "Shin_R:rotation": deg_to_rad(50.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-28.0), "Forearm_R:rotation": deg_to_rad(-4.0), "Hand_R:rotation": deg_to_rad(20.0), "WeaponBone:rotation": deg_to_rad(62.0),
		}],
		[0.52, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# POMMEL_STRIKE (Fast Close-Quarters Visor-Cracking Hilt Bash!)
	lib.add_animation("pommel_strike", _make_pose_anim(0.32, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 4.0, "Pelvis:rotation": deg_to_rad(-4.0),
			"Torso:rotation": deg_to_rad(-10.0), "Head:rotation": deg_to_rad(8.0), "Hat:rotation": deg_to_rad(-6.0),
			"Thigh_L:rotation": deg_to_rad(28.0), "Shin_L:rotation": deg_to_rad(-22.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-22.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(22.0), "Forearm_R:rotation": deg_to_rad(-114.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(-95.0),
		}],
		[0.11, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(22.0), "Head:rotation": deg_to_rad(-16.0), "Hat:rotation": deg_to_rad(16.0),
			"Thigh_L:rotation": deg_to_rad(42.0), "Shin_L:rotation": deg_to_rad(-12.0), "Boot_L:rotation": deg_to_rad(-24.0),
			"Thigh_R:rotation": deg_to_rad(-48.0), "Shin_R:rotation": deg_to_rad(44.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-96.0), "Forearm_R:rotation": deg_to_rad(-22.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(-88.0),
		}],
		[0.32, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# LEG_SWEEP (Ultra-Low Ducking Ankle Reaper — ducks clean under high slashes!)
	lib.add_animation("leg_sweep", _make_pose_anim(0.42, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 8.0, "Pelvis:rotation": deg_to_rad(6.0),
			"Torso:rotation": deg_to_rad(8.0), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(-4.0),
			"Thigh_L:rotation": deg_to_rad(30.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-26.0), "Shin_R:rotation": deg_to_rad(26.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-34.0), "Forearm_R:rotation": deg_to_rad(-46.0), "WeaponBone:rotation": deg_to_rad(-45.0),
		}],
		[0.14, {
			"Pelvis:position:y": 54.0, "Pelvis:rotation": deg_to_rad(18.0),
			"Torso:rotation": deg_to_rad(28.0), "Head:rotation": deg_to_rad(-24.0), "Hat:rotation": deg_to_rad(18.0),
			"Thigh_L:rotation": deg_to_rad(56.0), "Shin_L:rotation": deg_to_rad(-88.0), "Boot_L:rotation": deg_to_rad(28.0),
			"Thigh_R:rotation": deg_to_rad(-76.0), "Shin_R:rotation": deg_to_rad(-4.0), "Boot_R:rotation": deg_to_rad(14.0),
			"UpperArm_R:rotation": deg_to_rad(16.0), "Forearm_R:rotation": deg_to_rad(-32.0), "WeaponBone:rotation": deg_to_rad(-68.0),
		}],
		[0.42, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SPIN_SLASH (Zwerchhau Whirlwind Double-Cut — rapid 2-hit high-to-low flurry!)
	lib.add_animation("spin_slash", _make_pose_anim(0.48, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 6.0, "Pelvis:rotation": deg_to_rad(-8.0),
			"Torso:rotation": deg_to_rad(-18.0), "Head:rotation": deg_to_rad(14.0), "Hat:rotation": deg_to_rad(-14.0),
			"Thigh_L:rotation": deg_to_rad(30.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-22.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-132.0), "Forearm_R:rotation": deg_to_rad(-44.0), "Hand_R:rotation": deg_to_rad(-14.0), "WeaponBone:rotation": deg_to_rad(-56.0),
		}],
		[0.14, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(12.0),
			"Torso:rotation": deg_to_rad(20.0), "Head:rotation": deg_to_rad(-16.0), "Hat:rotation": deg_to_rad(20.0),
			"Thigh_L:rotation": deg_to_rad(38.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-22.0),
			"Thigh_R:rotation": deg_to_rad(-46.0), "Shin_R:rotation": deg_to_rad(42.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-34.0), "Forearm_R:rotation": deg_to_rad(-8.0), "Hand_R:rotation": deg_to_rad(16.0), "WeaponBone:rotation": deg_to_rad(52.0),
		}],
		[0.21, {
			"Pelvis:position:y": 18.0, "Pelvis:rotation": deg_to_rad(-6.0),
			"Torso:rotation": deg_to_rad(-10.0), "Head:rotation": deg_to_rad(8.0), "Hat:rotation": deg_to_rad(-12.0),
			"UpperArm_R:rotation": deg_to_rad(24.0), "Forearm_R:rotation": deg_to_rad(-26.0), "Hand_R:rotation": deg_to_rad(12.0), "WeaponBone:rotation": deg_to_rad(58.0),
		}],
		[0.31, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(18.0), "Head:rotation": deg_to_rad(-14.0), "Hat:rotation": deg_to_rad(18.0),
			"Thigh_L:rotation": deg_to_rad(42.0), "Shin_L:rotation": deg_to_rad(-12.0), "Boot_L:rotation": deg_to_rad(-24.0),
			"Thigh_R:rotation": deg_to_rad(-50.0), "Shin_R:rotation": deg_to_rad(44.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-106.0), "Forearm_R:rotation": deg_to_rad(-16.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(22.0),
		}],
		[0.48, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# MORDHAU_SMASH (Half-Sword Crossguard Thunderblow — crushes plate helmets & guards!)
	lib.add_animation("mordhau_smash", _make_pose_anim(0.46, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": -4.0, "Pelvis:rotation": deg_to_rad(-10.0),
			"Torso:rotation": deg_to_rad(-24.0), "Head:rotation": deg_to_rad(18.0), "Hat:rotation": deg_to_rad(-18.0),
			"Thigh_L:rotation": deg_to_rad(30.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-16.0), "Shin_R:rotation": deg_to_rad(16.0), "Boot_R:rotation": deg_to_rad(-4.0),
			"UpperArm_R:rotation": deg_to_rad(-142.0), "Forearm_R:rotation": deg_to_rad(-42.0), "Hand_R:rotation": deg_to_rad(-16.0), "WeaponBone:rotation": deg_to_rad(-58.0),
		}],
		[0.12, {
			"Pelvis:position:y": -8.0, "Pelvis:rotation": deg_to_rad(-12.0),
			"Torso:rotation": deg_to_rad(-26.0), "Head:rotation": deg_to_rad(20.0), "Hat:rotation": deg_to_rad(-20.0),
			"UpperArm_R:rotation": deg_to_rad(-148.0), "Forearm_R:rotation": deg_to_rad(-40.0), "Hand_R:rotation": deg_to_rad(-18.0), "WeaponBone:rotation": deg_to_rad(-64.0),
		}],
		[0.24, {
			"Pelvis:position:y": 26.0, "Pelvis:rotation": deg_to_rad(17.0),
			"Torso:rotation": deg_to_rad(28.0), "Head:rotation": deg_to_rad(-22.0), "Hat:rotation": deg_to_rad(26.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-12.0), "Boot_L:rotation": deg_to_rad(-30.0),
			"Thigh_R:rotation": deg_to_rad(-56.0), "Shin_R:rotation": deg_to_rad(52.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-28.0), "Forearm_R:rotation": deg_to_rad(-5.0), "Hand_R:rotation": deg_to_rad(18.0), "WeaponBone:rotation": deg_to_rad(60.0),
		}],
		[0.33, {
			"Pelvis:position:y": 18.0, "Pelvis:rotation": deg_to_rad(11.0),
			"Torso:rotation": deg_to_rad(16.0), "Head:rotation": deg_to_rad(-12.0), "Hat:rotation": deg_to_rad(10.0),
			"UpperArm_R:rotation": deg_to_rad(-38.0), "Forearm_R:rotation": deg_to_rad(-18.0), "Hand_R:rotation": deg_to_rad(14.0), "WeaponBone:rotation": deg_to_rad(42.0),
		}],
		[0.46, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# RIPOSTE_CLEAVE (Blazing Zornhau Master-Cut directly out of Parry/Riposte!)
	lib.add_animation("riposte_cleave", _make_pose_anim(0.38, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 6.0, "Pelvis:rotation": deg_to_rad(-4.0),
			"Torso:rotation": deg_to_rad(-12.0), "Head:rotation": deg_to_rad(10.0), "Hat:rotation": deg_to_rad(-10.0),
			"Thigh_L:rotation": deg_to_rad(30.0), "Shin_L:rotation": deg_to_rad(-26.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(24.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-118.0), "Forearm_R:rotation": deg_to_rad(-48.0), "Hand_R:rotation": deg_to_rad(-12.0), "WeaponBone:rotation": deg_to_rad(-46.0),
		}],
		[0.07, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(8.0),
			"Torso:rotation": deg_to_rad(14.0), "Head:rotation": deg_to_rad(-12.0), "Hat:rotation": deg_to_rad(10.0),
			"Thigh_L:rotation": deg_to_rad(42.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-22.0),
			"Thigh_R:rotation": deg_to_rad(-48.0), "Shin_R:rotation": deg_to_rad(44.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-72.0), "Forearm_R:rotation": deg_to_rad(-12.0), "Hand_R:rotation": deg_to_rad(12.0), "WeaponBone:rotation": deg_to_rad(28.0),
		}],
		[0.17, {
			"Pelvis:position:y": 24.0, "Pelvis:rotation": deg_to_rad(16.0),
			"Torso:rotation": deg_to_rad(25.0), "Head:rotation": deg_to_rad(-20.0), "Hat:rotation": deg_to_rad(24.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-30.0),
			"Thigh_R:rotation": deg_to_rad(-56.0), "Shin_R:rotation": deg_to_rad(52.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-32.0), "Forearm_R:rotation": deg_to_rad(-4.0), "Hand_R:rotation": deg_to_rad(20.0), "WeaponBone:rotation": deg_to_rad(60.0),
		}],
		[0.38, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# BACKSTEP_CUT (Evasive Abzug Fadeaway Slash — leans torso & head back while scything enemy arms!)
	lib.add_animation("backstep_cut", _make_pose_anim(0.42, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(-12.0),
			"Torso:rotation": deg_to_rad(-22.0), "Head:rotation": deg_to_rad(18.0), "Hat:rotation": deg_to_rad(16.0),
			"Thigh_L:rotation": deg_to_rad(44.0), "Shin_L:rotation": deg_to_rad(-38.0), "Boot_L:rotation": deg_to_rad(8.0),
			"Thigh_R:rotation": deg_to_rad(-10.0), "Shin_R:rotation": deg_to_rad(8.0), "Boot_R:rotation": deg_to_rad(-18.0),
			"UpperArm_R:rotation": deg_to_rad(-126.0), "Forearm_R:rotation": deg_to_rad(-42.0), "Hand_R:rotation": deg_to_rad(-12.0), "WeaponBone:rotation": deg_to_rad(-48.0),
		}],
		[0.14, {
			"Pelvis:position:y": 18.0, "Pelvis:rotation": deg_to_rad(-14.0),
			"Torso:rotation": deg_to_rad(-20.0), "Head:rotation": deg_to_rad(16.0), "Hat:rotation": deg_to_rad(22.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-42.0), "Boot_L:rotation": deg_to_rad(10.0),
			"Thigh_R:rotation": deg_to_rad(-4.0), "Shin_R:rotation": deg_to_rad(6.0), "Boot_R:rotation": deg_to_rad(-22.0),
			"UpperArm_R:rotation": deg_to_rad(-44.0), "Forearm_R:rotation": deg_to_rad(-6.0), "Hand_R:rotation": deg_to_rad(16.0), "WeaponBone:rotation": deg_to_rad(48.0),
		}],
		[0.26, {
			"Pelvis:position:y": 12.0, "Pelvis:rotation": deg_to_rad(-8.0),
			"Torso:rotation": deg_to_rad(-12.0), "Head:rotation": deg_to_rad(10.0), "Hat:rotation": deg_to_rad(8.0),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-28.0), "Boot_L:rotation": deg_to_rad(2.0),
			"Thigh_R:rotation": deg_to_rad(-16.0), "Shin_R:rotation": deg_to_rad(16.0), "Boot_R:rotation": deg_to_rad(-8.0),
			"UpperArm_R:rotation": deg_to_rad(-38.0), "Forearm_R:rotation": deg_to_rad(-16.0), "Hand_R:rotation": deg_to_rad(14.0), "WeaponBone:rotation": deg_to_rad(36.0),
		}],
		[0.42, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SIG_LANDSKNECHT (Gassenhauer — Low Rising Unterhau Scythe -> Advancing Figure-8 Overhead Cleave!)
	lib.add_animation("sig_landsknecht", _make_pose_anim(0.48, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 16.0, "Pelvis:rotation": deg_to_rad(-10.0),
			"Torso:rotation": deg_to_rad(-16.0), "Head:rotation": deg_to_rad(12.0), "Hat:rotation": deg_to_rad(-10.0),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-32.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-30.0), "Shin_R:rotation": deg_to_rad(30.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(32.0), "Forearm_R:rotation": deg_to_rad(-22.0), "Hand_R:rotation": deg_to_rad(16.0), "WeaponBone:rotation": deg_to_rad(64.0),
		}],
		[0.13, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(18.0), "Head:rotation": deg_to_rad(-14.0), "Hat:rotation": deg_to_rad(18.0),
			"Thigh_L:rotation": deg_to_rad(42.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-22.0),
			"Thigh_R:rotation": deg_to_rad(-48.0), "Shin_R:rotation": deg_to_rad(42.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-108.0), "Forearm_R:rotation": deg_to_rad(-18.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(20.0),
		}],
		[0.21, {
			"Pelvis:position:y": -4.0, "Pelvis:rotation": deg_to_rad(-8.0),
			"Torso:rotation": deg_to_rad(-18.0), "Head:rotation": deg_to_rad(14.0), "Hat:rotation": deg_to_rad(-16.0),
			"UpperArm_R:rotation": deg_to_rad(-144.0), "Forearm_R:rotation": deg_to_rad(-42.0), "Hand_R:rotation": deg_to_rad(-16.0), "WeaponBone:rotation": deg_to_rad(-60.0),
		}],
		[0.31, {
			"Pelvis:position:y": 24.0, "Pelvis:rotation": deg_to_rad(16.0),
			"Torso:rotation": deg_to_rad(26.0), "Head:rotation": deg_to_rad(-22.0), "Hat:rotation": deg_to_rad(24.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-30.0),
			"Thigh_R:rotation": deg_to_rad(-56.0), "Shin_R:rotation": deg_to_rad(52.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-30.0), "Forearm_R:rotation": deg_to_rad(-5.0), "Hand_R:rotation": deg_to_rad(20.0), "WeaponBone:rotation": deg_to_rad(60.0),
		}],
		[0.48, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SIG_FECHTMEISTER (Meisterhau Bind — High Angled Ochs Crossguard Bind -> Spiral Disarming Cut!)
	lib.add_animation("sig_fechtmeister", _make_pose_anim(0.44, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 6.0, "Pelvis:rotation": deg_to_rad(-4.0),
			"Torso:rotation": deg_to_rad(-8.0), "Head:rotation": deg_to_rad(8.0), "Hat:rotation": deg_to_rad(-6.0),
			"Thigh_L:rotation": deg_to_rad(28.0), "Shin_L:rotation": deg_to_rad(-24.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-26.0), "Shin_R:rotation": deg_to_rad(26.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-112.0), "Forearm_R:rotation": deg_to_rad(-36.0), "Hand_R:rotation": deg_to_rad(8.0), "WeaponBone:rotation": deg_to_rad(104.0),
		}],
		[0.14, {
			"Pelvis:position:y": 10.0, "Pelvis:rotation": deg_to_rad(6.0),
			"Torso:rotation": deg_to_rad(8.0), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(6.0),
			"Thigh_L:rotation": deg_to_rad(36.0), "Shin_L:rotation": deg_to_rad(-20.0), "Boot_L:rotation": deg_to_rad(-12.0),
			"Thigh_R:rotation": deg_to_rad(-38.0), "Shin_R:rotation": deg_to_rad(36.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-122.0), "Forearm_R:rotation": deg_to_rad(-28.0), "Hand_R:rotation": deg_to_rad(14.0), "WeaponBone:rotation": deg_to_rad(118.0),
		}],
		[0.24, {
			"Pelvis:position:y": 22.0, "Pelvis:rotation": deg_to_rad(15.0),
			"Torso:rotation": deg_to_rad(24.0), "Head:rotation": deg_to_rad(-20.0), "Hat:rotation": deg_to_rad(20.0),
			"Thigh_L:rotation": deg_to_rad(46.0), "Shin_L:rotation": deg_to_rad(-12.0), "Boot_L:rotation": deg_to_rad(-28.0),
			"Thigh_R:rotation": deg_to_rad(-54.0), "Shin_R:rotation": deg_to_rad(50.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-34.0), "Forearm_R:rotation": deg_to_rad(-6.0), "Hand_R:rotation": deg_to_rad(20.0), "WeaponBone:rotation": deg_to_rad(58.0),
		}],
		[0.44, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SIG_EXECUTIONER (Guillotine Chop — Dread High-Hanging Raise -> Seismic Flagstone Execution!)
	lib.add_animation("sig_executioner", _make_pose_anim(0.54, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": -2.0, "Pelvis:rotation": deg_to_rad(-8.0),
			"Torso:rotation": deg_to_rad(-18.0), "Head:rotation": deg_to_rad(14.0), "Hat:rotation": deg_to_rad(-12.0),
			"Thigh_L:rotation": deg_to_rad(26.0), "Shin_L:rotation": deg_to_rad(-20.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-18.0), "Shin_R:rotation": deg_to_rad(18.0), "Boot_R:rotation": deg_to_rad(-2.0),
			"UpperArm_R:rotation": deg_to_rad(-134.0), "Forearm_R:rotation": deg_to_rad(-44.0), "Hand_R:rotation": deg_to_rad(-14.0), "WeaponBone:rotation": deg_to_rad(-54.0),
		}],
		[0.16, {
			"Pelvis:position:y": -14.0, "Pelvis:rotation": deg_to_rad(-14.0),
			"Torso:rotation": deg_to_rad(-28.0), "Head:rotation": deg_to_rad(22.0), "Hat:rotation": deg_to_rad(-24.0),
			"Thigh_L:rotation": deg_to_rad(18.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(12.0),
			"Thigh_R:rotation": deg_to_rad(-14.0), "Shin_R:rotation": deg_to_rad(14.0), "Boot_R:rotation": deg_to_rad(10.0),
			"UpperArm_R:rotation": deg_to_rad(-154.0), "Forearm_R:rotation": deg_to_rad(-38.0), "Hand_R:rotation": deg_to_rad(-20.0), "WeaponBone:rotation": deg_to_rad(-70.0),
		}],
		[0.28, {
			"Pelvis:position:y": 30.0, "Pelvis:rotation": deg_to_rad(18.0),
			"Torso:rotation": deg_to_rad(30.0), "Head:rotation": deg_to_rad(-24.0), "Hat:rotation": deg_to_rad(28.0),
			"Thigh_L:rotation": deg_to_rad(52.0), "Shin_L:rotation": deg_to_rad(-12.0), "Boot_L:rotation": deg_to_rad(-32.0),
			"Thigh_R:rotation": deg_to_rad(-60.0), "Shin_R:rotation": deg_to_rad(56.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-24.0), "Forearm_R:rotation": deg_to_rad(-4.0), "Hand_R:rotation": deg_to_rad(22.0), "WeaponBone:rotation": deg_to_rad(66.0),
		}],
		[0.39, {
			"Pelvis:position:y": 22.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(22.0), "Head:rotation": deg_to_rad(-16.0), "Hat:rotation": deg_to_rad(14.0),
			"UpperArm_R:rotation": deg_to_rad(-34.0), "Forearm_R:rotation": deg_to_rad(-14.0), "Hand_R:rotation": deg_to_rad(16.0), "WeaponBone:rotation": deg_to_rad(48.0),
		}],
		[0.54, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SIG_BLACK_KNIGHT (Iron Bull Barge — Tucked-Chin Full-Plate Shoulder & Gauntlet Ram!)
	lib.add_animation("sig_black_knight", _make_pose_anim(0.40, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(-4.0),
			"Torso:rotation": deg_to_rad(-8.0), "Head:rotation": deg_to_rad(6.0), "Hat:rotation": deg_to_rad(-6.0),
			"Thigh_L:rotation": deg_to_rad(34.0), "Shin_L:rotation": deg_to_rad(-30.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-28.0), "Shin_R:rotation": deg_to_rad(28.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(-24.0), "Forearm_R:rotation": deg_to_rad(-98.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(-42.0),
		}],
		[0.13, {
			"Pelvis:position:y": 24.0, "Pelvis:rotation": deg_to_rad(18.0),
			"Torso:rotation": deg_to_rad(30.0), "Head:rotation": deg_to_rad(-24.0), "Hat:rotation": deg_to_rad(22.0),
			"Thigh_L:rotation": deg_to_rad(52.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-34.0),
			"Thigh_R:rotation": deg_to_rad(-58.0), "Shin_R:rotation": deg_to_rad(54.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-58.0), "Forearm_R:rotation": deg_to_rad(-88.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(-36.0),
		}],
		[0.25, {
			"Pelvis:position:y": 20.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(24.0), "Head:rotation": deg_to_rad(-18.0), "Hat:rotation": deg_to_rad(14.0),
			"Thigh_L:rotation": deg_to_rad(46.0), "Shin_L:rotation": deg_to_rad(-14.0), "Boot_L:rotation": deg_to_rad(-26.0),
			"Thigh_R:rotation": deg_to_rad(-50.0), "Shin_R:rotation": deg_to_rad(46.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-54.0), "Forearm_R:rotation": deg_to_rad(-82.0), "Hand_R:rotation": deg_to_rad(4.0), "WeaponBone:rotation": deg_to_rad(-32.0),
		}],
		[0.40, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	# SIG_BRAVO (Punta Doppia — Ducking Low-Profile Slip -> Rapid 2-Hit Rapier Double-Needle Lunge!)
	lib.add_animation("sig_bravo", _make_pose_anim(0.44, Animation.LOOP_NONE, [
		[0.0, {
			"Pelvis:position:y": 14.0, "Pelvis:rotation": deg_to_rad(6.0),
			"Torso:rotation": deg_to_rad(8.0), "Head:rotation": deg_to_rad(-6.0), "Hat:rotation": deg_to_rad(-4.0),
			"Thigh_L:rotation": deg_to_rad(34.0), "Shin_L:rotation": deg_to_rad(-30.0), "Boot_L:rotation": deg_to_rad(-4.0),
			"Thigh_R:rotation": deg_to_rad(-30.0), "Shin_R:rotation": deg_to_rad(30.0), "Boot_R:rotation": deg_to_rad(0.0),
			"UpperArm_R:rotation": deg_to_rad(22.0), "Forearm_R:rotation": deg_to_rad(-106.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(88.0),
		}],
		[0.07, {
			"Pelvis:position:y": 46.0, "Pelvis:rotation": deg_to_rad(16.0),
			"Torso:rotation": deg_to_rad(24.0), "Head:rotation": deg_to_rad(-22.0), "Hat:rotation": deg_to_rad(14.0),
			"Thigh_L:rotation": deg_to_rad(54.0), "Shin_L:rotation": deg_to_rad(-82.0), "Boot_L:rotation": deg_to_rad(24.0),
			"Thigh_R:rotation": deg_to_rad(-72.0), "Shin_R:rotation": deg_to_rad(62.0), "Boot_R:rotation": deg_to_rad(8.0),
			"UpperArm_R:rotation": deg_to_rad(12.0), "Forearm_R:rotation": deg_to_rad(-98.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(88.0),
		}],
		[0.15, {
			"Pelvis:position:y": 26.0, "Pelvis:rotation": deg_to_rad(14.0),
			"Torso:rotation": deg_to_rad(22.0), "Head:rotation": deg_to_rad(-20.0), "Hat:rotation": deg_to_rad(16.0),
			"Thigh_L:rotation": deg_to_rad(48.0), "Shin_L:rotation": deg_to_rad(-10.0), "Boot_L:rotation": deg_to_rad(-34.0),
			"Thigh_R:rotation": deg_to_rad(-56.0), "Shin_R:rotation": deg_to_rad(52.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-108.0), "Forearm_R:rotation": deg_to_rad(-6.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(80.0),
		}],
		[0.21, {
			"Pelvis:position:y": 22.0, "Pelvis:rotation": deg_to_rad(8.0),
			"Torso:rotation": deg_to_rad(12.0), "Head:rotation": deg_to_rad(-10.0), "Hat:rotation": deg_to_rad(-6.0),
			"UpperArm_R:rotation": deg_to_rad(-24.0), "Forearm_R:rotation": deg_to_rad(-78.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(84.0),
		}],
		[0.28, {
			"Pelvis:position:y": 30.0, "Pelvis:rotation": deg_to_rad(17.0),
			"Torso:rotation": deg_to_rad(25.0), "Head:rotation": deg_to_rad(-23.0), "Hat:rotation": deg_to_rad(20.0),
			"Thigh_L:rotation": deg_to_rad(54.0), "Shin_L:rotation": deg_to_rad(-8.0), "Boot_L:rotation": deg_to_rad(-38.0),
			"Thigh_R:rotation": deg_to_rad(-62.0), "Shin_R:rotation": deg_to_rad(58.0), "Boot_R:rotation": deg_to_rad(4.0),
			"UpperArm_R:rotation": deg_to_rad(-114.0), "Forearm_R:rotation": deg_to_rad(-4.0), "Hand_R:rotation": deg_to_rad(0.0), "WeaponBone:rotation": deg_to_rad(82.0),
		}],
		[0.44, {
			"Pelvis:position:y": 2.0, "Pelvis:rotation": deg_to_rad(3.0),
			"Torso:rotation": deg_to_rad(-5.0), "Head:rotation": deg_to_rad(2.0), "Hat:rotation": deg_to_rad(0.0),
			"Thigh_L:rotation": deg_to_rad(24.0), "Shin_L:rotation": deg_to_rad(-18.0), "Boot_L:rotation": deg_to_rad(-6.0),
			"Thigh_R:rotation": deg_to_rad(-24.0), "Shin_R:rotation": deg_to_rad(22.0), "Boot_R:rotation": deg_to_rad(2.0),
			"UpperArm_R:rotation": deg_to_rad(-52.0), "Forearm_R:rotation": deg_to_rad(-55.0), "Hand_R:rotation": deg_to_rad(10.0), "WeaponBone:rotation": deg_to_rad(-28.0),
		}],
	]))

	anim_player.add_animation_library("", lib)


static func _make_pose_anim(length_sec: float, loop_mode: Animation.LoopMode, keyframes: Array) -> Animation:
	var anim := Animation.new()
	anim.length = length_sec
	anim.loop_mode = loop_mode

	var track_map := {}
	for kf in keyframes:
		var t: float = float(kf[0])
		var pose: Dictionary = kf[1]
		for prop_key in pose.keys():
			var node_path := _bone_track_path(prop_key)
			if not track_map.has(prop_key):
				var tr := anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(tr, node_path)
				var interp := Animation.INTERPOLATION_CUBIC_ANGLE if String(prop_key).ends_with(":rotation") else Animation.INTERPOLATION_CUBIC
				anim.track_set_interpolation_type(tr, interp)
				track_map[prop_key] = tr
			anim.track_insert_key(int(track_map[prop_key]), t, pose[prop_key])

	return anim


static func _bone_track_path(prop_key: String) -> String:
	var parts := prop_key.split(":", false, 1)
	var bone_name := parts[0]
	var prop_sub := parts[1]
	match bone_name:
		"Pelvis": return "Skeleton2D/Pelvis:" + prop_sub
		"Torso": return "Skeleton2D/Pelvis/Torso:" + prop_sub
		"Head": return "Skeleton2D/Pelvis/Torso/Head:" + prop_sub
		"Hat": return "Skeleton2D/Pelvis/Torso/Head/Hat:" + prop_sub
		"Thigh_L": return "Skeleton2D/Pelvis/Thigh_L:" + prop_sub
		"Shin_L": return "Skeleton2D/Pelvis/Thigh_L/Shin_L:" + prop_sub
		"Boot_L": return "Skeleton2D/Pelvis/Thigh_L/Shin_L/Boot_L:" + prop_sub
		"Thigh_R": return "Skeleton2D/Pelvis/Thigh_R:" + prop_sub
		"Shin_R": return "Skeleton2D/Pelvis/Thigh_R/Shin_R:" + prop_sub
		"Boot_R": return "Skeleton2D/Pelvis/Thigh_R/Shin_R/Boot_R:" + prop_sub
		"UpperArm_R": return "Skeleton2D/Pelvis/Torso/UpperArm_R:" + prop_sub
		"Forearm_R": return "Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R:" + prop_sub
		"Hand_R": return "Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R:" + prop_sub
		"WeaponBone": return "Skeleton2D/Pelvis/Torso/UpperArm_R/Forearm_R/Hand_R/WeaponBone:" + prop_sub
		"UpperArm_L": return "Skeleton2D/Pelvis/Torso/UpperArm_L:" + prop_sub
		"Forearm_L": return "Skeleton2D/Pelvis/Torso/UpperArm_L/Forearm_L:" + prop_sub
		"Hand_L": return "Skeleton2D/Pelvis/Torso/UpperArm_L/Forearm_L/Hand_L:" + prop_sub
		_: return "Skeleton2D/" + prop_key


static func _spec(parts: Dictionary, part_id: String) -> Dictionary:
	if part_id == "" or not parts.has(part_id):
		return {}
	return parts[part_id]


static func _vec2(arr: Variant) -> Vector2:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


static func _socket_offset(spec: Dictionary, socket_name: String) -> Vector2:
	if spec.is_empty():
		return Vector2.ZERO
	var sockets: Dictionary = spec.get("sockets", {})
	if not sockets.has(socket_name):
		return Vector2.ZERO
	var pivot := _vec2(spec.get("pivot", [0, 0]))
	var sock := _vec2(sockets[socket_name])
	var s := float(spec.get("scale", 1.0))
	return (sock - pivot) * s


static func _pascal_case(raw: String) -> String:
	var out := ""
	for tok in raw.split("_", false):
		if tok.length() > 0:
			out += tok[0].to_upper() + tok.substr(1)
	return out
