extends SceneTree

# Loads every first-person weapon scene, instantiates it, and verifies that the
# root name and part count are sane. Prints one PASS/FAIL line per weapon and a
# final summary line: "WEAPONS: N failure(s)".

const MIN_PARTS := 28

func _init() -> void:
	var weapons := [
		"ak47",
		"m4",
		"dragunov",
		"mosin9130",
		"l85",
		"g3a3",
		"m1911",
	]
	var failures := 0
	for key in weapons:
		var path := "res://scenes/primitives/%s.tscn" % key
		var scene: PackedScene = load(path)
		if scene == null:
			print("FAIL %s: could not load %s" % [key, path])
			failures += 1
			continue
		var inst: Node = scene.instantiate()
		if inst == null:
			print("FAIL %s: could not instantiate %s" % [key, path])
			failures += 1
			continue
		if inst.name != key:
			print("FAIL %s: root node name is '%s' (expected '%s')" % [key, inst.name, key])
			failures += 1
			inst.free()
			continue
		var parts := inst.get_child_count()
		if parts < MIN_PARTS:
			print("FAIL %s: only %d parts (expected >= %d)" % [key, parts, MIN_PARTS])
			failures += 1
			inst.free()
			continue
		print("PASS %s: root=%s parts=%d" % [key, inst.name, parts])
		inst.free()
	print("WEAPONS: %d failure(s)" % failures)
	quit()
