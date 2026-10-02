extends SceneTree

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main: Node3D = packed.instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	# hide boot/home if present
	await process_frame
	await process_frame
	var vp: Viewport = root
	vp.size = Vector2i(1280, 720)
	var player: Node3D = main.get_node("Player") as Node3D
	player.global_position = Vector3(0, 1.0, 14)
	player.rotation.y = PI
	var head: Node3D = player.get_node("Head") as Node3D
	head.rotation.x = deg_to_rad(-6.0)
	for i in range(40):
		await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	img.save_png("/home/ubuntu/.openclaw/workspace/shotdawn-fps-preview.png")
	print("saved")
	quit()
