extends RefCounted
## Centers in viewport fractions; sizes relative to its shorter side.
const PATH := "user://mobile_controls.cfg"
const IDS := ["fire", "jump", "switch", "plant", "move"]
const DEFAULTS := {
	"fire": {"center": Vector2(0.91, 0.51), "scale": 1.2},
	"jump": {"center": Vector2(0.91, 0.72), "scale": 1.0},
	"switch": {"center": Vector2(0.74, 0.89), "scale": 1.0},
	"plant": {"center": Vector2(0.91, 0.89), "scale": 1.0},
	"move": {"center": Vector2(0.20, 0.73), "scale": 1.0}}
var controls: Dictionary = DEFAULTS.duplicate(true)
var show_joystick := true

func load_settings(path: String = PATH) -> void:
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for id in IDS:
		var center: Variant = cfg.get_value(id, "center", controls[id].center)
		var scale_value: Variant = cfg.get_value(id, "scale", 1.0)
		if center is Vector2 and is_finite(center.x) and is_finite(center.y):
			controls[id].center = center.clamp(Vector2.ZERO, Vector2.ONE)
		if (scale_value is float or scale_value is int) and is_finite(float(scale_value)):
			controls[id].scale = clampf(float(scale_value), 0.6, 1.8)
	show_joystick = bool(cfg.get_value("options", "show_joystick", true))

func save_settings(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	for id in IDS:
		cfg.set_value(id, "center", controls[id].center)
		cfg.set_value(id, "scale", controls[id].scale)
	cfg.set_value("options", "show_joystick", show_joystick)
	return cfg.save(path)

func reset() -> void:
	controls = DEFAULTS.duplicate(true)
	show_joystick = true

func rect_for(id: String, viewport: Vector2) -> Rect2:
	var short_side := minf(viewport.x, viewport.y)
	var base := Vector2(0.25, 0.14) if id != "move" else Vector2(0.32, 0.32)
	var size := (base * short_side * float(controls[id].scale)).min(viewport)
	var center: Vector2 = controls[id].center * viewport
	return Rect2((center - size * 0.5).clamp(Vector2.ZERO, viewport - size), size)

func set_center(id: String, center: Vector2, viewport: Vector2) -> void:
	if viewport.x <= 0 or viewport.y <= 0:
		return
	var half := rect_for(id, viewport).size * 0.5
	controls[id].center = center.clamp(half, viewport - half) / viewport
