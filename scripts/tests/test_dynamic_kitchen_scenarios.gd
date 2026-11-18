extends SceneTree
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")


const Cases = preload("res://scripts/kitchen_exchange_scenarios.gd")
const Tactics = preload("res://scripts/ai_kitchen_tactics.gd")
const Feeds = preload("res://scripts/debug/kitchen_review_feeds.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var game
var checks: = 0
var failures: Array[String] = []
var hits: Array = []
var bounces: Array = []
var results: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, detail: String) -> void :
	checks += 1
	if not ok: failures.append(detail)
func run() -> void :
	results.append({"source_hashes": source_hashes(), "started_at": Time.get_datetime_string_from_system(true)})
	for team in [0, 1]:
		var wide: Vector3 = Cases.dink_target("WIDE", 0, team, 1)
		var center: Vector3 = Cases.dink_target("WIDE", 2, team, 1)
		check(absf(wide.x) - absf(center.x) > 0.8, "wide-to-center change is too small")
		check(Cases.dink_target("WIDE", 0, team, -1).x == - wide.x, "diagonal did not mirror")
	check(absf(Cases.recovery_x(1.8, -1.05)) < 1.0, "wide recovery did not cover toward center")
	check(absf(Cases.recovery_x(0.3, -1.05)) < absf(Cases.recovery_x(1.8, -1.05)), "central return did not change recovery")
	var context: = {"ball_height": 1.25, "net_height": 1.0, "net_distance": 2.1, "contact_distance": 0.8, "difficulty": 2}
	check(Tactics.attack_kind(context) == "SPEED_UP", "net-height popup selected smash")
	context.ball_height = 1.95
	check(Tactics.attack_kind(context) == "SMASH", "high reachable popup lacks overhead option")
	context.net_distance = 4.5
	check(Tactics.attack_kind(context) == "SPEED_UP", "distant high contact forced downward smash")
	context.net_distance = 2.1
	context.contact_distance = 1.2
	check(Tactics.attack_kind(context) != "SMASH", "stretched reach chose smash")
	context.incoming_speed = 13.0
	context.ball_height = 1.1
	check(Tactics.response_kind(context, 0.0) == "RESET", "strong low attack did not favor reset")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.ball.hit_by_paddle.connect(record_hit)
	game.ball.bounced.connect( func(point): bounces.append(point))
	var practice = game.practice_launcher
	game.score_left = 4
	game.score_right = 7
	for receiver in [0, 1]:
		for diagonal in [1, -1]:
			for kind in Cases.CASES:
				await run_case(kind, receiver, diagonal)
	await run_moving_sequences()
	await run_attack_sequences()
	practice.start_drill("DINK", true, 1, "ATTACK")
	check(practice.allow_attacks and not practice.needs_bounce(), "attack simulation stayed cooperative")
	practice.set_allow_attacks(false)
	check(practice.needs_bounce(), "cooperative toggle lost real bounce gate")
	practice.stop_practice()
	check(game.score_left == 4 and game.score_right == 7, "scenario exit changed match score")
	var finish_hashes: Dictionary = source_hashes()
	var changed_sources: Array[String] = []
	for path in results[0].source_hashes:
		if results[0].source_hashes[path] != finish_hashes.get(path, ""): changed_sources.append(path)
	results.append({"source_drift": changed_sources, "finished_at": Time.get_datetime_string_from_system(true)})
	check(changed_sources.is_empty(), "runtime source changed during scenario verification; rerun at freeze")
	var file = FileAccess.open("/tmp/dynamic-kitchen-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("DYNAMIC KITCHEN: %d checks, %d failures" % [checks, failures.size()])
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
func run_case(kind: String, receiver: int, diagonal: int) -> void :
	hits.clear()
	bounces.clear()
	var data: Dictionary = Feeds.scenario(game, kind, receiver, diagonal, 114)
	var player = game.player_left if receiver == 0 else game.player_right
	var start: Vector3 = player.global_position
	var previous: Vector3 = start
	var max_step: = 0.0
	var travel: = 0.0
	var moved_before_bounce: = false
	var p = game.practice_launcher
	for frame in range(240):
		await physics_frame
		var step: float = Vector2(player.global_position.x - previous.x, player.global_position.z - previous.z).length()
		max_step = maxf(max_step, step)
		travel += step
		previous = player.global_position
		if bounces.is_empty() and player.global_position.distance_to(start) > 0.15: moved_before_bounce = true
		if not hits.is_empty() or p._attempt_finished: break
	var tag: String = "%s P%d D%d" % [kind, receiver, diagonal]
	var hit: bool = not hits.is_empty() and hits[0].team == receiver
	check(max_step <= player.move_speed / Engine.physics_ticks_per_second + 0.006, tag + " teleported above movement limit")
	if kind == "UNREACHABLE":
		check( not hit, tag + " manufactured an out-of-reach return")
		check(p._attempt_finished and p.last_failure == "DOUBLE_BOUNCE", tag + " did not finish as an in-bounds missed return")
	else:
		check(hit, tag + " did not reach the real ball")
	if kind in ["WIDE", "CENTER", "ACUTE"]:
		check(travel > 0.25 and moved_before_bounce, tag + " lacks anticipatory foot travel")
	if hit:
		var h: Dictionary = hits[0]
		check(absf(h.surface - 0.0375) <= 0.0051, tag + " ball missed visible paddle surface")
		check(h.wrist <= 0.7001, tag + " stretched connected arm")
		check( not h.volley or not h.foot_fault, tag + " illegal NVZ volley")
		if kind in ["WIDE", "CENTER", "ACUTE", "SHORT_LOW", "SAFE_DINK"]:
			check( not h.volley and not bounces.is_empty(), tag + " skipped real bounce")
	results.append({"case": tag, "hit": hit, "travel": travel, "max_step": max_step, "anticipation": moved_before_bounce, 
		"bounces": bounces.size(), "response": p.last_response_kind, "failure": p.last_failure})
	print("DYNAMIC CASE ", results.back())
	p.stop_practice()
	await physics_frame
func record_hit(team: int) -> void :
	var player = game.player_left if team == 0 else game.player_right
	var pose: PostureDefinition = player.posture.transition_pose_blend
	if pose == null: pose = PostureLibrary.instance().get_def(player.paddle_posture)
	var hand: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
	var grip: Vector3 = player.paddle_node.to_global(PaddleDimensions.MAIN_GRIP_OFFSET + hand)
	hits.append({"team": team, "volley": game.ball.was_volley, 
		"surface": Geometry.distance_to_head_shape(player.paddle_node.to_local(game.ball.global_position)), 
		"grip": grip.distance_to(WristReach.live_shoulder(player, pose)), 
		"wrist": WristReach.displayed_wrist(player, pose).distance_to(WristReach.live_shoulder(player, pose)), 
		"foot_fault": game.rally_scorer._ground_contact_in_kitchen(player), 
		"response": game.practice_launcher.last_response_kind, "speed": game.ball.linear_velocity.length()})

func run_attack_sequences() -> void :
	var attacks: = 0
	var resets: = 0
	var popups: = 0
	for receiver in [0, 1]:
		for trial in range(4):
			hits.clear()
			bounces.clear()
			Feeds.scenario(game, "HIGH_POPUP", receiver, 1, 110 + trial)
			var practice = game.practice_launcher
			practice.demo_enabled = true
			for frame in range(480):
				await physics_frame
				if practice._attempt_finished or hits.size() >= 6: break



			if trial == 0:
				check(hits.size() >= 2, "targeted attack/reset pair did not make two real contacts for receiver %d" % receiver)
				if hits.size() >= 2:
					check(hits[0].response in ["SMASH", "SPEED_UP"] and hits[1].response == "RESET", "targeted strong attack did not receive a real block/reset")
			check(practice.last_failure in ["", "DOUBLE_BOUNCE", "OUT_OF_BOUNDS", "BALL_IN_NET"], "attack sequence ended through an illegal or unexplained return: " + practice.last_failure)
			for hit in hits:
				if hit.response in ["SMASH", "SPEED_UP"]: attacks += 1
				if hit.response == "RESET": resets += 1
				if hit.response in ["POPUP", "HIGH_POPUP"]: popups += 1
				check( not hit.volley or not hit.foot_fault, "attack sequence used NVZ volley")
				check(absf(hit.surface - 0.0375) <= 0.0051 and hit.wrist <= 0.7001, "attack sequence manufactured contact")
			results.append({"attack_receiver": receiver, "seed": 110 + trial, "hits": hits.size(), "outcome": practice.last_failure, "responses": hits.map( func(hit): return hit.response)})
			print("ATTACK SEQUENCE receiver=", receiver, " seed=", 110 + trial, " hits=", hits, " failure=", practice.last_failure)
			practice.stop_practice()
			await physics_frame
	check(attacks > 0, "high popups never produced a legal strong attack")
	check(resets > 0, "strong attacks never produced a real block/reset")
	results.append({"attack_sequences": 8, "attacks": attacks, "resets": resets, "popups": popups})

func source_hashes() -> Dictionary:
	var hashes: = {}
	_hash_directory("res://scripts", hashes)
	_hash_directory("res://data", hashes)
	_hash_directory("res://scenes", hashes)
	for path in ["res://project.godot", "res://scripts/debug/kitchen_review_feeds.gd", "res://scripts/tests/test_dynamic_kitchen_scenarios.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _hash_directory(path: String, hashes: Dictionary) -> void :
	for file in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd", "tres", "tscn"]:
			var full: String = path.path_join(file)
			hashes[full] = FileAccess.get_sha256(full)
	for directory in DirAccess.get_directories_at(path):
		if directory not in ["archive", "tests", "debug"]: _hash_directory(path.path_join(directory), hashes)

func run_moving_sequences() -> void :
	for diagonal in [1, -1]:
		hits.clear()
		bounces.clear()
		var practice = game.practice_launcher
		practice.start_drill("DINK", true, diagonal, "WIDE")
		practice.loop_enabled = false
		var minimum: Array[float] = [game.player_left.global_position.x, game.player_right.global_position.x]
		var maximum: Array[float] = minimum.duplicate()
		var recovery_seen: Array[bool] = [false, false]
		var previous_error: Array[float] = [0.0, 0.0]
		var previous_flight: = -1
		for frame in range(1000):
			await physics_frame
			for team in [0, 1]:
				var player = game.player_left if team == 0 else game.player_right
				minimum[team] = minf(minimum[team], player.global_position.x)
				maximum[team] = maxf(maximum[team], player.global_position.x)
				var error: float = absf(practice.get_exchange_home(team).x - player.global_position.x)
				if game.ball.last_hit_by == team and game.ball.flight_id == previous_flight and previous_error[team] > 0.3 and error < previous_error[team] - 0.015:
					recovery_seen[team] = true
				previous_error[team] = error
			previous_flight = game.ball.flight_id
			if practice._attempt_finished or hits.size() >= 6: break
		check(hits.size() >= 6, "moving diagonal %d failed to sustain six real contacts" % diagonal)
		for team in [0, 1]:
			check(maximum[team] - minimum[team] > 0.55, "moving diagonal %d player %d stayed in a fixed lane" % [diagonal, team])
			check(recovery_seen[team], "moving diagonal %d player %d did not recover toward angle-aware home" % [diagonal, team])
		results.append({"moving_sequence_diagonal": diagonal, "hits": hits.size(), "min_x": minimum, "max_x": maximum, "recovery": recovery_seen})
		practice.stop_practice()
		await physics_frame
