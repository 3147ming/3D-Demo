extends RefCounted
## 模型配色工具（Godot 材质层重做配色，不重展 UV、不依赖 Blender）
## 遍历模型下的 MeshInstance3D，按节点/网格名关键词分组，覆盖 StandardMaterial3D。
## 配色对齐现有 UI：墨黑 / 旧金 / 朱红 / 青灰，低模手绘质感。

## kind: "player" 墨刃行者；"enemy" 骷髅护法
static func apply(root: Node3D, kind: String) -> void:
	if root == null:
		return
	var rules: Dictionary = _player_rules() if kind == "player" else _enemy_rules()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var cfg: Dictionary = _match(m.name.to_lower(), rules)
		m.material_override = _make_material(cfg)

# ---------------- 配色规则 ----------------
static func _player_rules() -> Dictionary:
	return {
		# 躯干衣物
		"body": {"color": Color(0.11, 0.12, 0.14), "roughness": 0.85, "metallic": 0.0},
		# 兜帽
		"head": {"color": Color(0.07, 0.08, 0.09), "roughness": 0.90, "metallic": 0.0},
		# 衣袖
		"arm": {"color": Color(0.16, 0.17, 0.19), "roughness": 0.85, "metallic": 0.0},
		# 裤腿 / 靴
		"leg": {"color": Color(0.17, 0.14, 0.12), "roughness": 0.80, "metallic": 0.0},
		# 披风
		"cape": {"color": Color(0.09, 0.10, 0.11), "roughness": 0.90, "metallic": 0.0},
		# 模型自带武器挂件（短刀 / 弩 / 投掷物）
		"knife": {"color": Color(0.32, 0.27, 0.18), "roughness": 0.45, "metallic": 0.55},
		"crossbow": {"color": Color(0.32, 0.27, 0.18), "roughness": 0.45, "metallic": 0.55},
		"throwable": {"color": Color(0.32, 0.27, 0.18), "roughness": 0.45, "metallic": 0.55},
		"default": {"color": Color(0.11, 0.12, 0.14), "roughness": 0.85, "metallic": 0.0},
	}

static func _enemy_rules() -> Dictionary:
	return {
		# 眼睛（原 Glow 材质，保留发光）
		"eyes": {
			"color": Color(0.20, 0.80, 0.70), "roughness": 0.40, "metallic": 0.0,
			"emission": Color(0.20, 0.90, 0.75), "emission_energy": 1.6,
		},
		# 盔甲（头盔 / 躯干）
		"helmet": {"color": Color(0.20, 0.21, 0.23), "roughness": 0.50, "metallic": 0.45},
		"body": {"color": Color(0.20, 0.21, 0.23), "roughness": 0.50, "metallic": 0.45},
		# 披风
		"cloak": {"color": Color(0.33, 0.10, 0.09), "roughness": 0.85, "metallic": 0.0},
		# 骨骼（头 / 颌 / 臂 / 腿）
		"head": {"color": Color(0.68, 0.66, 0.60), "roughness": 0.85, "metallic": 0.0},
		"jaw": {"color": Color(0.68, 0.66, 0.60), "roughness": 0.85, "metallic": 0.0},
		"arm": {"color": Color(0.68, 0.66, 0.60), "roughness": 0.85, "metallic": 0.0},
		"leg": {"color": Color(0.68, 0.66, 0.60), "roughness": 0.85, "metallic": 0.0},
		"default": {"color": Color(0.68, 0.66, 0.60), "roughness": 0.85, "metallic": 0.0},
	}

# ---------------- 工具 ----------------
static func _match(name: String, rules: Dictionary) -> Dictionary:
	for kw in rules.keys():
		if kw == "default":
			continue
		if name.contains(kw):
			return rules[kw]
	return rules.get("default", {})

static func _make_material(cfg: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cfg.get("color", Color.WHITE)
	m.roughness = cfg.get("roughness", 0.8)
	m.metallic = cfg.get("metallic", 0.0)
	if cfg.has("emission"):
		m.emission_enabled = true
		m.emission = cfg["emission"]
		m.emission_energy_multiplier = cfg.get("emission_energy", 1.0)
	return m
