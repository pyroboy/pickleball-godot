extends SceneTree
const Sequence = preload("res://scripts/ui/mobile_pose_sequence.gd")
const Clock = preload("res://scripts/stroke_playback_clock.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Runtime = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label)
func same(a:PostureDefinition,b:PostureDefinition,label:String)->void:
	for field in ["paddle_forehand_mul","paddle_y_offset","paddle_forward_mul","body_yaw_deg","hip_yaw_deg","torso_yaw_deg","crouch_amount"]:
		check(is_equal_approx(a.get(field),b.get(field)),label+" "+field)
func run()->void:
	var scale := Engine.time_scale
	var seq := Sequence.new()
	var ready:PostureDefinition=PostureLibrary.instance().get_def(20)
	var durations:Array=[]
	for def in PostureLibrary.instance().all_definitions():
		if def.posture_id==20:continue
		var before:=var_to_bytes(Store._encode_fields(def))
		seq.configure(def,Sequence.Mode.TO_READY)
		var finish:=Motion.sample_drive(def,1,1)
		var d:=Clock.durations(def,finish,ready)
		check(is_equal_approx(seq.duration,seq.prefix_seconds+d.total),"duration parity %s"%def.display_name)
		durations.append({"name":def.display_name,"seconds":d})
		for ratio in [0.0,0.1,0.25,0.5,0.9,1.0]:
			var t:float=d.strike*ratio
			var curve:=Tween.TRANS_QUAD if def.ft_ease_curve==1 else Tween.TRANS_SINE if def.ft_ease_curve==2 else Tween.TRANS_EXPO
			var ease_type:=Tween.EASE_IN_OUT if def.ft_ease_curve==2 else Tween.EASE_OUT
			var expected_p:float=Tween.interpolate_value(0.,.5,t,d.strike,curve,ease_type)
			var actual:=seq.sample(seq.prefix_seconds+t)
			check(is_equal_approx(actual.progress,expected_p),"strike easing parity")
			same(actual.pose,Motion.sample_drive(def,expected_p,1),"runtime drive pose parity")
			t=d.strike+d.sweep*ratio
			expected_p=Tween.interpolate_value(.5,.5,d.sweep*ratio,d.sweep,curve,ease_type)
			same(seq.sample(seq.prefix_seconds+t).pose,Motion.sample_drive(def,expected_p,1),"runtime sweep pose parity")
			t=d.stroke+d.hold+d.recovery*ratio
			var joined:=Clock.Grip.supports_both_joined(finish,ready)
			var factor:float=Tween.interpolate_value(0.,1.,d.recovery*ratio,d.recovery,Tween.TRANS_LINEAR if joined else Tween.TRANS_SINE,Tween.EASE_IN_OUT)
			var recovery:=Clock.Grip.sample(finish,ready,factor) if joined else Path.blend_pose(finish,ready,factor)
			same(seq.sample(seq.prefix_seconds+t).pose,recovery,"runtime recovery pose parity")
		for variant in [1,2]:
			seq.configure(def,Sequence.Mode.TO_READY,0,variant)
			check(is_equal_approx(seq.stroke_seconds,d.stroke),"variant does not invent duration")
			for t in [0.,d.strike*.5,d.strike,d.stroke]:
				var state:=Clock.state(def,t,seq.finish,seq.ready)
				same(seq.sample(seq.prefix_seconds+t).pose,seq.variant.sample(seq.source,state.progress),"shared variant geometry and clock")
			seq.configure(def,Sequence.Mode.RECEIVE_STROKE,0,variant)
			if variant==1:
				same(seq.sample(seq.RECEIVE_SECONDS+seq.Held.WINDUP_SECONDS).pose,seq.variant.sample_amount(seq.source,0.,0.),"Strong normal windup at 0.6 seconds")
				same(seq.sample(seq.prefix_seconds).pose,seq.variant.sample(seq.source,0.),"Strong extension at 1.2 seconds")
		for stance in [Sequence.Stance.OPEN,Sequence.Stance.CLOSED]:
			seq.configure(def,Sequence.Mode.RECEIVE_STROKE,stance)
			var a:PostureDefinition=seq.sample(seq.duration*.72).pose
			seq.sample(seq.duration*.99);seq.sample(.02)
			same(a,seq.sample(seq.duration*.72).pose,"backward seek deterministic")
		check(before==var_to_bytes(Store._encode_fields(def)),"no authored mutation")
	for style in range(7):
		var def:=ServeStore.get_def(style)
		seq.configure(def,Sequence.Mode.TO_READY)
		var contact:float=Runtime.serve_plan(style).contact_time
		for t in [0.,contact*.5,contact,seq.stroke_seconds,seq.stroke_seconds+Motion.SERVE_HOLD_TIME,seq.duration]:
			same(seq.sample(seq.prefix_seconds+t).pose,Runtime.sample_serve_elapsed(style,t,1.,1.,def,false),"serve exact runtime phase")
		for variant in [1,2]:
			seq.configure(def,Sequence.Mode.TO_READY,0,variant)
			check(seq.sample(seq.stroke_seconds+Motion.SERVE_HOLD_TIME*.5).pose != null,"variant serve hold sample")
			same(seq.sample(seq.duration).pose,seq.ready,"variant serve ends ready")
	seq.configure(PostureLibrary.instance().get_def(1),Sequence.Mode.RECEIVE_STROKE)
	check(seq.sample(.1).split.active,"receive fixture split active")
	check(seq.sample(seq.duration).split.is_empty(),"own stroke never adds split step")
	check(Engine.time_scale==scale,"no global time scale writes")
	print(JSON.stringify({"checks":checks,"failures":failures,"durations":durations}))
	quit(0 if failures.is_empty() else 1)
