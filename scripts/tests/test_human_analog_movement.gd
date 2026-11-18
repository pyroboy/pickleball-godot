extends SceneTree

var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func clear_input():
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
func run():
	create_timer(10).timeout.connect( func(): push_error("Analog movement timeout");quit(2))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup();game.aim_controller.cancel()
	var player = game.player_left;player.hitting.serving_visual_active = false
	game.ball.is_in_play = false;game.ball.freeze = true
	var speeds: Array[float] = []
	for strength in [0.2, 0.5, 1.0]:
		clear_input();player.global_position = Vector3(0, 1, 4);player.current_velocity = Vector3.ZERO
		Input.action_press("move_right", strength)
		var expected: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var start: Vector3 = player.global_position
		player._physics_process(0.05)
		var speed: float = Vector2(player.current_velocity.x, player.current_velocity.z).length();speeds.append(speed)
		check(absf(speed - player.move_speed * expected.length()) < 0.0001, "analog speed remains proportional at strength%.2f" % strength)
		check(absf(player.global_position.distance_to(start) - speed * 0.05) < 0.0001, "world displacement matches analog speed")
	check(speeds[0] > 0 and speeds[0] < speeds[1] and speeds[1] < speeds[2], "tiny, half, full deflections give distinct movement speeds")
	check(absf(speeds[2] - player.move_speed) < 0.0001, "keyboard/cardinal full input retains full speed")
	clear_input();player.global_position = Vector3(0, 1, 4)
	Input.action_press("move_right", 1);Input.action_press("move_up", 1);player._physics_process(0.05)
	check(absf(player.current_velocity.length() - player.move_speed) < 0.0001, "full diagonal capped at same speed")
	clear_input();player._physics_process(0.05)
	check(player.current_velocity == Vector3.ZERO, "release stops without stale drift")
	game.queue_free(); await process_frame
	print("HUMAN ANALOG MOVEMENT: ", checks, " checks; speeds=", speeds, "; failures=", failures)
	quit(0 if failures.is_empty() else 1)
