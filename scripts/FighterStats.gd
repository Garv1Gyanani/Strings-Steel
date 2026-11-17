class_name FighterStats
extends RefCounted

## Per-fighter gameplay tuning. Each roster entry differs in more than visuals:
## health, footwork, attack tempo, damage profile, armour coverage, parry skill
## and the spacing the AI prefers when piloting that fighter.
##
## Keys missing from a fighter entry fall back to DEFAULT.

const DEFAULT := {
	"display_name": "FIGHTER",
	"blurb": "",
	"max_hp": 100.0,
	"move_speed": 300.0,
	"attack_speed": 1.0, # AnimationPlayer playback multiplier for slash/thrust/kick
	"damage_mult": 1.0, # all blade damage
	"thrust_mult": 1.0, # extra multiplier on thrusts
	"limb_damage_mult": 1.0, # how quickly blows chew through limb HP (dismemberment)
	"stamina_regen": 22.0,
	"stamina_cost_mult": 1.0,
	"armor_mult": 1.0, # damage taken on armoured slots
	"armored_slots": [],
	"perfect_parry_window": 0.25,
	"dash_cooldown": 0.55,
	"dash_speed": 760.0,
	"ai_spacing": 195.0,
	"ai_aggression": 0.55, # 0..1, shortens AI attack cooldowns
	"ai_thrust_bias": 0.0, # -1..1, shifts AI attack choice toward slashes / thrusts
	# Head sprite part ids (from rig_metadata.json) per facial expression.
	"heads": {"calm": "p1_head_calm", "yell": "p1_head_yell", "pain": "p1_head_grimace", "bloody": "p1_head_bloody", "dead": "p1_head_dead"},
}

const TABLE := {
	"landsknecht": {
		"display_name": "LANDSKNECHT",
		"blurb": "Doppelsöldner. Hits hard, recovers fast, wears no armour.",
		"max_hp": 110.0,
		"move_speed": 300.0,
		"damage_mult": 1.15,
		"limb_damage_mult": 1.1,
		"stamina_regen": 26.0,
		"ai_spacing": 190.0,
		"ai_aggression": 0.65,
	},
	"fechtmeister": {
		"display_name": "FECHTMEISTER",
		"blurb": "Master of defence. Wide perfect-parry window, half plate.",
		"attack_speed": 1.05,
		"armor_mult": 0.72,
		"armored_slots": ["torso", "head", "shin_r", "shin_l"],
		"perfect_parry_window": 0.34,
		"ai_spacing": 200.0,
		"ai_aggression": 0.45,
		"heads": {"calm": "p2_head_calm", "yell": "p2_head_yell", "pain": "p2_head_pain", "bloody": "p2_head_bloody", "dead": "p2_head_dead"},
	},
	"plague_executioner": {
		"display_name": "PLAGUE EXECUTIONER",
		"blurb": "Slow, brutal chops that cleave limbs. Brigandine coat.",
		"max_hp": 115.0,
		"move_speed": 265.0,
		"attack_speed": 0.86,
		"damage_mult": 1.3,
		"thrust_mult": 0.85,
		"limb_damage_mult": 1.45,
		"stamina_regen": 19.0,
		"stamina_cost_mult": 1.15,
		"armor_mult": 0.8,
		"armored_slots": ["torso", "head"],
		"perfect_parry_window": 0.22,
		"dash_cooldown": 0.7,
		"ai_spacing": 180.0,
		"ai_aggression": 0.6,
		"ai_thrust_bias": -0.6,
		"heads": {"calm": "p3_head_mask", "yell": "p3_head_mask", "pain": "p3_head_bloody", "bloody": "p3_head_bloody", "dead": "p3_head_dead"},
	},
	"black_knight": {
		"display_name": "BLACK KNIGHT",
		"blurb": "Full plate. Shrugs off blows but tires quickly.",
		"max_hp": 125.0,
		"move_speed": 245.0,
		"attack_speed": 0.9,
		"damage_mult": 1.1,
		"stamina_regen": 17.0,
		"stamina_cost_mult": 1.2,
		"armor_mult": 0.58,
		"armored_slots": ["torso", "head", "shin_r", "shin_l", "thigh_r", "thigh_l"],
		"perfect_parry_window": 0.24,
		"dash_cooldown": 0.8,
		"dash_speed": 640.0,
		"ai_spacing": 195.0,
		"ai_aggression": 0.5,
		"heads": {"calm": "p4_head_helm", "yell": "p4_head_helm", "pain": "p4_head_bloody", "bloody": "p4_head_bloody", "dead": "p4_head_dead"},
	},
	"venetian_bravo": {
		"display_name": "VENETIAN BRAVO",
		"blurb": "Rapier duellist. Lightning thrusts and footwork, but fragile.",
		"max_hp": 88.0,
		"move_speed": 345.0,
		"attack_speed": 1.2,
		"damage_mult": 0.9,
		"thrust_mult": 1.45,
		"limb_damage_mult": 0.85,
		"stamina_regen": 25.0,
		"stamina_cost_mult": 0.85,
		"perfect_parry_window": 0.28,
		"dash_cooldown": 0.4,
		"dash_speed": 860.0,
		"ai_spacing": 215.0,
		"ai_aggression": 0.7,
		"ai_thrust_bias": 0.7,
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
