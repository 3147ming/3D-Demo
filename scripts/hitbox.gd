extends Area3D
class_name Hitbox
## 攻击判定盒：激活期间检测进入的 Hurtbox，造成一次伤害
## 命中时发出 hit_landed 信号供主场景触发 hit-stop / 屏幕震动 / 粒子

@export var damage := 10.0
@export var poise_damage := 10.0
@export var knockback := 6.0
@export var owner_node: Node = null
## 是否为重击（影响命中停顿与震动强度）
@export var is_heavy := false

signal hit_landed(pos: Vector3, dmg: float, heavy: bool)

var _hit: Dictionary = {}

func _ready() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)

func activate(dmg: float, poi: float, attacker: Node, kback: float = 6.0, heavy: bool = false) -> void:
	damage = dmg
	poise_damage = poi
	knockback = kback
	owner_node = attacker
	is_heavy = heavy
	_hit.clear()
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	for body in get_overlapping_bodies():
		_apply_hit(body)

func _on_body_entered(body: Node) -> void:
	_apply_hit(body)

func _apply_hit(body: Node) -> void:
	if owner_node and body == owner_node:
		return
	if _hit.has(body):
		return
	if body.is_in_group("hurtbox"):
		_hit[body] = true
		var hit_pos: Vector3 = body.global_position + Vector3(0, 1.0, 0)
		body.call("take_hit", damage, poise_damage, global_position, knockback, owner_node)
		hit_landed.emit(hit_pos, damage, is_heavy)
