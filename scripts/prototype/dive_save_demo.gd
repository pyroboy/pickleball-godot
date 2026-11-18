extends Node3D
## Manually launched practice prototype. Main game never instantiates this scene.
const Dive = preload("res://scripts/prototype/dive_save_controller.gd")
const Motion = preload("res://scripts/prototype/long_reach_pose.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const BallScript = preload("res://scripts/ball.gd")
const Paddle = preload("res://scripts/paddle_dimensions.gd")
const Contact = preload("res://scripts/finite_paddle_contact.gd")
const Surface = preload("res://scripts/paddle_clearance.gd")
const Floor = preload("res://scripts/paddle_floor_geometry.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Hands = preload("res://scripts/player_hand_presentation.gd")
const Shot = preload("res://scripts/shot_physics.gd")
const STEP := 1.0/120.0
var hands = Hands.new()
var shot = Shot.new()
var omega := Vector3.ZERO
var accumulator := 0.0
var case_name := "right_high"
var hitch_mode := false
var render_frames := 0
var contact_events: Array[Dictionary] = []
var flight_events: Array[Dictionary] = []
var substeps: Array[Dictionary] = []
var last_hit_by := 1
var bounce_count := 1
var committed_paddle := Transform3D.IDENTITY
var admission := "not attempted"
var reach_clamps := 0
var current_wrist_distance := 0.0
var requested_wrist_distance := 0.0
var current_motion_time := 0.0
var activation_time := -1.0
var dive = Dive.new()
var game
var actor
var ball
var camera: Camera3D
var title: Label
var status: Label
var button: Button
var origin := Vector3(0,1,4)
var base_body := Transform3D.IDENTITY
var base_paddle := Transform3D.IDENTITY
var base_rig:Dictionary={}
var paddle_in_chest:=Transform3D.IDENTITY
var ready_grip_rotation := 0.0
var ready_main_wrist := Vector3.ZERO
var ready_main_channels:Dictionary={}
var ready_grip_anchor := Vector3.ZERO
var velocity := Vector3.ZERO
var ball_position := Vector3.ZERO
var live := false
var visual_time := -1.0
var demo_time := 0.0
var auto_mode := false
var auto_attempted := false
var saved := false
var misses := 0
var frames: Array[Dictionary] = []
var output := ""
var ready_done := false
var initial_ankles: Array[Vector3] = []
var initial_yaws: Array[float] = []
var view := "oblique"
var simulation_hz := 30
var hip_local: Array[Vector3] = []
var support_preflight_checks := 0
var latest_motion: Dictionary = {}

func _ready() -> void:
	Engine.physics_ticks_per_second=120
	get_tree().root.size=Vector2i(540,960)
	get_tree().root.content_scale_size=Vector2i(540,960)
	DisplayServer.window_set_size(Vector2i(540,960))
	for a in OS.get_cmdline_user_args():
		if a == "--demo-auto": auto_mode=true
		if a == "--demo-hitch":hitch_mode=true
		if a.begins_with("--demo-case="):case_name=a.trim_prefix("--demo-case=")
		if a.begins_with("--demo-view="):view=a.trim_prefix("--demo-view=")
		if a.begins_with("--demo-hz="):simulation_hz=clampi(int(a.trim_prefix("--demo-hz=")),30,120)
		if a.begins_with("--demo-output="): output=a.trim_prefix("--demo-output=")
	var pause = get_node_or_null("/root/PauseController")
	if pause:
		var viewport=get_tree().root
		if viewport.focus_exited.is_connected(pause._on_window_focus_exited):viewport.focus_exited.disconnect(pause._on_window_focus_exited)
		if viewport.focus_entered.is_connected(pause._on_window_focus_entered):viewport.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	game=load("res://scenes/game.tscn").instantiate();add_child(game)
	for i in 6: await get_tree().process_frame
	game.game_serve.cleanup();game.between_point_controller.cancel()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	for tween in get_tree().get_processed_tweens():tween.kill()
	for child in game.find_children("*","Node",true,false):
		child.set_process(false);child.set_physics_process(false)
		if child is CanvasLayer:child.visible=false
	actor=game.player_left;ball=game.ball;game.player_right.hide()
	ball.freeze=true;ball.is_in_play=false
	actor.global_position=origin
	actor.posture.force_posture_update(PostureLibrary.instance().get_def(actor.PaddlePosture.READY))
	base_body=actor.body_pivot.transform;base_paddle=actor.paddle_node.transform
	hands.initialize(actor);shot.setup(ball,actor,game.player_right)
	var ready_pose=PostureLibrary.instance().get_def(actor.PaddlePosture.READY)
	ready_grip_rotation=float(ready_pose.main_grip_rotation_deg-ready_pose.paddle_in_hand_rotation_deg)
	base_rig=Motion.capture_base(actor)
	var main_arm=actor.right_arm_node
	ready_main_wrist=actor.body_pivot.get_node("TorsoMesh").to_local(main_arm.anatomical_wrist_world)
	ready_main_channels=Anatomy.decompose(Anatomy.forearm_reference_for_arm(main_arm,main_arm.anatomical_wrist_world,false),main_arm.hand_mesh.global_basis*main_arm.articulated_hand.anatomical_basis)
	ready_grip_anchor=actor.paddle_node.to_local(main_arm.hand_mesh.global_position)
	paddle_in_chest=actor.body_pivot.get_node("TorsoMesh").global_transform.affine_inverse()*actor.paddle_node.global_transform
	for leg in [actor.right_leg_node,actor.left_leg_node]:
		initial_ankles.append(leg.foot_pivot.global_position)
		initial_yaws.append(leg.foot_pivot.global_rotation.y)
		hip_local.append(actor.body_pivot.to_local(leg.thigh_pivot.global_position))
	for child in actor.find_children("*","Node",true,false):
		if child is Area3D:child.monitoring=false;child.monitorable=false
	camera=Camera3D.new();add_child(camera);camera.position=Vector3(4.1,3.0,8.5)
	if view=="side":camera.position=Vector3(4.0,1.9,4.8)
	elif view=="front":camera.position=Vector3(.20,2.2,0.2)
	if view=="court":camera.position=Vector3(7.4,7.0,9.2)
	camera.look_at(Vector3(0,.55,0.1) if view=="court" else Vector3(.30,.65,4.05));camera.fov=48 if view=="court" else 42;camera.make_current()
	var layer=CanvasLayer.new();layer.layer=110;add_child(layer)
	var panel=VBoxContainer.new();panel.position=Vector2(24,30);panel.size=Vector2(492,180);layer.add_child(panel)
	title=Label.new();title.text="LONG REACH · PRACTICE";title.add_theme_font_size_override("font_size",22);panel.add_child(title)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size=Vector2(480,92);status.add_theme_font_size_override("font_size",21);panel.add_child(status)
	var row=HBoxContainer.new();row.position=Vector2(24,836);layer.add_child(row)
	button=Button.new();button.text="LUNGE  [Space]";button.custom_minimum_size=Vector2(240,72);button.add_theme_font_size_override("font_size",23);button.focus_mode=Control.FOCUS_NONE;button.pressed.connect(request_dive);row.add_child(button)
	var reset=Button.new();reset.text="Toss again  [R]";reset.custom_minimum_size=Vector2(240,72);reset.add_theme_font_size_override("font_size",21);reset.focus_mode=Control.FOCUS_NONE;reset.pressed.connect(toss);row.add_child(reset)
	dive.enabled=true;ready_done=true;toss()

func state() -> Dictionary:
	return {"playing":true,"paused":false,"in_play":live,"last_hit_by":last_hit_by,"player_num":0,"bounces":bounce_count,"jumping":false,"flight_id":ball.flight_id}

func toss() -> void:
	if not ready_done:return
	dive.reset();actor.global_position=origin;actor.body_pivot.transform=base_body;actor.paddle_node.transform=base_paddle
	actor.posture.force_posture_update(PostureLibrary.instance().get_def(actor.PaddlePosture.READY))
	Motion.apply_body(actor,base_rig,Motion.sample(0.0))
	ball_position=Vector3(1.02,.65,3.098038);velocity=Vector3(0,2.010466,2.0)
	if case_name=="left":ball_position=Vector3(-1.02,.65,2.884048);velocity.y=2.478005
	if case_name=="low":ball_position=Vector3(1.02,.65,2.682634);velocity.y=1.561841
	# Longer contact points retain real aero flight, not animated ball paths.
	if case_name=="right":ball_position=Vector3(1.35,.65,3.70-.96487242);velocity.y=2.79156625
	if case_name=="left":ball_position=Vector3(-1.28,.65,3.55-.96487242);velocity.y=2.79156625
	if case_name in ["right_low","low"]:ball_position=Vector3(1.20,.65,3.60-.96733761);velocity.y=1.68660301
	if case_name=="left_low":ball_position=Vector3(-1.14,.65,3.50-.96733761);velocity.y=1.68660301
	if case_name in ["right_high","left_high","right_upper","left_upper","high_miss","high_too_late","high_outgoing","high_double_bounce","high_out_of_reach"]:
		var upper:bool=case_name in ["right_upper","left_upper"]
		var side:float=-1.0 if case_name in ["left_high","left_upper"] else 1.0
		ball_position=Vector3(side*.95,.65,3.50-(.950413 if upper else .956704))
		velocity.y=5.13214421 if upper else 4.27093530
		if case_name=="high_out_of_reach":ball_position.z=3.50-.937072;velocity.y=6.78464770
	if case_name=="out_of_reach":ball_position.x=1.85
	last_hit_by=0 if case_name in ["outgoing","high_outgoing"] else 1
	bounce_count=2 if case_name in ["double_bounce","high_double_bounce"] else 1
	omega=Vector3.ZERO;ball.global_position=ball_position
	ball.flight_id+=1;live=true;visual_time=-1;demo_time=0;saved=false;auto_attempted=false
	accumulator=0;render_frames=0;contact_events.clear();flight_events.clear();substeps.clear();frames.clear()
	admission="not attempted";reach_clamps=0;activation_time=-1
	var is_high:bool=case_name.contains("high") or case_name.contains("upper")
	title.text="HIGH REACH · PRACTICE" if is_high else "LONG REACH · PRACTICE"
	button.text="REACH  [Space]" if is_high else "LUNGE  [Space]"
	status.text="One-bounce practice toss. Tap REACH." if is_high else "One-bounce practice toss. Tap LUNGE.\nFinite paddle contact · recovery + cooldown"

func request_dive() -> void:
	if not ready_done or dive.active or dive.cooldown>0:return
	var prediction: Dictionary=Flight.trace(ball_position,velocity,omega,.60)
	var candidate: Dictionary={}
	for sample:Dictionary in prediction.samples:
		# Leave room for first surface contact before the center intercept.
		if float(sample.time)<.405:continue
		var proposed:Dictionary=Dive.choose_plan(actor.global_position,state(),[sample],Rect2(-3.0,2.0,6.0,5.0))
		if proposed.is_empty():continue
		proposed["incoming_velocity"]=sample.vel
		proposed["backhand"]=proposed.direction.dot(actor._get_forehand_axis())<0.0
		# Reject an impossible arm/paddle fit before scanning the full leg motion.
		# Both physical gates still have to pass before a plan can begin.
		if not _commit_reachable_face(proposed):continue
		if not _plan_has_leg_support(proposed):continue
		candidate=proposed;break
	if dive.begin(candidate,state()):
		committed_paddle=candidate.paddle
		visual_time=0.0;activation_time=demo_time;admission="admitted physical reach"
	else:
		admission="rejected: legal timing / finite reach / cooldown"
		status.text="No safe grounded reach for this toss.\nToss again to try. Groundstrokes only."

func _commit_reachable_face(candidate:Dictionary)->bool:
	var before_root:Transform3D=actor.global_transform
	var before_body:Transform3D=actor.body_pivot.transform
	var motion:Dictionary=Motion.sample(Motion.CONTACT_TIME,candidate.direction,candidate.travel,bool(candidate.backhand),float(candidate.point.y))
	actor.global_position=origin+motion.root_offset
	Motion.apply_body(actor,base_rig,motion)
	var arm=actor.right_arm_node
	var shoulder:Vector3=arm.upper_pivot.global_position
	var target:=Vector3(-.7 if candidate.point.x>0 else .7,.1125,-4.0)
	# Conservative triangle-inequality bound: both arm links, wrist socket,
	# every point in the paddle-head bounding box, ball radius and tolerance.
	# This only discards physically impossible fits before expensive shot solves.
	var head_extent:=Vector3(Paddle.HEAD_RADIUS,Paddle.LENGTH-Paddle.MAIN_GRIP_Y,Paddle.HEAD_HALF_THICKNESS).length()
	var reach_bound:float=arm.upper_arm_length+arm.forearm_length+arm.articulated_hand.wrist_socket.length()+head_extent+BallScript.BALL_RADIUS+Surface.contact_surface_tolerance()+.001
	var response:Dictionary={}
	if shoulder.distance_to(candidate.point)<=reach_bound:
		response=shot.solve_aimed_launch(candidate.point,target,.25,0,0,"AUTO","GROUNDSTROKE")
	var accepted:=false
	if response.get("feasible",false):
		# Face normal follows the required impulse; roll and grip are admitted only
		# when the actual hand/forearm remains inside the rig's wrist limits.
		var normal:Vector3=(response.velocity-candidate.incoming_velocity).normalized()
		var down:Vector3=(Vector3.DOWN-normal*Vector3.DOWN.dot(normal)).normalized()
		var backhand:bool=bool(candidate.backhand)
		var low:bool=candidate.point.y<.50
		var preferred:=Vector2(90.0,45.0) if low and backhand else (Vector2(-30.0,-90.0) if low else (Vector2(135.0,0.0) if backhand else Vector2(-135.0,0.0)))
		if candidate.point.y>1.05:
			var high_blend:float=smoothstep(1.05,1.45,float(candidate.point.y))
			var upper_blend:float=smoothstep(1.45,1.85,float(candidate.point.y))
			preferred=Vector2(135.0+15.0*high_blend+15.0*upper_blend,45.0*high_blend*(1.0-upper_blend)) if backhand else Vector2(-135.0-45.0*upper_blend,0.0)
		for choice:Vector2 in [preferred]:
			var y:Vector3=down.rotated(normal,deg_to_rad(choice.x))
			var basis:=Basis(y.cross(normal).normalized(),y,normal).orthonormalized()
			if backhand:basis=Basis(-basis.x,basis.y,-basis.z)
			var head:Vector3=candidate.point-normal*(BallScript.BALL_RADIUS+Paddle.HEAD_HALF_THICKNESS)
			var floor_y:float=BallScript.FLOOR_Y+Floor.head_clearance(basis)
			if head.y<floor_y:
				var up_in_face:Vector3=Vector3.UP-normal*normal.y
				head+=up_in_face*((floor_y-head.y)/up_in_face.y)
			if case_name in ["miss","high_miss"]:head+=Vector3(-.24,0,0)
			var tx:=Transform3D(basis,head-basis*Paddle.HEAD_OFFSET)
			var mount:Transform3D=_main_mount(tx,choice.y)
			var wrist:Vector3=Hands.wrist_for(arm,mount)
			if case_name not in ["miss","high_miss"] and not Contact.touches(tx,candidate.point,BallScript.BALL_RADIUS):continue
			var distance:float=wrist.distance_to(shoulder)
			if distance>arm.upper_arm_length+arm.forearm_length-.005:continue
			var pole:Vector3=_main_pole(wrist,mount,motion,1.0)
			arm.solve_ik(tx*Paddle.MAIN_GRIP_OFFSET,pole,tx,wrist)
			var channels:Dictionary=Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm,wrist,false),mount.basis*arm.articulated_hand.anatomical_basis,1.0)
			if not channels.within_animation_budget:continue
			candidate["paddle"]=tx;candidate["return_target"]=target;candidate["contact_normal"]=normal
			candidate["wrist_distance"]=distance;candidate["shaft_roll"]=choice.x
			candidate["grip_rotation"]=choice.y;candidate["wrist_channels"]=channels
			var chest:Transform3D=actor.body_pivot.get_node("TorsoMesh").global_transform
			candidate["paddle_in_chest"]=chest.affine_inverse()*tx
			candidate["pole_in_chest"]=chest.affine_inverse()*pole
			candidate["wrist_in_chest"]=chest.affine_inverse()*wrist
			accepted=true;break
	actor.global_transform=before_root;Motion.apply_body(actor,base_rig,Motion.sample(0.0));actor.body_pivot.transform=before_body
	actor.posture.force_posture_update(PostureLibrary.instance().get_def(actor.PaddlePosture.READY))
	return accepted

func _main_pole(wrist:Vector3,mount:Transform3D,motion:Dictionary,weight:float)->Vector3:
	var arm=actor.right_arm_node
	var guide:Dictionary=motion.duplicate()
	guide["pole_weight"]=weight
	var authored:Vector3=Motion.main_pole(actor,wrist,mount,guide,base_rig)
	var hand_distal:Vector3=mount.basis*arm.articulated_hand.anatomical_basis.x
	var conditioned:Vector3=Anatomy.conditioned_pole(arm.upper_pivot.global_position,wrist,authored,hand_distal,arm.upper_arm_length,arm.forearm_length)
	return authored.lerp(conditioned,weight)

func _path_pole(wrist:Vector3,chest:Transform3D,weight:float)->Vector3:
	var shoulder:Vector3=actor.right_arm_node.upper_pivot.global_position
	var ready:Vector3=(chest*base_rig.main_elbow-shoulder).normalized()
	var contact:Vector3=(chest*dive.plan.pole_in_chest-shoulder).normalized()
	var direction:Vector3=ready.slerp(contact,weight)
	# A small outboard arc keeps the forehand upper arm off the ribcage
	# during the lead step, with exactly unchanged READY/contact endpoints.
	if not bool(dive.plan.backhand) and dive.plan.point.y>=.5:
		var mid_arc_weight:float=1.0-smoothstep(1.05,1.25,float(dive.plan.point.y))
		direction+=chest.basis.x*sin(PI*weight)*.50*mid_arc_weight
	var guide:Vector3=shoulder+direction.normalized()
	return Anatomy.stabilized_pole(shoulder,wrist,guide,chest.basis.x)

func _main_mount(paddle:Transform3D,grip_rotation:float)->Transform3D:
	return hands.main_mount(actor.right_arm_node,paddle*Paddle.MAIN_GRIP_OFFSET,paddle.basis,{"main_grip_rotation_deg":grip_rotation,"paddle_in_hand_rotation_deg":0.0})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_SPACE:request_dive()
		if event.keycode==KEY_R:toss()

func _process(delta: float) -> void:
	if not ready_done:return
	var dt:=1.0/float(simulation_hz) if auto_mode else maxf(delta,0.0)
	if hitch_mode and render_frames in [8,18]:dt=.1 if render_frames==8 else .2
	render_frames+=1;accumulator+=dt
	# Carry every elapsed tick through hitches, with a bounded per-render work
	# budget. Excess remains queued; no long variable physics step or lost time.
	var count:=0
	while accumulator+1e-9>=STEP and count<120:
		_tick(STEP);accumulator-=STEP;count+=1
	button.disabled=not live or dive.active or dive.cooldown>0
	frames.append(_observation())
	if auto_mode and demo_time+1e-6>=3.5:
		if output!="":
			DirAccess.make_dir_recursive_absolute(output)
			var f=FileAccess.open(output.path_join("demo-trace.json"),FileAccess.WRITE)
			f.store_string(JSON.stringify({"frames":frames,"substeps":substeps,"contacts":contact_events,"flight_events":flight_events,"saved":saved,"misses":misses,"admission":admission,"activation_time":activation_time,"plan":dive.plan,"scope":"isolated grounded practice, actual finite contact and existing aimed return; match authority pending","simulation_hz":simulation_hz,"physics_hz":120,"hitches":hitch_mode,"case":case_name,"support_preflight_checks":support_preflight_checks,"reach_clamps":reach_clamps,"view":view},"\t"));f.close()
		get_tree().quit()

func _tick(dt:float)->void:
	if auto_mode and not auto_attempted and demo_time+1e-6>=(.90 if case_name=="high_too_late" else (.48 if case_name=="too_late" else .10)):
		auto_attempted=true;request_dive()
	var previous_ball:=ball_position
	var previous_velocity:=velocity
	var previous_paddle:Transform3D=actor.paddle_node.global_transform
	var next_ball:=ball_position
	var next_velocity:=velocity
	var next_omega:=omega
	if live:
		var step:Array=BallScript.predict_aero_step(ball_position,velocity,omega,BallScript.get_effective_gravity(),dt)
		next_ball=step[0];next_velocity=step[1];next_omega=step[2]
	if visual_time>=0.0:
		visual_time=minf(Motion.DURATION,visual_time+dt)
		var contact_time:float=float(dive.plan.get("time",.43))
		current_motion_time=visual_time*Motion.CONTACT_TIME/contact_time if visual_time<=contact_time else Motion.CONTACT_TIME+(visual_time-contact_time)*(Motion.DURATION-Motion.CONTACT_TIME)/(Motion.DURATION-contact_time)
		var motion:Dictionary=Motion.sample(current_motion_time,dive.plan.get("direction",Vector3.RIGHT),float(dive.plan.get("travel",0.0)),bool(dive.plan.get("backhand",false)),float(dive.plan.point.y))
		latest_motion=motion
		actor.global_position=origin+motion.root_offset
		Motion.apply_body(actor,base_rig,motion)
		_apply_foot_support(motion,dive.plan.get("direction",Vector3.RIGHT))
		var chest:Transform3D=actor.body_pivot.get_node("TorsoMesh").global_transform
		var weight:float=smoothstep(.12,maxf(.32,contact_time-.015),visual_time)*(1.0-smoothstep(contact_time+.12,contact_time+.55,visual_time))
		# Joint-space reach: interpolate fixed chest-local wrist and elbow goals,
		# then hand flex/deviation/forearm rotation inside the existing budgets.
		# Derive the real paddle from the hand, never a visually impossible wrist.
		var arm=actor.right_arm_node
		var shoulder:Vector3=arm.upper_pivot.global_position
		var wrist:Vector3=chest*(ready_main_wrist.lerp(dive.plan.wrist_in_chest,weight))
		wrist+=dive.plan.contact_normal*.12*smoothstep(contact_time,contact_time+.12,visual_time)*weight
		var limit:float=arm.upper_arm_length+arm.forearm_length-.001
		requested_wrist_distance=shoulder.distance_to(wrist)
		if requested_wrist_distance>limit:
			wrist=shoulder+(wrist-shoulder).limit_length(limit);reach_clamps+=1
		current_wrist_distance=shoulder.distance_to(wrist)
		var pole:Vector3=_path_pole(wrist,chest,weight)
		arm.solve_ik(wrist,pole,Transform3D.IDENTITY,wrist)
		var reference:Basis=Anatomy.forearm_reference_for_arm(arm,wrist,false)
		var finish:Dictionary=dive.plan.wrist_channels
		var flex:float=lerpf(float(ready_main_channels.flexion_deg),float(finish.flexion_deg),weight)
		var dev:float=lerpf(float(ready_main_channels.radial_deviation_deg),float(finish.radial_deviation_deg),weight)
		var axial:float=lerpf(float(ready_main_channels.forearm_axial_deg),float(finish.forearm_axial_deg),weight)
		var anatomical:Basis=reference*Basis(Vector3.RIGHT,deg_to_rad(axial))*Basis(Vector3.UP,deg_to_rad(flex))*Basis(Vector3.BACK,deg_to_rad(dev))
		var mount:=Transform3D(anatomical*arm.articulated_hand.anatomical_basis.inverse(),Vector3.ZERO)
		mount.origin=wrist-mount.basis*arm.articulated_hand.wrist_socket
		var grip_rotation:float=lerpf(ready_grip_rotation,float(dive.plan.grip_rotation),weight)
		var grip:Basis=Hands.GripFrame.basis(Basis.IDENTITY,false,grip_rotation)
		var paddle_basis:Basis=mount.basis*grip.inverse()
		var anchor:Vector3=ready_grip_anchor.lerp(Paddle.MAIN_GRIP_OFFSET,weight)
		actor.paddle_node.global_transform=Transform3D(paddle_basis,mount.origin-paddle_basis*anchor)
		hands.apply_mount(arm,mount)
		Motion.apply_support_arm(actor,base_rig,motion,hands)
		dive.elapsed=visual_time
		if visual_time>=Motion.DURATION:dive.active=false
	var floor_fraction:=INF
	if live and next_ball.y<=.1125 and previous_ball.y>.1125:
		floor_fraction=(previous_ball.y-.1125)/(previous_ball.y-next_ball.y)
	var fraction:float=dive.contact_fraction(previous_ball,next_ball,previous_paddle,actor.paddle_node.global_transform,state(),BallScript.BALL_RADIUS,dt) if live else -1.0
	if fraction>=0.0 and fraction<floor_fraction:
		var at:Vector3=previous_ball.lerp(next_ball,fraction)
		var tx:Transform3D=Contact.interpolate_head_transform(previous_paddle,actor.paddle_node.global_transform,fraction)
		var response:Dictionary=shot.solve_aimed_launch(at,dive.plan.return_target,.25,0,0,"AUTO","GROUNDSTROKE")
		var incoming:Vector3=previous_velocity.lerp(next_velocity,fraction)
		velocity=response.velocity;omega=response.omega;saved=true;last_hit_by=0;bounce_count=0;ball.flight_id+=1
		contact_events.append({"time":demo_time+dt*fraction,"fraction":fraction,"position":at,"ball_from":previous_ball,"ball_to":next_ball,"paddle":tx,"paddle_from":previous_paddle,"paddle_to":actor.paddle_node.global_transform,"visual_time":visual_time-dt+dt*fraction,"remainder_seconds":dt*(1.0-fraction),"head":tx*Paddle.HEAD_OFFSET,"surface_gap":Surface.distance_to_head_shape(tx.affine_inverse()*at)-BallScript.BALL_RADIUS,"incoming":incoming,"outgoing":velocity,"omega":omega,"response_feasible":response.feasible,"response_net_clear":response.net_clear,"response_target_error":response.target_error,"wrist_distance":current_wrist_distance,"arm_budget":actor.right_arm_node.upper_arm_length+actor.right_arm_node.forearm_length,"feet":_foot_observations()})
		var remainder:Array=BallScript.predict_aero_step(at,velocity,omega,BallScript.get_effective_gravity(),dt*(1.0-fraction))
		ball_position=remainder[0];velocity=remainder[1];omega=remainder[2]
		contact_events[-1]["after_remainder_ball"]=ball_position
		contact_events[-1]["after_remainder_velocity"]=velocity
		contact_events[-1]["after_remainder_omega"]=omega
	else:
		if fraction>=0.0:dive.contacted=false # Earlier floor TOI wins; no contact is awarded.
		ball_position=next_ball;velocity=next_velocity;omega=next_omega
		if floor_fraction!=INF:
			ball_position=previous_ball.lerp(next_ball,floor_fraction);ball_position.y=.1125
			bounce_count+=1;live=false
			flight_events.append({"type":"return_landing" if saved else "second_bounce_miss","time":demo_time+floor_fraction*dt,"position":ball_position,"in_opponent_court":saved and absf(ball_position.x)<3.048 and ball_position.z<0 and ball_position.z>-6.7056})
			if not saved:misses+=1
	if live and saved and previous_ball.z>0 and ball_position.z<=0:
		var cross_fraction:float=previous_ball.z/(previous_ball.z-ball_position.z)
		var crossing:Vector3=previous_ball.lerp(ball_position,cross_fraction)
		var clearance:float=crossing.y-Flight.net_clear_y_at(crossing.x)
		flight_events.append({"type":"net_crossing","time":demo_time+dt*cross_fraction,"position":crossing,"clearance":clearance})
		if clearance<0:live=false;flight_events.append({"type":"net_fault","position":crossing})
	ball.global_position=ball_position
	dive.cooldown=maxf(0,dive.cooldown-dt)
	demo_time+=dt
	if visual_time>=0:
		status.text="%s\n%s"%["PADDLE CONTACT · RETURN" if saved else ("MISSED · RECOVERING" if not live else str(latest_motion.get("phase","")).replace("_"," ").to_upper()),"%s · GROUNDED REACH"%["BACKHAND" if dive.plan.get("backhand",false) else "FOREHAND"]]
	substeps.append(_observation())

func _observation()->Dictionary:
	return {"time":demo_time,"visual_time":visual_time,"motion_time":current_motion_time,"saved":saved,"live":live,"last_hit_by":last_hit_by,"bounces":bounce_count,"flight_id":ball.flight_id,"upper_length":actor.right_arm_node.upper_pivot.global_position.distance_to(actor.right_arm_node.forearm_pivot.global_position),"fore_length":actor.right_arm_node.forearm_pivot.global_position.distance_to(actor.right_arm_node.anatomical_wrist_world),"camera":str(camera.global_transform),"camera_h":camera.h_offset,"camera_v":camera.v_offset,"root":str(actor.global_position),"ball":str(ball_position),"velocity":str(velocity),"paddle":str(actor.paddle_node.global_transform),"head":str(actor.paddle_node.to_global(Paddle.HEAD_OFFSET)),"wrist_distance":current_wrist_distance,"requested_wrist_distance":requested_wrist_distance,"arm_stretch":actor.right_arm_node.visual_stretch,"paddle_lowest":actor.paddle_node.to_global(Paddle.HEAD_OFFSET).y-Floor.head_clearance(actor.paddle_node.global_basis)+Floor.MARGIN,"phase":str(latest_motion.get("phase","ready")),"feet":_foot_observations(),"body_origin":str(actor.body_pivot.global_position),"torso":str(actor.body_pivot.get_node("TorsoMesh").global_transform),"right_shoulder":str(actor.right_arm_node.upper_pivot.global_position),"right_elbow":str(actor.right_arm_node.forearm_pivot.global_position),"right_wrist":str(actor.right_arm_node.anatomical_wrist_world),"left_shoulder":str(actor.left_arm_node.upper_pivot.global_position),"left_elbow":str(actor.left_arm_node.forearm_pivot.global_position),"left_wrist":str(actor.left_arm_node.anatomical_wrist_world),"support_arm_stretch":actor.left_arm_node.visual_stretch,"support":latest_motion}

func _apply_foot_support(motion:Dictionary,direction:Vector3)->void:
	var toward:=Vector3(direction.x,0,direction.z).normalized()
	var lead_right:bool=toward.dot(actor._get_forehand_axis())>=0
	for i in range(2):
		var leg=actor.right_leg_node if i==0 else actor.left_leg_node
		var lead:bool=(i==0)==lead_right
		var advance:float=motion.lead_travel if lead else motion.trail_travel
		var lift:float=motion.lead_lift if lead else motion.trail_lift
		var ankle:Vector3=initial_ankles[i]+toward*advance+Vector3.UP*lift
		# Shoe heading and knee pole agree; yaw stops changing at plant.
		var yaw_weight:float=motion.lead_yaw_weight if lead else motion.trail_yaw_weight
		var yaw:float=initial_yaws[i]+(-.44 if lead_right else .44)*yaw_weight
		var shoe_forward:Vector3=Basis(Vector3.UP,yaw)*Vector3.FORWARD
		var pole:Vector3=ankle+shoe_forward*.65+Vector3.UP*.35
		leg.solve_ik(ankle,pole,0.0)
		leg.foot_pivot.global_basis=Basis(Vector3.UP,yaw)

func _foot_observations()->Array:
	var out:Array=[]
	for leg in [actor.right_leg_node,actor.left_leg_node]:
		var bounds:AABB=leg.foot_mesh.mesh.get_aabb()
		var lowest:=INF
		for i in 8:lowest=minf(lowest,(leg.foot_mesh.global_transform*bounds.get_endpoint(i)).y)
		out.append({"ankle":str(leg.foot_pivot.global_position),"hip":str(leg.thigh_pivot.global_position),"knee":str(leg.shin_pivot.global_position),"sole_min":lowest,"reachable":leg.reach_report.get("feasible",false),"reach":leg.reach_report,"foot_basis":str(leg.foot_pivot.global_basis),"mesh_offset":str(leg.foot_mesh.position)})
	return out

func _plan_has_leg_support(candidate:Dictionary)->bool:
	var direction:Vector3=candidate.direction
	var lead_right:bool=direction.dot(actor._get_forehand_axis())>=0
	# Small explicit candidate admission solve, performed only on user activation.
	# Uses actual authored socket frames, never moves a planted target to hide reach.
	for frame in range(ceili(Motion.DURATION*120.0)+1):
		var m:Dictionary=Motion.sample(float(frame)/120.0,direction,float(candidate.travel),bool(candidate.get("backhand",false)),float(candidate.point.y))
		var body:=base_body
		body.origin+=m.body_offset
		body.basis=Basis.from_euler(base_body.basis.get_euler()+m.body_rotation+Vector3.UP*float(m.get("body_yaw",0.0)))
		var root_transform:Transform3D=actor.global_transform
		root_transform.origin=origin+m.root_offset
		var world:Transform3D=root_transform*body
		for i in range(2):
			var lead:bool=(i==0)==lead_right
			var ankle:Vector3=initial_ankles[i]+direction*float(m.lead_travel if lead else m.trail_travel)+Vector3.UP*float(m.lead_lift if lead else m.trail_lift)
			var distance:float=(world*hip_local[i]).distance_to(ankle)
			support_preflight_checks+=1
			if distance<.18286 or distance>.8274:return false
	return true
