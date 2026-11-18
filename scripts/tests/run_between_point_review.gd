extends SceneTree
func _initialize() -> void : call_deferred("_run")
func _run() -> void :
	var scene = load("res://scenes/between_point_review.tscn").instantiate()
	if scene.get_script() == null:
		quit(2)
		return
	root.add_child(scene)
	current_scene = scene
