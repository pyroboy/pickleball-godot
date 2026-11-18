extends SceneTree
const Motion = preload("res://scripts/incoming_ready_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func point(p: PostureDefinition) -> Vector3:
	return Vector3(p.paddle_forehand_mul, p.paddle_y_offset, p.paddle_forward_mul)
func run():
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	var base: PostureDefinition = PostureLibrary.instance().get_def(2)
	var target: PostureDefinition = Path.sample(base, 0.28)
	check(Motion.GripTransition.supports_both_joined(ready, target), "reviewed route must be enabled")
	if not failures.is_empty(): print("JOINED GRIP CLOCK: route not enabled");quit(2);return
	var before: = point(base)
	var pose: PostureDefinition = Motion.blend_pose(ready, target, 0.032)
	check(Motion.grip_transition_active(pose), "first delta starts one captured transfer")
	var first: Dictionary = pose.get_meta(Motion.GRIP_TRANSITION_STATE)
	var captured: PostureDefinition = first["to"]
	var changed: = Path.rotate_guard(target, 20.0)
	var previous: float = first.progress
	for i in range(4):
		pose = Motion.blend_pose(pose, changed, 0.032)
		var state: Dictionary = pose.get_meta(Motion.GRIP_TRANSITION_STATE)
		check(state["to"] == captured, "bearing drift retains the captured endpoint")
		check(float(state.progress) > previous, "bearing drift cannot restart the clock")
		previous = state.progress
	var paused: PostureDefinition = Motion.blend_pose(pose, changed, 0.0)
	check(point(paused).distance_to(point(pose)) < 1e-06, "zero delta cannot move the hand")
	check(is_equal_approx(paused.get_meta(Motion.GRIP_TRANSITION_STATE).progress, previous), "zero delta cannot consume transfer time")
	for i in range(6): pose = Motion.blend_pose(pose, ready, 0.032)
	check( not Motion.grip_transition_active(pose), "cancel reverses to the captured Ready endpoint")
	check(point(pose).distance_to(point(ready)) < 1e-06, "reverse endpoint is exact Ready")
	check(pose.left_hand_mode == 1 and is_equal_approx(pose.support_grip_rotation_deg, -120.0), "reverse retains joined195 grip")
	var whole: PostureDefinition = Motion.blend_pose(ready, target, 0.1)
	for fps in [30, 60, 120]:
		pose = ready
		for i in range(int(fps / 10)): pose = Motion.blend_pose(pose, target, 1.0 / fps)
		check(point(pose).distance_to(point(whole)) < 1e-05, "transfer position is rate-independent at%d" % fps)
		check(pose.right_elbow_pole.distance_to(whole.right_elbow_pole) < 1e-05, "main elbow is rate-independent at%d" % fps)
	pose = ready
	for i in range(20): pose = Motion.blend_pose(pose, target, 0.016)
	check( not Motion.grip_transition_active(pose), "transfer completes on its one clock")
	check(point(pose).distance_to(point(target)) < 1e-05, "forward endpoint is exact target")
	check(pose.left_hand_mode == 1 and pose.support_grip_style == 1.0, "forward endpoint retains315 support profile")
	check(point(base) == before, "source contact resource is immutable")
	check( not Motion.GripTransition.supports_both_joined(ready, PostureLibrary.instance().get_def(0)), "forehand stays on its existing owner")
	for failure in failures: push_error(failure)
	print("JOINED GRIP CLOCK: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
