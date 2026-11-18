extends SceneTree
var game
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	root.content_scale_size = Vector2i(720,1560); root.size = Vector2i(720,1560)
	root.get_node("PauseController").set_process_input(false)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	game.set_physics_process(false)
	game.ball.gravity_scale = 0.0
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.global_position = Vector3(0, 1.2, -3.0)
	game.game_state = 2; game.ball.freeze = false; game.ball.is_in_play = true; game.ball.last_hit_by = 1
	game.hud._between_point_active = false; game.hud._gameplay_visible = true
	var c = game.mobile_controls
	for resolution in [Vector2i(360,640),Vector2i(390,844),Vector2i(720,1560),Vector2i(1080,2340),Vector2i(720,800)]:
		root.content_scale_size = resolution; root.size = resolution
		await process_frame; c._layout()
		var screen: Rect2 = root.get_visible_rect()
		for i in 3:
			check(screen.encloses(Rect2(c._guide_nodes[i]-Vector2.ONE*c._shot_button_radius,Vector2.ONE*c._shot_button_radius*2)),"skill contained %s %d" % [resolution,i])
			check(c._guide_nodes[i].distance_to(c._charge_center)>c._shot_button_radius+c._charge_radius*1.22,"skill separate HIT")
			check(c._guide_nodes[i].distance_to(c._stick_center)>c._shot_button_radius+c._stick_radius*1.35,"skill separate MOVE")
			for j in range(i): check(c._guide_nodes[i].distance_to(c._guide_nodes[j])>2*c._shot_button_radius,"skills separate")
		check(screen.encloses(Rect2(c._cancel_center-Vector2.ONE*c._cancel_radius,Vector2.ONE*c._cancel_radius*2)),"cancel contained")
		for i in 3: check(c._cancel_center.distance_to(c._guide_nodes[i])>c._cancel_radius+c._shot_button_radius,"cancel separate skills")
		for region in c.camera_occlusion_regions(): check(not region.has_point(screen.get_center()),"controls preserve centered POV ball")
	check(c._press(10,c._stick_center+Vector2(c._stick_radius,0)),"left press")
	check(c._press(11,c._charge_center),"right press")
	c._drag(11,c._charge_center+Vector2(-c._charge_radius,-c._charge_radius))
	check(c._stick_id==10 and c._charge_id==11,"independent touch ownership")
	check(c.aim_direction().x<0 and c.aim_direction().y<0,"right directional aim")
	check(Input.is_action_pressed("move_right") and Input.is_action_pressed("ui_accept"),"move and shot held together")
	game.aim_controller.update(0.1,false,Vector2.ZERO,true)
	check(not game.aim_controller.cursor_visible,"idle target hidden")
	var before: Vector3 = game.aim_controller.get_target()
	game.aim_controller.update(0.1,true,c.aim_direction(),true)
	check(game.aim_controller.get_target().x<before.x,"right input moves landing target")
	game.game_trajectory._update_player_cursor()
	check(game.game_trajectory.landing_cursor.visible,"held aiming shows landing marker")
	game.aim_controller.planted=true
	check(not game.aim_controller.should_plant_player(),"mobile aim does not seize movement")
	check(game.player_left._get_human_input().x>0,"left still moves while aiming")
	c._drag(11,c._charge_center+Vector2(-5*c._charge_radius,0))
	check(not c._cancel_armed,"long drag remains aim")
	c._drag(11,c._cancel_center); check(c._cancel_armed,"explicit cancel arms")
	check(c.aim_direction()==Vector2.ZERO,"cancel stops aiming")
	c._drag(11,c._charge_center); check(not c._cancel_armed,"leaving cancel resumes")
	c._release(11,true)
	check(not game.game_trajectory.landing_cursor.visible,"cancel immediately hides landing marker")
	check(c._stick_id==10 and Input.is_action_pressed("move_right"),"shot cancel preserves movement finger")
	c._release(10,true)
	for i in 3:
		c._press(20+i,c._guide_nodes[i])
		check(c._charge_id==20+i and Input.is_action_pressed("ui_accept"),"skill starts held shot")
		check(c._selected_shot()==c.GUIDE_LABELS[i],"skill selects expected shot")
		c._drag(20+i,c._guide_nodes[i]+Vector2(c._charge_radius,0))
		check(c.aim_direction().x>0,"skill drag aims from its own origin")
		check(c._selected_shot()==c.GUIDE_LABELS[i],"drag does not mutate selected skill")
		c._release(20+i,true)
	c._press(30,c._charge_center); check(c._selected_shot()=="FLAT","HIT is Flat counterpart")
	c.cancel_all(); check(c._owners.is_empty() and not Input.is_action_pressed("ui_accept"),"cancel clears all actions")
	game.game_state=0; game.serving_team=0
	check(c._shot_button_at(c._guide_nodes[0])==-1,"rally skills not serving buttons")
	game.aim_controller.reset(); game.aim_controller.update(0.2,true,Vector2(1,-1),true)
	var target: Vector3 = game.aim_controller.get_target()
	check(target.z<=-2.6 and target.x<0,"serve aim remains diagonal legal box")
	var committed: Vector3 = game.aim_controller.capture(); game.aim_controller.update(1,true,Vector2(-1,1),true)
	check(game.aim_controller.get_target().is_equal_approx(committed),"committed target stays locked through contact")
	check(not game.aim_controller.cursor_visible,"release hides marker while preserving committed target")
	game.aim_controller.release()
	root.content_scale_size=Vector2i(1280,720);root.size=Vector2i(1280,720);await process_frame;c._layout()
	check(not c.enabled and c._owners.is_empty(),"landscape retains desktop controls and clears touch ownership")
	print("RIGHT THUMB AIM: ",checks," checks, failures: ",failures)
	current_scene=null;game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
