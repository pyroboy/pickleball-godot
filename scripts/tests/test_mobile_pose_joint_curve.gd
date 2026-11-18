extends SceneTree
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Keyframe = preload("res://scripts/stroke_body_keyframe.gd")
var checks := 0
var failures: Array[String] = []
var sampled := 0
var max_drift: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func counted_sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	sampled += 1
	return Path.sample(definition, progress)

func static_sample(definition: PostureDefinition, _progress: float) -> PostureDefinition:
	return definition

func verify_samples(preview, definition: PostureDefinition, sampler: Callable) -> void:
	for index in range(65):
		preview.show_pose(sampler.call(definition, index / 64.0))
		for id in Preview.JOINT_NAMES:
			var position: Vector3 = preview.joint_samples[id][index]
			max_drift[id] = maxf(float(max_drift.get(id, 0)), position.distance_to(preview.joint_world_position(id)))
			check(position.is_finite() and position.distance_to(preview.joint_world_position(id)) < .00001,
				"cached curve equals rendered joint %s at %d" % [id, index])

func run() -> void:
	var preview = Preview.new()
	preview.size = Vector2(640, 480)
	root.add_child(preview)
	await process_frame
	await process_frame
	var definition: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	var displayed: PostureDefinition = Path.sample(definition, .27)
	preview.show_pose(displayed)
	preview.select_joint("right_elbow")
	check(preview.selected_joint_samples.is_empty() and not preview.selected_joint_has_motion, "selection before motion has no invented curve")
	var displayed_positions: Dictionary = {}
	for id in Preview.JOINT_NAMES: displayed_positions[id] = preview.joint_world_position(id)
	preview.set_motion_sampler(counted_sample)
	preview.set_motion(definition)
	check(sampled == 65, "all twelve curves share exactly one 65-pose solve pass")
	check(preview.joint_samples.size() == 12 and preview.selected_joint_samples.size() == 65, "all displayed joints cached and existing selection refreshed")
	check(preview.pose == displayed, "curve sampling preserves scrubbed resource")
	for id in Preview.JOINT_NAMES:
		check(preview.joint_world_position(id).distance_to(displayed_positions[id]) < .00001, "curve sampling restores displayed " + id)
	verify_samples(preview, definition, Path.sample)
	var rebuilds: int = preview.motion_rebuild_count
	var node_count: int = preview.find_children("*", "", true, false).size()
	for id in Preview.JOINT_NAMES:
		preview.select_joint(id)
		check(preview.selected_joint_samples == preview.joint_samples[id], "selection uses cached " + id)
	check(sampled == 65 and preview.motion_rebuild_count == rebuilds, "selection runs no extra sampler/IK pass")
	check(preview.find_children("*", "", true, false).size() == node_count, "selected curves allocate no extra scene nodes")
	for index in range(80):
		preview.show_pose(Path.sample(definition, index / 79.0))
		preview.set_preview_progress(index / 79.0)
		preview.set_motion(definition)
	preview.view("side"); preview.zoom(.1)
	check(sampled == 65 and preview.motion_rebuild_count == rebuilds, "playback/scrubbing/orbit/zoom reuse sampled curves")
	preview.select_joint("right_elbow")
	# The off-contact in-between moves without replacing the three stage values.
	# The production Forehand above is still checked against all 65 real solved
	# samples. Mutation responsiveness needs an explicit, unsaturated fixture:
	# a user's imported shoulder rotations/reach can legitimately pin an elbow.
	definition = neutral_curve_fixture()
	definition.right_elbow_path = PackedVector3Array([
		Vector3(.1, 0, 0), Vector3(.2, .2, -.2), Vector3(.1, 0, 0),
		Vector3(-.1, -.1, .2), Vector3(.1, 0, 0)])
	preview.set_motion(definition)
	var before: PackedVector3Array = preview.selected_joint_samples.duplicate()
	definition.right_elbow_path[1] += Vector3(.1, .25, -.1)
	preview.set_motion(definition)
	check(preview.selected_joint_samples[16].distance_to(before[16]) > .001, "editing authored in-between changes selected curve")
	for index in [0, 32, 64]:
		check(preview.selected_joint_samples[index].distance_to(before[index]) < .00001, "in-between edit preserves phase endpoint %d" % index)
	verify_samples(preview, definition, Path.sample)
	definition.windup_body = Keyframe.new()
	definition.windup_body.values.body_yaw_deg = 35.0
	preview.set_motion(definition)
	var windup: Vector3 = preview.selected_joint_samples[0]
	definition.windup_body.values.body_yaw_deg = 60.0
	preview.set_motion(definition)
	check(preview.selected_joint_samples[0].distance_to(windup) > .001, "in-place body-keyframe edit refreshes selected curve")
	check(preview.selected_joint_has_motion, "moving joint has a trajectory")
	preview.set_arc_visible(false)
	check(not preview._arc.visible and not preview._arc_visible, "Arc toggle hides paddle and selected overlay together")
	preview.set_arc_visible(true)
	check(preview._arc.visible and preview._arc_visible, "Arc toggle restores both without rebuilding")
	preview.clear_joint_selection()
	check(preview.selected_joint_samples.is_empty() and not preview.selected_joint_has_motion, "clearing selection clears overlay")
	preview.select_joint("right_hand")
	preview.set_motion_sampler(static_sample)
	preview.set_motion(definition)
	check(preview.selected_joint_samples.size() == 65 and not preview.selected_joint_has_motion, "stationary joint does not invent a path or phases")
	rebuilds = preview.motion_rebuild_count
	preview.set_motion(PostureLibrary.instance().get_def(20))
	check(not preview.selected_joint_has_motion and preview.selected_joint_samples.is_empty() and preview.motion_rebuild_count == rebuilds, "Ready stays one honest static marker")
	preview.set_motion(null, false)
	check(not preview.selected_joint_has_motion and preview.selected_joint_samples.is_empty(), "body stance never reuses preceding stroke curve")
	preview.set_motion_sampler(ServeStore.sample)
	for style in range(7):
		var serve: PostureDefinition = ServeStore.get_default(style)
		preview.show_pose(ServeStore.sample(serve, .37))
		var current: Vector3 = preview.joint_world_position("right_hand")
		preview.set_motion(serve)
		check(preview.joint_world_position("right_hand").distance_to(current) < .00001, "serve sampling restores selected joint %d" % style)
		verify_samples(preview, serve, ServeStore.sample)
		check(preview.selected_joint_has_motion, "serve's selected hand has motion %d" % style)
		check(preview.joint_samples.right_foot[0].distance_to(preview.joint_samples.right_foot[64]) < .00001, "serve's planted stance stays planted %d" % style)
	print("MAX JOINT DRIFT: ", max_drift)
	preview.queue_free()
	await process_frame
	print("MOBILE POSE JOINT CURVE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func neutral_curve_fixture() -> PostureDefinition:
	var pose := PostureDefinition.new()
	pose.posture_id = 0; pose.family = 0; pose.display_name = "Neutral curve test"
	pose.paddle_forehand_mul = .42; pose.paddle_y_offset = .08; pose.paddle_forward_mul = .46
	pose.paddle_roll_base_deg = 120; pose.paddle_pitch_signed_deg = 5; pose.paddle_pitch_sign_source = 1
	pose.charge_paddle_offset = Vector3(.02, .12, -.74)
	pose.charge_paddle_rotation_deg = Vector3(0, 0, -100)
	pose.ft_paddle_offset = Vector3(-.66, .4, -.12)
	pose.ft_paddle_rotation_deg = Vector3(0, 0, -152)
	pose.crouch_amount = .07; pose.left_hand_mode = 4
	return pose
