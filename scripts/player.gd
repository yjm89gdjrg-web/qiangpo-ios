extends CharacterBody3D

## FPS 玩家控制器 —— 触屏专用 + 键鼠调试
## 手感参数参考经典 FPS，可在此微调

const SPEED = 5.5
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENS = 0.0022
const TOUCH_SENS = 0.005
const GRAVITY = 9.8

# 武器表
const WEAPONS := [
	{"name": "ak47",      "label": "AK47",      "dmg": 38, "rate": 0.10, "kick": 0.014, "spread": 0.010, "ammo": 30},
	{"name": "m4",        "label": "M4A1",      "dmg": 32, "rate": 0.085,"kick": 0.010, "spread": 0.008, "ammo": 30},
	{"name": "dragunov",  "label": "德拉贡诺夫", "dmg": 95, "rate": 1.20, "kick": 0.035, "spread": 0.002, "ammo": 10},
	{"name": "mosin9130", "label": "莫辛纳甘",   "dmg": 110,"rate": 1.50, "kick": 0.040, "spread": 0.002, "ammo": 5},
	{"name": "l85",       "label": "L85A2",     "dmg": 34, "rate": 0.095,"kick": 0.011, "spread": 0.009, "ammo": 30},
	{"name": "g3a3",      "label": "G3A3",      "dmg": 44, "rate": 0.14, "kick": 0.018, "spread": 0.011, "ammo": 20},
	{"name": "m1911",     "label": "M1911",     "dmg": 45, "rate": 0.22, "kick": 0.020, "spread": 0.012, "ammo": 7},
]

var yaw := 0.0
var pitch := 0.0
var recoil := 0.0
var fire_timer := 0.0
var hp := 100
var armor := 100
var ammo := 30
var kills := 0
var deaths := 0
var weapon_idx := 0
var reloading := false
var hit_marker := 0.0        # 命中提示剩余时间（HUD 画叉）
var gun_kick := 0.0          # 枪身回坐动画
var gun_base := Vector3.ZERO # WeaponRoot 原始位置

var move_touch_id := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var look_touch_id := -1
var look_last := Vector2.ZERO
var fire_touch_id := -1
var hud_firing: bool = false

var round_manager: Node
var move_region := Rect2()
var mouse_firing := false
const Audio = preload("res://scripts/hot_update/audio_manager.gd")
var sfx = Audio.new()
const FX = preload("res://scripts/fx.gd")
var arms: Node3D
var muzzle_local := Vector3(0.25, -0.20, -1.13)  # 枪口在相机空间的近似位置

@onready var head := $Head
@onready var camera := $Head/Camera3D
@onready var weapon_root := $Head/Camera3D/WeaponRoot

func _ready() -> void:
	sfx.attach(self)
	_apply_weapon()
	_attach_arms()
	gun_base = weapon_root.position
	# 触屏优先：不锁定鼠标，避免手机上一开局就乱转
	if OS.has_feature("web") or OS.has_feature("editor"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	call_deferred("_link_round_manager")

func _attach_arms() -> void:
	# 第一人称持枪手臂（只显示给本地玩家）
	var packed: PackedScene = load("res://scenes/primitives/fps_arms.tscn")
	if packed == null:
		return
	arms = packed.instantiate() as Node3D
	if arms == null:
		return
	arms.name = "Arms"
	camera.add_child(arms)
	arms.position = Vector3.ZERO

func _link_round_manager() -> void:
	round_manager = get_tree().current_scene.get_node_or_null("RoundManager")

func _cur() -> Dictionary:
	return WEAPONS[weapon_idx]

func _apply_weapon() -> void:
	for i in range(weapon_root.get_child_count()):
		var c := weapon_root.get_child(i)
		if c is Node3D:
			c.visible = (i == weapon_idx)
	ammo = _cur()["ammo"]
	reloading = false

func _switch_weapon(idx: int) -> void:
	if idx < 0 or idx >= WEAPONS.size() or idx == weapon_idx:
		return
	weapon_idx = idx
	_apply_weapon()
	sfx.play("switch", -6.0)

func reset_mobile_input() -> void:
	move_touch_id = -1
	look_touch_id = -1
	fire_touch_id = -1
	move_vec = Vector2.ZERO
	hud_firing = false
	mouse_firing = false

func _input(event: InputEvent) -> void:
	# Releases must work even over GUI; only starts belong in unhandled input.
	if event is InputEventScreenTouch and not event.pressed:
		if event.index == move_touch_id:
			move_touch_id = -1
			move_vec = Vector2.ZERO
		if event.index == look_touch_id:
			look_touch_id = -1
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse_firing = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_mobile_input()

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_firing = event.pressed
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch -= event.relative.y * MOUSE_SENS
		pitch = clamp(pitch, -1.4, 1.4)
		rotation.y = yaw
		head.rotation.x = pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_7:
			_switch_weapon(k - KEY_1)
		elif k == KEY_R:
			_reload()
		elif k == KEY_E and round_manager:
			if round_manager.bomb_planted:
				round_manager.try_defuse()
			else:
				round_manager.try_plant()
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		var vp: Vector2 = get_viewport().get_visible_rect().size
		if t.pressed:
			# 左下 42% 区域 = 移动摇杆
			if move_region.has_point(t.position) and move_touch_id == -1:
				move_touch_id = t.index
				move_origin = t.position
				move_vec = Vector2.ZERO
			# 右下区域 = 瞄准转视角
			elif t.position.x > vp.x * 0.55 and look_touch_id == -1:
				look_touch_id = t.index
				look_last = t.position
		else:
			if t.index == move_touch_id:
				move_touch_id = -1
				move_vec = Vector2.ZERO
			elif t.index == look_touch_id:
				look_touch_id = -1
			elif t.index == fire_touch_id:
				fire_touch_id = -1
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		if d.index == move_touch_id:
			var v: Vector2 = d.position - move_origin
			var m: float = v.length()
			var radius := maxf(20.0, move_region.size.x * 0.3)
			if m > radius:
				v = v / m * radius
			move_vec = v / radius
		elif d.index == look_touch_id:
			var rel: Vector2 = d.position - look_last
			look_last = d.position
			yaw -= rel.x * TOUCH_SENS
			pitch -= rel.y * TOUCH_SENS
			pitch = clamp(pitch, -1.4, 1.4)
			rotation.y = yaw
			head.rotation.x = pitch

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var ix := Input.get_axis("move_left", "move_right")
	var iz := Input.get_axis("move_forward", "move_back")
	if move_touch_id != -1:
		ix += move_vec.x
		iz += move_vec.y
	var input_dir := Vector2(ix, iz)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		sfx.play("jump", -10.0)

	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if dir:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

	fire_timer -= delta
	var want_fire := (mouse_firing and not OS.has_feature("mobile")) or hud_firing
	if want_fire and fire_timer <= 0.0 and ammo > 0 and not reloading:
		_fire()

	recoil = move_toward(recoil, 0.0, 6.0 * delta * 0.05)
	head.rotation.x = pitch + recoil
	if gun_kick > 0.0:
		gun_kick = move_toward(gun_kick, 0.0, 1.2 * delta)
	if weapon_root:
		weapon_root.position = gun_base + Vector3(0, gun_kick * 0.12, gun_kick * 0.55)
	if hit_marker > 0.0:
		hit_marker = max(hit_marker - delta, 0.0)

func _fire() -> void:
	if get_tree().paused:
		return
	var w := _cur()
	fire_timer = w["rate"]
	ammo -= 1
	recoil += w["kick"]
	gun_kick = min(gun_kick + 0.06, 0.12)
	sfx.play("fire", -8.0)

	var cam_xform: Transform3D = camera.global_transform
	var muzzle_pos: Vector3 = cam_xform * muzzle_local
	var forward: Vector3 = -cam_xform.basis.z

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_transform.origin
	var sp: float = w["spread"]
	var spread_v: Vector3 = Vector3(randf_range(-sp, sp), randf_range(-sp, sp), 0.0)
	var dir: Vector3 = forward + spread_v
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * 200.0)
	query.exclude = [self]

	var result: Dictionary = space.intersect_ray(query)
	var end_pos: Vector3 = origin + dir.normalized() * 200.0
	if not result.is_empty():
		end_pos = result.position as Vector3
		var hit: Node = result.collider as Node
		if hit and hit.is_in_group("enemy"):
			hit.take_damage(int(w["dmg"]))
			sfx.play("hit", -6.0)
			hit_marker = 0.12
			if hit.hp <= 0:
				kills += 1
				_notify_kill("敌人")
		var n: Vector3 = result.get("normal", Vector3.UP) as Vector3
		FX.impact(self, result.position as Vector3, n)

	# 枪口火光 + 曳光弹 + 抛壳
	FX.muzzle_flash(self, muzzle_pos, forward, 1.0)
	FX.tracer(self, muzzle_pos, end_pos)
	FX.shell(self, cam_xform * Vector3(0.30, -0.12, -0.55), cam_xform.basis.x)

	if ammo <= 0:
		_reload()

func _reload() -> void:
	if reloading:
		return
	reloading = true
	sfx.play("reload", -6.0)
	await get_tree().create_timer(1.4, false).timeout
	ammo = _cur()["ammo"]
	reloading = false

func _spawn_impact(pos: Vector3) -> void:
	var m: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	m.mesh = sphere
	get_tree().current_scene.add_child(m)
	m.global_position = pos
	await get_tree().create_timer(0.25, false).timeout
	m.queue_free()

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	# 护甲优先吸收 60% 伤害（CF 风格）
	if armor > 0:
		var absorbed: int = int(amount * 0.6)
		absorbed = min(absorbed, armor)
		armor -= absorbed
		amount -= absorbed
	hp -= amount
	if hp <= 0:
		hp = 0
		sfx.play("die")
		_notify_kill("你（被击杀）")
		get_tree().call_deferred("reload_current_scene")

func heal_full() -> void:
	hp = 100
	armor = 100

func _notify_kill(victim: String) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var hud: Node = scene.get_node_or_null("HUD")
	if hud and hud.has_method("add_kill_feed"):
		hud.call("add_kill_feed", "你  ➤  " + victim)

func get_hud_text() -> String:
	var w := _cur()
	var base := "HP %d   KILLS %d   [%s] %d/%d" % [hp, kills, w["label"], ammo, w["ammo"]]
	if reloading:
		base += "   装弹中…"
	if round_manager:
		base += "\n爆破：" + round_manager.get_status()
	return base
