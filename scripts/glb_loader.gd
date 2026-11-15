extends RefCounted
## GLB / GLTF 模型加载工具
## 自动完成三件小白最容易踩坑的事：统一身高、脚底落地、查找动画

## 把模型挂到 parent 下，返回 {"root": Node3D, "anim": AnimationPlayer, "clips": PackedStringArray}
## 文件不存在时返回空字典，调用方继续使用程序化占位模型
static func attach_model(parent: Node3D, path: String, target_height: float, tag := "[GLB]") -> Dictionary:
	if not ResourceLoader.exists(path):
		print("%s 未找到 %s，继续使用程序化占位模型" % [tag, path])
		return {}

	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		push_warning("%s 加载失败：%s（文件可能未导入完成）" % [tag, path])
		return {}

	var root := (packed as PackedScene).instantiate() as Node3D
	if root == null:
		push_warning("%s 实例化失败：%s" % [tag, path])
		return {}

	parent.add_child(root)
	root.name = "Visual"

	# 1) 按包围盒高度缩放到目标身高
	var box := _global_aabb(root)
	if box.size.y > 0.001:
		root.scale = Vector3.ONE * (target_height / box.size.y)

	# 2) 让脚底对齐 parent 原点（避免悬空或陷地）
	box = _global_aabb(root)
	var ground_y := parent.global_position.y
	root.global_position.y -= (box.position.y - ground_y)

	var anim := _find_anim_player(root)
	var clips := PackedStringArray()
	if anim != null:
		clips = anim.get_animation_list()

	print("%s 已加载 %s | 缩放 %.3f | 动画 %d 个" % [tag, path, root.scale.x, clips.size()])
	if clips.size() > 0:
		print("%s 动画列表：%s" % [tag, ", ".join(clips)])

	return {"root": root, "anim": anim, "clips": clips}

## 计算节点下所有网格的世界空间包围盒
static func _global_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	if first:
		result = AABB(root.global_position, Vector3.ONE * 0.001)
	return result

## 递归查找第一个 AnimationPlayer
static func _find_anim_player(root: Node3D) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for node in root.find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null

## 按关键词自动匹配动画名（返回 key -> clip 名称）
static func auto_map(clips: PackedStringArray, hints: Dictionary) -> Dictionary:
	var map := {}
	for key in hints.keys():
		map[key] = ""
	for key in hints.keys():
		var words: Array = hints[key]
		for clip in clips:
			var low := String(clip).to_lower()
			var matched := false
			for w in words:
				if low.contains(String(w)):
					matched = true
					break
			if matched:
				map[key] = String(clip)
				break
	return map
