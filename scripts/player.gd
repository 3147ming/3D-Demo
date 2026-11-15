extends CharacterBody3D
class_name Player
## 玩家：第三人称动作角色，含移动/跳跃/轻击三连/重击/闪避无敌帧/识破/锁定

signal hp_changed(value: float, maxv: float)
signal stamina_changed(value: float, maxv: float)

const C = preload("res://scripts/combat.gd")

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

# 相机
var camera_pivot: Node3D
var camera: Camera3D
var yaw := 0.0
var pitch := 0.2
var lock_target: Node3D = null

# 节点引用
var body_mesh: MeshInstance3D
var weapon_pivot: Node3D
var hitbox: Hitbox
var anim_tween: Tween

func _ready() -> void:
	_build_self()
	collision_layer = 1
	collision_mask = 1 | (1 << 2)
	add_to_group("player")
	add_to_group("hurtbox")

func _build_self() -> void:
	# 胶囊碰撞
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.shape.radius = 0.4
	col.shape.height = 1.8
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# 身体（占位：上半身圆柱 + 头球，风格化）
	body_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.4
	body.height = 1.4
	body_mesh.mesh = body
	body_mesh.position = Vector3(0, 1.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.62, 0.70)
	mat.roughness = 0.7
	body_mesh.material_override = mat
	add_child(body_mesh)

	var head := MeshInstance3D.new()
	head.mesh = SphereMesh.new()
	head.mesh.radius = 0.22
	head.mesh.height = 0.44
	head.position = Vector3(0, 1.95, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.82, 0.75, 0.66)
	head.material_override = hmat
	add_child(head)

	# 武器枢轴 + 棍
	weapon_pivot = Node3D.new()
	weapon_pivot.position = Vector3(0.4, 1.3, 0.3)
	add_child(weapon_pivot)
	var staff := MeshInstance3D.new()
	staff.mesh = CylinderMesh.new()
	staff.mesh.top_radius = 0.05
	staff.mesh.bottom_radius = 0.05
	staff.mesh.height = 2.2
	staff.position = Vector3(0, 1.1, 0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.62, 0.50, 0.30)
	smat.roughness = 0.5
	staff.material_override = smat
	weapon_pivot.add_child(staff)

	# 攻击判定盒
	hitbox = Hitbox.new()
	var hs := CollisionShape3D.new()
	hs.shape = BoxShape3D.new()
	hs.shape.size = Vector3(1.0, 1.2, 2.6)
	hitbox.add_child(hs)
	hitbox.position = Vector3(0, 1.2, 1.4)
	weapon_pivot.add_child(hitbox)

	# 相机
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.6, 0)
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0.6, -6.0)
	camera.fov = 65.0
	camera.current = true
	camera_pivot.add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clamp(pitch - event.relative.y * 0.003, -0.6, 1.0)
		camera_pivot.rotation.y = yaw
		camera_pivot.rotation.x = pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

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
		stamina = min(stamina + C.PLAYER_STAMINA_REGEN * delta, C.PLAYER_MAX_STAMINA)
		stamina_changed.emit(stamina, C.PLAYER_MAX_STAMINA)

	_update_lock(delta)
	move_and_slide()

# ---------------- 移动 ----------------
func _update_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam_basis := Basis(Vector3.UP, yaw)
	var move_dir := (cam_basis * Vector3(input.x, 0, -input.y)).normalized()

	var speed := C.PLAYER_SPEED
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = C.PLAYER_JUMP_VELOCITY

	if move_dir.length() > 0.1:
		look_at(global_position + move_dir, Vector3.UP)
		state = State.MOVE
	else:
		state = State.IDLE

# ---------------- 全局输入（连招缓冲） ----------------
func _handle_global_input() -> void:
	if Input.is_action_just_pressed("light_attack"):
		if state == State.ATTACK:
			combo_buffer = 0.4   # 400ms 内衔接
		elif state in [State.IDLE, State.MOVE]:
			heavy_flag = false
			_start_attack(C.LIGHT_COMBO[combo_idx])
	elif Input.is_action_just_pressed("heavy_attack"):
		if state in [State.IDLE, State.MOVE]:
			heavy_flag = true
			_start_attack(C.HEAVY, true)
	elif Input.is_action_just_pressed("dodge") and stamina >= C.PLAYER_DODGE_COST:
		var dir := Vector3.ZERO
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var cam_basis := Basis(Vector3.UP, yaw)
		dir = (cam_basis * Vector3(input.x, 0, -input.y)).normalized()
		if dir.length() < 0.1:
			dir = -transform.basis.z
		_start_dodge(dir)
	elif Input.is_action_just_pressed("parry"):
		if state in [State.IDLE, State.MOVE, State.ATTACK]:
			_start_parry()

# ---------------- 攻击 ----------------
func _start_attack(atk: Dictionary, heavy := false) -> void:
	if stamina < atk.stamina:
		return
	heavy_flag = heavy
	stamina -= atk.stamina
	stamina_changed.emit(stamina, C.PLAYER_MAX_STAMINA)
	stamina_timer = C.PLAYER_STAMINA_DELAY
	state = State.ATTACK
	current_attack = atk
	attack_phase = "startup"
	attack_timer = atk.startup
	velocity.x = 0; velocity.z = 0
	# 武器挥动动画
	if anim_tween: anim_tween.kill()
	anim_tween = create_tween()
	anim_tween.tween_property(weapon_pivot, "rotation:x", deg_to_rad(-80), atk.startup)
	anim_tween.tween_callback(func(): weapon_pivot.rotation.x = deg_to_rad(-80))
	anim_tween.tween_property(weapon_pivot, "rotation:x", deg_to_rad(70), atk.active)
	anim_tween.tween_callback(func(): hitbox.activate(atk.dmg, atk.poise, self, 6.0))
	anim_tween.tween_interval(atk.active)
	anim_tween.tween_callback(func(): hitbox.deactivate(); weapon_pivot.rotation.x = 0)
	anim_tween.tween_property(weapon_pivot, "rotation:x", 0, atk.recovery)

func _update_attack(delta: float) -> void:
	combo_buffer -= delta
	attack_timer -= delta
	if attack_timer > 0:
		return
	match attack_phase:
		"startup":
			attack_phase = "active"
			attack_timer = current_attack.active
		"active":
			attack_phase = "recovery"
			attack_timer = current_attack.recovery
		"recovery":
			# 连招衔接
			if not heavy_flag and combo_buffer > 0.0:
				combo_idx = (combo_idx + 1) % C.LIGHT_COMBO.size()
				combo_buffer = 0.0
				_start_attack(C.LIGHT_COMBO[combo_idx])
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
	stamina_changed.emit(stamina, C.PLAYER_MAX_STAMINA)
	stamina_timer = C.PLAYER_STAMINA_DELAY
	look_at(global_position + dodge_dir, Vector3.UP)

func _update_dodge(delta: float) -> void:
	dodge_timer -= delta
	velocity.x = dodge_dir.x * C.PLAYER_DODGE_SPEED
	velocity.z = dodge_dir.z * C.PLAYER_DODGE_SPEED
	if dodge_timer <= 0:
		state = State.IDLE

func is_invincible() -> bool:
	return state == State.DODGE and (C.PLAYER_DODGE_DURATION - dodge_timer) < C.PLAYER_DODGE_IFRAME

# ---------------- 识破 ----------------
func _start_parry() -> void:
	state = State.PARRY
	parry_timer = C.PARRY_WINDOW

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
	hp -= dmg
	hp_changed.emit(hp, C.PLAYER_MAX_HP)
	var dir := (global_position - from_pos).normalized()
	velocity.x = dir.x * kback
	velocity.z = dir.z * kback
	state = State.HURT
	set_meta("hurt_timer", 0.25)
	if hp <= 0:
		hp = 0
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
