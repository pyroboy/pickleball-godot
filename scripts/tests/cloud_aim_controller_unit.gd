extends SceneTree
## Standalone adapter for the unchanged existing aim-controller unit suite.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var totals := {"pass": 0, "fail": 0, "errors": []}
	preload("res://scripts/tests/test_aim_controller.gd").new().run_all(totals)
	for error in totals.errors:
		push_error(str(error))
	print("CLOUD AIM CONTROLLER UNIT: %d cases, %d failures" % [totals.pass + totals.fail, totals.fail])
	await process_frame
	quit(0 if totals.fail == 0 else 1)
