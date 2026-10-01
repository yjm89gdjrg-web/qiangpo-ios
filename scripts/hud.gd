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
	_layout()
	call_deferred("_link")

func _link() -> void:
	var scene := get_tree().current_scene
	player = scene.get_node_or_null("Player")
	round_manager = scene.get_node_or_null("RoundManager")

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	var bw: float = clamp(vp.x * 0.16, 110.0, 190.0)
	var bh: float = clamp(vp.y * 0.16, 70.0, 120.0)
	var margin: float = 18.0
	var right_x: float = vp.x - bw - margin

	if status:
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.position = Vector2(margin, margin)
		status.size = Vector2(vp.x * 0.62, bh * 1.6)
		status.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.035, 18.0, 34.0)))
	if action_button:
		action_button.size = Vector2(bw, bh)
		action_button.position = Vector2(right_x, vp.y - bh - margin)
		action_button.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.03, 16.0, 28.0)))
	if weapon_button:
		weapon_button.text = "换枪"
		weapon_button.size = Vector2(bw, bh)
		weapon_button.position = Vector2(right_x - bw - margin, vp.y - bh - margin)
		weapon_button.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.03, 16.0, 28.0)))
	if jump_button:
		jump_button.text = "跳跃"
		jump_button.size = Vector2(bw, bh)
		jump_button.position = Vector2(right_x, vp.y - bh * 2 - margin * 2)
		jump_button.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.03, 16.0, 28.0)))
	if fire_button:
		fire_button.text = "开火"
		fire_button.size = Vector2(bw * 1.2, bh * 1.2)
		fire_button.position = Vector2(right_x - bw * 0.2, vp.y - bh * 3 - margin * 3)
		fire_button.add_theme_font_size_override("font_size", int(clamp(vp.y * 0.03, 16.0, 28.0)))

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
	if not round_manager:
		return
	if round_manager.bomb_planted:
		round_manager.try_defuse()
	else:
		round_manager.try_plant()

func _on_switch() -> void:
	if player and player.has_method("_switch_weapon"):
		player.call("_switch_weapon", (player.weapon_idx + 1) % player.WEAPONS.size())

func _on_jump() -> void:
	if player and player.is_on_floor():
		player.velocity.y = player.JUMP_VELOCITY

func _on_fire_down() -> void:
	if is_instance_valid(player):
		player.hud_firing = true

func _on_fire_up() -> void:
	if is_instance_valid(player):
		player.hud_firing = false
