extends Node3D
## 主场景：搭建地面/光照/环境，生成玩家与敌人，HUD

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")

var player: CharacterBody3D
var enemy: CharacterBody3D
var ui: CanvasLayer
var money_label: Label
var buff_label: Label
var status_label: Label
var world_env: WorldEnvironment
var rain: GPUParticles3D
var weather := "mist"
var difficulty := "normal"

func _ready() -> void:
	_build_world()
	_build_rain()
	_spawn_player()
	_spawn_enemy()
	_build_hud()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_world() -> void:
	# 环境光与雾
	var env := WorldEnvironment.new()
	world_env = env
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
	player.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and player:
		player.save_game()

# ---------------- 天气 / 难度 ----------------
func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 700
	rain.lifetime = 1.1
	rain.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 26, 40))
	rain.position = Vector3(0, 11, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 1, 14)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -6, 0)
	rain.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.66, 0.76, 0.92, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	rain.draw_pass_1 = quad
	rain.emitting = false
	add_child(rain)

func cycle_weather() -> void:
	weather = "rain" if weather == "mist" else "mist"
	if rain:
		rain.emitting = (weather == "rain")
	if world_env and world_env.environment:
		var e := world_env.environment
		if weather == "rain":
			e.fog_density = 0.028
			e.fog_light_color = Color(0.10, 0.12, 0.16)
			e.ambient_light_energy = 0.8
		else:
			e.fog_density = 0.012
			e.fog_light_color = Color(0.15, 0.12, 0.10)
			e.ambient_light_energy = 1.0

func toggle_difficulty() -> void:
	difficulty = "hard" if difficulty == "normal" else "normal"
	var sp := 1.2 if difficulty == "hard" else 1.0
	var dm := 1.15 if difficulty == "hard" else 1.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.speed_mult = sp
			e.dmg_mult = dm

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
		var lv: int = player.forge_level(wid)
		if lv > 0:
			parts.append("锻造 +%d" % lv)
		buff_label.text = "　".join(parts)
	if status_label:
		status_label.text = "天气 %s · 难度 %s（N / M 切换）" % [
			"雨" if weather == "rain" else "雾",
			"困难" if difficulty == "hard" else "普通"]

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# 玩家血条 / 体力 / 内力
	var php := ColorRect.new()
	php.color = Color(0, 0, 0, 0.5)
	php.size = Vector2(240, 60)
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
	pst_bar.size = Vector2(236, 6)
	pst_bar.position = Vector2(2, 42)
	php.add_child(pst_bar)
	var pchi_bar := ColorRect.new()
	pchi_bar.color = Color(0.42, 0.62, 0.58)
	pchi_bar.size = Vector2(236, 6)
	pchi_bar.position = Vector2(2, 51)
	php.add_child(pchi_bar)
	player.hp_changed.connect(func(v, m):
		php_bar.size.x = 236.0 * (v / m)
		php_label.text = "HP %d / %d" % [int(v), int(m)])
	player.stamina_changed.connect(func(v, m):
		pst_bar.size.x = 236.0 * (v / m))
	player.chi_changed.connect(func(v, m):
		pchi_bar.size.x = 236.0 * (v / m))

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
	hint.text = "WASD 移动 · Ctrl 跳 · 空格 闪避 · 左键轻击 · 右键重击 · C 识破 · Q 锁定 · Z/X/V 法术 · F 变身 · Tab 行囊 · P 刀谱"
	hint.position = Vector2(20, 660)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))
	canvas.add_child(hint)

	# 铜钱 / 丹药状态
	money_label = Label.new()
	money_label.text = "铜钱 120"
	money_label.position = Vector2(20, 84)
	money_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.42))
	canvas.add_child(money_label)

	status_label = Label.new()
	status_label.position = Vector2(20, 106)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.72, 0.70, 0.62))
	canvas.add_child(status_label)

	buff_label = Label.new()
	buff_label.position = Vector2(20, 124)
	buff_label.add_theme_font_size_override("font_size", 12)
	buff_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.72))
	canvas.add_child(buff_label)
