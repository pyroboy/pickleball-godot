extends RefCounted
## Stateless isolated-rig adapter. Every call first restores the authored pose;
## seeking backwards/forwards and entering/leaving flight cannot carry old locks.
const Contacts = preload("res://scripts/pose_foot_contacts.gd")

static func show(preview, pose, split_sample: Dictionary) -> Dictionary:
	preview.show_pose(pose)
	var player = preview.player
	if player == null or player.leg_ik == null: return {"applied": false}
	var legs = player.leg_ik
	var grounded: Array[Dictionary] = [
		{"position": legs.right_foot_smooth, "yaw": legs._right_yaw, "planted": legs.right_foot_locked},
		{"position": legs.left_foot_smooth, "yaw": legs._left_yaw, "planted": legs.left_foot_locked}]
	var contacts := Contacts.split_sample(grounded, split_sample)
	var active: bool = bool(split_sample.get("active", false)) and str(split_sample.get("phase", "ready")) in ["split_load", "split_unweight", "split_land"]
	if not active: return {"applied": false, "contacts": contacts}
	legs.right_foot_smooth = contacts[0].position; legs.left_foot_smooth = contacts[1].position
	legs.right_foot_locked = contacts[0].planted; legs.left_foot_locked = contacts[1].planted
	legs.right_foot_lock_pos = grounded[0].position; legs.left_foot_lock_pos = grounded[1].position
	var fixed_paddle: Transform3D = player.paddle_node.global_transform
	player.body_pivot.position.y += clampf(float(split_sample.get("body_lift", 0.0)), 0.0, .025) - clampf(float(split_sample.get("crouch", 0.0)), 0.0, .028)
	player.paddle_node.global_transform = fixed_paddle
	# Authored solve avoids locomotion and match state. Add pitch on a temporary
	# pose only; the editor's saved foot angles remain untouched.
	var display = pose.duplicate(true)
	var pitch := clampf(float(split_sample.get("ankle_pitch_deg", 0.0)), 0.0, 12.0) if not contacts[0].planted else 0.0
	display.right_foot_pitch_deg += pitch; display.left_foot_pitch_deg += pitch
	legs._solve_legs(0.0, display, true)
	preview.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if preview.gizmo: preview.gizmo.sync_scene()
	return {"applied": true, "contacts": contacts, "phase": split_sample.get("phase", "ready")}
