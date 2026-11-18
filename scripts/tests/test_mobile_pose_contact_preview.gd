extends SceneTree
const Helper = preload("res://scripts/ui/mobile_pose_contact_preview.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Clearance = preload("res://scripts/paddle_clearance.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var count := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	count += 1
	if not value: push_error(message); quit(1)
func run() -> void:
	var preview = Preview.new(); root.add_child(preview)
	await process_frame; await process_frame
	var helper = Helper.new(); preview.player.get_parent().add_child(helper); helper.initialize(preview.player)
	var def: PostureDefinition = PostureLibrary.instance().get_def(0)
	preview.show_pose(Path.sample(def, .5))
	var solved: Transform3D = preview.player.paddle_node.global_transform
	helper.configure(def, solved)
	check(helper.find_children("*", "CollisionObject3D", true, false).is_empty(), "no physics bodies")
	check(helper.block.visible, "authored zone visible")
	check(is_equal_approx(helper.block.mesh.size.x, def.zone_x_max - def.zone_x_min), "exact authored width")
	check(helper.block.find_children("*", "Label3D", true, false).is_empty(), "preparation zone has no floating label")
	check(helper.block.get_child_count() == 1 and helper.block.get_child(0) is MeshInstance3D, "preparation zone outline remains")
	var local: Vector3 = solved.affine_inverse() * helper.ball_position_at(.5)
	check(absf(Clearance.distance_to_head_shape(local) - Ball.BALL_RADIUS) < .000001, "ball tangent to finite paddle at contact")
	check(helper.ball_position_at(.49).distance_to(helper.ball_position_at(.5)) < .05, "incoming continuity")
	check(helper.ball_position_at(.51).distance_to(helper.ball_position_at(.5)) < .05, "outgoing continuity")
	for style in range(7):
		helper.configure(def, solved, style)
		check(helper.ball_position_at(.5).is_equal_approx(helper.contact_point), "serve endpoint")
		var positions: Array[float] = []
		for i in range(51):
			var point: Vector3 = helper.ball_position_at(i * .01)
			check(point.is_finite(), "finite serve point")
			check(point.y >= Ball.FLOOR_Y + Ball.BALL_RADIUS - .003, "no below floor")
			positions.append(point.y)
		if Helper.Styles.is_drop(style): check(positions.min() < positions[50] - .01, "drop has bounce")
	helper.set_block_visible(false); check(not helper.block.visible, "block toggle")
	var child_ref: WeakRef = weakref(helper.ball)
	helper.dispose(); await process_frame; await process_frame
	check(child_ref.get_ref() == null, "cleanup owns meshes")
	preview.queue_free(); await process_frame
	print("CONTACT PREVIEW PASS ", count); quit()
