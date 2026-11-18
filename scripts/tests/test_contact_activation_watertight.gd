extends SceneTree
const Zones = preload("res://scripts/contact_activation_zones.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Regions = preload("res://scripts/preparation_superblocks.gd")
const CourtSide = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
var records: Array = []
class IncomingBall extends RefCounted:
	var is_in_play := true
	var last_hit_by := 1
	var bounces_since_last_hit := 1
	var both_bounces_complete := true
	var global_position := Vector3.ZERO
	var linear_velocity := Vector3.BACK * 8.0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func world(player, x: float, height: float, front: float) -> Vector3:
	return Vector3(player.global_position.x, player.COURT_FLOOR_Y + height, player.global_position.z) + player._get_forehand_axis() * x + player._get_forward_axis() * front
func point_owners(x: float, height: float) -> Array:
	var owners: Array = []
	for def in PostureLibrary.instance().all_definitions():
		if def.has_zone and Zones.contains(def, x, height): owners.append(def.posture_id)
	return owners
func run():
	var lib := PostureLibrary.instance()
	var originals: Dictionary = {}
	for def in lib.all_definitions():
		originals[def.posture_id] = Vector4(def.zone_x_min, def.zone_x_max, def.zone_y_min, def.zone_y_max)
	Zones.refresh()
	var bridge_count := 0
	for region in Zones.display_regions():
		var rect: Rect2 = region.rect
		if region.bridge: bridge_count += 1
		# Exact face/edge/corner membership from the same geometry the debug boxes use.
		for x in [rect.position.x, rect.get_center().x, rect.end.x]:
			for height in [rect.position.y, rect.get_center().y, rect.end.y]:
				check(not point_owners(x, height).is_empty(), "displayed activation face/edge/corner has no owner")
				for id in region.owners:
					check(Zones.contains(lib.get_def(id), x, height), "display and detector disagree for owner%d" % id)
	check(bridge_count > 0, "no gaps were repaired")
	# Every row/column interval bracketed by original zones is continuously covered.
	for xi in range(-87, 110):
		for yi in range(27, 215):
			var x: float = xi * 0.01
			var y: float = yi * 0.01
			var left := false; var right := false; var below := false; var above := false
			for def in lib.all_definitions():
				if not def.has_zone: continue
				if y >= def.zone_y_min - .03 and y <= def.zone_y_max + .03:
					left = left or def.zone_x_max + .03 <= x
					right = right or def.zone_x_min - .03 >= x
				if x >= def.zone_x_min - .03 and x <= def.zone_x_max + .03:
					below = below or def.zone_y_max + .03 <= y
					above = above or def.zone_y_min - .03 >= y
			if left and right or below and above:
				check(not point_owners(x, y).is_empty(), "interior gap x%.3f y%.3f" % [x, y])
	for side in range(2):
		var player = CourtSide.new(side)
		player.global_position = Vector3(0, 1.2, 3.8 if side == 0 else -3.8)
		player.global_transform.origin = player.global_position
		var ball := IncomingBall.new()
		ball.last_hit_by = 1 - side
		ball.linear_velocity = -player._get_forward_axis() * 8.0
		# Planning and scoring must agree: only first ground contact judges OUT.
		var correct_z: float = 3.0 if side == 0 else -3.0
		ball.bounces_since_last_hit = 0
		var airborne := {"samples": [{"pos": Vector3(3.3, .3, correct_z), "time": .1, "bounces": 0}]}
		check(is_inf(Planner.predicted_fault_time(player, ball, airborne)), "airborne boundary crossing cancels contact prediction")
		var first_in := {"samples": airborne.samples, "bounce_events": [{"pos": Vector3(3.06, player.COURT_FLOOR_Y, correct_z), "time": .2}, {"pos": Vector3(4.0, player.COURT_FLOOR_Y, correct_z), "time": .7}]}
		check(is_equal_approx(Planner.predicted_fault_time(player, ball, first_in), .7), "painted-line first bounce was rejected before second bounce")
		var first_out := {"bounce_events": [{"pos": Vector3(3.08, player.COURT_FLOOR_Y, correct_z), "time": .2}]}
		check(is_equal_approx(Planner.predicted_fault_time(player, ball, first_out), .2), "true first outside bounce failed prediction gate")
		ball.bounces_since_last_hit = 1
		for xy in [Vector2(-.30,.92), Vector2(0,1.74), Vector2(.21,.7), Vector2(.64,1.1), Vector2(-.21,.4)]:
			var point := world(player, xy.x, xy.y, .45)
			ball.global_position = point + player._get_forward_axis() * .5
			var flight := {"samples": [{"pos": ball.global_position, "time": 0.0, "bounces": 0}, {"pos": point - player._get_forward_axis() * .5, "time": .125, "bounces": 0}]}
			var plan := Planner.select(player, ball, flight)
			check(not plan.is_empty(), "reachable seam missing x%.2f y%.2f side%d" % [xy.x,xy.y,side])
			if not plan.is_empty():
				check(Planner.point_fits(player, plan.def, plan.point), "plan escaped physical reach")
				var wrist: Vector3 = Wrist.wrist_from_head(plan.point, Path.paddle_basis(player, plan.def), plan.def)
				check(wrist.distance_to(Body.shoulder_world(player, plan.def)) <= Wrist.link_budget(player, plan.def) + Wrist.NUMERICAL_EPSILON, "seam bypassed arm reach")
				check(Planner.select(player, ball, flight, plan.posture).posture == plan.posture, "overlap hysteresis lost selected owner")
				var saved_order: Array = lib.definitions.duplicate()
				lib.definitions.reverse()
				check(Planner.select(player, ball, flight).posture == plan.posture, "overlap depends on library order")
				lib.definitions = saved_order
				records.append({"side":side,"x":xy.x,"height":xy.y,"posture":plan.posture})
		# Fast lateral traversal: both physics sample endpoints lie outside reach,
		# while the segment crosses it. Nominal front-plane tests cannot catch it.
		for dt in [1.0/30.0, 1.0/60.0, 1.0/120.0]:
			var a := world(player,-1.3,1.05,.60)
			var b := world(player,1.3,1.05,.60)
			ball.global_position = a; ball.linear_velocity = (b-a)/dt
			var flight := {"samples":[{"pos":a,"time":0.0,"bounces":0},{"pos":b,"time":dt,"bounces":0}]}
			var plan := Planner.select(player, ball, flight)
			check(not plan.is_empty() and plan.get("swept_prediction",false), "fast lateral crossing lost at dt%.5f" % dt)
			if not plan.is_empty(): check(Planner.point_fits(player,plan.def,plan.point), "swept prediction has invalid contact")
			ball.bounces_since_last_hit=2
			check(Planner.select(player,ball,flight).is_empty(), "sweep bypassed second bounce")
			ball.bounces_since_last_hit=0;ball.both_bounces_complete=false
			check(Planner.select(player,ball,flight).is_empty(), "sweep bypassed opening bounce rule")
			ball.bounces_since_last_hit=1;ball.both_bounces_complete=true
		for point in [world(player,3.0,1.0,.5),world(player,0,3.0,.5),world(player,0,1.0,-.2),world(player,0,-.05,.5)]:
			var fitted := false
			for def in lib.all_definitions():
				if def.has_zone: fitted = fitted or Planner.point_fits(player,def,point)
			check(not fitted, "outside outer reach/floor/behind accepted")
	for def in lib.all_definitions():
		check(originals[def.posture_id] == Vector4(def.zone_x_min,def.zone_x_max,def.zone_y_min,def.zone_y_max), "authored source zone mutated")
	for failure in failures: push_error(failure)
	var file = FileAccess.open("/tmp/contact-activation-watertight.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"bridge_count":bridge_count,"cases":records},"\t"));file.close()
	print("CONTACT ACTIVATION WATERTIGHT: %d checks, %d failures; %d seam patches" % [checks,failures.size(),bridge_count])
	quit(0 if failures.is_empty() else 1)
