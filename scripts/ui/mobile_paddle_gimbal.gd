extends Control
## Large independent axis rings. Rings remain usable at Euler singularities and
## cross the -180/180 seam continuously; the inset shows the resolved paddle.
signal rotation_dragged(axis: int, degrees: float)
const COLORS := [Color("ff8c8c"), Color("81e4b1"), Color("86bfff")]
const NAMES := ["Pitch / Tilt", "Yaw / Turn", "Roll / Twist"]
var angles := Vector3.ZERO
var resolved_angles := Vector3.ZERO
var grip_spin := 0.0
var active_axis := 0
var ui_scale := 1.0
var _dragging := false
var _touch := -1
var _last_angle := 0.0
var _last_point := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)

func set_angles(value: Vector3, resolved: Vector3, in_hand_degrees: float = 0.0) -> void:
	angles = value; resolved_angles = resolved; grip_spin=in_hand_degrees; queue_redraw()

func select_axis(axis: int) -> void:
	active_axis = clampi(axis, 0, 2); queue_redraw()

func cancel_gesture() -> void:
	_dragging = false; _touch = -1; queue_redraw()

func center() -> Vector2:
	return Vector2(size.x * .5, size.y * .48)

func radius(axis: int) -> float:
	return minf(size.x * .42, size.y * .40) - float(axis) * 30.0 * ui_scale

func ring_point(axis: int, degrees: float) -> Vector2:
	return center() + Vector2.from_angle(deg_to_rad(degrees) - PI * .5) * radius(axis)

func _draw() -> void:
	var middle := center()
	for axis in range(3):
		var r := radius(axis)
		if r < 8: continue
		draw_arc(middle, r, 0, TAU, 96, COLORS[axis].darkened(.6), 12 * ui_scale, true)
		draw_arc(middle, r, 0, TAU, 96, COLORS[axis], (4.5 if axis == active_axis else 2.5) * ui_scale, true)
		for tick in range(12):
			var direction := Vector2.from_angle(float(tick) * TAU / 12.0 - PI * .5)
			draw_line(middle + direction * (r - 5 * ui_scale), middle + direction * (r + 5 * ui_scale), COLORS[axis], 1.5 * ui_scale, true)
		var point := ring_point(axis, wrapf(angles[axis], -180, 180))
		draw_circle(point, (12 if axis == active_axis else 9) * ui_scale, COLORS[axis])
		if axis == active_axis: draw_arc(point, 15 * ui_scale, 0, TAU, 32, Color.WHITE, 2 * ui_scale, true)
	# This is an orientation inset, never an independent transform/IK system.
	var a := resolved_angles * PI / 180.0
	var basis := Basis(Vector3.RIGHT, a.x) * Basis(Vector3.UP, a.y) * Basis(Vector3.FORWARD, a.z) * Basis(Vector3.UP,deg_to_rad(grip_spin))
	var polygon := PackedVector2Array()
	for i in range(24):
		var t := float(i) * TAU / 24.0
		polygon.append(middle + _project(basis * Vector3(cos(t) * 18, 16 + sin(t) * 24, 0)) * ui_scale)
	draw_colored_polygon(polygon, Color("f3d96b"))
	polygon.append(polygon[0]); draw_polyline(polygon, Color.WHITE, 1.5 * ui_scale, true)
	draw_line(middle + _project(basis * Vector3(0,-6,0)) * ui_scale, middle + _project(basis * Vector3(0,-37,0)) * ui_scale, Color("dfb68c"), 7 * ui_scale, true)
	var font := get_theme_default_font()
	var legend: String = "Pitch / Tilt     Yaw / Turn     Roll / Twist"
	draw_string(font,Vector2((size.x-font.get_string_size(legend,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(20*ui_scale)).x)*.5,20*ui_scale),legend,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(20*ui_scale),Color("c6d8e1"))
	var caption: String = NAMES[active_axis] + " · drag ring · full turns wrap"
	draw_string(font, Vector2((size.x-font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(20*ui_scale)).x)*.5,size.y-9*ui_scale),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(20*ui_scale),COLORS[active_axis])

func _project(point: Vector3) -> Vector2:
	return Vector2(point.x + point.z * .42, -point.y + point.z * .24)

func _begin(point: Vector2) -> void:
	var distance := point.distance_to(center())
	var nearest := active_axis
	var best := INF
	for axis in range(3):
		var gap := absf(distance - radius(axis))
		if gap < best: best = gap; nearest = axis
	if best > 24 * ui_scale: return
	active_axis = nearest; _dragging = true; _last_angle = (point-center()).angle(); _last_point = point; grab_focus(); queue_redraw()

func _move(point: Vector2) -> void:
	if not _dragging or point.distance_to(center()) < 10 * ui_scale: return
	var angle := (point-center()).angle()
	var delta := rad_to_deg(wrapf(angle-_last_angle,-PI,PI))
	_last_angle = angle; _last_point = point
	if absf(delta) > .00001: rotation_dragged.emit(active_axis,delta)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0:
			_begin(event.position)
			if _dragging: _touch = event.index
		elif not event.pressed and event.index == _touch: cancel_gesture()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		_move(event.position); accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _touch >= 0: return
		if event.pressed: _begin(event.position)
		else: cancel_gesture()
		accept_event()
	elif event is InputEventMouseMotion and _dragging and _touch < 0:
		_move(event.position); accept_event()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: cancel_gesture(); accept_event()
		elif event.keycode in [KEY_LEFT,KEY_RIGHT]:
			rotation_dragged.emit(active_axis, (-1.0 if event.keycode==KEY_LEFT else 1.0) * (.1 if event.shift_pressed else 1.0)); accept_event()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_VISIBILITY_CHANGED]: cancel_gesture()
