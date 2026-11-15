extends CharacterBody3D
class_name Player
## 玩家：第三人称动作角色，含移动/跳跃/轻击三连/重击/闪避无敌帧/识破/锁定

signal hp_changed(value: float, maxv: float)
signal stamina_changed(value: float, maxv: float)
signal chi_changed(value: float, maxv: float)

const C = preload("res://scripts/combat.gd")
const GlbLoader = preload("res://scripts/glb_loader.gd")

@onready var sfx: Node = get_node("/root/Sfx")

# ---- 模型接入：把文件放到 assets/models/ 下即可自动生效，缺省则用程序化人形 ----
const VISUAL_PATH := "res://assets/models/player.glb"
const VISUAL_HEIGHT := 1.8   # 模型统一缩放到的身高（米），按需要改
const VISUAL_YAW := 0.0      # 模型背对镜头时改成 PI
const ANIM_HINTS := {
	"idle": ["idle", "stand", "breath"],
	"run": ["run", "walk", "jog", "move"],
	"attack": ["attack", "slash", "swing", "combo", "punch"],
	"dodge": ["dodge", "roll", "evade"],
	"parry": ["parry", "block", "guard"],
	"hurt": ["hurt", "hit", "damage", "impact"],
	"death": ["death", "die", "dead"],
}
# 循环播放的动画（其余按一次性处理）
const LOOP_WORDS := ["idle", "walk", "run", "blocking", "spellcasting", "aiming"]
# 轻击连段动画（KayKit 命名，按 combo_idx 取用；模型没有这些动画时自动回退）
const ATTACK_CLIPS := [
	"1H_Melee_Attack_Slice_Diagonal",
	"1H_Melee_Attack_Slice_Horizontal",
	"1H_Melee_Attack_Chop",
	"1H_Melee_Attack_Stab",
]
const HEAVY_CLIP := "2H_Melee_Attack_Spin"

# 状态
enum State { IDLE, MOVE, ATTACK, DODGE, PARRY, HURT, DEAD }
var state := State.IDLE

# 资源
var hp: float = C.PLAYER_MAX_HP
var stamina: float = C.PLAYER_MAX_STAMINA
var stamina_timer := 0.0
var combo_idx := 0
var combo_buffer := 0.0

# 攻击计时
var attack_timer := 0.0
var attack_phase := ""  # startup / active / recovery
var current_attack: Dictionary = {}

# 闪避
var dodge_dir := Vector3.ZERO
var dodge_timer := 0.0

# 识破
var parry_timer := 0.0
var gait_phase := 0.0

# 内力 / 法术 / 变身
var chi: float = C.PLAYER_MAX_CHI
var chi_timer := 0.0
var spell_cd := {"freeze": 0.0, "blink": 0.0, "shield": 0.0}
var transformed := false
var transform_timer := 0.0
var blink_invuln := 0.0

# 相机
var camera_pivot: Node3D
var camera: Camera3D
var yaw := 0.0            # 目标 yaw（鼠标/锁定写入）
var pitch := 0.15         # 目标 pitch
var cam_yaw := 0.0        # 平滑后的实际 yaw
var cam_pitch := 0.15
var lock_target: Node3D = null
var lock_marker: MeshInstance3D

# 近景越肩机位（相对 pivot：右偏、略高、身后）
const CAM_OFFSET := Vector3(0.55, 0.72, 3.4)
const CAM_FOLLOW_K := 14.0    # 位置平滑系数
const CAM_ROTATE_K := 18.0    # 朝向平滑系数

# 节点引用
var body_pivot: Node3D
var torso: MeshInstance3D
var head_pivot: Node3D
var arm_L: Node3D
var arm_R: Node3D
var forearm_L: Node3D
var forearm_R: Node3D
var leg_L: Node3D
var leg_R: Node3D
var calf_L: Node3D
var calf_R: Node3D
var body_material: StandardMaterial3D
var weapon_pivot: Node3D
var weapon_mesh: MeshInstance3D
var hitbox: Hitbox
var anim_tween: Tween

# GLB 视觉（存在模型文件时启用）
var visual_root: Node3D = null
var anim_player: AnimationPlayer = null
var anim_map: Dictionary = {}
var current_anim := ""

# 武器 / 武学 / 装备 / 行囊
var current_weapon: Dictionary = {}
var current_style: Dictionary = {}
var equipment := {"weapon": "", "armor": "", "head": "", "accessory": ""}

# 蓄力重击
var heavy_charging := false
var heavy_charge_time := 0.0
var heavy_charge_level := 0

# 武器拖尾
var trail_points: Array = []
var trail_mesh: ImmediateMesh
var trail_mi: MeshInstance3D
var trail_active := false
var trail_color: Color = Color(0.7, 0.85, 1.0)
var current_attack_step := 0.0      # 当前攻击前进步伐总距离
var current_attack_step_done := 0.0 # 已前进距离
var current_attack_body_turn := 0.0 # 身体目标转向弧度
var current_attack_body_turn_done := 0.0
var weapon_emissive: StandardMaterial3D = null
var shake_offset: Vector3 = Vector3.ZERO  # 外部写入的屏幕震动偏移
var bag := {
	"pill_heal": 2, "pill_chi": 1, "pill_speed": 1, "pill_guard": 1,
	"herb": 3, "bloodsand": 2, "bone": 2, "ghostfire": 1,
	"cloth_robe": 1, "leather_armor": 1, "headband": 1, "ink_jade": 1,
	"key_buddha": 1,
}
var money := 120
var forge_levels := {}
var buff_speed := 0.0
var buff_guard := 0.0
var ui: CanvasLayer = null

func _ready() -> void:
	_build_self()
	collision_layer = 1
	collision_mask = 1 | (1 << 2)
	add_to_group("player")
	add_to_group("hurtbox")
	load_bindings()
	equip_style(StyleDB.DEFAULT_ID)
	if not load_game():
		hp = get_max_hp()
		stamina = get_max_stamina()
		hp_changed.emit(hp, get_max_hp())
		stamina_changed.emit(stamina, get_max_stamina())
	chi = C.PLAYER_MAX_CHI
	chi_changed.emit(chi, C.PLAYER_MAX_CHI)
	_setup_visual()

## 尝试加载 GLB；失败则保持程序化人形
func _setup_visual() -> void:
	var r := GlbLoader.attach_model(self, VISUAL_PATH, VISUAL_HEIGHT, "[玩家模型]")
	if r.is_empty():
		return
	visual_root = r["root"]
	visual_root.rotation.y = VISUAL_YAW
	anim_player = r["anim"]
	if anim_player != null:
		anim_map = GlbLoader.auto_map(r["clips"], ANIM_HINTS)
		GlbLoader.configure_loops(anim_player, LOOP_WORDS)
		print("[玩家模型] 动画映射：", anim_map)
	# 有真实模型后隐藏程序化人形（节点保留，逻辑仍可运行）
	if body_pivot != null:
		body_pivot.visible = false
	if weapon_mesh != null:
		weapon_mesh.visible = false

func _build_self() -> void:
	# 胶囊碰撞
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.shape.radius = 0.4
	col.shape.height = 1.8
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# ---- 程序化人形（body_pivot 为整体锚点，后续可换 GLTF 蒙皮）----
	body_pivot = Node3D.new()
	add_child(body_pivot)

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color(0.52, 0.58, 0.66)
	body_material.roughness = 0.75

	# 躯干 / 骨盆
	torso = _make_mesh(_capsule(0.21, 0.70), body_material, Vector3(0, 1.18, 0))
	body_pivot.add_child(torso)
	var pelvis := _make_mesh(_capsule(0.18, 0.26), body_material, Vector3(0, 0.86, 0))
	body_pivot.add_child(pelvis)

	# 头颈
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 1.52, 0)
	body_pivot.add_child(head_pivot)
	var neck := _make_mesh(_capsule(0.06, 0.12), body_material, Vector3(0, 0.04, 0))
	head_pivot.add_child(neck)
	var head := _make_mesh(_sphere(0.20), _skin_material(), Vector3(0, 0.20, 0))
	head_pivot.add_child(head)

	# 双臂：肩 → 上臂 + 肘 → 前臂 + 手
	arm_L = Node3D.new()
	arm_L.position = Vector3(-0.28, 1.34, 0)
	body_pivot.add_child(arm_L)
	arm_L.add_child(_make_mesh(_capsule(0.085, 0.42), body_material, Vector3(0, -0.21, 0)))
	forearm_L = Node3D.new()
	forearm_L.position = Vector3(0, -0.42, 0)
	arm_L.add_child(forearm_L)
	forearm_L.add_child(_make_mesh(_capsule(0.07, 0.40), body_material, Vector3(0, -0.20, 0)))
	forearm_L.add_child(_make_mesh(_box(Vector3(0.10, 0.12, 0.10)), _skin_material(), Vector3(0, -0.42, 0)))

	arm_R = Node3D.new()
	arm_R.position = Vector3(0.28, 1.34, 0)
	body_pivot.add_child(arm_R)
	arm_R.add_child(_make_mesh(_capsule(0.085, 0.42), body_material, Vector3(0, -0.21, 0)))
	forearm_R = Node3D.new()
	forearm_R.position = Vector3(0, -0.42, 0)
	arm_R.add_child(forearm_R)
	forearm_R.add_child(_make_mesh(_capsule(0.07, 0.40), body_material, Vector3(0, -0.20, 0)))
	forearm_R.add_child(_make_mesh(_box(Vector3(0.10, 0.12, 0.10)), _skin_material(), Vector3(0, -0.42, 0)))

	# 双腿：髋 → 大腿 + 膝 → 小腿 + 脚
	leg_L = Node3D.new()
	leg_L.position = Vector3(-0.16, 0.84, 0)
	body_pivot.add_child(leg_L)
	leg_L.add_child(_make_mesh(_capsule(0.10, 0.42), body_material, Vector3(0, -0.21, 0)))
	calf_L = Node3D.new()
	calf_L.position = Vector3(0, -0.42, 0)
	leg_L.add_child(calf_L)
	calf_L.add_child(_make_mesh(_capsule(0.085, 0.40), body_material, Vector3(0, -0.20, 0)))
	calf_L.add_child(_make_mesh(_box(Vector3(0.12, 0.08, 0.24)), body_material, Vector3(0, -0.42, 0.05)))

	leg_R = Node3D.new()
	leg_R.position = Vector3(0.16, 0.84, 0)
	body_pivot.add_child(leg_R)
	leg_R.add_child(_make_mesh(_capsule(0.10, 0.42), body_material, Vector3(0, -0.21, 0)))
	calf_R = Node3D.new()
	calf_R.position = Vector3(0, -0.42, 0)
	leg_R.add_child(calf_R)
	calf_R.add_child(_make_mesh(_capsule(0.085, 0.40), body_material, Vector3(0, -0.20, 0)))
	calf_R.add_child(_make_mesh(_box(Vector3(0.12, 0.08, 0.24)), body_material, Vector3(0, -0.42, 0.05)))

	# 武器枢轴（路径保持不变，武器网格与 hitbox 挂在下面）
	weapon_pivot = Node3D.new()
	weapon_pivot.position = Vector3(0.34, 1.0, 0.06)
	add_child(weapon_pivot)

	# 攻击判定盒（look_at 使 -Z 为前方，判定盒必须放在 -Z 侧）
	hitbox = Hitbox.new()
	var hs := CollisionShape3D.new()
	hs.shape = BoxShape3D.new()
	hs.shape.size = Vector3(1.2, 1.4, 2.2)
	hitbox.add_child(hs)
	hitbox.position = Vector3(0, 0.15, -1.4)
	weapon_pivot.add_child(hitbox)
	hitbox.hit_landed.connect(_on_hit_landed)

	# 武器拖尾（ImmediateMesh 绘制带状轨迹）
	trail_mesh = ImmediateMesh.new()
	trail_mi = MeshInstance3D.new()
	trail_mi.mesh = trail_mesh
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(1, 1, 1, 0.8)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.emissive_enabled = true
	tmat.emission = Color(0.6, 0.8, 1.0)
	tmat.emission_energy_multiplier = 2.0
	trail_mi.material_override = tmat
	add_child(trail_mi)

	# 相机（放置在 +Z 侧，相机自身看向 -Z，正好面向角色）
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.6, 0)
	camera_pivot.top_level = true   # 不与角色旋转耦合，避免角色转身带动镜头
	add_child(camera_pivot)
	camera_pivot.global_position = global_position + Vector3(0, 1.6, 0)
	camera = Camera3D.new()
	camera.position = CAM_OFFSET
	camera.fov = 70.0
	camera.current = true
	camera_pivot.add_child(camera)

	# 锁定标记：面向相机的小圆环
	lock_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.40
	torus.rings = 24
	torus.ring_segments = 8
	lock_marker.mesh = torus
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.85, 0.70, 0.35)
	mmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mmat.no_depth_test = true
	lock_marker.material_override = mmat
	lock_marker.visible = false
	add_child(lock_marker)

# ---------------- 占位几何工具 ----------------
func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m

func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _make_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi

func _skin_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.74, 0.64)
	m.roughness = 0.8
	return m

# ---------------- 武器 / 武学 ----------------
func equip_weapon(id: String) -> void:
	current_weapon = WeaponDB.get_weapon(id)
	if weapon_mesh and is_instance_valid(weapon_mesh):
		weapon_mesh.queue_free()
	weapon_mesh = _build_weapon_mesh(current_weapon)
	weapon_pivot.add_child(weapon_mesh)
	_apply_reach(float(current_weapon.get("reach", 2.4)))

func _build_weapon_mesh(w: Dictionary) -> MeshInstance3D:
	var spec: Dictionary = w.get("mesh", {})
	weapon_emissive = StandardMaterial3D.new()
	weapon_emissive.albedo_color = spec.get("color", Color(0.7, 0.7, 0.7))
	weapon_emissive.roughness = 0.35
	weapon_emissive.metallic = 0.6 if spec.get("shape", "cylinder") == "box" else 0.2
	weapon_emissive.emissive_enabled = true
	weapon_emissive.emission = Color(0.15, 0.12, 0.08)
	weapon_emissive.emission_energy_multiplier = 0.5

	var mi := MeshInstance3D.new()
	match spec.get("shape", "cylinder"):
		"box":
			var bm := BoxMesh.new()
			bm.size = spec.get("size", Vector3(0.06, 1.4, 0.16))
			mi.mesh = bm
			mi.position = Vector3(0, 0.7, 0)
		"spear":
			var cm := CylinderMesh.new()
			cm.top_radius = spec.get("radius", 0.035)
			cm.bottom_radius = spec.get("radius", 0.035)
			cm.height = spec.get("length", 2.8)
			mi.mesh = cm
			mi.position = Vector3(0, spec.get("length", 2.8) * 0.5, 0)
			var tip := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.0
			tm.bottom_radius = 0.07
			tm.height = 0.3
			tip.mesh = tm
			tip.position = Vector3(0, spec.get("length", 2.8) + 0.15, 0)
			tip.material_override = weapon_emissive
			mi.add_child(tip)
		_:
			var cm2 := CylinderMesh.new()
			cm2.top_radius = spec.get("radius", 0.05)
			cm2.bottom_radius = spec.get("radius", 0.05)
			cm2.height = spec.get("length", 2.2)
			mi.mesh = cm2
			mi.position = Vector3(0, spec.get("length", 2.2) * 0.5, 0)
	mi.material_override = weapon_emissive
	# 已接入 GLB 模型时隐藏程序化武器（模型通常自带）
	if visual_root != null:
		mi.visible = false
	return mi

func _apply_reach(reach: float) -> void:
	var hs := hitbox.get_child(0) as CollisionShape3D
	if hs and hs.shape is BoxShape3D:
		hs.shape.size = Vector3(1.2, 1.4, reach)
	hitbox.position = Vector3(0, 0.15, -reach * 0.6)

func equip_style(id: String) -> void:
	current_style = StyleDB.get_style(id)
	combo_idx = 0
	equipment["weapon"] = String(current_style.get("weapon_id", WeaponDB.DEFAULT_ID))
	equip_weapon(equipment["weapon"])

# ---------------- 属性汇总层（基础值 + 装备加成） ----------------
func get_base(attr: String) -> float:
	match attr:
		"max_hp": return C.PLAYER_MAX_HP
		"max_stamina": return C.PLAYER_MAX_STAMINA
		"attack": return 0.0
		"defense": return 0.0
		"poise_regen": return 0.0
		"move_speed": return C.PLAYER_SPEED
		"stamina_regen": return C.PLAYER_STAMINA_REGEN
	return 0.0

func get_equip_bonus(attr: String) -> float:
	var total := 0.0
	for slot in equipment:
		if slot == "weapon":
			continue
		var id: String = equipment[slot]
		if id == "":
			continue
		var item := EquipDB.get_item(id)
		if item.is_empty():
			continue
		var stats: Dictionary = item.get("stats", {})
		total += float(stats.get(attr, 0.0))
	return total

func get_stat(attr: String) -> float:
	return get_base(attr) + get_equip_bonus(attr)

func get_max_hp() -> float: return get_stat("max_hp")
func get_max_stamina() -> float: return get_stat("max_stamina")
func get_attack() -> float: return get_stat("attack")
func get_defense() -> float: return get_stat("defense")
func get_move_speed() -> float: return get_stat("move_speed")
func get_stamina_regen() -> float: return get_stat("stamina_regen") + get_stat("poise_regen")

func equip_item(slot: String, id: String) -> bool:
	if not EquipDB.SLOTS.has(slot) or slot == "weapon":
		return false
	if id != "":
		if count_item(id) <= 0:
			return false
		if String(EquipDB.get_item(id).get("slot", "")) != slot:
			return false

	var old_hp_max := get_max_hp()
	var old_st_max := get_max_stamina()
	equipment[slot] = id
	var new_hp_max := get_max_hp()
	var new_st_max := get_max_stamina()

	# 上限变化：提升补值、降低钳制
	if new_hp_max > old_hp_max:
		hp += new_hp_max - old_hp_max
	hp = minf(hp, new_hp_max)
	if new_st_max > old_st_max:
		stamina += new_st_max - old_st_max
	stamina = minf(stamina, new_st_max)
	hp_changed.emit(hp, new_hp_max)
	stamina_changed.emit(stamina, new_st_max)
	return true

func unequip_slot(slot: String) -> void:
	equip_item(slot, "")

# ---------------- 行囊 / 丹药 / 炼制 / 锻造 ----------------
func count_item(id: String) -> int:
	return int(bag.get(id, 0))

func add_item(id: String, n: int = 1) -> void:
	bag[id] = count_item(id) + n
	_refresh_ui()

func remove_item(id: String, n: int = 1) -> bool:
	if count_item(id) < n:
		return false
	bag[id] = count_item(id) - n
	_refresh_ui()
	return true

func _refresh_ui() -> void:
	if ui and ui.has_method("refresh"):
		ui.refresh()

func use_item(id: String) -> bool:
	var def := ItemDB.get_item(id)
	if String(def.get("type", "")) != "pill" or count_item(id) <= 0:
		return false
	match String(def.get("effect", "")):
		"heal":
			if hp >= get_max_hp():
				return false
			hp = minf(hp + float(def.get("value", 45.0)), get_max_hp())
			hp_changed.emit(hp, get_max_hp())
		"stamina":
			if stamina >= get_max_stamina():
				return false
			stamina = minf(stamina + float(def.get("value", 55.0)), get_max_stamina())
			stamina_changed.emit(stamina, get_max_stamina())
		"speed":
			buff_speed = float(def.get("value", 10.0))
		"guard":
			buff_guard = float(def.get("value", 8.0))
		_:
			return false
	bag[id] = count_item(id) - 1
	sfx.play("coin")
	_refresh_ui()
	return true

func craft(recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	var cost: Dictionary = recipe.get("cost", {})
	for k in cost:
		if count_item(k) < int(cost[k]):
			return false
	if money < int(recipe.get("money", 0)):
		return false
	for k in cost:
		bag[k] = count_item(k) - int(cost[k])
	money -= int(recipe.get("money", 0))
	bag[recipe["out"]] = count_item(String(recipe["out"])) + 1
	_refresh_ui()
	return true

func forge_level(weapon_id: String) -> int:
	return int(forge_levels.get(weapon_id, 0))

func forge_cost() -> Dictionary:
	var lv := forge_level(String(current_weapon.get("id", "staff")))
	return {"herb": 2 + lv, "bone": 1 + lv, "money": 40 + lv * 30}

func can_forge() -> bool:
	var wid := String(current_weapon.get("id", "staff"))
	if forge_level(wid) >= 5:
		return false
	var cost := forge_cost()
	return count_item("herb") >= int(cost["herb"]) \
		and count_item("bone") >= int(cost["bone"]) \
		and money >= int(cost["money"])

func forge_current() -> bool:
	if not can_forge():
		return false
	var wid := String(current_weapon.get("id", "staff"))
	var cost := forge_cost()
	bag["herb"] = count_item("herb") - int(cost["herb"])
	bag["bone"] = count_item("bone") - int(cost["bone"])
	money -= int(cost["money"])
	forge_levels[wid] = forge_level(wid) + 1
	_refresh_ui()
	return true

func forge_bonus() -> float:
	return 1.0 + 0.06 * forge_level(String(current_weapon.get("id", "staff")))

# ---------------- 药铺购买 ----------------
func buy_item(id: String) -> bool:
	var def := ItemDB.get_item(id)
	var price := int(def.get("price", 0))
	if price <= 0 or money < price:
		return false
	money -= price
	add_item(id, 1)
	return true

# ---------------- 存档 ----------------
const SAVE_PATH := "user://inkblade_save.json"
const BIND_PATH := "user://inkblade_keybinds.json"

func save_game() -> void:
	var data := {
		"money": money,
		"bag": bag,
		"equipment": equipment,
		"forge": forge_levels,
		"hp": hp,
		"stamina": stamina,
		"style": String(current_style.get("id", StyleDB.DEFAULT_ID)),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false

	money = int(data.get("money", money))
	var saved_bag = data.get("bag", {})
	if typeof(saved_bag) == TYPE_DICTIONARY:
		for k in saved_bag:
			bag[String(k)] = int(saved_bag[k])
	var saved_forge = data.get("forge", {})
	if typeof(saved_forge) == TYPE_DICTIONARY:
		for k in saved_forge:
			forge_levels[String(k)] = int(saved_forge[k])

	# 先恢复武学（同时换武器），再逐槽恢复装备
	equip_style(String(data.get("style", StyleDB.DEFAULT_ID)))
	var saved_eq = data.get("equipment", {})
	if typeof(saved_eq) == TYPE_DICTIONARY:
		for slot in ["armor", "head", "accessory"]:
			equip_item(slot, String(saved_eq.get(slot, "")))

	hp = minf(float(data.get("hp", get_max_hp())), get_max_hp())
	stamina = minf(float(data.get("stamina", get_max_stamina())), get_max_stamina())
	hp_changed.emit(hp, get_max_hp())
	stamina_changed.emit(stamina, get_max_stamina())
	return true

# ---------------- 键位自定义 ----------------
var bindings := {}

func load_bindings() -> void:
	if not FileAccess.file_exists(BIND_PATH):
		return
	var f := FileAccess.open(BIND_PATH, FileAccess.READ)
	if not f:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		for k in data:
			bindings[String(k)] = int(data[k])
		for action in bindings:
			_replace_key(String(action), int(bindings[action]))

func _replace_key(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var k := InputEventKey.new()
	k.keycode = code
	InputMap.action_add_event(action, k)

func rebind(action: String, code: int) -> void:
	bindings[action] = code
	_replace_key(action, code)
	var f := FileAccess.open(BIND_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(bindings))
		f.close()
	_refresh_ui()

func key_label(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).keycode)
	return "—"

# ---------------- 法术 / 变身 ----------------
func _spell_ready(key: String, def: Dictionary) -> bool:
	if float(spell_cd.get(key, 0.0)) > 0.0:
		return false
	var cost := float(def["cost"])
	if chi < cost:
		return false
	chi -= cost
	chi_timer = C.PLAYER_CHI_DELAY
	spell_cd[key] = float(def["cd"])
	chi_changed.emit(chi, C.PLAYER_MAX_CHI)
	sfx.play("spell")
	return true

func cast_freeze() -> bool:
	if not _spell_ready("freeze", C.SPELL_FREEZE):
		return false
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("apply_freeze"):
			e.apply_freeze(float(C.SPELL_FREEZE["duration"]))
	return true

func cast_blink() -> bool:
	if not _spell_ready("blink", C.SPELL_BLINK):
		return false
	global_position -= transform.basis.z * float(C.SPELL_BLINK["distance"])
	blink_invuln = float(C.SPELL_BLINK["invuln"])
	return true

func cast_shield() -> bool:
	if not _spell_ready("shield", C.SPELL_SHIELD):
		return false
	buff_guard = maxf(buff_guard, float(C.SPELL_SHIELD["duration"]))
	return true

func try_transform() -> void:
	if transformed or chi < C.TRANSFORM_COST:
		return
	chi -= C.TRANSFORM_COST
	chi_changed.emit(chi, C.PLAYER_MAX_CHI)
	transformed = true
	transform_timer = C.TRANSFORM_DURATION
	sfx.play("transform")
	if body_pivot:
		body_pivot.scale = Vector3(1.15, 1.15, 1.15)
	if body_material:
		body_material.emissive_enabled = true
		body_material.emission = Color(0.55, 0.22, 0.10)

func _end_transform() -> void:
	transformed = false
	transform_timer = 0.0
	if body_pivot:
		body_pivot.scale = Vector3.ONE
	if body_material:
		body_material.emissive_enabled = false
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.global_position.distance_to(global_position) <= C.TRANSFORM_END_RADIUS:
			if e.has_method("take_hit"):
				e.take_hit(C.TRANSFORM_END_DAMAGE, 40.0, global_position, 10.0)

func _scaled_move(base: Dictionary) -> Dictionary:
	var m := base.duplicate()
	var w := current_weapon
	var sp := float(w.get("speed_mult", 1.0))
	m["startup"] = float(base.get("startup", 0.1)) * sp
	m["active"] = float(base.get("active", 0.1)) * sp
	m["recovery"] = float(base.get("recovery", 0.2)) * sp
	m["dmg"] = (float(base.get("dmg", 10.0)) + get_attack()) \
		* float(w.get("damage_mult", 1.0)) * forge_bonus() \
		* (C.TRANSFORM_DAMAGE_MULT if transformed else 1.0)
	m["poise"] = float(base.get("poise", 10.0)) * float(w.get("poise_mult", 1.0))
	m["stamina"] = float(base.get("stamina", 8.0)) * float(w.get("stamina_mult", 1.0))
	if w.has("reach"):
		m["reach"] = float(w["reach"])
	return m

func _light_moves() -> Array:
	return current_style.get("light_combo", [])

func _heavy_move() -> Dictionary:
	return current_style.get("heavy", {})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clamp(pitch - event.relative.y * 0.003, -0.5, 0.35)
	elif event is InputEventMouseButton and event.pressed:
		# 菜单打开时把鼠标交给 UI
		if ui and ui.is_open:
			return
		# 仅在鼠标可见时点击才重捕获；已捕获时左右键留给攻击 action
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if ui and ui.is_open:
				ui.close()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_TAB:
			if ui: ui.toggle("bag")
		elif event.keycode == KEY_G:
			if ui: ui.toggle("shop")
		elif event.keycode == KEY_H:
			if ui: ui.toggle("forge")
		elif event.keycode == KEY_B:
			if ui: ui.toggle("keys")
		elif event.keycode == KEY_R:
			use_item("pill_heal")
		elif event.keycode == KEY_T:
			use_item("pill_chi")
		elif event.keycode == KEY_Y:
			use_item("pill_speed")
		elif event.keycode == KEY_U:
			use_item("pill_guard")
		elif event.keycode == KEY_Z:
			cast_freeze()
		elif event.keycode == KEY_X:
			cast_blink()
		elif event.keycode == KEY_V:
			cast_shield()
		elif event.keycode == KEY_F:
			try_transform()
		elif event.keycode == KEY_P:
			if ui: ui.toggle("help")
		elif event.keycode == KEY_N:
			if get_parent() and get_parent().has_method("cycle_weather"):
				get_parent().cycle_weather()
		elif event.keycode == KEY_M:
			if get_parent() and get_parent().has_method("toggle_difficulty"):
				get_parent().toggle_difficulty()
		elif event.keycode == KEY_F5:
			save_game()
		elif event.keycode == KEY_F9:
			load_game()
		elif event.keycode == KEY_1:
			equip_style("staff_style")
		elif event.keycode == KEY_2:
			equip_style("saber_style")
		elif event.keycode == KEY_3:
			equip_item("armor", "cloth_robe")
		elif event.keycode == KEY_4:
			equip_item("armor", "leather_armor")
		elif event.keycode == KEY_5:
			equip_item("head", "headband")
		elif event.keycode == KEY_6:
			equip_item("accessory", "ink_jade")
		elif event.keycode == KEY_0:
			unequip_slot("armor")
			unequip_slot("head")
			unequip_slot("accessory")

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# 菜单打开时暂停角色动作
	if ui and ui.is_open:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		move_and_slide()
		_update_pose(delta)
		_update_camera(delta)
		return

	buff_speed = maxf(0.0, buff_speed - delta)
	buff_guard = maxf(0.0, buff_guard - delta)

	# 内力回复与法术冷却
	chi_timer -= delta
	if chi_timer <= 0.0:
		chi = minf(chi + C.PLAYER_CHI_REGEN * delta, C.PLAYER_MAX_CHI)
		chi_changed.emit(chi, C.PLAYER_MAX_CHI)
	for k in spell_cd:
		spell_cd[k] = maxf(0.0, float(spell_cd[k]) - delta)
	blink_invuln = maxf(0.0, blink_invuln - delta)
	if transformed:
		transform_timer -= delta
		if transform_timer <= 0.0:
			_end_transform()

	# 全局输入缓冲：攻击/闪避/识破在任何状态都能录入（用于连招衔接）
	_handle_global_input()

	match state:
		State.IDLE, State.MOVE:
			_update_move(delta)
		State.ATTACK:
			_update_attack(delta)
		State.DODGE:
			_update_dodge(delta)
		State.PARRY:
			_update_parry(delta)
		State.HURT:
			_update_hurt(delta)

	# 体力回复
	stamina_timer -= delta
	if stamina_timer <= 0.0 and state != State.ATTACK:
		stamina = min(stamina + get_stamina_regen() * delta, get_max_stamina())
		stamina_changed.emit(stamina, get_max_stamina())

	_update_lock(delta)
	move_and_slide()

	_update_pose(delta)
	_update_trail(delta)
	_update_camera(delta)
	_update_marker()

# ---------------- 程序化姿态 ----------------
func _update_pose(delta: float) -> void:
	# 有 GLB 模型时改由动画驱动，不再跑程序化姿态
	if visual_root != null:
		_sync_anim()
		return
	if not body_pivot:
		return

	# 躯干倾角：受击后仰 / 闪避前倾
	var tilt := 0.0
	if state == State.HURT:
		tilt = 0.18
	elif state == State.DODGE:
		tilt = -0.22
	body_pivot.rotation.x = lerp(body_pivot.rotation.x, tilt, 0.2)

	var planar := Vector2(velocity.x, velocity.z).length()
	var amp := clampf(planar / C.PLAYER_SPEED, 0.0, 1.0)
	gait_phase += delta * (6.0 + 6.0 * amp)

	if state == State.ATTACK:
		# 持械臂跟随武器挥动（多轴），另一侧维持平衡
		var wrx: float = weapon_pivot.rotation.x
		var wry: float = weapon_pivot.rotation.y
		arm_R.rotation.x = lerp(arm_R.rotation.x, wrx * 0.75, 0.45)
		arm_R.rotation.y = lerp(arm_R.rotation.y, wry * 0.5, 0.4)
		forearm_R.rotation.x = lerp(forearm_R.rotation.x, wrx * 0.25, 0.4)
		arm_L.rotation.x = lerp(arm_L.rotation.x, 0.25, 0.2)
		arm_L.rotation.y = lerp(arm_L.rotation.y, -wry * 0.3, 0.3)
		leg_L.rotation.x = lerp(leg_L.rotation.x, 0.18, 0.15)
		leg_R.rotation.x = lerp(leg_R.rotation.x, -0.12, 0.15)
		calf_L.rotation.x = lerp(calf_L.rotation.x, -0.15, 0.15)
		calf_R.rotation.x = lerp(calf_R.rotation.x, 0.0, 0.15)
		return

	if amp > 0.08:
		# 步态：双腿交替、双臂反向摆动
		var s := sin(gait_phase)
		var swing := 0.55 * amp
		leg_L.rotation.x = s * swing
		leg_R.rotation.x = -s * swing
		calf_L.rotation.x = maxf(0.0, -s) * 0.7 * amp
		calf_R.rotation.x = maxf(0.0, s) * 0.7 * amp
		arm_L.rotation.x = -s * 0.45 * amp
		arm_R.rotation.x = s * 0.35 * amp
		forearm_L.rotation.x = -0.25 * amp
		forearm_R.rotation.x = -0.25 * amp
	else:
		# 站立呼吸
		var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.05
		leg_L.rotation.x = lerp(leg_L.rotation.x, 0.0, 0.15)
		leg_R.rotation.x = lerp(leg_R.rotation.x, 0.0, 0.15)
		calf_L.rotation.x = lerp(calf_L.rotation.x, 0.0, 0.15)
		calf_R.rotation.x = lerp(calf_R.rotation.x, 0.0, 0.15)
		arm_L.rotation.x = lerp(arm_L.rotation.x, breathe, 0.12)
		arm_R.rotation.x = lerp(arm_R.rotation.x, -breathe, 0.12)
		forearm_L.rotation.x = lerp(forearm_L.rotation.x, 0.0, 0.12)
		forearm_R.rotation.x = lerp(forearm_R.rotation.x, 0.0, 0.12)

# ---------------- GLB 动画驱动 ----------------
## 按战斗状态切换动画；同名动画不会重复重启
func _sync_anim() -> void:
	if anim_player == null:
		return
	var want := ""
	match state:
		State.IDLE:
			want = _clip("idle")
		State.MOVE:
			want = _clip("run")
		State.ATTACK:
			want = _attack_clip()
		State.DODGE:
			want = _dodge_clip()
		State.PARRY:
			want = _clip("parry")
		State.HURT:
			want = _clip("hurt")
		State.DEAD:
			want = _clip("death")
	if want == "" or want == current_anim:
		return
	current_anim = want
	var spd := 1.0
	if state == State.MOVE:
		# 跑步动画随实际移动速度加速/减速
		spd = clampf(Vector2(velocity.x, velocity.z).length() / maxf(1.0, C.PLAYER_SPEED), 0.6, 1.6)
	anim_player.play(want, 0.15, spd)

## 取动画名；缺该项时回退到 idle，避免卡在上一个姿势
func _clip(key: String) -> String:
	var v: String = String(anim_map.get(key, ""))
	if v == "":
		v = String(anim_map.get("idle", ""))
	return v

## 攻击动画：重击用旋转斩，轻击按连段序号切换不同挥砍
func _attack_clip() -> String:
	if anim_player == null:
		return ""
	if heavy_flag and anim_player.has_animation(HEAVY_CLIP):
		return HEAVY_CLIP
	if ATTACK_CLIPS.size() > 0:
		var idx: int = clampi(combo_idx, 0, ATTACK_CLIPS.size() - 1)
		var nm: String = ATTACK_CLIPS[idx]
		if anim_player.has_animation(nm):
			return nm
	return _clip("attack")

## 闪避动画：按实际闪避方向选 前/后/左/右
func _dodge_clip() -> String:
	if anim_player == null:
		return ""
	var local: Vector3 = global_transform.basis.inverse() * dodge_dir
	var nm := "Dodge_Forward"
	if absf(local.x) > absf(local.z):
		nm = "Dodge_Right" if local.x > 0.0 else "Dodge_Left"
	else:
		nm = "Dodge_Forward" if local.z < 0.0 else "Dodge_Backward"
	if anim_player.has_animation(nm):
		return nm
	return _clip("dodge")

# ---------------- 武器拖尾 ----------------
func _get_weapon_tip_pos() -> Vector3:
	# 武器尖端：weapon_pivot 本地 Y 轴正向
	var reach: float = float(current_weapon.get("reach", 2.4)) * 0.55
	return weapon_pivot.global_position + weapon_pivot.global_transform.basis.y * reach

func _update_trail(_delta: float) -> void:
	if not trail_mesh:
		return
	if not trail_active:
		if trail_points.size() > 0:
			# 快速淡出并清空
			trail_points.clear()
			trail_mesh.clear_surfaces()
		return
	# 记录尖端位置
	trail_points.append(_get_weapon_tip_pos())
	while trail_points.size() > C.TRAIL_MAX_POINTS:
		trail_points.pop_front()
	# 绘制带状拖尾
	trail_mesh.clear_surfaces()
	if trail_points.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cam_dir: Vector3 = (camera.global_position - global_position).normalized() if camera else Vector3.FORWARD
	for i in range(trail_points.size()):
		var p: Vector3 = trail_points[i]
		var alpha: float = float(i) / float(trail_points.size())
		var width: float = C.TRAIL_WIDTH * alpha
		# 计算垂直于轨迹与视线的偏移方向
		var tangent: Vector3
		if i > 0:
			tangent = (p - trail_points[i - 1]).normalized()
		else:
			tangent = (trail_points[i + 1] - p).normalized()
		var side: Vector3 = tangent.cross(cam_dir)
		if side.length() < 0.001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		trail_mesh.surface_set_color(Color(trail_color.r, trail_color.g, trail_color.b, alpha))
		trail_mesh.surface_add_vertex(p + side * width * 0.5)
		trail_mesh.surface_set_color(Color(trail_color.r, trail_color.g, trail_color.b, alpha))
		trail_mesh.surface_add_vertex(p - side * width * 0.5)
	trail_mesh.surface_end()

# ---------------- 命中反馈回调 ----------------
func _on_hit_landed(pos: Vector3, dmg: float, heavy: bool) -> void:
	var m := get_parent()
	if m and m.has_method("on_player_hit"):
		m.call("on_player_hit", pos, dmg, heavy, current_attack.get("arc", "slash"))

# ---------------- 相机 ----------------
func _update_camera(delta: float) -> void:
	if not camera_pivot or not camera:
		return

	# 位置平滑跟随（camera_pivot 为 top_level，需手动同步）
	var anchor := global_position + Vector3(0, 1.6, 0)
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		anchor, 1.0 - exp(-CAM_FOLLOW_K * delta))

	# 锁定时：yaw 自动转向"玩家背后看向敌人"的方位
	if lock_target and is_instance_valid(lock_target):
		var d := global_position - lock_target.global_position
		d.y = 0.0
		if d.length() > 0.05:
			yaw = atan2(d.x, d.z)
			pitch = lerp(pitch, 0.10, 1.0 - exp(-6.0 * delta))

	# 朝向平滑（最短角插值，避免翻转）
	var k := 1.0 - exp(-CAM_ROTATE_K * delta)
	cam_yaw = lerp_angle(cam_yaw, yaw, k)
	cam_pitch = lerp(cam_pitch, pitch, k)
	camera_pivot.rotation.y = cam_yaw
	camera_pivot.rotation.x = cam_pitch

	# 遮挡：从 pivot 向机位射线，命中则拉近
	var desired_global: Vector3 = camera_pivot.global_transform * CAM_OFFSET
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		camera_pivot.global_position, desired_global, 1)
	q.exclude.append(get_rid())
	var hit := space.intersect_ray(q)
	var factor := 1.0
	if hit:
		var full := camera_pivot.global_position.distance_to(desired_global)
		var hit_d := camera_pivot.global_position.distance_to(hit.position)
		factor = clampf((hit_d - 0.25) / maxf(full, 0.01), 0.3, 1.0)
	camera.position = CAM_OFFSET * factor + shake_offset
	shake_offset = shake_offset.lerp(Vector3.ZERO, 0.4)  # 震动衰减由主场景驱动，这里兜底归零

	# 不入地
	if camera.global_position.y < 0.45:
		var p := camera.global_position
		p.y = 0.45
		camera.global_position = p

func _update_marker() -> void:
	if not lock_marker:
		return
	if lock_target and is_instance_valid(lock_target) and lock_target.is_inside_tree():
		lock_marker.visible = true
		lock_marker.global_position = lock_target.global_position + Vector3(0, 2.3, 0)
	else:
		lock_marker.visible = false
		if lock_target and not is_instance_valid(lock_target):
			lock_target = null

# ---------------- 移动 ----------------
func _update_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	# 相机前方为 -Z：W(input.y=-1) 应得到 z=-1，故直接用 input.y
	var move_dir := (cam_basis * Vector3(input.x, 0, input.y)).normalized()

	var speed := get_move_speed() * (1.3 if buff_speed > 0.0 else 1.0) \
		* (C.TRANSFORM_SPEED_MULT if transformed else 1.0)
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = C.PLAYER_JUMP_VELOCITY

	if move_dir.length() > 0.1:
		look_at(global_position + move_dir, Vector3.UP)
		state = State.MOVE
	else:
		state = State.IDLE

# ---------------- 全局输入（连招缓冲 / 方向攻击 / 蓄力） ----------------
func _handle_global_input() -> void:
	# 蓄力中：持续累积，不处理其他攻击输入
	if heavy_charging:
		heavy_charge_time += get_physics_process_delta_time()
		var new_level := 0
		for i in range(C.CHARGE_LEVELS.size()):
			if heavy_charge_time >= C.CHARGE_LEVELS[i]:
				new_level = i + 1
		if new_level != heavy_charge_level:
			heavy_charge_level = new_level
			_update_charge_visual()
		if Input.is_action_just_released("heavy_attack"):
			_release_heavy_charge()
		elif Input.is_action_just_pressed("dodge"):
			_cancel_heavy_charge()
		return

	var moves := _light_moves()
	if Input.is_action_just_pressed("light_attack"):
		if state == State.ATTACK:
			combo_buffer = 0.4
		elif state in [State.IDLE, State.MOVE] and moves.size() > 0:
			heavy_flag = false
			var dir: String = _get_attack_direction()
			_start_attack(_scaled_move(_pick_light_move(dir, moves)), dir)
	elif Input.is_action_pressed("heavy_attack"):
		if state in [State.IDLE, State.MOVE]:
			_start_heavy_charge()
	elif Input.is_action_just_pressed("dodge") and stamina >= C.PLAYER_DODGE_COST:
		var dir := Vector3.ZERO
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var cam_basis := Basis(Vector3.UP, cam_yaw)
		dir = (cam_basis * Vector3(input.x, 0, input.y)).normalized()
		if dir.length() < 0.1:
			dir = -transform.basis.z
		_start_dodge(dir)
	elif Input.is_action_just_pressed("parry"):
		if state in [State.IDLE, State.MOVE, State.ATTACK]:
			_start_parry()

## 根据当前移动输入判断攻击方向
func _get_attack_direction() -> String:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length() < 0.3:
		return "neutral"
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	var move_dir := (cam_basis * Vector3(input.x, 0, input.y)).normalized()
	var forward := -transform.basis.z
	var angle := forward.signed_angle_to(move_dir, Vector3.UP)
	if absf(angle) < PI * 0.25:
		return "forward"
	elif absf(angle) > PI * 0.75:
		return "back"
	else:
		return "side"

## 根据方向选择轻击招式
func _pick_light_move(dir: String, moves: Array) -> Dictionary:
	if dir == "neutral":
		return moves[combo_idx]
	var alt: Dictionary = current_style.get(dir, {})
	if not alt.is_empty():
		return alt
	return moves[combo_idx]

## 开始蓄力
func _start_heavy_charge() -> void:
	var heavy: Dictionary = current_style.get("heavy", {})
	if stamina < float(heavy.get("stamina", 24.0)):
		return
	heavy_charging = true
	heavy_charge_time = 0.0
	heavy_charge_level = 0
	state = State.ATTACK
	attack_phase = "charging"
	current_attack = {}
	velocity.x = 0
	velocity.z = 0
	_update_charge_visual()
	sfx.play("swing")

## 更新蓄力视觉（武器发光强度）
func _update_charge_visual() -> void:
	if not weapon_emissive:
		return
	var intensity: float = 0.5 + heavy_charge_level * 1.2
	weapon_emissive.emission_energy_multiplier = intensity
	if heavy_charge_level >= C.CHARGE_MAX_LEVEL:
		weapon_emissive.emission = Color(1.0, 0.5, 0.15)
	elif heavy_charge_level >= 2:
		weapon_emissive.emission = Color(0.9, 0.55, 0.25)
	else:
		weapon_emissive.emission = Color(0.4, 0.5, 0.8)

## 取消蓄力
func _cancel_heavy_charge() -> void:
	heavy_charging = false
	heavy_charge_level = 0
	heavy_charge_time = 0.0
	if weapon_emissive:
		weapon_emissive.emission_energy_multiplier = 0.5
		weapon_emissive.emission = Color(0.15, 0.12, 0.08)
	state = State.IDLE
	attack_phase = ""

## 释放蓄力重击
func _release_heavy_charge() -> void:
	var level: int = heavy_charge_level
	heavy_charging = false
	var heavy: Dictionary = current_style.get("heavy", {})
	var charge_table: Array = current_style.get("charge", [])
	var atk := _scaled_move(heavy)
	if level > 0 and level <= charge_table.size():
		var ch: Dictionary = charge_table[level - 1]
		atk["dmg"] = float(atk["dmg"]) * float(ch.get("dmg_mult", 1.0))
		atk["reach"] = float(atk.get("reach", 2.6)) * float(ch.get("reach_mult", 1.0))
	atk["poise"] = float(atk["poise"]) * (1.0 + level * 0.3)
	heavy_charge_level = 0
	heavy_charge_time = 0.0
	if weapon_emissive:
		weapon_emissive.emission_energy_multiplier = 0.5
		weapon_emissive.emission = Color(0.15, 0.12, 0.08)
	heavy_flag = true
	_start_attack(atk, "neutral", true, level)

# ---------------- 攻击 ----------------
func _start_attack(atk: Dictionary, _dir: String = "neutral", heavy: bool = false, charge_level: int = 0) -> void:
	if stamina < float(atk.get("stamina", 8.0)):
		return
	heavy_flag = heavy
	var stamina_cost: float = float(atk.get("stamina", 8.0))
	stamina -= stamina_cost
	sfx.play("swing")
	stamina_changed.emit(stamina, get_max_stamina())
	stamina_timer = C.PLAYER_STAMINA_DELAY
	state = State.ATTACK
	current_attack = atk
	attack_phase = "startup"
	attack_timer = float(atk.get("startup", 0.1))

	# 蓄力等级影响 reach
	var reach_val: float = float(atk.get("reach", 2.6))
	_apply_reach(reach_val)

	# 前进步伐与身体转向
	current_attack_step = float(atk.get("step", 0.0))
	current_attack_step_done = 0.0
	current_attack_body_turn = float(atk.get("body_turn", 0.0))
	current_attack_body_turn_done = 0.0

	# 轨迹颜色
	trail_color = atk.get("trail_color", Color(0.7, 0.85, 1.0))

	# 多轴旋转：从 rot_from 挥到 rot_to
	var rot_from: Vector3 = atk.get("rot_from", Vector3(-1.2, 0, 0))
	var rot_to: Vector3 = atk.get("rot_to", Vector3(1.0, 0, 0))
	var startup_t: float = float(atk.get("startup", 0.1))
	var active_t: float = float(atk.get("active", 0.1))
	var recovery_t: float = float(atk.get("recovery", 0.2))

	# 蓄力 3 段时武器放大
	if charge_level >= 3 and weapon_mesh:
		weapon_mesh.scale = Vector3(1.5, 1.5, 1.5)

	if anim_tween:
		anim_tween.kill()
	anim_tween = create_tween()
	# 起手：回到 rot_from
	anim_tween.tween_property(weapon_pivot, "rotation", rot_from, startup_t)
	# 命中阶段：rot_from → rot_to，激活 hitbox
	anim_tween.tween_callback(func():
		trail_active = true
		hitbox.activate(float(atk["dmg"]), float(atk["poise"]), self, 6.0 + charge_level * 2.0, heavy)
	)
	anim_tween.tween_property(weapon_pivot, "rotation", rot_to, active_t)
	anim_tween.tween_callback(func():
		hitbox.deactivate()
		trail_active = false
	)
	# 收招：rot_to → 0
	anim_tween.tween_property(weapon_pivot, "rotation", Vector3.ZERO, recovery_t)
	anim_tween.tween_callback(func():
		if weapon_mesh:
			weapon_mesh.scale = Vector3.ONE
	)

func _update_attack(delta: float) -> void:
	if attack_phase == "charging":
		# 蓄力状态由输入处理，这里保持静止
		velocity.x = 0
		velocity.z = 0
		return
	combo_buffer -= delta
	attack_timer -= delta

	# active 阶段：前进步伐 + 身体转向
	if attack_phase == "active":
		var active_total: float = float(current_attack.get("active", 0.1))
		if active_total > 0.0:
			var prog: float = 1.0 - clampf(attack_timer / active_total, 0.0, 1.0)
			# 前进步伐（沿角色朝向 -Z）
			var target_step: float = current_attack_step * prog
			var step_diff: float = target_step - current_attack_step_done
			current_attack_step_done = target_step
			var fwd := -transform.basis.z
			velocity.x = fwd.x * step_diff / delta
			velocity.z = fwd.z * step_diff / delta
			# 身体转向（绕 Y 轴）
			body_pivot.rotation.y = current_attack_body_turn * prog

	if attack_timer > 0:
		return
	match attack_phase:
		"startup":
			attack_phase = "active"
			attack_timer = float(current_attack.get("active", 0.1))
		"active":
			attack_phase = "recovery"
			attack_timer = float(current_attack.get("recovery", 0.2))
		"recovery":
			body_pivot.rotation.y = 0.0
			var moves := _light_moves()
			if not heavy_flag and combo_buffer > 0.0 and moves.size() > 0:
				combo_idx = (combo_idx + 1) % moves.size()
				combo_buffer = 0.0
				var dir: String = _get_attack_direction()
				_start_attack(_scaled_move(_pick_light_move(dir, moves)), dir)
			else:
				combo_idx = 0
				combo_buffer = 0.0
				state = State.IDLE

var heavy_flag := false

# ---------------- 闪避 ----------------
func _start_dodge(dir: Vector3) -> void:
	state = State.DODGE
	dodge_dir = dir.normalized()
	dodge_timer = C.PLAYER_DODGE_DURATION
	stamina -= C.PLAYER_DODGE_COST
	sfx.play("dodge")
	stamina_changed.emit(stamina, get_max_stamina())
	stamina_timer = C.PLAYER_STAMINA_DELAY
	look_at(global_position + dodge_dir, Vector3.UP)

func _update_dodge(delta: float) -> void:
	dodge_timer -= delta
	velocity.x = dodge_dir.x * C.PLAYER_DODGE_SPEED
	velocity.z = dodge_dir.z * C.PLAYER_DODGE_SPEED
	if dodge_timer <= 0:
		state = State.IDLE

func is_invincible() -> bool:
	if blink_invuln > 0.0:
		return true
	return state == State.DODGE and (C.PLAYER_DODGE_DURATION - dodge_timer) < C.PLAYER_DODGE_IFRAME

# ---------------- 识破 ----------------
func _start_parry() -> void:
	state = State.PARRY
	parry_timer = C.PARRY_WINDOW
	sfx.play("parry")

func _update_parry(delta: float) -> void:
	parry_timer -= delta
	if parry_timer <= 0:
		state = State.IDLE

func is_parrying() -> bool:
	return state == State.PARRY

# ---------------- 受击 ----------------
func _update_hurt(delta: float) -> void:
	velocity.x *= 0.85
	velocity.z *= 0.85
	# 短暂硬直后回到 idle
	if get_meta("hurt_timer", 0.2) > 0:
		set_meta("hurt_timer", get_meta("hurt_timer", 0.2) - delta)
	else:
		state = State.IDLE

func take_hit(dmg: float, _poi: float, from_pos: Vector3, kback: float = 6.0) -> void:
	if state == State.DEAD:
		return
	if is_invincible():
		return
	if is_parrying():
		# 识破成功：反弹架势伤害给攻击者（此处简单处理）
		return
	# 防御减伤，至少造成 1 点；金刚散期间再减半
	var actual := maxf(1.0, dmg - get_defense())
	if buff_guard > 0.0:
		actual *= 0.5
	hp = maxf(hp - actual, 0.0)
	hp_changed.emit(hp, get_max_hp())
	sfx.play("hurt")
	var dir := (global_position - from_pos).normalized()
	velocity.x = dir.x * kback
	velocity.z = dir.z * kback
	state = State.HURT
	set_meta("hurt_timer", 0.25)
	# 重置攻击残留姿态
	body_pivot.rotation.y = 0.0
	if anim_tween:
		anim_tween.kill()
	weapon_pivot.rotation = Vector3.ZERO
	if hp <= 0:
		state = State.DEAD
		queue_free()  # 临时处理

# ---------------- 锁定 ----------------
func _update_lock(_delta: float) -> void:
	if Input.is_action_just_pressed("lock_on"):
		if lock_target:
			lock_target = null
		else:
			# 锁定最近的敌人
			var best: Node3D = null
			var best_dist := 12.0
			for e in get_tree().get_nodes_in_group("enemy"):
				var d := global_position.distance_to(e.global_position)
				if d < best_dist:
					best_dist = d
					best = e
			lock_target = best
	if lock_target and is_instance_valid(lock_target):
		var dir := (lock_target.global_position - global_position).normalized()
		look_at(global_position + dir, Vector3.UP)
