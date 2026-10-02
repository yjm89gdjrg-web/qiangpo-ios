extends CanvasLayer

## 手机 HUD：按实际屏幕尺寸自动排版
## 状态文字 + 下包/拆包 + 换枪 + 跳跃 + 开火

var status: Label
var scoreboard: Label
var hp_label: Label
var armor_label: Label
var ammo_label: Label
var weapon_label: Label
var killfeed: VBoxContainer
var hitmarker: Control
var hp_fill: ColorRect
var armor_fill: ColorRect
var hp_bar_bg: Panel
var armor_bar_bg: Panel
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
var crosshair: Control

func _ready() -> void:
	layer = 10
	status = get_node_or_null("Status") as Label
	scoreboard = Label.new()
	scoreboard.name = "Scoreboard"
	scoreboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scoreboard)
	action_button = get_node_or_null("ActionButton") as Button
	weapon_button = get_node_or_null("WeaponButton") as Button
	jump_button = get_node_or_null("JumpButton") as Button
	fire_button = get_node_or_null("FireButton") as Button
	# Multi-touch: a Button's default mouse filter swallows a touch so it never
	# reaches the game layer, which makes "hold move + tap jump" unreliable.
	# Handle ScreenTouch explicitly on each button instead of the pressed signal.
	for control in [action_button, weapon_button, jump_button]:
		if control:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
			control.gui_input.connect(_action_button_input.bind(control))
	if fire_button:
		fire_button.button_down.connect(_on_fire_down)
		fire_button.button_up.connect(_on_fire_up)
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.size = Vector2(44, 44)
	var accent := Color(0.85, 0.95, 1.0, 0.85)
	for i in 4:
		var arm := ColorRect.new()
		arm.color = accent
		arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var long := Vector2(14, 2)
		if i >= 2:
			long = Vector2(2, 14)
		arm.size = long
		var gap := 6.0
		if i == 0:
			arm.position = Vector2(22 - 14 - gap, 21)
		elif i == 1:
			arm.position = Vector2(22 + gap, 21)
		elif i == 2:
			arm.position = Vector2(21, 22 - 14 - gap)
		else:
			arm.position = Vector2(21, 22 + gap)
		crosshair.add_child(arm)
	add_child(crosshair)
	_build_combat_hud()
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
	var area := layout.usable_rect(vp)
	if crosshair:
		crosshair.position = (area.position + area.size * 0.5 - crosshair.size * 0.5).round()
	if status:
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.position = area.position + Vector2(18, 18)
		status.size = Vector2(area.size.x * 0.70, area.size.y * 0.16)
		status.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.035, 18.0, 34.0)))
	if scoreboard:
		scoreboard.position = area.position + Vector2(0, 18)
		scoreboard.size = Vector2(area.size.x, 50)
		scoreboard.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.04, 20.0, 36.0)))
	var stat_fs := int(clamp(vp.y * 0.038, 18.0, 32.0))
	var bar_w: float = clampf(area.size.x * 0.20, 150.0, 300.0)
	var bar_h: float = clampf(vp.y * 0.035, 16.0, 26.0)
	var base_y: float = area.position.y + area.size.y * 0.84
	if hp_bar_bg:
		hp_bar_bg.position = Vector2(area.position.x + area.size.x * 0.28, base_y)
		hp_bar_bg.size = Vector2(bar_w, bar_h)
	if armor_bar_bg:
		armor_bar_bg.position = Vector2(area.position.x + area.size.x * 0.28, base_y + bar_h + 6)
		armor_bar_bg.size = Vector2(bar_w, bar_h)
	if hp_label:
		hp_label.position = Vector2(area.position.x + area.size.x * 0.28 - 60, base_y - 6)
		hp_label.size = Vector2(56, bar_h + 12)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hp_label.add_theme_font_size_override("font_size", stat_fs)
	if armor_label:
		armor_label.position = Vector2(area.position.x + area.size.x * 0.28 - 60, base_y + bar_h)
		armor_label.size = Vector2(56, bar_h + 12)
		armor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		armor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		armor_label.add_theme_font_size_override("font_size", stat_fs)
	if ammo_label:
		ammo_label.position = Vector2(area.position.x + area.size.x * 0.50, base_y - 18)
		ammo_label.size = Vector2(area.size.x * 0.16, stat_fs * 2.4)
		ammo_label.add_theme_font_size_override("font_size", int(stat_fs * 1.6))
	if weapon_label:
		weapon_label.position = Vector2(area.position.x + area.size.x * 0.50, base_y + stat_fs * 1.6)
		weapon_label.size = Vector2(area.size.x * 0.16, stat_fs)
		weapon_label.add_theme_font_size_override("font_size", int(stat_fs * 0.8))
	if killfeed:
		killfeed.position = Vector2(area.position.x + area.size.x - 320, area.position.y + 70)
		killfeed.size = Vector2(300, 160)
		for child in killfeed.get_children():
			if child is Label:
				(child as Label).add_theme_font_size_override("font_size", int(stat_fs * 0.7))
	if hitmarker:
		hitmarker.position = (area.position + area.size * 0.5 - hitmarker.size * 0.5).round()
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
		if control is Button:
			_style_button(control as Button)
	weapon_button.text = "换枪"
	jump_button.text = "跳跃"
	fire_button.text = "开火"
	move_region.visible = layout.show_joystick
	settings_button.size = Vector2(90, 44)
	settings_button.position = area.position + Vector2(maxf(0, area.size.x - 108), 18)
	_style_button(settings_button)
	if is_instance_valid(player):
		player.move_region = layout.rect_for("move", vp)
		player.reset_mobile_input()

func _build_combat_hud() -> void:
	# 命中标记（中心 X，命中时短暂显示）
	hitmarker = Control.new()
	hitmarker.name = "HitMarker"
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.size = Vector2(40, 40)
	hitmarker.visible = false
	var hm_color := Color(1.0, 0.32, 0.28, 0.95)
	for ang in [PI / 4.0, -PI / 4.0]:
		var bar := ColorRect.new()
		bar.color = hm_color
		bar.size = Vector2(24, 3)
		bar.pivot_offset = Vector2(12, 1.5)
		bar.position = Vector2(8, 18.5)
		bar.rotation = ang
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hitmarker.add_child(bar)
	add_child(hitmarker)

	# 左下：血量条 + 护甲条（CF 风格）
	hp_bar_bg = _make_bar(Color(0.12, 0.16, 0.20, 0.72))
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.32, 0.86, 0.38, 1.0)
	hp_bar_bg.add_child(hp_fill)
	add_child(hp_bar_bg)
	hp_label = _make_stat_label()
	add_child(hp_label)

	armor_bar_bg = _make_bar(Color(0.12, 0.16, 0.20, 0.72))
	armor_fill = ColorRect.new()
	armor_fill.color = Color(0.36, 0.62, 0.95, 1.0)
	armor_bar_bg.add_child(armor_fill)
	add_child(armor_bar_bg)
	armor_label = _make_stat_label()
	add_child(armor_label)

	# 右下：弹药 / 武器名
	ammo_label = _make_stat_label()
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(ammo_label)
	weapon_label = _make_stat_label()
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	weapon_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.85))
	add_child(weapon_label)

	# 右上：击杀提示
	killfeed = VBoxContainer.new()
	killfeed.name = "KillFeed"
	killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	killfeed.alignment = BoxContainer.ALIGNMENT_END
	killfeed.add_theme_constant_override("separation", 4)
	add_child(killfeed)

func _update_combat_hud() -> void:
	if not is_instance_valid(player):
		return
	var hp_val: int = player.hp
	var armor_val: int = player.armor if "armor" in player else 0
	if hp_label:
		hp_label.text = str(hp_val)
	if armor_label:
		armor_label.text = str(armor_val)
	if hp_fill and hp_bar_bg:
		var w: float = maxf(hp_bar_bg.size.x - 4.0, 1.0)
		hp_fill.position = Vector2(2, 2)
		hp_fill.size = Vector2(w * clampf(float(hp_val) / 100.0, 0.0, 1.0), maxf(hp_bar_bg.size.y - 4.0, 1.0))
		hp_fill.color = Color(0.32, 0.86, 0.38) if hp_val > 35 else Color(0.92, 0.28, 0.24)
	if armor_fill and armor_bar_bg:
		var w2: float = maxf(armor_bar_bg.size.x - 4.0, 1.0)
		armor_fill.position = Vector2(2, 2)
		armor_fill.size = Vector2(w2 * clampf(float(armor_val) / 100.0, 0.0, 1.0), maxf(armor_bar_bg.size.y - 4.0, 1.0))
	if ammo_label:
		if player.reloading:
			ammo_label.text = "装弹中…"
		else:
			var mag: int = player.ammo
			var cap: int = player._cur()["ammo"]
			ammo_label.text = "%d / %d" % [mag, cap]
		ammo_label.add_theme_color_override("font_color", Color(0.92, 0.28, 0.24) if player.ammo <= 5 else Color(0.96, 0.98, 1.0))
	if weapon_label:
		weapon_label.text = player._cur()["label"]
	if hitmarker:
		hitmarker.visible = player.hit_marker > 0.0

func _make_bar(bg: Color) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.7, 0.85, 1.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _make_stat_label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	return l

func add_kill_feed(text: String) -> void:
	if killfeed == null:
		return
	var row := Label.new()
	row.text = text
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6, 1.0))
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	row.add_theme_constant_override("outline_size", 4)
	row.add_theme_font_size_override("font_size", 18)
	killfeed.add_child(row)
	while killfeed.get_child_count() > 5:
		killfeed.get_child(0).queue_free()
		break

func _action_button_input(event: InputEvent, control: Button) -> void:
	if get_tree().paused:
		return
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed:
			control.set_pressed_no_signal(true)
			control.accept_event()
			if control == action_button:
				_on_action()
			elif control == weapon_button:
				_on_switch()
			elif control == jump_button:
				_on_jump()
		else:
			control.set_pressed_no_signal(false)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			control.set_pressed_no_signal(true)
			if control == action_button:
				_on_action()
			elif control == weapon_button:
				_on_switch()
			elif control == jump_button:
				_on_jump()
		else:
			control.set_pressed_no_signal(false)

func _style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.20, 0.28, 0.55)
	normal.border_color = Color(0.72, 0.88, 1.0, 0.75)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(14)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.95, 0.72, 0.25, 0.80)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))

func _process(_delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp != last_size:
		last_size = vp
		_layout()
	if status and player and player.has_method("get_hud_text"):
		status.text = player.get_hud_text()
	if scoreboard and round_manager:
		var t: int = round_manager.t_score
		var ct: int = round_manager.ct_score
		var r: int = round_manager.round_number
		var max_r: int = round_manager.MAX_ROUNDS
		scoreboard.text = "T: %d | CT: %d | 回合: %d/%d" % [t, ct, r, max_r]
	_update_combat_hud()
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
		_clear_action_buttons()

func _clear_action_buttons() -> void:
	for control in [action_button, weapon_button, jump_button]:
		if control:
			control.set_pressed_no_signal(false)
