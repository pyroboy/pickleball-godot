extends SceneTree

const Feet = preload("res://scripts/player_nvz_state.gd")
const Styles = preload("res://scripts/serve_style.gd")
var game
var checks := 0
var failures: Array[String] = []
var contacts := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func tick() -> void:
	await physics_frame
	await process_frame
func reset(team: int = 0, parity: int = 0) -> void:
	game.score_left = parity
	game.score_right = parity
	game.serving_team = team
	game._reset_ball()
	game.ai_serve_timer = 0.0
	game.game_serve.select_serve_style(0)

func shift_foot(p, side: int, offset: Vector3) -> void:
	if side == 0: p.leg_ik.right_foot_smooth += offset
	else: p.leg_ik.left_foot_smooth += offset
	p.leg_ik._solve_legs(0.0, p.posture.transition_pose_blend)

func run() -> void:
	create_timer(180.0).timeout.connect(func(): quit(2))
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await tick()
	game.input_handler.set_process(false)
	game.game_serve.serve_launched.connect(func(_team: int): contacts += 1)
	# Reproduce real manual repositioning while holding a serve. Previously these
	# stopped permanently in a stride, including two airborne feet after retreat.
	var moves: Array[Dictionary] = [
		{"action": "move_left", "frames": 2},
		{"action": "move_right", "frames": 4},
		{"action": "move_down", "frames": 5},
	]
	for style in range(7):
		for move in moves:
			reset()
			game.game_serve.select_serve_style(style)
			for i in 5: await tick()
			var p = game.player_left
			Input.action_press(move.action)
			for i in move.frames: await tick()
			Input.action_release(move.action)
			for i in 120: await tick()
			var tag: String = "style%d %s%d" % [style, move.action, move.frames]
			check(game.rally_scorer.check_server_position(p.global_position, 0, 1).valid, tag + " legal root fixture")
			check(p.leg_ik.is_support_ready(0) and p.leg_ik.is_support_ready(1), tag + " finishes both planted stance contacts")
			check(game.game_serve._legal_service_feet(p, 0), tag + " soles recover behind baseline")
			var planted: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
			game.game_serve.start_charge()
			game.game_serve.tick_charge(0.7 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			for i in 4: await tick()
			check(planted[0].is_equal_approx(p.leg_ik.right_foot_smooth) and planted[1].is_equal_approx(p.leg_ik.left_foot_smooth), tag + " charge preserves recovered planted stance")
			var before := contacts
			game.game_serve.release(0.7)
			for i in 150:
				await tick()
				if contacts > before or game.game_serve._service_fault_triggered: break
			check(contacts == before + 1, tag + " actual serve launches exactly once")
			check(not game.game_serve._service_fault_triggered, tag + " no false service fault")
	# Legality remains shoe-based: root behind baseline is insufficient if an
	# actual grounded shoe crosses a boundary. Check mirrored courts and parity.
	for team in [0, 1]:
		for parity in [0, 1]:
			for boundary in ["baseline", "sideline", "centerline", "airborne", "one_foot"]:
				reset(team, parity)
				game.game_serve._prepare_server(0.0)
				var p = game.player_left if team == 0 else game.player_right
				var footprints: Array[Dictionary] = Feet.footprints(p)
				check(game.game_serve._legal_service_feet(p, team), "default soles legal team%d parity%d" % [team, parity])
				match boundary:
					"baseline":
						var dz: float = PickleballConstants.BASELINE_Z - footprints[0].min.z - 0.001 if team == 0 else -PickleballConstants.BASELINE_Z - footprints[0].max.z + 0.001
						shift_foot(p, 0, Vector3(0, 0, dz))
					"sideline":
						shift_foot(p, 0, Vector3(PickleballConstants.COURT_WIDTH * 0.5 - footprints[0].max.x + 0.001, 0, 0))
					"centerline":
						var positive: bool = (parity == 0) == (team == 0)
						shift_foot(p, 0, Vector3(-footprints[0].min.x - 0.001 if positive else -footprints[0].max.x + 0.001, 0, 0))
					"airborne":
						shift_foot(p, 0, Vector3.UP * 0.1); shift_foot(p, 1, Vector3.UP * 0.1)
					"one_foot":
						shift_foot(p, 0, Vector3.UP * 0.1)
				var result: Dictionary = game.game_serve._check_service_feet(p, team)
				var tag: String = "team%d parity%d %s" % [team, parity, boundary]
				check(result.valid == (boundary == "one_foot"), tag + " real foot legality retained")
				if boundary != "one_foot":
					check(result.boundary == boundary, tag + " specific cause identified")
					check(not result.detail.is_empty(), tag + " useful explanation")
	# The contact path must carry each explanation through to the real HUD.
	for boundary in ["baseline", "sideline", "centerline", "airborne"]:
		reset()
		for i in 5: await tick()
		game.game_serve.start_charge(); game.game_serve.release(0.7)
		var p = game.player_left
		match boundary:
			"baseline": shift_foot(p, 0, Vector3(0, 0, PickleballConstants.BASELINE_Z - Feet.footprints(p)[0].min.z - .02))
			"sideline": shift_foot(p, 0, Vector3(2, 0, 0))
			"centerline": shift_foot(p, 0, Vector3(-2, 0, 0))
			"airborne":
				shift_foot(p, 0, Vector3.UP * 0.1); shift_foot(p, 1, Vector3.UP * 0.1)
		var result: Dictionary = game.game_serve._check_service_feet(p, 0)
		var before := contacts
		game.game_serve._launch_pending_serve()
		check(game.game_state == game.GameState.POINT_SCORED and game.serving_team == 1 and contacts == before, boundary + " genuine contact fault rejects launch")
		check(game.scoreboard_ui._hud.fault.text.contains(result.detail), boundary + " real HUD explains actual fault")
	print("SERVE POSITION FAULTS: %d checks, %d failures; %d/21 repositioned serves" % [checks, failures.size(), contacts])
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
