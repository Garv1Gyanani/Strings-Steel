class_name FighterStats
extends RefCounted

## Per-fighter gameplay tuning. Each roster entry differs in more than visuals:
## health, footwork, attack tempo, blade weight/inertia, damage profile, armour
## coverage, parry skill and the AI archetype when piloting that fighter.
##
## Keys missing from a fighter entry fall back to DEFAULT.

const DEFAULT := {
	"display_name": "FIGHTER",
	"blurb": "",
	"max_hp": 100.0,
	"move_speed": 336.0,
	"attack_speed": 1.08, # AnimationPlayer playback multiplier for attacks
	"blade_weight": 1.0, # Cursor IK inertia (>1 = heavier, slower slew; <1 = nimble)
	"damage_mult": 1.0, # all blade damage
	"thrust_mult": 1.0, # extra multiplier on thrusts
	"armor_pierce_thrust": 0.15, # fraction of armour mitigation ignored on point thrusts
	"limb_damage_mult": 1.0, # how quickly blows chew through limb HP (dismemberment)
	"stamina_regen": 27.0,
	"stamina_cost_mult": 1.0,
	"armor_mult": 1.0, # damage taken on armoured slots
	"armored_slots": [],
	"perfect_parry_window": 0.25,
	"dash_cooldown": 0.42,
	"dash_speed": 880.0,
	"ai_spacing": 195.0,
	"ai_aggression": 0.55, # 0..1, shortens AI attack cooldowns
	"ai_thrust_bias": 0.0, # -1..1, shifts AI attack choice toward slashes / thrusts
	"ai_style": "balanced", # "pressure" | "master" | "executioner" | "bully" | "duelist"
	"unhelmed_head": "", # optional bare head sprite id revealed when helmet is smashed off
	# Head sprite part ids (from rig_metadata.json) per facial expression.
	"heads": {"calm": "p1_head_calm", "yell": "p1_head_yell", "pain": "p1_head_grimace", "bloody": "p1_head_bloody", "dead": "p1_head_dead"},
}

const LOADOUT_ORDER := ["signature", "halberd", "warhammer", "pollaxe", "buckler", "katzbalger"]
const LOADOUT_LABELS := {
	"signature": "SIGNATURE",
	"halberd": "CRIMSON HALBERD",
	"warhammer": "BEC DE CORBIN",
	"pollaxe": "POLLAXE",
	"buckler": "SWORD + BUCKLER",
	"katzbalger": "KATZBALGER",
}

## Per-weapon-part combat modifiers (applied when equipping a loadout or picking up a dropped blade).
const WEAPON_SPECS := {
	"p1_sword_long": {"label": "LONGSWORD", "weight": 1.0, "speed": 1.0, "dmg": 1.0, "guard_crush": 1.0, "ap_cut": 0.0, "ap_thrust": 0.0, "two_handed": true},
	"p2_sword_flam": {"label": "FLAMBERGE", "weight": 1.02, "speed": 1.0, "dmg": 1.04, "guard_crush": 1.08, "ap_cut": 0.0, "ap_thrust": 0.0, "two_handed": true},
	"p3_sword_exec": {"label": "EXECUTIONER BLADE", "weight": 1.15, "speed": 0.94, "dmg": 1.12, "guard_crush": 1.22, "ap_cut": 0.08, "ap_thrust": -0.05, "two_handed": true},
	"p4_sword_flam": {"label": "GREATSWORD", "weight": 1.10, "speed": 0.96, "dmg": 1.08, "guard_crush": 1.18, "ap_cut": 0.05, "ap_thrust": 0.0, "two_handed": true},
	"p5_sword_rapier": {"label": "RAPIER", "weight": 0.82, "speed": 1.14, "dmg": 0.92, "guard_crush": 0.82, "ap_cut": 0.0, "ap_thrust": 0.25, "two_handed": false},
	"p2_pollaxe": {"label": "IRON POLLAXE", "weight": 1.22, "speed": 0.90, "dmg": 1.20, "guard_crush": 1.48, "ap_cut": 0.30, "ap_thrust": 0.22, "two_handed": true},
	"p_weapon_halberd": {"label": "CRIMSON HALBERD", "weight": 1.12, "speed": 0.96, "dmg": 1.16, "guard_crush": 1.34, "ap_cut": 0.22, "ap_thrust": 0.34, "two_handed": true},
	"p_weapon_warhammer": {"label": "BEC DE CORBIN", "weight": 1.18, "speed": 0.94, "dmg": 1.18, "guard_crush": 1.62, "ap_cut": 0.52, "ap_thrust": 0.30, "two_handed": true},
	"p1_sword_katz": {"label": "KATZBALGER", "weight": 0.76, "speed": 1.22, "dmg": 0.94, "guard_crush": 0.90, "ap_cut": 0.0, "ap_thrust": 0.08, "two_handed": false},
}

const TABLE := {
	"landsknecht": {
		"display_name": "LANDSKNECHT",
		"blurb": "Doppelsöldner. Relentless high-low combos & fast stamina, no armour.",
		"max_hp": 112.0,
		"move_speed": 345.0,
		"attack_speed": 1.10,
		"blade_weight": 0.95,
		"damage_mult": 1.12,
		"limb_damage_mult": 1.08,
		"stamina_regen": 31.0,
		"ai_spacing": 188.0,
		"ai_aggression": 0.72,
		"ai_style": "pressure",
	},
	"fechtmeister": {
		"display_name": "FECHTMEISTER",
		"blurb": "Master of defence. Wide perfect-parry window, steel gauntlets & half plate.",
		"move_speed": 338.0,
		"attack_speed": 1.12,
		"blade_weight": 0.90,
		"armor_mult": 0.72,
		"armored_slots": ["torso", "head", "shin_r", "shin_l", "forearm_r", "forearm_l"],
		"perfect_parry_window": 0.34,
		"ai_spacing": 202.0,
		"ai_aggression": 0.54,
		"ai_style": "master",
		"heads": {"calm": "p2_head_calm", "yell": "p2_head_yell", "pain": "p2_head_pain", "bloody": "p2_head_bloody", "dead": "p2_head_dead"},
	},
	"plague_executioner": {
		"display_name": "PLAGUE EXECUTIONER",
		"blurb": "Heavy executioner's blade. Slow wind-up, brutal limb-chopping momentum.",
		"max_hp": 115.0,
		"move_speed": 300.0,
		"attack_speed": 0.94,
		"blade_weight": 1.28,
		"damage_mult": 1.24,
		"thrust_mult": 0.82,
		"armor_pierce_thrust": 0.05,
		"limb_damage_mult": 1.25,
		"stamina_regen": 24.0,
		"stamina_cost_mult": 1.12,
		"armor_mult": 0.80,
		"armored_slots": ["torso", "head", "arm_r"],
		"perfect_parry_window": 0.22,
		"dash_cooldown": 0.54,
		"ai_spacing": 186.0,
		"ai_aggression": 0.64,
		"ai_thrust_bias": -0.65,
		"ai_style": "executioner",
		"unhelmed_head": "p3_head_yell",
		"heads": {"calm": "p3_head_mask", "yell": "p3_head_mask", "pain": "p3_head_bloody", "bloody": "p3_head_bloody", "dead": "p3_head_dead"},
	},
	"black_knight": {
		"display_name": "BLACK KNIGHT",
		"blurb": "Full plate harness. Shrugs off slashes and bullies guards, tires quickly.",
		"max_hp": 125.0,
		"move_speed": 282.0,
		"attack_speed": 0.98,
		"blade_weight": 1.18,
		"damage_mult": 1.10,
		"limb_damage_mult": 1.05,
		"stamina_regen": 22.0,
		"stamina_cost_mult": 1.16,
		"armor_mult": 0.58,
		"armored_slots": ["torso", "head", "arm_r", "forearm_r", "arm_l", "forearm_l", "shin_r", "shin_l", "thigh_r", "thigh_l"],
		"perfect_parry_window": 0.24,
		"dash_cooldown": 0.60,
		"dash_speed": 740.0,
		"ai_spacing": 182.0,
		"ai_aggression": 0.68,
		"ai_style": "bully",
		"unhelmed_head": "p4_head_calm",
		"heads": {"calm": "p4_head_helm", "yell": "p4_head_helm", "pain": "p4_head_bloody", "bloody": "p4_head_bloody", "dead": "p4_head_dead"},
	},
	"venetian_bravo": {
		"display_name": "VENETIAN BRAVO",
		"blurb": "Rapier duellist. Nimble armour-piercing thrusts and footwork, fragile.",
		"max_hp": 88.0,
		"move_speed": 392.0,
		"attack_speed": 1.28,
		"blade_weight": 0.70,
		"damage_mult": 0.88,
		"thrust_mult": 1.45,
		"armor_pierce_thrust": 0.45,
		"limb_damage_mult": 0.70,
		"stamina_regen": 30.0,
		"stamina_cost_mult": 0.84,
		"perfect_parry_window": 0.28,
		"dash_cooldown": 0.32,
		"dash_speed": 980.0,
		"ai_spacing": 226.0,
		"ai_aggression": 0.76,
		"ai_thrust_bias": 0.75,
		"ai_style": "duelist",
		"heads": {"calm": "p5_head_calm", "yell": "p5_head_yell", "pain": "p5_head_yell", "bloody": "p5_head_bloody", "dead": "p5_head_dead"},
	},
}


static func get_stats(fighter_id: String) -> Dictionary:
	var out: Dictionary = DEFAULT.duplicate(true)
	var entry: Dictionary = TABLE.get(fighter_id, {})
	for k in entry.keys():
		out[k] = entry[k]
	if String(out["display_name"]) == "FIGHTER":
		out["display_name"] = fighter_id.replace("_", " ").to_upper()
	return out
