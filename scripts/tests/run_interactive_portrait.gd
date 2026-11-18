extends SceneTree


func _initialize() -> void : call_deferred("start")
func start() -> void :
	root.content_scale_size = Vector2i(720, 1560)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(432, 936)
	var scene = load("res://scenes/title.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	print("INTERACTIVE PORTRAIT canvas=", root.get_visible_rect(), " window=", root.size)
