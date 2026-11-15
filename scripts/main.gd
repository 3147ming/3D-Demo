extends Node3D
## 主场景：搭建地面/光照/环境，生成玩家与敌人，HUD

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")

var player: CharacterBody3D
var enemy: CharacterBody3D
var ui: CanvasLayer
var money_label: Label
var buff_label: Label

func _ready() -> void:
	_build_world()
	_spawn_player()
	_spawn_enemy()
	_build_hud()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_world() -> void:
	# 环境光与雾
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.18, 0.16, 0.22)
	env.environment.ambient_light_energy = 1.0
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.15, 0.12, 0.10)
	env.environment.fog_density = 0.012
	add_child(env)

	# 主光
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)

	# 补光
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 6, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.6, 0.7, 1.0)
	add_child(fill)

	# 地面（青石板风格）
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(60, 60)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.18, 0.17, 0.20)
	gmat.roughness = 0.9
	ground.material_override = gmat
	ground.rotation.x = deg_to_rad(-90)
	add_child(ground)

	var gcol := CollisionShape3D.new()
	gcol.shape = BoxShape3D.new()
	gcol.shape.size = Vector3(60, 0.2, 60)
	gcol.position = Vector3(0, -0.1, 0)
	var gbody := StaticBody3D.new()
	gbody.add_child(gcol)
	add_child(gbody)

	# 几个装饰柱（带碰撞，供镜头遮挡检测）
	for i in range(6):
		var a := 6.28 * i / 6.0
		var pos := Vector3(cos(a) * 8, 2.0, sin(a) * 8)

		var p := MeshInstance3D.new()
		p.mesh = CylinderMesh.new()
		p.mesh.top_radius = 0.5
		p.mesh.bottom_radius = 0.6
		p.mesh.height = 4.0
		p.position = pos
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.30, 0.28, 0.26)
		p.material_override = pm
		add_child(p)

		var col := CollisionShape3D.new()
		col.shape = CylinderShape3D.new()
		col.shape.radius = 0.6
		col.shape.height = 4.0
		col.position = pos
		var body := StaticBody3D.new()
		body.add_child(col)
		add_child(body)

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.position = Vector3(0, 0, 4)
	add_child(player)

func _spawn_enemy() -> void:
	enemy = CharacterBody3D.new()
	enemy.set_script(EnemyScript)
	enemy.position = Vector3(0, 0, -4)
	add_child(enemy)
	enemy.died.connect(_on_enemy_died)

func _on_enemy_died(_pos: Vector3) -> void:
	var drops := ["herb", "bloodsand", "bone", "ghostfire"]
	player.add_item(drops[randi() % drops.size()], 1)
	player.money += 15

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.set_script(load("res://scripts/game_ui.gd"))
	add_child(ui)
	ui.setup(player)
	player.ui = ui

func _process(_delta: float) -> void:
	if money_label and player:
		money_label.text = "铜钱 %d" % player.money
	if buff_label and player:
		var parts: Array = []
		if player.buff_speed > 0.0:
			parts.append("清风 %.0fs" % player.buff_speed)
		if player.buff_guard > 0.0:
			parts.append("金刚 %.0fs" % player.buff_guard)
		var wid := String(player.current_weapon.get("id", ""))
		var lv := player.forge_level(wid)
		if lv > 0:
			parts.append("锻造 +%d" % lv)
		buff_label.text = "　".join(parts)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# 玩家血条
	var php := ColorRect.new()
	php.color = Color(0, 0, 0, 0.5)
	php.size = Vector2(240, 48)
	php.position = Vector2(20, 20)
	canvas.add_child(php)
	var php_bar := ColorRect.new()
	php_bar.color = Color(0.75, 0.55, 0.30)
	php_bar.size = Vector2(236, 18)
	php_bar.position = Vector2(2, 2)
	php.add_child(php_bar)
	var php_label := Label.new()
	php_label.text = "HP 100 / 100"
	php_label.position = Vector2(6, 22)
	php_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	php.add_child(php_label)
	var pst_bar := ColorRect.new()
	pst_bar.color = Color(0.55, 0.65, 0.70)
	pst_bar.size = Vector2(236, 8)
	pst_bar.position = Vector2(2, 38)
	php.add_child(pst_bar)
	player.hp_changed.connect(func(v, m):
		php_bar.size.x = 236.0 * (v / m)
		php_label.text = "HP %d / %d" % [int(v), int(m)])
	player.stamina_changed.connect(func(v, m):
		pst_bar.size.x = 236.0 * (v / m))

	# 敌人血条 + 架势
	var ehp := ColorRect.new()
	ehp.color = Color(0, 0, 0, 0.5)
	ehp.size = Vector2(300, 56)
	ehp.position = Vector2(490, 20)
	canvas.add_child(ehp)
	var ehp_bar := ColorRect.new()
	ehp_bar.color = Color(0.72, 0.22, 0.20)
	ehp_bar.size = Vector2(296, 18)
	ehp_bar.position = Vector2(2, 2)
	ehp.add_child(ehp_bar)
	var epoise_bar := ColorRect.new()
	epoise_bar.color = Color(0.85, 0.70, 0.30)
	epoise_bar.size = Vector2(296, 10)
	epoise_bar.position = Vector2(2, 24)
	ehp.add_child(epoise_bar)
	var ehp_label := Label.new()
	ehp_label.text = "烬门护法"
	ehp_label.position = Vector2(6, 36)
	ehp_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	ehp.add_child(ehp_label)
	enemy.hp_changed.connect(func(v, m): ehp_bar.size.x = 296.0 * (v / m))
	enemy.posture_changed.connect(func(v, m): epoise_bar.size.x = 296.0 * (v / m))

	# 操作提示
	var hint := Label.new()
	hint.text = "WASD 移动 · Ctrl 跳 · 空格 闪避 · 左键/J 轻击 · 右键/K 重击 · C 识破 · Q 锁定 · Tab 行囊 · G 药铺 · H 锻造 · R/T/Y/U 服丹"
	hint.position = Vector2(20, 660)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))
	canvas.add_child(hint)

	# 铜钱 / 丹药状态
	money_label = Label.new()
	money_label.text = "铜钱 120"
	money_label.position = Vector2(20, 74)
	money_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.42))
	canvas.add_child(money_label)

	buff_label = Label.new()
	buff_label.position = Vector2(20, 96)
	buff_label.add_theme_font_size_override("font_size", 12)
	buff_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.72))
	canvas.add_child(buff_label)
