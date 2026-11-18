extends "res://scripts/tests/cloud_movement_f_temporal_reticle_runtime.gd"
## Large real thumb drags and ordinary menu boundaries. No fabricated game state.
var menu_edges: Array = []

func build_schedule() -> void:
	schedule=[[2.5,"pause"],[2.8,"resume"],[4.2,"guide_open"],[4.5,"guide_close"],[5.5,"settings_open"],[5.9,"settings_close"],[6.2,"resume"],[9.0,"reset_open"],[9.3,"reset_cancel"],[9.6,"resume"],[12.0,"reset_open"],[12.3,"reset_confirm"],[15.0,"practice_DRIVE"]]

func driver(now: int) -> void:
	super.driver(now)
	if is_instance_valid(game) and driver_hit and game.aim_controller.mode=="AIM" and not game.mobile_controls._blocked():
		var mobile=game.mobile_controls
		hit_position=mobile._charge_center+Vector2(sin(elapsed()*4.1),cos(elapsed()*3.3)).limit_length(1.0)*mobile._charge_radius*0.95
		drag(41,hit_position)

func lifecycle(kind: String, nominal: float) -> void:
	var before:Dictionary={"held":Input.is_action_pressed("ui_accept"),"cursor":game.game_trajectory.landing_cursor.visible,"focus":game.aim_focus.active,"state":game.game_state,"ball_position":game.ball.global_position}
	await super.lifecycle(kind,nominal)
	if is_instance_valid(game):
		var edge:Dictionary={"action":kind,"elapsed":elapsed(),"before":before,"after":{"held":Input.is_action_pressed("ui_accept"),"cursor":game.game_trajectory.landing_cursor.visible,"focus":game.aim_focus.active,"paused":paused,"state":game.game_state,"ball_position":game.ball.global_position},"reset_before":reset_before}
		menu_edges.append(edge);event("reticle_menu_edge",edge)

func run() -> void:
	await super.run()
	FileAccess.open(output.path_join("reticle_menu_edges.json"),FileAccess.WRITE).store_string(JSON.stringify(menu_edges,"\t"))
