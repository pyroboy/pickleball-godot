extends SceneTree
const Tactics = preload("res://scripts/ai_kitchen_tactics.gd")
var failures: Array[String] = []
var checks: = 0
func check(ok: bool, text: String):
	checks += 1
	if not ok: failures.append(text)
func _initialize(): call_deferred("run")
func run():
	var rng: = RandomNumberGenerator.new()
	rng.seed = 96104
	var context: = {"near_kitchen": true, "legal_volley": true, "reachable": true, "balanced": true, "reaction_ready": true, "ball_height": 1.85, "net_height": 1.0, "difficulty": 1}
	var counts: Array[int] = []
	for difficulty in range(3):
		context.difficulty = difficulty
		var count: = 0
		for index in range(1000):
			if Tactics.choose(context, rng.randf()) == "ATTACK": count += 1
		counts.append(count)
		check(count > 200 and count < 950, "pop-up attack should be probabilistic")
	check(counts[0] < counts[1] and counts[1] < counts[2], "difficulty should increase attack tendency")
	for height in [0.35, 0.65, 0.95, 1.05]:
		context.ball_height = height
		check(Tactics.attack_probability(context) == 0.0 and Tactics.choose(context, 0.0) == "SOFT", "low dink must stay soft")
	context.ball_height = 1.85
	for blocker in ["legal_volley", "reachable", "balanced", "reaction_ready"]:
		context[blocker] = false
		check(Tactics.attack_probability(context) == 0.0, blocker + " did not prevent attack")
		context[blocker] = true
	context.near_kitchen = false
	check(Tactics.choose(context, 0.0) == "NORMAL", "baseline behavior wrongly replaced")
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var p = game.practice_launcher
	p.start_drill("DINK")
	check(p.allow_attacks and not p.demo_enabled and not p.needs_bounce(), "playable dink did not enable strategic attacks")
	p.set_allow_attacks(false)
	check(p.needs_bounce(), "cooperative toggle lost forced bounce")
	p.start_drill("DINK", true)
	check( not p.allow_attacks and p.needs_bounce(), "pose demo should remain cooperative")
	var brain = game.player_right.ai_brain
	var player = game.player_right
	player.leg_ik.feet_initialized = true
	player.leg_ik._last_body_position = player.global_position
	player.leg_ik.right_foot_smooth = Vector3(0.1, PickleballConstants.FLOOR_Y, -2.72)
	player.leg_ik.left_foot_smooth = Vector3(-0.1, PickleballConstants.FLOOR_Y, -2.72)
	check(brain._feet_established_outside_kitchen(), "both planted legal feet rejected")
	var footprint: Dictionary = preload("res://scripts/player_nvz_state.gd").footprints(player)[0]
	player.leg_ik.right_foot_smooth.z += - PickleballConstants.NON_VOLLEY_ZONE + 0.0002 - footprint.max.z
	check( not brain._feet_established_outside_kitchen(), "shoe on line allowed volley")
	player.leg_ik.right_foot_smooth = Vector3(0.1, PickleballConstants.FLOOR_Y + 0.15, -2.72)
	check( not brain._feet_established_outside_kitchen(), "foot leaving kitchen falsely established outside before landing")
	player.leg_ik.right_foot_smooth.y = PickleballConstants.FLOOR_Y
	check(brain._feet_established_outside_kitchen(), "both feet failed to re-establish outside")
	player.leg_ik.right_foot_smooth.y += 0.15
	check(brain._feet_established_outside_kitchen(), "legal foot lift from outside was rejected")
	var base_latency: int = brain._get_latency_frames()
	game._apply_setting("gameplay.reaction_delay", 0.2)
	check(brain._get_latency_frames() == base_latency + roundi(0.2 * Engine.physics_ticks_per_second), "reaction setting did not add latency")
	game._apply_setting("gameplay.reaction_delay", 0.0)
	check(brain._get_latency_frames() == base_latency, "reaction setting zero did not preserve baseline")
	p.stop_practice()
	var live_attacks: = 0
	var live_returns: = 0
	for trial in range(8):
		preload("res://scripts/debug/kitchen_review_feeds.gd").popup(game, 110 + trial)
		for frame in range(150):
			await physics_frame
			if game.ball.last_hit_by == 1 or p._attempt_finished: break
		if game.ball.last_hit_by == 1:
			live_returns += 1
			if brain.last_kitchen_tactic == "ATTACK": live_attacks += 1
			check( not game.ball.was_volley or brain._feet_established_outside_kitchen(), "live pop-up attack/return used illegal feet")
		print("POPUP LIVE trial=", trial, " tactic=", brain.last_kitchen_tactic, " hit=", game.ball.last_hit_by == 1, " fault=", p.last_failure)
		p.stop_practice()
		await physics_frame
	check(live_returns >= 6 and live_attacks > 0 and live_attacks < 8, "live pop-ups did not produce legal probabilistic attacks")
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("KITCHEN POPUP TACTICS: %d checks, %d failures; attack counts per 1000 E/M/H=%s" % [checks, failures.size(), counts])
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
