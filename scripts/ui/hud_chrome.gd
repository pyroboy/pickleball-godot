extends Control



enum Kind{SCOREBOARD, GUIDANCE, GUIDE, PAUSE, PILL, SKIP}

const ICE: = Color("eaf4ff")
const BLUE: = Color("4eb8ff")
const RED: = Color("ff6278")

var kind: Kind = Kind.SCOREBOARD
var serving_team: int = -1:
	set(value):
		if serving_team == value: return
		serving_team = value
		queue_redraw()

## PILL: team shown first (the server's side, drawn with a ring) and the other team after it.
var first_team: int = 0:
	set(value):
		if first_team == value: return
		first_team = value
		queue_redraw()

var guidance_details: = true:
	set(value):
		if guidance_details == value: return
		guidance_details = value
		queue_redraw()

func _ready() -> void :
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void :
	match kind:
		Kind.SCOREBOARD: _draw_scoreboard()
		Kind.GUIDANCE: _draw_guidance()
		Kind.GUIDE:
			draw_set_transform(size * 0.5, 0.0, Vector2.ONE * minf(size.x, size.y) / 42.0)
			_draw_book()
		Kind.PAUSE:
			draw_set_transform(size * 0.5, 0.0, Vector2.ONE * minf(size.x, size.y) / 42.0)
			draw_style_box(_rounded_fill(ICE, 2), Rect2(-10, -14, 6, 28))
			draw_style_box(_rounded_fill(ICE, 2), Rect2(4, -14, 6, 28))
		Kind.PILL: _draw_pill()
		Kind.SKIP:
			draw_set_transform(size * 0.5, 0.0, Vector2.ONE * minf(size.x, size.y) / 42.0)
			for dx in [-11.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([Vector2(dx, -12), Vector2(dx + 11, 0), Vector2(dx, 12)]), ICE)
	draw_set_transform(Vector2.ZERO)

func _draw_pill() -> void :
	# Team colour dots at both ends of the score pill; the server's dot wears a ring.
	var r: = size.y * 0.2
	var left_color: = BLUE if first_team == 0 else RED
	var right_color: = RED if first_team == 0 else BLUE
	var left_at: = Vector2(size.y * 0.5, size.y * 0.5)
	var right_at: = Vector2(size.x - size.y * 0.5, size.y * 0.5)
	draw_circle(left_at, r + 3.0, ICE, false, 2.0, false)
	draw_circle(left_at, r, left_color, true, -1, false)
	draw_circle(right_at, r, right_color, true, -1, false)

func _draw_scoreboard() -> void :
	var w: = size.x
	var h: = size.y
	var s: = h / 104.0
	var outer: = PackedVector2Array([
		Vector2(16 * s, 1 * s), Vector2(w * 0.19, 1 * s), Vector2(w * 0.2, 4 * s), 
		Vector2(w * 0.8, 4 * s), Vector2(w * 0.81, 1 * s), Vector2(w - 16 * s, 1 * s), 
		Vector2(w - 1 * s, 14 * s), Vector2(w - 1 * s, h - 20 * s), Vector2(w - 15 * s, h - 7 * s), 
		Vector2(w * 0.67, h - 7 * s), Vector2(w * 0.655, h - 1 * s), Vector2(w * 0.345, h - 1 * s), 
		Vector2(w * 0.33, h - 7 * s), Vector2(15 * s, h - 7 * s), Vector2(1 * s, h - 20 * s), Vector2(1 * s, 14 * s)
	])
	draw_colored_polygon(outer, Color("112237"))
	_outline(outer, Color("4a6c90"), 1.5 * s)
	var left: = PackedVector2Array([
		Vector2(12 * s, 20 * s), Vector2(21 * s, 11 * s), Vector2(w * 0.26, 11 * s), 
		Vector2(w * 0.331, h - 16 * s), Vector2(21 * s, h - 16 * s), Vector2(12 * s, h - 25 * s)
	])
	draw_polygon(left, PackedColorArray([
		Color("123154"), Color("15365e"), Color("21518a"), 
		Color("24588f"), Color("153659"), Color("133153")
	]))
	_outline(left, Color("328cd9"), 1.7 * s)
	var right: = PackedVector2Array()
	for point in left: right.append(Vector2(w - point.x, point.y))
	draw_polygon(right, PackedColorArray([
		Color("3c2639"), Color("432d40"), Color("7b3549"), 
		Color("843749"), Color("4e2c3e"), Color("432838")
	]))
	_outline(right, Color("d95168"), 1.7 * s)
	draw_line(Vector2(w * 0.18, 7 * s), Vector2(w * 0.26, 7 * s), BLUE, 3 * s, true)
	draw_line(Vector2(w * 0.74, 7 * s), Vector2(w * 0.82, 7 * s), RED, 3 * s, true)
	draw_line(Vector2(w * 0.365, h - 1 * s), Vector2(w * 0.635, h - 1 * s), Color("34617f"), s, true)
	if serving_team != 0: _draw_player(Vector2(50 * s, 52 * s), s, BLUE)
	if serving_team != 1: _draw_player(Vector2(w - 50 * s, 52 * s), s, RED)

func _draw_player(origin: Vector2, scale_factor: float, tint: Color) -> void :
	draw_set_transform(origin, 0, Vector2.ONE * scale_factor)
	draw_circle(Vector2(0, -12), 10, tint, true, -1, true)
	draw_arc(Vector2(0, -12), 10, PI, TAU, 16, tint.lightened(0.3), 1, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-20, 24), Vector2(-20, 17), Vector2(-17, 10), Vector2(-12, 5), 
		Vector2(-6, 2), Vector2(6, 2), Vector2(12, 5), Vector2(17, 10), 
		Vector2(20, 17), Vector2(20, 24)
	]), tint)
	draw_set_transform(Vector2.ZERO)

func _draw_guidance() -> void :
	var s: = size.y / 148.0
	var edge: = PackedVector2Array([
		Vector2(10 * s, 1 * s), Vector2(size.x - 10 * s, 1 * s), Vector2(size.x - 1 * s, 10 * s), 
		Vector2(size.x - 1 * s, size.y - 10 * s), Vector2(size.x - 10 * s, size.y - 1 * s), 
		Vector2(12 * s, size.y - 1 * s), Vector2(1 * s, size.y - 12 * s), Vector2(1 * s, 10 * s)
	])
	draw_colored_polygon(edge, Color(0.065, 0.12, 0.2, 0.92))
	_outline(edge, Color(0.31, 0.41, 0.54, 0.75), s)
	if guidance_details:
		for row in [49, 98]:
			draw_line(Vector2(63 * s, row * s), Vector2(size.x - 17 * s, row * s), Color("3e536c"), s, true)
	draw_set_transform(Vector2(31 * s, 25 * s), 0, Vector2.ONE * s)
	_draw_paddle()
	if guidance_details:
		draw_set_transform(Vector2(31 * s, 74 * s), 0, Vector2.ONE * s)
		_draw_rotate()
		draw_set_transform(Vector2(31 * s, 124 * s), 0, Vector2.ONE * s)
		_draw_aim()
	draw_set_transform(Vector2.ZERO)

func _draw_paddle() -> void :
	var edge: = PackedVector2Array([
		Vector2(-5, -16), Vector2(4, -19), Vector2(13, -16), Vector2(17, -9), 
		Vector2(16, -2), Vector2(3, 10), Vector2(-3, 10), Vector2(-16, 23), 
		Vector2(-20, 19), Vector2(-8, 6), Vector2(-8, 0), Vector2(-10, -7)
	])
	_outline(edge, ICE, 2.2)
	for offset in [-5, 0, 5]:
		draw_line(Vector2(-3 + offset, 3), Vector2(10 + offset * 0.6, -10), Color("a9c7e7"), 1.5, true)
	draw_line(Vector2(-14, 15), Vector2(-12, 17), ICE, 2, true)

func _draw_rotate() -> void :
	draw_arc(Vector2.ZERO, 15, - PI * 0.52, PI * 1.08, 28, ICE, 3, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-2, -22), Vector2(-11, -14), Vector2(-1, -9)]), ICE)

func _draw_aim() -> void :
	draw_arc(Vector2.ZERO, 14, 0, TAU, 32, ICE, 2.5, true)
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(direction * 10, direction * 20, ICE, 2.5, true)

func _draw_book() -> void :
	draw_polyline(PackedVector2Array([
		Vector2(0, -10), Vector2(-5, -14), Vector2(-12, -15), Vector2(-18, -12), 
		Vector2(-18, 12), Vector2(-11, 10), Vector2(-5, 11), Vector2(0, 14), 
		Vector2(5, 11), Vector2(11, 10), Vector2(18, 12), Vector2(18, -12), 
		Vector2(12, -15), Vector2(5, -14), Vector2(0, -10), Vector2(0, 14)
	]), ICE, 2.3, true)

func _outline(points: PackedVector2Array, color: Color, line_width: float) -> void :
	var closed: = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, line_width, true)

func _rounded_fill(color: Color, radius: int) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
