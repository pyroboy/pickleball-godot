extends SceneTree
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Dimensions = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame;await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for player in [game.player_left, game.player_right]:
		player.global_position = Vector3(0,player.ground_y,3.5 if player.player_num == 0 else -3.5)
		var pose: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
		player.posture.transition_pose_blend = pose
		player.posture.force_posture_update(pose)
		var original: Transform3D = Path.world_transform(player,pose)
		for face in [-1.0,1.0]:
			for direction in [-1.0,1.0]:
				for offset in [-0.0002,-0.00001,0.0,0.00001,0.0002,0.001,0.008]:
					var point: Vector3 = original * Vector3(0,Dimensions.HEAD_CENTER_Y,face * (Dimensions.HEAD_HALF_THICKNESS + offset))
					var incoming: Vector3 = original.basis * Vector3(0,0,direction * 5.0)
					var seated: PostureDefinition = Geometry.contact_surface_pose(player,pose,point,incoming)
					var label: String = "team%d face%.0f incoming%.0f offset%.6f" % [player.player_num,face,direction,offset]
					check(seated != null,label + " no supported contact")
					if seated == null: continue
					var transform: Transform3D = Path.world_transform(player,seated)
					var gap: float = Geometry.distance_to_head_shape(transform.affine_inverse() * point)
					check(absf(gap - Ball.BALL_RADIUS) < 0.0002,label + " wrong seated surface gap %.6f" % gap)
					check(Wrist.fits(transform,seated,Wrist.live_shoulder(player,seated),Wrist.link_budget(player,seated)),label + " stretched wrist")
					check(original.origin.distance_to(transform.origin) < 0.060,label + " oversized seat correction")
	print("CONTACT SURFACE FACE: %d checks, %d failures: %s" % [checks,failures.size(),failures])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
