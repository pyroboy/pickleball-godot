extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")








const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")

var _menu: Node = null
var _manual_paused: bool = false
var _focus_paused: bool = false
var _previous_max_fps: int = 0
var _last_back_source: = ""
var _last_back_msec: = -1000
var _overlay_pauses: Dictionary = {}
var _entry_gate: WeakRef

func entry_gate() -> Node:
	return _entry_gate.get_ref() if _entry_gate != null else null

func register_entry_gate(owner: Node) -> bool:
	if is_instance_valid(entry_gate()): return false
	_entry_gate = weakref(owner)
	hold_overlay(owner)
	return true

func unregister_entry_gate(owner: Node) -> void:
	if entry_gate() == owner: _entry_gate = null

func entry_has_blocking_pause(owner: Node) -> bool:
	if _focus_paused or contact_reset_required(): return true
	for id in _overlay_pauses:
		if int(id) != owner.get_instance_id(): return true
	return false

func defer_entry_practice(game: Node, panel: Node) -> bool:
	var owner = entry_gate()
	return is_instance_valid(owner) and owner.defer_practice(game, panel)

func show_entry_pause_if_needed() -> void:
	if _manual_paused: _show_pause_menu()


func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().quit_on_go_back = false
	var window: = get_window()
	if window:
		window.focus_entered.connect(_on_window_focus_entered)
		window.focus_exited.connect(_on_window_focus_exited)

func _set_pause_state() -> void :
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _manual_paused or _focus_paused or not _overlay_pauses.is_empty() or contact_reset_required()
		# Paused by the menu or by leaving the app: stop drawing and ticking (settings.gd). Pose
		# editors and other tool overlays pause the match too, but stay live to work in.
		var settings: Node = tree.root.get_node_or_null("Settings")
		if settings != null and settings.has_method("set_pause_idle"):
			settings.set_pause_idle(tree.paused and (_manual_paused or _focus_paused) and _overlay_pauses.is_empty())

func hold_overlay(owner: Node) -> void:
	_overlay_pauses[owner.get_instance_id()] = weakref(owner)
	_set_pause_state()

func release_overlay(owner: Node) -> void:
	_overlay_pauses.erase(owner.get_instance_id())
	_set_pause_state()

func contact_reset_required() -> bool:
	var scene = get_tree().current_scene if get_tree() else null
	if scene == null or not "contact_authority" in scene or scene.contact_authority == null: return false
	return not scene.contact_authority.unresolved_continuation.is_empty()

func _show_pause_menu() -> void :
	if is_instance_valid(entry_gate()): return
	if _menu != null and is_instance_valid(_menu):
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	if tree.current_scene.scene_file_path == "res://scenes/title.tscn":
		return
	_menu = PauseMenuScript.new()
	_menu.set_meta("controller", self)
	tree.current_scene.add_child(_menu)
	if TimeScale != null and TimeScale.has_method("force_normal"):
		TimeScale.force_normal()

func _hide_pause_menu() -> void :
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	if TimeScale != null and TimeScale.has_method("release_forced_normal"):
		TimeScale.release_forced_normal()

func _on_window_focus_exited() -> void :
	if _focus_paused or RuntimePolicy.autoplay: return   # benchmarks/captures run unfocused
	_cancel_scene_input()
	_previous_max_fps = Engine.max_fps
	Engine.max_fps = 5
	_focus_paused = true
	_set_pause_state()
	var scene = get_tree().current_scene
	if _overlay_pauses.is_empty() and (scene == null or not scene.has_method("_tool_state_active") or not scene._tool_state_active()):
		_show_pause_menu()
	if RuntimePolicy.developer_tools: print("[PauseController] window focus lost — throttling to 5 FPS")

func _on_window_focus_entered() -> void :
	if not _focus_paused: return
	Engine.max_fps = _previous_max_fps
	_focus_paused = false
	_set_pause_state()
	if not _manual_paused:
		_hide_pause_menu()
	if RuntimePolicy.developer_tools: print("[PauseController] window focus regained — restoring FPS")

func _unhandled_input(event: InputEvent) -> void :
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_dispatch_back("keyboard")
		get_viewport().set_input_as_handled()

func _dispatch_back(source: String) -> void :


	var now: = Time.get_ticks_msec()
	if source != _last_back_source and now - _last_back_msec < 150: return
	_last_back_source = source
	_last_back_msec = now
	if not _handle_back_request(): get_tree().quit()

func _handle_back_request() -> bool:
	var entry = entry_gate()
	if is_instance_valid(entry):
		entry.request_cancel("back")
		return true
	var tree: = get_tree()
	if tree == null or tree.current_scene == null: return true
	var scene: = tree.current_scene
	_cancel_scene_input()
	if is_instance_valid(_menu) and _menu.close_settings(): return true
	var picker = scene.get("practice_panel") if scene.has_method("_tool_state_active") else null
	if is_instance_valid(picker) and picker._picker_open:
		picker.close_picker()
		return true
	if scene.has_method("close_active_tool") and scene.close_active_tool(): return true
	if scene.scene_file_path == "res://scenes/title.tscn":
		var overlay = scene.get("_overlay")
		if is_instance_valid(overlay): overlay._on_close();return true
		var hint = scene.get("_hint")
		if is_instance_valid(hint) and hint.text.begins_with("MOVE"):
			scene._toggle_controls()
			return true
		if scene.has_method("request_loading_back") and scene.request_loading_back():return true
		return false
	toggle()
	return true

func _cancel_scene_input() -> void :
	if is_instance_valid(entry_gate()): return
	var scene = get_tree().current_scene if get_tree() != null else null
	if scene == null or not scene.has_method("_tool_state_active"): return
	if scene.has_method("cancel_aim_focus"): scene.cancel_aim_focus()
	var mobile = scene.get("mobile_controls")
	if is_instance_valid(mobile): mobile.cancel_all()
	var input = scene.get("input_handler")
	var human = scene.player_left.posture.human_contact if scene.get("player_left") else null
	var committed: bool = int(scene.get("game_state")) == 1 or human != null and human.phase >= 0
	if is_instance_valid(input) and not committed: input.cancel_charge_input()

func _notification(what: int) -> void :
	if not is_inside_tree(): return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_dispatch_back("native")
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_on_window_focus_exited()
		var scene = get_tree().current_scene
		if scene != null and scene.has_method("_tool_state_active"):
			_manual_paused = true
			_set_pause_state()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_on_window_focus_entered()

func toggle() -> void :
	if _menu != null and is_instance_valid(_menu):
		close()
	else:
		open()

func open() -> void :
	_cancel_scene_input()
	_manual_paused = true
	_set_pause_state()
	_show_pause_menu()
	if RuntimePolicy.developer_tools: print("[PauseController] opened")

## Leave the court for the title screen from the pause menu. Clears every pause reason this
## controller owns first, so the title (and the next match) never start paused.
func return_to_title() -> void :
	var tree: = get_tree()
	if tree == null: return
	_cancel_scene_input()
	_manual_paused = false
	_overlay_pauses.clear()
	_hide_pause_menu()
	for key in ["open_practice", "local_doubles"]:
		if tree.has_meta(key): tree.remove_meta(key)
	tree.paused = false
	Engine.time_scale = 1.0
	tree.change_scene_to_file("res://scenes/title.tscn")
	if RuntimePolicy.developer_tools: print("[PauseController] returned to title")

func close() -> void :
	if contact_reset_required():
		_manual_paused = true
		_set_pause_state()
		_show_pause_menu()
		return
	_manual_paused = false
	_set_pause_state()
	_hide_pause_menu()
	if _focus_paused:
		_show_pause_menu()
	if RuntimePolicy.developer_tools: print("[PauseController] closed")
