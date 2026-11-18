extends RefCounted



static func drain(tree: SceneTree) -> void :
	await tree.process_frame
	await tree.process_frame
	var deadline: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < deadline:
		OS.delay_msec(5)
		await tree.process_frame
	await tree.process_frame
	await tree.process_frame
