extends "res://scripts/tests/test_mobile_stance_presets.gd"
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const FootPitch = preload("res://scripts/foot_pitch_grounding.gd")

func pitch_ring_angle(gizmo) -> float:
	gizmo.sync_scene()
	var best := -INF
	var chosen := NAN
	for index in range(96):
		var angle := TAU * index / 96.0
		var point: Vector2 = gizmo.ring_point(0, angle)
		if gizmo.hit_axis(point) != 0: continue
		var pixel: Vector2 = point * Vector2(editor._preview.viewport.size) / editor._preview.size
		if absf(gizmo.world_axes[0].normalized().dot(editor._preview.camera.project_ray_normal(pixel))) < .13: continue
		var clearance := INF
		for sample in range(96):
			var a: Vector2 = gizmo.ring_point(1, TAU * sample / 96.0)
			var b: Vector2 = gizmo.ring_point(1, TAU * (sample + 1) / 96.0)
			clearance = minf(clearance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
		if clearance > best: best = clearance; chosen = angle
	check(is_finite(chosen), "foot pitch has an independently pickable stable projected arc")
	return 0.0 if not is_finite(chosen) else chosen

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	output = "/workspace/scratch/6b6e64f75bd2/verification/foot-pitch"
	DirAccess.make_dir_recursive_absolute(output)
	var isolate := "user://pose_store_tests/foot_pitch_%d_%d/" % [OS.get_process_id(),int(Time.get_unix_time_from_system()*1000000)]
	Store.set_test_path(isolate + "pose.json"); Serve.set_test_path(isolate + "serve.json"); Grip.set_test_path(isolate + "grip.json"); View.set_test_path(isolate + "view.json")
	var plain := PostureDefinition.new()
	check(plain.right_foot_pitch_deg == 0 and plain.left_foot_pitch_deg == 0, "new pitch defaults are exactly zero")
	var target := PostureDefinition.new(); target.right_foot_pitch_deg = 30; target.left_foot_pitch_deg = -20
	var blend: PostureDefinition = plain.lerp_with(target, .5)
	check(blend.right_foot_pitch_deg == 15 and blend.left_foot_pitch_deg == -10, "independent pitch channels interpolate")
	var key := Key.new(); key.capture(target)
	check(key.values.right_foot_pitch_deg == 30 and key.values.left_foot_pitch_deg == -20, "body keys capture both pitch channels")
	key.apply_to(plain); check(plain.right_foot_pitch_deg == 30, "body keys apply pitch")
	var base := BasePoseDefinition.new(); base.right_foot_pitch_deg = 20; base.left_foot_pitch_deg = 10
	check(base.duplicate_pose().right_foot_pitch_deg == 20, "base copy preserves pitch")
	var base_preview: PostureDefinition = base.to_preview_posture(PostureDefinition.new())
	check(base_preview.right_foot_pitch_deg == 20 and base_preview.left_foot_pitch_deg == 10, "base preview preserves authored feet")
	# Old complete snapshots stay valid when the two additive channels are absent.
	for is_base in [false, true]:
		var source: Resource = Store._export_packaged_default(0, is_base)
		var legacy := Store._encode_fields(source)
		legacy.erase("right_foot_pitch_deg"); legacy.erase("left_foot_pitch_deg")
		check(Store._valid_fields(legacy, is_base), "legacy snapshot permits omitted pitch")
		source.right_foot_pitch_deg = 12; source.left_foot_pitch_deg = -9
		Store._apply_fields(source, legacy)
		check(source.right_foot_pitch_deg == 0 and source.left_foot_pitch_deg == 0, "legacy absence resets pitch to zero")
	# Each fixed approved import must preserve future additive values it omitted.
	for id in Store.APPROVED_POSE_IMPORTS:
		var fields := Store._encode_fields(Store._export_packaged_default(int(id), false))
		fields.right_foot_pitch_deg = 12.0; fields.left_foot_pitch_deg = -8.0
		for stage in ["windup_body", "follow_through_body"]:
			if not fields[stage] is Dictionary: fields[stage] = {}
			fields[stage].right_foot_pitch_deg = 20.0; fields[stage].left_foot_pitch_deg = -10.0
		var document := {"version": 1, "postures": {id: fields}, "base_poses": {}}
		# Persisted JSON keys are Strings; GDScript dot insertion uses StringName.
		document=JSON.parse_string(JSON.stringify(document))
		check(Store._valid_document(document), "pre-migration JSON fixture valid")
		check(Store._prepare_approved_pose_imports(document, false), "approved migration runs")
		var approved_fields: Dictionary = JSON.parse_string(Store.APPROVED_POSE_IMPORTS[id].JSON_TEXT).fields
		check(document.postures[id].right_foot_pitch_deg == approved_fields.get("right_foot_pitch_deg", 12) and document.postures[id].left_foot_pitch_deg == approved_fields.get("left_foot_pitch_deg", -8), "migration applies explicit Contact pitch and retains only omitted pitch")
		for stage in ["windup_body", "follow_through_body"]:
			check(document.postures[id][stage].right_foot_pitch_deg == 20 and document.postures[id][stage].left_foot_pitch_deg == -10, "migration retains omitted stage pitch")
		check(Store._valid_document(document), "migrated additive data remains valid")
	var flat_fields := Store._encode_fields(Serve.get_default(0))
	flat_fields.windup_body.right_foot_pitch_deg = 18.0; flat_fields.windup_body.left_foot_pitch_deg = 12.0
	var flat_doc := {"version": 1, "serves": {"0": flat_fields}}
	flat_doc=JSON.parse_string(JSON.stringify(flat_doc))
	check(Serve._prepare_approved_import(flat_doc), "Flat migration runs")
	check(flat_doc.serves["0"].windup_body.right_foot_pitch_deg == 18 and flat_doc.serves["0"].windup_body.left_foot_pitch_deg == 12, "Flat migration preserves omitted new pitch")
	check(Serve._valid_document(flat_doc), "Flat migrated pitch respects Wind-up lock policy")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game; await frames(4)
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	select_id(0)
	var original: String = Store.export_pose_json(editor._current)
	editor._joint_chosen("right_foot"); editor._gizmo_mode.select(1); editor._select_gizmo_mode(1)
	check(Store.export_pose_json(editor._current) == original and not editor._dirty.has(editor._key), "viewing foot controls never changes imported values")
	check(editor._body_inputs.has("right_foot_pitch_deg") and editor._sliders.has("right_foot_pitch_deg"), "typed number and slider exposed")
	check(editor._preview.gizmo.bindings[0].field == "right_foot_pitch_deg" and editor._preview.gizmo.bindings[2].is_empty(), "Rotate X pitch available without fake roll")
	var gizmo=editor._preview.gizmo
	var angle := pitch_ring_angle(gizmo)
	var point:Vector2=gizmo.ring_point(0,angle)
	var next:Vector2=gizmo.ring_point(0,angle + deg_to_rad(8) * float(gizmo.angle_signs[0]))
	var before_angle:float=editor._edit.right_foot_pitch_deg
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=point;press.pressed=true;editor._preview._camera_input(press)
	check(gizmo._axis == 0 and not gizmo._drag_edge, "foot pitch captures its real, stable 3D ring plane")
	var drag:=InputEventMouseMotion.new();drag.position=next;drag.relative=next-point;editor._preview._camera_input(drag)
	press.pressed=false;press.position=next;editor._preview._camera_input(press)
	check(is_equal_approx(editor._edit.right_foot_pitch_deg,before_angle+8) and is_equal_approx(editor._body_inputs.right_foot_pitch_deg.value,before_angle+8), "in-preview pitch ring updates exact selected-foot number")
	for stage in range(3):
		editor._select_stage(stage)
		var before := {}
		for other in range(3):
			if other != stage: before[other] = Path.endpoint(editor._current, other).right_foot_pitch_deg
		editor._set_body_value(Fields.body_descriptor("right_foot_pitch_deg"), -1, 9.0 + stage * 6.0)
		editor._joint_chosen("left_foot")
		editor._set_body_value(Fields.body_descriptor("left_foot_pitch_deg"), -1, -3.0 - stage * 2.0)
		for other in before: check(is_equal_approx(Path.endpoint(editor._current, other).right_foot_pitch_deg, before[other]), "pitch edit preserves nonselected phase")
		editor._joint_chosen("right_foot")
		check(is_equal_approx(editor._body_inputs.right_foot_pitch_deg.value, 9 + stage * 6), "pitch numeric input tracks authoring")
		check(editor._foot_pitch_status.text.contains("requested") and editor._foot_pitch_status.text.contains("applied"), "pitch panel reports requested and applied")
		var report: Dictionary = editor._preview.player.leg_ik.foot_pitch_report(true)
		check(report.grounded and absf(report.applied) < .001, "grounded sole stays flat despite saved toe-down request")
		var leg = editor._preview.player.right_leg_node
		check(FootPitch.lowest_y(leg, leg.foot_pivot.global_rotation.y, report.applied) >= PickleballConstants.FLOOR_Y - .00002, "grounded foot does not pierce court")
	editor._save_current()
	var fresh: Resource = PostureLibrary.new().get_def(0)
	for stage in range(3):
		var endpoint: Resource = Path.endpoint(fresh, stage)
		check(endpoint.right_foot_pitch_deg == 9 + stage * 6 and endpoint.left_foot_pitch_deg == -3 - stage * 2, "independent stage pitch survives save/reload")
	var exported: Dictionary = JSON.parse_string(Store.export_pose_json(editor._current))
	check(exported.fields.right_foot_pitch_deg == 15 and exported.fields.windup_body.right_foot_pitch_deg == 9 and exported.fields.follow_through_body.right_foot_pitch_deg == 21, "Copy JSON exports all three authored pitch keys")
	editor._set_body_value(Fields.body_descriptor("right_foot_pitch_deg"), -1, 900)
	check(editor._edit.right_foot_pitch_deg == 45, "typed toe-down input clamps to game authoring range")
	editor._set_body_value(Fields.body_descriptor("right_foot_pitch_deg"), -1, -900)
	check(editor._edit.right_foot_pitch_deg == -30, "typed toe-up input clamps to game authoring range")
	editor._reset_field("right_foot_pitch_deg", -1)
	check(editor._edit.right_foot_pitch_deg == 21, "reset returns saved pitch")
	await snap("portrait-grounded-pitch")
	# Lift in the existing authored stance, then rotate the actual visible foot.
	editor._set_body_value(Fields.body_descriptor("right_foot_offset"), 1, .20)
	editor._set_body_value(Fields.body_descriptor("right_foot_pitch_deg"), -1, 30)
	var lifted: Dictionary = editor._preview.player.leg_ik.foot_pitch_report(true)
	check(not lifted.grounded and lifted.applied > 10, "lifted foot visibly points toes down")
	check(editor._edit.right_foot_pitch_deg == 30, "physical limits never overwrite authored request")
	await snap("portrait-lifted-pitch")
	editor._select_workspace(2); editor._joint_chosen("right_foot"); editor._select_stage(1)
	check(not editor._body_inputs.has("right_foot_pitch_deg") and not editor._preview.gizmo.enabled, "serve Contact pitch remains protected")
	editor._select_stage(0)
	check(editor._body_inputs.has("right_foot_pitch_deg"), "serve Wind-up exposes pitch")
	editor._set_body_value(Fields.body_descriptor("right_foot_pitch_deg"), -1, 12)
	editor._save_current(); check(not editor._dirty.has(editor._key), "serve Wind-up pitch saves")
	check(Serve.endpoint(editor._current, 1).right_foot_pitch_deg == 0, "serve Contact authored pitch unchanged")
	editor._select_workspace(1); editor._joint_chosen("left_foot")
	editor._set_body_value(Fields.body_descriptor("left_foot_pitch_deg"), -1, 16)
	editor._save_current(); check(not editor._dirty.has(editor._key), "base stance pitch saves")
	check(editor._preview.pose.left_foot_pitch_deg == 16, "base pitch reaches preview sampler")
	editor._finish_close(); await frames(3); pause.close(); game.queue_free(); await frames(2)
	print("MOBILE FOOT PITCH: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
