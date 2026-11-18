extends SceneTree
const M = preload("res://scripts/drive_serve_motion.gd")
const S = preload("res://scripts/serve_style.gd")
const P = preload("res://scripts/stroke_swing_path.gd")
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
func _initialize(): call_deferred("run")
func run():
	var player = Side.new(0)
	var rows: Array = []
	for x in [0.1, 0.14, 0.18]:
		for forward in [ - 0.04, 0.0, 0.04]:
			var minimum: = INF; var bad: = 0; var worst: = ""
			for style in [2, 4, 5, 6]:
				var plan: Dictionary = S.release_plan(player.global_position, false, style)
				for q in [0.0, 0.25, 0.5, 0.75, 1.0]:
					for sample in plan.samples:
						if sample.time >= plan.contact_time - 0.001: break
						var elapsed: float = sample.time
						var pose: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, q, player.global_position.y)
						var progress: float = clampf(1.0 - (plan.contact_time - elapsed) / S.stroke_duration(style), 0, 1)
						var weight: float = smoothstep(0, 1, elapsed / 0.12) * (1.0 - smoothstep(0, 0.65, progress))
						pose.paddle_forehand_mul += x * weight;pose.paddle_forward_mul += forward * weight
						var tx: Transform3D = P.world_transform(player, pose)
						var gap: float = G.distance_to_paddle_shape(tx.affine_inverse() * sample.pos) - 0.0375
						if gap < minimum: minimum = gap;worst = "style%d q%.2f t%.4f" % [style, q, elapsed]
						if gap < - 0.001: bad += 1
			rows.append({"x": x, "forward": forward, "minimum": minimum, "bad": bad, "worst": worst})
	print(JSON.stringify(rows))
	quit()
