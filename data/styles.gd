class_name StyleDB
## 武学（招式集）数据表：每套武学定义轻击连招与重击
## 段字段：dmg / poise / startup / active / recovery / stamina / reach / from_deg / to_deg

const DEFAULT_ID := "staff_style"

const STYLES := {
	"staff_style": {
		"id": "staff_style",
		"name": "墨棍法",
		"style": "均衡",
		"weapon_id": "staff",
		"unlock": null,
		"light_combo": [
			{"dmg": 14.0, "poise": 10.0, "startup": 0.10, "active": 0.12, "recovery": 0.18, "stamina": 8.0, "reach": 2.4, "from_deg": -70.0, "to_deg": 55.0},
			{"dmg": 12.0, "poise": 10.0, "startup": 0.08, "active": 0.12, "recovery": 0.20, "stamina": 8.0, "reach": 2.4, "from_deg": 50.0, "to_deg": -60.0},
			{"dmg": 22.0, "poise": 24.0, "startup": 0.16, "active": 0.14, "recovery": 0.34, "stamina": 12.0, "reach": 2.6, "from_deg": -105.0, "to_deg": 80.0},
		],
		"heavy": {"dmg": 40.0, "poise": 40.0, "startup": 0.40, "active": 0.16, "recovery": 0.50, "stamina": 28.0, "reach": 2.8, "from_deg": -125.0, "to_deg": 95.0},
	},
	"saber_style": {
		"id": "saber_style",
		"name": "斩刀诀",
		"style": "灵巧",
		"weapon_id": "saber",
		"unlock": null,
		"light_combo": [
			{"dmg": 11.0, "poise": 8.0, "startup": 0.07, "active": 0.09, "recovery": 0.14, "stamina": 6.0, "reach": 2.2, "from_deg": -55.0, "to_deg": 70.0},
			{"dmg": 10.0, "poise": 8.0, "startup": 0.06, "active": 0.09, "recovery": 0.13, "stamina": 6.0, "reach": 2.2, "from_deg": 65.0, "to_deg": -65.0},
			{"dmg": 18.0, "poise": 18.0, "startup": 0.12, "active": 0.11, "recovery": 0.24, "stamina": 9.0, "reach": 2.3, "from_deg": -85.0, "to_deg": 85.0},
		],
		"heavy": {"dmg": 34.0, "poise": 46.0, "startup": 0.34, "active": 0.14, "recovery": 0.44, "stamina": 24.0, "reach": 2.4, "from_deg": -95.0, "to_deg": 120.0},
	},
}

static func get_style(id: String) -> Dictionary:
	return STYLES.get(id, STYLES[DEFAULT_ID])
