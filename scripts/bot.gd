extends CharacterBody3D

## AI 机器人 —— 直线追击 + 简易避障 + 射程内开枪
## 不依赖导航网格，避免 NavigationServer 报错和机器人不动

const SPEED = 3.4
const CHASE_RANGE = 40.0
const ATTACK_RANGE = 22.0
const FIRE_RATE = 0.85
const DAMAGE = 9
const PROBE := 1.4
const AVOID_GROUPS := ["Structures", "Covers", "Props"]
## 网格 A* 寻路（确定性，避免在掩体后抖动）
const GRID_MIN := -31.0
const GRID_CELL := 2.0
const GRID_N := 31

var hp := 100
var fire_timer := 0.0
var target: Node3D = null
var avoid_dir := Vector3.ZERO
var strafe := 1.0
var strafe_timer := 0.0
var stuck_time := 0.0
var last_pos := Vector3.ZERO
var obstacles: Array[Node] = []
var blocked_cells: PackedByteArray = PackedByteArray()
var path: Array[Vector3] = []
var path_timer := 0.0
var team := "CT"  # 队伍："T" 或 "CT"
var spawn_pos := Vector3.ZERO
var anim: AnimationPlayer = null
const FX = preload("res://scripts/fx.gd")

func _ready() -> void:
	add_to_group("bot")
	if team == "CT":
		add_to_group("enemy")
	else:
		add_to_group("friendly")
	last_pos = global_position
	spawn_pos = global_position
	call_deferred("_find_target")
	call_deferred("_collect_obstacles")
	call_deferred("_setup_model")

func _setup_model() -> void:
	# 用真实士兵模型替代胶囊体：设置动画 + 按队伍染色
	var body: Node = get_node_or_null("Body")
	if body == null:
		return
	anim = _find_anim_player(body)
	if anim != null:
		anim.play("Idle")
	var tint := Color(1.0, 0.30, 0.26) if team == "CT" else Color(0.42, 0.66, 1.0)
	_tint_meshes(body, tint)

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var r: AnimationPlayer = _find_anim_player(c)
		if r != null:
			return r
	return null

func _tint_meshes(node: Node, tint: Color) -> void:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var src: Material = mesh.surface_get_material(s)
			var mat: StandardMaterial3D
			if src is StandardMaterial3D:
				mat = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			mat.albedo_color = mat.albedo_color.lerp(Color(tint.r, tint.g, tint.b, mat.albedo_color.a), 0.62)
			mi.set_surface_override_material(s, mat)

func _find_target() -> void:
	# 只攻击敌对队伍
	var target_group := "player" if team == "CT" else "enemy"
	var candidates := get_tree().get_nodes_in_group(target_group)
	if candidates.size() > 0:
		target = candidates[0]

func _collect_obstacles() -> void:
	# Blockers are axis-aligned boxes; treat each MeshInstance3D child as a slab.
	var scene: Node = get_tree().current_scene
	if scene == null:
		# Walk up to the scene root; bots may be added before current_scene is set.
		scene = self
		while scene.get_parent() != null and scene.get_parent() != get_tree().root:
			scene = scene.get_parent()
	if scene == null:
		return
	for group_name in AVOID_GROUPS:
		var container: Node = scene.get_node_or_null(group_name)
		if container == null:
			continue
		for child in container.get_children():
			var mesh: MeshInstance3D = child.get_node_or_null("Mesh") as MeshInstance3D
			if mesh != null:
				obstacles.append(mesh)
	for name in ["WallN", "WallS", "WallE", "WallW"]:
		var wall: Node = scene.get_node_or_null(name)
		if wall == null:
			continue
		var mesh2: MeshInstance3D = wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh2 != null:
			obstacles.append(mesh2)
	_build_blocked_grid()

func _build_blocked_grid() -> void:
	blocked_cells = PackedByteArray()
	blocked_cells.resize(GRID_N * GRID_N)
	for cz in range(GRID_N):
		for cx in range(GRID_N):
			var p := _center_of(Vector2i(cx, cz))
			blocked_cells[cz * GRID_N + cx] = 1 if _blocked_at(p) else 0

func _cell_of(p: Vector3) -> Vector2i:
	var cx := int(floor((p.x - GRID_MIN) / GRID_CELL))
	var cz := int(floor((p.z - GRID_MIN) / GRID_CELL))
	return Vector2i(clampi(cx, 0, GRID_N - 1), clampi(cz, 0, GRID_N - 1))

func _center_of(c: Vector2i) -> Vector3:
	return Vector3(GRID_MIN + (float(c.x) + 0.5) * GRID_CELL, 1.0, GRID_MIN + (float(c.y) + 0.5) * GRID_CELL)

func _cell_blocked(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= GRID_N or c.y >= GRID_N:
		return true
	if blocked_cells.size() != GRID_N * GRID_N:
		return _blocked_at(_center_of(c))
	return blocked_cells[c.y * GRID_N + c.x] == 1

func _compute_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var start := _cell_of(from)
	var goal := _cell_of(to)
	var pts: Array[Vector3] = []
	if start == goal:
		pts.append(to)
		return pts
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var open: Array[Vector2i] = [start]
	var came: Dictionary = {}
	var g: Dictionary = {start: 0.0}
	var f: Dictionary = {start: 0.0}
	var closed: Dictionary = {}
	var guard := 0
	while not open.is_empty() and guard < 4000:
		guard += 1
		var best_i := 0
		for i in range(open.size()):
			if float(f.get(open[i], INF)) < float(f.get(open[best_i], INF)):
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if cur == goal:
			break
		closed[cur] = true
		for d in dirs:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= GRID_N or nb.y >= GRID_N:
				continue
			if closed.has(nb) or _cell_blocked(nb):
				continue
			if d.x != 0 and d.y != 0:
				if _cell_blocked(Vector2i(cur.x + d.x, cur.y)) or _cell_blocked(Vector2i(cur.x, cur.y + d.y)):
					continue
			var step := 1.41421 if (d.x != 0 and d.y != 0) else 1.0
			var ng: float = float(g.get(cur, INF)) + step
			if ng < float(g.get(nb, INF)):
				g[nb] = ng
				came[nb] = cur
				f[nb] = ng + Vector2(float(nb.x - goal.x), float(nb.y - goal.y)).length()
				if not open.has(nb):
					open.append(nb)
	if not came.has(goal):
		return pts
	var cells: Array[Vector2i] = []
	var c: Vector2i = goal
	var guard2 := 0
	while c != start and came.has(c) and guard2 < 2000:
		cells.append(c)
		c = came[c]
		guard2 += 1
	cells.reverse()
	for cell in cells:
		pts.append(_center_of(cell))
	return pts

func _physics_process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		_find_target()
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var to_player: Vector3 = target.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	var line_clear: bool = _clear_line(global_position, target.global_position)

	path_timer -= delta
	if dist < ATTACK_RANGE and line_clear:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_face_target()
		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_timer = FIRE_RATE
			_shoot_at_player()
	else:
		# Route around geometry with grid A* when the direct line is blocked.
		var dest: Vector3 = target.global_position
		if not line_clear:
			if path_timer <= 0.0 or path.is_empty():
				path = _compute_path(global_position, target.global_position)
				path_timer = 0.5
			while path.size() > 0 and global_position.distance_to(path[0]) < 1.5:
				path.pop_front()
			if path.size() > 0:
				dest = path[0]
		var ddir: Vector3 = dest - global_position
		ddir.y = 0.0
		if ddir.length() > 0.6:
			var move: Vector3 = ddir.normalized()
			velocity.x = move.x * SPEED
			velocity.z = move.z * SPEED
			_face_direction(move)
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
		if line_clear:
			_face_target()
		fire_timer -= delta
		if dist < ATTACK_RANGE and line_clear and fire_timer <= 0.0:
			fire_timer = FIRE_RATE
			_shoot_at_player()

	move_and_slide()
	_track_stuck(delta)
	_update_anim()

func _update_anim() -> void:
	if anim == null:
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	var want := "Run" if planar > 0.6 else "Idle"
	if anim.current_animation != want and anim.has_animation(want):
		anim.play(want, 0.2)

func _clear_line(from: Vector3, to: Vector3) -> bool:
	var steps: int = int(from.distance_to(to) / 1.5)
	if steps < 1:
		return true
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var point: Vector3 = from.lerp(to, t)
		for mesh in obstacles:
			if not is_instance_valid(mesh):
				continue
			var half: Vector3 = _half_extents(mesh)
			var center: Vector3 = mesh.global_position
			if abs(point.x - center.x) < half.x + 0.5 and abs(point.z - center.z) < half.z + 0.5:
				return false
	return true

func _face_direction(dir: Vector3) -> void:
	if dir.length_squared() > 0.001:
		rotation.y = atan2(-dir.x, -dir.z)

func _track_stuck(delta: float) -> void:
	var moved: float = (global_position - last_pos).length()
	last_pos = global_position
	if moved < 0.04:
		stuck_time += delta
	else:
		stuck_time = 0.0
	if stuck_time > 1.5:
		# Stuck: force a fresh path on the next frame.
		path.clear()
		path_timer = 0.0
		stuck_time = 0.0

func _avoid(dir: Vector3, goal: Vector3 = Vector3.ZERO) -> Vector3:
	# If a blocker sits ahead, slide along the side that still makes progress.
	var ahead := global_position + dir * PROBE
	if not _blocked_at(ahead):
		return dir
	var side := Vector3(-dir.z, 0, dir.x)
	var left_free: bool = not _blocked_at(global_position + side * PROBE)
	var right_free: bool = not _blocked_at(global_position - side * PROBE)
	if left_free and not right_free:
		return side.normalized()
	if right_free and not left_free:
		return (-side).normalized()
	# Both sides open: commit to one consistent side so the bot walks around
	# the blocker instead of oscillating in front of it.
	return side.normalized()

func _blocked_at(point: Vector3) -> bool:
	for mesh in obstacles:
		if not is_instance_valid(mesh):
			continue
		var half: Vector3 = _half_extents(mesh)
		var center: Vector3 = mesh.global_position
		if abs(point.x - center.x) < half.x + 0.5 and abs(point.z - center.z) < half.z + 0.5:
			return true
	return false

func _half_extents(mesh: MeshInstance3D) -> Vector3:
	var aabb: AABB = mesh.get_aabb()
	return aabb.size * 0.5

func _face_target() -> void:
	var dir: Vector3 = target.global_position - global_position
	rotation.y = atan2(-dir.x, -dir.z)

func _shoot_at_player() -> void:
	var origin: Vector3 = global_position + Vector3(0, 1.4, 0)
	var destination: Vector3 = target.global_position + Vector3(0, 1.2, 0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, destination)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var muzzle: Vector3 = global_position + Vector3(0, 1.35, 0) - global_transform.basis.z * 0.4
	FX.muzzle_flash(self, muzzle, (destination - muzzle).normalized(), 0.8)
	if not hit.is_empty():
		FX.impact(self, hit.position as Vector3, hit.get("normal", Vector3.UP) as Vector3)
		if hit.get("collider") == target and target.has_method("take_damage"):
			target.take_damage(DAMAGE)

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()

func reset_for_round() -> void:
	# 回合重置：恢复血量、回到出生点
	hp = 100
	global_position = spawn_pos
	velocity = Vector3.ZERO
	fire_timer = 0.0
	stuck_time = 0.0
	last_pos = spawn_pos
	path.clear()
	path_timer = 0.0
	# 重新寻找目标
	call_deferred("_find_target")
