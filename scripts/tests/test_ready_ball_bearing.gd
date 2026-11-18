extends SceneTree
const Gaze = preload("res://scripts/player_head_gaze.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
class MockBall extends RefCounted:
	var global_position: = Vector3.ZERO
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	for team in [0, 1]:
		var player = Side.new(team); var ball = MockBall.new()
		for lateral in [-2.0, - 0.5, 0.0, 0.5, 2.0]:
			for up in [-1.0, 0.0, 8.0]:
				ball.global_position = player.global_position + player._get_forward_axis() * 3 + player._get_forehand_axis() * lateral + Vector3.UP * up
				var actual: float = Gaze.rest_body_yaw(player, ball)
				var expected: float = rad_to_deg(atan2(lateral, 3.0))
				check(absf(actual - expected) < 0.0001, "court%d lateral%.1f height%.1f horizontal bearing %.3f != %.3f" % [team, lateral, up, actual, expected])
		ball.global_position = player.global_position + Vector3.UP * 3
		check(is_zero_approx(Gaze.rest_body_yaw(player, ball)), "coincident horizontal ball remains neutral")
	for message in failures: push_error(message)
	print("READY BALL BEARING: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
