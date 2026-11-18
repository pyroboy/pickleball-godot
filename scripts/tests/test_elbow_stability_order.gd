extends SceneTree
## Geometric pole conditioning must be stateless: scrubbing cannot lag contact.
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size()<40: failures.append(label)
func elbow(wrist: Vector3, pole: Vector3) -> Vector3:
	var axis:=wrist.normalized()
	var radial:=(pole-axis*pole.dot(axis)).normalized()
	return wrist*0.5+radial*sqrt(maxf(0.0,0.35*0.35-wrist.length_squared()*0.25))
func solve(p, pose: PostureDefinition) -> Array[Vector3]:
	p.posture.transition_pose_blend=pose;p.posture.force_posture_update(pose)
	var result: Array[Vector3]=[]
	for arm in [p.right_arm_node,p.left_arm_node]:
		var wrist:Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
		check(wrist.distance_to(arm.anatomical_wrist_world)<2e-05,"visible and solved wrist remain exact")
		check(arm.forearm_pivot.global_position.is_finite(),"elbow remains finite")
		result.append(arm.forearm_pivot.global_position);result.append(wrist)
	return result
func run() -> void:
	var wrist:=Vector3(0.5,0,0)
	var authored:=Vector3.UP
	var a:=Vector3.ZERO
	var b:=Vector3.ZERO
	for edge in [0.698,0.7]:
		var wa:=Vector3(edge-0.000001,0,0);var wb:=Vector3(edge+0.000001,0,0)
		a=Anatomy.conditioned_pole(Vector3.ZERO,wa,authored,Vector3(0,0.8,0.6),0.35,0.35)
		b=Anatomy.conditioned_pole(Vector3.ZERO,wb,authored,Vector3(0,0.8,0.6),0.35,0.35)
		check(elbow(wa,a).distance_to(elbow(wb,b))<0.001,"conditioning stays continuous across reach %.3f"%edge)
	for sign_value in [-1.0,1.0]:
		var ref:Vector3=Vector3.UP*sign_value
		a=Anatomy.stabilized_pole(Vector3.ZERO,wrist,Vector3.RIGHT,ref)
		check(a.is_finite() and a.is_equal_approx(ref),"exactly axial guide has a deterministic finite reference")
		var previous:=Vector3.ZERO
		for degrees in range(-180,181):
			var guide:=Vector3.RIGHT+Vector3.UP.rotated(Vector3.RIGHT,deg_to_rad(degrees))*0.12
			b=Anatomy.stabilized_pole(Vector3.ZERO,wrist,guide,ref)
			if degrees>-180:check(elbow(wrist,b).distance_to(previous)<0.012,"regularization introduces no cancellation or angular branch jump")
			previous=elbow(wrist,b)
	check(Anatomy.stabilized_pole(Vector3.ZERO,wrist,Vector3(0,0,0.35),Vector3.UP)==Vector3(0,0,0.35),"perpendicular editor guides retain full authority")
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	for frame in range(5):await process_frame
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens():tween.kill()
	for node in game.find_children("*","Node",true,false):node.set_process(false);node.set_physics_process(false)
	# Both physical solvers used to switch to world-Up at |dot| > 0.999,
	# even while the supplied guide still had a valid bend-plane projection.
	for actor in [game.player_left,game.player_right]:
		for arm in [actor.right_arm_node,actor.left_arm_node]:
			var shoulder:Vector3=arm.upper_pivot.global_position
			var target:Vector3=shoulder+Vector3.RIGHT*0.5
			var edge:float=sqrt(1.0/(0.999*0.999)-1.0)
			arm.solve_ik(target,shoulder+Vector3(1,0,edge-0.000001),null,target)
			var before:Vector3=arm.forearm_pivot.global_position
			arm.solve_ik(target,shoulder+Vector3(1,0,edge+0.000001),null,target)
			check(before.distance_to(arm.forearm_pivot.global_position)<0.00002,"physical IK no longer switches a valid pole to world-Up")
	var rng:=RandomNumberGenerator.new();rng.seed=617
	for p in [game.player_left,game.player_right]:
		p.hitting.serving_visual_active=false;p.hitting.charge_visual_active=false;p.hitting.is_in_follow_through=false;p.current_velocity=Vector3.ZERO;p.posture.editor_preview_mode=true
		for id in [0,10,11]:
			for grip in [-45.0,0.0,45.0]:
				var base:PostureDefinition=PostureLibrary.instance().get_def(id).duplicate(true)
				base.main_grip_rotation_deg+=grip;base.support_grip_rotation_deg+=grip
				var poses:Array[PostureDefinition]=[];var frames:Array=[]
				var maxima:=[0.0,0.0]
				for step in range(241):
					var pose:PostureDefinition=Motion.sample_drive(base,float(step)/240.0,1.0)
					poses.append(pose);frames.append(solve(p,pose))
					if step>0:
						for side in [0,1]:maxima[side]=maxf(maxima[side],frames[step][side*2].distance_to(frames[step-1][side*2]))
				if is_zero_approx(grip):
					if id==0:check(maxima[0]<0.03,"forehand near-axis elbow spike remains reduced")
					if id==10:check(maxima[0]<0.03,"wide forehand near-axis elbow spike remains reduced")
					if id==11:check(maxima[1]<0.055,"wide backhand support near-axis spike remains reduced")
				for order in [0,1]:
					for index in range(241):
						var step:int=240-index if order==0 else rng.randi_range(0,240)
						var actual:=solve(p,poses[step])
						for part in range(4):check(actual[part].distance_to(frames[step][part])<0.00002,"forward/reverse/random pose order gives same elbow and wrist")
				print("ELBOW SAMPLES court%d drive%d grip%d max_step_m=%s"%[p.player_num,id,int(grip),str(maxima)])
		for style in [0,4]:
			var duration:float=float(Preview.serve_plan(style).contact_time)+Styles.sweep_duration(style)+Motion.SERVE_HOLD_TIME+Motion.SERVE_RECOVERY_TIME
			var poses:Array[PostureDefinition]=[];var frames:Array=[]
			for step in range(121):
				var pose:PostureDefinition=Preview.sample_serve_elapsed(style,duration*step/120.0,1.0)
				poses.append(pose);frames.append(solve(p,pose))
			for step in range(120,-1,-1):
				var actual:=solve(p,poses[step])
				for part in range(4):check(actual[part].distance_to(frames[step][part])<0.00002,"serve reverse sampling preserves elbow and wrist")
	print("ELBOW STABILITY / ORDER: %d checks, %d failures"%[checks,failures.size()])
	for failure in failures:push_error(failure)
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
