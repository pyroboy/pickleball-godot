extends SceneTree
const Suite = preload("res://scripts/tests/test_player_leg_ik.gd")
var checks: = 0
var errors: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and errors.size() < 80: errors.append(label)
func run():
	var suite = Suite.new()
	for court in [0, 1]:
		for fps in [30, 60, 120]:
			for mode in ["lateral", "drop", "retreat", "reversal", "heading_only"]:
				var pair = suite.fixture(court); var p = pair[0]; var ik = pair[1]; var pose = suite.ready_pose()
				var yaw = [ik._right_yaw, ik._left_yaw]; var serial = [ik.right_contact_serial, ik.left_contact_serial]
				var feet = [ik.right_foot_smooth, ik.left_foot_smooth]
				var maximum_open: = 0.0
				for frame in range(fps * 2):
					var velocity: Vector3 = p._get_forehand_axis() * 2.5
					if mode in ["drop", "retreat"]: velocity = ( - p._get_forward_axis() + p._get_forehand_axis() * 0.65).normalized() * (1.0 if mode == "drop" else 4.0)
					if mode == "drop" and frame > fps / 3: velocity = Vector3.ZERO
					if mode == "reversal" and frame > fps / 2: velocity = - velocity
					if mode == "heading_only": velocity = Vector3.ZERO;pose.right_foot_yaw_deg = 60
					p.current_velocity = velocity
					suite.tick(p, ik, 1.0 / fps, pose)
					var now_yaw = [ik._right_yaw, ik._left_yaw]; var now_serial = [ik.right_contact_serial, ik.left_contact_serial]
					var now_feet = [ik.right_foot_smooth, ik.left_foot_smooth]; var locked = [ik.right_foot_locked, ik.left_foot_locked]
					for side in [0, 1]:
						if locked[side] and serial[side] == now_serial[side]:
							check(absf(angle_difference(yaw[side], now_yaw[side])) < 1e-05, "planted yaw stable " + mode)
							check(feet[side].distance_to(now_feet[side]) < 1e-05, "planted position stable " + mode)
					maximum_open = maxf(maximum_open, absf(ik.locomotion_hip_yaw_deg))
					yaw = now_yaw;serial = now_serial;feet = now_feet
				if mode == "lateral": check(maximum_open < 0.01, "lateral shuffle faces play")
				if mode == "drop": check(maximum_open > 10 and maximum_open < 80, "short retreat uses bounded drop step")
				if mode == "retreat": check(maximum_open > 120, "long retreat turns to travel")
				if mode == "heading_only": check(absf(angle_difference(ik._right_yaw, deg_to_rad(-60) + (PI if court == 1 else 0))) < 0.001, "heading-only replant reaches authored target")
				ik.free()
	var totals = {"pass": 0, "fail": 0, "errors": []};suite.run_all(totals)
	for error in totals.errors: errors.append(error)
	print("CONTACT HEADING: ", checks, " checks; legacy ", totals.pass, " pass/", totals.fail, " fail; errors ", errors.size())
	for error in errors: push_error(error)
	quit(0 if errors.is_empty() else 1)
