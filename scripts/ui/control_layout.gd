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

## 屏幕可用区域（避开 iPhone 刘海与底部横条），以屏幕比例表示。
static func safe_area_fraction() -> Rect2:
	var screen := Vector2(DisplayServer.screen_get_size())
	if screen.x <= 0 or screen.y <= 0:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var frac := Rect2(Vector2(safe.position) / screen, Vector2(safe.size) / screen)
	if frac.size.x <= 0.0 or frac.size.y <= 0.0 or frac.size.x > 1.0 or frac.size.y > 1.0:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	return frac

func usable_rect(viewport: Vector2) -> Rect2:
	var frac := safe_area_fraction()
	var rect := Rect2(frac.position * viewport, frac.size * viewport)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2(Vector2.ZERO, viewport)
	return rect

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
	var area := usable_rect(viewport)
	var short_side := minf(viewport.x, viewport.y)
	var base := Vector2(0.25, 0.14) if id != "move" else Vector2(0.32, 0.32)
	var size := (base * short_side * float(controls[id].scale)).min(area.size)
	var center: Vector2 = controls[id].center * viewport
	return Rect2((center - size * 0.5).clamp(area.position, area.position + area.size - size), size)

func set_center(id: String, center: Vector2, viewport: Vector2) -> void:
	if viewport.x <= 0 or viewport.y <= 0:
		return
	var area := usable_rect(viewport)
	var half := rect_for(id, viewport).size * 0.5
	controls[id].center = center.clamp(area.position + half, area.position + area.size - half) / viewport
