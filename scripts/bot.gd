extends CharacterBody3D

## AI 机器人 —— 直线追击 + 简易避障 + 射程内开枪
## 不依赖导航网格，避免 NavigationServer 报错和机器人不动

const SPEED = 3.4
const CHASE_RANGE = 40.0
const ATTACK_RANGE = 22.0
const FIRE_RATE = 0.85
const DAMAGE = 9
const PROBE := 1.6
const AVOID_GROUPS := ["Structures", "Covers", "Props"]
## Corridor centres; bots route via the nearest one instead of grinding into blocks.
const WAYPOINTS := [
	Vector3(-21, 1, 20), Vector3(-21, 1, 8), Vector3(-21, 1, -6),
	Vector3(-21, 1, -18), Vector3(-18, 1, -24),
	Vector3(21, 1, 20), Vector3(21, 1, 8), Vector3(21, 1, -6),
	Vector3(21, 1, -18), Vector3(18, 1, -24),
	Vector3(0, 1, 26), Vector3(0, 1, 14), Vector3(0, 1, -22)
]

var hp := 100
var fire_timer := 0.0
var target: Node3D = null
var avoid_dir := Vector3.ZERO
var strafe := 1.0
var strafe_timer := 0.0
var stuck_time := 0.0
var last_pos := Vector3.ZERO
var obstacles: Array[Node] = []
var team := "CT"  # 队伍："T" 或 "CT"
var spawn_pos := Vector3.ZERO

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

func _physics_process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		_find_target()
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var to_player: Vector3 = target.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = 1.2 + randf() * 1.2
		strafe = 1.0 if randf() < 0.5 else -1.0

	if dist < ATTACK_RANGE:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_face_target()
		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_timer = FIRE_RATE
			_shoot_at_player()
	elif dist < CHASE_RANGE:
		var dir: Vector3 = to_player.normalized()
		var move := _avoid(dir)
		velocity.x = move.x * SPEED
		velocity.z = move.z * SPEED
		_face_target()
	else:
		var waypoint := _next_waypoint()
		if waypoint != Vector3.ZERO:
			var wdir: Vector3 = waypoint - global_position
			wdir.y = 0.0
			if wdir.length() > 1.2:
				var wmove := _avoid(wdir.normalized())
				velocity.x = wmove.x * SPEED
				velocity.z = wmove.z * SPEED
				_face_direction(wmove)
				move_and_slide()
				_track_stuck(delta)
				return
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	_track_stuck(delta)

func _next_waypoint() -> Vector3:
	if not target or not is_instance_valid(target):
		return Vector3.ZERO
	var goal: Vector3 = target.global_position
	# If the straight line is already clear, just go straight - never detour.
	if _clear_line(global_position, goal):
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_cost := INF
	var direct: float = global_position.distance_to(goal)
	for wp in WAYPOINTS:
		var to_bot: float = global_position.distance_to(wp)
		var to_goal: float = wp.distance_to(goal)
		if to_bot < 2.0 or to_goal >= direct - 1.0:
			continue
		if not _clear_line(global_position, wp):
			continue
		var cost: float = to_bot + to_goal
		if cost < best_cost:
			best_cost = cost
			best = wp
	return best

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
			if abs(point.x - center.x) < half.x + 0.8 and abs(point.z - center.z) < half.z + 0.8:
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
	if stuck_time > 0.7:
		strafe = -strafe
		strafe_timer = 1.5
		stuck_time = 0.0

func _avoid(dir: Vector3) -> Vector3:
	# If a blocker sits ahead, slide sideways along the clearer side.
	var ahead := global_position + dir * PROBE
	var blocked := false
	for mesh in obstacles:
		if not is_instance_valid(mesh):
			continue
		var half: Vector3 = _half_extents(mesh)
		var center: Vector3 = mesh.global_position
		if abs(ahead.x - center.x) < half.x + 0.6 and abs(ahead.z - center.z) < half.z + 0.6:
			blocked = true
			break
	if not blocked:
		return dir
	var side := Vector3(-dir.z, 0, dir.x) * strafe
	var probe_side := global_position + side * PROBE
	for mesh2 in obstacles:
		if not is_instance_valid(mesh2):
			continue
		var h2: Vector3 = _half_extents(mesh2)
		var c2: Vector3 = mesh2.global_position
		if abs(probe_side.x - c2.x) < h2.x + 0.6 and abs(probe_side.z - c2.z) < h2.z + 0.6:
			return (side * -1.0).normalized()
	return side.normalized()

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
	if not hit.is_empty() and hit.get("collider") == target and target.has_method("take_damage"):
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
	# 重新寻找目标
	call_deferred("_find_target")
