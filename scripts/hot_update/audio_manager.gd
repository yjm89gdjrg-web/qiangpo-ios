extends RefCounted
## Plays hot-updated WAV assets. Sounds come from the resource slot; the App
## itself ships no audio, so they can be replaced without a new build.

const NAMES := ["fire", "hit", "jump", "switch", "plant", "explode", "die", "reload"]

var players: Dictionary = {}
var enabled := true
var last_slot := ""

func _init() -> void:
	for name in NAMES:
		var player := AudioStreamPlayer.new()
		player.name = "sfx_" + name
		players[name] = player

func attach(parent: Node) -> void:
	for name in players:
		var player: AudioStreamPlayer = players[name]
		if player.get_parent() != parent:
			if player.get_parent():
				player.get_parent().remove_child(player)
			parent.add_child(player)
	if player_is_empty():
		load_from_active()

func player_is_empty() -> bool:
	for name in players:
		var player: AudioStreamPlayer = players[name]
		if player.stream != null:
			return false
	return true

## Loads whatever WAVs the active resource slot provides, if any.
func load_from_active() -> void:
	var store = load("res://scripts/hot_update/resource_store.gd").new()
	store.activate()
	refresh(store)

func refresh(store: RefCounted) -> void:
	var slot: String = store.active_dir
	for name in NAMES:
		var player: AudioStreamPlayer = players[name]
		var path: String = store.audio_path(name) if slot != "" else ""
		if path.is_empty():
			player.stream = null
			continue
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		if not load_wav(stream, path):
			player.stream = null
			continue
		player.stream = stream
	last_slot = slot

func load_wav(stream: AudioStreamWAV, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 44 or bytes.slice(0, 4) != PackedByteArray([82, 73, 70, 70]):
		return false
	stream.data = bytes
	return true

func has_any() -> bool:
	for name in players:
		var player: AudioStreamPlayer = players[name]
		if player.stream != null:
			return true
	return false

func play(name: String, volume_db: float = 0.0) -> void:
	if not enabled or not players.has(name):
		return
	var player: AudioStreamPlayer = players[name]
	if player.stream == null:
		return
	player.volume_db = volume_db
	player.play()
