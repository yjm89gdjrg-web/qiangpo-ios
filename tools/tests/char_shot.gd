extends SceneTree

func _initialize() -> void:
	await process_frame
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var bots: Node = main.get_node("Bots")
	var b1: Node3D = bots.get_child(0) as Node3D   # CT -> red
	var b3: Node3D = bots.get_child(2) as Node3D   # T  -> blue
	for b in bots.get_children():
		b.set_physics_process(false)
		b.set_process(false)
	b1.global_position = Vector3(-2.6, 0, 23)
	b1.rotation.y = PI
	b3.global_position = Vector3(2.6, 0, 23)
	b3.rotation.y = PI
	var player: Node3D = main.get_node("Player") as Node3D
	player.global_position = Vector3(0, 1.0, 27.5)
	player.rotation.y = 0.0
	var head: Node3D = player.get_node("Head") as Node3D
	head.rotation.x = deg_to_rad(-5.0)
	for i in range(40):
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("/home/ubuntu/.openclaw/workspace/shotdawn-char-preview.png")
	print("saved")
	quit()
