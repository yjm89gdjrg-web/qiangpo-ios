extends Node
## Resource updates are real sandbox assets; IPA updates still need an external installer.
const Store = preload("res://scripts/hot_update/resource_store.gd")
const ResourceClient = preload("res://scripts/hot_update/resource_client.gd")
const CURRENT_VERSION := Store.APP_VERSION
const MANIFEST_URL := "https://hit-appeared-corp-agreed.trycloudflare.com/update/ShotDawn-update.json"
const DOWNLOAD_PATH := "user://ShotDawn-update.ipa"
var client: Node
var manifest_request: HTTPRequest
var download_request: HTTPRequest
var ui_layer: CanvasLayer
var overlay: Control
var panel: PanelContainer
var status_label: Label
var progress: ProgressBar
var download_button: Button
var apply_button: Button
var app_button: Button
var latest_manifest: Dictionary = {}
var resource_manifest: Dictionary = {}
var mode := "resource"
var checking := false
var input_was_captured := false
var saved_process_modes: Dictionary = {}

func _ready() -> void:
	_build_ui()
	client = ResourceClient.new()
	add_child(client)
	client.manifest_checked.connect(_resource_checked)
	client.patch_installed.connect(_resource_installed)
	client.download_progress.connect(_on_download_progress)
	manifest_request = HTTPRequest.new()
	manifest_request.timeout = 20.0
	manifest_request.max_redirects = 0
	manifest_request.body_size_limit = 65536
	add_child(manifest_request)
	manifest_request.request_completed.connect(_on_manifest_completed)
	download_request = HTTPRequest.new()
	download_request.timeout = 120.0
	download_request.max_redirects = 0
	add_child(download_request)
	download_request.request_completed.connect(_on_download_completed)
	# User explicitly checks first: no surprise consent dialog/network request on startup.

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 30
	add_child(ui_layer)
	var check := Button.new()
	check.text = "更新"
	check.position = Vector2(18, 125)
	check.custom_minimum_size = Vector2(100, 48)
	check.pressed.connect(_check_for_update)
	ui_layer.add_child(check)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	ui_layer.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "资源热更新 / 应用安装包 · %s" % CURRENT_VERSION
	box.add_child(title)
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(400, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	progress = ProgressBar.new()
	progress.visible = false
	box.add_child(progress)
	download_button = Button.new()
	download_button.text = "同意下载资源"
	download_button.pressed.connect(_start_download)
	box.add_child(download_button)
	apply_button = Button.new()
	apply_button.text = "立即载入资源（重新开始本局）"
	apply_button.visible = false
	apply_button.pressed.connect(_apply_resources)
	box.add_child(apply_button)
	app_button = Button.new()
	app_button.text = "另行检查应用 IPA 更新"
	app_button.pressed.connect(_check_app_update)
	box.add_child(app_button)
	var close := Button.new()
	close.text = "稍后 / 返回游戏"
	close.pressed.connect(_close)
	box.add_child(close)

func _show() -> void:
	if overlay.visible:
		return
	overlay.visible = true
	input_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Block gameplay touch input as well as GUI clicks while consenting/downloading.
	for path in ["Player", "Bots", "RoundManager", "HUD"]:
		var node := get_parent().get_node_or_null(path)
		if node:
			saved_process_modes[path] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var player := get_parent().get_node_or_null("Player")
	if player:
		player.set("hud_firing", false)
		player.set("move_touch_id", -1)
		player.set("look_touch_id", -1)
		player.set("fire_touch_id", -1)
		player.set("move_vec", Vector2.ZERO)

func _close() -> void:
	overlay.visible = false
	for path in ["Player", "Bots", "RoundManager", "HUD"]:
		var node := get_parent().get_node_or_null(path)
		if node:
			node.process_mode = saved_process_modes.get(path, Node.PROCESS_MODE_INHERIT)
	saved_process_modes.clear()
	if input_was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _check_for_update() -> void:
	if client.busy or checking or download_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_show()
		return
	mode = "resource"
	resource_manifest = {}
	download_button.text = "同意下载资源"
	download_button.disabled = true
	apply_button.visible = false
	progress.visible = false
	_show()
	status_label.text = "正在检查资源更新…\n仅更新地图/PNG素材，不更新代码或 IPA。"
	client.check()

func _resource_checked(manifest: Dictionary, error: String) -> void:
	if not error.is_empty():
		status_label.text = error
		return
	var store = Store.new()
	store.activate()
	var current: int = int(store.active_manifest.get("revision", 0))
	if int(manifest.revision) <= current:
		status_label.text = "资源已是最新（r%d）。应用 %s。" % [current, CURRENT_VERSION]
		return
	resource_manifest = manifest
	status_label.text = "可用资源 r%d → r%d · %.2f MB\n%s\n是否下载？安装后下次启动生效；无需安装 IPA。" % [current, int(manifest.revision), float(manifest.size) / 1048576.0, str(manifest.get("notes", "地图和素材更新")).left(500)]
	download_button.disabled = false

func _start_download() -> void:
	if mode == "app":
		_start_app_download()
		return
	download_button.disabled = true
	app_button.disabled = true
	progress.visible = true
	progress.value = 0
	status_label.text = "正在下载资源，完成后校验 SHA256 和安全文件清单…"
	client.download(resource_manifest)

func _resource_installed(success: bool, message: String) -> void:
	status_label.text = message
	app_button.disabled = false
	progress.visible = false
	apply_button.visible = success
	download_button.disabled = success

func _on_download_progress(downloaded: int, total: int) -> void:
	if total > 0:
		progress.value = float(downloaded) / float(total) * 100.0

func _apply_resources() -> void:
	# ZIP data never replaces cached scripts: boot reconstructs only data-driven meshes.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/boot.tscn")

func _check_app_update() -> void:
	if client.busy or checking or download_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	mode = "app"
	checking = true
	download_button.disabled = true
	download_button.text = "下载 IPA（需外部自签安装）"
	apply_button.visible = false
	status_label.text = "正在检查应用安装包；IPA 不能在应用内自行安装。"
	var url := str(ProjectSettings.get_setting("hot_update/app_manifest_url", MANIFEST_URL))
	var store = Store.new()
	if not store.trusted_url(url):
		checking = false
		status_label.text = "应用清单地址不在应用内置的可信 HTTPS 路径列表"
		return
	var err := manifest_request.request(url)
	if err != OK:
		checking = false
		status_label.text = "应用更新检查失败: %d" % err

func _on_manifest_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	checking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_label.text = "应用更新检查失败: HTTP %d" % code
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		status_label.text = "应用清单无效"
		return
	latest_manifest = parsed
	var latest := str(parsed.get("version", ""))
	if Store.version_number(latest) <= Store.version_number(CURRENT_VERSION):
		status_label.text = "应用已是最新 %s；资源更新与 IPA 更新互相独立。" % CURRENT_VERSION
		return
	status_label.text = "应用 %s → %s\n%s\n此操作只下载 IPA，不能自行安装；需外部自签工具。" % [CURRENT_VERSION, latest, str(parsed.get("notes", "")).left(500)]
	download_button.disabled = false

func _start_app_download() -> void:
	var url := str(latest_manifest.get("ipa_url", ""))
	var store = Store.new()
	# Bare IP/self-signed download sites intentionally rejected; browser/manual install only.
	if not store.trusted_url(url):
		status_label.text = "IPA 地址不在应用内置的可信 HTTPS 路径列表。\n请从官方发布页面手动下载并自签安装；不绕过 TLS 校验。"
		return
	download_button.disabled = true
	app_button.disabled = true
	progress.visible = true
	status_label.text = "正在下载 IPA；完成后仍需外部自签安装。"
	download_request.download_file = DOWNLOAD_PATH + ".part"
	var err := download_request.request(url)
	if err != OK:
		status_label.text = "IPA 下载启动失败: %d" % err
		download_button.disabled = false
		app_button.disabled = false

func _process(_delta: float) -> void:
	if mode == "app" and progress.visible:
		_on_download_progress(download_request.get_downloaded_bytes(), download_request.get_body_size())

func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	download_button.disabled = false
	app_button.disabled = false
	progress.visible = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and DirAccess.rename_absolute(DOWNLOAD_PATH + ".part", DOWNLOAD_PATH) == OK:
		status_label.text = "IPA 已保存到应用沙盒 ShotDawn-update.ipa。\n应用不能自行安装或导出到自签工具；请通过文件共享或官方发布页面获取 IPA。"
	else:
		DirAccess.remove_absolute(DOWNLOAD_PATH + ".part")
		status_label.text = "IPA 下载失败: HTTP %d" % code
