extends SceneTree
const P = preload("res://scripts/stroke_swing_path.gd")
const M = preload("res://scripts/drive_serve_motion.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
var checks: = 0
var errors: Array[String] = []
func _initialize(): call_deferred("run")
func compare(p, pose, original, label):
	checks += 1
	var a: Transform3D = P.world_transform(p, pose); var b: Transform3D = P.world_transform(p, original)
	if not a.is_equal_approx(b): errors.append(label + " changed paddle transform")
func run():
	for court in [0, 1]:
		var p = Side.new(court)
		for id in [0, 2, 3, 4, 10, 11]:
			var base = PostureLibrary.instance().get_def(id)
			for q in [0.0, 0.05, 0.25, 0.5, 0.75, 1.0]:
				for spin in range(3):
					for step in range(65):
						var t: float = step / 64.0
						var pose = M.sample_drive(base, t, q, false, spin)
						var before = pose.lerp_with(pose, 0)
						if base.family in [0, 1]: before.torso_pitch_deg += 12 * M.drive_strength(base, q) * maxf(0, t * 2 - 1) * q
						elif base.family == 3: before.torso_pitch_deg += 12 * maxf(0, 1 - t * 2) * q
						compare(p, pose, before, "drive %d q%.2f spin%d t%.3f" % [id, q, spin, t])
		for step in range(65):
			var t: float = step / 64.0
			var pose = P.sample(PostureLibrary.instance().get_def(10), t); var before = pose.lerp_with(pose, 0)
			before.torso_pitch_deg += 12 * maxf(0, t * 2 - 1);compare(p, pose, before, "authored wide %.3f" % t)
		for q in [0.0, 0.05, 0.25, 0.5, 0.75, 1.0]:
			var start = M.serve_style_preparation(2, q, Vector3(0.22, 0.08, 0.48))
			for step in range(65):
				var t: float = step / 64.0
				var pose = M.serve_style_strike(start, t, 2); var before = pose.lerp_with(pose, 0)
				before.torso_pitch_deg += 16 * q * (1 - t * t);compare(p, pose, before, "slice %.2f %.3f" % [q, t])
	print("CLEARANCE PADDLE INVARIANTS: ", checks, " checks, ", errors.size(), " failures")
	for error in errors.slice(0, 30): push_error(error)
	quit(0 if errors.is_empty() else 1)
