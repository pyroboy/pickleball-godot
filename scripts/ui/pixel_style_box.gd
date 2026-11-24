extends StyleBox
## UI kit StyleBox drawn in hard pixel steps (semi pixel art: no anti-aliasing, no glow):
##  - plate: stair corners, one-UI-pixel lighter lip, darker bottom bevel, optional pixel rim
##    (HUD pills, TIPS, Skip);
##  - disc: the on-screen pads' pixel disc (round icon buttons).
## Only the drawing changes: the caller sets the content margins (so the control's minimum
## size is what it was) and the control's rect, its touch area, is untouched. The owner
## control should use TEXTURE_FILTER_NEAREST (the disc masks are tiny textures scaled up).
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")

var disc: = false
var fill: = UiTheme.PANEL
var rim: = Color(0, 0, 0, 0)
var rim_width: = 1
var unit: = 3.0          # screen pixels per UI pixel (PixelDraw.unit)
var bevel: = 2           # darker UI-pixel rows at the bottom (plate) / crescent on or off (disc)
var lip: = true
var inset: = Vector2.ZERO   # drawn this far inside the rect on each side (negative: outside)
var drop: = 0.0          # pressed: the face sits this many screen pixels lower

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	rect = rect.grow_individual(-inset.x, -inset.y, -inset.x, -inset.y)
	if disc:
		PixelDraw.disc_rid(to_canvas_item, rect.get_center() + Vector2(0, drop), minf(rect.size.x, rect.size.y) * 0.5, unit, fill, rim, rim_width, bevel > 0)
	else:
		rect.position.y += drop
		rect.size.y -= drop
		PixelDraw.plate_rid(to_canvas_item, rect, fill, unit, bevel, lip and drop <= 0.0, rim)

static func plate(fill_color: Color, s: float, bevel_rows: int = 2, rim_color: Color = Color(0, 0, 0, 0)) -> StyleBox:
	var style: = new()
	style.fill = fill_color
	style.rim = rim_color
	style.unit = PixelDraw.unit(s)
	style.bevel = bevel_rows
	return style

static func round_button(fill_color: Color, s: float, rim_color: Color = Color(0, 0, 0, 0)) -> StyleBox:
	var style: = plate(fill_color, s, 1, rim_color)
	style.disc = true
	return style

## Dark HUD pill for one line of pixel text (serve line, shot name, speed): kit navy,
## translucent so it stays light, readable over the cement, the crowd and the shop sign.
## Margins centre the 2x pixel font's capitals on the face above the bevel.
static func label_pill(s: float) -> StyleBox:
	var style: = plate(Color(UiTheme.PANEL, 0.86), s, 1)
	style.content_margin_left = roundf(10.0 * s)
	style.content_margin_right = roundf(10.0 * s)
	style.content_margin_top = roundf(7.0 * s)
	style.content_margin_bottom = roundf(6.0 * s)
	return style

static func set_margins(style: StyleBox, left: float, top: float, right: float, bottom: float) -> void:
	style.content_margin_left = left
	style.content_margin_top = top
	style.content_margin_right = right
	style.content_margin_bottom = bottom
