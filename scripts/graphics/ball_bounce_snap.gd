extends Node
## Draws the ball touching the floor on a bounce (visual only).
## Physics runs at 30 Hz with interpolation; a bounce lands between two ticks, so the
## interpolated ball turned around ~12 cm above the court and never met its shadow,
## while the bounce burst/decal appeared on the floor beside it. This node drives the
## ball's visual children (mesh, halo) itself: normally at the interpolated transform,
## and for the first rendered frame after a bounce exactly at the contact point.
## The physics body, its collision and every gameplay read are untouched.
## Other visuals read the same drawn position from ball.get_meta("render_origin").

var _ball: RigidBody3D
var _parts: Array = []          # [GeometryInstance3D, local Transform3D]
var _snap: = Vector3.INF        # contact point to show on the next rendered frame

static func attach(ball: RigidBody3D) -> Node:
	var node: = (load("res://scripts/graphics/ball_bounce_snap.gd") as GDScript).new() as Node
	node.name = "BallBounceSnap"
	node.set("_ball", ball)
	ball.add_child(node)
	return node

func _ready() -> void:
	process_priority = -100   # before the trail and shadows read render_origin
	for child in _ball.get_children():
		if child is GeometryInstance3D:
			_parts.append([child, child.transform])
			child.top_level = true
			child.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The signal reports the court-surface height; the ball rests a radius above it.
	_ball.bounced.connect(func(point: Vector3) -> void:
		_snap = Vector3(point.x, maxf(point.y, Ball.FLOOR_Y + Ball.BALL_RADIUS), point.z))

func _process(_delta: float) -> void:
	if not is_instance_valid(_ball): return
	var xf: = _ball.get_global_transform_interpolated()
	if get_tree().paused: xf = _ball.global_transform
	if _snap != Vector3.INF:
		xf.origin = _snap
		_snap = Vector3.INF
	_ball.set_meta("render_origin", xf.origin)
	for part in _parts:
		var node: GeometryInstance3D = part[0]
		if is_instance_valid(node): node.global_transform = xf * part[1]
