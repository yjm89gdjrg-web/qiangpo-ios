extends SceneTree
## Proves bots can navigate the rebuilt map rather than grinding into walls.
var failures := 0

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		check(false, "main scene loads")
		quit(1)
		return
	var main: Node3D = packed.instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await process_frame

	var player: Node3D = main.get_node("Player") as Node3D
	var bots: Array = []
	var container: Node = main.get_node("Bots")
	for child in container.get_children():
		if child is CharacterBody3D:
			bots.append(child)
	check(bots.size() == 3, "3 bots present")

	check(main.get_node("Structures").get_child_count() > 0, "structures exist")
	check(main.get_node("Props").get_child_count() > 0, "props exist")
	check(main.get_node("Covers").get_child_count() == 4, "4 covers exist")
	check(main.get_node("Ground/Mesh") != null, "hot-update Ground/Mesh path preserved")

	# Bot obstacle collection must find the new geometry.
	var bot: CharacterBody3D = bots[0] as CharacterBody3D
	bot._collect_obstacles()
	check(bot.obstacles.size() >= 8, "bot collected obstacles (%d)" % bot.obstacles.size())

	# Place a bot far from the player behind the mid block and let it chase.
	var start_pos := Vector3(-18, 1, -22)
	bot.global_position = start_pos
	player.global_position = Vector3(0, 0.05, 12)
	var start_dist: float = bot.global_position.distance_to(player.global_position)
	for i in range(240):
		await physics_frame
	var end_dist: float = bot.global_position.distance_to(player.global_position)
	check(end_dist < start_dist - 4.0, "bot closed distance (%.1f -> %.1f)" % [start_dist, end_dist])
	check(bot.global_position.y > -1.0, "bot did not fall through the floor")

	# A bot placed against a wall should still make progress sideways, not freeze.
	var bot2: CharacterBody3D = bots[1] as CharacterBody3D
	bot2.global_position = Vector3(0, 0.05, -1.0)
	bot2._collect_obstacles()
	var pos_before: Vector3 = bot2.global_position
	for i in range(120):
		await physics_frame
	var moved: float = pos_before.distance_to(bot2.global_position)
	check(moved > 1.0, "bot behind mid block moves instead of sticking (moved %.2f)" % moved)

	main.queue_free()
	await process_frame
	print("BOT NAV: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
