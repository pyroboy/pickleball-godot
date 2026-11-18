extends RefCounted


const COLUMN: = Vector2(0.417110649305134, 0.620205599438965)
const CONTACT: = Vector3(COLUMN.x, - 0.3, COLUMN.y)
# Ball hold heights above the player origin (~0.92 m above the court). Real underhand
# serves hold the ball at about waist height for a volley serve and chest height for a drop.
const VOLLEY_HOLD_Y: = 0.05
const DROP_HOLD_Y: = 0.25
static func hold_offset(drop: bool) -> Vector3:
	return Vector3(COLUMN.x, DROP_HOLD_Y if drop else VOLLEY_HOLD_Y, COLUMN.y)
