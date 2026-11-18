extends SceneTree
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var game
var checks := 0
var failures: Array[String] = []
var label := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(label+": "+message)
func tick() -> void:
	game.input_handler._process(1.0/60.0)
func camera_check(mode: int) -> void:
	game.camera_rig.update(1.0/60.0)
	game.camera_rig._process(1.0/60.0)
	check(game.main_camera.global_transform.is_finite(), "camera finite during physical gameplay")
	if mode == 0 and game.serving_team == 1 and int(game.game_state) in [0,1,2]:
		check(game.camera_rig.gameplay_camera.active_kind == "center", "real Red serve retains centered receiving view")
		check(game.main_camera.global_position.z > 0.0, "real Red serve stays on Blue side")
	if mode == 2:
		var pixel: Vector2 = game.main_camera.unproject_position(game.ball.global_position)
		check(pixel.distance_to(root.get_visible_rect().get_center())<0.05,"POV ball exactly centered during physical gameplay")
func run() -> void:
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): pause.get_tree().root.focus_exited.disconnect(pause._on_window_focus_exited)
	root.content_scale_size=Vector2i(720,1280);root.size=Vector2i(360,640)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await process_frame;await physics_frame
	Fixture.configure(game)
	game.shot_physics.accuracy.rng.seed=1916
	var c=game.mobile_controls
	for mode in 3:
		game.camera_rig.set_gameplay_camera_mode(mode)
		for side in 2:
			label="camera%d serve-side%d" % [mode,side]
			c.cancel_all(); game.serving_team=side;game._reset_ball();game.between_point_controller.cancel()
			for i in 24: await physics_frame
			var before: int=game.shot_physics.accuracy.samples
			game.game_serve.start_charge();game.game_serve.tick_charge(0.5)
			game.game_serve.release(0.5)
			check(game.shot_physics.accuracy.samples==before,"serve release does not sample before contact")
			for frame in 120:
				await physics_frame;camera_check(mode)
				if game.ball.is_in_play: break
			check(game.ball.is_in_play and game.ball.last_hit_by==side,"real serve launched on correct side")
			check(game.shot_physics.accuracy.samples==before+(1 if side==0 else 0),"human serve samples once; AI unchanged")
			check(game.camera_rig.gameplay_camera.mode==mode,"serve retains selected mode")
		game.serving_team=0
		for shot in 4:
			label="camera%d touch-shot%d" % [mode,shot]
			c.cancel_all();Fixture.prepare(game,Fixture.cases()[0])
			game.hud._between_point_active=false;game.hud.set_gameplay_elements_visible(true)
			await physics_frame;await physics_frame
			var origin: Vector2=c._charge_center if shot==0 else c._guide_nodes[shot-1]
			var before: int=game.shot_physics.accuracy.samples
			check(c._press(19,origin),"shot touch accepted")
			c._drag(19,origin+Vector2(18,-12)*c._s);tick()
			check(game.aim_controller.cursor_visible,"held right thumb shows target")
			check(not game.aim_controller.should_plant_player(),"touch aim preserves movement")
			for frame in 14: tick();await physics_frame;camera_check(mode)
			var target: Vector3=game.aim_controller.get_target()
			check(game.shot_physics.accuracy.samples==before,"held target never samples")
			c._release(19,false);tick()
			check(not game.aim_controller.cursor_visible,"release hides target")
			for frame in 220:
				tick();await physics_frame;camera_check(mode)
				if game.ball.last_hit_by==0: break
			check(game.ball.last_hit_by==0,"touch release reaches real human paddle contact")
			check(game.shot_physics.accuracy.samples==before+1,"accepted touch hit samples exactly once")
			if game.ball.last_hit_by==0:
				var profile: Dictionary=game.ball.get_meta("shot_profile",{})
				check(game.ball.get_meta("aim_target",Vector3.INF).is_equal_approx(target),"contact keeps committed intention")
				var axes: Vector2=profile.accuracy_radii
				var offset: Vector3=profile.accuracy_sampled_target-profile.accuracy_intended_target
				check(Vector2(offset.x/axes.x,offset.z/axes.y).length()<=1.000001,"actual sampled target remains bounded")
				var evidence: Dictionary=game.player_left.posture.human_contact.last_contact_evidence
				check(evidence.has("raw_paddle") and evidence.has("raw_ball"),"physical contact evidence retained")
				if evidence.has("raw_paddle"):
					var local: Vector3=evidence.raw_paddle.affine_inverse()*evidence.raw_ball
					check(Geometry.distance_to_head_shape(local)<=Ball.BALL_RADIUS+Geometry.contact_surface_tolerance()+0.0001,"finite paddle truly touches ball")
			c.cancel_all();game._reset_ball()
			check(not game.aim_controller.cursor_visible and game.camera_rig.gameplay_camera.mode==mode,"reset clears marker and preserves view")
	c.cancel_all();current_scene=null;game.queue_free();await process_frame
	for failure in failures: push_error(failure)
	print("COMBINED CAMERA CONTROLS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
