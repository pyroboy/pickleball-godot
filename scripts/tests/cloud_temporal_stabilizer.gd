extends SceneTree
## Geometry-only safety and continuity checks. Never changes authoritative game state.
const Stabilizer = preload("res://scripts/ui/aim_preview_stabilizer.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);print("FAIL: ",label)

func run() -> void:
	for input in [PackedVector3Array(),PackedVector3Array([Vector3(1,2,3)]),PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]),PackedVector3Array([Vector3.ZERO,Vector3(2,3,0),Vector3(4,0,0)])]:
		var output: PackedVector3Array = Stabilizer.resample(input)
		check(output.size() == (0 if input.is_empty() else 48),"bounded output count")
		if input.is_empty():continue
		check(output[0].is_equal_approx(input[0]) and output[-1].is_equal_approx(input[-1]),"resampling preserves authoritative endpoints")
		for point in output:check(point.is_finite(),"resampling stays finite")
	var straight := Stabilizer.resample(PackedVector3Array([Vector3.ZERO,Vector3(10,0,0)]))
	for index in range(1,straight.size()):check(absf(straight[index].distance_to(straight[index-1])-10.0/47.0)<0.00001,"uniform straight-line arc length")
	var source:=PackedVector3Array([Vector3.ZERO,Vector3(0,2,2),Vector3(0,0,4)])
	var destination:=PackedVector3Array([Vector3(1,0,0),Vector3(1,2,2),Vector3(1,0,4)])
	var warning:=PackedVector3Array([Vector3(1,0,0),Vector3(1,0.2,1)])
	var source_copy:=source.duplicate();var destination_copy:=destination.duplicate()
	for rate in [30,60,120]:
		var state:=Stabilizer.new()
		var first:PackedVector3Array=state.present(source,1,"ESTIMATED ARC",0)
		check(first[0].is_equal_approx(source[0]),"first geometry appears immediately")
		var at_change:PackedVector3Array=state.present(destination,2,"ESTIMATED ARC",100000)
		check(at_change[0].is_equal_approx(source[0]),"same-risk refresh begins at displayed source")
		var last_x:=0.0
		for frame in range(1,ceili(0.1*rate)+1):
			var now:=100000+roundi(float(frame)*1000000.0/rate)
			var path:PackedVector3Array=state.present(destination,2,"ESTIMATED ARC",now)
			check(path[0].x>=last_x and path[0].x<=1.0,"bounded monotonic blend at %d Hz"%rate)
			last_x=path[0].x
		check(absf(last_x-1.0)<0.00001,"same-risk blend finishes within 100 ms plus frame")
		var unsafe:PackedVector3Array=state.present(warning,3,"NET RISK",210000)
		check(unsafe[0].is_equal_approx(warning[0]) and unsafe[-1].is_equal_approx(warning[-1]),"new warning geometry has no retained favorable path")
		state.reset()
		check(state._path_current.is_empty() and state._path_from.is_empty() and state._path_to.is_empty(),"cancel reset clears all presentation geometry")
		var fresh:PackedVector3Array=state.present(source,1,"ESTIMATED ARC",220000)
		check(fresh[-1].is_equal_approx(source[-1]),"new presentation cannot revive old warning path")
	check(source==source_copy and destination==destination_copy,"presentation never mutates authoritative input arrays")
	print("CLOUD TEMPORAL STABILIZER: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
