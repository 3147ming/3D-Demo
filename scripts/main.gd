extends Node3D
## 主场景：搭建地面/光照/环境，生成玩家与敌人，HUD

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const CombatFXScript = preload("res://scripts/combat_fx.gd")
const C = preload("res://scripts/combat.gd")

const UI_INK := Color(0.025, 0.030, 0.034, 0.92)
const UI_INK_SOFT := Color(0.045, 0.052, 0.055, 0.86)
const UI_GOLD := Color(0.86, 0.66, 0.30)
const UI_GOLD_DIM := Color(0.43, 0.34, 0.19)
const UI_TEXT := Color(0.91, 0.88, 0.78)
const UI_DIM := Color(0.57, 0.58, 0.54)
const UI_TEAL := Color(0.30, 0.65, 0.59)
const UI_RED := Color(0.65, 0.20, 0.16)

const ICON_DIR := "res://assets/icons/"
const SKILL_ICON := {
	"freeze": "spell_freeze",
	"blink": "spell_blink",
	"shield": "spell_shield",
	"transform": "transform",
}

@onready var sfx: Node = get_node("/root/Sfx")

## 死亡重生点（土地庙做好后改为最近休息的庙）
const RESPAWN_POS := Vector3(0, 0, 8)

var player: CharacterBody3D
var combat_fx: Node3D
var enemies: Array = []
var hud_enemy: Node = null
var active_attacker: Node = null
var respawn_timer := 0.0
var ui: CanvasLayer
# 死亡流程
var player_dead := false
var death_phase := ""
var death_clock := 0.0
var death_layer: CanvasLayer
var death_rect: ColorRect
var death_title: Label
var death_hint: Label
var money_label: Label
var buff_label: Label
var status_label: Label
var player_hp_bar: ProgressBar
var player_stamina_bar: ProgressBar
var player_chi_bar: ProgressBar
var player_hp_value: Label
var player_stamina_value: Label
var player_chi_value: Label
var target_panel: PanelContainer
var target_name_label: Label
var target_hp_bar: ProgressBar
var target_posture_bar: ProgressBar
var target_state_label: Label
var skill_slots: Dictionary = {}
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
	_build_combat_fx()
	_spawn_enemies()
	_build_hud()
	_build_ui()
	_build_death_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_world() -> void:
	# 环境光与雾（加强雾气营造氛围）
	var env := WorldEnvironment.new()
	world_env = env
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.065, 0.085)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.30, 0.28, 0.36)
	env.environment.ambient_light_energy = 1.2
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.18, 0.17, 0.22)
	env.environment.fog_density = 0.01
	env.environment.fog_height = 1.0
	env.environment.fog_height_density = 0.12
	# SSAO
	env.environment.ssao_enabled = true
	env.environment.ssao_radius = 1.2
	env.environment.ssao_intensity = 1.2
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
	env.environment.tonemap_exposure = 1.12
	env.environment.adjustment_brightness = 1.05
	env.environment.adjustment_contrast = 1.08
	env.environment.adjustment_saturation = 1.02
	env.environment.adjustment_enabled = true
	add_child(env)

	# 主光（侧逆光，拉出轮廓）
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 12)
	sun.light_energy = 2.05
	sun.light_color = Color(0.95, 0.88, 0.78)
	sun.shadow_enabled = true
	sun.shadow_blur = 0.8
	add_child(sun)

	# 补光（冷色填充）
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 6, 4)
	fill.light_energy = 0.5
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.omni_range = 30.0
	add_child(fill)

	# 轮廓光（正后方暖色，强化角色边缘）
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 145, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.95, 0.65, 0.35)
	rim.shadow_enabled = false
	add_child(rim)

	# 地面（青石板风格）
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(60, 60)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.27, 0.26, 0.30)
	# 程序化噪声：作为粗糙度变化；albedo 使用可平铺石板贴图
	var gnoise := FastNoiseLite.new()
	gnoise.frequency = 0.05
	gnoise.fractal_octaves = 3
	var gtex := NoiseTexture2D.new()
	gtex.width = 256
	gtex.height = 256
	gtex.seamless = true
	gtex.noise = gnoise
	var floor_path := "res://assets/textures/floor_stone.png"
	if ResourceLoader.exists(floor_path):
		gmat.albedo_texture = load(floor_path)
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
		var pillar_path := "res://assets/textures/pillar_stone.png"
		if ResourceLoader.exists(pillar_path):
			pm.albedo_texture = load(pillar_path)
		pm.uv1_scale = Vector3(1, 2, 1)
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
	player.connect("died", Callable(self, "_on_player_died"))

func _build_combat_fx() -> void:
	combat_fx = Node3D.new()
	combat_fx.set_script(CombatFXScript)
	add_child(combat_fx)
	combat_fx.setup(self, player)

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
	e.posture_broken_signal.connect(Callable(combat_fx, "on_posture_broken").bind(e))
	enemies.append(e)
	if hud_enemy == null:
		hud_enemy = e

func _on_enemy_died(_pos: Vector3, e: Node) -> void:
	enemies.erase(e)
	if hud_enemy == e:
		hud_enemy = null
	var drops := ["herb", "bloodsand", "bone", "ghostfire"]
	if is_instance_valid(player):
		player.add_item(drops[randi() % drops.size()], 1)
		player.money += 15
	sfx.play("coin")
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
	spark_mat.emission_enabled = true
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
	stone_mat.albedo_color = Color(0.21, 0.21, 0.24)
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
			e.ambient_light_energy = 0.95
		else:
			e.fog_density = 0.018
			e.fog_light_color = Color(0.12, 0.10, 0.14)
			e.ambient_light_energy = 1.25

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
	mat.emission_enabled = true
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

# ---------------- 死亡与复活 ----------------
func _build_death_overlay() -> void:
	death_layer = CanvasLayer.new()
	death_layer.layer = 100
	add_child(death_layer)
	death_rect = ColorRect.new()
	death_rect.color = Color(0.015, 0.017, 0.020, 1.0)
	death_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_rect.modulate.a = 0.0
	death_rect.visible = false
	death_layer.add_child(death_rect)

	death_title = Label.new()
	death_title.text = "死"
	death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_title.add_theme_font_size_override("font_size", 120)
	death_title.add_theme_color_override("font_color", Color(0.72, 0.18, 0.14))
	death_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_layer.add_child(death_title)

	death_hint = Label.new()
	death_hint.text = "回生 · 土地庙"
	death_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	death_hint.offset_top = -180.0
	death_hint.offset_bottom = -140.0
	death_hint.offset_left = -160.0
	death_hint.offset_right = 160.0
	death_hint.add_theme_font_size_override("font_size", 20)
	death_hint.add_theme_color_override("font_color", UI_GOLD_DIM)
	death_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_layer.add_child(death_hint)

func _on_player_died() -> void:
	if player_dead:
		return
	player_dead = true
	death_phase = "in"
	death_clock = 0.0
	death_rect.modulate.a = 0.0
	death_rect.visible = true
	death_title.modulate.a = 0.0
	death_hint.modulate.a = 0.0
	if ui and ui.has_method("close"):
		ui.close()
	# 死亡时清掉慢镜头/停顿，避免黑屏过渡被拖慢
	slowmo_timer = 0.0
	slowmo_scale = 1.0
	hit_stop_frames = 0
	Engine.time_scale = 1.0
	# 敌人停手，避免围着尸体继续劈
	for e in enemies:
		if is_instance_valid(e):
			e.set_physics_process(false)
	_trigger_shake(C.SHAKE_BREAK, 0.5)
	# 解锁鼠标，便于后续菜单操作
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _update_death(delta: float) -> void:
	death_clock += delta
	match death_phase:
		"in":
			var a: float = clampf(death_clock / 0.9, 0.0, 1.0)
			death_rect.modulate.a = a
			death_title.modulate.a = clampf((death_clock - 0.15) / 0.5, 0.0, 1.0)
			death_hint.modulate.a = clampf((death_clock - 0.55) / 0.5, 0.0, 1.0)
			if death_clock >= 1.4:
				death_phase = "hold"
				death_clock = 0.0
				_respawn_player()
		"hold":
			if death_clock >= 1.0:
				death_phase = "out"
				death_clock = 0.0
		"out":
			death_rect.modulate.a = 1.0 - clampf(death_clock / 0.7, 0.0, 1.0)
			death_title.modulate.a = death_rect.modulate.a
			death_hint.modulate.a = death_rect.modulate.a
			if death_clock >= 0.7:
				death_phase = ""
				death_rect.visible = false
				player_dead = false
				for e in enemies:
					if is_instance_valid(e):
						e.set_physics_process(true)
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _respawn_player() -> void:
	if not is_instance_valid(player):
		return
	player.revive(RESPAWN_POS)
	_reset_encounter()
	# 重置出来的敌人先冻结，等黑屏淡出后再放行
	for e in enemies:
		if is_instance_valid(e):
			e.set_physics_process(false)

## 世界重置：清空全部敌人后按初始编组重新生成
func _reset_encounter() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	hud_enemy = null
	active_attacker = null
	respawn_timer = 0.0
	_spawn_enemies()

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

	if money_label and is_instance_valid(player):
		money_label.text = "铜钱  %d" % player.money
	if buff_label and is_instance_valid(player):
		var parts: Array = []
		if player.buff_speed > 0.0:
			parts.append("清风 %.0fs" % player.buff_speed)
		if player.buff_guard > 0.0:
			parts.append("金刚 %.0fs" % player.buff_guard)
		var wid := String(player.current_weapon.get("id", ""))
		var lv: int = player.forge_level(wid)
		if lv > 0:
			parts.append("锻造 +%d" % lv)
		buff_label.text = "　".join(parts) if not parts.is_empty() else " "
	if status_label:
		status_label.text = "%s · %s　N 天气 / M 难度" % [
			"雨" if weather == "rain" else "雾",
			"困难" if difficulty == "hard" else "普通"]

	_update_target_hud()
	_update_skill_hud()

	# 死亡流程
	if death_phase != "":
		_update_death(_delta)

	# 敌人补充
	if not player_dead and respawn_timer > 0.0:
		respawn_timer -= _delta
		if respawn_timer <= 0.0 and enemies.size() < 3:
			var a := randf() * TAU
			_spawn_enemy(Vector3(cos(a) * 8.0, 0.0, sin(a) * 8.0 - 2.0))

func _hud_panel_style(active: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_INK_SOFT if active else UI_INK
	style.border_color = UI_GOLD if active else UI_GOLD_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style

func _hud_label(parent: Control, text: String, font_size: int = 13,
		color: Color = UI_TEXT, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _hud_bar(parent: Control, color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = 100.0
	bar.value = 100.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.09, 0.09, 0.95)
	back.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	# 左上：玩家状态。
	var player_panel := PanelContainer.new()
	player_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.offset_left = 20.0
	player_panel.offset_top = 20.0
	player_panel.offset_right = 312.0
	player_panel.offset_bottom = 142.0
	player_panel.add_theme_stylebox_override("panel", _hud_panel_style())
	root.add_child(player_panel)
	var player_rows := VBoxContainer.new()
	player_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_rows.add_theme_constant_override("separation", 4)
	player_panel.add_child(player_rows)
	_hud_label(player_rows, "行  者", 13, UI_GOLD)
	player_hp_bar = _hud_bar(player_rows, UI_RED, 22.0)
	player_hp_value = _hud_label(player_hp_bar, "", 12, UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	player_hp_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player_hp_value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var stamina_row := HBoxContainer.new()
	stamina_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_rows.add_child(stamina_row)
	var stamina_title := _hud_label(stamina_row, "体力", 11, UI_DIM)
	stamina_title.custom_minimum_size.x = 34.0
	player_stamina_bar = _hud_bar(stamina_row, Color(0.61, 0.66, 0.62), 7.0)
	player_stamina_value = _hud_label(stamina_row, "", 11, UI_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	player_stamina_value.custom_minimum_size.x = 66.0

	var chi_row := HBoxContainer.new()
	chi_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_rows.add_child(chi_row)
	var chi_title := _hud_label(chi_row, "内力", 11, UI_DIM)
	chi_title.custom_minimum_size.x = 34.0
	player_chi_bar = _hud_bar(chi_row, UI_TEAL, 7.0)
	player_chi_value = _hud_label(chi_row, "", 11, UI_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	player_chi_value.custom_minimum_size.x = 66.0

	# 顶部中央：当前目标与金色架势条。
	target_panel = PanelContainer.new()
	target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_panel.anchor_left = 0.5
	target_panel.anchor_right = 0.5
	target_panel.offset_left = -200.0
	target_panel.offset_top = 20.0
	target_panel.offset_right = 200.0
	target_panel.offset_bottom = 112.0
	target_panel.add_theme_stylebox_override("panel", _hud_panel_style())
	root.add_child(target_panel)
	var target_rows := VBoxContainer.new()
	target_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_rows.add_theme_constant_override("separation", 4)
	target_panel.add_child(target_rows)
	target_name_label = _hud_label(target_rows, "", 14, UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	target_hp_bar = _hud_bar(target_rows, UI_RED, 13.0)
	target_posture_bar = _hud_bar(target_rows, UI_GOLD, 7.0)
	target_state_label = _hud_label(target_rows, "", 11, UI_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	target_panel.visible = false

	# 右上：紧凑的次级信息。
	var info_panel := PanelContainer.new()
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.offset_left = -330.0
	info_panel.offset_top = 20.0
	info_panel.offset_right = -20.0
	info_panel.offset_bottom = 104.0
	info_panel.add_theme_stylebox_override("panel", _hud_panel_style())
	root.add_child(info_panel)
	var info_rows := VBoxContainer.new()
	info_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_rows.add_theme_constant_override("separation", 2)
	info_panel.add_child(info_rows)
	money_label = _hud_label(info_rows, "", 13, UI_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	status_label = _hud_label(info_rows, "", 11, UI_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	buff_label = _hud_label(info_rows, " ", 11, UI_TEAL, HORIZONTAL_ALIGNMENT_RIGHT)

	# 底部中央：技能键位、消耗、冷却与持续状态。
	var skill_bar := HBoxContainer.new()
	skill_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_bar.anchor_left = 0.5
	skill_bar.anchor_right = 0.5
	skill_bar.anchor_top = 1.0
	skill_bar.anchor_bottom = 1.0
	skill_bar.offset_left = -294.0
	skill_bar.offset_right = 294.0
	skill_bar.offset_top = -126.0
	skill_bar.offset_bottom = -20.0
	skill_bar.add_theme_constant_override("separation", 10)
	root.add_child(skill_bar)
	skill_slots["freeze"] = _build_skill_slot(skill_bar, "Z", "定身", 30)
	skill_slots["blink"] = _build_skill_slot(skill_bar, "X", "移形闪", 20)
	skill_slots["shield"] = _build_skill_slot(skill_bar, "V", "护身法", 40)
	skill_slots["transform"] = _build_skill_slot(skill_bar, "F", "变身", int(C.TRANSFORM_COST))

	var hint := _hud_label(root, "WASD 移动 · 空格 闪避 · 左/右键 攻击 · C 识破 · Q 锁定 · Tab 行囊",
		11, Color(0.70, 0.69, 0.61, 0.86), HORIZONTAL_ALIGNMENT_CENTER)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -360.0
	hint.offset_right = 360.0
	hint.offset_top = -154.0
	hint.offset_bottom = -132.0

	player.hp_changed.connect(_refresh_player_hp)
	player.stamina_changed.connect(_refresh_player_stamina)
	player.chi_changed.connect(_refresh_player_chi)
	_refresh_player_hp(player.hp, player.get_max_hp())
	_refresh_player_stamina(player.stamina, player.get_max_stamina())
	_refresh_player_chi(player.chi, C.PLAYER_MAX_CHI)
	_update_skill_hud()

func _build_skill_slot(parent: Control, key: String, title: String, cost: int) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(137.0, 106.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var normal_style := _hud_panel_style()
	panel.add_theme_stylebox_override("panel", normal_style)
	parent.add_child(panel)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 10.0
	rows.offset_top = 7.0
	rows.offset_right = -10.0
	rows.offset_bottom = -7.0
	rows.add_theme_constant_override("separation", 1)
	panel.add_child(rows)

	var icon_id: String = SKILL_ICON.get(key, "")
	if icon_id != "":
		var icon_path := ICON_DIR + icon_id + ".png"
		if ResourceLoader.exists(icon_path):
			var icon_tr := TextureRect.new()
			icon_tr.custom_minimum_size = Vector2(36, 36)
			icon_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_tr.texture = load(icon_path)
			rows.add_child(icon_tr)

	_hud_label(rows, key, 18, UI_GOLD)
	_hud_label(rows, title, 15, UI_TEXT)
	var cost_label := _hud_label(rows, "%d 内力" % cost, 11, UI_DIM)
	var state_label := _hud_label(rows, "就绪", 11, UI_TEAL)

	var mask := ColorRect.new()
	mask.color = Color(0.015, 0.020, 0.022, 0.80)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.anchor_right = 1.0
	mask.anchor_bottom = 1.0
	panel.add_child(mask)
	mask.visible = false
	var cd_label := _hud_label(panel, "", 22, UI_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {
		"panel": panel, "mask": mask, "cd": cd_label, "cost": cost_label,
		"state": state_label, "normal_style": normal_style,
		"active_style": _hud_panel_style(true), "active": false,
	}

func _refresh_player_hp(value: float, max_value: float) -> void:
	if not player_hp_bar:
		return
	player_hp_bar.max_value = maxf(max_value, 1.0)
	player_hp_bar.value = value
	player_hp_value.text = "HP  %d / %d" % [ceili(value), int(max_value)]

func _refresh_player_stamina(value: float, max_value: float) -> void:
	if not player_stamina_bar:
		return
	player_stamina_bar.max_value = maxf(max_value, 1.0)
	player_stamina_bar.value = value
	player_stamina_value.text = "%d / %d" % [ceili(value), int(max_value)]

func _refresh_player_chi(value: float, max_value: float) -> void:
	if not player_chi_bar:
		return
	player_chi_bar.max_value = maxf(max_value, 1.0)
	player_chi_bar.value = value
	player_chi_value.text = "%d / %d" % [ceili(value), int(max_value)]

func _update_target_hud() -> void:
	if not is_instance_valid(player) or not target_panel:
		return
	var locked: Node3D = player.lock_target
	if is_instance_valid(locked) and locked in enemies and locked.hp > 0.0:
		hud_enemy = locked
	elif hud_enemy == null or not is_instance_valid(hud_enemy) or hud_enemy.hp <= 0.0:
		_pick_hud_enemy()
	var valid: bool = is_instance_valid(hud_enemy) and hud_enemy.hp > 0.0
	target_panel.visible = valid
	if not valid:
		return
	target_hp_bar.max_value = hud_enemy.hp_max
	target_hp_bar.value = hud_enemy.hp
	target_posture_bar.max_value = hud_enemy.poise_max
	target_posture_bar.value = maxf(hud_enemy.poise, 0.0)
	target_name_label.text = "烬门护法　%d / %d" % [ceili(hud_enemy.hp), int(hud_enemy.hp_max)]
	var broken: bool = hud_enemy.poise <= 0.0
	target_state_label.text = "架 势 崩 坏" if broken else "架势  %d / %d" % [ceili(hud_enemy.poise), int(hud_enemy.poise_max)]
	target_state_label.add_theme_color_override("font_color", UI_GOLD if broken else UI_DIM)

func _pick_hud_enemy() -> void:
	var best: Node = null
	var best_d := 1e9
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0.0:
			var d: float = player.global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
	hud_enemy = best

func _update_skill_hud() -> void:
	if not is_instance_valid(player) or skill_slots.is_empty():
		return
	_update_skill_slot("freeze", C.SPELL_FREEZE)
	_update_skill_slot("blink", C.SPELL_BLINK)
	_update_skill_slot("shield", C.SPELL_SHIELD, player.buff_guard > 0.0,
		"护身 %.1fs" % player.buff_guard)
	_update_skill_slot("transform", {"cost": C.TRANSFORM_COST, "cd": 0.0},
		player.transformed, "化身 %.1fs" % player.transform_timer)

func _update_skill_slot(key: String, definition: Dictionary,
		active: bool = false, active_text: String = "") -> void:
	if not skill_slots.has(key):
		return
	var slot: Dictionary = skill_slots[key]
	var cooldown: float = float(player.spell_cd.get(key, 0.0)) if key != "transform" else 0.0
	var max_cooldown: float = float(definition.get("cd", 0.0))
	var cost: float = float(definition.get("cost", 0.0))
	var enough_chi: bool = player.chi + 0.001 >= cost
	var mask: ColorRect = slot["mask"]
	mask.visible = cooldown > 0.0
	if max_cooldown > 0.0:
		mask.anchor_top = 1.0 - clampf(cooldown / max_cooldown, 0.0, 1.0)
		mask.offset_top = 0.0
	var cd_label: Label = slot["cd"]
	cd_label.visible = cooldown > 0.0
	cd_label.text = "%.1f" % cooldown if cooldown < 10.0 else str(ceili(cooldown))
	var state_label: Label = slot["state"]
	var cost_label: Label = slot["cost"]
	cost_label.add_theme_color_override("font_color", UI_DIM if enough_chi else Color(0.64, 0.34, 0.27))
	if active:
		state_label.text = active_text
		state_label.add_theme_color_override("font_color", UI_GOLD)
	elif cooldown > 0.0:
		state_label.text = "调息"
		state_label.add_theme_color_override("font_color", UI_DIM)
	elif not enough_chi:
		state_label.text = "内力不足"
		state_label.add_theme_color_override("font_color", Color(0.64, 0.34, 0.27))
	else:
		state_label.text = "就绪"
		state_label.add_theme_color_override("font_color", UI_TEAL)
	if bool(slot["active"]) != active:
		slot["active"] = active
		var panel: Panel = slot["panel"]
		panel.add_theme_stylebox_override("panel", slot["active_style"] if active else slot["normal_style"])
