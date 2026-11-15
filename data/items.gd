class_name ItemDB
## 物品表：丹药 / 材料 / 信物；装备条目从 EquipDB 间接解析

const CATEGORIES := [
	{"id": "all", "label": "全部"},
	{"id": "pill", "label": "丹药"},
	{"id": "material", "label": "材料"},
	{"id": "gear", "label": "装备"},
	{"id": "key", "label": "信物"},
]

const ITEMS := {
	"pill_heal": {
		"id": "pill_heal", "name": "回春丹", "type": "pill", "tag": "丹药",
		"desc": "立即恢复 45 点气血。", "price": 30,
		"effect": "heal", "value": 45.0, "hotkey": "R",
	},
	"pill_chi": {
		"id": "pill_chi", "name": "凝神散", "type": "pill", "tag": "丹药",
		"desc": "立即恢复 55 点体力。", "price": 26,
		"effect": "stamina", "value": 55.0, "hotkey": "T",
	},
	"pill_speed": {
		"id": "pill_speed", "name": "清风散", "type": "pill", "tag": "丹药",
		"desc": "10 秒内身法提升（移动更快）。", "price": 36,
		"effect": "speed", "value": 10.0, "hotkey": "Y",
	},
	"pill_guard": {
		"id": "pill_guard", "name": "金刚散", "type": "pill", "tag": "丹药",
		"desc": "8 秒内受到的伤害减半。", "price": 42,
		"effect": "guard", "value": 8.0, "hotkey": "U",
	},
	"herb": {
		"id": "herb", "name": "青灵草", "type": "material", "tag": "材料",
		"desc": "炼丹主药：回春丹 / 凝神散 / 清风散。", "price": 12,
	},
	"bloodsand": {
		"id": "bloodsand", "name": "血砂", "type": "material", "tag": "材料",
		"desc": "炼丹辅料：回春丹 / 金刚散。", "price": 16,
	},
	"bone": {
		"id": "bone", "name": "兽骨", "type": "material", "tag": "材料",
		"desc": "炼丹辅料：清风散 / 金刚散；亦可锻器。", "price": 10,
	},
	"ghostfire": {
		"id": "ghostfire", "name": "幽火", "type": "material", "tag": "材料",
		"desc": "炼丹辅料：凝神散。", "price": 22,
	},
	"key_buddha": {
		"id": "key_buddha", "name": "残破佛钥", "type": "key", "tag": "信物",
		"desc": "开启断崖佛门。", "price": 0,
	},
	"token_wuyan": {
		"id": "token_wuyan", "name": "幽火令", "type": "key", "tag": "信物",
		"desc": "无面令牌，背面刻着「无面」二字。", "price": 0,
	},
}

## 炼制配方：out = 产物，cost = 材料消耗，money = 铜钱
const RECIPES := [
	{"id": "craft_heal", "out": "pill_heal", "cost": {"herb": 2, "bloodsand": 1}, "money": 10},
	{"id": "craft_chi", "out": "pill_chi", "cost": {"herb": 2, "ghostfire": 1}, "money": 12},
	{"id": "craft_speed", "out": "pill_speed", "cost": {"herb": 1, "bone": 1}, "money": 14},
	{"id": "craft_guard", "out": "pill_guard", "cost": {"bloodsand": 1, "bone": 2}, "money": 18},
]

static func get_item(id: String) -> Dictionary:
	if ITEMS.has(id):
		return ITEMS[id]
	var eq := EquipDB.get_item(id)
	if not eq.is_empty():
		return {
			"id": id,
			"name": eq.get("name", id),
			"type": "gear",
			"tag": EquipDB.SLOT_NAMES.get(eq.get("slot", ""), "装备"),
			"desc": eq.get("desc", ""),
			"slot": eq.get("slot", ""),
		}
	return {}

static func get_recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r["id"] == id:
			return r
	return {}
