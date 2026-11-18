extends RefCounted



static func finish(tree: SceneTree, game: Node, observer: Node = null) -> void :
	if is_instance_valid(observer): observer.queue_free()
	if is_instance_valid(game): game.queue_free()
	await tree.process_frame
	await tree.process_frame
	var deadline: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < deadline:
		OS.delay_msec(5)
		await tree.process_frame
	await tree.process_frame
