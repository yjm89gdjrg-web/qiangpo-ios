extends CharacterBody3D

## AI 机器人 —— 直线追击 + 射程内开枪
## 不依赖导航网格，避免 NavigationServer 报错和机器人不动

const SPEED = 3.4
const CHASE_RANGE = 40.0
const ATTACK_RANGE = 22.0
const FIRE_RATE = 0.85
const DAMAGE = 9

var hp := 100
var fire_timer := 0.0
var target: Node3D = null

func _ready() -> void:
	add_to_group("enemy")
	call_deferred("_find_target")

func _find_target() -> void:
	target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		_find_target()
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var to_player: Vector3 = target.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

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
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		_face_target()
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

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
