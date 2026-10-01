extends Node
## No preload of main scene or gameplay assets: validate/activate BEFORE loading main.
const Store = preload("res://scripts/hot_update/resource_store.gd")

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var store = Store.new()
	store.activate()
	# Explicit string load prevents main's resource dependencies being cached before boot.
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("无法加载内置关卡")
		return
	var main := packed.instantiate() as Node3D
	store.apply_map(main)
	main.set_meta("active_resource_revision", int(store.active_manifest.get("revision", 0)))
	main.set_meta("resource_boot_error", store.last_error)
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	queue_free()
