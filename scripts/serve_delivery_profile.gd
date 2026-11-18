extends RefCounted


const COLUMN: = Vector2(0.417110649305134, 0.620205599438965)
const CONTACT: = Vector3(COLUMN.x, - 0.3, COLUMN.y)
# Ball hold heights above the player origin (~0.92 m above the court). Real underhand
# serves hold the ball at about waist height for a volley serve and chest height for a drop.
const VOLLEY_HOLD_Y: = 0.05
const DROP_HOLD_Y: = 0.25
# Per-style ball column (x = forehand side, y = toward the net), so each serve meets the ball
# where real players do: Flat just in front; Topspin and Drop Drive further out front; Slice
# and Banana a little wider (brush the outside / across); Screwball closer (brush the inside);
# High Soft later, nearer full extension. Order: ServeStyle.Style.
const STYLE_COLUMNS: = [
	COLUMN,                     # Flat
	Vector2(0.40, 0.68),        # Topspin
	Vector2(0.47, 0.64),        # Slice
	Vector2(0.45, 0.57),        # High Soft
	Vector2(0.41, 0.68),        # Drop Drive
	Vector2(0.46, 0.64),        # Banana
	Vector2(0.36, 0.64),        # Screwball
]

static func hold_offset(drop: bool, style: int = -1) -> Vector3:
	var column: Vector2 = STYLE_COLUMNS[style] if style >= 0 and style < STYLE_COLUMNS.size() else COLUMN
	return Vector3(column.x, DROP_HOLD_Y if drop else VOLLEY_HOLD_Y, column.y)
