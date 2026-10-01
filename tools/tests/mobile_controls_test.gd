extends SceneTree
const Layout = preload("res://scripts/ui/control_layout.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func buttons_named(node: Node, text: String) -> int:
	var count := 1 if node is Button and node.text == text else 0
	for child in node.get_children():
		count += buttons_named(child, text)
	return count

func run() -> void:
	var layout = Layout.new()
	var path := "user://mobile_controls_test.cfg"
	var args := OS.get_cmdline_user_args()
	if args.size() and args[0] == "write":
		layout.controls.fire.center = Vector2(0.31, 0.42)
		layout.controls.fire.scale = 1.55
		layout.show_joystick = false
		check(layout.save_settings(path) == OK, "write restart fixture")
		quit(failures)
		return
	if args.size() and args[0] == "read":
		layout.load_settings(path)
		check(layout.controls.fire.center == Vector2(0.31, 0.42) and layout.controls.fire.scale == 1.55 and not layout.show_joystick, "persisted layout survives a separate engine process")
		DirAccess.remove_absolute(path)
		quit(failures)
		return
	layout.controls.fire.center = Vector2(0.31, 0.42)
	layout.controls.fire.scale = 1.55
	layout.show_joystick = false
	check(layout.save_settings(path) == OK, "save normalized position, selected size, visibility")
	var restored = Layout.new()
	restored.load_settings(path)
	check(restored.controls.fire.center == Vector2(0.31, 0.42) and restored.controls.fire.scale == 1.55 and not restored.show_joystick, "fresh settings instance restores persisted layout")
	for vp in [Vector2(1280, 720), Vector2(844, 390), Vector2(640, 360)]:
		for id in Layout.IDS:
			restored.set_center(id, Vector2(-500, 9000), vp)
			var rect: Rect2 = restored.rect_for(id, vp)
			check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= vp.x + 0.01 and rect.end.y <= vp.y + 0.01, "%s clamped at %s" % [id, vp])
	restored.reset()
	check(restored.controls.fire.center == Vector2(0.91, 0.51) and restored.show_joystick, "restore defaults")
	DirAccess.remove_absolute(path)

	var home: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	await process_frame
	var settings: Node = home.get_node("Settings")
	var updater: Node = home.get_node("UpdateManager")
	check(home.find_child("SettingsButton", true, false) != null, "homepage settings entry")
	check(buttons_named(updater.ui_layer, "更新") == 0, "no floating header update shortcut")
	settings.open()
	settings.open_editor()
	check(paused and get_nodes_in_group("player").is_empty() and get_nodes_in_group("enemy").is_empty(), "home editor pauses and never loads gameplay")
	home._start()
	await process_frame
	check(current_scene == home, "start is blocked behind settings")
	settings.cancel_editor()
	# Exercise updater's real UI pause lease without a network request.
	updater._show()
	settings.close()
	check(paused and updater.overlay.visible, "settings -> update handoff remains paused")
	updater._close()
	check(not paused, "last overlay closing restores original pause state")
	paused = true
	settings.open()
	settings.close()
	check(paused, "pre-existing paused state preserved")
	paused = false
	home._start()
	await process_frame
	await process_frame
	await process_frame
	check(current_scene is Node3D, "home start still loads gameplay only on explicit start")
	var main := current_scene
	var player: Node = main.get_node("Player")
	var hud: Node = main.get_node("HUD")
	settings = main.get_node("Settings")
	updater = main.get_node("UpdateManager")
	check(hud.settings_button.text == "设置" and buttons_named(updater.ui_layer, "更新") == 0, "game settings entry; updater overlay preserved without shortcut")
	hud._on_fire_down()
	check(player.hud_firing, "fire callback starts firing")
	hud._on_fire_up()
	check(not player.hud_firing, "fire callback releases")
	var previous: int = player.weapon_idx
	hud._on_switch()
	check(player.weapon_idx != previous, "switch gameplay callback")
	# Let the character settle onto the actual floor, then exercise jump.
	player.position.y = 0.05
	for i in range(8):
		await physics_frame
	hud._on_jump()
	check(player.velocity.y == player.JUMP_VELOCITY, "jump gameplay callback on floor")
	# Place on the bomb site to exercise a successful plant callback.
	player.global_position = main.get_node("RoundManager").site_position
	hud._on_action()
	check(main.get_node("RoundManager").action_timer > 0, "plant gameplay callback")
	main.get_node("RoundManager")._process(3.0)
	player.move_touch_id = 4
	player.look_touch_id = 5
	player.move_vec = Vector2.ONE
	player.hud_firing = true
	settings.open()
	check(paused and not player.hud_firing and player.move_touch_id == -1 and player.look_touch_id == -1 and player.move_vec == Vector2.ZERO, "opening settings resets held GUI/touch input")
	var bomb_time: float = main.get_node("RoundManager").bomb_timer
	var player_pos: Vector3 = player.position
	for i in range(4):
		await process_frame
	check(main.get_node("RoundManager").bomb_timer == bomb_time and player.position == player_pos, "settings actually pauses simulation and round timer")
	settings.open_editor()
	previous = player.weapon_idx
	var ammo: int = player.ammo
	hud._on_fire_down()
	hud._on_switch()
	hud._on_action()
	hud._on_jump()
	player._fire()
	check(not player.hud_firing and player.weapon_idx == previous and player.ammo == ammo and main.get_node("RoundManager").bomb_planted, "editor suppresses fire/jump/switch/defuse callbacks")
	# Touch/mouse editor input uses real GUI callbacks, never gameplay buttons.
	var start: Vector2 = settings.layout.controls.fire.center
	var press := InputEventScreenTouch.new()
	press.index = 6
	press.pressed = true
	press.position = Vector2(10, 10)
	settings._handle_input(press, "fire")
	var drag := InputEventScreenDrag.new()
	drag.index = 6
	drag.position = Vector2(60, 40)
	settings._handle_input(drag, "fire")
	check(settings.layout.controls.fire.center != start, "touch editor drag moves selected control")
	press.pressed = false
	settings._input(press)
	check(not settings.dragging, "editor release anywhere clears touch drag")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(8, 8)
	settings._handle_input(click, "jump")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(30, 40)
	var jump_start: Vector2 = settings.layout.controls.jump.center
	settings._handle_input(motion, "jump")
	check(settings.layout.controls.jump.center != jump_start, "mouse editor drag moves selected control")
	settings._resize_selected(1.7)
	check(settings.layout.controls.jump.scale == 1.7, "size slider adjusts selected control")
	settings.cancel_editor()
	check(settings.layout.controls.fire.center == start, "cancel rolls back editor draft")
	# Save via editor UI; a newly created settings object and HUD both see it.
	settings.open_editor()
	settings.layout.controls.jump.center = Vector2(0.55, 0.65)
	settings._resize_selected(1.4)
	settings.layout.controls.jump.scale = 1.4
	settings.save_editor()
	var saved = Layout.new()
	saved.load_settings()
	check(saved.controls.jump.center == Vector2(0.55, 0.65) and saved.controls.jump.scale == 1.4, "editor Save persists chosen control position and size")
	check(hud.layout.controls.jump.center == saved.controls.jump.center, "editor Save reapplies gameplay HUD")
	settings.open_editor()
	settings.restore_defaults()
	settings.save_editor()
	check(hud.layout.controls.jump.center == Vector2(0.91, 0.72), "restore defaults + Save reapplies gameplay")
	settings.close()
	check(not paused, "game resumes after settings/editor")
	hud._on_action()
	check(main.get_node("RoundManager").action_timer < 0, "defuse gameplay callback resumes")
	player.move_touch_id = 8
	player.move_vec = Vector2.ONE
	var release := InputEventScreenTouch.new()
	release.index = 8
	release.pressed = false
	player._input(release)
	check(player.move_touch_id == -1 and player.move_vec == Vector2.ZERO, "joystick release over GUI cannot stick")
	for vp in [Vector2i(1280, 720), Vector2i(844, 390)]:
		root.size = vp
		await process_frame
		hud._layout()
		for button in [hud.fire_button, hud.jump_button, hud.weapon_button, hud.action_button]:
			check(button.position.x >= 0 and button.position.y >= 0 and button.get_rect().end.x <= vp.x + 0.01 and button.get_rect().end.y <= vp.y + 0.01, "actual HUD %s onscreen at %s" % [button.name, vp])
		check(player.move_region == hud.layout.rect_for("move", Vector2(vp)), "player joystick follows viewport/layout at %s" % vp)
	# Hold the joystick with one finger while tapping action buttons with a second:
	# a Button's default mouse filter used to swallow that second touch.
	var move_down := InputEventScreenTouch.new()
	move_down.index = 21
	move_down.pressed = true
	move_down.position = player.move_region.get_center()
	player._unhandled_input(move_down)
	check(player.move_touch_id == 21, "second-finger test: joystick engaged")
	var before_weapon: int = player.weapon_idx
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = hud.weapon_button.get_rect().get_center()
	tap.index = 22
	hud.weapon_button.gui_input.emit(tap)
	check(player.weapon_idx != before_weapon, "switch works while joystick is held")
	var released := InputEventScreenTouch.new()
	released.pressed = false
	released.index = 22
	hud.weapon_button.gui_input.emit(released)
	player.velocity = Vector3.ZERO
	player.position.y = 0.05
	for i in range(8):
		await physics_frame
	var tap_jump := InputEventScreenTouch.new()
	tap_jump.pressed = true
	tap_jump.position = hud.jump_button.get_rect().get_center()
	tap_jump.index = 23
	hud.jump_button.gui_input.emit(tap_jump)
	check(player.velocity.y == player.JUMP_VELOCITY, "jump works while joystick is held")
	var jump_up := InputEventScreenTouch.new()
	jump_up.pressed = false
	jump_up.index = 23
	hud.jump_button.gui_input.emit(jump_up)
	var tap_plant := InputEventScreenTouch.new()
	tap_plant.pressed = true
	tap_plant.position = hud.action_button.get_rect().get_center()
	tap_plant.index = 24
	main.get_node("RoundManager").bomb_planted = false
	hud.action_button.gui_input.emit(tap_plant)
	check(main.get_node("RoundManager").action_timer > 0 or main.get_node("RoundManager").bomb_planted, "plant works while joystick is held")
	var plant_up := InputEventScreenTouch.new()
	plant_up.pressed = false
	plant_up.index = 24
	hud.action_button.gui_input.emit(plant_up)
	# Fire button keeps working too, and the joystick is still held throughout.
	var tap_fire := InputEventScreenTouch.new()
	tap_fire.pressed = true
	tap_fire.position = hud.fire_button.get_rect().get_center()
	tap_fire.index = 25
	hud.fire_button.gui_input.emit(tap_fire)
	check(player.hud_firing, "fire works while joystick is held")
	var fire_up := InputEventScreenTouch.new()
	fire_up.pressed = false
	fire_up.index = 25
	hud.fire_button.gui_input.emit(fire_up)
	check(not player.hud_firing, "fire releases")
	check(player.move_touch_id == 21, "joystick still held after all taps")
	var move_up := InputEventScreenTouch.new()
	move_up.pressed = false
	move_up.index = 21
	player._input(move_up)
	check(player.move_touch_id == -1, "joystick releases after taps")
	main.queue_free()
	await process_frame
	print("MOBILE CONTROLS: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
