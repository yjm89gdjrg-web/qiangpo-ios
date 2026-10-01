extends RefCounted
## Restricted, non-executable resource ZIPs. Never mount untrusted PCK/scene/script files.
const APP_VERSION := "1.2.5"
const ROOT := "user://resource_updates"
const MAX_ARCHIVE := 32 * 1024 * 1024
const MAX_FILE := 8 * 1024 * 1024
const MAX_EXPANDED := 48 * 1024 * 1024
var last_error := ""
var active_manifest: Dictionary = {}
var active_dir := ""

func fail(message: String) -> bool:
	last_error = message
	return false

static func version_number(value: String) -> int:
	var parts := value.split(".")
	if parts.size() != 3:
		return -1
	var n := 0
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 999:
			return -1
		n = n * 1000 + int(part)
	return n

func trusted_url(url: String) -> bool:
	# Trust roots come ONLY from bundled project settings, never remote manifests.
	# Alternate domains must have valid HTTPS certificates and exact path prefixes.
	if not url.begins_with("https://") or url.contains("..") or url.contains("\\") or url.contains("@") or url.contains("%") or url.contains("#") or url.contains("?"):
		return false
	var prefixes: Variant = ProjectSettings.get_setting("hot_update/trusted_url_prefixes", PackedStringArray(["https://hit-appeared-corp-agreed.trycloudflare.com/update/"]))
	if not (prefixes is Array or prefixes is PackedStringArray):
		return false
	for prefix in prefixes:
		var root := str(prefix)
		if root.begins_with("https://") and root.ends_with("/") and not root.contains("@") and not root.contains("%") and not root.contains("..") and url.begins_with(root):
			return true
	return false

func validate_manifest(m: Dictionary) -> bool:
	if m.get("schema", 0) != 1 or m.get("format", "") != "shotdawn-assets-zip-v1":
		return fail("不支持的资源包格式")
	var revision: Variant = m.get("revision", 0)
	if not (revision is int or revision is float) or float(revision) != int(revision) or int(revision) <= 0:
		return fail("资源版本无效")
	var low := version_number(str(m.get("min_app", "")))
	var high := version_number(str(m.get("max_app", "")))
	var app := version_number(APP_VERSION)
	if low < 0 or high < low or app < low or app > high:
		return fail("资源包与应用 %s 不兼容，请先更新应用" % APP_VERSION)
	var size: Variant = m.get("size", 0)
	if not (size is int or size is float) or float(size) != int(size) or int(size) < 1 or int(size) > MAX_ARCHIVE:
		return fail("资源包大小无效")
	var sha := str(m.get("sha256", ""))
	if sha.length() != 64 or not sha.is_valid_hex_number(false):
		return fail("资源包 SHA256 无效")
	if not trusted_url(str(m.get("url", ""))):
		return fail("资源地址不在应用内置的可信 HTTPS 路径列表")
	return true

func _allowed_path(path: String) -> bool:
	if path == "maps/main.json":
		return true
	if not path.begins_with("textures/") or not path.ends_with(".png"):
		return false
	var name := path.trim_prefix("textures/").trim_suffix(".png")
	if name.is_empty() or name.length() > 80:
		return false
	for c in name:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true

func _vector(value: Variant, count: int, low: float, high: float) -> bool:
	if not value is Array or value.size() != count:
		return false
	for v in value:
		if not (v is int or v is float) or not is_finite(float(v)) or float(v) < low or float(v) > high:
			return false
	return true

func validate_map(m: Dictionary, files: PackedStringArray) -> bool:
	if m.get("schema", 0) != 1:
		return fail("地图数据格式无效")
	for key in m:
		if not key in ["schema", "label", "ground_color", "wall_color", "cover_color", "site_color", "ground_texture", "boxes"]:
			return fail("地图包含未允许字段: " + str(key))
	if not m.get("label", "") is String or str(m.get("label", "")).length() > 80:
		return fail("地图标签过长")
	for key in ["ground_color", "wall_color", "cover_color", "site_color"]:
		if m.has(key) and not _vector(m[key], 4, 0.0, 1.0):
			return fail("地图颜色无效")
	if m.has("ground_texture") and (not _allowed_path(str(m.ground_texture)) or not str(m.ground_texture).begins_with("textures/") or not str(m.ground_texture) in files):
		return fail("地图纹理不存在")
	var boxes: Variant = m.get("boxes", [])
	if not boxes is Array or boxes.size() > 64:
		return fail("地图方块过多")
	for box in boxes:
		if not box is Dictionary or box.size() != 3 or not _vector(box.get("position"), 3, -55.0, 55.0) or not _vector(box.get("size"), 3, 0.1, 20.0) or not _vector(box.get("color"), 4, 0.0, 1.0):
			return fail("地图方块无效")
	return true

func _read_archive(path: String, m: Dictionary) -> Dictionary:
	if not validate_manifest(m):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(m.size):
		fail("资源包大小校验失败")
		return {}
	file.close()
	if FileAccess.get_sha256(path).to_lower() != str(m.sha256).to_lower():
		fail("资源包 SHA256 校验失败")
		return {}
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		fail("无法打开资源 ZIP")
		return {}
	var names := zip.get_files()
	var result: Dictionary = {}
	var total := 0
	if names.size() > 65 or not "maps/main.json" in names:
		fail("资源 ZIP 文件清单无效")
		zip.close()
		return {}
	# Check the entire directory BEFORE reading/extracting anything.
	for name in names:
		if not _allowed_path(name) or names.count(name) != 1:
			fail("资源 ZIP 含禁止路径: " + name)
			zip.close()
			return {}
	for name in names:
		# Both ZIP directories were bounded/validated by _safe_zip before this read.
		var bytes := zip.read_file(name)
		if bytes.is_empty() or bytes.size() > MAX_FILE:
			fail("资源文件大小无效")
			zip.close()
			return {}
		total += bytes.size()
		if total > MAX_EXPANDED:
			fail("资源包展开过大")
			zip.close()
			return {}
		if name.ends_with(".png"):
			if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137,80,78,71,13,10,26,10]):
				fail("PNG 格式错误")
				zip.close()
				return {}
			var width := _big_endian(bytes, 16)
			var height := _big_endian(bytes, 20)
			var image := Image.new()
			if width < 1 or height < 1 or width > 2048 or height > 2048 or image.load_png_from_buffer(bytes) != OK:
				fail("PNG 无效或超过 2048px")
				zip.close()
				return {}
		result[name] = bytes
	zip.close()
	var parsed: Variant = JSON.parse_string(result["maps/main.json"].get_string_from_utf8())
	if not parsed is Dictionary or not validate_map(parsed, names):
		fail("地图数据校验失败: " + last_error)
		return {}
	return result

func _big_endian(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset+1]) << 16) | (int(bytes[offset+2]) << 8) | int(bytes[offset+3])

func _safe_zip(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_ARCHIVE:
		return fail("无法打开资源包或文件过大")
	# Strict ZIP_STORED subset: validate BOTH local headers and central directory
	# before ZIPReader can allocate/decompress. No ZIP64, extras, comments or links.
	var entries: Dictionary = {}
	var expanded_total := 0
	var central_offset := -1
	while f.get_position() + 4 <= f.get_length():
		var offset := f.get_position()
		var sig := f.get_32()
		if sig == 0x02014b50:
			central_offset = offset
			f.seek(offset)
			break
		if sig != 0x04034b50 or f.get_position() + 26 > f.get_length():
			return fail("ZIP 结构不受支持")
		f.get_16()
		var flags := f.get_16()
		var method := f.get_16()
		f.get_32()
		var crc := f.get_32()
		var compressed := f.get_32()
		var expanded := f.get_32()
		var name_len := f.get_16()
		var extra_len := f.get_16()
		if flags != 0 or method != 0 or compressed != expanded or expanded < 1 or expanded > MAX_FILE or name_len < 1 or name_len > 100 or extra_len != 0:
			return fail("仅支持无加密、无压缩的受限 ZIP")
		if f.get_position() + name_len + compressed > f.get_length():
			return fail("ZIP 文件截断")
		var name := f.get_buffer(name_len).get_string_from_utf8()
		if not _allowed_path(name) or entries.has(name) or entries.size() >= 65:
			return fail("ZIP 含重复或禁止路径: " + name)
		expanded_total += expanded
		if expanded_total > MAX_EXPANDED:
			return fail("ZIP 展开过大")
		entries[name] = [offset, compressed, crc]
		f.seek(f.get_position() + compressed)
	if central_offset < 0:
		return fail("ZIP 缺少目录")
	var seen: Dictionary = {}
	while f.get_position() + 4 <= f.get_length():
		var offset := f.get_position()
		var sig := f.get_32()
		if sig == 0x06054b50:
			if f.get_position() + 18 != f.get_length():
				return fail("ZIP 尾部无效")
			var disk := f.get_16()
			var central_disk := f.get_16()
			var count_disk := f.get_16()
			var count_all := f.get_16()
			var central_size := f.get_32()
			var declared_offset := f.get_32()
			var comment_len := f.get_16()
			if disk != 0 or central_disk != 0 or count_disk != entries.size() or count_all != entries.size() or seen.size() != entries.size() or declared_offset != central_offset or central_size != offset - central_offset or comment_len != 0 or not entries.has("maps/main.json"):
				return fail("ZIP 目录不一致")
			return true
		if sig != 0x02014b50 or f.get_position() + 42 > f.get_length():
			return fail("ZIP 中央目录无效")
		f.get_16()
		f.get_16()
		var flags := f.get_16()
		var method := f.get_16()
		f.get_32()
		var crc := f.get_32()
		var compressed := f.get_32()
		var expanded := f.get_32()
		var name_len := f.get_16()
		var extra_len := f.get_16()
		var comment_len := f.get_16()
		var disk := f.get_16()
		f.get_16()
		var attributes := f.get_32()
		var local_offset := f.get_32()
		if name_len < 1 or name_len > 100 or extra_len != 0 or comment_len != 0 or disk != 0 or flags != 0 or method != 0 or compressed != expanded or ((attributes >> 16) & 0xf000) == 0xa000:
			return fail("ZIP 中央目录含不受支持条目")
		var name := f.get_buffer(name_len).get_string_from_utf8()
		if not entries.has(name) or seen.has(name) or entries[name] != [local_offset, compressed, crc]:
			return fail("ZIP 中央目录与本地文件不一致")
		seen[name] = true
	return fail("ZIP 缺少尾部")

func _write_json(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return fail("无法写入更新状态")
	f.store_string(JSON.stringify(data))
	f.flush()
	return true

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if parsed is Dictionary else {}

func install(archive: String, manifest: Dictionary) -> bool:
	last_error = ""
	if not validate_manifest(manifest) or not _safe_zip(archive):
		return false
	var contents := _read_archive(archive, manifest)
	if contents.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(ROOT)
	var sha := str(manifest.sha256).to_lower()
	var slot: String = ROOT + "/" + str(sha)
	DirAccess.make_dir_recursive_absolute(slot)
	# Immutable slots; active pointer remains untouched until every write succeeds.
	if DirAccess.copy_absolute(archive, slot + "/assets.zip") != OK or not _write_json(slot + "/manifest.json", manifest):
		return fail("资源暂存失败，原资源不受影响")
	if not _extract(slot, contents):
		return false
	var state := _json(ROOT + "/active.json")
	var previous: String = str(state.get("sha256", ""))
	if previous == sha:
		previous = str(state.get("previous", ""))
	if not _write_json(ROOT + "/active.json.tmp", {"sha256": sha, "previous": previous}):
		return false
	if DirAccess.rename_absolute(ROOT + "/active.json.tmp", ROOT + "/active.json") != OK:
		return fail("资源状态切换失败")
	return true

func _extract(slot: String, contents: Dictionary) -> bool:
	for name in contents:
		DirAccess.make_dir_recursive_absolute((slot + "/" + name).get_base_dir())
		var f := FileAccess.open(slot + "/" + name, FileAccess.WRITE)
		if f == null:
			return fail("资源写入失败")
		f.store_buffer(contents[name])
		f.flush()
	return true

func activate() -> bool:
	active_dir = ""
	active_manifest = {}
	var state := _json(ROOT + "/active.json")
	for sha in [str(state.get("sha256", "")), str(state.get("previous", ""))]:
		if sha.length() != 64 or not sha.is_valid_hex_number(false):
			continue
		var slot: String = ROOT + "/" + str(sha)
		var m := _json(slot + "/manifest.json")
		if str(m.get("sha256", "")).to_lower() != sha or not _safe_zip(slot + "/assets.zip"):
			continue
		var contents := _read_archive(slot + "/assets.zip", m)
		if contents.is_empty() or not _extract(slot, contents):
			continue
		active_manifest = m
		active_dir = slot
		return true
	return false

func apply_map(scene: Node3D) -> void:
	if active_dir.is_empty():
		return
	var m := _json(active_dir + "/maps/main.json")
	var paths := {"ground_color": ["Ground/Mesh"], "wall_color": ["WallN/Mesh", "WallS/Mesh", "WallE/Mesh", "WallW/Mesh"], "cover_color": ["Covers/Cover1/Mesh", "Covers/Cover2/Mesh", "Covers/Cover3/Mesh", "Covers/Cover4/Mesh"], "site_color": ["BombSiteA/Marker"]}
	for key in paths:
		for path in paths[key]:
			var mesh: MeshInstance3D = scene.get_node_or_null(path) as MeshInstance3D
			if mesh == null or (not m.has(key) and not (key == "ground_color" and m.has("ground_texture"))):
				continue
			var material := StandardMaterial3D.new()
			if m.has(key):
				var c: Array = m[key]
				material.albedo_color = Color(c[0], c[1], c[2], c[3])
			if key == "ground_color" and m.has("ground_texture"):
				var image := Image.load_from_file(active_dir + "/" + str(m.ground_texture))
				material.albedo_texture = ImageTexture.create_from_image(image)
			mesh.material_override = material
	var container := Node3D.new()
	container.name = "HotPatchGeometry"
	scene.add_child(container)
	for box in m.get("boxes", []):
		var body := StaticBody3D.new()
		var p: Array = box.position
		var s: Array = box.size
		var c: Array = box.color
		body.position = Vector3(p[0], p[1], p[2])
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(s[0], s[1], s[2])
		mesh.mesh = cube
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(c[0], c[1], c[2], c[3])
		mesh.material_override = material
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = cube.size
		collision.shape = shape
		body.add_child(collision)
		container.add_child(body)
	scene.set_meta("resource_revision", int(active_manifest.revision))
	scene.set_meta("resource_label", str(m.get("label", "")))
