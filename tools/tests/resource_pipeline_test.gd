extends SceneTree
const Store = preload("res://scripts/hot_update/resource_store.gd")
const Client = preload("res://scripts/hot_update/resource_client.gd")

# Test-only transport adapter. Production URL validation/HTTPRequest/install remain
# intact; localhost TLS is verified using a temporary explicitly trusted test CA.
class FixtureClient extends "res://scripts/hot_update/resource_client.gd":
	func _request_url(url: String) -> Error:
		var cert := X509Certificate.new()
		if cert.load(OS.get_environment("PATCH_TEST_CERT")) != OK:
			return ERR_CANT_OPEN
		request.set_tls_options(TLSOptions.client(cert))
		var file := url.get_file()
		return request.request(OS.get_environment("PATCH_TEST_SERVER") + "/" + file)

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, label: String) -> bool:
	if not condition:
		push_error("FAIL " + label)
		quit(1)
		return false
	print("PASS ", label)
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() else "download"
	var store = Store.new()
	var fixture := OS.get_environment("PATCH_TEST_DIR")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture + "/resources.json"))
	if mode == "download":
		if not require(not store.activate(), "clean user sandbox; built-in resources"):
			return
		var boot := load("res://scenes/boot.tscn") as PackedScene
		root.add_child(boot.instantiate())
		for i in range(8):
			await process_frame
		if not require(current_scene.get_meta("active_resource_revision", -1) == 0, "live game starts with built-in map"):
			return
		var client := FixtureClient.new()
		root.add_child(client)
		client.check()
		var checked: Array = await client.manifest_checked
		if not require(str(checked[1]).is_empty() and int(checked[0].revision) == 7, "HTTPS manifest download with CA validation"):
			return
		var progressed := [false]
		client.download_progress.connect(func(_a, _b): progressed[0] = true)
		client.download(checked[0])
		var installed: Array = await client.patch_installed
		if not require(installed[0], "HTTPS ZIP download -> size/SHA256 -> atomic install: " + str(installed[1])):
			return
		if not require(progressed[0], "download progress emitted"):
			return
		var live := root.get_node_or_null("Main")
		if not require(live != null and not live.has_node("HotPatchGeometry") and live.get_meta("active_resource_revision", -1) == 0, "install does not mutate running game"):
			return
		quit(0)
		return
	if mode == "boot" or mode == "fallback" or mode == "previous":
		var boot := load("res://scenes/boot.tscn") as PackedScene
		root.add_child(boot.instantiate())
		for i in range(8):
			await process_frame
		var scene := current_scene as Node3D
		if not require(scene != null and scene.name == "Main", "next process boots main only after activation"):
			return
		var revision := int(scene.get_meta("active_resource_revision", 0))
		if mode == "fallback":
			if not require(revision == 0 and not scene.has_node("HotPatchGeometry"), "corrupt installed ZIP falls back to built-in map"):
				return
		else:
			var expected := 7 if mode == "boot" else 8
			if not require(revision == expected, "persistent resource revision r%d" % expected):
				return
			var ground := scene.get_node("Ground/Mesh") as MeshInstance3D
			var material := ground.material_override as StandardMaterial3D
			if not require(material != null and material.albedo_color.is_equal_approx(Color(0.08, 0.25, 0.85, 1)), "modified map visible: blue ground material"):
				return
			if not require(scene.get_node("HotPatchGeometry").get_child_count() == 1 and scene.get_node("HotPatchGeometry").get_child(0).get_child(1) is CollisionShape3D, "new purple obstacle mesh and collision present"):
				return
			if mode == "boot":
				var ground_texture := material.albedo_texture
				if not require(ground_texture != null and ground_texture.get_width() == 2, "runtime PNG loaded without editor import/cache"):
					return
				var ui: Node = scene.get_node("UpdateManager")
				var production_client: Node = ui.client
				production_client.queue_free()
				var local_client := FixtureClient.new()
				ui.add_child(local_client)
				ui.client = local_client
				ui.call("_check_for_update")
				if not require(scene.get_node("Player").process_mode == Node.PROCESS_MODE_DISABLED, "consent UI blocks gameplay input"):
					return
				ui.client.request.cancel_request()
				ui.call("_close")
				if not require(scene.get_node("Player").process_mode == Node.PROCESS_MODE_INHERIT, "closing consent UI restores gameplay"):
					return
				ui.call("_apply_resources")
				for i in range(8):
					await process_frame
				if not require(current_scene.get_meta("resource_revision", 0) == 7, "reload boot applies patch without restarting executable"):
					return
		quit(0)
		return
	if mode == "negative":
		var base := fixture + "/resources-r7.zip"
		var old_state := FileAccess.get_file_as_string(Store.ROOT + "/active.json")
		for field in ["size", "sha256", "min_app", "max_app", "url", "format"]:
			var bad := manifest.duplicate(true)
			match field:
				"size": bad.size = int(manifest.size) + 1
				"sha256": bad.sha256 = "0".repeat(64)
				"min_app": bad.min_app = "1.2.3"
				"max_app": bad.max_app = "1.2.1"
				"url": bad.url = "https://raw.githubusercontent.com.attacker.test/evil.zip"
				"format": bad.format = "pck"
			if not require(not store.install(base, bad), "reject " + field + ": " + store.last_error):
				return
		for url in ["http://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/a.zip", "https://123.207.197.63/a.zip", "https://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/../scripts/a.gd", "https://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/%2e%2e/a.zip"]:
			if not require(not store.trusted_url(url), "reject untrusted URL"):
				return
		for name in ["script", "traversal", "deflate", "duplicate", "scene", "symlink", "central", "badmap", "hugepng", "truncated"]:
			var path: String = fixture + "/bad-" + name + ".zip"
			var bad := manifest.duplicate(true)
			bad.size = FileAccess.get_file_as_bytes(path).size()
			bad.sha256 = FileAccess.get_sha256(path)
			if not require(not store.install(path, bad), "reject malicious archive " + name + ": " + store.last_error):
				return
		if not require(FileAccess.get_file_as_string(Store.ROOT + "/active.json") == old_state, "all failures preserve active pointer"):
			return
		var client := FixtureClient.new()
		root.add_child(client)
		var bad := manifest.duplicate(true)
		bad.sha256 = "0".repeat(64)
		client.download(bad)
		var failed: Array = await client.patch_installed
		if not require(not failed[0], "HTTPS download rejects wrong SHA before switching active resource"):
			return
		for name in ["redirect.zip", "missing.zip"]:
			bad = manifest.duplicate(true)
			bad.url = "https://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/" + name
			client.download(bad)
			failed = await client.patch_installed
			if not require(not failed[0], "reject network response " + name):
				return
		if not require(FileAccess.get_file_as_string(Store.ROOT + "/active.json") == old_state, "network failures preserve active pointer"):
			return
		# An incomplete staging file must never affect boot.
		var f := FileAccess.open(Store.ROOT + "/download.zip.part", FileAccess.WRITE)
		f.store_string("interrupted")
		f.close()
		if not require(store.activate() and int(store.active_manifest.revision) == 7, "interrupted download ignored at boot"):
			return
		quit(0)
		return
	if mode == "install_next":
		for revision in [8, 9]:
			var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture + "/manifest-r%d.json" % revision))
			if not require(store.install(fixture + "/resources-r%d.zip" % revision, m), "stage resource r%d" % revision):
				return
		quit(0)
		return
	push_error("unknown mode")
	quit(1)
