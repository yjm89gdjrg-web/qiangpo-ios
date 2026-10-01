extends CanvasLayer
const Layout = preload("res://scripts/ui/control_layout.gd")
const Pause = preload("res://scripts/ui/modal_pause.gd")
const LABELS := {"fire": "开火", "jump": "跳跃", "switch": "换枪", "plant": "下包 / 拆包", "move": "移动区域"}
var layout = Layout.new()
var overlay: Control
var menu: CenterContainer
var editor: Control
var selected := "fire"
var handles: Dictionary = {}
var slider: HSlider
var selection: Label
var joystick_toggle: CheckButton
var save_status: Label
var dragging := false
var pointer := -2
var drag_offset := Vector2.ZERO
var last_size := Vector2.ZERO
var snapshot: Dictionary
var old_show := true
var pause_gate: Node

func _ready() -> void:
	name = "Settings"
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	layout.load_settings()
	pause_gate = Pause.for_scene(get_parent())
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.hide()
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	menu = CenterContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(menu)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 12)
	menu.add_child(box)
	_button(box, "自定义触屏布局", open_editor)
	joystick_toggle = CheckButton.new()
	joystick_toggle.text = "显示移动摇杆区域"
	joystick_toggle.toggled.connect(_toggle_joystick)
	box.add_child(joystick_toggle)
	_button(box, "更新", open_update)
	_button(box, "返回", close)
	save_status = Label.new()
	box.add_child(save_status)
	editor = Control.new()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.hide()
	overlay.add_child(editor)
	for id in Layout.IDS:
		var handle := Button.new()
		handle.text = LABELS[id]
		handle.clip_text = true
		handle.gui_input.connect(_handle_input.bind(id))
		editor.add_child(handle)
		handles[id] = handle
	var toolbar := VBoxContainer.new()
	var area := layout.usable_rect(get_viewport().get_visible_rect().size)
	toolbar.position = area.position + Vector2(12, 8)
	toolbar.custom_minimum_size = Vector2(300, 0)
	editor.add_child(toolbar)
	selection = Label.new()
	selection.text = "拖动按键 / 移动区域；选择后调大小"
	toolbar.add_child(selection)
	slider = HSlider.new()
	slider.min_value = 0.6
	slider.max_value = 1.8
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(280, 36)
	slider.value_changed.connect(_resize_selected)
	toolbar.add_child(slider)
	var row := HBoxContainer.new()
	toolbar.add_child(row)
	_button(row, "保存", save_editor)
	_button(row, "取消", cancel_editor)
	_button(row, "恢复默认", restore_defaults)

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(90, 44)
	button.pressed.connect(callback)
	parent.add_child(button)

func open() -> void:
	if overlay.visible:
		return
	pause_gate.acquire(self)
	overlay.show()
	menu.show()
	editor.hide()
	joystick_toggle.set_pressed_no_signal(layout.show_joystick)
	save_status.text = ""

func close() -> void:
	if editor.visible:
		cancel_editor()
	overlay.hide()
	pause_gate.release(self)

func open_update() -> void:
	var updater := get_parent().get_node_or_null("UpdateManager")
	if updater:
		# Acquire updater's lease BEFORE releasing ours.
		updater._check_for_update()
		close()

func _toggle_joystick(value: bool) -> void:
	layout.show_joystick = value
	var err: Error = layout.save_settings()
	save_status.text = "" if err == OK else "保存失败，请重试"
	_refresh_hud()

func open_editor() -> void:
	snapshot = layout.controls.duplicate(true)
	old_show = layout.show_joystick
	menu.hide()
	editor.show()
	dragging = false
	_select(selected)
	_layout_handles()

func _select(id: String) -> void:
	selected = id
	selection.text = LABELS[id] + " · 拖动位置 / 调整大小"
	slider.set_value_no_signal(layout.controls[id].scale)
	for key in handles:
		handles[key].modulate = Color(1, 0.85, 0.35) if key == id else Color.WHITE

func _handle_input(event: InputEvent, id: String) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not dragging:
			_begin_drag(id, event.index, handles[id].position + event.position)
		elif event.index == pointer and not event.pressed:
			dragging = false
	elif event is InputEventScreenDrag and dragging and event.index == pointer:
		_drag_to(handles[id].position + event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not dragging:
			_begin_drag(id, -1, handles[id].position + event.position)
		elif pointer == -1 and not event.pressed:
			dragging = false
	elif event is InputEventMouseMotion and dragging and pointer == -1:
		_drag_to(handles[id].position + event.position)
	handles[id].accept_event()

func _begin_drag(id: String, index: int, pos: Vector2) -> void:
	_select(id)
	pointer = index
	dragging = true
	drag_offset = handles[id].position + handles[id].size * 0.5 - pos

func _drag_to(pos: Vector2) -> void:
	layout.set_center(selected, pos + drag_offset, get_viewport().get_visible_rect().size)
	_layout_handles()

func _input(event: InputEvent) -> void:
	# Global release even if the finger ends outside its handle or another GUI consumes it.
	if event is InputEventScreenTouch and not event.pressed and event.index == pointer:
		dragging = false
	elif event is InputEventMouseButton and not event.pressed and pointer == -1:
		dragging = false

func _resize_selected(value: float) -> void:
	layout.controls[selected].scale = value
	_layout_handles()

func _layout_handles() -> void:
	var vp := get_viewport().get_visible_rect().size
	for id in handles:
		var rect: Rect2 = layout.rect_for(id, vp)
		handles[id].size = rect.size
		handles[id].position = rect.position

func _process(_delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if editor.visible and vp != last_size:
		last_size = vp
		_layout_handles()

func restore_defaults() -> void:
	layout.reset()
	_select(selected)
	_layout_handles()

func save_editor() -> void:
	if layout.save_settings() != OK:
		selection.text = "保存失败，请重试"
		return
	dragging = false
	editor.hide()
	menu.show()
	joystick_toggle.set_pressed_no_signal(layout.show_joystick)
	_refresh_hud()

func cancel_editor() -> void:
	layout.controls = snapshot.duplicate(true)
	layout.show_joystick = old_show
	dragging = false
	editor.hide()
	menu.show()

func _refresh_hud() -> void:
	var hud := get_parent().get_node_or_null("HUD")
	if hud:
		hud._layout()
