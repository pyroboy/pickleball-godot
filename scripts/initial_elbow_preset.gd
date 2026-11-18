extends RefCounted
## Isolated initial-preset engine. Never edits authored poses or global physics.
## Rotations are preview overlays about the immutable displayed paddle HEAD center.
const Route=preload("res://scripts/auto_elbow_route.gd")
const Fixture=preload("res://scripts/auto_elbow_fixture.gd")
const Quality=preload("res://scripts/auto_elbow_quality.gd")
const Offset=preload("res://scripts/auto_elbow_offset.gd")
const Size=preload("res://scripts/paddle_dimensions.gd")
const Clearance=preload("res://scripts/body_clearance.gd")
const Paddle=preload("res://scripts/paddle_clearance.gd")
const ArmVisual=preload("res://scripts/player_arm_visual.gd")
const VERSION="initial-preset-head-locked-v1"

class Cancellation extends RefCounted:
	var mutex:=Mutex.new()
	var stopped:=false
	func cancel() -> void:
		mutex.lock();stopped=true;mutex.unlock()
	func is_cancelled() -> bool:
		mutex.lock();var value:=stopped;mutex.unlock();return value


static func attached(frame: Dictionary) -> bool:
	return bool(frame.dominant) or str(frame.production_hand_mode)=="GRIP" or (str(frame.production_hand_mode)=="REGRIP" and float(frame.production_support_grip_weight)>=0.999999)

static func adapt_pair(pair: Array, rotation: Vector3) -> Array:
	if rotation==Vector3.ZERO:return pair
	var result: Array=pair.duplicate(true)
	var delta:=Basis.from_euler(rotation)
	var head: Vector3=pair[0].paddle_transform*Size.HEAD_OFFSET
	var paddle: Transform3D=pair[0].paddle_transform
	paddle.basis=delta*paddle.basis;paddle.origin=head-paddle.basis*Size.HEAD_OFFSET
	var margins:=Clearance.sample_paddle(paddle,Paddle.sample_head_surface(),pair[0].body_geometry)
	var margin:=INF
	for value in margins.values():margin=minf(margin,float(value))
	for side in range(2):
		var f: Dictionary=result[side]
		f.paddle_transform=paddle;f.paddle_inverse=paddle.affine_inverse();f.fixed_paddle_torso_sample_margin_m=margin
		if attached(f):
			var mount: Transform3D=f.hand_mount
			mount.basis=delta*mount.basis;mount.origin=head+delta*(mount.origin-head)
			f.hand_mount=mount;f.wrist=mount*f.wrist_socket;f.hand_basis=mount.basis*f.anatomical_basis
			f.target_position=head+delta*(f.target_position-head)
			f.thumb_up=delta*f.thumb_up
	for side in range(2):
		for obstacle in result[side].obstacles:
			if obstacle.label=="other_fore":obstacle.b=result[1-side].wrist
	return result

static func lookup(time: float, source: Dictionary, side: int) -> Dictionary:
	var pair: Array=source.get("%.9f"%time,[])
	return {} if pair.is_empty() else pair[side]

static func options(source: Dictionary,side: int,duration: float) -> Dictionary:
	return {"frame_at":lookup.bind(source,side),"require_obstacles":true,"extra_evaluator":Fixture.paddle_constraint,"velocity_weight":10.0,"angular_velocity_weight":5.0,"baseline_weight":0.1,"stop_on_empty_candidates":true,"max_validation_step_s":duration/120.0*1.001}

static func inherited_diagnostics(fine: Array, side: int) -> Dictionary:
	var invalid:=0;var max_gap:=0.0
	for pair in fine:
		var f: Dictionary=pair[side]
		var distance: float=f.shoulder.distance_to(f.wrist)
		var gap: float=maxf(distance-f.upper_length-f.fore_length,absf(f.upper_length-f.fore_length)-distance)
		max_gap=maxf(max_gap,gap)
		if gap>0.000001:invalid+=1
	return {"side":side,"status":"Inherited arm retained; not certified by this preset","unreachable_samples":invalid,"max_reach_gap_m":max_gap}

static func inherited_paddle_gate(base: Array,pair: Array,active: Array) -> Dictionary:
	# No wrist/reach gate here: an inherited free/ball hand can already be
	# unreachable. But changing the paddle must not introduce an unchecked
	# paddle-vs-that-arm collision. Nonzero rotation requires a conservative
	# clearance certificate, never a comparison of two negative lower bounds.
	if Fixture.basis_angle_deg(base[0].paddle_transform.basis,pair[0].paddle_transform.basis)<0.00001:return {"valid":true}
	for side in range(2):
		if active[side]:continue
		if attached(pair[side]):return {"valid":false,"status":"Attached hand cannot be inherited unchanged during paddle rotation","side":side}
		var f: Dictionary=pair[side]
		var inverse: Transform3D=f.paddle_inverse
		var shoulder: Vector3=inverse*f.shoulder;var elbow: Vector3=inverse*f.baseline_elbow;var wrist: Vector3=inverse*f.wrist
		var margin:=INF
		for head in [true,false]:
			margin=minf(margin,Fixture._paddle_segment_bound(shoulder,elbow,f.upper_radius,head,6))
			margin=minf(margin,Fixture._paddle_segment_bound(elbow,wrist,f.fore_radius,head,6))
		if margin<0.001:return {"valid":false,"status":"Rotation cannot certify paddle clearance against unchanged support arm","clearance_lower_bound_m":margin,"side":side}
	return {"valid":true}

static func evaluate_candidate(knots: Array,source: Dictionary,fine: Array,duration: float,rotation: Vector3,cancellation: RefCounted=null) -> Dictionary:
	var changed_source: Dictionary={}
	for frame in knots[0]:
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled","inherited_issues":[]}
		var key: String="%.9f"%frame.time
		var pair:=adapt_pair(source[key],rotation)
		if float(pair[0].fixed_paddle_torso_sample_margin_m)<-0.000001:
			return {"valid":false,"status":"Paddle intersects torso at a sampled phase; elbows alone cannot repair it","rotation":rotation,"inherited_issues":[inherited_diagnostics(fine,1 if fine[0][0].dominant else 0)]}
		changed_source[key]=pair
	for key in source:
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled","inherited_issues":[]}
		if not changed_source.has(key):changed_source[key]=adapt_pair(source[key],rotation)
	var planned: Array=[{},{}];var active: Array=[false,false];var quality: Array=[{},{}];var inherited: Array=[]
	var dominant: int=0 if bool(fine[0][0].dominant) else 1
	for side in [dominant,1-dominant]:
		var frames: Array=[]
		for frame in knots[side]:frames.append(changed_source["%.9f"%frame.time][side])
		var opts:=options(changed_source,side,duration);opts.cancellation=cancellation
		var baked:=Route.bake(frames,opts)
		if bool(baked.complete):
			var old_path: Array=[];var new_path: Array=[];var baseline_valid:=true;var safe:=true
			for pair in fine:
				var frame: Dictionary=changed_source["%.9f"%pair[side].time][side]
				var sample:=Route.sample(baked,frame.time,frame)
				safe=safe and bool(sample.get("feasible",false))
				old_path.append(pair[side].baseline_elbow);new_path.append(sample.get("elbow",pair[side].baseline_elbow))
				baseline_valid=baseline_valid and bool(Route.evaluate(frame,frame.baseline_elbow,baked.options).valid)
			var old_metrics:=Quality.metrics([old_path]);var new_metrics:=Quality.metrics([new_path])
			quality[side]=Quality.decide(old_metrics,new_metrics,baseline_valid,safe)
			var non_regressing: bool=new_metrics.max_step_m<=old_metrics.max_step_m*1.01+0.000005 and new_metrics.max_second_difference_m<=old_metrics.max_second_difference_m*1.01+0.000005
			# An attached arm must be re-solved when its wrist rotates, even if original
			# smoothness was already good. Never admit a quality-regressing alternative.
			var must_resolve:=false
			if rotation!=Vector3.ZERO:
				for pair in fine:must_resolve=must_resolve or attached(pair[side])
			var acceptable: bool=bool(quality[side].get("apply",false)) or (must_resolve and safe and non_regressing and str(quality[side].status)=="retain_valid_baseline")
			if side==dominant and rotation==Vector3.ZERO and baseline_valid and str(quality[side].status)=="retain_valid_baseline":
				return {"valid":false,"status":"Original already passes the current model; no better smoothing found. Original retained.","original_retained":true,"inherited_issues":[]}
			if acceptable:planned[side]=baked;active[side]=true
		if not active[side]:
			if side==dominant:return {"valid":false,"status":"No complete paddle-arm route passed the sampled model and smoothness gates","route_status":baked.get("status",""),"route_failures":baked.get("infeasible_intervals",[]),"quality_detail":quality[side],"rotation":rotation,"inherited_issues":[inherited_diagnostics(fine,1-dominant)]}
			if rotation!=Vector3.ZERO:
				for pair in fine:
					if attached(pair[side]):return {"valid":false,"status":"Rotated attached support arm has no complete valid route","rotation":rotation,"inherited_issues":[inherited_diagnostics(fine,1-dominant)]}
			inherited.append(inherited_diagnostics(fine,side))
	var pair_bad:=0
	for original_pair in fine:
		var pair: Array=changed_source["%.9f"%original_pair[0].time]
		var inherited_gate:=inherited_paddle_gate(original_pair,pair,active)
		if not inherited_gate.valid:return {"valid":false,"status":inherited_gate.status,"rotation":rotation,"inherited_issues":inherited}
		var solutions: Array=[]
		for side in range(2):solutions.append(Route.sample(planned[side],pair[side].time,pair[side]) if active[side] else {"valid":true,"elbow":pair[side].baseline_elbow})
		if not bool(Fixture.validate_pair(pair,solutions).valid):pair_bad+=1
	if pair_bad>0:return {"valid":false,"status":"Candidate collides with the final other-arm geometry","rotation":rotation,"inherited_issues":inherited}
	return {"valid":true,"status":"Initial paddle-arm smoothing preview" if not active[1-dominant] else "Initial two-arm smoothing preview","bakes":planned,"active_sides":active,"rotation":rotation,"angle_deg":rad_to_deg(Basis.from_euler(rotation).get_rotation_quaternion().get_angle()),"quality":{"apply":true,"arms":quality},"inherited_issues":inherited,"continuous_time_certified":false,"offsets":[Vector3.ZERO,Vector3.ZERO],"version":VERSION}

static func search(knots: Array,source: Dictionary,fine: Array,duration: float,allow_rotation: bool=true,cancellation: RefCounted=null) -> Dictionary:
	if fine.is_empty() or source.is_empty():return {"valid":false,"status":"No captured source frames","inherited_issues":[]}
	var mixed_regrip:=false
	for pair in fine:
		for f in pair:
			if not f.dominant and str(f.production_hand_mode)=="REGRIP" and float(f.production_support_grip_weight)>0.000001 and float(f.production_support_grip_weight)<0.999999:mixed_regrip=true
	var last: Dictionary={}
	var attempts:=0
	for degrees in ([0.0,5.0,10.0,15.0] if allow_rotation and not mixed_regrip else [0.0]):
		var candidates: Array=[Vector3.ZERO] if degrees==0.0 else [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
		for axis in candidates:
			if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled; last accepted preview retained","inherited_issues":[],"attempts":attempts}
			var rotation: Vector3=axis*deg_to_rad(degrees)
			last=evaluate_candidate(knots,source,fine,duration,rotation,cancellation);attempts+=1
			if bool(last.get("original_retained",false)):
				last.attempts=attempts;return last
			if bool(last.valid):
				last.attempts=attempts;last.angle_search_limited_by_regrip=mixed_regrip
				return last
	last["attempts"]=attempts;last["angle_search_limited_by_regrip"]=mixed_regrip
	last["status"]="Unchanged / manual refinement needed. "+str(last.get("status","No accepted route"))
	return last

static func offset(knots: Array,source: Dictionary,fine: Array,duration: float,zero_result: Dictionary,wanted: Array,cancellation: RefCounted=null) -> Dictionary:
	if not bool(zero_result.get("valid",false)) or wanted.size()!=2:return {"valid":false,"status":"No generated route to offset"}
	for side in range(2):
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
		var value: Vector3=wanted[side]
		if not value.is_finite() or maxf(absf(value.x),maxf(absf(value.y),absf(value.z)))>0.20:return {"valid":false,"status":"Offsets must be finite and within20 cm per axis"}
		if not zero_result.active_sides[side] and value!=Vector3.ZERO:return {"valid":false,"status":"This arm is inherited unchanged; manual guide offset unavailable"}
	if wanted[0]==Vector3.ZERO and wanted[1]==Vector3.ZERO:
		var reset: Dictionary=zero_result.duplicate(true);reset.offsets=wanted.duplicate();return reset
	var adapted: Dictionary={}
	for key in source:
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
		var pair:=adapt_pair(source[key],zero_result.rotation).duplicate(true)
		for side in range(2):
			if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
			if zero_result.active_sides[side]:
				var reference:=Route.sample(zero_result.bakes[side],pair[side].time,pair[side])
				pair[side].guide_elbow=reference.elbow+pair[side].body_transform.basis.orthonormalized()*wanted[side]
		adapted[key]=pair
	var result: Dictionary=zero_result.duplicate(true)
	for side in range(2):
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
		if not zero_result.active_sides[side] or wanted[side]==Vector3.ZERO:continue
		var frames: Array=[]
		for frame in knots[side]:frames.append(adapted["%.9f"%frame.time][side])
		var opts:=options(adapted,side,duration);opts.guide_weight=100.0;opts.cancellation=cancellation
		result.bakes[side]=Route.bake(frames,opts)
		if not bool(result.bakes[side].complete):return {"valid":false,"status":"Guide edit has no complete validated route; previous preview retained"}
	var old_paths: Array=[[],[]];var new_paths: Array=[[],[]]
	for original_pair in fine:
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
		var pair: Array=adapted["%.9f"%original_pair[0].time];var solutions: Array=[]
		for side in range(2):
			if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
			var solution: Dictionary=Route.sample(result.bakes[side],pair[side].time,pair[side]) if result.active_sides[side] else {"valid":true,"elbow":pair[side].baseline_elbow}
			if not bool(solution.get("valid",false)):return {"valid":false,"status":"Guide edit failed dense sampled validation"}
			solutions.append(solution)
			if result.active_sides[side]:old_paths[side].append(original_pair[side].baseline_elbow);new_paths[side].append(solution.elbow)
		if not bool(Fixture.validate_pair(pair,solutions).valid):return {"valid":false,"status":"Guide edit failed final pair collision check"}
	for side in range(2):
		if cancellation!=null and cancellation.is_cancelled():return {"valid":false,"status":"Cancelled"}
		if not result.active_sides[side]:continue
		var quality:=Quality.decide(Quality.metrics([old_paths[side]]),Quality.metrics([new_paths[side]]),false,true)
		if not quality.apply:return {"valid":false,"status":"Guide edit failed per-arm smoothness gate"}
	result.offsets=wanted.duplicate();result.status="Manual whole-guide refinement preview";return result

static func apply(player,basepair: Array,result: Dictionary,time: float) -> Dictionary:
	if not bool(result.get("valid",false)):return {"applied":false,"status":"No accepted preview"}
	var pair:=adapt_pair(basepair,result.rotation)
	var inherited_gate:=inherited_paddle_gate(basepair,pair,result.active_sides)
	if not inherited_gate.valid:return {"applied":false,"status":inherited_gate.status}
	var solutions: Array=[]
	for side in range(2):
		var solution: Dictionary=Route.sample(result.bakes[side],time,pair[side]) if result.active_sides[side] else {"valid":true,"elbow":pair[side].baseline_elbow}
		if not bool(solution.get("valid",false)):return {"applied":false,"status":"Current sample failed; authored original retained"}
		solutions.append(solution)
	if not bool(Fixture.validate_pair(pair,solutions).valid):return {"applied":false,"status":"Current paired geometry failed"}
	var body: Transform3D=player.body_pivot.global_transform
	var original_paddle: Transform3D=player.paddle_node.global_transform
	var head: Vector3=original_paddle*Size.HEAD_OFFSET
	var preserved: Array=[]
	for arm in [player.right_arm_node,player.left_arm_node]:
		var state: Array=[]
		for node in [arm.upper_pivot,arm.forearm_pivot,arm.hand_pivot,arm.upper_mesh,arm.fore_mesh,arm.hand_mesh]:state.append({"node":node,"transform":node.transform})
		preserved.append({"nodes":state,"arm":arm,"anatomical_wrist_world":arm.anatomical_wrist_world,"visual_stretch":arm.visual_stretch,"visual_wrist_lag_deg":arm.visual_wrist_lag_deg})
	player.paddle_node.global_transform=pair[0].paddle_transform
	var okay:=true;var metrics: Dictionary={"max_link_error_m":0.0,"max_wrist_error_m":0.0,"max_shoulder_error_m":0.0,"max_wrist_ratio":0.0}
	for side in range(2):
		if not result.active_sides[side]:continue
		var applied:=Offset.apply_solution(player,pair[side],solutions[side],side)
		okay=okay and bool(applied.get("applied",false)) and bool(applied.get("actual_wrist_budget_ok",false))
		metrics.max_link_error_m=maxf(metrics.max_link_error_m,maxf(float(applied.get("upper_length_error_m",INF)),float(applied.get("fore_length_error_m",INF))))
		metrics.max_wrist_error_m=maxf(metrics.max_wrist_error_m,float(applied.get("wrist_error_m",INF)))
		metrics.max_wrist_ratio=maxf(metrics.max_wrist_ratio,float(applied.get("actual_wrist_coupled_ratio",INF)))
	for side in range(2):
		var arm=player.right_arm_node if side==0 else player.left_arm_node
		metrics.max_shoulder_error_m=maxf(metrics.max_shoulder_error_m,arm.upper_pivot.global_position.distance_to(basepair[side].shoulder))
	metrics.head_error_m=(player.paddle_node.global_transform*Size.HEAD_OFFSET).distance_to(head)
	metrics.body_error_m=player.body_pivot.global_position.distance_to(body.origin)
	metrics.body_rotation_error_deg=Fixture.basis_angle_deg(player.body_pivot.global_basis,body.basis)
	okay=okay and metrics.max_link_error_m<=0.00002 and metrics.max_wrist_error_m<=0.00002 and metrics.max_shoulder_error_m<=0.00002 and metrics.head_error_m<=0.000002 and metrics.body_error_m<=0.000002 and metrics.body_rotation_error_deg<=0.001
	if not okay:
		player.paddle_node.global_transform=original_paddle
		for state in preserved:
			for item in state.nodes:item.node.transform=item.transform
			state.arm.anatomical_wrist_world=state.anatomical_wrist_world;state.arm.visual_stretch=state.visual_stretch;state.arm.visual_wrist_lag_deg=state.visual_wrist_lag_deg
			ArmVisual.update_arm(state.arm)
		for arm in [player.right_arm_node,player.left_arm_node]:arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
	return {"applied":okay,"status":"Preview applied" if okay else "Actual transform gate failed; authored original restored","metrics":metrics}
