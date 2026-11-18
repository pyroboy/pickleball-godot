extends "res://scripts/tests/author_serve_neutral_endpoints.gd"
const Dimensions = preload("res://scripts/player_body_dimensions.gd")
func vision_margin(p) -> float:
	var head: Node3D = p.body_pivot.get_node("TorsoMesh/HeadMesh")
	var forward: Vector3 = p._get_forward_axis(); var facing: = Basis(forward.cross(Vector3.UP), Vector3.UP, - forward)
	var scale: = Vector3(Dimensions.HEAD_RADIUS / 0.089, Dimensions.HEAD_HEIGHT / 0.24, Dimensions.HEAD_RADIUS / 0.089)
	var direction: Vector3 = head.global_basis * facing * Vector3.FORWARD
	var tx: Transform3D = p.paddle_node.global_transform.affine_inverse(); var nearest: = INF
	for side in [-1.0, 1.0]:
		var eye: Vector3 = Vector3(side * 0.033, 0.022, - 0.0735) + (Basis(Vector3.UP, - side * 0.38) * Vector3.FORWARD) * 0.0055
		var pupil: Vector3 = head.global_transform * (facing * (eye * scale))
		for step in range(101): nearest = minf(nearest, Paddle.distance_to_paddle_shape(tx * (pupil + direction * step * 0.01)))
	return nearest
func run():
	source_phase = "READY";output = "/workspace/shared/pickleball-hands/one-hand-ready-rig.json"
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;p.posture.editor_preview_mode = false
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	surface = Paddle.sample_head_surface()
	for x in [0.08, 0.15]:
		for y in [0.1, 0.16]:
			for forward in [0.38, 0.45]:
				for dominant in [0, 1]:
					var sign: float = -1.0 if dominant == 1 else 1.0
					var config: = {"wrist_x": x * sign, "wrist_y": y, "wrist_forward0": forward, "load_backshift": 0.0, "axial": 0.0, "pole_x": 0.4 * sign, "pole_y": 0.1, "pole_forward": 0.3, "dominant": dominant}
					for kitchen in [0, 1]:
						var count: int = rows.size();sample(p, config, kitchen, 0.0, 0.05)
						if rows.size() > count: rows[-1]["vision_margin"] = vision_margin(p)
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("ONE HAND READY RIG ", rows.size(), " -> ", output)
	game.queue_free(); await process_frame;quit()
