extends SceneTree

const Geometry = preload("res://scripts/paddle_clearance.gd")
const HandPresentation = preload("res://scripts/player_hand_presentation.gd")
const Styles = preload("res://scripts/serve_style.gd")
var checks: = 0
var failures: Array[String] = []
var minimum_gap: = INF
var maximum_gap: = - INF

func _initialize() -> void :
	call_deferred("run")

func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.game_serve.set_process(false)
	for side in [0, 1]:
		game.serving_team = side
		game._reset_ball()
		var player = game.player_left if side == 0 else game.player_right
		for style in range(7):
			game.game_serve.selected_serve_style = style
			for height_index in range(17):
				var offset: Vector3 = Styles.hold_offset(style)
				offset.y = 0.08 + 0.37 * height_index / 16.0
				game.game_serve._held_position = player.global_position + player._get_forehand_axis() * offset.x + Vector3.UP * offset.y + player._get_forward_axis() * offset.z
				for index in range(21):
					var charge: float = index / 20.0
					player.hitting.set_underhand_serve_charge(charge)
					player._process(1.0 / 60.0)
					var hand: MeshInstance3D = player.left_arm_node.hand_mesh
					var ball_center: Vector3 = game.game_serve.get_held_ball_position()
					var gap: float = HandPresentation.ball_surface_gap(player.left_arm_node, ball_center, Ball.BALL_RADIUS)
					minimum_gap = minf(minimum_gap, gap)
					maximum_gap = maxf(maximum_gap, gap)
					checks += 2
					var tag: = "side%d style%d hold%.4f charge%.2f" % [side, style, offset.y, charge]
					if absf(gap) > 0.003:
						failures.append(tag + " ball/hand gap %.6fm" % gap)
					var reach: float = player.left_arm_node.hand_pivot.global_position.distance_to(player.left_arm_node.upper_pivot.global_position)
					if reach > 0.705:
						failures.append(tag + " support reach %.6fm" % reach)
	game.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SERVE PRESENTATION: %d checks, %d failures; gap %.6f to %.6fm" % [checks, failures.size(), minimum_gap, maximum_gap])
	quit(0 if failures.is_empty() else 1)
