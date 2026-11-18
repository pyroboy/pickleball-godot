extends Node
## Editor-only snapshot/search service. Gameplay never instantiates this node.
## No scene objects enter the worker; cancelled generations never publish.
signal completed(result: Dictionary)
signal progress_changed(message: String)
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Fixture = preload("res://scripts/auto_elbow_fixture.gd")
const Preset = preload("res://scripts/initial_elbow_preset.gd")
const Sequence = preload("res://scripts/ui/mobile_pose_sequence.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
var busy := false
var generation := 0
var _thread: Thread
var _cancellation
var _capture_view
var _source_def: PostureDefinition
var _source: Dictionary = {}
var _knots: Array = []
var _fine: Array = []
var _zero: Dictionary = {}
var _accepted: Dictionary = {}
var _duration := 0.0

func cancel() -> void:
	generation += 1
	if _cancellation != null: _cancellation.cancel()

func _exit_tree() -> void:
	cancel()
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()
	_thread = null

func start(def: PostureDefinition, allow_angle: bool = true) -> void:
	if busy: return
	cancel()
	var ticket := generation
	if def == null or def.posture_id == 20 or ServeStore.is_serve(def):
		completed.emit({"valid":false,"status":"Smoothing unavailable for this static or serve context. Manual refinement remains available."})
		return
	busy = true
	var capture_began := Time.get_ticks_usec()
	_cancellation = Preset.Cancellation.new()
	# Regeneration starts from authored values. Existing accepted smoothing stays
	# visible until a replacement is explicitly applied; it is never overwritten.
	var original: PostureDefinition = def.duplicate(true)
	original.elbow_preset_bake = {}
	var seq = Sequence.new()
	seq.configure(original, Sequence.Mode.STROKE_ONLY, Sequence.Stance.AUTHORED, 0, true)
	seq.prefix_seconds=0.0;seq.preparation_seconds=0.0;seq.duration=seq.stroke_seconds
	var duration: float = seq.duration
	if _capture_view == null:
		_capture_view = Preview.new()
		_capture_view.visible = false
		add_child(_capture_view)
		await get_tree().process_frame
	var knot_times: Array[float] = Fixture.sequence_times(seq,120)
	var capture_times: Array[float] = []
	for index in range(knot_times.size()-1):
		for sub in range(4): capture_times.append(lerpf(knot_times[index],knot_times[index+1],float(sub)/4.0))
	capture_times.append(duration)
	for index in range(481): capture_times.append(duration*float(index)/480.0)
	capture_times.sort()
	var source: Dictionary = {}; var knots: Array = [[],[]]; var fine: Array = []
	for index in range(capture_times.size()):
		if ticket != generation: break
		var time: float = capture_times[index]
		var key := "%.9f" % time
		if not source.has(key):
			var pose: PostureDefinition = seq.sample(time).pose
			var pair: Array = Fixture.capture(_capture_view.player,pose,time,true)
			var p = _capture_view.player
			var root_frame := Transform3D(Basis(p._get_forehand_axis(),Vector3.UP,-p._get_forward_axis()),p.global_position)
			for frame in pair: frame.root_transform = root_frame
			source[key] = pair.duplicate(true)
		if index % 8 == 0:
			progress_changed.emit("Capturing stroke %d/%d. Original unchanged; Cancel available." % [index+1,capture_times.size()])
			await get_tree().process_frame
	if ticket != generation:
		busy = false; return
	for time in knot_times:
		for side in range(2): knots[side].append(source["%.9f" % time][side])
	for index in range(481): fine.append(source["%.9f" % (duration*float(index)/480.0)])
	var capture_elapsed_s := (Time.get_ticks_usec()-capture_began)/1000000.0
	var result: Dictionary = await _run("search",knots,source,fine,duration,{},[],allow_angle,ticket)
	var search_elapsed_s: float = float(result.get("worker_elapsed_s",0.0))
	if ticket == generation:
		if bool(result.get("valid",false)):
			var packed: Dictionary = await _candidate(original,result,source,fine,duration,ticket)
			if ticket != generation:
				busy=false;return
			if bool(packed.get("valid",false)):
				_source_def = original; _source = source; _knots = knots; _fine = fine
				_duration = duration; _zero = result.duplicate(true); _accepted = result.duplicate(true)
			result = packed
		busy = false
		result.capture_elapsed_s = capture_elapsed_s
		result.search_elapsed_s = search_elapsed_s
		completed.emit(result)
	busy = false

func request_offset(side: int, value: Vector3) -> void:
	if busy or _zero.is_empty(): return
	var wanted: Array = _accepted.get("offsets",[Vector3.ZERO,Vector3.ZERO]).duplicate()
	if side < 0 or side > 1: return
	wanted[side] = value
	_update_offsets(wanted)

func reset_offsets() -> void:
	if busy or _zero.is_empty(): return
	_update_offsets([Vector3.ZERO,Vector3.ZERO])

func _update_offsets(wanted: Array) -> void:
	cancel(); var ticket := generation
	busy = true; _cancellation = Preset.Cancellation.new()
	var result: Dictionary = await _run("offset",_knots,_source,_fine,_duration,_zero,wanted,false,ticket)
	if ticket == generation:
		if bool(result.get("valid",false)):
			var packed: Dictionary = await _candidate(_source_def,result,_source,_fine,_duration,ticket)
			if ticket != generation:
				busy=false;return
			if bool(packed.get("valid",false)): _accepted = result.duplicate(true)
			result = packed
		busy = false
		completed.emit(result)
	busy = false

func _candidate(def: PostureDefinition, result: Dictionary, source: Dictionary, fine: Array, duration: float, ticket: int) -> Dictionary:
	var packer = load("res://scripts/elbow_preset_pack.gd")
	var bake: Dictionary = packer.pack(result,source,fine,duration,def,"stroke_runtime")
	if bake.is_empty(): return {"valid":false,"status":"Route could not be serialized safely. Original retained; manual refinement needed."}
	var pose: PostureDefinition = def.duplicate(true)
	# Validate the exact JSON representation that Save/Copy will retain.
	pose.elbow_preset_bake = JSON.parse_string(JSON.stringify(bake))
	var replay = Sequence.new()
	replay.configure(pose,Sequence.Mode.STROKE_ONLY,Sequence.Stance.AUTHORED,0,true)
	replay.prefix_seconds=0.0;replay.preparation_seconds=0.0;replay.duration=replay.stroke_seconds
	for index in range(961):
		if ticket != generation: return {"valid":false,"status":"Cancelled"}
		var time: float = duration*float(index)/960.0
		var sample: PostureDefinition = replay.sample(time).pose
		Fixture.capture(_capture_view.player,sample,time,false)
		var report: Dictionary = _capture_view.player.get_meta("elbow_preset_report",{})
		if not bool(report.get("applied",false)):
			return {"valid":false,"status":"Saved-route replay did not pass at %.4f. Original retained: %s" % [time,str(report.get("status","missing runtime sample"))]}
		if index % 8 == 0:
			progress_changed.emit("Verifying saved playback %d/961 · Original unchanged" % (index+1))
			await get_tree().process_frame
	var output := result.duplicate(true)
	output.erase("bakes")
	output.pose = pose
	output.source_sha256 = Store.authored_fingerprint(def,"stroke_runtime")
	output.scope = "Runtime stroke only; authored/held/recovery contexts retain the original when mismatched"
	return output

func _run(kind: String, knots: Array, source: Dictionary, fine: Array, duration: float, zero: Dictionary, wanted: Array, angle: bool, ticket: int) -> Dictionary:
	_thread = Thread.new()
	var error := _thread.start(_compute.bind(kind,knots,source,fine,duration,zero,wanted,angle,_cancellation))
	if error != OK:
		_thread = null
		return {"valid":false,"status":"Smoothing worker unavailable; original retained"}
	var began := Time.get_ticks_usec()
	while _thread.is_alive():
		if ticket == generation:
			var stage: String = _cancellation.progress_message() if _cancellation != null and _cancellation.has_method("progress_message") else ""
			if stage.is_empty(): stage = "Searching" if kind=="search" else "Re-solving guide"
			progress_changed.emit("%s · %.1fs total · Cancel available; original unchanged" % [stage,(Time.get_ticks_usec()-began)/1000000.0])
		await get_tree().process_frame
	var result: Dictionary = _thread.wait_to_finish()
	result.worker_elapsed_s = (Time.get_ticks_usec()-began)/1000000.0
	_thread = null
	return result

static func _compute(kind: String, knots: Array, source: Dictionary, fine: Array, duration: float, zero: Dictionary, wanted: Array, angle: bool, token) -> Dictionary:
	if kind == "offset": return Preset.offset(knots,source,fine,duration,zero,wanted,token)
	return Preset.search(knots,source,fine,duration,angle,token)
