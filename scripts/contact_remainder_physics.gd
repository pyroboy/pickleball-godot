extends RefCounted
## Pure collision continuation after a measured hand impact. Segment times
## conserve elapsed time; exhaustion exposes unconsumed time to the caller.
const BallPhysics=preload("res://scripts/ball.gd")
const Boundary=preload("ball_boundary_motion.gd")
const Net=preload("res://scripts/net_profile.gd")
const Geometry=preload("res://scripts/contact_surface_geometry.gd")
const MAX_SEGMENTS:=64
const MAX_EVENTS:=8
const CONTACT_EPSILON:=0.00002
static var _fabric:=PackedVector3Array()

static func trace(position:Vector3,velocity:Vector3,omega:Vector3,elapsed:float,radius:float=BallPhysics.BALL_RADIUS,initial_drift_seconds:float=0.0,scene:Dictionary={})->Dictionary:
	var requested:float=maxf(elapsed,0.0)
	var remaining:float=requested
	var consumed:=0.0
	var segments:Array[Dictionary]=[]
	var events:Array[Dictionary]=[]
	var gravity:float=BallPhysics.get_effective_gravity()
	var floor_supported:=false
	var quantum:float=1.0/float(Engine.physics_ticks_per_second)
	var drift_remaining:float=clampf(initial_drift_seconds,0.0,requested)
	while remaining>1e-10 and segments.size()<MAX_SEGMENTS and events.size()<MAX_EVENTS:
		# Match Ball.predict_aero_step's semi-implicit kick then drift.
		# Forces are applied ONCE for this interval; all geometric CCD and
		# contact responses use that same drift velocity. A body interruption
		# carries the unconsumed drift instead of applying forces twice.
		if drift_remaining<=1e-10:
			drift_remaining=minf(remaining,quantum)
			var step_gravity:float=0.0 if floor_supported else gravity
			var predicted:Array=BallPhysics.predict_aero_step(position,velocity,omega,step_gravity,drift_remaining)
			velocity=predicted[1];omega=predicted[2]
		var duration:float=minf(remaining,drift_remaining)
		var kick_end_time:float=consumed+duration
		var endpoint:Vector3=position+velocity*duration
		var collision:Dictionary=_first_collision(position,endpoint,velocity,radius,scene)
		if not collision.get("hit",false):
			segments.append({"from":position,"to":endpoint,"time_from":consumed,"time_to":consumed+duration,
				"velocity_from":velocity,"velocity_to":velocity,"omega_from":omega,"omega_to":omega,"kick_end_time":kick_end_time,"event_after":{}})
			position=endpoint
			consumed+=duration;remaining=maxf(0.0,requested-consumed);drift_remaining=maxf(0.0,drift_remaining-duration)
			continue
		if collision.get("type","")=="unsupported_wall_transform":break
		var fraction:float=clampf(float(collision.fraction),0.0,1.0)
		var until_contact:float=duration*fraction
		var point:Vector3=position.lerp(endpoint,fraction)
		var incoming:Vector3=velocity
		var incoming_spin:Vector3=omega
		var normal:Vector3=collision.normal
		var outgoing:Vector3=incoming
		var outgoing_spin:Vector3=incoming_spin
		if collision.type=="floor":
			point.y=BallPhysics.FLOOR_Y+radius
			var bounce:Array=Boundary.response("floor",incoming,incoming_spin)
			outgoing=bounce[0];outgoing_spin=bounce[1]
			if outgoing.y<0.025:
				floor_supported=true;outgoing.y=0.0
		elif collision.type=="ceiling":
			point.y=BallPhysics.FLIGHT_CEILING_Y
			var capped:Array=Boundary.response("ceiling",incoming,incoming_spin);outgoing=capped[0];outgoing_spin=capped[1]
		elif collision.type=="wall":
			var toward:float=incoming.dot(normal)
			outgoing=(incoming-normal*toward)-normal*toward*float(collision.restitution)
		else:
			var toward:float=incoming.dot(normal)
			outgoing=(incoming-normal*toward)*0.86-normal*toward*0.32
		var event:Dictionary={"type":collision.type,"time":consumed+until_contact,"fraction":(consumed+until_contact)/requested if requested>0 else 0.0,
			"point":point,"normal":normal,"incoming":incoming,"outgoing":outgoing,"omega_before":incoming_spin,"omega_after":outgoing_spin}
		if collision.has("post"):event.post=collision.post
		if collision.has("body_id"):event.body_id=collision.body_id
		segments.append({"from":position,"to":point,"time_from":consumed,"time_to":consumed+until_contact,
			"velocity_from":velocity,"velocity_to":incoming,"omega_from":omega,"omega_to":incoming_spin,"kick_end_time":kick_end_time,"event_after":event})
		events.append(event)
		consumed+=until_contact;remaining=maxf(0.0,requested-consumed);drift_remaining=maxf(0.0,drift_remaining-until_contact)
		# Microscopic collision separation, never a target correction.
		position=point+normal*CONTACT_EPSILON;velocity=outgoing;omega=outgoing_spin
	return {"position":position,"velocity":velocity,"omega":omega,"segments":segments,"events":events,
		"elapsed":consumed,"requested_elapsed":requested,"remaining_elapsed":remaining,"complete":remaining<=1e-10,
		"blocked":remaining>1e-10,"reason":"collision_budget" if remaining>1e-10 else "complete"}

static func _first_collision(from:Vector3,to:Vector3,velocity:Vector3,radius:float,scene:Dictionary={})->Dictionary:
	var best:Dictionary=Boundary.first(from,to,velocity,radius)
	var wall:Dictionary=_box_sweep(from,to,velocity,radius,scene.get("wall",{}))
	if wall.get("hit",false) and float(wall.fraction)<float(best.fraction):best=wall
	if not scene.get("net_active",true):return best
	var fabric:Dictionary=_fabric_sweep(from,to,radius)
	if fabric.get("hit",false) and velocity.dot(fabric.normal)<-0.00001 and float(fabric.fraction)<float(best.fraction):
		best=fabric;best.type="net"
	var post:Dictionary=Net.post_sweep(from,to,radius)
	if post.get("hit",false) and velocity.dot(post.normal)<-0.00001 and float(post.fraction)<=float(best.fraction)+1e-8:
		best=post;best.type="post"
	return best

static func _fabric_sweep(from:Vector3,to:Vector3,radius:float)->Dictionary:
	var result:Dictionary={"hit":false,"fraction":1.0}
	var low:Vector3=from.min(to);var high:Vector3=from.max(to)
	if low.x>Net.HALF_SPAN+radius or high.x<-Net.HALF_SPAN-radius: return result
	if low.z>Net.THICKNESS*.5+radius or high.z<-Net.THICKNESS*.5-radius:return result
	if low.y>Net.top_y_at(Net.HALF_SPAN)+radius or high.y<Net.FLOOR_Y-.01-radius:return result
	_ensure_fabric()
	for index in range(0,_fabric.size()-2,3):
		var a:Vector3=_fabric[index];var b:Vector3=_fabric[index+1];var c:Vector3=_fabric[index+2]
		var box:=AABB(a,Vector3.ZERO).expand(b).expand(c).grow(radius)
		if not box.has_point(from) and not box.has_point(to) and not box.intersects_segment(from,to):continue
		var limit:float=result.fraction
		if Geometry.segment_triangle_distance(from,from.lerp(to,limit),a,b,c)>radius:continue
		var left:=0.0;var right:=limit
		if from.distance_to(Geometry.closest_triangle(from,a,b,c))<=radius:right=0.0
		else:
			for iteration in 14:
				var middle:float=(left+right)*.5
				if Geometry.segment_triangle_distance(from,from.lerp(to,middle),a,b,c)<=radius:right=middle
				else:left=middle
		var point:Vector3=from.lerp(to,right)
		var nearest:Vector3=Geometry.closest_triangle(point,a,b,c)
		var normal:Vector3=(point-nearest).normalized()
		if normal.length_squared()<.5:normal=(b-a).cross(c-a).normalized()
		if (to-from).dot(normal)>=0.0:continue
		result={"hit":true,"fraction":right,"normal":normal,"point":point,"surface":nearest,"type":"net"}
	return result

static func _ensure_fabric()->void:
	if not _fabric.is_empty():return
	var z:float=Net.THICKNESS*.5
	var bottom:float=Net.FLOOR_Y-.01
	for i in Net.COLLISION_SEGMENTS:
		var left:float=lerpf(-Net.HALF_SPAN,Net.HALF_SPAN,float(i)/Net.COLLISION_SEGMENTS)
		var right:float=lerpf(-Net.HALF_SPAN,Net.HALF_SPAN,float(i+1)/Net.COLLISION_SEGMENTS)
		var tl:float=Net.top_y_at(left);var tr:float=Net.top_y_at(right)
		_quad(Vector3(left,bottom,-z),Vector3(right,bottom,-z),Vector3(right,tr,-z),Vector3(left,tl,-z))
		_quad(Vector3(left,bottom,z),Vector3(left,tl,z),Vector3(right,tr,z),Vector3(right,bottom,z))
		_quad(Vector3(left,tl,-z),Vector3(right,tr,-z),Vector3(right,tr,z),Vector3(left,tl,z))
		_quad(Vector3(left,bottom,-z),Vector3(left,bottom,z),Vector3(right,bottom,z),Vector3(right,bottom,-z))
		if i==0:_quad(Vector3(left,bottom,-z),Vector3(left,tl,-z),Vector3(left,tl,z),Vector3(left,bottom,z))
		if i==Net.COLLISION_SEGMENTS-1:_quad(Vector3(right,bottom,-z),Vector3(right,bottom,z),Vector3(right,tr,z),Vector3(right,tr,-z))

static func _quad(a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
	_fabric.append_array(PackedVector3Array([a,b,c,a,c,d]))

static func contact_at(point:Vector3,velocity:Vector3,radius:float,scene:Dictionary={})->Dictionary:
	## Actual point/surface overlap confirmation after a curved-path broadphase.
	if velocity.y<0.0 and point.y<=BallPhysics.FLOOR_Y+radius:
		return {"hit":true,"type":"floor","normal":Vector3.UP,"point":point}
	if velocity.y>0.0 and point.y>=BallPhysics.FLIGHT_CEILING_Y:
		return {"hit":true,"type":"ceiling","normal":Vector3.DOWN,"point":point}
	var wall:Dictionary=_box_sweep(point,point,velocity,radius,scene.get("wall",{}))
	if wall.get("hit",false):return wall
	if not scene.get("net_active",true):return {"hit":false}
	var post:Dictionary=Net.post_sweep(point,point,radius)
	if post.get("hit",false) and velocity.dot(post.normal)<0.0:
		post.type="post";post.point=point;return post
	if absf(point.x)>Net.HALF_SPAN+radius or absf(point.z)>Net.THICKNESS*.5+radius or point.y>Net.top_y_at(Net.HALF_SPAN)+radius:return {"hit":false}
	_ensure_fabric()
	for index in range(0,_fabric.size()-2,3):
		var nearest:Vector3=Geometry.closest_triangle(point,_fabric[index],_fabric[index+1],_fabric[index+2])
		if point.distance_squared_to(nearest)>radius*radius:continue
		var normal:Vector3=(point-nearest).normalized()
		if normal.length_squared()>.5 and velocity.dot(normal)<0.0:return {"hit":true,"type":"net","normal":normal,"point":point}
	return {"hit":false}

static func response_event(contact:Dictionary,velocity:Vector3,omega:Vector3)->Dictionary:
	var normal:Vector3=contact.normal
	var outgoing:Vector3;var spin:Vector3=omega
	if contact.type=="floor":
		var bounce:Array=Boundary.response("floor",velocity,omega);outgoing=bounce[0];spin=bounce[1]
	elif contact.type=="ceiling":
		var capped:Array=Boundary.response("ceiling",velocity,omega);outgoing=capped[0];spin=capped[1]
	elif contact.type=="wall":
		var toward:float=velocity.dot(normal)
		outgoing=(velocity-normal*toward)-normal*toward*float(contact.restitution)
	else:
		var toward:float=velocity.dot(normal);outgoing=(velocity-normal*toward)*.86-normal*toward*.32
	var event:Dictionary={"type":contact.type,"point":contact.point,"normal":normal,"incoming":velocity,"outgoing":outgoing,"omega_before":omega,"omega_after":spin}
	if contact.has("post"):event.post=contact.post
	if contact.has("body_id"):event.body_id=contact.body_id
	return event

static func _box_sweep(from:Vector3,to:Vector3,velocity:Vector3,radius:float,box:Dictionary)->Dictionary:
	if box.is_empty():return {"hit":false}
	var frame:Transform3D=box.transform
	var inverse:Transform3D=frame.affine_inverse()
	var origin:Vector3=inverse*from
	var motion:Vector3=inverse.basis*(to-from)
	var half:Vector3=box.half_size
	# The registered actual wall is rigid and unscaled. Unsupported shape
	# edits are explicit query failures, never a replacement infinite plane.
	if frame.basis != Basis.IDENTITY:return {"hit":true,"type":"unsupported_wall_transform","fraction":0.0,"normal":Vector3.ZERO}
	var cuts:Array[float]=[0.0,1.0]
	for axis in 3:
		if motion[axis]==0.0:continue
		for sign_value in [-1.0,1.0]:
			var t:float=(sign_value*float(half[axis])-float(origin[axis]))/float(motion[axis])
			if t>0.0 and t<1.0:cuts.append(t)
	cuts.sort()
	for i in range(cuts.size()-1):
		var low:float=cuts[i];var high:float=cuts[i+1]
		var middle:float=(low+high)*.5
		var aa:=0.0;var bb:=0.0;var cc:float=-radius*radius
		for axis in 3:
			var sample:float=float(origin[axis])+float(motion[axis])*middle
			var boundary:float=clampf(sample,-float(half[axis]),float(half[axis]))
			if sample==boundary:continue
			var offset:float=float(origin[axis])-boundary
			aa+=float(motion[axis])*float(motion[axis]);bb+=2.0*offset*float(motion[axis]);cc+=offset*offset
		var t:float=INF
		if (aa*low+bb)*low+cc<=0.0:t=low
		elif aa>0.0:
			var discriminant:float=bb*bb-4.0*aa*cc
			if discriminant>=0.0:
				var root:float=(-bb-sqrt(discriminant))/(2.0*aa)
				if root>=low and root<=high:t=root
		if not is_finite(t):continue
		var local:Vector3=origin+motion*t
		var nearest:Vector3=local.clamp(-half,half)
		var normal:Vector3=(frame.basis*(local-nearest)).normalized()
		if normal.length_squared()<.5 or velocity.dot(normal)>=-0.00001:continue
		return {"hit":true,"type":"wall","fraction":t,"point":from.lerp(to,t),"normal":normal,"restitution":box.restitution,"body_id":box.body_id}
	return {"hit":false}
