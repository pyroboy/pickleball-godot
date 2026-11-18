extends RefCounted


const COLUMN: = Vector2(0.417110649305134, 0.620205599438965)
const CONTACT: = Vector3(COLUMN.x, - 0.3, COLUMN.y)
const VOLLEY_HOLD_Y: = 0.25
const DROP_HOLD_Y: = 0.45
static func hold_offset(drop: bool) -> Vector3:
	return Vector3(COLUMN.x, DROP_HOLD_Y if drop else VOLLEY_HOLD_Y, COLUMN.y)
