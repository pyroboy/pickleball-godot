class_name TestPaddleReachAndPoseData extends TestBase

func run_all(totals: Dictionary) -> void :
	var tests: Array[Callable] = [
		test_reach_clamps_only_outside_points, 
		test_all_stroke_postures_have_reachable_contact_zones, 
		test_procedural_motion_data_is_present, 
	]
	_run_test_list(totals, tests)

func test_reach_clamps_only_outside_points() -> void :
	var shoulder: = Vector3(0.18, 1.15, 0.0)
	var inside: = shoulder + Vector3.RIGHT * 0.7
	_assert_eq_v3(PaddleReach.clamp_head_world(inside, shoulder), inside, 0.0001)
	var outside: = shoulder + Vector3.RIGHT * 3.0
	var result: = PaddleReach.clamp_head_world(outside, shoulder)
	_assert_eq_f(result.distance_to(shoulder), PaddleReach.MAX_HEAD_DISTANCE, 0.0001)
	var below_floor: = shoulder + Vector3(2.0, -2.0, 0.0)
	var floor_result: = PaddleReach.clamp_head_with_floor(below_floor, shoulder, 0.375)
	_assert_ge(floor_result.y, 0.375, "paddle clears floor")
	_assert_le(floor_result.distance_to(shoulder), PaddleReach.MAX_HEAD_DISTANCE, "floor clamp preserves reach")

func test_all_stroke_postures_have_reachable_contact_zones() -> void :
	var defs: Array = PostureLibrary.instance().all_definitions()
	_assert_eq(defs.size(), 21, "all 21 stroke postures load")
	var zone_count: = 0
	for def in defs:
		var head: = Vector3(def.paddle_forehand_mul, 1.0 + def.paddle_y_offset, def.paddle_forward_mul)
		var shoulder: = Vector3(0.18, 1.15, 0.0)
		_assert_le(head.distance_to(shoulder), PaddleReach.MAX_HEAD_DISTANCE + 0.001, def.display_name + " paddle")
		if not def.has_zone:
			continue
		zone_count += 1
		_assert_lt(def.zone_x_min, def.zone_x_max, def.display_name + " X bounds")
		_assert_lt(def.zone_y_min, def.zone_y_max, def.display_name + " Y bounds")
		_assert_ge(def.zone_y_min, def.paddle_floor_clearance, def.display_name + " floor clearance")
		for x in [def.zone_x_min, def.zone_x_max]:
			for y in [def.zone_y_min, def.zone_y_max]:
				var contact: = Vector3(x, 0.075 + y, def.zone_forward_offset)
				_assert_le(contact.distance_to(shoulder), PaddleReach.MAX_HEAD_DISTANCE, def.display_name + " contact corner")
	_assert_eq(zone_count, 18, "ready and charge poses have no contact zone")

func test_procedural_motion_data_is_present() -> void :
	for def in PostureLibrary.instance().all_definitions():
		if def.posture_id in [8, 9, 20]:
			continue
		_assert_gt(def.charge_paddle_offset.length(), 0.0, def.display_name + " charge")
		_assert_gt(def.ft_paddle_offset.length(), 0.0, def.display_name + " follow through")
