extends "res://scripts/tests/diagnose_vendor_shifted_hold.gd"


func author_support_direction(p, pose: PostureDefinition) -> void :
	var model = p.left_arm_node.articulated_hand
	var angle: float = deg_to_rad(-15.0 / model.radial_sign)
	var local_roll: = Basis(model.anatomical_basis.z, angle)
	var high0: Basis = Grasp.BASES[2] * local_roll
	var high1: Basis = Grasp.BASES[3] * local_roll
	var height: float = clampf((active_hold.y - Grasp.LOW_HEIGHT) / (Grasp.HIGH_HEIGHT - Grasp.LOW_HEIGHT), 0.0, 1.0)
	var corrected: Basis = Grasp.BASES[0].slerp(Grasp.BASES[1], active_charge).slerp(high0.slerp(high1, active_charge), height).orthonormalized()


	p.arm_ik._hands._grasp_key = Vector2(active_charge, active_hold.y)
	p.arm_ik._hands._grasp_basis = corrected
	p.posture.editor_preview_mode = true;p.arm_ik.update_arm_ik(0.0, pose);p.posture.editor_preview_mode = false
	super.author_support_direction(p, pose)
func sample(p, style: int, charge: float, elapsed: float, plan: Dictionary):
	super.sample(p, style, charge, elapsed, plan)
	var arm = p.left_arm_node; var model = arm.articulated_hand
	var center: Vector3 = plan.release_position
	var mount: Transform3D = arm.hand_mesh.global_transform
	var gap: float = model.ball_surface_gap(mount.affine_inverse() * center)
	var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
	var original_wrist: Vector3 = center + stance * Grasp.basis(charge, active_hold.y) * (model.wrist_socket - model.cup_ball_center)
	var wrist: Vector3 = mount * model.wrist_socket
	records[-1]["full_hand_ball_gap_m"] = gap
	records[-1]["wrist_displacement_from_original_cup_m"] = wrist.distance_to(original_wrist)
	check(absf(gap) < 0.0002, "side%d style%d q%.2f full skin/sphere tangent" % [p.player_num, style, charge])
	check(wrist.distance_to(original_wrist) <= 0.0201, "bounded high-key correction wrist displacement")
func run():
	report_path = "/workspace/shared/pickleball-hands/vendor-grasp-roll-check.json"
	await super.run()
