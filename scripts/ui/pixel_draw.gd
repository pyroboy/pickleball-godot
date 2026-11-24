extends RefCounted
## Pixel-art drawing for the UI kit (proposal PDF p.23): everything snaps to a "UI pixel"
## (3 screen pixels on the 720-wide layout). Discs and rings are baked once as small
## white masks and drawn scaled with nearest filtering, so a control redraw costs a few
## texture draws, not hundreds of rects. Text: the 5x7 pixel font with a hard 1-UI-pixel
## drop shadow, never a black outline. Callers set texture_filter = NEAREST on themselves.

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const SHADOW: = Color(0.02, 0.07, 0.1, 0.92)   # dark navy, not black

static var _masks: Dictionary = {}

## Screen pixels per UI pixel for a layout scale (1.0 on a 720-wide phone).
static func unit(s: float) -> float:
	return maxf(1.0, roundf(3.0 * s))

static func _mask(kind: String, r: int, w: int) -> ImageTexture:
	var key: = "%s:%d:%d" % [kind, r, w]
	if _masks.has(key): return _masks[key]
	var n: int = r * 2
	var img: = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rr: float = float(r) - 0.2
	for y in n:
		for x in n:
			var p: = Vector2(x + 0.5 - r, y + 0.5 - r)
			var d: float = p.length()
			var on: bool = false
			match kind:
				"disc": on = d <= rr
				"ring": on = d <= rr and d > rr - w
				"low": on = d <= rr and (p + Vector2(0, w)).length() > rr    # bottom crescent
				"high": on = d <= rr and (p - Vector2(0, w)).length() > rr   # top crescent
			if on: img.set_pixel(x, y, Color.WHITE)
	var tex: = ImageTexture.create_from_image(img)
	_masks[key] = tex
	return tex

static func _disc_rect(center: Vector2, r: int, u: float) -> Rect2:
	return Rect2((center - Vector2(r, r) * u).round(), Vector2(r, r) * 2.0 * u)

## Filled pixel disc with a lighter top edge and a darker bottom bevel; optional rim.
static func disc(ci: CanvasItem, center: Vector2, radius: float, u: float, fill: Color,
		rim: Color = Color(0, 0, 0, 0), rim_width: int = 1, bevel: bool = true) -> void:
	disc_rid(ci.get_canvas_item(), center, radius, u, fill, rim, rim_width, bevel)

## disc() for callers that only have the canvas item RID (StyleBox._draw).
static func disc_rid(ci: RID, center: Vector2, radius: float, u: float, fill: Color,
		rim: Color = Color(0, 0, 0, 0), rim_width: int = 1, bevel: bool = true) -> void:
	var r: int = maxi(2, roundi(radius / u))
	var rect: = _disc_rect(center, r, u)
	RenderingServer.canvas_item_add_texture_rect(ci, rect, _mask("disc", r, 0).get_rid(), false, fill)
	if bevel:
		RenderingServer.canvas_item_add_texture_rect(ci, rect, _mask("low", r, 1).get_rid(), false, Color(fill.darkened(0.45), fill.a))
		RenderingServer.canvas_item_add_texture_rect(ci, rect, _mask("high", r, 1).get_rid(), false, Color(fill.lightened(0.28), fill.a))
	if rim.a > 0.0:
		RenderingServer.canvas_item_add_texture_rect(ci, rect, _mask("ring", r, rim_width).get_rid(), false, rim)

## Stepped pixel plate (the HUD pills, TIPS, Skip, the LED board frame): corners cut in
## two whole-UI-pixel stairs, one UI pixel lighter lip on top, `bevel` darker UI-pixel rows
## at the bottom, optional one-UI-pixel rim that follows the stairs. Drawn as
## non-overlapping rects, so a translucent fill stays even and nothing is anti-aliased.
static func plate_rid(ci: RID, rect: Rect2, fill: Color, u: float, bevel: int = 2, lip: bool = true,
		rim: Color = Color(0, 0, 0, 0)) -> void:
	var p: = rect.position.round()
	var w: = roundf(rect.size.x)
	var h: = roundf(rect.size.y)
	if w <= 0.0 or h <= 0.0: return
	if w < 5.0 * u or h < 5.0 * u:
		RenderingServer.canvas_item_add_rect(ci, Rect2(p, Vector2(w, h)), fill)
		return
	var dark: = Color(fill.darkened(0.45), fill.a)
	var light: = Color(fill.lightened(0.3), fill.a)
	var split: = h - float(bevel) * u   # rows at or below this are the bevel
	# Rows top to bottom: [from, to, inset]. Stairs: 2u, u, body, u, 2u.
	_band(ci, p, w, 0.0, u, 2.0 * u, split, light if lip else fill, dark)
	_band(ci, p, w, u, 2.0 * u, u, split, fill, dark)
	_band(ci, p, w, 2.0 * u, h - 2.0 * u, 0.0, split, fill, dark)
	_band(ci, p, w, h - 2.0 * u, h - u, u, split, fill, dark)
	_band(ci, p, w, h - u, h, 2.0 * u, split, fill, dark)
	if rim.a > 0.0:
		for r in [Rect2(p.x + 2.0 * u, p.y, w - 4.0 * u, u), Rect2(p.x + 2.0 * u, p.y + h - u, w - 4.0 * u, u),
				Rect2(p.x, p.y + 2.0 * u, u, h - 4.0 * u), Rect2(p.x + w - u, p.y + 2.0 * u, u, h - 4.0 * u),
				Rect2(p.x + u, p.y + u, u, u), Rect2(p.x + w - 2.0 * u, p.y + u, u, u),
				Rect2(p.x + u, p.y + h - 2.0 * u, u, u), Rect2(p.x + w - 2.0 * u, p.y + h - 2.0 * u, u, u)]:
			RenderingServer.canvas_item_add_rect(ci, r, rim)

static func _band(ci: RID, p: Vector2, w: float, from: float, to: float, inset: float, split: float, top_color: Color, bevel_color: Color) -> void:
	if to <= from or w - 2.0 * inset <= 0.0: return
	var cut: = clampf(split, from, to)
	if cut > from: RenderingServer.canvas_item_add_rect(ci, Rect2(p.x + inset, p.y + from, w - 2.0 * inset, cut - from), top_color)
	if to > cut: RenderingServer.canvas_item_add_rect(ci, Rect2(p.x + inset, p.y + cut, w - 2.0 * inset, to - cut), bevel_color)

## Full pixel ring (outline only).
static func ring(ci: CanvasItem, center: Vector2, radius: float, u: float, color: Color, width: int = 1) -> void:
	var r: int = maxi(2, roundi(radius / u))
	ci.draw_texture_rect(_mask("ring", r, width), _disc_rect(center, r, u), false, color)

## Partial ring (charge, timing): chunky facets about two UI pixels long, no anti-aliasing.
static func arc(ci: CanvasItem, center: Vector2, radius: float, u: float, from: float, to: float,
		color: Color, width: int = 2) -> void:
	var points: int = maxi(3, ceili(absf(to - from) * radius / (u * 2.0)) + 1)
	ci.draw_arc(center.round(), roundf(radius / u) * u, from, to, points, color, width * u, false)

## Cut-corner polygon for a rect (45 degree chamfer of `cut` screen pixels).
static func chamfer(rect: Rect2, cut: float) -> PackedVector2Array:
	var p: = rect.position
	var e: = rect.end
	return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut),
		Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])

## Kit plate: cut corners, one UI pixel lighter top edge, chunky darker bottom bevel.
## Returns the face rect (above the bevel) for placing content.
static func plate(ci: CanvasItem, rect: Rect2, fill: Color, u: float, bevel: int = 2, cut: int = 2) -> Rect2:
	rect = Rect2(rect.position.round(), rect.size.round())
	var c: float = cut * u
	ci.draw_colored_polygon(chamfer(rect, c), Color(fill.darkened(0.45), fill.a))
	var face: = Rect2(rect.position, rect.size - Vector2(0, bevel * u))
	ci.draw_colored_polygon(chamfer(face, c), fill)
	ci.draw_rect(Rect2(face.position + Vector2(c, 0), Vector2(face.size.x - 2.0 * c, u)), Color(fill.lightened(0.3), fill.a))
	return face

static func font() -> Font:
	return UiTheme.pixel_font()

## Whole-pixel font size for a wanted size in screen pixels.
static func font_size(px: float) -> int:
	return UiTheme.pixel_size(px)

static func text_width(text: String, size: int) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Centred pixel text on `baseline_center`, hard drop shadow one UI pixel down.
static func text(ci: CanvasItem, value: String, baseline_center: Vector2, size: int, color: Color, u: float) -> void:
	var f: = font()
	var origin: = (baseline_center - Vector2(text_width(value, size) * 0.5, 0.0)).round()
	ci.draw_string(f, origin + Vector2(0, u), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SHADOW, SHADOW.a * color.a))
	ci.draw_string(f, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Baseline that centres one line of `size` text vertically on `center_y`.
static func baseline_for(center_y: float, size: int) -> float:
	var f: = font()
	return roundf(center_y + (f.get_ascent(size) - f.get_descent(size)) * 0.5)
