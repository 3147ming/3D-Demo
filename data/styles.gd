class_name StyleDB
## 武学（招式集）数据表
## 段字段：
##   dmg / poise / startup / active / recovery / stamina / reach
##   rot_from: Vector3(弧度)  武器起始旋转
##   rot_to:   Vector3(弧度)  武器结束旋转
##   body_turn: float(弧度)   命中阶段身体转向幅度
##   step: float              命中阶段前进步伐
##   trail_color: Color       斩击轨迹颜色
##   arc: String              slash / thrust / overhead / horizontal

const DEFAULT_ID := "staff_style"

const STYLES := {
	"staff_style": {
		"id": "staff_style",
		"name": "墨棍法",
		"style": "均衡",
		"weapon_id": "staff",
		"unlock": null,
		# 中立三连（竖向劈砍）
		"light_combo": [
			{"dmg": 14.0, "poise": 10.0, "startup": 0.10, "active": 0.12, "recovery": 0.18, "stamina": 8.0, "reach": 2.6,
			 "rot_from": Vector3(-1.25, 0, 0), "rot_to": Vector3(1.05, 0, 0),
			 "body_turn": 0.25, "step": 0.45, "trail_color": Color(0.55, 0.75, 1.0), "arc": "slash"},
			{"dmg": 12.0, "poise": 10.0, "startup": 0.08, "active": 0.12, "recovery": 0.20, "stamina": 8.0, "reach": 2.6,
			 "rot_from": Vector3(1.0, 0, 0.3), "rot_to": Vector3(-1.1, 0, -0.3),
			 "body_turn": -0.3, "step": 0.3, "trail_color": Color(0.55, 0.75, 1.0), "arc": "slash"},
			{"dmg": 22.0, "poise": 24.0, "startup": 0.16, "active": 0.14, "recovery": 0.34, "stamina": 12.0, "reach": 2.8,
			 "rot_from": Vector3(-1.85, 0, 0.5), "rot_to": Vector3(1.35, 0, -0.5),
			 "body_turn": 0.35, "step": 0.7, "trail_color": Color(0.7, 0.85, 1.0), "arc": "overhead"},
		],
		# 重击（下劈）
		"heavy": {"dmg": 40.0, "poise": 40.0, "startup": 0.40, "active": 0.16, "recovery": 0.50, "stamina": 28.0, "reach": 3.0,
		          "rot_from": Vector3(-2.1, 0, 0), "rot_to": Vector3(1.5, 0, 0),
		          "body_turn": 0.4, "step": 0.8, "trail_color": Color(0.85, 0.6, 0.3), "arc": "overhead"},
		# 方向攻击
		"forward": {"dmg": 18.0, "poise": 16.0, "startup": 0.12, "active": 0.10, "recovery": 0.22, "stamina": 10.0, "reach": 3.2,
		            "rot_from": Vector3(-0.6, 0, 0), "rot_to": Vector3(0.2, 0, 0),
		            "body_turn": 0.0, "step": 1.1, "trail_color": Color(0.6, 0.9, 0.7), "arc": "thrust"},
		"side": {"dmg": 16.0, "poise": 14.0, "startup": 0.12, "active": 0.16, "recovery": 0.24, "stamina": 10.0, "reach": 2.8,
		         "rot_from": Vector3(0.1, 1.2, 0), "rot_to": Vector3(0.1, -1.2, 0),
		         "body_turn": 0.6, "step": 0.4, "trail_color": Color(0.55, 0.75, 1.0), "arc": "horizontal"},
		"back": {"dmg": 20.0, "poise": 22.0, "startup": 0.18, "active": 0.14, "recovery": 0.30, "stamina": 12.0, "reach": 2.6,
		         "rot_from": Vector3(1.4, 0, 0), "rot_to": Vector3(-1.6, 0, 0),
		         "body_turn": -0.4, "step": -0.3, "trail_color": Color(0.85, 0.5, 0.6), "arc": "overhead"},
		# 蓄力分段（hold 0.4/0.8/1.2s）
		"charge": [
			{"dmg_mult": 1.0, "reach_mult": 1.0, "scale": 1.0},
			{"dmg_mult": 1.5, "reach_mult": 1.15, "scale": 1.1},
			{"dmg_mult": 2.1, "reach_mult": 1.35, "scale": 1.25},
			{"dmg_mult": 3.0, "reach_mult": 1.6, "scale": 1.5},
		],
	},
	"saber_style": {
		"id": "saber_style",
		"name": "斩刀诀",
		"style": "灵巧",
		"weapon_id": "saber",
		"unlock": null,
		"light_combo": [
			{"dmg": 11.0, "poise": 8.0, "startup": 0.07, "active": 0.09, "recovery": 0.14, "stamina": 6.0, "reach": 2.4,
			 "rot_from": Vector3(-1.0, 0.4, 0.2), "rot_to": Vector3(1.1, -0.4, -0.2),
			 "body_turn": 0.35, "step": 0.4, "trail_color": Color(0.9, 0.85, 0.6), "arc": "slash"},
			{"dmg": 10.0, "poise": 8.0, "startup": 0.06, "active": 0.09, "recovery": 0.13, "stamina": 6.0, "reach": 2.4,
			 "rot_from": Vector3(1.0, -0.5, -0.3), "rot_to": Vector3(-1.0, 0.5, 0.3),
			 "body_turn": -0.35, "step": 0.3, "trail_color": Color(0.9, 0.85, 0.6), "arc": "slash"},
			{"dmg": 18.0, "poise": 18.0, "startup": 0.12, "active": 0.11, "recovery": 0.24, "stamina": 9.0, "reach": 2.5,
			 "rot_from": Vector3(-1.6, 0.8, 0.6), "rot_to": Vector3(1.5, -0.8, -0.6),
			 "body_turn": 0.5, "step": 0.6, "trail_color": Color(1.0, 0.9, 0.5), "arc": "overhead"},
		],
		"heavy": {"dmg": 34.0, "poise": 46.0, "startup": 0.34, "active": 0.14, "recovery": 0.44, "stamina": 24.0, "reach": 2.7,
		          "rot_from": Vector3(-1.9, 0.6, 0.4), "rot_to": Vector3(1.7, -0.6, -0.4),
		          "body_turn": 0.55, "step": 0.7, "trail_color": Color(1.0, 0.7, 0.3), "arc": "overhead"},
		"forward": {"dmg": 15.0, "poise": 14.0, "startup": 0.09, "active": 0.08, "recovery": 0.18, "stamina": 8.0, "reach": 3.0,
		            "rot_from": Vector3(-0.5, 0, 0), "rot_to": Vector3(0.15, 0, 0),
		            "body_turn": 0.0, "step": 1.3, "trail_color": Color(0.8, 0.9, 0.5), "arc": "thrust"},
		"side": {"dmg": 14.0, "poise": 12.0, "startup": 0.09, "active": 0.14, "recovery": 0.20, "stamina": 8.0, "reach": 2.6,
		         "rot_from": Vector3(0.05, 1.4, 0), "rot_to": Vector3(0.05, -1.4, 0),
		         "body_turn": 0.7, "step": 0.5, "trail_color": Color(0.9, 0.85, 0.6), "arc": "horizontal"},
		"back": {"dmg": 17.0, "poise": 20.0, "startup": 0.14, "active": 0.12, "recovery": 0.26, "stamina": 10.0, "reach": 2.4,
		         "rot_from": Vector3(1.3, 0, 0.4), "rot_to": Vector3(-1.5, 0, -0.4),
		         "body_turn": -0.45, "step": -0.2, "trail_color": Color(1.0, 0.6, 0.5), "arc": "overhead"},
		"charge": [
			{"dmg_mult": 1.0, "reach_mult": 1.0, "scale": 1.0},
			{"dmg_mult": 1.5, "reach_mult": 1.15, "scale": 1.1},
			{"dmg_mult": 2.1, "reach_mult": 1.35, "scale": 1.25},
			{"dmg_mult": 3.0, "reach_mult": 1.6, "scale": 1.5},
		],
	},
}

static func get_style(id: String) -> Dictionary:
	return STYLES.get(id, STYLES[DEFAULT_ID])
