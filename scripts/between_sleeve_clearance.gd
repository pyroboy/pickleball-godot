extends RefCounted
## Exact sleeve query accelerator. The conservative separating-axis margin only
## proves distant triangle pairs clear; close pairs retain the original query.
const Sleeve=preload("res://scripts/live_ready_clearance.gd")
const Surface=preload("res://scripts/player_surface_contacts.gd")

static func _pair_clear(a:Vector3,b:Vector3,c:Vector3,d:Vector3,e:Vector3,f:Vector3,gap:float)->bool:
 var first:Array[Vector3]=[b-a,c-b,a-c]
 var second:Array[Vector3]=[e-d,f-e,d-f]
 var na:Vector3=first[0].cross(first[1]);var nb:Vector3=second[0].cross(second[1])
 var axes:Array[Vector3]=[na,nb]
 for x in first:
  for y in second:axes.append(x.cross(y))
 if na.cross(nb).length_squared()<.000000000001:
  for x in first:axes.append(na.cross(x))
  for y in second:axes.append(nb.cross(y))
 var separated:bool=false
 for axis in axes:
  if axis.length_squared()<.000000000001:continue
  var lo_a:float=minf(a.dot(axis),minf(b.dot(axis),c.dot(axis)))
  var hi_a:float=maxf(a.dot(axis),maxf(b.dot(axis),c.dot(axis)))
  var lo_b:float=minf(d.dot(axis),minf(e.dot(axis),f.dot(axis)))
  var hi_b:float=maxf(d.dot(axis),maxf(e.dot(axis),f.dot(axis)))
  var distance:float=maxf(lo_a-hi_b,lo_b-hi_a)
  if distance>0.0:separated=true
  # A positive projection gap divided by axis length is a lower bound on
  # Euclidean separation. One extra micrometre is reserved for arithmetic.
  if distance>(gap+.000001)*axis.length():return true
 if not separated:return false
 return gap<=0.0 or Sleeve.triangle_distance(a,b,c,d,e,f)>=gap

static func _clear_triangle(a:Vector3,b:Vector3,c:Vector3,broad:AABB,geometry:Dictionary,tree:Dictionary,gap:float)->bool:
 if not broad.intersects(tree.bounds):return true
 if tree.has("children"):
  for child in tree.children:
   if not _clear_triangle(a,b,c,broad,geometry,child,gap):return false
  return true
 var body:PackedVector3Array=geometry.points
 for item:int in tree.indices:
  if not broad.intersects(geometry.bounds[item]):continue
  var offset:int=item*3
  if not _pair_clear(a,b,c,body[offset],body[offset+1],body[offset+2],gap):return false
 return true

static func arm_clear(arm, geometry: Dictionary, required_gap: float = 0.0) -> bool:
 if not geometry.get("valid", false): return false
 var inverse: Transform3D = geometry.inverse
 var shoulder: Vector3 = arm.upper_pivot.global_position
 var elbow: Vector3 = arm.forearm_pivot.global_position
 var axis := (elbow - shoulder).normalized()
 var displayed_wrist: Vector3 = arm.forearm_pivot.to_global(Vector3(0, 0, -arm.forearm_length))
 if Sleeve._inside(inverse * elbow, geometry) or Sleeve._inside(inverse * displayed_wrist, geometry): return false
 var body: PackedVector3Array = geometry.points
 for mesh in [arm.upper_mesh, arm.fore_mesh]:
  var points := Surface.world_triangles(mesh)
  for index in range(0, points.size() - 2, 3):
   var polygon := PackedVector3Array([points[index], points[index + 1], points[index + 2]])
   if mesh == arm.upper_mesh:
    var clipped := PackedVector3Array()
    var previous := polygon[-1]; var before := (previous - shoulder).dot(axis) >= Sleeve.JointSeam
    for point in polygon:
     var after := (point - shoulder).dot(axis) >= Sleeve.JointSeam
     if before != after: clipped.append(previous.lerp(point, (Sleeve.JointSeam - (previous - shoulder).dot(axis)) / (point - previous).dot(axis)))
     if after: clipped.append(point)
     previous = point; before = after
    polygon = clipped
   if polygon.size() < 3: continue
   for i in range(polygon.size()): polygon[i] = inverse * polygon[i]
   for fan in range(1, polygon.size() - 1):
    var a: Vector3 = polygon[0]; var b: Vector3 = polygon[fan]; var c: Vector3 = polygon[fan + 1]
    var broad := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(required_gap)
    if not _clear_triangle(a, b, c, broad, geometry, geometry.tree, required_gap): return false
 return true

