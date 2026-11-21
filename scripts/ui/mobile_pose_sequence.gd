extends RefCounted
## Deterministic, private fixture; no ball/contact simulation and no global state writes.
const Clock = preload("res://scripts/stroke_playback_clock.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ReadyCurve = preload("res://scripts/ready_windup_curve.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Runtime = preload("res://scripts/runtime_motion_preview.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Held = preload("res://scripts/held_hit_motion.gd")
const Split = preload("res://scripts/split_step_timing.gd")
const Variants = preload("res://scripts/stroke_windup_variants.gd")
enum Mode { STROKE, TO_READY, RECEIVE_STROKE, SERVE_RECEIVE, STROKE_ONLY }
const ElbowRuntime = preload("res://scripts/elbow_preset_runtime.gd")
enum Stance { AUTHORED, OPEN, CLOSED }
const CUE_LEAD := 0.20
const SPLIT_STEP := 1.0 / 240.0
# Neutral direction-read timeout is intentional: no invented lateral target.
const RECEIVE_SECONDS := CUE_LEAD + Split.LAND_AFTER_STRIKE + Split.READ_TIMEOUT + Split.RECOVER_TIME + SPLIT_STEP*4.0
var source: PostureDefinition
var ready: PostureDefinition
var finish: PostureDefinition
var style := -1
var mode := Mode.STROKE
var stance := Stance.AUTHORED
var runtime_motion := true
var variant_mode := 0
var variant
var stroke_seconds := 0.0
var release_seconds := 0.0
var full_seconds := 0.0
var preparation_seconds := 0.0
var prefix_seconds := 0.0
var duration := 0.0
var _split_frames: Array[Dictionary] = []

func configure(def: PostureDefinition, selected_mode: int = Mode.STROKE, selected_stance: int = Stance.AUTHORED, selected_variant: int = 0, use_runtime: bool = true, player = null) -> void:
	source = def.duplicate(true)
	mode = selected_mode; stance = selected_stance; variant_mode = selected_variant; runtime_motion = use_runtime
	style = ServeStore.style_id(source)
	ready = PostureLibrary.instance().get_def(20).duplicate(true)
	variant = null
	if variant_mode != 0:
		variant = Variants.new()
		variant.configure(source, variant_mode, ServeStore.sample if style >= 0 else Callable(), player)
	finish = _stroke_pose(1.0)
	if style >= 0:
		release_seconds = float(Runtime.serve_plan(style).contact_time)
		stroke_seconds = release_seconds + Styles.sweep_duration(style)
		full_seconds = stroke_seconds + Motion.SERVE_HOLD_TIME + Motion.SERVE_RECOVERY_TIME
		ready = Runtime.serve_recovery_target().duplicate(true)
	else:
		var d := Clock.durations(source, finish, ready)
		release_seconds = d.strike; stroke_seconds = d.stroke; full_seconds = d.total
	preparation_seconds = Held.STRONG_SECONDS if variant_mode == Variants.STRONG else Held.WINDUP_SECONDS
	prefix_seconds = preparation_seconds + (RECEIVE_SECONDS if mode == Mode.RECEIVE_STROKE else 0.0)
	duration = prefix_seconds + (stroke_seconds if mode == Mode.STROKE else full_seconds) + (RECEIVE_SECONDS if mode == Mode.SERVE_RECEIVE else 0.0)
	if mode == Mode.STROKE_ONLY:
		preparation_seconds = 0.0; prefix_seconds = 0.0
		duration = stroke_seconds + (Motion.SERVE_HOLD_TIME if style >= 0 else Clock.hold_duration(source))
	_bake_split()

# A core-only certificate cannot be switched on inside an unvalidated full
# action. This predicate is shared with pending Preview and its joint guide.
func permits_core_overlay() -> bool:
	return mode == Mode.STROKE_ONLY and style < 0 and runtime_motion and stance == Stance.AUTHORED and variant_mode == 0

func scoped_pose(pose: PostureDefinition) -> PostureDefinition:
	if not permits_core_overlay(): ElbowRuntime.clear_tag(pose)
	return pose

func _stroke_pose(progress: float) -> PostureDefinition:
	var pose: PostureDefinition
	if variant != null: pose = variant.sample(source, progress)
	elif style >= 0: pose = ServeStore.sample(source, progress)
	else: pose = Motion.sample_drive(source, progress, 1.0) if runtime_motion else Path.sample(source, progress)
	return scoped_pose(pose)

func _bake_split() -> void:
	_split_frames.clear()
	var split := Split.new()
	var t := 0.0
	while t <= RECEIVE_SECONDS + SPLIT_STEP:
		# Prime at a positive runtime tick; subsequent snapshots are absolute-time indexed.
		split.update(SPLIT_STEP, {"live": true, "cue_id": 1, "cue_lead": CUE_LEAD, "strike_id": 1 if t >= CUE_LEAD else -1, "hop_allowed": true})
		_split_frames.append(split.sample())
		t += SPLIT_STEP

func sample(seconds: float) -> Dictionary:
	var elapsed := clampf(seconds, 0.0, duration)
	var t := elapsed
	var pose: PostureDefinition
	var phase := ""
	var p := 0.0
	var split: Dictionary = {}
	if mode == Mode.RECEIVE_STROKE and t < RECEIVE_SECONDS:
		pose = ready.duplicate(true); split = _split_at(t); phase = "Opponent cue · " + str(split.phase)
	elif t < prefix_seconds:
		var preparation_elapsed := t-(RECEIVE_SECONDS if mode == Mode.RECEIVE_STROKE else 0.0)
		var windup := _stroke_pose(0.0)
		# Strong held input has two runtime intervals, not one stretched blend:
		# Ready → authored Wind-up at 0.6 s, then extension up to 1.2 s.
		if variant_mode == Variants.STRONG and variant != null:
			windup = variant.sample_amount(source,0.0,0.0)
			if preparation_elapsed > Held.WINDUP_SECONDS:
				pose = variant.sample_amount(source,0.0,smoothstep(Held.WINDUP_SECONDS,Held.STRONG_SECONDS,preparation_elapsed))
		var u: float = Ramp.lead(source,preparation_elapsed/Held.WINDUP_SECONDS) if Ramp.custom(source,Ramp.LEAD) else smoothstep(0.0,Held.WINDUP_SECONDS,preparation_elapsed)
		if pose == null:
			pose = ReadyCurve.sample(ready,windup,u)
		phase = "Charging · Ready → Wind-up" if preparation_elapsed <= Held.WINDUP_SECONDS else "Charging · Wind-up → Strong"
	elif mode == Mode.SERVE_RECEIVE and t >= prefix_seconds+full_seconds:
		pose = ready.duplicate(true); split = _split_at(t-prefix_seconds-full_seconds); phase = "Opponent return cue · " + str(split.phase); p = 1.0
	else:
		t -= prefix_seconds
		if style >= 0:
			p = 0.5*t/release_seconds if t <= release_seconds else 0.5+0.5*minf((t-release_seconds)/Styles.sweep_duration(style),1.0)
			pose = Runtime.sample_serve_elapsed(style,t,1.0,1.0,source,false)
			pose.set_meta("mobile_serve_planted_stance", true)
			phase = str(pose.get_meta("preview_serve_phase", "Serve"))
			if variant != null:
				if t <= stroke_seconds: pose = variant.sample(source,p)
				elif t <= stroke_seconds+Motion.SERVE_HOLD_TIME: pose = finish.duplicate(true)
				else: pose = Motion.ServeJoint.recover_to_ready(finish,ready,clampf((t-stroke_seconds-Motion.SERVE_HOLD_TIME)/Motion.SERVE_RECOVERY_TIME,0,1))
		else:
			var state := Clock.state(source,t,finish,ready)
			p = state.progress; phase = state.phase
			pose = _stroke_pose(p)
			if state.recovery > 0:
				pose = Clock.Grip.sample(finish,ready,state.recovery) if Clock.Grip.supports_both_joined(finish,ready) else Path.blend_pose(finish,ready,state.recovery)
	pose = scoped_pose(_stance_copy(pose))
	return {"pose": pose, "phase": phase, "progress": clampf(p,0,1), "elapsed": elapsed, "duration": duration, "split": split, "authored_key": -1, "context": true}

func _split_at(t: float) -> Dictionary:
	return _split_frames[clampi(int(round(t/SPLIT_STEP)),0,_split_frames.size()-1)].duplicate(true)

func _stance_copy(pose: PostureDefinition) -> PostureDefinition:
	if stance == Stance.AUTHORED: return pose
	var p := pose.duplicate(true)
	var closed := stance == Stance.CLOSED
	var side := (-1.0 if source.family == 1 else 1.0)*(-1.0 if source.paddle_hand == 1 else 1.0)
	var yaw := side*75.0 if closed else 0.0
	p.stance_width = 0.24 if closed else 0.66
	p.front_foot_forward = 0.30 if closed else 0.0; p.back_foot_back = -0.30 if closed else 0.0
	p.right_foot_offset = Vector3.ZERO; p.left_foot_offset = Vector3.ZERO
	p.right_foot_yaw_deg = yaw; p.left_foot_yaw_deg = yaw
	p.right_knee_pole = Vector3(sin(deg_to_rad(yaw)),0.5,cos(deg_to_rad(yaw))); p.left_knee_pole = p.right_knee_pole
	p.lead_foot = 1 if side > 0 else 0; p.crouch_amount = 0.14 if closed else 0.18
	p.body_yaw_deg = yaw; p.hip_yaw_deg = 0; p.torso_yaw_deg = 0
	return p
