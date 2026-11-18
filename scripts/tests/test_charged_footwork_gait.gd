extends SceneTree


const Suite = preload("res://scripts/tests/test_player_leg_ik.gd")
class MockFootwork extends RefCounted:
	var state: = "idle"
	var plan: Dictionary = {}
	var load_side: = 0
	func wants_plant() -> bool: return state in ["plant", "load", "swing"]
class MockHuman extends RefCounted:
	var footwork: = MockFootwork.new()
class ChargedPosture extends Suite.MockPosture:
	var human_contact: = MockHuman.new()
var checks: = 0
var errors: Array[String] = []
var records: Array = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and errors.size() < 80: errors.append(label)
func fixture(suite, court: int) -> Array:
	var pair: Array = suite.fixture(court)
	pair[0].posture = ChargedPosture.new()
	return pair
func run() -> void :
	var suite = Suite.new()
	for court in [0, 1]:
		for hz in [30, 60, 120]:
			for side in [0, 1]:
				_test_crossover(suite, court, hz, side)
				_test_shuffle(suite, court, hz, side)
				_test_plant_priority(suite, court, hz, side)
	for error in errors: push_error(error)
	print("CHARGED FOOTWORK GAIT: %d checks, %d failures" % [checks, errors.size()])
	var output: = "/tmp/charged-footwork-gait.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var file: = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks": checks, "failures": errors, "records": records}, "\t"))
	quit(0 if errors.is_empty() else 1)
func _test_crossover(suite, court: int, hz: int, side: int) -> void :
	var pair: Array = fixture(suite, court); var p = pair[0]; var ik = pair[1]
	var pose: PostureDefinition = suite.ready_pose()
	var work = p.posture.human_contact.footwork
	work.state = "crossover";work.load_side = side
	var direction: Vector3 = p._get_forehand_axis() * (1.0 if side == 0 else -1.0)
	var feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	var yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
	var serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
	var minimum_lateral: = INF; var maximum_lateral: = - INF
	var minimum_heading_gap: = INF; var minimum_shoe_gap: = INF
	var maximum_drift: = 0.0; var maximum_yaw_drift: = 0.0
	var maximum_ready_turn := 0.0
	var ready_at: = -1.0
	var tag: = "P%d %dHz load%d" % [court, hz, side]
	for frame in range(hz * 3):
		var elapsed: float = float(frame) / hz
		if elapsed < 1.2:
			work.state = "crossover";p.current_velocity = direction * 3.5
		elif elapsed < 1.5:
			work.state = "adjust";p.current_velocity = direction * 0.7
		else:
			work.state = "plant";p.current_velocity = Vector3.ZERO
		suite.tick(p, ik, 1.0 / hz, pose)
		maximum_ready_turn = maxf(maximum_ready_turn, absf(ik.locomotion_hip_yaw_deg))
		var now: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
		var now_yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
		var now_serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
		var locked: Array[bool] = [ik.right_foot_locked, ik.left_foot_locked]
		for foot_side in [0, 1]:
			if locked[foot_side] and serials[foot_side] == now_serials[foot_side]:
				maximum_drift = maxf(maximum_drift, feet[foot_side].distance_to(now[foot_side]))
				maximum_yaw_drift = maxf(maximum_yaw_drift, absf(angle_difference(yaws[foot_side], now_yaws[foot_side])))
		minimum_shoe_gap = minf(minimum_shoe_gap, now[0].distance_to(now[1]))
		if elapsed > 0.45 and elapsed < 1.2:
			var lateral: float = (now[0] - now[1]).dot(p._get_forehand_axis())
			minimum_lateral = minf(minimum_lateral, lateral);maximum_lateral = maxf(maximum_lateral, lateral)
			var heading_side: = Vector3( - ik._heading_forward.z, 0, ik._heading_forward.x)
			minimum_heading_gap = minf(minimum_heading_gap, (now[0] - now[1]).dot(heading_side))
		if elapsed < 1.5: check( not ik.is_support_ready(side), tag + " moving feet cannot authorize load")
		elif ready_at < 0 and ik.is_support_ready(side): ready_at = elapsed
		feet = now;yaws = now_yaws;serials = now_serials
	check(minimum_lateral < - 0.12 and maximum_lateral > 0.12, tag + " actual feet pass laterally")
	# User priority: long lateral coverage preserves Ready facing. Feet may
	# cross during a crossover, with real shoe clearance and locked contacts.
	check(maximum_ready_turn < 0.001, tag + " crossover keeps Ready/court facing %.4f" % maximum_ready_turn)
	check(minimum_shoe_gap >= 0.095, tag + " shoes have physical clearance %.4f" % minimum_shoe_gap)
	check(maximum_drift < 1e-05, tag + " all support positions remain locked")
	check(maximum_yaw_drift < 1e-05, tag + " all support headings remain locked")
	check(ready_at >= 1.5 and ready_at < 2.4, tag + " completes adjustment and outside load %.3f" % ready_at)
	check(ik.is_support_ready(side), tag + " load remains usable")
	records.append({"case": tag, "minimum_court_lateral_gap": minimum_lateral, "maximum_court_lateral_gap": maximum_lateral, "minimum_heading_gap": minimum_heading_gap, "minimum_shoe_gap": minimum_shoe_gap, "maximum_planted_drift": maximum_drift, "maximum_planted_yaw_drift": maximum_yaw_drift, "support_ready_at": ready_at})
	ik.free()
func _test_shuffle(suite, court: int, hz: int, side: int) -> void :
	var pair: Array = fixture(suite, court); var p = pair[0]; var ik = pair[1]
	var pose: PostureDefinition = suite.ready_pose()
	p.posture.human_contact.footwork.state = "shuffle"
	p.current_velocity = p._get_forehand_axis() * (0.8 if side == 0 else - 0.8)
	for frame in range(hz):
		suite.tick(p, ik, 1.0 / hz, pose)
		check(absf(ik.locomotion_hip_yaw_deg) < 0.01, "compact shuffle faces play")
		check((ik.right_foot_smooth - ik.left_foot_smooth).dot(p._get_forehand_axis()) >= ik.MIN_FOOT_SEPARATION - 1e-05, "compact shuffle does not cross")
		check( not ik._run_active, "compact shuffle stays in one-foot step cycle")
	ik.free()
func _test_plant_priority(suite, court: int, hz: int, side: int) -> void :
	var pair: Array = fixture(suite, court); var p = pair[0]; var ik = pair[1]
	var pose: PostureDefinition = suite.ready_pose()
	var targets: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	var offset: Vector3 = p._get_forward_axis()


	targets[side] += offset * 0.1;targets[1 - side] += offset * 0.2
	ik._reset_feet(targets)
	var work = p.posture.human_contact.footwork
	work.state = "plant";work.load_side = side
	suite.tick(p, ik, 1.0 / hz, pose)
	check(ik._active_side == side, "outside leg replants before the larger opposite gap")
	check( not ik.is_support_ready(side), "airborne outside leg never authorizes load")
	for frame in range(hz): suite.tick(p, ik, 1.0 / hz, pose)
	check(ik.is_support_ready(side), "outside support becomes ready after both steps")
	var serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
	work.state = "load"
	for frame in range(hz / 2):
		pose.crouch_amount += 0.001
		suite.tick(p, ik, 1.0 / hz, pose)
	check(ik.is_support_ready(side), "body load blend preserves support readiness")
	check(serials == [ik.right_contact_serial, ik.left_contact_serial], "body-only load cannot spuriously replant feet")
	ik.free()
