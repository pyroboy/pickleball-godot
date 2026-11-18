extends SceneTree
func _initialize() -> void:
	var totals: Dictionary = {"pass":0,"fail":0,"errors":[]}
	preload("res://scripts/tests/test_serve_styles.gd").new().run_all(totals)
	for error in totals.errors: push_error(error)
	print("SERVE STYLES: %d passed, %d failed" % [totals.pass,totals.fail])
	quit(0 if totals.fail==0 else 1)
