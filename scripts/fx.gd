extends RefCounted
## 程序化战斗特效：枪口火光 / 曳光弹 / 命中火花 / 爆炸 / 弹壳
## 全部运行时生成，无需外部资源；由 player / round_manager / bot 调用。

const TRACER_TIME := 0.07
const FLASH_TIME := 0.05
const SPARK_TIME := 0.35
const SHELL_TIME := 1.2

static func _host(node: Node) -> Node:
	# Prefer the current scene so effects live in world space.
	var scene: Node = node.get_tree().current_scene
	return scene if scene != null else node

static func muzzle_flash(node: Node, at: Vector3, dir: Vector3, scale: float = 1.0) -> void:
	var host := _host(node)
	var holder := Node3D.new()
	host.add_child(holder)
	holder.global_position = at
	if dir.length_squared() > 0.0001:
		holder.look_at(at + dir.normalized(), Vector3.UP)

	# Bright cone-ish flash made of two crossed quads via PrismMesh + Sphere core.
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055 * scale
	sphere.height = 0.11 * scale
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.86, 0.45, 0.95)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.72, 0.25)
	core_mat.emission_energy_multiplier = 6.0
	core.mesh = sphere
	core.material_override = core_mat
	holder.add_child(core)

	var petal := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.16 * scale, 0.16 * scale, 0.16 * scale)
	var petal_mat := StandardMaterial3D.new()
	petal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	petal_mat.albedo_color = Color(1.0, 0.9, 0.55, 0.85)
	petal_mat.emission_enabled = true
	petal_mat.emission = Color(1.0, 0.8, 0.35)
	petal_mat.emission_energy_multiplier = 5.0
	petal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	petal.mesh = prism
	petal.material_override = petal_mat
	petal.rotation = Vector3(1.570796, 0, 0)
	holder.add_child(petal)

	# Short-lived light for a real flash on nearby geometry.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 3.2 * scale
	light.omni_range = 3.5 * scale
	holder.add_child(light)

	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector3.ONE * 0.4, FLASH_TIME)
	tw.tween_callback(holder.queue_free)

static func tracer(node: Node, from: Vector3, to: Vector3) -> void:
	var host := _host(node)
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	var dist: float = from.distance_to(to)
	box.size = Vector3(0.02, 0.02, maxf(dist, 0.1))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.6, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 4.0
	line.mesh = box
	line.material_override = mat
	host.add_child(line)
	line.global_position = (from + to) * 0.5
	if dist > 0.01:
		line.look_at(to, Vector3.UP)
	# BoxMesh length is on Z; look_at aligns -Z to target, so rotate to center.
	var tw := line.create_tween()
	tw.tween_property(line, "scale", Vector3(0.2, 0.2, 1.0), TRACER_TIME)
	tw.tween_callback(line.queue_free)

static func impact(node: Node, at: Vector3, normal: Vector3 = Vector3.UP) -> void:
	var host := _host(node)
	var holder := Node3D.new()
	host.add_child(holder)
	holder.global_position = at
	if normal.length_squared() > 0.0001:
		holder.look_at(at + normal, Vector3.UP)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.78, 0.35, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 3.0

	# Burst of small sparks + a puff.
	for i in 6:
		var spark := MeshInstance3D.new()
		var s := BoxMesh.new()
		var len := 0.03 + randf() * 0.05
		s.size = Vector3(0.012, 0.012, len)
		spark.mesh = s
		spark.material_override = mat
		holder.add_child(spark)
		var dir := Vector3(randf_range(-0.6, 0.6), randf_range(0.1, 0.9), randf_range(0.2, 0.8)).normalized()
		var start := Vector3.ZERO
		var end := dir * (0.25 + randf() * 0.35)
		spark.position = start
		spark.look_at(end, Vector3.UP)
		var tw := spark.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "position", end, SPARK_TIME)
		tw.tween_property(spark, "scale", Vector3(0.1, 0.1, 0.1), SPARK_TIME)

	var puff := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.05
	sph.height = 0.1
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.albedo_color = Color(0.75, 0.73, 0.68, 0.55)
	puff.mesh = sph
	puff.material_override = puff_mat
	holder.add_child(puff)
	var tw2 := puff.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(puff, "scale", Vector3(3.0, 3.0, 3.0), SPARK_TIME)
	tw2.tween_property(puff, "transparency", 1.0, SPARK_TIME)

	var kill := holder.create_tween()
	kill.tween_interval(SPARK_TIME + 0.05)
	kill.tween_callback(holder.queue_free)

static func explosion(node: Node, at: Vector3) -> void:
	var host := _host(node)
	var holder := Node3D.new()
	host.add_child(holder)
	holder.global_position = at

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.62, 0.2, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.12)
	mat.emission_energy_multiplier = 8.0

	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.6
	sph.height = 1.2
	ball.mesh = sph
	ball.material_override = mat
	holder.add_child(ball)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 8.0
	light.omni_range = 14.0
	holder.add_child(light)

	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3(5.0, 5.0, 5.0), 0.55)
	tw.tween_property(ball, "transparency", 1.0, 0.55)
	tw.tween_property(light, "light_energy", 0.0, 0.55)
	tw.chain().tween_callback(holder.queue_free)

static func shell(node: Node, at: Vector3, dir: Vector3) -> void:
	var host := _host(node)
	var shell_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = 0.03
	cyl.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.62, 0.28)
	mat.metallic = 0.9
	mat.roughness = 0.3
	shell_mesh.mesh = cyl
	shell_mesh.material_override = mat
	host.add_child(shell_mesh)
	shell_mesh.global_position = at
	var toss: Vector3 = dir.normalized() * 1.5 + Vector3(0, 1.6, 0)
	var tw := shell_mesh.create_tween()
	tw.set_parallel(true)
	tw.tween_property(shell_mesh, "global_position", at + toss * 0.5 + Vector3(0, -0.4, 0), SHELL_TIME)
	tw.tween_property(shell_mesh, "rotation", Vector3(randf() * 12.0, randf() * 12.0, randf() * 12.0), SHELL_TIME)
	tw.chain().tween_callback(shell_mesh.queue_free)
