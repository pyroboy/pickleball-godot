extends RefCounted
## Data-only playback. No candidate search, source capture or collision hierarchy.
## A mismatched context retains the production pose without partial writes.
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Visual = preload("res://scripts/player_arm_visual.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
const Codec = preload("res://scripts/elbow_preset_bake.gd")
const POSITION_EPS := 0.00002
const ROTATION_EPS := 0.000174532925 # 0.01 degrees; geometry congruence, not a broad retarget.
const SAMPLE_META := "elbow_preset_sample"
const PRIVATE_PREVIEW_META := "elbow_preset_private_preview"
static var _source_cache: Dictionary = {}
const MAX_SOURCE_CACHE := 64

static func v(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

static func transform(a: Array) -> Transform3D:
	return Transform3D(Basis(v(a.slice(0,3)),v(a.slice(3,6)),v(a.slice(6,9))),v(a.slice(9,12)))

static func root_for(player) -> Transform3D:
	return Transform3D(Basis(player._get_forehand_axis(),Vector3.UP,-player._get_forward_axis()),player.global_position)

## Torso/skin model vertices are built back-facing on the far court, while
## the model root remains unturned. Normalize that built-in reference basis.
static func model_transform(root: Transform3D,world: Transform3D) -> Transform3D:
	var result := root.affine_inverse()*world
	result.basis=result.basis*root.basis
	return result

static func basis_error(a: Basis,b: Basis) -> float:
	var q := (a.orthonormalized().get_rotation_quaternion().inverse()*b.orthonormalized().get_rotation_quaternion()).normalized()
	return 2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w))

static func clear_tag(pose) -> void:
	if pose != null and pose.has_meta(SAMPLE_META): pose.remove_meta(SAMPLE_META)

static func tag(pose,source,progress: float,scope: String) -> void:
	clear_tag(pose)
	if pose == null or source == null or source.elbow_preset_bake.is_empty(): return
	var bake: Dictionary = source.elbow_preset_bake
	if not Codec.admit(bake):return
	if str(bake.get("scope","")) != scope or int(bake.get("handedness",-1)) != source.paddle_hand or int(bake.get("source_id",-1))!=source.posture_id: return
	# Check actual effective authored channels. No cached validity may survive a
	# manual edit, a new global grip or a reused Resource instance.
	if str(bake.get("source_sha256","")) != _source_fingerprint(source,scope): return
	var coordinate := clampf(progress,0.0,1.0)
	if scope=="stroke_runtime":
		var duration: float=maxf(0.01,source.ft_duration_strike)+maxf(0.01,source.ft_duration_sweep)
		if absf(float(bake.duration)-duration)>0.000001:return
		coordinate=clock_coordinate(source,coordinate)
	pose.set_meta(SAMPLE_META,{"bake":bake,"progress":coordinate,"scope":scope})

## Byte equality (not a lossy hash) makes the cache safe for in-place edits.
## No baked payload is copied/serialized here. Full canonical SHA is recomputed
## only when one of the effective authored fields actually changes.
static func _source_fingerprint(source,scope: String) -> String:
	var store: Script=load("res://scripts/mobile_pose_store.gd")
	var fields: Array=[source.posture_id]
	for field in store._fields(false):
		if field=="elbow_preset_bake":continue
		var value=source.get(field)
		if field in ["windup_body","follow_through_body"]:value=value.values if value!=null else null
		fields.append(value)
	var signature: PackedByteArray=var_to_bytes(fields)
	var key: String=str(source.get_instance_id())+"/"+scope
	var cached: Dictionary=_source_cache.get(key,{})
	if not cached.is_empty() and cached.ref.get_ref()==source and cached.bytes==signature:return cached.fingerprint
	var fingerprint: String=store.authored_fingerprint(source,scope)
	if _source_cache.size()>=MAX_SOURCE_CACHE:_source_cache.erase(_source_cache.keys()[0])
	_source_cache[key]={"ref":weakref(source),"bytes":signature,"fingerprint":fingerprint}
	return fingerprint

## Invert the same monotone engine easing used by StrokePlaybackClock. The
## fixed28 iterations are scalar arithmetic, never a pose/candidate search.
static func clock_coordinate(source,progress: float) -> float:
	var p := clampf(progress,0.0,1.0)
	var strike: float=maxf(0.01,source.ft_duration_strike)
	var sweep: float=maxf(0.01,source.ft_duration_sweep)
	if p<=0.0:return 0.0
	if p>=1.0:return 1.0
	if p==0.5:return strike/(strike+sweep)
	var initial: float=0.0 if p<0.5 else 0.5
	var span: float=strike if p<0.5 else sweep
	var transition: Tween.TransitionType=Tween.TRANS_QUAD if source.ft_ease_curve==1 else Tween.TRANS_SINE if source.ft_ease_curve==2 else Tween.TRANS_EXPO
	var ease: Tween.EaseType=Tween.EASE_IN_OUT if source.ft_ease_curve==2 else Tween.EASE_OUT
	var low:=0.0;var high:=1.0
	for iteration in range(28):
		var middle: float=(low+high)*0.5
		var value: float=Tween.interpolate_value(initial,0.5,middle*span,span,transition,ease)
		if value<p:low=middle
		else:high=middle
	var u: float=(low+high)*0.5
	return (strike*u if p<0.5 else strike+sweep*u)/(strike+sweep)

static func _bracket(rows: Array,p: float,key: String="") -> Array:
	var low := 0;var high := rows.size()-1
	while low < high:
		var middle: int = (low+high)/2
		var value: float = float(rows[middle][0] if key.is_empty() else rows[middle][key])
		if value < p: low=middle+1
		else: high=middle
	var b := low;var a := maxi(0,b-1)
	var start: float = float(rows[a][0] if key.is_empty() else rows[a][key])
	var finish: float = float(rows[b][0] if key.is_empty() else rows[b][key])
	return [a,b,0.0 if b==a else clampf((p-start)/(finish-start),0.0,1.0)]

static func _perpendicular(axis: Vector3,hint: Vector3) -> Vector3:
	var radial := hint-axis*hint.dot(axis)
	if radial.length_squared()<1e-12:
		var least := Vector3.RIGHT
		if absf(axis.y)<=absf(axis.x) and absf(axis.y)<=absf(axis.z): least=Vector3.UP
		elif absf(axis.z)<=absf(axis.x): least=Vector3.BACK
		radial=least-axis*least.dot(axis)
	return radial.normalized()

static func _transport(reference: Vector3,before: Vector3,after: Vector3) -> Vector3:
	var cross_axis := before.cross(after)
	var cosine := clampf(before.dot(after),-1.0,1.0)
	var rotated := reference
	if cross_axis.length_squared()>1e-14: rotated=reference.rotated(cross_axis.normalized(),atan2(cross_axis.length(),cosine))
	elif cosine<0.0: rotated=reference.rotated(_perpendicular(before,reference),PI)
	return _perpendicular(after,rotated)

static func sample_elbow(route: Dictionary,p: float,shoulder: Vector3,wrist: Vector3,upper: float,fore: float,root_basis: Basis) -> Vector3:
	var distance := shoulder.distance_to(wrist)
	if distance<1e-6 or distance>upper+fore+0.000001 or distance<absf(upper-fore)-0.000001: return Vector3.INF
	var rows: Array=route.knots;var bracket:=_bracket(rows,p)
	var a: Array=rows[bracket[0]];var b: Array=rows[bracket[1]];var u: float=bracket[2]
	# Exact knots use their own transported chart, as Route.sample does.
	if absf(p-float(b[0]))<1e-9: a=b;u=0.0
	var angle: float=float(a[1])
	if a!=b:
		var h: float=float(b[0])-float(a[0]);var square:=u*u;var cube:=square*u
		angle=(2*cube-3*square+1)*float(a[1])+(cube-2*square+u)*h*float(a[2])+(-2*cube+3*square)*float(b[1])+(cube-square)*h*float(b[2])
	var axis := (wrist-shoulder)/distance
	var reference := _transport(root_basis*v(a.slice(6,9)),root_basis*v(a.slice(3,6)),axis)
	var along := (upper*upper-fore*fore+distance*distance)/(2.0*distance)
	var radius := sqrt(maxf(0.0,upper*upper-along*along))
	return shoulder+axis*along+reference.rotated(axis,angle)*radius

static func _same_transform(actual: Transform3D,a: Array,b: Array,u: float) -> bool:
	var expected := transform(a).interpolate_with(transform(b),u)
	return actual.origin.distance_to(expected.origin)<=POSITION_EPS and basis_error(actual.basis,expected.basis)<=ROTATION_EPS and actual.basis.get_scale().distance_to(expected.basis.get_scale())<=POSITION_EPS

static func _context_matches(player,bake: Dictionary,p: float,root: Transform3D) -> bool:
	var bracket := _bracket(bake.samples,p,"p")
	var a: Dictionary=bake.samples[bracket[0]];var b: Dictionary=bake.samples[bracket[1]];var u: float=bracket[2]
	var inverse := root.affine_inverse()
	if not _same_transform(model_transform(root,player.body_pivot.global_transform),a.body,b.body,u): return false
	if not _same_transform(inverse*player.paddle_node.global_transform,a.paddle,b.paddle,u): return false
	var hands=player.arm_ik._hands
	if absf(float(hands._support_grip_weight)-lerpf(float(a.weight),float(b.weight),u))>0.00001: return false
	var torso=player.body_pivot.get_meta("articulated_torso",null)
	if torso==null: return false
	var skins: Array=[torso._last_pelvis,torso._last_abdomen,torso._last_chest]
	for i in range(3):
		if not _same_transform(model_transform(root,player.body_pivot.global_transform*skins[i]),a.skin[i],b.skin[i],u): return false
	for side in range(2):
		var arm=player.right_arm_node if side==0 else player.left_arm_node
		var mode: String="GRIP" if side==int(bake.handedness) else str(hands.mode)
		if mode!=str(a.modes[side]) or mode!=str(b.modes[side]): return false
		if absf(arm.upper_arm_length-float(bake.rig.links[side][0]))>0.000001 or absf(arm.forearm_length-float(bake.rig.links[side][1]))>0.000001:return false
		if arm.articulated_hand.wrist_socket.distance_to(v(bake.rig.sockets[side]))>0.000001:return false
		var anatomy: Array=bake.rig.anatomy[side]
		if basis_error(arm.articulated_hand.anatomical_basis,Basis(v(anatomy.slice(0,3)),v(anatomy.slice(3,6)),v(anatomy.slice(6,9))))>ROTATION_EPS:return false
		if (inverse*arm.upper_pivot.global_position).distance_to(v(a.shoulders[side]).lerp(v(b.shoulders[side]),u))>POSITION_EPS:return false
		if not _same_transform(inverse*arm.hand_mesh.global_transform,a.hands[side],b.hands[side],u):return false
		# Inherited-arm geometry participates in the bake's collision proof too.
		if not bool(bake.active_sides[side]) and (inverse*arm.forearm_pivot.global_position).distance_to(v(a.elbows[side]).lerp(v(b.elbows[side]),u))>POSITION_EPS:return false
	return true

static func apply(player,pose) -> Dictionary:
	if pose==null or not pose.has_meta(SAMPLE_META):return {"applied":false,"status":"No matching baked sample"}
	# Core-only certificates cannot authorize a complete gameplay action.
	# Permission belongs to a private rig, never to a copied pose or saved bake.
	if not bool(player.get_meta(PRIVATE_PREVIEW_META,false)) or player.posture==null or not player.posture.editor_preview_mode:
		return {"applied":false,"status":"Core-only preset requires a private diagnostic preview; original retained"}
	if bool(player.get_meta("elbow_preset_capture",false)):return {"applied":false,"status":"Capturing authored baseline"}
	var sample=pose.get_meta(SAMPLE_META)
	if not sample is Dictionary or sample.size()!=3 or not sample.has_all(["bake","progress","scope"]):return {"applied":false,"status":"Invalid baked sample metadata"}
	if not (sample.progress is float or sample.progress is int) or not is_finite(float(sample.progress)) or float(sample.progress)<0.0 or float(sample.progress)>1.0:return {"applied":false,"status":"Invalid baked sample progress"}
	if not sample.scope is String or not Codec.admit(sample.bake):return {"applied":false,"status":"Invalid or changed baked payload"}
	var bake: Dictionary=sample.bake;var p: float=float(sample.progress)
	if sample.scope!=bake.scope:return {"applied":false,"status":"Baked sample scope mismatch"}
	if int(bake.source_id)!=pose.posture_id or int(bake.handedness)!=pose.paddle_hand:return {"applied":false,"status":"Source or handedness changed"}
	var root:=root_for(player)
	if not _context_matches(player,bake,p,root):return {"applied":false,"status":"Current contact/body/grip context differs; original retained"}
	var body: Transform3D=player.body_pivot.global_transform
	var paddle: Transform3D=player.paddle_node.global_transform
	var head: Vector3=paddle*Size.HEAD_OFFSET
	var delta: Basis=root.basis*Basis.from_euler(v(bake.rotation_deg)*(PI/180.0))*root.basis.inverse()
	var next_paddle:=Transform3D(delta*paddle.basis,Vector3.ZERO)
	next_paddle.origin=head-next_paddle.basis*Size.HEAD_OFFSET
	var states: Array=[];var solutions: Array=[]
	for side in range(2):
		var arm=player.right_arm_node if side==0 else player.left_arm_node
		var nodes: Array=[]
		for node in [arm.upper_pivot,arm.forearm_pivot,arm.hand_pivot,arm.upper_mesh,arm.fore_mesh,arm.hand_mesh]:nodes.append([node,node.transform])
		states.append({"arm":arm,"nodes":nodes,"wrist":arm.anatomical_wrist_world,"stretch":arm.visual_stretch,"lag":arm.visual_wrist_lag_deg,"shoulder":arm.upper_pivot.global_position})
		var mount: Transform3D=arm.hand_mesh.global_transform
		var target: Vector3=arm.hand_pivot.global_position
		var attached: bool=side==int(bake.handedness) or str(player.arm_ik._hands.mode)=="GRIP" or (str(player.arm_ik._hands.mode)=="REGRIP" and float(player.arm_ik._hands._support_grip_weight)>=0.999999)
		if attached:
			if not bool(bake.active_sides[side]) and v(bake.rotation_deg).length_squared()>1e-12:return {"applied":false,"status":"Rotated attached arm is not active"}
			mount=Transform3D(delta*mount.basis,head+delta*(mount.origin-head));target=head+delta*(target-head)
		var wrist: Vector3=mount*arm.articulated_hand.wrist_socket
		var elbow: Vector3=arm.forearm_pivot.global_position
		if bool(bake.active_sides[side]):
			elbow=sample_elbow(bake.routes[side],p,arm.upper_pivot.global_position,wrist,arm.upper_arm_length,arm.forearm_length,root.basis)
			if not elbow.is_finite():return {"applied":false,"status":"Fixed wrist is unreachable"}
		solutions.append({"mount":mount,"target":target,"wrist":wrist,"elbow":elbow})
	# No mutations happened before every active solution was reconstructed.
	player.paddle_node.global_transform=next_paddle
	var okay:=true
	for side in range(2):
		if not bool(bake.active_sides[side]):continue
		var arm=states[side].arm;var solution: Dictionary=solutions[side]
		if arm.upper_pivot.global_basis.get_scale().distance_to(Vector3.ONE)>0.001:okay=false;break
		arm.upper_pivot.global_basis=arm.upper_pivot.global_basis.orthonormalized();arm.forearm_pivot.basis=Basis.IDENTITY
		arm.visual_wrist_lag_deg=0.0
		arm.solve_ik(solution.target,solution.elbow,next_paddle if side==int(bake.handedness) else null,solution.wrist)
		arm.articulated_hand.set_mesh_world_transform(solution.mount)
		arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
		var actual_wrist: Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
		var channels: Dictionary=Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm,actual_wrist,side==1),arm.hand_mesh.global_basis*arm.articulated_hand.anatomical_basis,arm.articulated_hand.radial_sign)
		okay=okay and bool(channels.within_animation_budget) and arm.visual_stretch<=1.000001
		okay=okay and actual_wrist.distance_to(solution.wrist)<=POSITION_EPS and arm.forearm_pivot.global_position.distance_to(solution.elbow)<=POSITION_EPS
		okay=okay and absf(arm.upper_pivot.global_position.distance_to(arm.forearm_pivot.global_position)-arm.upper_arm_length)<=POSITION_EPS
		okay=okay and absf(arm.forearm_pivot.global_position.distance_to(actual_wrist)-arm.forearm_length)<=POSITION_EPS
	for state in states:okay=okay and state.arm.upper_pivot.global_position.distance_to(state.shoulder)<=POSITION_EPS
	okay=okay and (player.paddle_node.global_transform*Size.HEAD_OFFSET).distance_to(head)<=0.000002
	okay=okay and player.body_pivot.global_position.distance_to(body.origin)<=0.000002 and basis_error(player.body_pivot.global_basis,body.basis)<=0.0000174533
	if not okay:
		player.paddle_node.global_transform=paddle
		for state in states:
			for item in state.nodes:item[0].transform=item[1]
			state.arm.anatomical_wrist_world=state.wrist;state.arm.visual_stretch=state.stretch;state.arm.visual_wrist_lag_deg=state.lag
			Visual.update_arm(state.arm);state.arm.articulated_hand.update_wrist_bridge(state.arm.fore_mesh.global_basis)
	return {"applied":okay,"status":"Baked initial preset applied" if okay else "Actual invariant gate failed; original restored"}
