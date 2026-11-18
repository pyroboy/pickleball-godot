extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var totals = {"pass": 0, "fail": 0, "errors": []}
	for path in ["test_body_proportions.gd", "test_incoming_ready_motion.gd", "test_paddle_clearance.gd", "test_drive_serve_motion.gd", "test_serve_styles.gd"]:
		load("res://scripts/tests/" + path).new().run_all(totals)
	print("BODY/MOTION GATES: ", totals.pass, " pass, ", totals.fail, " failed")
	for error in totals.errors: print(error)
	quit(0 if totals.fail == 0 else 1)
