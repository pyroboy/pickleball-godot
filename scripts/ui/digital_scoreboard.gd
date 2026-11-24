extends Control
class_name DigitalScoreboard
## Retro LED scoreboard: two fixed team boxes (left = your team / blue, right =
## opponents / red), 7-segment amber digits with unlit "ghost" segments, a server
## dot and server-number LED. A changed score rolls its digits (old slides out
## up, new drops in), flickers, and flashes the team box. Redraws only while
## something animates.
## Drawn in the UI kit's pixel style like the rest of the HUD: kit navy plate with stair
## corners and bevel, team boxes with one-UI-pixel rims, names in the pixel font, square
## LEDs, whole-pixel segments, no glow.
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")

const BLUE := Color("4eb8ff")
const RED := Color("ff6278")
const LED := Color("ffb43a")          # amber LED
const LED_HOT := Color("fff1c4")
const GHOST := Color(1.0, 0.7, 0.25, 0.08)
const FACE := Color("0b0f14")
const BEZEL := Color("2b3440")
const ROLL_SECONDS := 0.32
const FLASH_SECONDS := 0.9

## 7-segment bits: a b c d e f g (top, top-right, bottom-right, bottom, bottom-left, top-left, middle)
const SEGMENTS := [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]

var left_name := "YOU"
var right_name := "OPP"
var _scores := [0, 0]
var _previous := [0, 0]
var _roll := [1.0, 1.0]               # 0..1 progress of the digit roll per team
var _flash := [0.0, 0.0]              # seconds left of the box flash per team
var serving_team := -1
var server_number := 0                # 1 or 2 in doubles, 0 hides the LED

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel font and pixel dots
	set_process(false)

func set_scores(left: int, right: int, animate: bool = true) -> void:
	var next := [left, right]
	for team in 2:
		if int(next[team]) != int(_scores[team]):
			_previous[team] = _scores[team]
			_scores[team] = next[team]
			if animate and is_visible_in_tree():
				_roll[team] = 0.0
				_flash[team] = FLASH_SECONDS
			else:
				_roll[team] = 1.0
	set_process(_animating())
	queue_redraw()

func set_server(team: int, number: int) -> void:
	if team == serving_team and number == server_number: return
	serving_team = team; server_number = number
	queue_redraw()

func set_names(left: String, right: String) -> void:
	if left == left_name and right == right_name: return
	left_name = left; right_name = right
	queue_redraw()

func is_animating() -> bool:
	return _animating()

func _animating() -> bool:
	return _roll[0] < 1.0 or _roll[1] < 1.0 or _flash[0] > 0.0 or _flash[1] > 0.0

func _process(delta: float) -> void:
	for team in 2:
		_roll[team] = minf(1.0, _roll[team] + delta / ROLL_SECONDS)
		_flash[team] = maxf(0.0, _flash[team] - delta)
	queue_redraw()
	if not _animating(): set_process(false)

## Screen pixels per UI pixel at this board size (3 on the 92-tall phone board).
func _unit() -> float:
	return maxf(1.0, roundf(size.y / 30.0))

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0: return
	var u := _unit()
	PixelDraw.plate_rid(get_canvas_item(), Rect2(Vector2.ZERO, size), UiTheme.PANEL, u, 2, true)
	var pad := roundf(h * 0.1 / u) * u
	var mid := roundf(w * 0.5)
	var box_w := roundf((w - pad * 3.0) * 0.5)
	for team in 2:
		var x := pad if team == 0 else mid + roundf(pad * 0.5)
		_team_box(team, Rect2(x, pad, box_w, h - pad * 2.0), u)
	# Centre colon LEDs: square pixels.
	for y in [h * 0.42, h * 0.62]:
		draw_rect(Rect2(Vector2(mid - u, roundf(y) - u), Vector2(u, u) * 2.0), LED * Color(1, 1, 1, 0.8))

func _team_box(team: int, rect: Rect2, u: float) -> void:
	var color := BLUE if team == 0 else RED
	var flash: float = _flash[team] / FLASH_SECONDS
	var face := Color("06090d").lerp(color.darkened(0.55), 0.55 * flash)
	PixelDraw.plate_rid(get_canvas_item(), rect, face, u, 0, false, color.darkened(0.25).lerp(color.lightened(0.4), flash))
	# Team name strip on the outer side, server dot on the inner side (pixel font, 2x on the phone).
	var font := UiTheme.pixel_font()
	var name_size := UiTheme.pixel_size(rect.size.y * 0.22)
	var k := float(name_size) / UiTheme.PIXEL_UNIT   # font pixels per glyph pixel (5x7 capitals)
	var caps_top := rect.position.y + u * 2.0        # inside the rim, one UI pixel gap
	var baseline := roundf(caps_top + font.get_ascent(name_size) - k)
	var label: String = left_name if team == 0 else right_name
	var label_x := rect.position.x + u * 3.0 if team == 0 else rect.end.x - u * 3.0 - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	draw_string(font, Vector2(roundf(label_x), baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, color.lightened(0.15))
	if serving_team == team:
		var dot_c := Vector2(rect.end.x - rect.size.y * 0.16 if team == 0 else rect.position.x + rect.size.y * 0.16, rect.position.y + rect.size.y * 0.2)
		PixelDraw.disc(self, dot_c, maxf(2.0 * u, rect.size.y * 0.075), u, Color("d8ff5a"), Color(0, 0, 0, 0), 1, false)
		if server_number > 0:
			var n := str(server_number)
			var nx := dot_c.x - rect.size.y * 0.16 - u - font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x if team == 0 else dot_c.x + rect.size.y * 0.14
			draw_string(font, Vector2(roundf(nx), baseline), n, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color("d8ff5a"))
	# Two digits under the name row (one UI pixel gap) down to two UI pixels above the
	# box bottom; digits roll vertically on change.
	var digit_top := roundf(caps_top + 7.0 * k + u)
	var digit_h := maxf(4.0, rect.end.y - u * 2.0 - digit_top)
	var digit_w := digit_h * 0.55
	var gap := digit_w * 0.28
	var total := digit_w * 2.0 + gap
	var origin := Vector2(rect.position.x + (rect.size.x - total) * 0.5, digit_top)
	var clip := Rect2(origin - Vector2(2, 2), Vector2(total + 4, digit_h + 4))
	var t: float = _roll[team]
	var ease_t: float = 1.0 - pow(1.0 - t, 3.0)
	var now: int = clampi(int(_scores[team]), 0, 99)
	var before: int = clampi(int(_previous[team]), 0, 99)
	var flicker: bool = t < 1.0 or (_flash[team] > 0.0 and int(_flash[team] * 14.0) % 2 == 0 and _flash[team] > FLASH_SECONDS * 0.55)
	for place in 2:
		var at := origin + Vector2(place * (digit_w + gap), 0.0)
		var new_digit: int = (now / 10) if place == 0 else (now % 10)
		var old_digit: int = (before / 10) if place == 0 else (before % 10)
		var blank_new: bool = place == 0 and now < 10
		var blank_old: bool = place == 0 and before < 10
		_digit(at, digit_w, digit_h, -1, 0.0, clip, false)   # ghost segments
		if t < 1.0 and (new_digit != old_digit or blank_new != blank_old):
			if not blank_old: _digit(at - Vector2(0, digit_h * ease_t), digit_w, digit_h, old_digit, 1.0 - ease_t, clip, false)
			if not blank_new: _digit(at + Vector2(0, digit_h * (1.0 - ease_t)), digit_w, digit_h, new_digit, ease_t, clip, true)
		elif not blank_new:
			_digit(at, digit_w, digit_h, new_digit, 0.75 if flicker else 1.0, clip, _flash[team] > 0.0)

## One 7-segment digit; value -1 draws the unlit ghost segments. Segments outside
## `clip` (vertically) are skipped so the roll looks like a window.
func _digit(at: Vector2, w: float, h: float, value: int, alpha: float, clip: Rect2, hot: bool) -> void:
	var t := w * 0.18                # segment thickness
	var half := h * 0.5
	var bits: int = 0x7F if value < 0 else SEGMENTS[value]
	var color: Color = GHOST if value < 0 else (LED.lerp(LED_HOT, 0.45) if hot else LED)
	color.a *= alpha if value >= 0 else 1.0
	var segs := [
		Rect2(at.x + t * 0.6, at.y, w - t * 1.2, t),                       # a
		Rect2(at.x + w - t, at.y + t * 0.6, t, half - t * 0.9),            # b
		Rect2(at.x + w - t, at.y + half + t * 0.3, t, half - t * 0.9),     # c
		Rect2(at.x + t * 0.6, at.y + h - t, w - t * 1.2, t),               # d
		Rect2(at.x, at.y + half + t * 0.3, t, half - t * 0.9),             # e
		Rect2(at.x, at.y + t * 0.6, t, half - t * 0.9),                    # f
		Rect2(at.x + t * 0.6, at.y + half - t * 0.5, w - t * 1.2, t),      # g
	]
	for i in 7:
		if bits & (1 << i) == 0: continue
		var seg: Rect2 = segs[i]
		var top := maxf(seg.position.y, clip.position.y)
		var bottom := minf(seg.end.y, clip.end.y)
		if bottom <= top: continue
		# Whole-pixel segments, hard edges (no glow halo).
		var x0 := roundf(seg.position.x)
		var y0 := roundf(top)
		draw_rect(Rect2(x0, y0, maxf(1.0, roundf(seg.end.x) - x0), maxf(1.0, roundf(bottom) - y0)), color)
