extends SceneTree
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const M = preload("res://scripts/drive_serve_motion.gd")
const S = preload("res://scripts/serve_style.gd")
const P = preload("res://scripts/stroke_swing_path.gd")
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Clearance = preload("res://scripts/paddle_clearance.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and failures.size() < 40: failures.append(label)
func head(tx: Transform3D) -> Vector3: return tx * PaddleSize.HEAD_OFFSET
func ball_at(plan: Dictionary, elapsed: float) -> Vector3:
	var previous: Vector3 = plan.release_position
	var previous_time: = 0.0
	for point in plan.samples:
		if point.time >= elapsed: return previous.lerp(point.pos, (elapsed - previous_time) / maxf(1e-06, point.time - previous_time))
		previous = point.pos;previous_time = point.time
	return plan.contact_position
func run():
	for side in [0, 1]:
		var player = Side.new(side)
		for style in range(7):
			var plan: Dictionary = S.release_plan(player.global_position, side == 1, style)
			var offset: Vector3 = plan.contact_position - player.global_position
			var local: = Vector3(offset.dot(player._get_forehand_axis()), offset.y, offset.dot(player._get_forward_axis()))
			var raw_contact: PostureDefinition = M._raw_serve_style_contact(style, local)
			var contact: PostureDefinition = M.serve_style_contact(style, local)
			var raw_tx: Transform3D = P.world_transform(player, raw_contact)
			var tx: Transform3D = P.world_transform(player, contact)
			check(head(tx).distance_to(head(raw_tx)) < 1e-05, "exact contact centre")
			check(tx.basis.z.distance_to(raw_tx.basis.z) < 1e-05, "exact contact face normal")
			check(tx.basis.is_equal_approx(raw_tx.basis * Basis(Vector3.BACK, deg_to_rad(preload("res://scripts/serve_pose_presentation.gd").contact_turn(style)))), "contact presentation applies exactly once")
			for q in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var prep: PostureDefinition = M.serve_style_preparation(style, q, S.hold_offset(style))
				var wait: PostureDefinition = M.serve_style_wait(prep, 0.0, style, local)
				check(P.world_transform(player, wait).is_equal_approx(P.world_transform(player, prep)), "release begins at actual held prep")
				check(P.world_transform(player, M.serve_strike(prep, 0, S.spin_mode(style))).is_equal_approx(P.world_transform(player, prep)), "legacy t0 ownership callback retains held shape")
				for progress in [0.65, 0.7, 0.8, 0.9, 0.99, 1.0]:
					var raw: Transform3D = P.world_transform(player, M._legacy_serve_style_strike(wait, progress, style, local))
					var actual: Transform3D = P.world_transform(player, M.serve_style_strike(wait, progress, style, local))
					var displacement: Vector3 = head(actual) - head(raw)
					check(displacement.length() < 1e-05, "late head path unchanged")
					check(actual.basis.z.distance_to(raw.basis.z) < 1e-05, "late strike face normal unchanged")
				var delta: = 0.001
				var old_next: Transform3D = P.world_transform(player, M._legacy_serve_style_follow_through(style, q, delta, local))
				var next: Transform3D = P.world_transform(player, M.serve_style_follow_through(style, q, delta, local))
				check((head(next) - head(old_next)).length() / delta < 0.005, "contact departure tangent retained")
				check(((head(next) - next.basis.z * PaddleSize.HEAD_HALF_THICKNESS) - (head(old_next) - old_next.basis.z * PaddleSize.HEAD_HALF_THICKNESS)).length() / delta < 0.005, "striking face centre departure tangent retained")
				var before: PostureDefinition = M.serve_style_strike(wait, 0.999, style, local)
				var raw_before: PostureDefinition = M._legacy_serve_style_strike(wait, 0.999, style, local)
				check(head(P.world_transform(player, before)).distance_to(head(P.world_transform(player, raw_before))) / 0.001 < 0.002, "contact arrival tangent retained")
				if style in [0, 1, 3]: check(contact.paddle_y_offset > before.paddle_y_offset, "volley strike rises through contact")
				if style in [5, 6]: check(contact.paddle_forehand_mul > before.paddle_forehand_mul if style == 5 else contact.paddle_forehand_mul < before.paddle_forehand_mul, "experimental lateral brush retained")
				for step in range(120):
					var elapsed: float = float(plan.contact_time) * step / 120.0
					var sampled: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, q, player.global_position.y)
					var paddle: Transform3D = P.world_transform(player, sampled)
					var gap: float = Clearance.distance_to_paddle_shape(paddle.affine_inverse() * ball_at(plan, elapsed)) - 0.0375
					check(gap >= - 0.001, "side%d style%d charge%.2f precontact%.4f gap%.5f" % [side, style, q, elapsed, gap])
	print("SERVE PRESENTATION INVARIANTS: ", checks, " checks, ", failures.size(), " failures")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
