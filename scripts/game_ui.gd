extends CanvasLayer
## 行囊 / 药铺 / 锻造 三合一菜单（程序化 UI，鼠标操作）

const C_BG := Color(0.035, 0.040, 0.045, 0.94)
const C_GOLD := Color(0.85, 0.72, 0.42)
const C_TEXT := Color(0.88, 0.86, 0.80)
const C_DIM := Color(0.66, 0.64, 0.56)

const TABS := [
	{"id": "bag", "label": "行囊 (Tab)"},
	{"id": "shop", "label": "药铺 (G)"},
	{"id": "forge", "label": "锻造 (H)"},
]

var player: Node = null
var root: Control
var title_label: Label
var money_label: Label
var list_box: VBoxContainer
var hint_label: Label
var kind := "bag"
var is_open := false
var bag_filter := "all"

func setup(p: Node) -> void:
	player = p
	layer = 20
	_build()

func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var panel := VBoxContainer.new()
	panel.position = Vector2(180, 60)
	panel.size = Vector2(920, 610)
	panel.add_theme_constant_override("separation", 8)
	root.add_child(panel)

	var head := HBoxContainer.new()
	panel.add_child(head)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", C_GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)

	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 16)
	money_label.add_theme_color_override("font_color", C_GOLD)
	head.add_child(money_label)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 10)
	panel.add_child(tab_row)
	for t in TABS:
		var b := Button.new()
		b.text = t["label"]
		b.pressed.connect(func(): open(t["id"]))
		tab_row.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", C_DIM)
	panel.add_child(hint_label)

	root.visible = false

func open(k: String) -> void:
	kind = k
	is_open = true
	root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	is_open = false
	root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func toggle(k: String) -> void:
	if is_open and kind == k:
		close()
	else:
		open(k)

func refresh() -> void:
	if not is_open or not player:
		return
	money_label.text = "铜钱 %d" % player.money
	for c in list_box.get_children():
		c.queue_free()

	match kind:
		"bag":
			title_label.text = "行囊"
			_build_bag()
		"shop":
			title_label.text = "葛九药铺"
			_build_shop()
		"forge":
			title_label.text = "铁匠铺 · 锻器"
			_build_forge()

# ---------------- 行囊 ----------------
func _build_bag() -> void:
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 6)
	list_box.add_child(cat_row)
	for cat in ItemDB.CATEGORIES:
		var b := Button.new()
		b.text = String(cat["label"])
		b.disabled = (bag_filter == cat["id"])
		b.pressed.connect(func(): bag_filter = cat["id"]; refresh())
		cat_row.add_child(b)

	var any := false
	for id in player.bag:
		if int(player.bag[id]) <= 0:
			continue
		var def := ItemDB.get_item(id)
		if def.is_empty():
			continue
		if bag_filter != "all" and String(def.get("type", "")) != bag_filter:
			continue
		any = true
		_build_bag_row(id, def)
	if not any:
		_add_note("行囊空空，去野外采些药材，或从敌人身上搜寻。")
	hint_label.text = "点击条目使用丹药 / 装备防具 · Tab 关闭"

func _build_bag_row(id: String, def: Dictionary) -> void:
	var n: int = player.count_item(id)
	var type := String(def.get("type", ""))
	var title := "%s  ×%d" % [def.get("name", id), n]
	var desc := String(def.get("desc", ""))
	var action := ""
	var enabled := false
	var cb := Callable()

	match type:
		"pill":
			action = "服用"
			enabled = n > 0
			cb = func(): player.use_item(id); refresh()
			desc += "  [%s]" % def.get("hotkey", "")
		"gear":
			var slot := String(def.get("slot", ""))
			action = "已装备" if player.equipment.get(slot, "") == id else "装备"
			enabled = player.equipment.get(slot, "") != id
			cb = func(): player.equip_item(slot, id); refresh()
		"key":
			action = "信物"
			enabled = false
		_:
			action = "材料"
			enabled = false

	_add_row(title, desc, action, enabled, cb)

# ---------------- 药铺 ----------------
func _build_shop() -> void:
	for r in ItemDB.RECIPES:
		var out := ItemDB.get_item(String(r["out"]))
		var cost_parts: Array = []
		var can: bool = player.money >= int(r["money"])
		for k in r["cost"]:
			var need := int(r["cost"][k])
			var have: int = player.count_item(k)
			if have < need:
				can = false
			cost_parts.append("%s %d/%d" % [ItemDB.get_item(k).get("name", k), have, need])
		if int(r["money"]) > 0:
			cost_parts.append("铜钱 %d" % int(r["money"]))
		var cost_text := " · ".join(cost_parts)
		_add_row(
			"炼 %s" % out.get("name", r["out"]),
			cost_text + "　" + String(out.get("desc", "")),
			"炼 制", can,
			func(): player.craft(r); refresh())
	hint_label.text = "材料来自野外采集与敌人掉落 · G 关闭"

# ---------------- 锻造 ----------------
func _build_forge() -> void:
	var wid := String(player.current_weapon.get("id", "staff"))
	var wname := String(player.current_weapon.get("name", "武器"))
	var lv: int = player.forge_level(wid)
	var cost: Dictionary = player.forge_cost()
	var can: bool = player.can_forge()
	_add_row(
		"%s  +%d" % [wname, lv],
		"当前伤害倍率 ×%.2f　下一级需 青灵草 %d · 兽骨 %d · 铜钱 %d" % [
			player.forge_bonus(), cost.get("herb", 0), cost.get("bone", 0), cost.get("money", 0)],
		"锻 造", can,
		func(): player.forge_current(); refresh())
	_add_note("锻造提升当前武器的伤害倍率，每级 +6%，上限 +5。切换武学会更换武器，锻造等级按武器分别记录。")
	hint_label.text = "H 关闭"

# ---------------- 行工具 ----------------
func _add_row(title: String, desc: String, action: String, enabled: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", C_TEXT)
	col.add_child(t)
	var d := Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", 12)
	d.add_theme_color_override("font_color", C_DIM)
	col.add_child(d)
	row.add_child(col)

	if action != "":
		var b := Button.new()
		b.text = action
		b.disabled = not enabled
		b.custom_minimum_size = Vector2(90, 30)
		if enabled:
			b.pressed.connect(cb)
		row.add_child(b)

	list_box.add_child(row)

func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", C_DIM)
	list_box.add_child(l)
