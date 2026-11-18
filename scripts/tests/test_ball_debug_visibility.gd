extends SceneTree
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var ball = game.ball
	check( not ball.spin_debug_visible, "spin debug disabled by default")
	check(ball._equator_marker == null or not ball._equator_marker.visible, "normal yellow ball has no red dot")
	var radius: float = ball.BALL_RADIUS
	game._set_debug_visuals_visible(true)
	check(ball.spin_debug_visible, "debug enables spin display")
	check(ball._equator_marker != null and ball._equator_marker.visible, "red marker exists only in debug")
	check(ball._equator_marker_2 != null and ball._equator_marker_2.visible, "second debug marker enabled")
	game._set_debug_visuals_visible(false)
	check( not ball._equator_marker.visible and not ball._equator_marker_2.visible, "normal mode hides equator markers")
	check( not ball._spin_axis_node.visible, "normal mode hides spin axis")
	check(ball.BALL_RADIUS == radius, "debug toggle never changes ball geometry")
	game.queue_free()
	await process_frame
	print("BALL DEBUG VISIBILITY: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
