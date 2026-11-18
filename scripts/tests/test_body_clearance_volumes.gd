extends SceneTree
const Shape = preload("res://scripts/body_clearance.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const D = preload("res://scripts/player_body_dimensions.gd")
var checks: = 0
var failures: Array[String] = []
class Actor extends RefCounted:
	var player_num: = 0
	var global_position: = Vector3(0, 1, 0)
	var global_transform: = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT if player_num == 0 else Vector3.LEFT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD if player_num == 0 else Vector3.BACK
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and failures.size() < 80: failures.append(label)
func run() -> void :
	var player: = Actor.new()
	for side in [0, 1]:
		player.player_num = side
		for bend in [0.0, 18.0, -18.0]:
			var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
			pose.torso_pitch_deg = -28;pose.torso_yaw_deg = bend;pose.hip_yaw_deg = bend * 0.5;pose.spine_curve_deg = bend;pose.torso_roll_deg = bend * 0.3
			var geometry: Dictionary = Shape.volumes(player, pose)
			check(geometry.cells.size() == 16, "all actual body ring intervals included")
			var found: Dictionary = {}
			for cell in geometry.cells:
				found[cell.region] = true
				for vertex in cell.points: check(Shape.cell_margin(vertex, cell) <= 4e-05, "conservative cell contains skin vertices")
			for region in Shape.REGIONS: check(found.has(region), "region present: " + region)
			var root: Transform3D = player.global_transform * Body.pivot_transform(player, pose)
			var pelvis: Vector3 = root * Body.pelvis_transform(player, pose) * Vector3.ZERO
			var abdomen: Vector3 = root * Body.abdomen_transform(player, pose) * Vector3(0, D.ABDOMEN_LENGTH * 0.5, 0)
			check(Shape.point_margins(pelvis, geometry).pelvis < - 0.02, "pelvis centre detected")
			check(Shape.point_margins(abdomen, geometry).abdomen < - 0.01, "abdomen centre detected")
			var outside: Dictionary = Shape.point_margins(pelvis + Vector3.RIGHT * 2, geometry)
			for region in Shape.REGIONS: check(outside[region] > 0, "remote point outside body")
			var blade: Dictionary = Shape.sample_paddle(Transform3D(Basis.IDENTITY, abdomen), [Vector3.ZERO], geometry)
			check(blade.abdomen < 0, "paddle crossing stomach detected")
			var arm: Dictionary = Shape.sample_segment(abdomen - Vector3.RIGHT * 0.25, abdomen + Vector3.RIGHT * 0.25, 0.03, geometry)
			check(arm.abdomen < - 0.02, "arm capsule crossing stomach detected")
	var leg: Dictionary = Shape.leg_metrics(Vector3.ZERO, Vector3.DOWN * D.THIGH_LENGTH, Vector3.DOWN * (D.THIGH_LENGTH + D.SHIN_LENGTH))
	check(is_equal_approx(leg.thigh_scale, 1) and is_equal_approx(leg.shin_scale, 1) and is_equal_approx(leg.span_ratio, 1), "real central leg dimensions used")
	print("BODY CLEARANCE VOLUMES: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
