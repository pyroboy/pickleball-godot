extends "res://scripts/tests/cloud_movement_f_temporal_reticle_runtime.gd"
## Actual serve releases for every style and normal Wall practice; no state injection.
var scope_rows:Array=[]
var scope_counts:Dictionary={}
var scope_last:=""
func build_schedule()->void:
	schedule=[]
	for style in 7:
		schedule.append([0.2+float(style)*6.0,"serve_style_%d"%style])
	schedule.append([42.2,"practice_WALL"])

func lifecycle(kind:String, nominal:float)->void:
	if kind.begins_with("serve_style_"):
		release_driver()
		await super.lifecycle("reset_open",nominal)
		await frames(2)
		await super.lifecycle("reset_confirm",nominal)
		var style:=int(kind.trim_prefix("serve_style_"))
		check(game.game_serve.select_serve_style(style),"normal serve style selector accepted",{"style":style})
		event("scope_style_selected",{"style":style})
		return
	await super.lifecycle(kind,nominal)

func driver(now:int)->void:
	if game.game_state==0 and game.serving_team==0:
		if now<next_control:return
		next_control=now+50000
		if game.mobile_controls._blocked():return
		if driver_hit and game.mobile_controls._charge_id!=41:set_hit(false);return
		var held_seconds:=float(now-last_hit_change)/1000000.0
		if not driver_hit and held_seconds>0.2:set_hit(true)
		elif driver_hit and held_seconds>0.65:set_hit(false)
		set_movement(Vector2.ZERO)
		return
	super.driver(now)

func observe(delta:float)->void:
	super.observe(delta)
	if not monitor or changing_scene or not is_instance_valid(game):return
	var timing:Dictionary=game.game_serve.get_serve_timing_state()
	var wall:bool=game.practice_launcher.is_wall()
	var cursor:bool=game.game_trajectory.landing_cursor.visible
	var key:String="wall" if wall else "style_%d"%int(timing.style)
	var phase:String=str(timing.phase)
	var row:Dictionary={"elapsed":elapsed(),"process_frame":Engine.get_process_frames(),"key":key,"phase":phase,"cursor":cursor,"mode":game.aim_controller.mode,"held":Input.is_action_pressed("ui_accept"),"locked":game.aim_controller.is_locked(),"state":game.game_state,"last_hit":game.ball.last_hit_by,"in_play":game.ball.is_in_play,"bounce":game.ball.bounces_since_last_hit,"wall_return_ready":game.ball.wall_return_ready,"wall_rebounds":game.practice_launcher.wall_practice.rebounds if wall else 0,"wall_returns":game.practice_launcher.wall_practice.returns if wall else 0}
	scope_rows.append(row)
	for name in [key+"_"+phase,key+("_visible" if cursor else "_hidden")]:scope_counts[name]=int(scope_counts.get(name,0))+1
	if wall and game.ball.wall_return_ready and game.ball.last_hit_by==-1 and cursor:scope_counts["wall_receiving_visible"]=int(scope_counts.get("wall_receiving_visible",0))+1
	if wall and game.ball.wall_return_ready and game.practice_launcher.wall_practice.rebounds>0 and cursor:scope_counts["wall_rebound_visible"]=int(scope_counts.get("wall_rebound_visible",0))+1
	if strict_reticle and (row.locked or row.last_hit==0 and row.state==2):check(not cursor,"cursor survives locked or outgoing context",row)

func run()->void:
	await super.run()
	FileAccess.open(output.path_join("reticle_scope.json"),FileAccess.WRITE).store_string(JSON.stringify({"counts":scope_counts,"rows":scope_rows},"\t"))
