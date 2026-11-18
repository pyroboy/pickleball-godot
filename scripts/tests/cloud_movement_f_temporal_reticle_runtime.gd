extends "res://scripts/tests/cloud_movement_f_temporal_d_runtime.gd"
## Read-only authority checks around the late reticle callback plus current-frame contracts.
var strict_reticle := false
var pre_cursor
var authority_before: Dictionary = {}
var authority_frame := -1
var reticle_stats := {"frames":0,"visible_frames":0,"position_mismatches":0,"label_mismatches":0,"visibility_mismatches":0,"max_world_error":0.0,"max_screen_error":0.0,"authority_mutations":0}
var reticle_samples: Array = []

class BeforeCursor extends Node:
	var harness
	func _process(_delta: float) -> void:
		if harness.monitor and not harness.changing_scene and is_instance_valid(harness.game):
			harness.authority_before = harness.authority_snapshot()
			harness.authority_frame = Engine.get_process_frames()

func _initialize() -> void:
	strict_reticle = OS.get_cmdline_user_args().has("--strict-reticle")
	super._initialize()

func spawn_game() -> void:
	await super.spawn_game()
	if not is_instance_valid(pre_cursor):
		pre_cursor = BeforeCursor.new();pre_cursor.harness=self
		pre_cursor.process_mode=Node.PROCESS_MODE_ALWAYS;pre_cursor.process_priority=1001
		root.add_child(pre_cursor)

func authority_snapshot() -> Dictionary:
	var a=game.aim_controller
	var f=game.aim_focus
	return {"game_state":game.game_state,"score":[game.score_left,game.score_right],"server":game.serving_team,
		"ball_position":game.ball.global_position,"ball_velocity":game.ball.linear_velocity,"ball_omega":game.ball.angular_velocity,"flight":game.ball.flight_id,"bounce":game.ball.bounces_since_last_hit,"last_hit":game.ball.last_hit_by,
		"player_position":game.player_left.global_position,"player_velocity":game.player_left.current_velocity,
		"aim_target":a.target,"aim_locked_target":a._locked_target,"aim_mode":a.mode,"aim_planted":a.planted,"aim_context":a._context,
		"held":Input.is_action_pressed("ui_accept"),"owners":game.mobile_controls._owners.duplicate(),"charge":game.input_handler.serve_charge_time,
		"focus_active":f.active,"focus_deadline":f.deadline_usec,"rally_deadline":f._rally_deadline_usec,"focus_holding":f.holding,"time_scale":Engine.time_scale,
		"trajectory_key":game.game_trajectory._last_trajectory_key,"trajectory_clock":game.game_trajectory._last_preview_ms,
		"physics_frame":Engine.get_physics_frames()}

func observe(delta: float) -> void:
	if monitor and not changing_scene and is_instance_valid(game) and authority_frame==Engine.get_process_frames():
		var after:=authority_snapshot()
		if authority_before!=after:
			reticle_stats.authority_mutations+=1
			var differences:Dictionary={}
			for key in after:
				if after[key]!=authority_before[key]:differences[key]={"before":authority_before[key],"after":after[key]}
			check(false,"late presentation changed authority",differences)
	super.observe(delta)
	if not monitor or changing_scene or not is_instance_valid(game):return
	var a=game.aim_controller;var f=game.aim_focus;var t=game.game_trajectory;var m=game.mobile_controls
	var wall:bool=game.practice_launcher.is_wall()
	var target:Vector3=a.target
	var point:Vector3=target+Vector3(0,0,0.035) if wall else Vector3(target.x,0.105,target.z)
	var valid_context:bool=game.game_state==0 and game.serving_team==0 or game.game_state==2 and game.ball.is_in_play and game.ball.last_hit_by!=game.player_left.player_num and game.ball.bounces_since_last_hit<2
	var visible:bool=a.cursor_visible and Input.is_action_pressed("ui_accept") and not a.is_locked() and not m._cancel_armed and not m._blocked() and valid_context
	var label:String="CHECK ARC" if f.active and f.preview_hint!="ESTIMATED ARC" else "AIM" if wall else "ESTIMATED AREA"
	var actual:bool=t.landing_cursor.visible
	var world_error:float=t.landing_cursor.global_position.distance_to(point) if actual else 0.0
	var camera:Camera3D=root.get_camera_3d()
	var screen_error:=0.0
	if actual and not camera.is_position_behind(point) and not camera.is_position_behind(t.landing_cursor.global_position):screen_error=camera.unproject_position(point).distance_to(camera.unproject_position(t.landing_cursor.global_position))
	var position_bad:=actual and world_error>0.00001
	var label_bad:bool=actual and t.landing_label.text!=label
	var visibility_bad:bool=actual!=visible or t.landing_label.visible!=visible
	reticle_stats.frames+=1
	reticle_stats.visible_frames+=int(actual)
	reticle_stats.position_mismatches+=int(position_bad)
	reticle_stats.label_mismatches+=int(label_bad)
	reticle_stats.visibility_mismatches+=int(visibility_bad)
	reticle_stats.max_world_error=maxf(reticle_stats.max_world_error,world_error)
	reticle_stats.max_screen_error=maxf(reticle_stats.max_screen_error,screen_error)
	if position_bad or label_bad or visibility_bad:
		if reticle_samples.size()<60:reticle_samples.append({"elapsed":elapsed(),"flight":game.ball.flight_id,"position_bad":position_bad,"label_bad":label_bad,"visibility_bad":visibility_bad,"actual_label":t.landing_label.text,"expected_label":label,"world_error":world_error,"screen_error":screen_error,"state":last_state.duplicate(true)})
	if strict_reticle:
		check(not position_bad,"reticle endpoint differs from current aim after camera",{"world_error":world_error,"screen_error":screen_error})
		check(not label_bad,"reticle label differs from current focus")
		check(not visibility_bad,"reticle visibility differs from current context")

func run() -> void:
	await super.run()
	FileAccess.open(output.path_join("reticle_result.json"),FileAccess.WRITE).store_string(JSON.stringify({"strict":strict_reticle,"metrics":reticle_stats,"mismatch_samples":reticle_samples},"\t"))
