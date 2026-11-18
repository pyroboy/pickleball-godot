extends SceneTree


var game
var checks: = 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var hits: = 0
var drop_selected: = false
func _initialize() -> void : call_deferred("run")
func check(ok: bool, text: String) -> void :
	checks += 1
	if not ok: failures.append(text);print("FAIL: ", text)
func frames(count: int) -> void :
	for i in count: await process_frame; await physics_frame
func touch(pressed: bool) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = 51;event.position = game.mobile_controls._charge_center;event.pressed = pressed
	if not pressed and drop_selected: event.position += Vector2.DOWN * game.mobile_controls._charge_radius * 1.1
	root.push_input(event, true)
func drop() -> void :
	var event: = InputEventScreenDrag.new()
	event.index = 51
	event.position = game.mobile_controls._charge_center + Vector2.DOWN * game.mobile_controls._charge_radius * 1.1
	root.push_input(event, true)
func run() -> void :
	create_timer(150, true).timeout.connect( func(): quit(2))
	root.size = Vector2i(540, 960);root.content_scale_size = Vector2i(720, 1280)
	for difficulty in [0, 1, 2]:
		for soft in [true, false]:
			for intent in ["AUTO", "DROP"]:
				game = load("res://scenes/game.tscn").instantiate()
				root.add_child(game);current_scene = game
				await frames(5)


				game.pvp_mode = true;game.aim_focus._sync_realtime_mode()
				game.ai_difficulty = difficulty
				drop_selected = intent == "DROP"
				game._reset_match();game._set_game_state(game.GameState.PLAYING)
				game.rally_scorer._serve_was_hit = true
				game.player_right.set_ai_movement_enabled(false)
				var p = game.player_left
				p.global_position = Vector3(0, p.ground_y, 3.2)
				p.hitting.clear_charge_visual();p.hitting.serving_visual_active = false
				p.leg_ik.feet_initialized = false;p._process(0);p.can_volley_from_feet()
				var origin: = Vector3(0.42, 0.3, -4.0)
				var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, Vector3(0.42, 1.12, 2.6), 1.85)
				game.ball.reset_rally_state();game.ball.both_bounces_complete = true
				game.ball.last_hit_by = 1;game.ball.is_in_play = true
				game.ball.global_position = origin;game.ball.linear_velocity = launch.velocity;game.ball.angular_velocity = Vector3.ZERO;game.ball.flight_id += 1
				var case_hits: = hits
				game.ball.hit_by_paddle.connect( func(team): if team == 0: hits += 1)
				var pressed: = false
				var released: = false
				var held_frames: = 0
				var chosen: = -1.0
				var perfect: = false
				for tick in 220:
					await frames(1)
					var ring = game.reaction_button
					if not pressed and ( not soft or ring.is_perfect()):
						touch(true)
						if intent == "DROP": drop()
						pressed = true
					elif pressed and not released:
						held_frames += 1
						if held_frames >= 3 and ring.is_perfect():
							chosen = game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME
							perfect = ring.is_perfect()
							touch(false)
							released = true
					if hits > case_hits or game.game_state != game.GameState.PLAYING: break
				var tag: = "%d_%s_%s" % [difficulty, "soft" if soft else "full", intent]
				check(pressed and released and perfect, tag + " did not use real perfect-window touch release")
				check(chosen >= 0 and (chosen < 0.16 if soft else chosen > 0.95), tag + " chosen charge fixture wrong")
				check(hits == case_hits + 1, tag + " missed finite paddle contact")
				var actual: float = float(game.last_shot_profile.get("charge", -1))
				check(absf(actual - chosen) < 0.04, tag + " timing overwrote chosen power")
				check(game.last_shot_profile.get("shot_type", "") == "DROP" if intent == "DROP" else game.last_shot_profile.get("mode", -1) == 0, tag + " selected shot intent changed")
				rows.append({"case": tag, "difficulty": difficulty, "intent": intent, "soft": soft, "perfect": perfect, "chosen_charge": chosen, "committed_charge": actual, "speed": game.ball.linear_velocity.length(), "hit": hits == case_hits + 1})
				print("POWER CASE ", rows.back())
				touch(false);game.mobile_controls.cancel_all();game.queue_free();game = null
				await frames(3)
	for difficulty in [0, 1, 2]:
		var soft_flat: Dictionary = rows[difficulty * 4]
		var full_flat: Dictionary = rows[difficulty * 4 + 2]
		check(float(full_flat.speed) > float(soft_flat.speed) + 0.5, "Full flat is not stronger than soft flat difficulty %d" % difficulty)
	var file: = FileAccess.open("/workspace/scratch/6b6e64f75bd2/verification/combined-code9/power-intent.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "hits": hits, "cases": rows}, "\t"));file.close()
	print("RELEASE POWER INTENT: ", checks, " checks; failures=", failures.size(), "; actual_hits=", hits)
	quit(0 if failures.is_empty() else 1)
