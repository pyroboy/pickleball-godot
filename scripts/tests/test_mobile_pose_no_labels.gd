extends SceneTree
## Scene text is forbidden in the mobile preview, including labels recreated by
## navigation/playback. Normal editor controls and interactive geometry remain.
const Store = preload("res://scripts/mobile_pose_store.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const Grip = preload("res://scripts/mobile_paddle_grip_store.gd")
const View = preload("res://scripts/mobile_pose_view_settings.gd")
var checks := 0
var failures: Array[String] = []
var poses_checked := [0, 0, 0]
var editor
var game

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func frames(count: int = 2) -> void:
	for index in range(count): await process_frame

func no_scene_labels(context: String) -> void:
	var visible_labels: Array[String] = []
	for label in editor._preview.viewport.find_children("*", "Label3D", true, false):
		if label.is_visible_in_tree(): visible_labels.append(str(label.get_path()) + ": " + label.text)
	check(visible_labels.is_empty(), context + " has no visible Label3D: " + str(visible_labels))
	# Scene overlays must not evade the Label3D check by becoming 2D UI labels.
	check(editor._preview.find_children("*", "Label", true, false).is_empty(), context + " has no overlay Label")

func handle_geometry(context: String) -> void:
	var g = editor._preview.gizmo
	g.sync_scene()
	check(g.scene_root.get_viewport() == editor._preview.viewport, context + " handles stay in private viewport")
	check(g._arrows.size() == 3 and g._rings.size() == 3, context + " retains three arrows and rings")
	for axis in range(3):
		var arrow: Node3D = g._arrows[axis]
		var ring: MeshInstance3D = g._rings[axis]
		check(arrow.get_child_count() == 2 and arrow.get_child(0) is MeshInstance3D and arrow.get_child(1) is MeshInstance3D, context + " retains shaft and tip %d" % axis)
		check(ring.mesh is TorusMesh, context + " retains torus %d" % axis)
		if g.scene_root.is_visible_in_tree():
			var available: bool = not g.bindings[axis].is_empty()
			check(arrow.visible == (available and g.mode == 0), context + " correct arrow visibility %d" % axis)
			check(ring.visible == (available and g.mode == 1), context + " correct ring visibility %d" % axis)
	check(g.scene_root.find_children("*", "Label3D", true, false).is_empty(), context + " handles allocate no scene text")

func editor_control_labels(context: String) -> void:
	for stage in range(3):
		check(editor._stages[stage].text == ["Wind-up", "Contact", "Finish"][stage], context + " keeps key button text")
	check(not editor._phase.text.is_empty() and not editor._play.text.is_empty(), context + " keeps transport text")
	check(editor._gizmo_mode.get_item_text(0) == "Move" and editor._gizmo_mode.get_item_text(1) == "Rotate", context + " keeps mode labels")
	check(not editor._status.text.is_empty() and not editor._gizmo_hint.text.is_empty(), context + " keeps status/help text")
	check(not editor._fields.find_children("*", "Label", true, false).is_empty(), context + " keeps field labels")

func motion_geometry(context: String) -> void:
	var preview = editor._preview
	check(preview.motion_root.visible and preview._ghost_root.visible and preview._arc.visible, context + " retains visible motion guides")
	check(preview.sample_heads.size() == 65 and preview.ghost_transforms.size() == 3, context + " retains solved arc and three keys")
	check(preview._ghost_root.find_children("*", "MeshInstance3D", true, false).size() == 6, context + " retains ghost paddle head/handle meshes")
	check(preview.motion_root.find_children("*", "Label3D", true, false).is_empty(), context + " allocates no floating key labels")
	var contact = preview.contact_preview
	check(contact != null and contact.visible and contact.ball.mesh is SphereMesh and contact.path.mesh is ImmediateMesh, context + " retains contact ball and path")
	check(contact.contact_marker.mesh is SphereMesh, context + " retains contact marker")
	if editor._current.has_zone:
		check(contact.block.visible and contact.block.mesh is BoxMesh, context + " retains preparation zone")
		check(contact.block.get_child_count() == 1 and contact.block.get_child(0) is MeshInstance3D, context + " retains zone outline only")

func check_view_toggles(context: String) -> void:
	var preview = editor._preview
	for shown in [false, true]:
		editor._gizmo_show.set_pressed_no_signal(shown); editor._toggle_gizmo()
		preview.set_ghosts_visible(shown); preview.set_arc_visible(shown)
		if preview.contact_preview != null: preview.contact_preview.set_block_visible(shown)
		no_scene_labels(context + " visibility " + str(shown))
		check(preview.gizmo.visible == shown, context + " gizmo visibility toggles")
		if editor._has_motion():
			check(preview._ghost_root.visible == shown and preview._arc.visible == shown, context + " motion guides toggle")
			if editor._current.has_zone: check(preview.contact_preview.block.visible == shown, context + " zone toggles")
	if editor._has_motion(): motion_geometry(context)

func check_transport(context: String) -> void:
	for progress in [0.0, .19, .5, .81, 1.0, .25]:
		editor._scrubbed(progress)
		no_scene_labels(context + " scrub " + str(progress))
	editor._toggle_play()
	check(editor._playing and editor._timeline.active, context + " Play still works")
	for fraction in [.13, .22, .3]:
		editor._timeline.advance(editor._timeline.sequence.duration * fraction); editor._refresh_preview()
		no_scene_labels(context + " playing " + str(fraction))
	editor._toggle_play(); no_scene_labels(context + " paused")
	check(not editor._playing and editor._resume_playback, context + " pause stays resumable")
	editor._toggle_play(); no_scene_labels(context + " resumed")
	check(editor._playing, context + " Resume still works")
	for progress in [.88, .11, .5]:
		editor._timeline._seek(progress); no_scene_labels(context + " timeline seek " + str(progress))
	editor._select_stage(1)

func check_selection(context: String, all_joints: bool) -> void:
	for category in range(editor.Fields.CATEGORIES.size()):
		if editor._category.is_item_disabled(category): continue
		editor._select_category(category)
		for mode in [0, 1]:
			editor._gizmo_mode.select(mode); editor._select_gizmo_mode(mode)
			no_scene_labels(context + " category %d mode %d" % [category, mode])
			handle_geometry(context + " category %d mode %d" % [category, mode])
	if all_joints:
		for joint in editor.Fields.JOINT_IDS:
			editor._joint_chosen(joint)
			no_scene_labels(context + " joint " + joint)
			check(editor._preview.selected_joint == joint, context + " joint selection retained " + joint)
	editor._joint_chosen("hips")
	editor_control_labels(context)

func check_additional_motion_flows(context: String) -> void:
	for count in [0, View.MAX_INBETWEEN_COUNT, View.DEFAULT_INBETWEEN_COUNT]:
		editor._ghost_slider.value = count
		no_scene_labels(context + " in-between count " + str(count))
		check(editor._preview.inbetween_count == count, context + " ghost count control retained")
	for variant in [1, 2]:
		editor._play_variant(variant)
		editor._timeline.advance(.1); editor._refresh_preview()
		no_scene_labels(context + " variant " + str(variant))
		editor._select_stage(1)
	for mode in range(editor._timeline._mode.item_count):
		for stance in range(editor._timeline._stance.item_count):
			editor._timeline._mode.select(mode); editor._timeline._stance.select(stance)
			editor._timeline._options_changed(mode)
			for progress in [.05, .45, .9]:
				editor._timeline._seek(progress)
				no_scene_labels(context + " sequence %d stance %d seek %.2f" % [mode, stance, progress])
	editor._timeline._mode.select(0); editor._timeline._stance.select(0); editor._select_stage(1)

func run() -> void:
	create_timer(180, true).timeout.connect(func(): push_error("No-label regression timed out"); quit(2))
	# These two Control scripts draw directly over the scene, so a node-only
	# check cannot detect their selected-joint, stage or gizmo-caption text.
	for path in ["res://scripts/ui/mobile_pose_preview.gd", "res://scripts/ui/mobile_pose_gizmo.gd"]:
		if not FileAccess.file_exists(path):
			print("NO LABELS source-only text-renderer check skipped (compiled export): ", path)
			continue
		var source := FileAccess.get_file_as_string(path)
		check(not source.is_empty() and not source.contains("draw_string"), path + " has no 2D scene text renderer")
	var isolated := "user://pose_store_tests/no_labels_%d/" % OS.get_process_id()
	check(Store.set_test_path(isolated + "poses.json") == OK, "isolate pose store")
	check(Serve.set_test_path(isolated + "serves.json") == OK, "isolate serve store")
	check(Grip.set_test_path(isolated + "grips.json") == OK, "isolate grip store")
	check(View.set_test_path(isolated + "view.json") == OK, "isolate view preferences")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(4)
	var pause = root.get_node("PauseController")
	pause.open(); game.open_mobile_pose_editor(); await frames(4)
	editor = game.mobile_pose_editor; editor.set_process(false)
	check(editor._preview.viewport.own_world_3d, "preview remains isolated")
	for workspace in range(3):
		editor._select_workspace(workspace)
		check(not editor._definitions.is_empty(), "workspace %d has fixtures" % workspace)
		for index in range(editor._definitions.size()):
			editor._select_pose(index); await frames(1)
			var context := "workspace %d / %s" % [workspace, editor._current.display_name]
			var before: String = Store.export_pose_json(editor._current)
			poses_checked[workspace] += 1
			for stage in range(3):
				editor._select_stage(stage)
				no_scene_labels(context + " key " + str(stage))
				check(editor._stage == (stage if editor._has_motion() else 1), context + " key behavior retained")
			editor._select_stage(1)
			check_selection(context, index == 0)
			check_view_toggles(context)
			if editor._has_motion():
				check_transport(context)
				if index == 0: check_additional_motion_flows(context)
			else:
				editor._toggle_play(); check(not editor._playing, context + " remains a static pose")
				no_scene_labels(context + " static Play")
			check(Store.export_pose_json(editor._current) == before, context + " navigation and preview preserve pose data")
			check(editor._dirty.is_empty(), context + " leaves authored data clean")
		print("NO LABELS workspace %d: %d poses checked" % [workspace, poses_checked[workspace]])
	# Reopening constructs a fresh private scene. Saved visual toggles must not
	# restore scene text, and both move/rotate meshes must still be selectable.
	var old_viewport: WeakRef = weakref(editor._preview.viewport)
	editor.close(); await frames(3)
	check(old_viewport.get_ref() == null, "closing frees private preview")
	game.open_mobile_pose_editor(); await frames(4)
	editor = game.mobile_pose_editor; editor.set_process(false)
	for workspace in range(3):
		editor._select_workspace(workspace); editor._joint_chosen("hips")
		no_scene_labels("reopened workspace %d" % workspace)
		editor_control_labels("reopened workspace %d" % workspace)
	editor._select_workspace(0); editor._select_stage(1); editor._joint_chosen("hips")
	editor._preview.yaw = .85; editor._preview.pitch = .55; editor._preview.update_camera()
	for mode in [0, 1]:
		editor._gizmo_mode.select(mode); editor._select_gizmo_mode(mode)
		var g = editor._preview.gizmo
		check(g.enabled and g.scene_root.is_visible_in_tree(), "reopened mode %d handles remain active" % mode)
		handle_geometry("reopened mode %d" % mode)
		for axis in range(3):
			var pickable := false
			if mode == 0: pickable = g.hit_axis(g.axis_geometry(axis).end) == axis
			else:
				for step in range(96):
					if g.hit_axis(g.ring_point(axis, TAU * step / 96.0)) == axis: pickable = true; break
			check(pickable, "reopened mode %d axis %d retains hit target" % [mode, axis])
		no_scene_labels("reopened mode %d" % mode)
	editor.close(); await frames(2)
	print("MOBILE POSE NO LABELS: %d checks, %d failures; strokes=%d stances=%d serves=%d" % [checks, failures.size(), poses_checked[0], poses_checked[1], poses_checked[2]])
	quit(0 if failures.is_empty() else 1)
