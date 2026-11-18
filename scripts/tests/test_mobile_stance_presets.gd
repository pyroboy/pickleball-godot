extends SceneTree
const Store = preload("res://scripts/mobile_pose_store.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const Grip = preload("res://scripts/mobile_paddle_grip_store.gd")
const View = preload("res://scripts/mobile_pose_view_settings.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Key = preload("res://scripts/stroke_body_keyframe.gd")
var checks := 0
var failures: Array[String] = []
var game
var editor
var pause
var capture := false
var output := "/workspace/scratch/6b6e64f75bd2/verification/stance-presets"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(n: int = 3) -> void:
	for i in range(n): await process_frame
func select_id(id: int) -> void:
	for i in range(editor._definitions.size()):
		if editor._definitions[i].posture_id == id: editor._select_pose(i); return
	check(false, "pose exists")
func body_snapshot(pose: Resource) -> Dictionary:
	var data := {}
	for field in Key.FIELDS + editor.POS + editor.ROT: data[field] = pose.get(field)
	return data
func snap(label: String) -> void:
	await frames(4)
	for control in [editor._preview, editor._scroll, editor._save]: check(root.get_visible_rect().encloses(control.get_global_rect()), label + " layout fits")
	if capture:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK, label + " rendered")
		# Clean high-resolution capture from the same actual game preview camera.
		var view = editor._preview
		view.set_ghosts_visible(false); view.set_arc_visible(false); view.set_inbetween_count(0)
		if view.contact_preview: view.contact_preview.hide()
		view.distance = 3.2
		view.viewport.size = Vector2i(1000, 1000); view.update_camera()
		await frames(3); await RenderingServer.frame_post_draw
		check(view.viewport.get_texture().get_image().save_png(output + "/" + label + "-ingame.png") == OK, label + " clean game view rendered")
		view._resize_view()

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output)
	var isolate := "user://pose_store_tests/stance_presets_%d/" % OS.get_process_id()
	Store.set_test_path(isolate + "pose.json"); Serve.set_test_path(isolate + "serve.json"); Grip.set_test_path(isolate + "grip.json"); View.set_test_path(isolate + "view.json")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game; await frames(4)
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	for id in [0, 10, 2]:
		select_id(id)
		var original: String = Store.export_pose_json(editor._current)
		for category in [0, 1, 4, 5, 7]:
			editor._paddle_view = 2; editor._select_category(category)
		check(Store.export_pose_json(editor._current) == original and not editor._dirty.has(editor._key), "opening preset UI preserves exact imported pose %d" % id)
		for stage in range(3):
			editor._select_stage(stage)
			var other := {}
			for key in range(3):
				if key != stage: other[key] = body_snapshot(Path.endpoint(editor._current, key))
			var fixed := {}
			var fixed_paddle: Transform3D = editor._preview.player.paddle_node.global_transform
			for field in editor.POS + editor.ROT + ["body_position_offset", "right_elbow_pole", "left_elbow_pole", "right_shoulder_rotation_deg", "left_shoulder_rotation_deg", "body_pitch_deg", "body_roll_deg"]: fixed[field] = editor._edit.get(field)
			for closed in [false, true]:
				editor._apply_stance_style(closed)
				var side: float = -1 if editor._current.family == 1 else 1
				check(is_equal_approx(editor._edit.stance_width, .24 if closed else .66), "preset has explicit width")
				check(is_equal_approx(editor._edit.crouch_amount, .14 if closed else .18), "preset has bent-knee crouch")
				check(is_equal_approx(editor._edit.body_yaw_deg, side * 75 if closed else 0) and is_zero_approx(editor._edit.hip_yaw_deg) and is_zero_approx(editor._edit.torso_yaw_deg), "preset chest yaw matches open/closed intent")
				check(editor._edit.right_foot_offset == Vector3.ZERO and editor._edit.left_foot_offset == Vector3.ZERO, "preset removes earlier foot offset stagger")
				check(editor._preview.player.paddle_node.global_transform.is_equal_approx(fixed_paddle), "preset preserves actual paddle contact transform")
				var delta: Vector3 = editor._preview.player.leg_ik.left_foot_smooth - editor._preview.player.leg_ik.right_foot_smooth
				check(absf(delta.dot(editor._preview.player._get_forward_axis()) - (side * .60 if closed else 0)) < .0001, "actual foot line open parallel or closed staggered")
				for field in fixed: check(editor._edit.get(field) == fixed[field], "preset preserves exact paddle/arm/translation field " + field)
				for key in other: check(body_snapshot(Path.endpoint(editor._current, key)) == other[key], "preset preserves complete nonselected key")
			editor._save_current()
			var reloaded: Resource = PostureLibrary.new().get_def(id)
			check(body_snapshot(Path.endpoint(reloaded, stage)) == body_snapshot(editor._edit), "preset exact values survive save/reload")
	# Buttons are reachable in Hips & stance, and perform the explicit action.
	select_id(0); editor._select_stage(0); editor._select_category(1)
	var buttons := {}
	for node in editor._fields.find_children("*", "Button", true, false):
		if node.text.begins_with("Open ·"): buttons.open = node
		if node.text.begins_with("Closed ·"): buttons.closed = node
	check(buttons.size() == 2, "both preset buttons present in Hips & stance controls")
	buttons.open.pressed.emit(); await snap("portrait-open-stance")
	buttons = {}
	for node in editor._fields.find_children("*", "Button", true, false):
		if node.text.begins_with("Closed ·"): buttons.closed = node
	buttons.closed.pressed.emit(); await snap("portrait-closed-stance")
	# Left-handed closed setup mirrors without changing paddle handedness.
	editor._changed("paddle_hand", 1); await frames(); editor._apply_stance_style(true)
	check(editor._edit.paddle_hand == 1 and is_equal_approx(editor._edit.body_yaw_deg, -75) and editor._edit.lead_foot == 0, "left-handed closed preset mirrors the authored stance")
	# Verify the actual support frame on both court sides and paddle hands.
	for id in [0, 2]:
		select_id(id); editor._select_stage(0)
		for hand in [0, 1]:
			editor._changed("paddle_hand", hand)
			for closed in [false, true]:
				editor._apply_stance_style(closed)
				var expected: float = (-1.0 if id == 2 else 1.0) * (-1.0 if hand == 1 else 1.0) * (75.0 if closed else 0.0)
				for p in [game.player_left, game.player_right]:
					p.posture.editor_preview_mode = true
					p.posture.force_posture_update(editor._edit, false)
					p.leg_ik._update_authored_stance(editor._edit)
					var forward: Vector3 = p._get_forward_axis().rotated(Vector3.UP, -deg_to_rad(expected))
					var actual: Vector3 = p.body_pivot.global_basis * p._get_forward_axis()
					actual.y = 0.0
					check(actual.normalized().dot(forward) > .999, "court/hand/family body frame follows preset")
					for leg in [p.right_leg_node, p.left_leg_node]:
						var shoe: Vector3 = -leg.foot_pivot.global_basis.z
						shoe.y = 0.0
						check(shoe.normalized().dot(forward) > .999, "court/hand/family shoe frame follows body")
					var knee: Vector3 = p._get_forehand_axis() * editor._edit.right_knee_pole.x + p._get_forward_axis() * editor._edit.right_knee_pole.z
					check(knee.normalized().dot(forward) > .999, "knee pole follows turned shoe frame")
	# Serve application changes Wind-up only; planted stance propagates as before.
	editor._select_workspace(2); editor._select_stage(1)
	var protected := {}
	for stage in [1, 2]:
		var pose: Resource = Serve.endpoint(editor._current, stage)
		protected[stage] = {}
		for field in editor.POS + editor.ROT + ["body_yaw_deg", "hip_yaw_deg", "torso_yaw_deg", "crouch_amount"]: protected[stage][field] = pose.get(field)
	editor._apply_stance_style(false)
	check(editor._stage == 1, "serve preset returns to selected Contact view")
	var windup: Resource = Serve.endpoint(editor._current, 0)
	check(is_equal_approx(windup.stance_width, .66) and is_equal_approx(windup.crouch_amount, .18), "serve Open edits Wind-up width/crouch")
	for stage in protected:
		var pose: Resource = Serve.endpoint(editor._current, stage)
		for field in protected[stage]: check(pose.get(field) == protected[stage][field], "serve preset preserves protected Contact/Finish " + field)
	editor._select_workspace(0); select_id(20); editor._apply_stance_style(false)
	check(is_equal_approx(editor._current.stance_width, .66) and is_equal_approx(editor._current.crouch_amount, .18), "Ready supports explicit Open preset")
	editor._finish_close(); await frames(3); pause.close(); game.queue_free(); await frames(2)
	print("MOBILE STANCE PRESETS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
