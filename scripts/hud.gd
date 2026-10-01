extends CanvasLayer

## 手机 HUD：按实际屏幕尺寸自动排版
## 状态文字 + 下包/拆包 + 换枪 + 跳跃 + 开火

var status: Label
var action_button: Button
var weapon_button: Button
var jump_button: Button
var fire_button: Button
var player: Node
var round_manager: Node
var last_size := Vector2.ZERO
const Layout = preload("res://scripts/ui/control_layout.gd")
var layout = Layout.new()
var settings: CanvasLayer
var settings_button: Button
var move_region: Panel
var fire_pointer := -1

func _ready() -> void:
	layer = 10
	status = get_node_or_null("Status") as Label
	action_button = get_node_or_null("ActionButton") as Button
	weapon_button = get_node_or_null("WeaponButton") as Button
	jump_button = get_node_or_null("JumpButton") as Button
	fire_button = get_node_or_null("FireButton") as Button
	if action_button and not action_button.pressed.is_connected(_on_action):
		action_button.pressed.connect(_on_action)
	if weapon_button and not weapon_button.pressed.is_connected(_on_switch):
		weapon_button.pressed.connect(_on_switch)
	if jump_button and not jump_button.pressed.is_connected(_on_jump):
		jump_button.pressed.connect(_on_jump)
	if fire_button:
		fire_button.button_down.connect(_on_fire_down)
		fire_button.button_up.connect(_on_fire_up)
	move_region = Panel.new()
	move_region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.25, 0.35, 0.25)
	style.border_color = Color(0.7, 0.85, 1.0, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(200)
	move_region.add_theme_stylebox_override("panel", style)
	add_child(move_region)
	var hint := Label.new()
	hint.text = "移动"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_region.add_child(hint)
	settings = CanvasLayer.new()
	settings.set_script(load("res://scripts/ui/settings.gd"))
	get_parent().add_child.call_deferred(settings)
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "设置"
	settings_button.pressed.connect(func(): settings.open())
	add_child(settings_button)
	if fire_button:
		fire_button.gui_input.connect(_fire_input)
	_layout()
	call_deferred("_link")

func _link() -> void:
	var scene := get_tree().current_scene
	player = scene.get_node_or_null("Player")
	round_manager = scene.get_node_or_null("RoundManager")
	_layout()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	layout.load_settings()
	if status:
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.position = Vector2(18, 18)
		status.size = Vector2(vp.x * 0.70, vp.y * 0.16)
		status.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.035, 18.0, 34.0)))
	var controls := {"fire": fire_button, "jump": jump_button, "switch": weapon_button, "plant": action_button, "move": move_region}
	for id in controls:
		var control: Control = controls[id]
		if not control:
			continue
		if control is Button:
			control.clip_text = true
		var rect: Rect2 = layout.rect_for(id, vp)
		control.size = rect.size
		control.position = rect.position
		control.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.03, 16.0, 28.0)))
	weapon_button.text = "换枪"
	jump_button.text = "跳跃"
	fire_button.text = "开火"
	move_region.visible = layout.show_joystick
	settings_button.size = Vector2(90, 44)
	settings_button.position = Vector2(maxf(0, vp.x - 108), 18)
	if is_instance_valid(player):
		player.move_region = layout.rect_for("move", vp)
		player.reset_mobile_input()

func _process(_delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp != last_size:
		last_size = vp
		_layout()
	if status and player and player.has_method("get_hud_text"):
		status.text = player.get_hud_text()
	if action_button and round_manager:
		action_button.text = "拆包" if round_manager.bomb_planted else "下包"

func _on_action() -> void:
	if get_tree().paused or not round_manager:
		return
	if round_manager.bomb_planted:
		round_manager.try_defuse()
	else:
		round_manager.try_plant()

func _on_switch() -> void:
	if not get_tree().paused and player and player.has_method("_switch_weapon"):
		player.call("_switch_weapon", (player.weapon_idx + 1) % player.WEAPONS.size())

func _on_jump() -> void:
	if not get_tree().paused and player and player.is_on_floor():
		player.velocity.y = player.JUMP_VELOCITY

func _on_fire_down() -> void:
	if not get_tree().paused and is_instance_valid(player):
		player.hud_firing = true

func _on_fire_up() -> void:
	if is_instance_valid(player):
		player.hud_firing = false

func _fire_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not get_tree().paused:
			fire_pointer = event.index
			_on_fire_down()
		elif event.index == fire_pointer:
			fire_pointer = -1
			_on_fire_up()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == fire_pointer:
		fire_pointer = -1
		_on_fire_up()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_on_fire_up()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_fire_up()
