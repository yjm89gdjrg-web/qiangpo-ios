extends Node
## One pause owner per overlay: settings -> updater handoff cannot unpause gameplay.
var owners: Array[Node] = []
var was_paused := false
var mouse_mode := Input.MOUSE_MODE_VISIBLE

static func for_scene(scene: Node) -> Node:
	var existing: Node = scene.get_meta("modal_pause_gate") if scene.has_meta("modal_pause_gate") else null
	if existing:
		return existing
	var gate := Node.new()
	gate.set_script(load("res://scripts/ui/modal_pause.gd"))
	gate.name = "ModalPause"
	gate.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.set_meta("modal_pause_gate", gate)
	scene.add_child.call_deferred(gate)
	return gate

func acquire(owner: Node) -> void:
	if owner in owners:
		return
	if owners.is_empty():
		was_paused = get_tree().paused
		mouse_mode = Input.mouse_mode
		var player := get_parent().get_node_or_null("Player")
		if player and player.has_method("reset_mobile_input"):
			player.reset_mobile_input()
	owners.append(owner)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func release(owner: Node) -> void:
	if owner not in owners:
		return
	owners.erase(owner)
	if owners.is_empty():
		get_tree().paused = was_paused
		Input.mouse_mode = mouse_mode

func _exit_tree() -> void:
	if not owners.is_empty():
		get_tree().paused = was_paused
