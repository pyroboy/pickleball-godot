extends SceneTree
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
var emitted: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func reverse_sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	return Path.sample(definition, 1.0 - progress)

func run() -> void:
	var preview = Preview.new()
	preview.size = Vector2(640, 480)
	root.add_child(preview)
	await process_frame
	await process_frame
	var definition: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	preview.show_pose(Path.sample(definition, .27))
	var expected := {
		"right_elbow": preview.player.right_arm_node.forearm_pivot,
		"left_elbow": preview.player.left_arm_node.forearm_pivot,
		"right_knee": preview.player.right_leg_node.shin_pivot,
		"left_knee": preview.player.left_leg_node.shin_pivot,
		"right_hand": preview.player.right_arm_node.hand_pivot,
		"left_hand": preview.player.left_arm_node.hand_pivot,
		"right_foot": preview.player.right_leg_node.foot_mesh,
		"left_foot": preview.player.left_leg_node.foot_mesh,
		"hips": preview.player.body_pivot.get_node("HipsMesh"),
		"torso": preview.player.body_pivot.get_node("TorsoMesh"),
		"head": preview.player.body_pivot.get_node("TorsoMesh/HeadMesh"),
		"paddle": preview.player.paddle_node.get_node("Head"),
	}
	preview.joint_selected.connect(func(id: String): emitted.append(id))
	var baseline: int = preview.find_children("*", "", true, false).size()
	for id in expected:
		preview.select_joint(id)
		check(preview.selected_joint == id, "dropdown selects " + id)
		check(preview.joint_world_position(id).is_equal_approx(expected[id].global_position), "highlight follows actual rig: " + id)
		check(preview.joint_screen_position(id).is_finite(), "visible projection: " + id)
	check(emitted.size() == 12, "selection emits twelve changes")
	preview.select_joint("paddle")
	preview.select_joint("unknown_joint")
	check(emitted.size() == 12 and preview.selected_joint == "paddle", "duplicate and invalid IDs do not change selection")
	check(not preview.joint_screen_position("unknown_joint").is_finite(), "unknown marker is not drawn at a fake location")
	check(preview.find_children("*", "", true, false).size() == baseline, "highlights allocate no scene nodes")
	for dimensions in [Vector2(400, 680), Vector2(900, 300)]:
		preview.size = dimensions
		await process_frame
		# Deliberately mismatch the render texture and local Control dimensions.
		preview.viewport.size = Vector2i(512, 384)
		preview.update_camera()
		for id in expected:
			var screen: Vector2 = preview.joint_screen_position(id)
			var pixel: Vector2 = screen * Vector2(preview.viewport.size) / dimensions
			var ray: Vector3 = preview.camera.project_ray_normal(pixel)
			var actual_ray: Vector3 = (expected[id].global_position - preview.camera.global_position).normalized()
			check(ray.dot(actual_ray) > .99999, "stretched projection %s %s" % [dimensions, id])
	preview.select_joint("hips")
	var point: Vector2 = preview.joint_screen_position("head")
	var before: Transform3D = preview.camera.transform
	var touch := InputEventScreenTouch.new()
	touch.index = 3; touch.position = point; touch.pressed = true
	preview._camera_input(touch)
	touch.pressed = false; preview._camera_input(touch)
	check(preview.selected_joint == "hips", "tapping another joint cannot override dropdown selection")
	check(preview.camera.transform.is_equal_approx(before), "tap does not orbit camera")
	touch.pressed = true; preview._camera_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 3; drag.relative = Vector2(32, 12)
	preview._camera_input(drag)
	check(not preview.camera.transform.is_equal_approx(before), "original touch drag still orbits")
	check(preview.selected_joint == "hips", "orbit preserves selection")
	preview._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	before = preview.camera.transform
	preview._camera_input(drag)
	check(preview._touch == -1 and preview.camera.transform.is_equal_approx(before), "focus loss cancels stale drag")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT; mouse.position = point; mouse.pressed = true
	preview._camera_input(mouse)
	var movement := InputEventMouseMotion.new(); movement.relative = Vector2(21, -9)
	preview._camera_input(movement)
	check(not preview.camera.transform.is_equal_approx(before), "original mouse drag still orbits")
	preview.cancel_gesture()
	check(not preview._mouse, "cancel clears mouse gesture")
	var selected: PostureDefinition = preview.pose
	var pose_transform: Transform3D = preview.player.paddle_node.global_transform
	preview.set_motion(definition)
	var rebuilds: int = preview.motion_rebuild_count
	var default_end: Transform3D = preview.ghost_transforms[2]
	preview.set_motion_sampler(Callable(self, "reverse_sample"))
	check(preview.motion_rebuild_count == rebuilds, "changing sampler invalidates lazily")
	preview.set_motion(definition)
	check(preview.motion_rebuild_count == rebuilds + 1, "next set_motion rebuilds through new sampler")
	check(preview.ghost_transforms[0].is_equal_approx(default_end), "custom sampler controls real solved ghost path")
	check(preview.pose == selected and preview.player.paddle_node.global_transform.is_equal_approx(pose_transform), "sampler rebuild restores scrubbed pose")
	check(preview.selected_joint == "hips", "sampler rebuild preserves dropdown selection")
	preview.set_motion_sampler(Callable(self, "reverse_sample"))
	preview.set_motion(definition)
	check(preview.motion_rebuild_count == rebuilds + 1, "same sampler reuses cached motion")
	preview.set_motion_sampler(Callable())
	preview.set_motion(definition)
	check(preview.motion_rebuild_count == rebuilds + 2 and preview.ghost_transforms[2].is_equal_approx(default_end), "clearing sampler restores normal stroke path")
	var rig_ref: WeakRef = weakref(preview.player)
	preview.queue_free()
	await process_frame
	await process_frame
	check(rig_ref.get_ref() == null, "editor cleanup frees cached joint nodes")
	print("MOBILE POSE JOINT HIGHLIGHT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
