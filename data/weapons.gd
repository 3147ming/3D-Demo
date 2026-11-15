class_name WeaponDB
## 武器数据表（占位数值，后续批次统一平衡）
## mesh 描述占位几何：shape = cylinder / box / spear

const DEFAULT_ID := "staff"

const WEAPONS := {
	"staff": {
		"id": "staff",
		"name": "墨棍",
		"kind": "棍",
		"damage_mult": 1.0,
		"poise_mult": 1.0,
		"speed_mult": 1.0,
		"reach": 2.6,
		"stamina_mult": 1.0,
		"moveset": "staff_style",
		"mesh": {"shape": "cylinder", "length": 2.2, "radius": 0.05, "color": Color(0.62, 0.50, 0.30)},
		"hold_pos": Vector3(0.34, 1.15, 0.02),
	},
	"saber": {
		"id": "saber",
		"name": "单刀",
		"kind": "刀",
		"damage_mult": 1.12,
		"poise_mult": 1.25,
		"speed_mult": 0.86,
		"reach": 2.3,
		"stamina_mult": 0.9,
		"moveset": "saber_style",
		"mesh": {"shape": "box", "size": Vector3(0.06, 1.5, 0.20), "color": Color(0.78, 0.79, 0.82)},
		"hold_pos": Vector3(0.34, 1.15, 0.02),
	},
	"spear": {
		"id": "spear",
		"name": "长枪",
		"kind": "枪",
		"damage_mult": 0.95,
		"poise_mult": 1.1,
		"speed_mult": 0.95,
		"reach": 3.1,
		"stamina_mult": 1.1,
		"moveset": "staff_style",
		"mesh": {"shape": "spear", "length": 2.8, "radius": 0.035, "color": Color(0.45, 0.40, 0.32)},
		"hold_pos": Vector3(0.34, 1.15, 0.02),
	},
	"sword": {
		"id": "sword",
		"name": "长剑",
		"kind": "剑",
		"damage_mult": 1.0,
		"poise_mult": 0.95,
		"speed_mult": 0.9,
		"reach": 2.2,
		"stamina_mult": 0.95,
		"moveset": "saber_style",
		"mesh": {"shape": "box", "size": Vector3(0.05, 1.2, 0.13), "color": Color(0.72, 0.74, 0.80)},
		"hold_pos": Vector3(0.34, 1.15, 0.02),
	},
}

static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS[DEFAULT_ID])
