extends SceneTree
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")


class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void : create_tween().tween_callback( func(): presented.emit())
var checks: = 0
var errors: Array[String] = []
var records: Array = []
var game
var late
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: errors.append(label)
func tick() -> void :
	if game.game_state == game.GameState.WAITING and game.serving_team == 1:
		game.ai_serve_timer = game.game_serve.get_charge_ratio() / 0.8 * 1.5 if game.game_serve.is_charging() else 0.0
	await physics_frame
	await late.presented
func run() -> void :
	create_timer(80).timeout.connect( func(): quit(2))
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	late = LateFrame.new();late.process_priority = 10000;root.add_child(late)
	for side in [0, 1]:
		for style in range(7):


			var charges: Array = [0.3, 0.9] if side == 0 else [0.3, 0.7]
			for charge in charges:
				game.serving_team = side;game._reset_ball();game.game_serve.select_serve_style(style)
				game.player_right.set_ai_movement_enabled(false)
				var p = game.player_left if side == 0 else game.player_right
				var arm = p.left_arm_node; var model = arm.articulated_hand
				for frame in range(12): await tick()
				game.game_serve.start_charge();game.game_serve.tick_charge(charge * PickleballConstants.MAX_SERVE_CHARGE_TIME)
				for frame in range(3): await tick()
				var tag: = "side%d style%d charge%.1f" % [side, style, charge]
				check(absf(model.ball_surface_gap(arm.hand_mesh.to_local(game.ball.global_position))) < 0.0002, tag + " held skin tangent")
				var held_center: Vector3 = game.ball.global_position
				game.game_serve.release(charge)
				check(game.ball.linear_velocity.length() < 1e-05, tag + " unforced release")
				var worst: float = INF; var worst_elapsed: = 0.0; var data: Array = []
				for frame in range(16):
					await tick()
					var elapsed: float = game.game_serve._release_elapsed
					if elapsed > 0.2 or game.ball.is_in_play: break
					if frame == 0:
						var preview_pose: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, charge, p.global_position.y)
						var hands = p.arm_ik._hands
						var offset: Vector3 = preview_pose.get_meta("preview_serve_held_offset")
						var editor_held: Transform3D = hands._serve_grasp_mount(arm, held_center, preview_pose.get_meta("preview_serve_charge"), offset.y)
						check(editor_held.origin.distance_to(hands._last_held_mount.origin) < 2e-05 and editor_held.basis.is_equal_approx(hands._last_held_mount.basis), tag + " editor release reconstructs the same original held frame as real input")
					var gap: float = model.ball_surface_gap(arm.hand_mesh.to_local(game.ball.global_position))
					check(arm.visual_stretch <= 1.001, tag + " release keeps true arm reach")
					if gap < worst: worst = gap;worst_elapsed = elapsed
					data.append({"elapsed": elapsed, "gap_m": gap, "mode": model._mode, "closure": model._closure})
				check(worst >= - 0.002, tag + " release skin gap %.5fm at %.4fs" % [worst, worst_elapsed])
				records.append({"case": tag, "minimum_gap_m": worst, "at_seconds": worst_elapsed, "samples": data})
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/serve-hand-release-clearance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "  "));file.close()
	print("SERVE HAND RELEASE: ", checks, " checks, ", errors.size(), " failures")
	for error in errors: push_error(error)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game, late)
	quit(0 if errors.is_empty() else 1)
