extends Node
## 启动入口：先显示加载屏，再切到正式关卡

const LEVEL := "res://scenes/main.tscn"

func _ready() -> void:
	# 用 get_node_or_null 而不是直接写单例名，插件未启用时也不会解析报错
	var loader := get_node_or_null("/root/SceneLoader")
	if loader == null or not loader.has_method("load_scene"):
		# 兜底：没有加载屏就直接进关卡
		get_tree().change_scene_to_file(LEVEL)
		return
	loader.call("load_scene", LEVEL)
