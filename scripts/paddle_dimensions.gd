extends RefCounted




const LENGTH: = 0.4191
const WIDTH: = 0.1905
const THICKNESS: = 0.016
const HANDLE_LENGTH: = 0.1397
const GRIP_CIRCUMFERENCE: = 0.10795
const HANDLE_RADIUS: = GRIP_CIRCUMFERENCE / TAU
const HEAD_LENGTH: = LENGTH - HANDLE_LENGTH
const HEAD_RADIUS: = WIDTH * 0.5
const HEAD_SPINE_HALF: = (HEAD_LENGTH - WIDTH) * 0.5
const HEAD_CENTER_Y: = HANDLE_LENGTH + HEAD_LENGTH * 0.5
const HEAD_HALF_THICKNESS: = THICKNESS * 0.5
const HEAD_OFFSET: = Vector3(0, HEAD_CENTER_Y, 0)
const HANDLE_CENTER_Y: = HANDLE_LENGTH * 0.5
const MAIN_GRIP_Y: = 0.055
const SUPPORT_GRIP_Y: = 0.11
const MAIN_GRIP_OFFSET: = Vector3(0, MAIN_GRIP_Y, 0)
const SUPPORT_GRIP_OFFSET: = Vector3(0, SUPPORT_GRIP_Y, 0)
const HEAD_BOTTOM_Y: = HANDLE_LENGTH
const HEAD_TOP_Y: = LENGTH
const OUTLINE_ARC_STEPS: = 16

static func head_outline() -> PackedVector2Array:
	var points: = PackedVector2Array()
	for cap in [1.0, -1.0]:
		for index in range(OUTLINE_ARC_STEPS + 1):
			var angle: float = PI * float(index) / OUTLINE_ARC_STEPS + (0.0 if cap > 0.0 else PI)
			points.append(Vector2(cos(angle) * HEAD_RADIUS, HEAD_CENTER_Y + cap * HEAD_SPINE_HALF + sin(angle) * HEAD_RADIUS))
	return points

static func head_hull_points() -> PackedVector3Array:
	var points: = PackedVector3Array()
	for point in head_outline():
		for z in [ - HEAD_HALF_THICKNESS, HEAD_HALF_THICKNESS]:
			points.append(Vector3(point.x, point.y, z))
	return points
