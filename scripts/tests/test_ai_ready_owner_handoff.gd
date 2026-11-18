extends SceneTree


const Body = preload("res://scripts/stroke_body_pose.gd")
var game
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
var launches: = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func pose_id(pose) -> int: return pose.posture_id if pose else -1
func sample(label: String) -> Dictionary:
	var p = game.player_right
	var ai = p.ai_brain
	return {"label": label, "physics_frame": Engine.get_physics_frames(), "flight": game.ball.flight_id, "observed_flight": ai._observed_flight_id, "in_play": game.ball.is_in_play, "last_hitter": game.ball.last_hit_by, "guard": p._ai_guard_active, "incoming": pose_id(ai.incoming_pose_override), "transition": pose_id(p.posture.transition_pose_blend), "reachable": ai.ai_selected_contact_reachable, "base_state": p.pose_controller.base_pose_state, "left_offset": p.posture.transition_pose_blend.left_hand_offset if p.posture.transition_pose_blend else Vector3.INF}
func on_launch(team: int) -> void :
	if team != 0: return
	launches += 1
	var p = game.player_right
	var before: Dictionary = sample("actual launch before presentation")
	rows.append(before)


	p._process(0.0)
	rows.append(sample("actual launch first presentation"))
	check(p.posture.transition_pose_blend != null, "actual launch dropped complete receiver pose before incoming ownership")
	if before.incoming < 0:
		check(p._ai_guard_active, "actual launch released guard with no incoming owner")
		check(p.posture.transition_pose_blend != null and p.posture.transition_pose_blend.posture_id == 20, "launch gap did not retain Ready")
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await process_frame
	game.game_serve.serve_launched.connect(on_launch)
	Input.action_press("ui_accept")
	for frame in 18: await physics_frame
	Input.action_release("ui_accept")
	for frame in 180:
		await physics_frame
		if launches > 0 and game.player_right.ai_brain.incoming_pose_override != null: break
	check(launches == 1, "normal held/released input did not launch one actual serve")
	check(game.player_right.ai_brain.incoming_pose_override != null, "incoming brain did not acquire pose after actual launch")
	rows.append(sample("actual next incoming owner"))
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var p = game.player_right
	var ai = p.ai_brain
	game.game_serve.cleanup();p.hitting.clear_charge_visual();p.hitting.is_in_follow_through = false;p.hitting.serving_visual_active = false


	var ready = PostureLibrary.instance().get_def(20).duplicate(true)
	p.posture.transition_pose_blend = ready;p.posture.force_posture_update(ready)
	p._ai_guard_active = true;p._ai_incoming_active = true;ai.incoming_pose_override = null;ai.ai_selected_contact_reachable = false
	ai._observed_flight_id = game.ball.flight_id
	game.ball.is_in_play = true;game.ball.last_hit_by = 0
	p.pose_controller.base_pose_state = 12
	p._process(0.0)
	check(p.posture.transition_pose_blend == ready and p._ai_guard_active, "same-flight activation loses displayed guard")
	check(p.posture.transition_pose_blend != null and p.posture.transition_pose_blend.left_hand_offset.is_equal_approx(ready.left_hand_offset), "same-flight guard diluted with lunge base")
	rows.append(sample("same-flight ownership gap"))
	ai.incoming_pose_override = PostureLibrary.instance().get_def(0).duplicate(true)
	p._process(0.0)
	check( not p._ai_guard_active and p.posture.transition_pose_blend == ai.incoming_pose_override, "legitimate incoming owner failed handoff")

	var editor_pose = PostureLibrary.instance().get_def(2).duplicate(true)
	ai.incoming_pose_override = null;p._ai_guard_active = true;p._ai_incoming_active = false
	p.posture.editor_preview_mode = true;p.posture.transition_pose_blend = editor_pose
	p._process(0.0)
	check(p.posture.transition_pose_blend == editor_pose, "guard cleanup cleared explicit editor owner")
	p.posture.editor_preview_mode = false
	var file = FileAccess.open("/tmp/ai-ready-owner-handoff.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));file.close()
	Input.action_release("ui_accept");game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	for failure in failures: push_error(failure)
	print("AI READY OWNER HANDOFF: %d checks, %d failures; actual launches=%d" % [checks, failures.size(), launches])
	quit(0 if failures.is_empty() else 1)
