extends SceneTree
const Preview=preload("res://scripts/ui/mobile_pose_preview.gd")
const Path=preload("res://scripts/stroke_swing_path.gd")
const D=preload("res://scripts/paddle_dimensions.gd")
const Keyframe=preload("res://scripts/stroke_body_keyframe.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func run()->void:
	var preview=Preview.new()
	preview.size=Vector2(640,360)
	root.add_child(preview)
	await process_frame
	await process_frame
	check(preview.motion_root==null,"motion visuals allocated only when requested")
	var def:PostureDefinition=PostureLibrary.instance().get_def(0).duplicate(true)
	var selected:PostureDefinition=Path.sample(def,.27)
	preview.show_pose(selected)
	var initial:Transform3D=preview.player.paddle_node.global_transform
	var time:=Time.get_ticks_usec()
	preview.set_motion(def)
	print("ARC BUILD USEC: ",Time.get_ticks_usec()-time)
	check(preview.pose==selected,"set_motion preserves selected resource")
	check(preview.player.paddle_node.global_transform.is_equal_approx(initial),"set_motion preserves rendered transform")
	check(preview.sample_heads.size()==65,"65 samples")
	check(preview.ghost_transforms.size()==3 and preview._ghosts.size()==3,"exactly 3 ghost paddles")
	check(preview._ghost_root.find_children("*","CollisionObject3D",true,false).is_empty(),"no ghost collision nodes")
	check(preview._ghost_root.find_children("*","MeshInstance3D",true,false).size()==6,"three actual Head and Handle mesh pairs")
	for stage in range(3):
		check(preview._ghosts[stage].get_node("Head").mesh==preview.player.paddle_node.get_node("Head").mesh,"real shared head mesh")
	check(preview.motion_root.find_children("*","Label3D",true,false).is_empty(),"motion geometry has no floating stage labels")
	for index in range(65):
		preview.show_pose(Path.sample(def,index/64.0))
		check(preview.sample_heads[index].distance_to(preview.player.paddle_node.to_global(D.HEAD_OFFSET))<.000001,"sample equals solved display %d"%index)
		if index in [0,32,64]:check(preview.ghost_transforms[index/32].is_equal_approx(preview.player.paddle_node.global_transform),"endpoint equals solved ghost")
	var count:int=preview.motion_rebuild_count
	for index in range(100):
		preview.show_pose(Path.sample(def,index/99.0))
		preview.set_motion(def)
	preview.view("side");preview.zoom(.1)
	check(preview.motion_rebuild_count==count,"scrub/play/camera do not rebuild cached arc")
	def.windup_body=Keyframe.new();def.windup_body.values.body_yaw_deg=25.0
	preview.set_motion(def)
	check(preview.motion_rebuild_count==count+1,"new nested keyframe invalidates cache")
	def.windup_body.values.body_yaw_deg=42.0
	preview.set_motion(def)
	check(preview.motion_rebuild_count==count+2,"in-place nested keyframe invalidates cache")
	var bounded:PostureDefinition=def.duplicate(true)
	bounded.charge_paddle_offset=Vector3(5,-5,5)
	bounded.ft_paddle_offset=Vector3(-5,-5,-5)
	preview.set_motion(bounded)
	for index in [0,17,32,55,64]:
		preview.show_pose(Path.sample(bounded,index/64.0))
		check(preview.sample_heads[index].distance_to(preview.player.paddle_node.to_global(D.HEAD_OFFSET))<.000001,"constraints match rendered paddle %d"%index)
	preview.set_motion(def,false)
	check(not preview.motion_root.visible,"body stance disable hides all motion")
	preview.set_motion(PostureLibrary.instance().get_def(20))
	check(not preview.motion_root.visible,"Ready rejects invented phases")
	preview.set_motion(def)
	preview.set_ghosts_visible(false);check(not preview._ghost_root.visible and preview._arc.visible,"independent ghost toggle")
	preview.set_arc_visible(false);check(not preview._arc.visible,"independent arc toggle")
	preview.set_ghosts_visible(true);preview.set_arc_visible(true)
	check(preview._ghost_root.visible and preview._arc.visible,"independent toggles restore")
	var root_ref:WeakRef=weakref(preview.motion_root)
	preview.queue_free()
	await process_frame
	await process_frame
	check(root_ref.get_ref()==null,"free editor frees motion resources")
	print("MOBILE POSE ARC: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
