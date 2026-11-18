extends SceneTree
## SceneTree adapter for the existing RefCounted rally-rule unit suite.
func _initialize()->void:call_deferred("run")
func run()->void:
	var totals:Dictionary={"pass":0,"fail":0,"errors":[]}
	preload("res://scripts/tests/test_rally_scorer.gd").new().run_all(totals)
	print("RALLY SCORER UNIT: %d cases, %d failures"%[totals.pass,totals.fail])
	for error in totals.errors:push_error(str(error))
	await process_frame;await process_frame;quit(0 if totals.fail==0 else 1)
