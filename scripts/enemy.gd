extends CharacterBody3D
class_name Enemy
## 敌人：简单状态机 + 架势系统（架势归零进入崩坏硬直，可被处决）

signal hp_changed(value: float, maxv: float)
signal posture_changed(value: float, maxv: float)
signal posture_broken_signal
signal died(pos: Vector3)

const C = preload("res://scripts/combat.gd")

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

var body_mesh: MeshInstance3D
var hitbox: Hitbox

func _ready() -> void:
	_build_self()
	collision_layer = 1
	collision_mask = 1
	add_to_group("enemy")
	add_to_group("hurtbox")
	target = get_tree().get_first_node_in_group("player")
	orbit_dir = 1.0 if randf() < 0.5 else -1.0

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
	var arm := Node3D.new()
	arm.position = Vector3(0.4, 1.4, 0.3)
	add_child(arm)
	var blade := MeshInstance3D.new()
	blade.mesh = BoxMesh.new()
	blade.mesh.size = Vector3(0.1, 2.0, 0.3)
	blade.position = Vector3(0, 1.0, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.85, 0.88)
	bmat.roughness = 0.3
	blade.material_override = bmat
	arm.add_child(blade)

	hitbox = Hitbox.new()
	var hs := CollisionShape3D.new()
	hs.shape = BoxShape3D.new()
	hs.shape.size = Vector3(1.2, 1.6, 2.4)
	hitbox.add_child(hs)
	hitbox.position = Vector3(0, 1.2, -1.4)   # look_at 的 -Z 为前方
	arm.add_child(hitbox)
	hitbox.hit_landed.connect(_on_hit_landed)

func _on_hit_landed(pos: Vector3, dmg: float, heavy: bool) -> void:
	var m := get_parent()
	if m and m.has_method("on_enemy_hit"):
		m.call("on_enemy_hit", pos, dmg, heavy)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# 定身：完全停止行动
	if freeze_timer > 0.0:
		freeze_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		move_and_slide()
		return

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

func apply_freeze(seconds: float) -> void:
	freeze_timer = maxf(freeze_timer, seconds)

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
	state = State.ATTACK
	velocity.x = 0.0
	velocity.z = 0.0
	# 佯攻：虚晃一枪后撤，逼迫玩家提前闪避
	if randf() < feint_chance:
		attack_phase = "feint"
		attack_timer = 0.22
	else:
		attack_phase = "startup"
		attack_timer = 0.5

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
		"active":
			hitbox.deactivate()
			attack_phase = "recovery"
			attack_timer = 0.7
		"recovery":
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

func take_hit(dmg: float, poi: float, from_pos: Vector3, kback: float = 6.0) -> void:
	if state in [State.DEAD, State.BROKEN]:
		if state == State.BROKEN:
			# 处决伤害加倍
			dmg *= 2.0
	hp -= dmg
	hp_changed.emit(hp, C.ENEMY_MAX_HP)
	Sfx.play("hit")
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
		Sfx.play("death")
		died.emit(global_position)
		queue_free()
