extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var player = main.player
	var fx = main.combat_fx
	var events: Array[StringName] = []
	player.vfx_requested.connect(func(kind: StringName, _from: Vector3, _to: Vector3): events.append(kind))
	var fixed_children: int = fx.get_child_count()
	check(main.target_panel.visible, "target panel initializes")
	check(main.skill_slots.size() == 4, "four skill slots initialize")

	player.spell_cd["freeze"] = 2.0
	check(not player.cast_freeze(), "cooldown blocks freeze")
	check(events.is_empty(), "failed cast emits no effect")
	player.spell_cd["freeze"] = 0.0
	player.chi = 100.0
	check(player.cast_freeze(), "freeze succeeds")
	await process_frame
	await process_frame
	check(events.has(&"freeze"), "freeze effect event emitted")
	check(fx.freeze_by_enemy.size() == main.enemies.size(), "all frozen enemies receive one ring set")
	var frozen = main.enemies[0]
	frozen.hp = 0.0
	await process_frame
	await process_frame
	check(not fx.freeze_by_enemy.has(frozen.get_instance_id()), "dead enemy freeze rings recycle")

	player.spell_cd["blink"] = 0.0
	player.chi = 100.0
	var before: Vector3 = player.global_position
	check(player.cast_blink(), "blink succeeds")
	check(player.global_position.distance_to(before) > 1.0, "blink moves player")
	player.spell_cd["shield"] = 0.0
	player.chi = 100.0
	check(player.cast_shield(), "shield succeeds")
	await process_frame
	await process_frame
	check(fx.shield_root.visible, "shield visual follows active buff")

	player.chi = 100.0
	player.try_transform()
	check(player.transformed, "transform starts")
	await process_frame
	check(fx.transform_root.visible, "transform persistent effect visible")
	player._end_transform()
	await process_frame
	check(not player.transformed and not fx.transform_root.visible, "transform end effect recycles")

	player.stamina = 100.0
	player._start_dodge(Vector3.RIGHT)
	check(events.has(&"dodge"), "dodge effect event emitted")
	var enemy = main.enemies[1]
	player._on_parry_counter(enemy)
	check(events.has(&"parry"), "parry effect event emitted")
	await process_frame
	check(fx.on_posture_broken != null, "posture callback remains callable")

	for i in 5:
		player.spell_cd["freeze"] = 0.0
		player.spell_cd["blink"] = 0.0
		player.spell_cd["shield"] = 0.0
		player.chi = 100.0
		player.cast_freeze()
		player.cast_blink()
		player.cast_shield()
		await process_frame
	check(fx.get_child_count() == fixed_children, "repeated casts do not add effect nodes")
	check(main.player_hp_bar.max_value == player.get_max_hp(), "HUD HP maximum matches player")
	check(main.skill_slots["blink"]["mask"].visible, "skill cooldown mask follows actual cooldown")

	if "--capture" in OS.get_cmdline_args() or "--capture" in OS.get_cmdline_user_args():
		player.chi = 100.0
		player.spell_cd["freeze"] = 0.0
		player.spell_cd["shield"] = 0.0
		player.cast_freeze()
		player.cast_shield()
		player.try_transform()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		root.size = Vector2i(1280, 720)
		for i in 12:
			await process_frame
		var image_1280 := root.get_texture().get_image()
		image_1280.save_png("res://.godot/tmp_combat_ui_1280.png")
		root.size = Vector2i(1600, 900)
		for i in 6:
			await process_frame
		var image_1600 := root.get_texture().get_image()
		image_1600.save_png("res://.godot/tmp_combat_ui_1600.png")

	var audio = root.get_node_or_null("Sfx")
	if audio:
		for audio_player in audio._players:
			audio_player.stop()
	main.queue_free()
	await process_frame
	await process_frame
	print("COMBAT_FX_TEST failures=", failures)
	quit(1 if failures > 0 else 0)
