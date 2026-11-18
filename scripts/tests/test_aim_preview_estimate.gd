extends SceneTree
const Estimate = preload("res://scripts/aim_preview_estimate.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Physics = preload("res://scripts/shot_physics.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var checks: = 0
var failures: Array[String] = []
var report: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	var physics = Physics.new()
	for style in range(7):
		for charge in [0.15, 0.75]:
			for target in [Vector3(-1.5, Flight.FLOOR_REST_Y, -4.6), Vector3(-2.3, Flight.FLOOR_REST_Y, -5.8)]:
				var origin: Vector3 = Styles.release_plan(Vector3(1.5, 1, 6.8), false, style).contact_position
				var actual: Dictionary = Styles.solve_launch(physics, origin, target, charge, 0, style)
				measure(origin, target, charge, 0, "AUTO", "SERVE", style, actual, "serve_%d" % style)
	for intent in ["AUTO", "DROP"]:
		for mode in range(3):
			for charge in [0.15, 0.75]:
				for origin in [Vector3(0.45, 1.2, 2.3), Vector3(-1.2, 0.55, 5.8)]:
					var target: = Vector3(1.7, Flight.FLOOR_REST_Y, -1.15 if intent == "DROP" else -5.2)
					var actual: Dictionary = physics.solve_aimed_launch(origin, target, charge, 0, mode, intent, "", 0)
					measure(origin, target, charge, mode, intent, "", -1, actual, intent + "_%d" % mode)
	var blocked: Dictionary = Estimate.solve(Vector3(0.4, 0.15, 0.03), Vector3(0.4, Flight.FLOOR_REST_Y, -6.1), 0.75, 0, "AUTO", "", 0)
	check(Estimate.risk_label(blocked) == "NET RISK", "near-net impossible estimate needs an honest net warning")
	if not blocked.net_clear:
		check(blocked.points[blocked.points.size() - 1].is_equal_approx(blocked.net_crossing), "net-risk preview incorrectly draws through net")
	check(Estimate.risk_label({"landing": Vector3(3.3, Flight.FLOOR_REST_Y, -4), "net_clear": true, "feasible": false}) == "OUT RISK", "out-of-bounds estimate needs an honest warning")
	check(Estimate.risk_label({}) == "ARC UNCERTAIN", "empty estimate must not claim a confident target")
	var file = FileAccess.open("/tmp/aim-preview-estimate-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": report}, "  "));file.close()
	for failure in failures: push_error(failure)
	print("AIM PREVIEW ESTIMATE: ", checks, " checks, ", failures.size(), " failures; cases=", report.size())
	quit(0 if failures.is_empty() else 1)
func measure(origin: Vector3, target: Vector3, charge: float, mode: int, intent: String, kind: String, style: int, actual: Dictionary, label: String):
	var started: = Time.get_ticks_usec()
	var estimate: Dictionary = Estimate.solve(origin, target, charge, mode, intent, kind, 0, style)
	var cost: int = Time.get_ticks_usec() - started
	check(estimate.get("candidates", 0) == 2 and estimate.get("integration_steps", 99999) <= 1400, "preview exceeded bounded work " + label)
	check(estimate.points.size() <= 48, "preview exceeded drawing budget " + label)
	var error: float = estimate.landing.distance_to(actual.landing) if estimate.has("landing") and actual.has("landing") else INF
	if estimate.get("feasible", false):
		check(estimate.target_error < 0.2 and error < 0.3, "confident estimated landing materially differs from committed solve " + label)
		check(actual.get("feasible", false), "preview claims certainty where actual solver is infeasible " + label)
	report.append({"kind": label, "origin": origin, "target": target, "charge": charge, "host_usec": cost, "feasible": estimate.get("feasible", false), "net_clear": estimate.get("net_clear", false), "actual_feasible": actual.get("feasible", false), "landing_error_vs_commit_m": error, "target_error_m": estimate.get("target_error", INF), "steps": estimate.integration_steps})
	print("PREVIEW CASE ", report.back())
