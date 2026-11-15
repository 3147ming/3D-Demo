extends Control
## 简易血条 UI（玩家与敌人共用）

@onready var bar: ProgressBar = $Bar
@onready var label: Label = $Label

var hp_max := 100.0

func _ready() -> void:
	bar.min_value = 0.0
	bar.max_value = hp_max
	bar.value = hp_max

func set_hp(value: float) -> void:
	bar.value = clampf(value, 0.0, hp_max)
	label.text = "%d / %d" % [int(value), int(hp_max)]

func set_max(m: float) -> void:
	hp_max = m
	bar.max_value = m
