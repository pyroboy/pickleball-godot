extends RefCounted

const REFERENCE_WIDTH: = 720.0

static func is_portrait(viewport_size: Vector2) -> bool:
	return viewport_size.y > viewport_size.x

static func scale_for(viewport_size: Vector2) -> float:
	return clampf(viewport_size.x / REFERENCE_WIDTH, 0.4, 2.0)

static func safe_rect(viewport: Viewport) -> Rect2:
	var full: = viewport.get_visible_rect()
	if not OS.has_feature("mobile"):
		return full

	var pixels: = DisplayServer.get_display_safe_area()
	var window_size: = Vector2(DisplayServer.window_get_size())
	if pixels.size.x <= 0 or pixels.size.y <= 0 or window_size.x <= 0 or window_size.y <= 0:
		return full
	return safe_rect_from_pixels(full, pixels, window_size, Vector2(DisplayServer.window_get_position()))

static func safe_rect_from_pixels(full: Rect2, pixels: Rect2i, window_size: Vector2, window_origin: = Vector2.ZERO) -> Rect2:
	if window_size.x <= 0 or window_size.y <= 0: return full
	var ratio: = full.size / window_size
	var origin: = (Vector2(pixels.position) - window_origin) * ratio
	var safe: = Rect2(origin, Vector2(pixels.size) * ratio).intersection(full)
	return safe if safe.size.x > 0 and safe.size.y > 0 else full

static func court_rect(viewport_size: Vector2, safe: Rect2) -> Rect2:
	var s: = scale_for(viewport_size)



	var top: = safe.position.y + 320 * s
	var bottom: = safe.end.y - 292 * s


	return Rect2(safe.position.x + 4 * s, top, safe.size.x - 8 * s, maxf(1.0, bottom - top))

static func deck_rect(viewport_size: Vector2, safe: Rect2) -> Rect2:
	var s: = scale_for(viewport_size)
	return Rect2(safe.position.x + 16 * s, safe.end.y - 314 * s, safe.size.x - 32 * s, 270 * s)
