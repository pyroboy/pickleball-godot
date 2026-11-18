extends Control
## A drawn pickleball avoids emoji/font differences on Android.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	draw_circle(center + Vector2(0, radius * 0.10), radius + 1.0, Color("07131f"), true, -1, true)
	draw_circle(center, radius, Color("e5f45b"), true, -1, true)
	draw_arc(center, radius, PI * 1.1, PI * 1.75, 20, Color("fbffbc"), maxf(1.0, radius * 0.09), true)
	for offset in [Vector2.ZERO, Vector2(-0.48, -0.34), Vector2(0.40, -0.42), Vector2(-0.36, 0.45), Vector2(0.46, 0.32)]:
		draw_circle(center + offset * radius, radius * 0.14, Color("62751b"), true, -1, true)
