extends Control
## Kit banner (proposal PDF p.23 "Big banner" / "Banners", p.24 "Point won"): a cut-corner
## plate in a solid colour with pixel-font text, and an optional ribbon under it. Drawn
## entirely in _draw (PixelDraw), sized to its text, centred on `anchor_center`.
## Motion: slams in (scale 1.25 -> 1 with a small settle); callers fade it with modulate.

const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")

var title: = ""
var ribbon: = ""
var fill: = Color("4f8ee0")
var ribbon_fill: = Color("f5d060")
var title_color: = Color("f2efe6")
var ribbon_color: = Color("0f2230")
var title_px: = 54.0        # wanted title size at scale 1 (snapped to the font's whole steps)
var ribbon_px: = 27.0
var s: = 1.0                # layout scale (MobileLayout.scale_for)
var max_width: = 0.0        # 0 = no limit
var _age: = 99.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Set the text and colours, size to fit, and play the slam-in.
func present(p_title: String, p_ribbon: String = "", p_fill: Color = fill, p_ribbon_fill: Color = ribbon_fill, animate: bool = true) -> void:
	title = p_title
	ribbon = p_ribbon
	fill = p_fill
	ribbon_fill = p_ribbon_fill
	title_color = Color("0f2230") if fill.get_luminance() > 0.62 else Color("f2efe6")
	ribbon_color = Color("0f2230") if ribbon_fill.get_luminance() > 0.55 else Color("f2efe6")
	resize_to_fit()
	_age = 0.0 if animate else 99.0
	scale = Vector2.ONE * (1.25 if animate else 1.0)
	set_process(animate)
	queue_redraw()

func set_ribbon(p_ribbon: String, p_fill: Color) -> void:
	ribbon = p_ribbon
	ribbon_fill = p_fill
	ribbon_color = Color("0f2230") if ribbon_fill.get_luminance() > 0.55 else Color("f2efe6")
	resize_to_fit()
	queue_redraw()

func _sizes() -> Dictionary:
	var u: float = PixelDraw.unit(s)
	var tsize: int = PixelDraw.font_size(title_px * s)
	var rsize: int = PixelDraw.font_size(ribbon_px * s)
	# Shrink the text a step at a time until it fits the allowed width.
	while max_width > 0.0 and tsize > PixelDraw.font_size(18) and PixelDraw.text_width(title, tsize) + 12.0 * u > max_width:
		tsize -= UiTheme.PIXEL_UNIT
	while max_width > 0.0 and rsize > UiTheme.PIXEL_UNIT and PixelDraw.text_width(ribbon, rsize) + 10.0 * u > max_width * 0.9:
		rsize -= UiTheme.PIXEL_UNIT
	var f: Font = PixelDraw.font()
	var plate_h: float = roundf((f.get_height(tsize) + 6.0 * u) / u) * u
	var plate_w: float = roundf((PixelDraw.text_width(title, tsize) + 12.0 * u) / u) * u
	var rib_h: float = roundf((f.get_height(rsize) + 4.0 * u) / u) * u if ribbon != "" else 0.0
	var rib_w: float = roundf((PixelDraw.text_width(ribbon, rsize) + 10.0 * u) / u) * u if ribbon != "" else 0.0
	return {"u": u, "t": tsize, "r": rsize, "pw": plate_w, "ph": plate_h, "rw": rib_w, "rh": rib_h}

func resize_to_fit() -> void:
	var z: = _sizes()
	var overlap: float = 1.0 * z.u
	size = Vector2(maxf(z.pw, z.rw), z.ph + (z.rh - overlap if ribbon != "" else 0.0))
	pivot_offset = size * 0.5

## Place so the banner's centre sits on `center` (whole pixels).
func center_on(center: Vector2) -> void:
	position = (center - size * 0.5).round()

func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.05)
	var k: float
	if _age < 0.12:
		k = lerpf(1.25, 0.96, ease(_age / 0.12, 0.4))
	else:
		k = 1.0 - 0.04 * exp(-(_age - 0.12) * 16.0) * cos((_age - 0.12) * 38.0)
	if _age > 0.5:
		k = 1.0
		set_process(false)
	scale = Vector2.ONE * k

func _draw() -> void:
	if title == "": return
	var z: = _sizes()
	var u: float = z.u
	var plate_rect: = Rect2(Vector2((size.x - z.pw) * 0.5, 0.0), Vector2(z.pw, z.ph))
	var face: Rect2 = PixelDraw.plate(self, plate_rect, fill, u, 2, 2)
	PixelDraw.text(self, title, Vector2(face.get_center().x, PixelDraw.baseline_for(face.get_center().y, z.t)), z.t, title_color, u)
	if ribbon == "": return
	var rib_rect: = Rect2(Vector2((size.x - z.rw) * 0.5, z.ph - u), Vector2(z.rw, z.rh))
	var rface: Rect2 = PixelDraw.plate(self, rib_rect, ribbon_fill, u, 1, 1)
	PixelDraw.text(self, ribbon, Vector2(rface.get_center().x, PixelDraw.baseline_for(rface.get_center().y, z.r)), z.r, ribbon_color, u)
