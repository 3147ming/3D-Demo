extends Node3D
## 主场景：搭建地面/光照/环境，生成玩家与敌人，HUD

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const C = preload("res://scripts/combat.gd")

@onready var sfx: Node = get_node("/root/Sfx")

var player: CharacterBody3D
var enemies: Array = []
var hud_enemy: Node = null
var active_attacker: Node = null
var respawn_timer := 0.0
var ehp_bar: ColorRect
var epoise_bar: ColorRect
var ehp_label: Label
var ui: CanvasLayer
var money_label: Label
var buff_label: Label
var status_label: Label
var world_env: WorldEnvironment
var rain: GPUParticles3D
var weather := "mist"
var difficulty := "normal"

# 命中反馈
var hit_stop_frames := 0
var shake_intensity := 0.0
var shake_duration := 0.0
var shake_timer := 0.0
var slowmo_timer := 0.0
var slowmo_scale := 1.0
var cam_original_pos: Vector3 = Vector3.ZERO
var spark_scene: PackedScene = null
var dust_scene: PackedScene = null
# 命中粒子池（复用节点，避免每次命中新建/销毁造成卡顿）
var spark_pool: Array[GPUParticles3D] = []
var dust_pool: Array[GPUParticles3D] = []
var pool_idx := 0

func _ready() -> void:
	_build_world()
	_build_rain()
	_build_ambient_particles()
	_build_vfx_pool()
	_build_props()
	_spawn_player()
	_spawn_enemies()
	_build_hud()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_world() -> void:
	# 环境光与雾（加强雾气营造氛围）
	var env := WorldEnvironment.new()
	world_env = env
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.04, 0.045, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.16, 0.14, 0.20)
	env.environment.ambient_light_energy = 0.5
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.09, 0.08, 0.11)
	env.environment.fog_density = 0.018
	env.environment.fog_height = 1.0
	env.environment.fog_height_density = 0.5
	# SSAO
	env.environment.ssao_enabled = true
	env.environment.ssao_radius = 1.2
	env.environment.ssao_intensity = 1.5
	env.environment.ssao_power = 1.5
	# 辉光：只保留 1-4 级、阈值高于 1，避免整屏溢光
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.3
	env.environment.glow_bloom = 0.0
	env.environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.environment.glow_hdr_threshold = 1.25
	env.environment.glow_hdr_scale = 1.0
	for i in range(1, 8):
		env.environment.set("glow_levels/" + str(i), i <= 4)
	# 色彩分级（暗部偏冷青，亮部偏暖橙）
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.tonemap_exposure = 0.85
	env.environment.adjustment_brightness = 0.85
	env.environment.adjustment_contrast = 1.08
	env.environment.adjustment_saturation = 1.02
	env.environment.adjustment_enabled = true
	add_child(env)

	# 主光（侧逆光，拉出轮廓）
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 12)
	sun.light_energy = 1.25
	sun.light_color = Color(0.95, 0.88, 0.78)
	sun.shadow_enabled = true
	sun.shadow_blur = 0.8
	add_child(sun)

	# 补光（冷色填充）
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 6, 4)
	fill.light_energy = 0.28
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.omni_range = 30.0
	add_child(fill)

	# 轮廓光（正后方暖色，强化角色边缘）
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 145, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.95, 0.65, 0.35)
	rim.shadow_enabled = false
	add_child(rim)

	# 地面（青石板风格）
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(60, 60)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.18, 0.17, 0.20)
	# 程序化噪声：让地面有不规则的石质明暗与粗糙度变化
	var gnoise := FastNoiseLite.new()
	gnoise.frequency = 0.05
	gnoise.fractal_octaves = 3
	var gtex := NoiseTexture2D.new()
	gtex.width = 256
	gtex.height = 256
	gtex.seamless = true
	gtex.noise = gnoise
	gmat.albedo_texture = gtex
	gmat.uv1_scale = Vector3(10, 10, 1)
	gmat.roughness = 0.92
	gmat.roughness_texture = gtex
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

func _spawn_enemies() -> void:
	var spawns := [Vector3(0, 0, -4), Vector3(-3.6, 0, -6.6), Vector3(3.6, 0, -6.6)]
	for p in spawns:
		_spawn_enemy(p)

func _spawn_enemy(pos: Vector3) -> void:
	var e := CharacterBody3D.new()
	e.set_script(EnemyScript)
	e.position = pos
	add_child(e)
	e.speed_mult = 1.2 if difficulty == "hard" else 1.0
	e.dmg_mult = 1.15 if difficulty == "hard" else 1.0
	e.feint_chance = 0.40 if difficulty == "hard" else 0.25
	e.block_chance = 0.55 if difficulty == "hard" else 0.35
	e.died.connect(_on_enemy_died.bind(e))
	enemies.append(e)
	if hud_enemy == null:
		hud_enemy = e

func _on_enemy_died(_pos: Vector3, e: Node) -> void:
	enemies.erase(e)
	if hud_enemy == e:
		hud_enemy = null
	var drops := ["herb", "bloodsand", "bone", "ghostfire"]
	player.add_item(drops[randi() % drops.size()], 1)
	player.money += 15
	sfx.play("coin")
	player.save_game()
	respawn_timer = 7.0
	# 击杀慢镜头
	_trigger_slowmo(C.SLOWMO_KILL, C.SLOWMO_KILL_SCALE)
	# 击杀大震动
	_trigger_shake(C.SHAKE_BREAK, 0.4)

# 进攻令牌：同一时间只允许一名敌人出手，其余走位包围
func request_attack(e: Node) -> bool:
	if active_attacker == null or not is_instance_valid(active_attacker):
		active_attacker = e
		return true
	return active_attacker == e

func release_attack(e: Node) -> void:
	if active_attacker == e:
		active_attacker = null

# ---------------- 命中反馈 ----------------
## 玩家命中敌人时由 player 回调
func on_player_hit(pos: Vector3, dmg: float, heavy: bool, _arc: String) -> void:
	# 命中停顿
	var frames: int = C.HIT_STOP_HEAVY if heavy else C.HIT_STOP_LIGHT
	if dmg >= 30.0:
		frames = C.HIT_STOP_BREAK
	_trigger_hit_stop(frames)
	# 屏幕震动
	var shake: float = C.SHAKE_HEAVY if heavy else C.SHAKE_LIGHT
	if dmg >= 30.0:
		shake = C.SHAKE_BREAK
	_trigger_shake(shake, 0.25)
	# 粒子
	_spawn_hit_vfx(pos, heavy)

## 敌人命中玩家时由 enemy 回调
func on_enemy_hit(pos: Vector3, _dmg: float, _heavy: bool) -> void:
	_trigger_hit_stop(C.HIT_STOP_LIGHT)
	_trigger_shake(C.SHAKE_HEAVY, 0.3)

## 攻击被格挡：金属火花 + 轻震屏 + 弹刀音
func on_block(pos: Vector3) -> void:
	Sfx.play("parry")
	_spawn_sparks(pos, true)
	_spawn_sparks(pos, false)
	_trigger_shake(C.SHAKE_LIGHT, 0.18)
	_spawn_hit_vfx(pos, false)

func _trigger_hit_stop(frames: int) -> void:
	hit_stop_frames = maxi(hit_stop_frames, frames)
	if hit_stop_frames > 0:
		Engine.time_scale = 0.04

func _trigger_shake(intensity: float, duration: float) -> void:
	shake_intensity = maxf(shake_intensity, intensity)
	shake_duration = maxf(shake_duration, duration)
	shake_timer = shake_duration

func _trigger_slowmo(duration: float, time_scale_value: float) -> void:
	slowmo_timer = maxf(slowmo_timer, duration)
	slowmo_scale = time_scale_value
	# 若没有命中停顿在生效，立即进入慢镜头
	if hit_stop_frames <= 0:
		Engine.time_scale = time_scale_value

## 命中粒子：火花 + 地面尘环
func _spawn_hit_vfx(pos: Vector3, heavy: bool) -> void:
	_spawn_sparks(pos, heavy)
	_spawn_dust_ring(pos, heavy)

# ---- 命中粒子池（预创建，命中时只复用不新建）----
func _build_vfx_pool() -> void:
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.85, 0.4)
	spark_mat.emissive_enabled = true
	spark_mat.emission = Color(1.0, 0.7, 0.2)
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.06, 0.06)
	spark_quad.material = spark_mat

	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.albedo_color = Color(0.8, 0.75, 0.65, 0.45)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dust_quad := QuadMesh.new()
	dust_quad.size = Vector2(0.25, 0.25)
	dust_quad.material = dust_mat

	spark_pool.clear()
	dust_pool.clear()
	for i in 10:
		spark_pool.append(_make_vfx_emitter(spark_quad, 20, 0.4))
	for i in 8:
		dust_pool.append(_make_vfx_emitter(dust_quad, 14, 0.5))

func _make_vfx_emitter(quad: QuadMesh, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.emitting = false
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0, -12, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	p.process_material = pm
	add_child(p)
	return p

func _spawn_sparks(pos: Vector3, heavy: bool) -> void:
	if spark_pool.is_empty():
		return
	_emit_from_pool(spark_pool, pos)
	if heavy:
		_emit_from_pool(spark_pool, pos + Vector3(0, 0.15, 0))

func _spawn_dust_ring(pos: Vector3, heavy: bool) -> void:
	if dust_pool.is_empty():
		return
	var ground := Vector3(pos.x, 0.06, pos.z)
	_emit_from_pool(dust_pool, ground)
	if heavy:
		_emit_from_pool(dust_pool, ground)

func _emit_from_pool(pool: Array, pos: Vector3) -> void:
	var p: GPUParticles3D = pool[pool_idx % pool.size()]
	pool_idx = (pool_idx + 1) % pool.size()
	p.global_position = pos
	p.emitting = false
	p.restart()
	p.emitting = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and player:
		player.save_game()

# ---------------- 场景点缀 ----------------
## 环形分布的残碑石墩，打破大片空地的空旷感（带碰撞，绕行有空间感）
func _build_props() -> void:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.15, 0.15, 0.17)
	stone_mat.roughness = 0.9
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.35
		var r := 8.0 + float(i % 3) * 2.2
		var h := 0.8 + float(i % 2) * 0.7
		var body := StaticBody3D.new()
		body.position = Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		body.rotation.y = a + 0.4
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, h, 0.55)
		mi.mesh = bm
		mi.material_override = stone_mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bm.size
		cs.shape = shape
		body.add_child(cs)
		add_child(body)

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
			e.fog_density = 0.018
			e.fog_light_color = Color(0.12, 0.10, 0.14)
			e.ambient_light_energy = 1.1

## 环境浮尘/余烬粒子（跟随玩家飘动）
func _build_ambient_particles() -> void:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 4.0
	p.visibility_aabb = AABB(Vector3(-20, 0, -20), Vector3(40, 12, 40))
	p.process_material = ParticleProcessMaterial.new()
	var pm: ParticleProcessMaterial = p.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 5, 12)
	pm.direction = Vector3(0, 0.3, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, -0.1, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.82, 0.55, 0.2)
	mat.emissive_enabled = true
	mat.emission = Color(0.8, 0.6, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = true
	add_child(p)

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
	# ---- 命中反馈 ----
	# hit-stop 帧计数（注意：time_scale 低时 _process 仍按真实帧调用）
	if hit_stop_frames > 0:
		hit_stop_frames -= 1
		if hit_stop_frames <= 0:
			Engine.time_scale = slowmo_scale
	# 慢镜头倒计时
	if slowmo_timer > 0:
		slowmo_timer -= _delta
		if slowmo_timer <= 0:
			slowmo_scale = 1.0
			if hit_stop_frames <= 0:
				Engine.time_scale = 1.0
	# 屏幕震动
	if shake_timer > 0 and player and "shake_offset" in player:
		shake_timer -= _delta
		var t: float = clampf(shake_timer / maxf(shake_duration, 0.01), 0.0, 1.0)
		player.shake_offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * shake_intensity * t
		if shake_timer <= 0:
			shake_intensity = 0.0
			player.shake_offset = Vector3.ZERO

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

	# 敌人血条跟随当前目标
	if hud_enemy == null or not is_instance_valid(hud_enemy):
		_pick_hud_enemy()
	if hud_enemy and is_instance_valid(hud_enemy):
		var hp_max: float = hud_enemy.hp_max
		var poise_max: float = hud_enemy.poise_max
		if ehp_bar:
			ehp_bar.size.x = 296.0 * clampf(hud_enemy.hp / hp_max, 0.0, 1.0)
		if epoise_bar:
			epoise_bar.size.x = 296.0 * clampf(hud_enemy.poise / poise_max, 0.0, 1.0)

	# 敌人补充
	if respawn_timer > 0.0:
		respawn_timer -= _delta
		if respawn_timer <= 0.0 and enemies.size() < 3:
			var a := randf() * TAU
			_spawn_enemy(Vector3(cos(a) * 8.0, 0.0, sin(a) * 8.0 - 2.0))

func _pick_hud_enemy() -> void:
	var best: Node = null
	var best_d := 1e9
	for e in enemies:
		if is_instance_valid(e):
			var d: float = player.global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
	hud_enemy = best

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
	ehp_bar = ColorRect.new()
	ehp_bar.color = Color(0.72, 0.22, 0.20)
	ehp_bar.size = Vector2(296, 18)
	ehp_bar.position = Vector2(2, 2)
	ehp.add_child(ehp_bar)
	epoise_bar = ColorRect.new()
	epoise_bar.color = Color(0.85, 0.70, 0.30)
	epoise_bar.size = Vector2(296, 10)
	epoise_bar.position = Vector2(2, 24)
	ehp.add_child(epoise_bar)
	ehp_label = Label.new()
	ehp_label.text = "烬门护法"
	ehp_label.position = Vector2(6, 36)
	ehp_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	ehp.add_child(ehp_label)

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
