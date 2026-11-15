class_name EquipDB
## 装备数据表（防具 / 头饰 / 饰品；武器槽直接引用 WeaponDB）
## stats 可正可负，缺省视为 0：attack / defense / max_hp / max_stamina / poise_regen / move_speed

const SLOTS := ["weapon", "armor", "head", "accessory"]

const SLOT_NAMES := {
	"weapon": "武器",
	"armor": "衣甲",
	"head": "头饰",
	"accessory": "饰品",
}

const ITEMS := {
	"cloth_robe": {
		"id": "cloth_robe",
		"name": "粗布袍",
		"slot": "armor",
		"rarity": "普通",
		"stats": {"max_hp": 15.0, "defense": 2.0},
		"desc": "洗得发白的粗布衣，聊胜于无。",
		"drop_source": "enemy_guard",
	},
	"leather_armor": {
		"id": "leather_armor",
		"name": "皮甲",
		"slot": "armor",
		"rarity": "精良",
		"stats": {"defense": 6.0, "move_speed": -0.3},
		"desc": "硬皮钉甲，挡得住刀，也压得住腿。",
		"drop_source": "enemy_guard",
	},
	"headband": {
		"id": "headband",
		"name": "束发带",
		"slot": "head",
		"rarity": "普通",
		"stats": {"max_stamina": 10.0, "poise_regen": 1.5},
		"desc": "束住长发，挥棍不挡眼。",
		"drop_source": "enemy_guard",
	},
	"ink_jade": {
		"id": "ink_jade",
		"name": "墨玉坠",
		"slot": "accessory",
		"rarity": "稀有",
		"stats": {"attack": 3.0, "poise_regen": 0.5},
		"desc": "贴身一块凉玉，出手更快半分。",
		"drop_source": "enemy_guard",
	},
}

static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func items_for_slot(slot: String) -> Array:
	var out: Array = []
	for key in ITEMS:
		if ITEMS[key].get("slot", "") == slot:
			out.append(ITEMS[key])
	return out
