extends RefCounted
## 战斗常量与工具函数（不挂载到节点，作为静态工具使用）

# ---------- 玩家属性 ----------
const PLAYER_MAX_HP := 100.0
const PLAYER_MAX_STAMINA := 100.0
const PLAYER_SPEED := 5.0
const PLAYER_SPRINT_SPEED := 8.0
const PLAYER_DODGE_SPEED := 12.0
const PLAYER_DODGE_DURATION := 0.35
const PLAYER_DODGE_IFRAME := 0.22    # 闪避前 0.22s 无敌
const PLAYER_DODGE_COST := 20.0
const PLAYER_STAMINA_REGEN := 28.0   # 每秒
const PLAYER_STAMINA_DELAY := 0.6    # 消耗后延迟回复
const PLAYER_JUMP_VELOCITY := 6.0

# ---------- 内力与法术 ----------
const PLAYER_MAX_CHI := 100.0
const PLAYER_CHI_REGEN := 16.0
const PLAYER_CHI_DELAY := 1.0

const SPELL_FREEZE := {"name": "定身", "cost": 30.0, "cd": 12.0, "duration": 3.0}
const SPELL_BLINK := {"name": "移形闪", "cost": 20.0, "cd": 8.0, "distance": 5.5, "invuln": 0.35}
const SPELL_SHIELD := {"name": "护身法", "cost": 40.0, "cd": 18.0, "duration": 8.0}

const TRANSFORM_COST := 50.0
const TRANSFORM_DURATION := 12.0
const TRANSFORM_DAMAGE_MULT := 1.5
const TRANSFORM_SPEED_MULT := 1.2
const TRANSFORM_END_DAMAGE := 40.0
const TRANSFORM_END_RADIUS := 5.0

# 攻击段（轻击三连）
const LIGHT_COMBO = [
	{"dmg": 14, "poise": 10, "startup": 0.10, "active": 0.12, "recovery": 0.18, "stamina": 8, "reach": 2.4},
	{"dmg": 12, "poise": 10, "startup": 0.08, "active": 0.12, "recovery": 0.20, "stamina": 8, "reach": 2.4},
	{"dmg": 22, "poise": 24, "startup": 0.16, "active": 0.14, "recovery": 0.34, "stamina": 12, "reach": 2.6},
]
# 重击
const HEAVY = {"dmg": 40, "poise": 40, "startup": 0.40, "active": 0.16, "recovery": 0.50, "stamina": 28, "reach": 2.8}

# 识破（parry）
const PARRY_WINDOW := 0.30
const PARRY_COST := 0.0
const PARRY_COUNTER_POISE := 60.0

# ---------- 敌人属性 ----------
const ENEMY_MAX_HP := 120.0
const ENEMY_MAX_POISE := 80.0
const ENEMY_POISE_REGEN := 6.0
const ENEMY_SPEED := 2.8
const ENEMY_ATTACK_RANGE := 2.2
const ENEMY_ATTACK_DMG := 18.0
const ENEMY_ATTACK_POISE := 12.0
const ENEMY_BREAK_TIME := 1.6   # 架势崩坏硬直

# ---------- 全局工具 ----------
static func clampf(v: float, lo: float, hi: float) -> float:
	return clamp(v, lo, hi)

static func angle_to(from: Vector3, to: Vector3) -> float:
	return from.signed_angle_to(to, Vector3.UP)
