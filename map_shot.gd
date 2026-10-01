extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var scene: Node3D = packed.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var ground: MeshInstance3D = scene.get_node("Ground/Mesh") as MeshInstance3D
	var collision: CollisionShape3D = scene.get_node("Ground/CollisionShape3D") as CollisionShape3D
	var plane: PlaneMesh = ground.mesh as PlaneMesh
	var box: BoxShape3D = collision.shape as BoxShape3D
	if abs(plane.size.x * ground.scale.x - box.size.x) > 0.01:
		push_error("GROUND_SIZE_MISMATCH")
		quit(1)
		return
	print("PASS ground visual/collision match: ", box.size)
	scene.get_node("Bots").process_mode = Node.PROCESS_MODE_DISABLED
	var player: CharacterBody3D = scene.get_node("Player") as CharacterBody3D
	for i in range(90):
		await physics_frame
	if not player.is_on_floor():
		push_error("PLAYER_NOT_ON_FLOOR")
		quit(1)
		return
	print("PASS player grounded y=", player.position.y)
	var hud: CanvasLayer = scene.get_node("HUD") as CanvasLayer
	var old_ammo: int = player.ammo
	hud.call("_on_fire_down")
	for i in range(2):
		await physics_frame
	hud.call("_on_fire_up")
	if player.ammo >= old_ammo:
		push_error("HUD_FIRE_NOT_CONNECTED")
		quit(1)
		return
	print("PASS HUD hold-fire consumes ammo")
	var bot: CharacterBody3D = scene.get_node("Bots/Bot1") as CharacterBody3D
	bot.position = Vector3(10, 0, -11)
	player.position = Vector3(10, 0, -1)
	await physics_frame
	var hp_before: int = player.hp
	bot.call("_shoot_at_player")
	if player.hp != hp_before:
		push_error("BOT_SHOOTS_THROUGH_COVER")
		quit(1)
		return
	print("PASS cover blocks bot bullets")
	player.position = Vector3(10, 0, -16)
	await physics_frame
	bot.call("_shoot_at_player")
	if player.hp >= hp_before:
		push_error("BOT_CANNOT_HIT_VISIBLE_PLAYER")
		quit(1)
		return
	print("PASS visible player takes bot damage")
	player.position = Vector3(0, 0, -14)
	var round_manager: Node = scene.get_node("RoundManager")
	round_manager.bomb_planted = true
	round_manager.bomb_timer = 35.0
	round_manager.call("_process", 0.1)
	if not str(round_manager.phase).contains("倒计时"):
		push_error("BOMB_COUNTDOWN_HIDDEN")
		quit(1)
		return
	print("PASS bomb countdown survives at site")
	round_manager.bomb_planted = false
	player.position = Vector3(0, 0, 0)
	player.hp = 100
	await physics_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		image.save_png(OS.get_environment("SHOTDAWN_VALIDATION_DIR").path_join("shotdawn-first-person.png"))
		var camera: Camera3D = Camera3D.new()
		scene.add_child(camera)
		camera.position = Vector3(35, 48, 52)
		camera.look_at(Vector3(0, 0, -8), Vector3.UP)
		camera.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		image.save_png(OS.get_environment("SHOTDAWN_VALIDATION_DIR").path_join("shotdawn-map.png"))
		print("PASS screenshots saved")
	await create_timer(0.35).timeout
	scene.queue_free()
	await process_frame
	quit(0)
