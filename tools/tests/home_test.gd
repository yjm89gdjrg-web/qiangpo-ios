extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/boot.tscn") as PackedScene
	var home: Node = scene.instantiate()
	root.add_child(home)
	current_scene = home
	await process_frame
	assert(get_nodes_in_group("player").is_empty(), "首页不应加载玩家")
	assert(get_nodes_in_group("enemy").is_empty(), "首页不应加载敌人")
	print("PASS home has no gameplay running")
	home.call("_start")
	await process_frame
	await process_frame
	assert(current_scene is Node3D, "开始按钮应进入地图")
	assert(get_nodes_in_group("player").size() == 1)
	print("PASS start enters map")
	current_scene.queue_free()
	await process_frame
	quit(0)
