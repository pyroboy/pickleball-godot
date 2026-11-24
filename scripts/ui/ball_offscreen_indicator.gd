extends CanvasLayer
## First-person view (gameplay_camera.gd FIRST_PERSON): when the ball is out of view, an arrow
## at the screen edge points to where it is. It grows and brightens as the ball gets closer, and
## pulses when the ball is coming toward you. Hidden while the ball is on screen or not in play.
## Visual only. Paused with the match (no process override).

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")

const EDGE_INSET := 46.0        # px from the safe screen edge (at a 1080-tall screen)
const NEAR_M := 2.0             # full size and brightness from here in
const FAR_M := 14.0             # smallest and faintest from here out
const SIZE_NEAR := 34.0
const SIZE_FAR := 18.0
const PULSE_HZ := 3.0

var camera: Camera3D
var ball: Node3D
var player: Node3D
var showing := false            # read by tests
var edge_point := Vector2.INF   # read by tests
var _canvas: Control

func _ready() -> void:
	layer = 60
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_indicator)
	add_child(_canvas)

func _process(_delta: float) -> void:
	_canvas.queue_redraw()

func _ball_point() -> Vector3:
	return ball.get_global_transform_interpolated().origin

func _draw_indicator() -> void:
	showing = false
	edge_point = Vector2.INF
	if not is_instance_valid(camera) or not is_instance_valid(ball) or not camera.current: return
	if "is_in_play" in ball and not ball.is_in_play: return
	var size: Vector2 = _canvas.get_viewport_rect().size
	var at: Vector3 = _ball_point()
	var behind: bool = camera.is_position_behind(at)
	var screen: Vector2 = camera.unproject_position(at)
	if not behind and Rect2(Vector2.ZERO, size).has_point(screen): return
	# Direction from the screen centre, in the camera's own frame (works behind the camera too).
	var local: Vector3 = camera.global_basis.inverse() * (at - camera.global_position)
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001: dir = Vector2.DOWN
	dir = dir.normalized()
	var scale: float = size.y / 1080.0
	var safe: Rect2 = Layout.safe_rect(get_viewport())
	var box: Rect2 = safe.grow(-EDGE_INSET * scale)
	var centre: Vector2 = box.get_center()
	# Where the ray from the centre leaves the inset box.
	var tx: float = (box.size.x * 0.5) / maxf(absf(dir.x), 1e-4)
	var ty: float = (box.size.y * 0.5) / maxf(absf(dir.y), 1e-4)
	var point: Vector2 = centre + dir * minf(tx, ty)
	var distance: float = camera.global_position.distance_to(at)
	var near: float = 1.0 - clampf((distance - NEAR_M) / (FAR_M - NEAR_M), 0.0, 1.0)
	var coming: bool = false
	if "linear_velocity" in ball and is_instance_valid(player):
		coming = Vector3(ball.linear_velocity).dot(player.global_position - at) > 0.0
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * PULSE_HZ) if coming else 0.0
	var arrow: float = lerpf(SIZE_FAR, SIZE_NEAR, near) * scale * (1.0 + 0.15 * pulse)
	var color := Color("dfff4f")   # the ball's yellow-green
	color.a = lerpf(0.55, 0.95, near)
	var side := Vector2(-dir.y, dir.x)
	var tip: Vector2 = point + dir * arrow * 0.6
	var back: Vector2 = point - dir * arrow * 0.5
	var shape := PackedVector2Array([tip, back + side * arrow * 0.55, back - side * arrow * 0.55])
	var shadow := PackedVector2Array()
	for p in shape: shadow.append(p + Vector2(2, 2) * scale)
	_canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.45 * color.a))
	_canvas.draw_colored_polygon(shape, color)
	# The ball itself, just inside the arrow, with a ring when it is coming at you.
	var dot: Vector2 = back - dir * arrow * 0.45
	_canvas.draw_circle(dot, arrow * 0.22, color)
	if coming: _canvas.draw_arc(dot, arrow * (0.35 + 0.2 * pulse), 0.0, TAU, 20, Color(color, color.a * (1.0 - pulse)), 2.0 * scale)
	showing = true
	edge_point = point
