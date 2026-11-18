extends RefCounted
## Editor-only conversion. Gameplay never loads the route planner/capture fixture.
const Codec=preload("res://scripts/elbow_preset_bake.gd")
const Store=preload("res://scripts/mobile_pose_store.gd")
const Runtime=preload("res://scripts/elbow_preset_runtime.gd")
static func vector(value: Vector3) -> Array:return [value.x,value.y,value.z]
static func basis(value: Basis) -> Array:return vector(value.x)+vector(value.y)+vector(value.z)
static func transform(value: Transform3D) -> Array:return basis(value.basis)+vector(value.origin)

static func pack(result: Dictionary,_source: Dictionary,fine: Array,duration: float,definition,scope: String="stroke_runtime") -> Dictionary:
	if not bool(result.get("valid",false)) or fine.size()<2 or duration<=0.0:return {}
	if not fine[0][0].has("root_transform"):return {}
	var first: Dictionary=fine[0][0]
	var root: Transform3D=first.root_transform
	var local_rotation:=root.basis.inverse()*Basis.from_euler(result.rotation)*root.basis
	var rig: Dictionary={"links":[],"sockets":[],"anatomy":[]}
	for side in range(2):
		var frame: Dictionary=fine[0][side]
		rig.links.append([frame.upper_length,frame.fore_length]);rig.sockets.append(vector(frame.wrist_socket));rig.anatomy.append(basis(frame.anatomical_basis))
	var payload: Dictionary={"version":1,"model":Codec.MODEL_VERSION,"scope":scope,"source_id":definition.posture_id,"source_sha256":Store.authored_fingerprint(definition,scope),"handedness":definition.paddle_hand,"active_sides":result.active_sides.duplicate(),"rotation_deg":vector(local_rotation.get_euler()*(180.0/PI)),"offsets":[vector(result.offsets[0]),vector(result.offsets[1])],"duration":duration,"rig":rig,"routes":[],"samples":[]}
	for side in range(2):
		if not bool(result.active_sides[side]):payload.routes.append({});continue
		var route: Dictionary=result.bakes[side];var knots: Array=[]
		for i in range(route.nodes.size()):
			var node: Dictionary=route.nodes[i];var chart: Dictionary=route.charts[i]
			if not bool(node.get("valid",false)):return {}
			knots.append([float(node.time)/duration,node.angle,float(node.tangent)*duration]+vector(root.basis.inverse()*chart.axis)+vector(root.basis.inverse()*chart.reference))
		payload.routes.append({"knots":knots})
	for pair in fine:
		var frame: Dictionary=pair[0]
		if not frame.has("root_transform"):return {}
		var inverse: Transform3D=frame.root_transform.affine_inverse()
		var sample: Dictionary={"p":float(frame.time)/duration,"body":transform(Runtime.model_transform(frame.root_transform,frame.body_transform)),"paddle":transform(inverse*frame.paddle_transform),"shoulders":[],"hands":[],"elbows":[],"skin":[],"modes":[],"weight":frame.production_support_grip_weight}
		if frame.body_skin_frames.size()!=3:return {}
		for skin in frame.body_skin_frames:sample.skin.append(transform(Runtime.model_transform(frame.root_transform,frame.body_transform*skin)))
		for side in range(2):
			var arm: Dictionary=pair[side]
			sample.shoulders.append(vector(inverse*arm.shoulder));sample.hands.append(transform(inverse*arm.hand_mount));sample.elbows.append(vector(inverse*arm.baseline_elbow));sample.modes.append("GRIP" if arm.dominant else str(arm.production_hand_mode))
		payload.samples.append(sample)
	return Codec.seal(payload)
