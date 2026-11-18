extends SceneTree
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Rule = preload("res://scripts/player_nvz_state.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func place(p, z: float, r: float, l: float, ry: float = 0.115, ly: float = 0.115) -> void :
	p.global_position = Vector3(0, 1, z)
	p.is_jumping = false
	p.posture.force_posture_update(PostureLibrary.instance().get_def(20))
	var feet: Array[Vector3] = [Vector3(0.24, ry, r), Vector3(-0.24, ly, l)]
	p.leg_ik._reset_feet(feet)
	p.leg_ik._last_body_position = Vector3(0, 0.115, z)
	p.leg_ik._solve_legs(0, PostureLibrary.instance().get_def(20), true)
func run():
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for side in [0, 1]:
		var p = game.player_left if side == 0 else game.player_right
		var sign_side: float = 1.0 if side == 0 else -1.0
		var b = game.ball
		b.is_in_play = true
		b.last_hit_by = 1 - side
		b.both_bounces_complete = true
		b.bounces_since_last_hit = 0
		b.was_volley = true
		p._nvz_state = Rule.new()
		place(p, 3 * sign_side, 3 * sign_side, 3 * sign_side)
		check(p.can_volley_from_feet(), "both established outside permits volley")
		check(Planner.legal_ball(p, b), "planner allows established outside")
		check(game.rally_scorer.check_kitchen_volley_at_hit(side, p.global_position.z).valid, "scorer agrees outside")
		var footprint: Dictionary = Rule.footprints(p)[0]
		var toe_overhang: float = 3.0 - footprint.min.z if side == 0 else footprint.max.z + 3.0
		var toe_center: float = (PickleballConstants.NON_VOLLEY_ZONE + toe_overhang) * sign_side
		place(p, 2.35 * sign_side, toe_center, 2.5 * sign_side)
		check(Rule.touches_ground(p), "actual toe on painted line is ground contact")
		check( not p.can_volley_from_feet(), "root outside but toe on line cannot volley")
		check( not Planner.legal_ball(p, b), "human planner rejects toe-on-line volley")
		check( not game.rally_scorer.check_kitchen_volley_at_hit(side, p.global_position.z).valid, "scorer agrees toe-on-line")
		place(p, 2.35 * sign_side, toe_center, 2.5 * sign_side, 0.25, 0.115)
		check( not Rule.touches_ground(p), "lifted illegal shoe no longer touches floor")
		check( not p.can_volley_from_feet(), "lifting illegal foot does not erase touch history")
		b.bounces_since_last_hit = 1
		check(Planner.legal_ball(p, b), "bounced dink remains legal inside kitchen")
		b.was_volley = false
		check(game.rally_scorer.check_kitchen_volley_at_hit(side, p.global_position.z).valid, "scorer permits bounced dink")
		b.bounces_since_last_hit = 0
		b.was_volley = true
		place(p, 2.35 * sign_side, 2.55 * sign_side, 2.55 * sign_side, 0.25, 0.115)
		check( not p.can_volley_from_feet(), "one outside foot still airborne is not re-establishment")
		place(p, 2.35 * sign_side, 2.55 * sign_side, 2.55 * sign_side)
		check(p.can_volley_from_feet(), "both grounded outside restores volley permission")
		place(p, 2.35 * sign_side, 2.55 * sign_side, 2.55 * sign_side, 0.3, 0.3)
		p.is_jumping = true
		check(p.can_volley_from_feet(), "legal jump retains established outside history")
		check(Planner.legal_ball(p, b), "planner permits legal airborne volley")
		place(p, 2.35 * sign_side, toe_center, 2.55 * sign_side)
		check( not p.can_volley_from_feet(), "landing toe in kitchen clears permission")
		game.rally_scorer._volley_momentum_watches = {side: {"time": Time.get_ticks_msec(), "stable_since": -1}}
		check( not game.rally_scorer.check_momentum_fault().valid, "post-volley toe crossing is a momentum fault")
	game.queue_free()
	await process_frame
	print("NVZ FOOT HISTORY: ", checks, " checks; failures=", failures)
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
