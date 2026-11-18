extends SceneTree

func _initialize() -> void : call_deferred("run")
func run() -> void :
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title);current_scene = title
	await process_frame
	create_timer(0.5, true).timeout.connect( func(): push_error("Native title Back did not quit");quit(1))
	print("TITLE NATIVE BACK: dispatching expected clean exit")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
