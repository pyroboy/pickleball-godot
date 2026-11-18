extends SceneTree

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const Shape = preload("res://scripts/body_clearance.gd")
const M = preload("res://scripts/drive_serve_motion.gd")
const P = preload("res://scripts/stroke_swing_path.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
func _initialize(): call_deferred("run")
func run():
	var p = Side.new(0)
	var surface = G.sample_head_surface()
	for kind in ["authored_wide", "runtime_fh", "runtime_bh", "overhead", "slice"]:
		var rows = []
		for degrees in [-16.0, -8.0, 0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0]:
			var face: = INF; var chest: = INF; var shift: = 0.0; var reach: = 0.0
			for q in [0.25, 0.5, 0.75, 1.0]:
				for step in range(33):
					var t: float = step / 32.0
					var pose: PostureDefinition
					if kind == "authored_wide": pose = P.sample(PostureLibrary.instance().get_def(10), t)
					elif kind == "slice": pose = M.serve_style_strike(M.serve_style_preparation(2, q, Vector3(0.22, 0.08, 0.48)), t, 2)
					else: pose = M.sample_drive(PostureLibrary.instance().get_def(0 if kind == "runtime_fh" else (2 if kind == "runtime_bh" else 4)), t, q)
					var original: Transform3D = P.world_transform(p, pose)
					var amount: float = maxf(0, t * 2 - 1) * q
					if kind == "authored_wide": amount = maxf(0, t * 2 - 1)
					if kind == "overhead": amount = maxf(0, 1 - t * 2) * q
					if kind == "slice": amount = (1 - t * t) * q
					pose.torso_pitch_deg -= degrees * amount
					var tx: Transform3D = P.world_transform(p, pose)
					shift = maxf(shift, tx.origin.distance_to(original.origin))
					face = minf(face, G.face_clearance(p, pose));chest = minf(chest, G.sampled_chest_clearance(p, pose, surface))
					reach = maxf(reach, (tx * PaddleSize.MAIN_GRIP_OFFSET).distance_to(G.Body.shoulder_world(p, pose)))
			rows.append({"deg": degrees, "face": face, "chest": chest, "paddle_shift": shift, "max_grip_reach": reach})
		print(kind, " ", JSON.stringify(rows))
	quit()
