extends Node3D
## 技能表现层：所有节点在 setup 时预建，战斗中只复用与回收。

const C = preload("res://scripts/combat.gd")
const GOLD := Color(0.95, 0.70, 0.28, 0.88)
const PALE_GOLD := Color(1.0, 0.86, 0.48, 0.90)
const INK := Color(0.055, 0.085, 0.085, 0.72)
const INK_TEAL := Color(0.10, 0.28, 0.25, 0.70)
const EMBER := Color(1.0, 0.34, 0.10, 0.88)

var player: CharacterBody3D
var ink_pool: Array[GPUParticles3D] = []
var dust_pool: Array[GPUParticles3D] = []
var gold_pool: Array[GPUParticles3D] = []
var ring_pool: Array[Dictionary] = []
var streak_pool: Array[Dictionary] = []
var freeze_pool: Array[Dictionary] = []
var freeze_by_enemy: Dictionary = {}
var emit_cursor := 0
var ring_cursor := 0
var streak_cursor := 0

var shield_root: Node3D
var shield_ring_a: MeshInstance3D
var shield_ring_b: MeshInstance3D
var shield_particles: GPUParticles3D
var shield_materials: Array[StandardMaterial3D] = []
var shield_alpha := 0.0
var transform_root: Node3D
var transform_ring: MeshInstance3D
var transform_particles: GPUParticles3D

func setup(_main: Node, player_node: CharacterBody3D) -> void:
	player = player_node
	_build_particle_pools()
	_build_ring_pool()
	_build_streak_pool()
	_build_freeze_pool()
	_build_shield()
	_build_transform()
	player.vfx_requested.connect(_on_player_vfx)

func _material(color: Color, glow: float = 0.8) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = glow
	return material

func _make_emitter(color: Color, amount: int, lifetime: float, size: float,
		continuous: bool = false, parent: Node3D = null) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = not continuous
	particles.explosiveness = 1.0 if not continuous else 0.0
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.22
	process.direction = Vector3.UP
	process.spread = 110.0
	process.initial_velocity_min = 0.6 if continuous else 1.4
	process.initial_velocity_max = 1.3 if continuous else 4.2
	process.gravity = Vector3(0, 0.15, 0) if continuous else Vector3(0, -2.2, 0)
	process.damping_min = 0.8
	process.damping_max = 1.8
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = _material(color, 0.65)
	quad.material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particles.draw_pass_1 = quad
	if parent:
		parent.add_child(particles)
	else:
		add_child(particles)
	return particles

func _build_particle_pools() -> void:
	for i in 12:
		ink_pool.append(_make_emitter(INK_TEAL, 22, 0.72, 0.30))
	for i in 8:
		dust_pool.append(_make_emitter(INK, 14, 0.55, 0.26))
	for i in 10:
		gold_pool.append(_make_emitter(PALE_GOLD, 18, 0.48, 0.085))

func _ring_mesh(color: Color, parent: Node3D = null) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 8
	ring.mesh = mesh
	ring.material_override = _material(color)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent:
		parent.add_child(ring)
	else:
		add_child(ring)
	return ring

func _build_ring_pool() -> void:
	for i in 24:
		var ring := _ring_mesh(GOLD)
		ring.visible = false
		ring_pool.append({
			"node": ring, "material": ring.material_override,
			"life": 0.0, "duration": 1.0, "start": 0.2, "end": 1.0,
			"color": GOLD, "spin": 0.0,
		})

func _spawn_ring(pos: Vector3, color: Color, start_radius: float,
		end_radius: float, duration: float, spin: float = 0.0) -> void:
	if ring_pool.is_empty():
		return
	var item: Dictionary = ring_pool[ring_cursor % ring_pool.size()]
	ring_cursor = (ring_cursor + 1) % ring_pool.size()
	item["life"] = duration
	item["duration"] = duration
	item["start"] = start_radius
	item["end"] = end_radius
	item["color"] = color
	item["spin"] = spin
	var ring: MeshInstance3D = item["node"]
	ring.global_position = Vector3(pos.x, 0.055, pos.z)
	ring.rotation = Vector3.ZERO
	ring.scale = Vector3.ONE * start_radius
	ring.visible = true

func _build_streak_pool() -> void:
	for i in 24:
		var streak := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		streak.mesh = mesh
		streak.material_override = _material(GOLD, 1.1)
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		streak.visible = false
		add_child(streak)
		streak_pool.append({
			"node": streak, "material": streak.material_override,
			"life": 0.0, "duration": 0.2, "width": 0.04,
			"length": 1.0, "color": GOLD,
		})

func _spawn_streak(from: Vector3, to: Vector3, color: Color,
		width: float = 0.04, duration: float = 0.22) -> void:
	var distance := from.distance_to(to)
	if distance < 0.02 or streak_pool.is_empty():
		return
	var item: Dictionary = streak_pool[streak_cursor % streak_pool.size()]
	streak_cursor = (streak_cursor + 1) % streak_pool.size()
	item["life"] = duration
	item["duration"] = duration
	item["width"] = width
	item["length"] = distance
	item["color"] = color
	var streak: MeshInstance3D = item["node"]
	streak.global_position = (from + to) * 0.5
	var up := Vector3.RIGHT if absf((to - from).normalized().dot(Vector3.UP)) > 0.96 else Vector3.UP
	streak.look_at(to, up)
	streak.scale = Vector3(width, width, distance)
	streak.visible = true

func _build_freeze_pool() -> void:
	for i in 8:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var ring_a := _ring_mesh(GOLD, root)
		ring_a.scale = Vector3.ONE * 0.76
		ring_a.position.y = 0.055
		var ring_b := _ring_mesh(PALE_GOLD, root)
		ring_b.scale = Vector3.ONE * 0.54
		ring_b.position.y = 0.10
		var mist := _make_emitter(INK_TEAL, 10, 1.15, 0.28, true, root)
		mist.position.y = 0.15
		freeze_pool.append({
			"root": root, "a": ring_a, "b": ring_b, "mist": mist,
			"target": null, "id": 0,
		})

func _activate_freeze(enemy: Node) -> void:
	if not is_instance_valid(enemy) or enemy.hp <= 0.0 or enemy.freeze_timer <= 0.0:
		return
	var id := enemy.get_instance_id()
	if freeze_by_enemy.has(id):
		return
	for item in freeze_pool:
		if item["target"] != null:
			continue
		item["target"] = enemy
		item["id"] = id
		freeze_by_enemy[id] = item
		var root: Node3D = item["root"]
		root.global_position = enemy.global_position
		root.visible = true
		var mist: GPUParticles3D = item["mist"]
		mist.restart()
		mist.emitting = true
		return

func _release_freeze(item: Dictionary) -> void:
	freeze_by_enemy.erase(int(item["id"]))
	item["target"] = null
	item["id"] = 0
	var root: Node3D = item["root"]
	root.visible = false
	var mist: GPUParticles3D = item["mist"]
	mist.emitting = false

func _build_shield() -> void:
	shield_root = Node3D.new()
	shield_root.visible = false
	add_child(shield_root)
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	shell.mesh = sphere
	shell.scale = Vector3(0.76, 0.96, 0.76)
	shell.position.y = 0.96
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shell_material := _material(Color(0.95, 0.72, 0.32, 0.07), 0.5)
	shell.material_override = shell_material
	shield_root.add_child(shell)
	shield_materials.append(shell_material)
	shield_ring_a = _ring_mesh(GOLD, shield_root)
	shield_ring_a.scale = Vector3.ONE * 0.80
	shield_ring_a.position.y = 0.20
	shield_ring_b = _ring_mesh(PALE_GOLD, shield_root)
	shield_ring_b.scale = Vector3.ONE * 0.72
	shield_ring_b.position.y = 1.58
	shield_materials.append(shield_ring_a.material_override)
	shield_materials.append(shield_ring_b.material_override)
	shield_particles = _make_emitter(PALE_GOLD, 18, 1.7, 0.055, true, shield_root)
	var process := shield_particles.process_material as ParticleProcessMaterial
	process.emission_sphere_radius = 0.68
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.65

func _build_transform() -> void:
	transform_root = Node3D.new()
	transform_root.visible = false
	add_child(transform_root)
	transform_ring = _ring_mesh(EMBER, transform_root)
	transform_ring.scale = Vector3.ONE * 0.94
	transform_ring.position.y = 0.065
	transform_particles = _make_emitter(EMBER, 26, 1.35, 0.07, true, transform_root)
	var process := transform_particles.process_material as ParticleProcessMaterial
	process.emission_sphere_radius = 0.72
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0, 0.45, 0)

func _emit(pool: Array, pos: Vector3) -> void:
	if pool.is_empty():
		return
	var particles: GPUParticles3D = pool[emit_cursor % pool.size()]
	emit_cursor += 1
	particles.global_position = pos
	particles.emitting = false
	particles.restart()
	particles.emitting = true

func _on_player_vfx(kind: StringName, from: Vector3, to: Vector3) -> void:
	match kind:
		&"freeze":
			_emit(ink_pool, from + Vector3(0, 0.8, 0))
			_spawn_ring(from, INK_TEAL, 0.35, 2.5, 0.65, 1.8)
			for enemy in get_tree().get_nodes_in_group("enemy"):
				_activate_freeze(enemy)
		&"blink":
			_emit(ink_pool, from + Vector3(0, 0.8, 0))
			_emit(ink_pool, to + Vector3(0, 0.8, 0))
			var direction := (to - from).normalized()
			var side := direction.cross(Vector3.UP).normalized()
			for i in 6:
				var t := float(i + 1) / 7.0
				var offset := side * (float(i % 3 - 1) * 0.18) + Vector3(0, 0.65 + float(i % 2) * 0.38, 0)
				var a := from.lerp(to, maxf(0.0, t - 0.13)) + offset
				var b := from.lerp(to, minf(1.0, t + 0.13)) + offset
				_spawn_streak(a, b, GOLD if i % 2 == 0 else INK_TEAL, 0.035, 0.26)
		&"shield":
			_emit(gold_pool, from + Vector3(0, 1.0, 0))
			_spawn_ring(from, GOLD, 0.35, 1.65, 0.48, -2.0)
		&"transform_start":
			_emit(ink_pool, from + Vector3(0, 0.9, 0))
			_emit(gold_pool, from + Vector3(0, 1.0, 0))
			_spawn_ring(from, EMBER, 0.35, 2.8, 0.62, 2.8)
		&"transform_end":
			_emit(gold_pool, from + Vector3(0, 0.8, 0))
			_spawn_ring(from, EMBER, 0.4, C.TRANSFORM_END_RADIUS, 0.72, 3.5)
			_spawn_ring(from, GOLD, 0.25, C.TRANSFORM_END_RADIUS * 0.82, 0.58, -2.5)
		&"parry":
			_emit(gold_pool, from)
			_spawn_streak(from + Vector3(-0.65, -0.42, 0), from + Vector3(0.65, 0.42, 0), PALE_GOLD, 0.055, 0.18)
			_spawn_streak(from + Vector3(-0.65, 0.42, 0), from + Vector3(0.65, -0.42, 0), GOLD, 0.045, 0.20)
		&"dodge":
			_emit(dust_pool, Vector3(from.x, 0.10, from.z))

func on_posture_broken(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var pos: Vector3 = enemy.global_position
	_spawn_ring(pos, GOLD, 0.25, 1.85, 0.48, 4.0)
	_spawn_ring(pos, INK_TEAL, 0.35, 2.2, 0.62, -3.0)
	_emit(gold_pool, pos + Vector3(0, 1.0, 0))
	_emit(ink_pool, pos + Vector3(0, 0.6, 0))

func _process(delta: float) -> void:
	_update_rings(delta)
	_update_streaks(delta)
	_update_freeze(delta)
	_update_persistent(delta)

func _update_rings(delta: float) -> void:
	for item in ring_pool:
		if float(item["life"]) <= 0.0:
			continue
		item["life"] = maxf(0.0, float(item["life"]) - delta)
		var ring: MeshInstance3D = item["node"]
		if float(item["life"]) <= 0.0:
			ring.visible = false
			continue
		var progress := 1.0 - float(item["life"]) / float(item["duration"])
		var eased := 1.0 - pow(1.0 - progress, 2.0)
		var radius := lerpf(float(item["start"]), float(item["end"]), eased)
		ring.scale = Vector3(radius, 1.0, radius)
		ring.rotate_y(float(item["spin"]) * delta)
		var color: Color = item["color"]
		var fade := 1.0 - progress
		var material: StandardMaterial3D = item["material"]
		material.albedo_color = Color(color.r, color.g, color.b, color.a * fade)
		material.emission_energy_multiplier = 0.35 + fade * 0.65

func _update_streaks(delta: float) -> void:
	for item in streak_pool:
		if float(item["life"]) <= 0.0:
			continue
		item["life"] = maxf(0.0, float(item["life"]) - delta)
		var streak: MeshInstance3D = item["node"]
		if float(item["life"]) <= 0.0:
			streak.visible = false
			continue
		var fade := float(item["life"]) / float(item["duration"])
		var width := float(item["width"]) * fade
		streak.scale = Vector3(width, width, float(item["length"]))
		var color: Color = item["color"]
		var material: StandardMaterial3D = item["material"]
		material.albedo_color = Color(color.r, color.g, color.b, color.a * fade)

func _update_freeze(delta: float) -> void:
	for item in freeze_pool:
		var target = item["target"]
		if target == null:
			continue
		if not is_instance_valid(target) or target.hp <= 0.0 or target.freeze_timer <= 0.0:
			_release_freeze(item)
			continue
		var root: Node3D = item["root"]
		root.global_position = target.global_position
		var ring_a: MeshInstance3D = item["a"]
		var ring_b: MeshInstance3D = item["b"]
		ring_a.rotate_y(delta * 1.8)
		ring_b.rotate_y(-delta * 2.6)

func _update_persistent(delta: float) -> void:
	if not is_instance_valid(player):
		shield_root.visible = false
		transform_root.visible = false
		return
	var shield_on: bool = player.buff_guard > 0.0
	shield_alpha = move_toward(shield_alpha, 1.0 if shield_on else 0.0, delta * (5.0 if shield_on else 2.8))
	shield_root.visible = shield_alpha > 0.01
	shield_particles.emitting = shield_on
	if shield_root.visible:
		shield_root.global_position = player.global_position
		shield_ring_a.rotate_y(delta * 0.9)
		shield_ring_b.rotate_y(-delta * 1.25)
		for material in shield_materials:
			var color := material.albedo_color
			var base_alpha := 0.07 if material == shield_materials[0] else 0.88
			material.albedo_color = Color(color.r, color.g, color.b, base_alpha * shield_alpha)

	var transformed: bool = player.transformed
	transform_root.visible = transformed
	transform_particles.emitting = transformed
	if transformed:
		transform_root.global_position = player.global_position
		transform_ring.rotate_y(delta * 1.6)
