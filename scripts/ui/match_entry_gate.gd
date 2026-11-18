extends CanvasLayer
## Isolated candidate: the normal, single Game's initial draw stays behind loading.
## Does not instantiate a second scene, advance gameplay, or synthesize input.
signal completed(report: Dictionary)
signal setup_completed(report: Dictionary)

const SETUP_TIMEOUT_USEC := 5000000

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const GAME_PATH := "res://scenes/game.tscn"
const DRAW_FIELDS := ["msaa_3d", "msaa_2d", "screen_space_aa", "use_taa", "use_debanding", "scaling_3d_mode", "scaling_3d_scale", "use_hdr_2d"]
var phase := "created"
var report: Dictionary = {}
var _pause: Node
var _game_ref: WeakRef
var _practice_ref: WeakRef
var _modes: Dictionary = {}
var _pending_nodes: Array[WeakRef] = []
var _label: Label
var _armed := false
var _cancel_requested := false
var _cleanup_started := false
var _scene_requested := false
var _scene_arrived := false
var _ready_seen := false
var _post_draws := 0
var _valid_draws := 0
var _draw_key: Array = []
var _draw_started_usec := 0
var _ready_draw_key: Array = []
var _started_usec := 0
var _setup_started_usec := 0
var _setup_done := false
var _setup_actors: Dictionary = {}
var _setup_actor_ids: Array = []
var _serve_cache_prepared := false

func _ready() -> void:
 name = "MatchEntryGate"
 layer = 120
 process_mode = Node.PROCESS_MODE_ALWAYS
 var background := ColorRect.new()
 background.color = Color("102b36")
 background.mouse_filter = Control.MOUSE_FILTER_STOP
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(background)
 _label = Label.new()
 _label.theme = UiTheme.create()
 _label.text = "Preparing the court…"
 _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 _label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 background.add_child(_label)

func arm() -> bool:
 _pause = get_node("/root/PauseController")
 if not _pause.register_entry_gate(self): return false
 _armed = true
 _started_usec = Time.get_ticks_usec()
 report = {"status":"pending", "game_count":0, "ready_count":0, "scene_changed_count":0, "valid_draws":[], "mode_rewrites":0, "practice_deferred":0, "practice_opened":0, "quit_calls":0}
 var tree := get_tree()
 tree.node_added.connect(_node_added)
 tree.scene_changed.connect(_scene_changed)
 tree.process_frame.connect(_before_process)
 tree.physics_frame.connect(_before_physics)
 RenderingServer.frame_pre_draw.connect(_pre_draw)
 RenderingServer.frame_post_draw.connect(_post_draw)
 phase = "loading_draw"
 return true

func show_loading() -> bool:
 var previous := _post_draws
 while _post_draws == previous and not _cancel_requested:
  await get_tree().process_frame
 return not _cancel_requested

func change_scene(packed: PackedScene) -> int:
 if _cancel_requested or not _armed: return ERR_BUSY
 phase = "scene_pending"
 _scene_requested = true
 var error := get_tree().change_scene_to_packed(packed)
 if error != OK: _scene_requested = false
 return error

func abort_before_scene() -> void:
 if _scene_requested: return
 _disconnect()
 _pause.unregister_entry_gate(self)
 _pause.release_overlay(self)
 _armed = false
 queue_free()

func game() -> Node:
 return _game_ref.get_ref() if _game_ref != null else null

func claims_game(value: Node) -> bool:
 return _armed and not _cancel_requested and game() == value

func defer_practice(value: Node, panel: Node) -> bool:
 # A cancellation still owns the scene's intent and must consume/discard it.
 if not _armed or game() != value: return false
 if _practice_ref == null and not _cancel_requested:
  _practice_ref = weakref(panel)
  report.practice_deferred += 1
 return true

func _node_added(node: Node) -> void:
 if node.scene_file_path == GAME_PATH:
  report.game_count += 1
  if _game_ref != null:
   request_cancel("duplicate_game")
   return
  _game_ref = weakref(node)
  node.ready.connect(_game_ready, CONNECT_ONE_SHOT)
  report.game_added_usec = Time.get_ticks_usec()
  return
 var actual := game()
 if is_instance_valid(actual) and actual.is_ancestor_of(node):
  _pending_nodes.append(weakref(node))
  if _ready_seen: _valid_draws = 0

func _game_ready() -> void:
 var actual := game()
 if not is_instance_valid(actual): return
 _ready_seen = true
 report.ready_count += 1
 report.game_ready_usec = Time.get_ticks_usec()
 report.game_id = actual.get_instance_id()
 _capture_tree(actual)
 _pending_nodes.clear()
 _setup_started_usec = Time.get_ticks_usec()
 _bind_setup_actors(actual)
 phase = "game_ready"

func _scene_changed() -> void:
 if not _scene_requested: return
 _scene_arrived = true # The engine transition is terminal even if its identity is wrong.
 var actual := game()
 if not is_instance_valid(actual) or get_tree().current_scene != actual or not actual.is_node_ready():
  request_cancel("unexpected_scene")
  return
 report.scene_changed_count += 1
 _capture_tree(actual)
 _pending_nodes.clear()
 _keep_input_first()
 phase = "waiting_setup"
 _maybe_complete_setup()
 if _cancel_requested: call_deferred("_cancel_cleanup")

func _bind_setup_actors(actual: Node) -> void:
 var roster: Array = actual.get_players()
 if roster.size() not in [2, 4]:
  request_cancel("unexpected_setup_roster")
  return
 for actor in roster:
  if not is_instance_valid(actor) or not actual.is_ancestor_of(actor) or not actor.has_signal("initial_paddle_setup_completed") or not "initial_paddle_setup_complete" in actor:
   request_cancel("missing_actor_setup_contract")
   return
  var id: int = actor.get_instance_id()
  if _setup_actors.has(id):
   request_cancel("duplicate_setup_actor")
   return
  var done_callback: Callable = _actor_setup_completed.bind(id)
  var exit_callback: Callable = _actor_setup_exiting.bind(id)
  _setup_actor_ids.append(id)
  _setup_actors[id] = {"node":weakref(actor), "done_callback":done_callback, "exit_callback":exit_callback}
  if not bool(actor.initial_paddle_setup_complete): actor.initial_paddle_setup_completed.connect(done_callback, CONNECT_ONE_SHOT)
  actor.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
 report.setup_actor_count = _setup_actors.size()
 report.setup_actor_ids = _setup_actor_ids.duplicate()

func _actor_setup_completed(id: int) -> void:
 if not _armed or _cancel_requested or not _setup_actors.has(id): return
 _maybe_complete_setup()

func _actor_setup_exiting(_id: int) -> void:
 if _armed and not _cancel_requested: request_cancel("setup_actor_removed")

func _setup_roster_valid() -> bool:
 var actual := game()
 if not is_instance_valid(actual) or _setup_actors.size() not in [2, 4]: return false
 var live_ids: Array = []
 for actor in actual.get_players():
  if not is_instance_valid(actor) or not actual.is_ancestor_of(actor): return false
  live_ids.append(actor.get_instance_id())
 if live_ids != _setup_actor_ids: return false
 for record in _setup_actors.values():
  var actor = record.node.get_ref()
  if not is_instance_valid(actor): return false
 return true

func _check_setup_progress() -> void:
 if not _ready_seen or _cancel_requested: return
 if not _setup_roster_valid():
  request_cancel("setup_roster_changed")
  return
 if not _setup_done and Time.get_ticks_usec() - _setup_started_usec > SETUP_TIMEOUT_USEC:
  request_cancel("actor_setup_timeout")
  return
 _maybe_complete_setup()

func _maybe_complete_setup() -> void:
 if _setup_done or not _scene_arrived or _cancel_requested or not _ready_seen: return
 if Time.get_ticks_usec() - _setup_started_usec > SETUP_TIMEOUT_USEC:
  request_cancel("actor_setup_timeout")
  return
 if not _setup_roster_valid():
  request_cancel("setup_roster_changed")
  return
 for record in _setup_actors.values():
  var actor = record.node.get_ref()
  if not bool(actor.initial_paddle_setup_complete): return
 if not _prepare_serve_cache(): return
 _capture_tree(game())
 _pending_nodes.clear()
 _setup_done = true
 _valid_draws = 0
 _ready_draw_key = []
 phase = "waiting_draw"
 report.setup_completed_usec = Time.get_ticks_usec()
 report.setup_completed_process_frame = Engine.get_process_frames()
 report.setup_completed_physics_frame = Engine.get_physics_frames()
 setup_completed.emit(report.duplicate(true))

func _prepare_serve_cache() -> bool:
 # Synchronous canonical data work only, with the actual scene still quarantined.
 if _serve_cache_prepared: return true
 if not _armed or _cancel_requested: return false
 var actual := game()
 if not is_instance_valid(actual) or actual.is_queued_for_deletion() or get_tree().current_scene != actual or not _setup_roster_valid():
  request_cancel("serve_cache_owner_changed")
  return false
 var serve = actual.get("game_serve")
 # Direct-Game/component fixtures need no gate helper contract. Exact title-entry
 # qualification separately requires a prepared receipt for the full candidate.
 if not is_instance_valid(serve) or not serve.has_method("prewarm_held_serve_curve"):
  report.serve_cache = {"status":"not_available"}
  _serve_cache_prepared = true
  return true
 var owner_id: int = serve.get_instance_id()
 var motion_id: int = serve._held_visual_motion.get_instance_id()
 var before: int = Time.get_ticks_usec()
 var prepared: bool = serve.prewarm_held_serve_curve()
 report.serve_cache = {"status":"prepared" if prepared else "failed", "begin_usec":before, "end_usec":Time.get_ticks_usec(), "game_id":actual.get_instance_id(), "owner_id":owner_id, "motion_id":motion_id, "style":serve.selected_serve_style, "revision":serve._held_visual_revision}
 if _cancel_requested or not _armed: return false
 if not prepared or not is_instance_valid(game()) or game() != actual or get_tree().current_scene != actual or actual.is_queued_for_deletion() or not _setup_roster_valid() or actual.get("game_serve") != serve or serve.get_instance_id() != owner_id or serve._held_visual_motion.get_instance_id() != motion_id:
  request_cancel("serve_cache_owner_changed")
  return false
 if Time.get_ticks_usec() - _setup_started_usec > SETUP_TIMEOUT_USEC:
  request_cancel("actor_setup_timeout")
  return false
 _serve_cache_prepared = true
 return true

func _disconnect_setup_actors() -> void:
 for record in _setup_actors.values():
  var actor = record.node.get_ref()
  if not is_instance_valid(actor): continue
  if actor.initial_paddle_setup_completed.is_connected(record.done_callback): actor.initial_paddle_setup_completed.disconnect(record.done_callback)
  if actor.tree_exiting.is_connected(record.exit_callback): actor.tree_exiting.disconnect(record.exit_callback)
 _setup_actors.clear()
 _setup_actor_ids.clear()

func _capture_tree(node: Node) -> void:
 # Game.ready is after synchronous child setup, not merely child.ready.
 _capture_mode(node)
 for child in node.get_children(): _capture_tree(child)

func _capture_mode(node: Node) -> void:
 var id := node.get_instance_id()
 if not _modes.has(id):
  _modes[id] = {"node":weakref(node), "mode":node.process_mode, "path":str(node.get_path())}
 elif node.process_mode != Node.PROCESS_MODE_DISABLED:
  # Authored setup after an earlier enrollment gets its final requested mode.
  _modes[id].mode = node.process_mode
  report.mode_rewrites += 1
 node.process_mode = Node.PROCESS_MODE_DISABLED

func _refresh_quarantine() -> void:
 if not _ready_seen or not is_instance_valid(game()): return
 var pending := _pending_nodes
 _pending_nodes = []
 for weak in pending:
  var node = weak.get_ref()
  if is_instance_valid(node) and game().is_ancestor_of(node): _capture_tree(node)
 for record in _modes.values():
  var node = record.node.get_ref()
  if is_instance_valid(node) and node.process_mode != Node.PROCESS_MODE_DISABLED:
   _valid_draws = 0
   _capture_mode(node)

func _keep_input_first() -> void:
 var host := get_parent()
 if host != null and get_index() != host.get_child_count() - 1:
  host.move_child(self, host.get_child_count() - 1)

func _before_process() -> void:
 if not _armed: return
 _refresh_quarantine()
 _check_setup_progress()
 if _scene_arrived: _keep_input_first()
 if _cancel_requested: return
 if _valid_draws >= 2:
  if _pause.entry_has_blocking_pause(self): _label.text = "Paused. Return to continue loading."
  elif Input.is_action_pressed("ui_accept"): _label.text = "Release HIT / Space to enter the court."
  else: _label.text = "Opening the court…"

func _before_physics() -> void:
 if not _armed: return
 _refresh_quarantine()
 _check_setup_progress()
 if _cancel_requested or not _setup_done or not _scene_arrived or _valid_draws < 2: return
 if _pause.entry_has_blocking_pause(self) or Input.is_action_pressed("ui_accept"): return
 if _current_draw_key() != _ready_draw_key:
  _valid_draws = 0
  return
 _release()

func _current_draw_key() -> Array:
 var actual := game()
 if not is_instance_valid(actual) or not _scene_arrived or get_tree().current_scene != actual: return []
 var viewport := get_viewport()
 var camera := viewport.get_camera_3d()
 if camera == null or camera != actual.main_camera: return []
 var settings := get_node("/root/Settings")
 var key: Array = [actual.get_instance_id(), Vector2i(viewport.get_visible_rect().size), camera.get_instance_id(), camera.global_transform, camera.fov, int(settings.get_value("video.shadow_quality",1))]
 for field in DRAW_FIELDS: key.append(viewport.get(field))
 return key

func _pre_draw() -> void:
 if not _armed or _cancel_requested or not _scene_arrived: return
 _refresh_quarantine()
 _check_setup_progress()
 if _cancel_requested or not _setup_done: return
 _draw_key = _current_draw_key()
 _draw_started_usec = Time.get_ticks_usec()

func _post_draw() -> void:
 _post_draws += 1
 if not _armed or _cancel_requested or _draw_key.is_empty(): return
 if _draw_key == _current_draw_key():
  if _draw_key != _ready_draw_key: _valid_draws = 0
  _ready_draw_key = _draw_key.duplicate()
  _valid_draws += 1
  report.valid_draws.append({"frame":Engine.get_process_frames(), "elapsed_usec":Time.get_ticks_usec()-_draw_started_usec, "extent":_draw_key[1]})
 else: _valid_draws = 0
 _draw_key = []

func _input(event: InputEvent) -> void:
 if not _armed: return
 if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
  _pause._dispatch_back("keyboard")
 get_viewport().set_input_as_handled()

func request_cancel(reason: String = "back") -> void:
 if _cancel_requested or not _armed: return
 _cancel_requested = true
 report.cancel_reason = reason
 report.cancel_usec = Time.get_ticks_usec()
 _label.text = "Closing…"
 call_deferred("_cancel_cleanup")

func _release() -> void:
 # One atomic pre-physics handoff, with the loading pause still held.
 phase = "handoff"
 var records: Array = _modes.values()
 records.reverse()
 for record in records:
  var node = record.node.get_ref()
  if is_instance_valid(node): node.process_mode = int(record.mode)
 var mismatch: Array = []
 for record in records:
  var node = record.node.get_ref()
  if is_instance_valid(node) and node.process_mode != int(record.mode): mismatch.append(record.path)
 report.restored_mode_count = records.size()
 report.mode_mismatches = mismatch
 if not mismatch.is_empty():
  _capture_tree(game())
  request_cancel("mode_restore_mismatch")
  return
 _disconnect()
 _pause.unregister_entry_gate(self)
 var panel: Node = _practice_ref.get_ref() if _practice_ref != null else null
 _practice_ref = null
 if is_instance_valid(panel):
  report.practice_opened += 1
  panel.open_practice()
 _pause.show_entry_pause_if_needed()
 visible = false
 _armed = false
 _pause.release_overlay(self)
 phase = "released"
 report.status = "released"
 report.release_physics_frame = Engine.get_physics_frames()
 report.elapsed_usec = Time.get_ticks_usec()-_started_usec
 report.paused_at_release = get_tree().paused
 completed.emit(report.duplicate(true))
 queue_free()

func _cancel_cleanup() -> void:
 if _cleanup_started or not _cancel_requested: return
 _cleanup_started = true
 phase = "cancel_wait_scene"
 while _scene_requested and not _scene_arrived:
  await get_tree().process_frame
 var actual := game()
 _practice_ref = null
 phase = "cleanup_game"
 # Queue-free is not immediate. Keep the existing root input/physics owner
 # alive until this actual subtree is gone, including later deferred children.
 # Cancel never restores process modes into a scene scheduled for deletion.
 _refresh_quarantine()
 var weak: WeakRef = weakref(actual) if is_instance_valid(actual) else null
 if is_instance_valid(actual): actual.queue_free()
 actual = null
 while weak != null and is_instance_valid(weak.get_ref()):
  _refresh_quarantine()
  await get_tree().process_frame
 _disconnect()
 _game_ref = null
 _modes.clear()
 _pending_nodes.clear()
 for index in 2: await get_tree().process_frame
 _pause.unregister_entry_gate(self)
 _pause.release_overlay(self)
 _armed = false
 report.status = "cancelled"
 report.cancel_to_exit_usec = Time.get_ticks_usec()-int(report.cancel_usec)
 report.quit_calls += 1
 report.game_remaining = weak != null and is_instance_valid(weak.get_ref())
 phase = "quit"
 completed.emit(report.duplicate(true))
 get_tree().quit()

func _disconnect() -> void:
 _disconnect_setup_actors()
 var tree := get_tree()
 if tree.node_added.is_connected(_node_added): tree.node_added.disconnect(_node_added)
 if tree.scene_changed.is_connected(_scene_changed): tree.scene_changed.disconnect(_scene_changed)
 if tree.process_frame.is_connected(_before_process): tree.process_frame.disconnect(_before_process)
 if tree.physics_frame.is_connected(_before_physics): tree.physics_frame.disconnect(_before_physics)
 if RenderingServer.frame_pre_draw.is_connected(_pre_draw): RenderingServer.frame_pre_draw.disconnect(_pre_draw)
 if RenderingServer.frame_post_draw.is_connected(_post_draw): RenderingServer.frame_post_draw.disconnect(_post_draw)

func _exit_tree() -> void:
 if _armed:
  _disconnect()
  if is_instance_valid(_pause):
   _pause.unregister_entry_gate(self)
   _pause.release_overlay(self)
