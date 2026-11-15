extends Area3D
class_name Hitbox
## 攻击判定盒：激活期间检测进入的 Hurtbox（Area3D，group "hurtbox"），造成一次伤害

@export var damage := 10.0
@export var poise_damage := 10.0
@export var knockback := 6.0
@export var owner_node: Node = null   # 攻击发起者，避免打到自己

var _hit: Dictionary = {}   # 已命中目标，避免一次攻击多段判定

func _ready() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 1       # 检测第 1 层的角色身体
	body_entered.connect(_on_body_entered)

func activate(dmg: float, poi: float, owner: Node, kback: float = 6.0) -> void:
	damage = dmg
	poise_damage = poi
	knockback = kback
	owner_node = owner
	_hit.clear()
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _on_body_entered(body: Node) -> void:
	if owner_node and body == owner_node:
		return
	if _hit.has(body):
		return
	if body.is_in_group("hurtbox"):
		_hit[body] = true
		body.call("take_hit", damage, poise_damage, global_position, knockback)
