extends Node
## Keep all gameplay unloaded until the player explicitly starts.
const Store = preload("res://scripts/hot_update/resource_store.gd")
var starting: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.035, 0.055, 0.085)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	var title: Label = Label.new()
	title.text = "枪破黎明"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "单机爆破 · %s" % Store.APP_VERSION
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	var play: Button = Button.new()
	play.name = "StartButton"
	play.text = "开始游戏"
	play.custom_minimum_size = Vector2(300, 64)
	play.pressed.connect(_start)
	box.add_child(play)
	var manager: Node = Node.new()
	manager.name = "UpdateManager"
	manager.set_script(load("res://scripts/update_manager.gd"))
	add_child(manager)
	var settings: CanvasLayer = CanvasLayer.new()
	settings.set_script(load("res://scripts/ui/settings.gd"))
	add_child(settings)
	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "设置"
	settings_button.custom_minimum_size = Vector2(300, 56)
	box.add_child(settings_button)
	settings_button.pressed.connect(settings.open)

func _start() -> void:
	if starting or get_tree().paused:
		return
	starting = true
	call_deferred("_launch")

func _launch() -> void:
	var store = Store.new()
	store.activate()
	var packed: PackedScene = ResourceLoader.load("res://scenes/main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		starting = false
		push_error("无法加载内置关卡")
		return
	var main: Node3D = packed.instantiate() as Node3D
	var audio = load("res://scripts/hot_update/audio_manager.gd").new()
	audio.refresh(store)
	main.set_meta("audio_ready", audio.has_any())
	store.apply_map(main)
	main.set_meta("active_resource_revision", int(store.active_manifest.get("revision", 0)))
	main.set_meta("resource_boot_error", store.last_error)
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	queue_free()
