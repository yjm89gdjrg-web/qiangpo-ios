extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not scene:
		push_error("场景加载失败"); quit(1); return
	var root: Node3D = scene.instantiate() as Node3D
	get_root().add_child(root)
	var player: CharacterBody3D = root.get_node_or_null("Player")
	var bots: Node3D = root.get_node_or_null("Bots")
	if player == null or bots == null:
		push_error("缺 Player/Bots"); quit(1); return
	var wr: Node3D = player.get_node_or_null("Head/Camera3D/WeaponRoot")
	print("✅ 场景加载 敌人=", bots.get_child_count(), " 武器数=", (wr.get_child_count() if wr else -1))
	for i in range(60):
		await process_frame
	# 换枪测试
	player.call("_switch_weapon", 2)
	await process_frame
	print("   换到武器 idx=2, ammo=", player.ammo)
	player.call("_fire")
	await process_frame
	print("   开火后 ammo=", player.ammo)
	for i in range(120):
		await process_frame
	print("   玩家HP=", player.hp, " 击杀=", player.kills)
	print("✅ 无崩溃")
	quit(0)
