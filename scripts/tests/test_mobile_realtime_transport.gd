extends SceneTree
const Store = preload("res://scripts/mobile_pose_store.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
var checks:=0
var failures:Array[String]=[]
var editor
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(n:int=3)->void:
	for i in range(n):await process_frame
func run()->void:
	create_timer(90,true).timeout.connect(func():quit(2))
	Store.set_test_path("user://realtime-transport/poses.json");Serve.set_test_path("user://realtime-transport/serves.json")
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(4)
	var pause=root.get_node("PauseController");pause.open();game.open_mobile_pose_editor();await frames(4);editor=game.mobile_pose_editor
	editor.set_process(false);pause._focus_paused=false
	var scale:float=Engine.time_scale
	var source:String=Store.export_pose_json(editor._current)
	editor._toggle_play();check(editor._timeline.active and editor._playing,"Play activates real time")
	var d:float=editor._timeline.sequence.duration
	editor._timeline.advance(d*.3);editor._refresh_preview();var t:float=editor._timeline.elapsed
	editor._toggle_play();check(not editor._playing and editor._resume_playback,"pause is resumable")
	editor._toggle_play();check(editor._playing and is_equal_approx(editor._timeline.elapsed,t),"resume same elapsed")
	for variant in [1,2]:
		editor._play_variant(variant);check(editor._timeline.sequence.variant_mode==variant,"variant sampler selected")
		editor._timeline.advance(.03);t=editor._timeline.elapsed
		editor._play_variant(variant);check(not editor._playing,"variant pause")
		editor._play_variant(variant);check(is_equal_approx(editor._timeline.elapsed,t),"variant resume")
		editor._timeline.advance(10);editor._stop();editor._play_variant(variant);check(is_zero_approx(editor._timeline.elapsed),"end restarts")
	editor._timeline._seek(.73);var pose=editor._preview.pose
	editor._timeline._seek(.11);editor._timeline._seek(.73)
	check(is_equal_approx(pose.paddle_forehand_mul,editor._preview.pose.paddle_forehand_mul),"reverse seek exact")
	check(not editor._playing and editor._resume_playback,"seek pauses, permits resume")
	editor._timeline._jump_phase(2);editor._sync_selected_gizmo()
	check(not editor._preview.gizmo.enabled,"context Contact never edits selected key")
	editor._last_tick=Time.get_ticks_usec()-9000000;root.focus_entered.emit()
	check(Time.get_ticks_usec()-editor._last_tick<100000,"focus return discards inactive wall gap")
	editor._select_stage(1);check(not editor._timeline.active,"key selection leaves context")
	editor._timeline._stance.select(2);editor._timeline._options_changed(2)
	check(Store.export_pose_json(editor._current)==source,"stance stays private")
	editor._scrubbed(.25);check(not editor._timeline.active,"authored scrub leaves context")
	editor._toggle_play();editor._dialog.show();t=editor._timeline.elapsed;editor._last_tick=Time.get_ticks_usec()-100000;editor._process(.1)
	check(is_equal_approx(t,editor._timeline.elapsed),"modal suspends clock")
	editor._dialog.hide();pause._focus_paused=true;editor._last_tick=Time.get_ticks_usec()-100000;editor._process(.1)
	check(is_equal_approx(t,editor._timeline.elapsed),"focus suspends clock")
	pause._focus_paused=false;editor._timeline._speed.select(0);editor._timeline.speed=1
	editor._last_tick=Time.get_ticks_usec()-100000;editor._process(.001)
	check(absf(editor._timeline.elapsed-t-.1)<.015,"unscaled wall clock ignores engine delta and old 50ms cap")
	check(Engine.time_scale==scale,"transport never changes global time scale")
	editor._timeline._mode.select(2);editor._timeline._options_changed(2);editor._timeline._seek(.03)
	check(not editor._timeline.sample.split.is_empty(),"receive context reaches split adapter")
	editor._select_stage(1);check(not editor._timeline.active,"split reset via key")
	editor.close();await frames(2)
	print(JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
