extends SceneTree

const R = preload("res://scripts/paddle_wrist_reach.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const P = preload("res://scripts/incoming_contact_planner.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func measure(player, pose, label: String) -> Dictionary:
	player.posture.transition_pose_blend = pose
	player.posture.force_posture_update(pose)
	var tx: Transform3D = player.paddle_node.global_transform
	var arm = player.left_arm_node if pose.paddle_hand == 1 else player.right_arm_node
	var actual_shoulder: Vector3 = R.live_shoulder(player, pose)
	var actual_wrist: Vector3 = R.displayed_wrist(player, pose)
	var pure_wrist: Vector3 = R.wrist_world(tx, pose)
	var wrist_distance: float = actual_wrist.distance_to(actual_shoulder)
	var accepted: bool = R.fits(tx, pose, actual_shoulder, R.link_budget(player, pose))
	check(pure_wrist.distance_to(actual_wrist) < 1e-05, label + " fixed socket differs from mounted hand")
	check(accepted == (wrist_distance <= R.link_budget(player, pose) + R.NUMERICAL_EPSILON), label + " live gate uses unfitted/wrong shoulder")
	var row: Dictionary = {"label": label, "team": player.player_num, "dominance": pose.paddle_hand, "pose": pose.posture_id, "planned_virtual_m": R.virtual_grip_world(Path.world_transform(player, pose), pose).distance_to(Body.shoulder_world(player, pose)), "planned_wrist_m": R.wrist_world(Path.world_transform(player, pose), pose).distance_to(Body.shoulder_world(player, pose)), "displayed_virtual_m": R.virtual_grip_world(tx, pose).distance_to(actual_shoulder), "displayed_wrist_m": wrist_distance, "socket_match_m": pure_wrist.distance_to(actual_wrist), "planned_shoulder": Body.shoulder_world(player, pose), "displayed_shoulder": actual_shoulder, "body_transform": player.body_pivot.global_transform, "feet": [player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth], "foot_locks": [player.leg_ik.right_foot_locked, player.leg_ik.left_foot_locked], "accepted": accepted, "visual_stretch": arm.visual_stretch, "upper_error_m": absf(actual_shoulder.distance_to(arm.forearm_pivot.global_position) - arm.upper_arm_length), "forearm_error_m": absf(arm.forearm_pivot.global_position.distance_to(actual_wrist) - arm.forearm_length)}
	rows.append(row)
	return row
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	var rejected_stretch: = 0
	var accepted_old_rejection: = 0
	for team in [0, 1]:
		var player = game.player_left if team == 0 else game.player_right
		player.global_position = Vector3(0, 1, 3 if team == 0 else -3)
		player.current_velocity = Vector3.ZERO
		player.hitting.clear_charge_visual();player.hitting.serving_visual_active = false
		for hand in [0, 1]:
			for fixture in [{"id": 1, "point": Vector3(0.3, - 0.05, 0.4197), "label": "formerly accepted overreach"}, {"id": 19, "point": Vector3( - 0.62, - 0.49, 0.4), "label": "formerly rejected wide backhand"}, {"id": 10, "point": Vector3(1.097, 0.377557143, 0.3573), "label": "formerly rejected wide forehand"}]:
				var base: PostureDefinition = PostureLibrary.instance().get_def(fixture.id).duplicate(true)
				base.paddle_hand = hand
				var point: Vector3 = player.global_position + player._get_forehand_axis() * fixture.point.x + Vector3.UP * fixture.point.y + player._get_forward_axis() * fixture.point.z
				var pose: PostureDefinition = P.pose_at(player, base, point)
				player.leg_ik.feet_initialized = false
				var row: Dictionary = measure(player, pose, "%s side%d hand%d" % [fixture.label, team, hand])
				if hand == 0:
					check(P.point_fits(player, pose, point) == (fixture.id != 1), row.label + " planned socket decision")
				if row.displayed_wrist_m > 0.7001:
					check( not row.accepted, row.label + " actual overreach accepted")
					rejected_stretch += 1
				elif row.displayed_virtual_m > 0.705:
					check(row.accepted, row.label + " physical socket rejected by virtual grip")
					check(row.visual_stretch <= 1.0002, row.label + " accepted physical wrist stretches")
					accepted_old_rejection += 1

			var boundary: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
			boundary.paddle_hand = hand
			player.leg_ik.feet_initialized = false;measure(player, boundary, "boundary seed")
			var shoulder: Vector3 = R.live_shoulder(player, boundary)
			var basis: Basis = Path.paddle_basis(player, boundary)
			var direction: Vector3 = (R.wrist_world(player.paddle_node.global_transform, boundary) - shoulder).normalized()
			for distance in [0.699, 0.6999, 0.7, 0.7002]:
				var head: Vector3 = shoulder + direction * distance - R.head_to_wrist_offset(basis, boundary)
				var pose: PostureDefinition = P.pose_at(player, boundary, head)
				var row: Dictionary = measure(player, pose, "boundary %.4f side%d hand%d" % [distance, team, hand])
				if row.accepted:
					check(row.upper_error_m <= 1e-05 and row.forearm_error_m <= 1e-05, row.label + " accepted endpoint distorts exact arm links")
	check(rejected_stretch > 0, "live fitted overreach negative coverage")
	check(accepted_old_rejection > 0, "live fitted physically reachable positive coverage")
	var file = FileAccess.open("/tmp/anatomical-wrist-contact-reach.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));file.close()
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	for failure in failures: push_error(failure)
	print("ANATOMICAL WRIST CONTACT REACH: %d checks, %d failures; live rejected=%d, live formerly rejected valid=%d" % [checks, failures.size(), rejected_stretch, accepted_old_rejection])
	quit(0 if failures.is_empty() else 1)
