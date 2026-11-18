extends SceneTree
const Dive = preload("res://scripts/prototype/dive_save_controller.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
var checks := 0
var failures: Array[String] = []
func ck(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	var state := {"playing": true,"paused": false,"in_play": true,"last_hit_by":1,"player_num":0,"bounces":1,"jumping":false,"flight_id":42}
	var origin := Vector3(0,1,4)
	var samples := [{"time":0.42,"pos":Vector3(1.09,0.45,4),"bounces":0}]
	var candidate := Dive.choose_plan(origin,state,samples,Rect2(-3,2,6,5))
	ck(not candidate.is_empty(),"groundstroke forecast")
	for hz in [30,60,120]:
		var dive = Dive.new()
		ck(not dive.begin(candidate,state),"disabled default")
		dive.enabled=true;ck(dive.begin(candidate,state),"explicit activation")
		ck(not dive.begin(candidate,state),"repeat blocked")
		for i in range(roundi(0.4*hz)):dive.advance(1.0/hz,state)
		var paddle := Transform3D.IDENTITY
		var head: Vector3 = paddle*D.HEAD_OFFSET
		ck(dive.contact_fraction(head+Vector3(2,0,0),head+Vector3(2,0,0),paddle,paddle,state)<0,"miss stays miss")
		ck(dive.contact_fraction(head-Vector3(0,0,0.2),head+Vector3(0,0,0.2),paddle,paddle,state)>=0,"real finite swept paddle contact")
		ck(dive.contact_fraction(head,head,paddle,paddle,state)<0,"one contact only")
		var outgoing=state.duplicate();outgoing.last_hit_by=0;outgoing.flight_id=43
		dive.advance(0.01,outgoing);ck(dive.active,"successful outgoing hit retains recovery")
		for i in range(2*hz):dive.advance(1.0/hz,state)
		ck(not dive.active,"recovery completes")
		ck(not dive.begin(candidate,state),"cooldown blocks immediate replay")
		dive.advance(0.2,state);ck(dive.begin(candidate,state),"cooldown expires")
		var invalid=state.duplicate();invalid.bounces=2;dive.advance(0,invalid);ck(not dive.active,"second bounce invalidates immediately")
		dive.reset();ck(dive.cooldown==0 and not dive.active,"reset clears")
	for key in ["playing","in_play"]:
		var bad=state.duplicate();bad[key]=false;ck(not Dive.eligible(bad),key)
	for key in ["paused","jumping"]:
		var bad=state.duplicate();bad[key]=true;ck(not Dive.eligible(bad),key)
	for bounce in [0,2,3]:
		var bad=state.duplicate();bad.bounces=bounce;ck(not Dive.eligible(bad),"no volley or second-bounce save")
	var bad=state.duplicate();bad.last_hit_by=0;ck(not Dive.eligible(bad),"outgoing")
	ck(Dive.choose_plan(origin,state,[{"time":0.1,"pos":Vector3(1.09,.45,4),"bounces":0}],Rect2(-3,2,6,5)).is_empty(),"too late")
	ck(Dive.choose_plan(origin,state,[{"time":0.42,"pos":Vector3(4,.45,4),"bounces":0}],Rect2(-3,2,6,5)).is_empty(),"bounded travel")
	var gate = Dive.new();gate.enabled=true;gate.begin(candidate,state)
	var paddle := Transform3D.IDENTITY
	var head:Vector3=paddle*D.HEAD_OFFSET
	gate.elapsed=.40
	ck(gate.contact_fraction(head-Vector3(0,0,.2),head+Vector3(0,0,.2),paddle,paddle,state,.0375,.1)<0,"pre-window sweep contact rejected")
	gate.elapsed=.60
	ck(gate.contact_fraction(head-Vector3(0,0,.36),head+Vector3(0,0,.04),paddle,paddle,state,.0375,.1)<0,"post-window sweep contact rejected")
	gate.elapsed=.45
	ck(gate.contact_fraction(head-Vector3(0,0,.2),head+Vector3(0,0,.2),paddle,paddle,state,.0375,.1)>=0,"clipped in-window sweep accepted")
	print("DIVE PROTOTYPE TESTS ","PASS" if failures.is_empty() else "FAIL"," ",checks," checks, 30/60/120 Hz; not match integration")
	quit(0 if failures.is_empty() else 1)
