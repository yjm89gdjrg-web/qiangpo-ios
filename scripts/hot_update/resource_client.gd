extends Node
## Production transport always enforces repository HTTPS and rejects redirects.
signal manifest_checked(manifest: Dictionary, error: String)
signal patch_installed(success: bool, message: String)
signal download_progress(downloaded: int, total: int)
const MANIFEST_URL := "https://hit-appeared-corp-agreed.trycloudflare.com/update/resources.json"
const Store = preload("res://scripts/hot_update/resource_store.gd")
var store = Store.new()
var request: HTTPRequest
var candidate: Dictionary = {}
var downloading := false
var busy := false

func _ready() -> void:
	request = HTTPRequest.new()
	request.timeout = 30.0
	request.max_redirects = 0
	request.body_size_limit = 65536
	add_child(request)
	request.request_completed.connect(_completed)

func _request_url(url: String) -> Error:
	return request.request(url, ["Cache-Control: no-cache"])

func check() -> void:
	if busy:
		return
	candidate = {}
	downloading = false
	request.download_file = ""
	request.body_size_limit = 65536
	busy = true
	var url := str(ProjectSettings.get_setting("hot_update/manifest_url", MANIFEST_URL))
	if not store.trusted_url(url):
		busy = false
		manifest_checked.emit({}, "资源清单地址不在应用内置的可信 HTTPS 路径列表")
		return
	var err := _request_url(url)
	if err != OK:
		busy = false
		manifest_checked.emit({}, "无法连接资源更新服务器: %s" % err)

func download(manifest: Dictionary) -> void:
	if busy:
		return
	if not store.validate_manifest(manifest):
		patch_installed.emit(false, store.last_error)
		return
	candidate = manifest.duplicate(true)
	DirAccess.make_dir_recursive_absolute(Store.ROOT)
	request.download_file = Store.ROOT + "/download.zip.part"
	request.body_size_limit = int(candidate.size)
	downloading = true
	busy = true
	var err := _request_url(str(candidate.url))
	if err != OK:
		busy = false
		downloading = false
		patch_installed.emit(false, "资源下载启动失败: %s" % err)

func _process(_delta: float) -> void:
	if busy and downloading:
		download_progress.emit(request.get_downloaded_bytes(), int(candidate.get("size", 0)))

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if not downloading:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			manifest_checked.emit({}, "资源检查失败: HTTP %d / %d；继续使用现有资源" % [code, result])
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not parsed is Dictionary or not store.validate_manifest(parsed):
			manifest_checked.emit({}, "资源清单无效: " + store.last_error)
			return
		candidate = parsed
		manifest_checked.emit(candidate, "")
		return
	downloading = false
	var path := Store.ROOT + "/download.zip.part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(path)
		patch_installed.emit(false, "资源下载失败: HTTP %d / %d；原资源未改变" % [code, result])
		return
	var ok: bool = store.install(path, candidate)
	DirAccess.remove_absolute(path)
	patch_installed.emit(ok, "资源已校验并保存；下次启动生效，也可立即重新载入关卡。" if ok else store.last_error)
