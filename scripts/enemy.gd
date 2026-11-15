extends CharacterBody3D
class_name Enemy
## 敌人：简单状态机 + 架势系统（架势归零进入崩坏硬直，可被处决）

signal hp_changed(value: float, maxv: float)
signal posture_changed(value: float, maxv: float)
signal posture_broken_signal
signal died(pos: Vector3)

const C = preload("res://scripts/combat.gd")
const GlbLoader = preload("res://scripts/glb_loader.gd")

@onready var sfx: Node = get_node("/root/Sfx")

# ---- 模型接入：把文件放到 assets/models/ 下即可自动生效 ----
const VISUAL_PATH := "res://assets/models/enemy.glb"
const VISUAL_HEIGHT := 2.0
const VISUAL_YAW := PI       # Kenney 模型朝 +Z，Godot look_at 朝 -Z，需转 180°
const ANIM_HINTS := {
	"idle": ["idle", "stand", "breath"],
	"run": ["run", "walk", "jog", "move"],
	"attack": ["attack", "slash", "swing", "combo", "punch"],
	"hurt": ["hurt", "hit", "damage", "impact"],
	"block": ["blocking", "block", "guard", "parry"],
	"death": ["death", "die", "dead"],
}
const LOOP_WORDS := ["idle", "walk", "run", "blocking", "spellcasting", "aiming"]
# 敌人攻击动画（随机挑一个，避免每个敌人动作雷同）
const ATTACK_CLIPS := [
	"1H_Melee_Attack_Chop",
	"1H_Melee_Attack_Slice_Diagonal",
	"1H_Melee_Attack_Slice_Horizontal",
]

enum State { IDLE, CHASE, ATTACK, HURT, BROKEN, DEAD }
var state := State.IDLE

var hp: float = C.ENEMY_MAX_HP
var hp_max: float = C.ENEMY_MAX_HP
var poise: float = C.ENEMY_MAX_POISE
var poise_max: float = C.ENEMY_MAX_POISE
var attack_timer := 0.0
var attack_phase := ""   # startup / active / recovery
var hurt_timer := 0.0
var freeze_timer := 0.0
var speed_mult := 1.0
var dmg_mult := 1.0
var feint_chance := 0.25
var orbit_dir := 1.0
var attack_cooldown := 0.0
var broken_timer := 0.0
var target: Node3D = null
# 格挡
var blocking := false
var block_timer := 0.0
var block_cooldown := 0.0
var block_chance := 0.35
var last_seen_attack_count := 0
# 连招
var combo_left := 0
# 动画锁定：播放 Block_Hit 等一次性动画时，暂时不让 _sync_anim 覆盖
var anim_lock := 0.0

var body_mesh: MeshInstance3D
var weapon_arm: Node3D
var hitbox: Hitbox

# GLB 视觉（存在模型文件时启用）
var visual_root: Node3D = null
var anim_player: AnimationPlayer = null
var anim_map: Dictionary = {}
var current_anim := ""
var attack_clip := ""

func _ready() -> void:
	_build_self()
	collision_layer = 1
	collision_mask = 1
	add_to_group("enemy")
	add_to_group("hurtbox")
	target = get_tree().get_first_node_in_group("player")
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_setup_visual()

## 尝试加载 GLB；失败则保持程序化占位模型
func _setup_visual() -> void:
	var r := GlbLoader.attach_model(self, VISUAL_PATH, VISUAL_HEIGHT, "[敌人模型]")
	if r.is_empty():
		return
	visual_root = r["root"]
	visual_root.rotation.y = VISUAL_YAW
	anim_player = r["anim"]
	if anim_player != null:
		anim_map = GlbLoader.auto_map(r["clips"], ANIM_HINTS)
		GlbLoader.configure_loops(anim_player, LOOP_WORDS)
	if body_mesh != null:
		body_mesh.visible = false
	if weapon_arm != null:
		weapon_arm.visible = false

func _build_self() -> void:
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.shape.radius = 0.5
	col.shape.height = 2.0
	col.position = Vector3(0, 1.0, 0)
	add_child(col)

	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = CapsuleMesh.new()
	body_mesh.mesh.radius = 0.5
	body_mesh.mesh.height = 1.6
	body_mesh.position = Vector3(0, 1.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.70, 0.25, 0.22)
	mat.roughness = 0.6
	body_mesh.material_override = mat
	add_child(body_mesh)

	# 武器（大刀）
	weapon_arm = Node3D.new()
	weapon_arm.position = Vector3(0.4, 1.4, 0.3)
	add_child(weapon_arm)
	var blade := MeshInstance3D.new()
	blade.mesh = BoxMesh.new()
	blade.mesh.size = Vector3(0.1, 2.0, 0.3)
	blade.position = Vector3(0, 1.0, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.85, 0.88)
	bmat.roughness = 0.3
	blade.material_override = bmat
	weapon_arm.add_child(blade)

	hitbox = Hitbox.new()
	var hs := CollisionShape3D.new()
	hs.shape = BoxShape3D.new()
	hs.shape.size = Vector3(1.2, 1.6, 2.4)
	hitbox.add_child(hs)
	hitbox.position = Vector3(0, 1.2, -1.4)   # look_at 的 -Z 为前方
	weapon_arm.add_child(hitbox)
	hitbox.hit_landed.connect(_on_hit_landed)

func _on_hit_landed(pos: Vector3, dmg: float, heavy: bool) -> void:
	var m := get_parent()
	if m and m.has_method("on_enemy_hit"):
		m.call("on_enemy_hit", pos, dmg, heavy)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_sync_anim()
		return

	# 定身：完全停止行动
	if freeze_timer > 0.0:
		freeze_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		move_and_slide()
		_sync_anim()
		return

	# 格挡计时
	if anim_lock > 0.0:
		anim_lock = maxf(0.0, anim_lock - delta)
	if block_cooldown > 0.0:
		block_cooldown = maxf(0.0, block_cooldown - delta)
	if blocking:
		block_timer -= delta
		if block_timer <= 0.0:
			_end_block()

	# 架势回复
	if state != State.BROKEN and state != State.HURT:
		poise = min(poise + C.ENEMY_POISE_REGEN * delta, C.ENEMY_MAX_POISE)
		posture_changed.emit(poise, C.ENEMY_MAX_POISE)

	match state:
		State.IDLE:
			_update_idle(delta)
		State.CHASE:
			_update_chase(delta)
		State.ATTACK:
			_update_attack(delta)
		State.HURT:
			_update_hurt(delta)
		State.BROKEN:
			_update_broken(delta)

	if not is_on_floor():
		velocity.y -= 18.0 * delta
	move_and_slide()
	_sync_anim()

func apply_freeze(seconds: float) -> void:
	freeze_timer = maxf(freeze_timer, seconds)

# ---------------- GLB 动画驱动 ----------------
func _sync_anim() -> void:
	if anim_player == null:
		return
	if anim_lock > 0.0:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	var want := ""
	match state:
		State.IDLE:
			want = _clip("idle")
		State.CHASE:
			if blocking:
				want = _clip("block")
			else:
				want = _clip("run") if moving else _clip("idle")
		State.ATTACK:
			want = _attack_clip()
		State.HURT, State.BROKEN:
			want = _clip("hurt")
		State.DEAD:
			want = _clip("death")
	if want == "" or want == current_anim:
		return
	current_anim = want
	anim_player.play(want, 0.12, 1.0)

func _clip(key: String) -> String:
	var v: String = String(anim_map.get(key, ""))
	if v == "":
		v = String(anim_map.get("idle", ""))
	return v

## 攻击动画：优先用 _start_attack 随机选中的那个
func _attack_clip() -> String:
	if anim_player != null and attack_clip != "" and anim_player.has_animation(attack_clip):
		return attack_clip
	return _clip("attack")

func _update_idle(_delta: float) -> void:
	if target and is_instance_valid(target):
		var d := global_position.distance_to(target.global_position)
		if d < 14.0:
			state = State.CHASE

func _update_chase(delta: float) -> void:
	if not target or not is_instance_valid(target):
		state = State.IDLE
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)

	var dir := (target.global_position - global_position)
	dir.y = 0
	var dist := dir.length()
	var dir_n := dir.normalized()
	look_at(global_position + dir_n, Vector3.UP)

	# 玩家起手攻击的瞬间，有概率举刀格挡
	var atk_count := _read_target_attack_count()
	if atk_count != last_seen_attack_count:
		last_seen_attack_count = atk_count
		if dist < 3.6 and block_cooldown <= 0.0 and randf() < block_chance:
			_start_block()

	if blocking:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var allowed := _request_token()

	if dist > C.ENEMY_ATTACK_RANGE or not allowed:
		var mv: Vector3
		if dist > C.ENEMY_ATTACK_RANGE * 1.8 or allowed:
			# 直接逼近
			mv = dir_n * C.ENEMY_SPEED * speed_mult
		else:
			# 无进攻令牌：围绕玩家侧移，保持包围
			var side := Vector3(-dir_n.z, 0.0, dir_n.x) * orbit_dir
			var err := clampf(dist - C.ENEMY_ATTACK_RANGE * 1.5, -1.5, 1.5)
			mv = (side + dir_n * err) * C.ENEMY_SPEED * 0.7 * speed_mult
		velocity.x = mv.x
		velocity.z = mv.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if attack_cooldown <= 0.0:
			_start_attack()

func _request_token() -> bool:
	var m := get_parent()
	if m and m.has_method("request_attack"):
		return bool(m.request_attack(self))
	return true

func _release_token() -> void:
	var m := get_parent()
	if m and m.has_method("release_attack"):
		m.release_attack(self)

func _start_attack() -> void:
	if blocking:
		_end_block()
	state = State.ATTACK
	velocity.x = 0.0
	velocity.z = 0.0
	# 随机挑一种挥砍，避免所有敌人动作雷同
	attack_clip = ""
	if ATTACK_CLIPS.size() > 0:
		attack_clip = ATTACK_CLIPS[randi() % ATTACK_CLIPS.size()]
	# 连招：1 段保底，概率追加到 2-3 段
	combo_left = 1
	if randf() < 0.55:
		combo_left += 1
	if randf() < feint_chance:
		combo_left += 1
	# 佯攻：虚晃一枪后撤，逼迫玩家提前闪避
	if randf() < feint_chance:
		attack_phase = "feint"
		attack_timer = 0.22
	else:
		attack_phase = "startup"
		attack_timer = 0.5

# ---------------- 格挡 ----------------
func _start_block() -> void:
	blocking = true
	block_timer = 0.55
	if weapon_arm:
		weapon_arm.rotation = Vector3(-0.9, 0.0, 0.35)

func _end_block() -> void:
	blocking = false
	block_timer = 0.0
	if weapon_arm:
		weapon_arm.rotation = Vector3.ZERO

func _read_target_attack_count() -> int:
	if not target or not is_instance_valid(target):
		return 0
	var v: Variant = target.get("attack_count")
	return int(v) if v != null else 0

## 成功格挡：不扣血，但削架势，并把玩家武器弹开
func _on_blocked(poi: float, attacker: Node) -> void:
	blocking = false
	block_timer = 0.0
	block_cooldown = 1.4
	if weapon_arm:
		weapon_arm.rotation = Vector3.ZERO
	# 格挡受击动画（Block_Hit），短暂锁定避免被移动动画覆盖
	if anim_player != null and anim_player.has_animation("Block_Hit"):
		current_anim = "Block_Hit"
		anim_player.play("Block_Hit", 0.05, 1.0)
		anim_lock = 0.32
	sfx.play("parry")
	poise -= poi * 0.45
	posture_changed.emit(poise, C.ENEMY_MAX_POISE)
	if poise <= 0.0:
		poise = 0.0
		state = State.BROKEN
		broken_timer = C.ENEMY_BREAK_TIME
		posture_broken_signal.emit()
		_release_token()
	var m := get_parent()
	if m and m.has_method("on_block"):
		m.call("on_block", global_position - transform.basis.z * 0.9 + Vector3(0, 1.3, 0))
	if attacker and is_instance_valid(attacker) and attacker.has_method("_on_attack_blocked"):
		attacker.call("_on_attack_blocked")

func _update_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0:
		return
	match attack_phase:
		"feint":
			# 后撤半步
			if target and is_instance_valid(target):
				var away := global_position - target.global_position
				away.y = 0.0
				away = away.normalized()
				velocity.x = away.x * C.ENEMY_SPEED * 1.6
				velocity.z = away.z * C.ENEMY_SPEED * 1.6
			attack_cooldown = 1.0
			_release_token()
			state = State.CHASE
		"startup":
			attack_phase = "active"
			attack_timer = 0.15
			hitbox.activate(C.ENEMY_ATTACK_DMG * dmg_mult, C.ENEMY_ATTACK_POISE, self, 8.0)
			# 前压半步，增加压迫感
			if target and is_instance_valid(target):
				var fwd := target.global_position - global_position
				fwd.y = 0.0
				fwd = fwd.normalized()
				velocity.x = fwd.x * 3.5
				velocity.z = fwd.z * 3.5
		"active":
			hitbox.deactivate()
			attack_phase = "recovery"
			attack_timer = 0.7
		"recovery":
			if combo_left > 1:
				# 连招接续：缩短起手再劈一刀
				combo_left -= 1
				if ATTACK_CLIPS.size() > 0:
					attack_clip = ATTACK_CLIPS[randi() % ATTACK_CLIPS.size()]
				attack_phase = "startup"
				attack_timer = 0.3
			else:
				attack_cooldown = 0.9
				_release_token()
				state = State.CHASE

func _update_hurt(delta: float) -> void:
	hurt_timer -= delta
	velocity.x *= 0.85
	velocity.z *= 0.85
	if hurt_timer <= 0:
		state = State.CHASE

func _update_broken(delta: float) -> void:
	broken_timer -= delta
	velocity.x *= 0.9
	velocity.z *= 0.9
	if broken_timer <= 0:
		poise = C.ENEMY_MAX_POISE * 0.5
		posture_changed.emit(poise, C.ENEMY_MAX_POISE)
		state = State.CHASE

func take_hit(dmg: float, poi: float, from_pos: Vector3, kback: float = 6.0, attacker: Node = null) -> void:
	if state == State.DEAD:
		return
	if blocking:
		_on_blocked(poi, attacker)
		return
	if state in [State.DEAD, State.BROKEN]:
		if state == State.BROKEN:
			# 处决伤害加倍
			dmg *= 2.0
	hp -= dmg
	hp_changed.emit(hp, C.ENEMY_MAX_HP)
	sfx.play("hit")
	var dir := (global_position - from_pos).normalized()
	velocity.x = dir.x * kback
	velocity.z = dir.z * kback
	if state != State.BROKEN:
		_release_token()
		poise -= poi
		posture_changed.emit(poise, C.ENEMY_MAX_POISE)
		if poise <= 0:
			state = State.BROKEN
			broken_timer = C.ENEMY_BREAK_TIME
			posture_broken_signal.emit()
		else:
			state = State.HURT
			hurt_timer = 0.25
	if hp <= 0:
		hp = 0
		state = State.DEAD
		_release_token()
		hitbox.deactivate()
		anim_lock = 0.0
		current_anim = ""
		sfx.play("death")
		died.emit(global_position)
		# 留一段时间播放死亡动画再移除（原来立即 queue_free，根本看不到死亡动作）
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_callback(queue_free)
