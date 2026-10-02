extends SceneTree

func _init():
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	
	await create_timer(0.5).timeout
	
	var vp := root.get_viewport()
	vp.size = Vector2i(1920, 1080)
	
	var player = scene.get_node("Player")
	var camera = player.get_node("Head/Camera3D")
	
	# 调整视角：稍微向上看，能看到墙体和地面
	player.global_position = Vector3(0, 1.6, 10)
	player.rotation.y = deg_to_rad(180)
	camera.rotation.x = deg_to_rad(-10)
	
	await create_timer(0.3).timeout
	
	var img := vp.get_texture().get_image()
	var out := "/home/ubuntu/.openclaw/workspace/shotdawn-textured-map.png"
	img.save_png(out)
	print("✓ Screenshot saved: " + out)
	
	quit()
