extends Node
## Administrative dead-ball point reset. Physical pickup remains the default.
const Admission=preload("res://scripts/between_pose_admission.gd")
const Budget=preload("res://scripts/live_arm_budget.gd")
const Foot=preload("res://scripts/pose_foot_contacts.gd")
const TOLERANCE:float=.00002
const MOVE_ACTIONS=["move_left","move_right","move_up","move_down"]
var game
var scene_id:int=0
var finalized_token:int=-1
var serial:int=0
var _movement_release:Array=[]
var _draw_started_key:Array=[]
var _draw_ready_key:Array=[]
var _valid_draws:int=0
var _focus_available:bool=true
var _pause_seen:bool=false
var active:bool=false
var phase:String="IDLE"
var phase_elapsed:float=0.0
var elapsed:float=0.0
var generation:int=-1
var reset_entered:bool=false
var reset_count:int=0
var geometry_queries:int=0
var _cycle_queries:int=0
var prepared_tick:int=-1
var ledger:Dictionary={}
var initial_stamina:Dictionary={}
var last_report:Dictionary={}
var history:Array=[]
var canvas:CanvasLayer
var cover:ColorRect
var label:Label
var pause_button:Button
var _pause_visual_key:Array=[]
func setup(owner)->void:
 game=owner
 process_mode=Node.PROCESS_MODE_ALWAYS
 process_physics_priority=200000
 RenderingServer.frame_pre_draw.connect(_pre_draw)
 RenderingServer.frame_post_draw.connect(_post_draw)
 canvas=CanvasLayer.new();canvas.layer=50;add_child(canvas)
 cover=ColorRect.new();cover.name="QuickPointCover";cover.color=Color(0.025,0.04,0.06,0.0);cover.mouse_filter=Control.MOUSE_FILTER_STOP
 cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(cover)
 label=Label.new();label.name="QuickPointStatus";label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",24);label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);cover.add_child(label)
 canvas.visible=false
 _sync_pause_button()
func _sync_pause_button()->bool:
 var source:Button=game.hud._pause_button if is_instance_valid(game) and game.hud!=null else null
 if not is_instance_valid(source) or not source.is_visible_in_tree() or source.get_script()!=null:return false
 var rect:Rect2=source.get_global_rect()
 if rect.size.x<=0.0 or rect.size.y<=0.0 or not get_viewport().get_visible_rect().encloses(rect):return false
 var key:Array=[source.get_instance_id(),rect,source.text,source.get_theme_font_size("font_size"),source.get_parent().theme]
 for child in source.get_children():
  var visual_script:Script=child.get_script()
  if child.get_child_count()!=0 or not child is Control:return false
  if visual_script!=null and visual_script.resource_path!="res://scripts/ui/hud_chrome.gd":return false
  if visual_script==null and not child is Label:return false
  if child is Control:key.append([child.get_instance_id(),child.get_rect(),child.visible,child.get_theme_font_size("font_size")])
 if key==_pause_visual_key and is_instance_valid(pause_button):return true
 # Duplicate visual properties/scripts, but no signal connections or groups.
 # The only action installed on this covered replacement is the existing Pause.
 var replacement:Button=source.duplicate(Node.DUPLICATE_SCRIPTS) as Button
 if replacement==null:return false
 for index in source.get_child_count():
  var original_child=source.get_child(index)
  if original_child.get_script()!=null:replacement.get_child(index).kind=original_child.kind
 replacement.name="QuickPointPause";replacement.theme=source.get_parent().theme
 replacement.process_mode=Node.PROCESS_MODE_ALWAYS;replacement.disabled=false
 replacement.set_anchors_preset(Control.PRESET_TOP_LEFT)
 replacement.position=rect.position-cover.global_position;replacement.size=rect.size
 replacement.pressed.connect(_pause)
 cover.add_child(replacement)
 if is_instance_valid(pause_button):pause_button.hide();pause_button.queue_free()
 pause_button=replacement;_pause_visual_key=key
 return true
func _pause()->void:
 var pause=get_tree().root.get_node_or_null("PauseController")
 if pause:pause.open()
func blocks_attempt()->bool:return active
func blocks_movement()->bool:
 return active or not _movement_release.is_empty()
func _latch_movement()->void:
 for action in MOVE_ACTIONS:
  if active and Input.is_action_pressed(action) and action not in _movement_release:_movement_release.append(action)
  if not Input.is_action_pressed(action):_movement_release.erase(action)
func _token()->int:
 return int(game.doubles_state.last_result.get("token",-1)) if game.doubles_mode else finalized_token
func _context_current()->bool:
 return is_instance_valid(game) and not game.is_queued_for_deletion() and game.get_instance_id()==scene_id and get_tree().current_scene==game and not game._is_practice() and not game.match_over and game._point_reset_generation==generation and _token()==finalized_token
func _notification(what:int)->void:
 if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
  _focus_available=false;_clear_draws()
 elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_WM_WINDOW_FOCUS_IN]:
  _focus_available=true;_clear_draws()
func _clear_draws()->void:
 _draw_started_key=[];_draw_ready_key=[];_valid_draws=0
func _draw_key()->Array:
 if not active or phase not in ["COVER_WAIT","REVEAL_WAIT"] or not _context_current() or not _focus_available or get_tree().paused:return []
 if not canvas.visible or not cover.is_visible_in_tree():return []
 var alpha:float=1.0 if phase=="COVER_WAIT" else 0.0
 if cover.color.a!=alpha:return []
 var view=get_viewport()
 if cover.size!=view.get_visible_rect().size:return []
 return [scene_id,serial,generation,finalized_token,phase,view.get_instance_id(),view.get_visible_rect(),cover.get_instance_id(),cover.size,alpha]
func _pre_draw()->void:
 if active and not _sync_pause_button():_clear_draws();return
 _draw_started_key=_draw_key()
func _post_draw()->void:
 if _draw_started_key.is_empty():return
 var current:Array=_draw_key()
 if current==_draw_started_key:
  if _draw_ready_key!=current:_valid_draws=0
  _draw_ready_key=current.duplicate();_valid_draws+=1
  if last_report.get("draws",[]).size()<8:last_report.draws.append({"phase":phase,"generation":generation,"serial":serial,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"count":_valid_draws})
 else:_clear_draws()
 _draw_started_key=[]
func _draw_acknowledged()->bool:
 return _valid_draws>=2 and not _draw_ready_key.is_empty() and _draw_ready_key==_draw_key()
func _ledger()->Dictionary:
 if game.doubles_mode:return game.doubles_state.snapshot().duplicate(true)
 return {"scores":[game.score_left,game.score_right],"serving_team":game.serving_team,"server_actor":game.get_server_actor().get_actor_id()}
func _settled()->bool:
 return not game.ball.is_in_play and game.ball.deferred_scene_interval().is_empty() and not game.match_over and not game.rally_scorer.has_pending_settlement() and game.contact_authority.unresolved_continuation.is_empty() and (not game.doubles_mode or game.doubles_state.active_rally.is_empty())
func begin()->bool:
 if active or game==null or game._is_practice() or game.game_state!=game.GameState.POINT_SCORED or not _settled():return false
 if game.doubles_mode and game.doubles_state.end_change_pending:return false
 if not _sync_pause_button():return false
 # Let the existing captured physical transition own an unfinished service
 # delivery/follow-through; Quick must not clear that presentation visibly.
 if game.game_serve.is_release_pending() or not game.game_serve._follow_through.is_empty():return false
 scene_id=game.get_instance_id();serial+=1;finalized_token=int(game.doubles_state.last_result.get("token",-1)) if game.doubles_mode else game._point_reset_generation
 if game.doubles_mode and finalized_token<0:return false
 active=true;phase="RECOVERY";phase_elapsed=0.0;elapsed=0.0;generation=game._point_reset_generation;reset_entered=false;reset_count=0;geometry_queries=0;_cycle_queries=0;ledger=_ledger();initial_stamina={}
 for actor in game.get_players():initial_stamina[actor.get_actor_id()]={"value":actor.stamina.value,"delay":actor.stamina.recovery_delay}
 last_report={"status":"active","generation":generation,"server":game.get_server_actor().get_actor_id(),"ledger":ledger.duplicate(true),"phases":[],"reset_inclusive_wall_usec":0,"geometry_inclusive_wall_usec":0,"presentation_wait_seconds":0.0,"draws":[],"finalized_token":finalized_token,"serial":serial}
 _note("RECOVERY")
 # Mark the gate active before releasing old input, so synthetic cancellation
 # cannot be interpreted as a new serve or charge behind the cover.
 game.game_serve.cleanup();game.input_handler.cancel_charge_input()
 if game.mobile_controls:game.mobile_controls.cancel_all()
 if game.aim_focus:game.aim_focus.cancel()
 if game.movement_guide:game.movement_guide.cancel()
 game.selected_movement_intent="AUTO"
 for actor in game.get_players():
  actor.cancel_contextual_jump()
  if actor.special_reach_driver:actor.special_reach_driver.cancel("finalized point recovery")
  if actor.ai_brain:actor.ai_brain.cancel_execution_commit()
  var human=actor.posture.human_contact if actor.posture!=null else null
  if human!=null and human.phase>=0 and human.phase<2:human.cancel(true)
 game.ai_serve_timer=0.0
 _latch_movement();_clear_draws()
 canvas.visible=true;cover.color.a=0.0;label.text="Next point · "+game._format_serve_call();label.modulate.a=0.0
 return true
func _note(next:String)->void:
 phase=next;phase_elapsed=0.0;_clear_draws()
 if last_report.has("phases"):last_report.phases.append({"phase":next,"elapsed":elapsed,"physics_frame":Engine.get_physics_frames(),"inclusive_wall_usec":Time.get_ticks_usec()})
func observe_reset_request(token:int)->void:
 if not active:return
 if phase=="RESETTING" and token==generation and not reset_entered:
  reset_entered=true;return
 cancel("external reset superseded transition")
func can_reset(token:int)->bool:
 return active and _context_current() and phase=="RESETTING" and not reset_entered and token==generation and game._point_reset_generation==generation and game.game_state==game.GameState.POINT_SCORED and _settled() and _ledger()==ledger and (not game.doubles_mode or not game.doubles_state.end_change_pending)
func _physics_process(delta:float)->void:
 _latch_movement()
 if not active:return
 if not _context_current():cancel("scene, finalized token, mode or generation superseded");return
 if get_tree().paused or not _focus_available or game._tool_state_active():
  _pause_seen=true;_clear_draws();return
 if _pause_seen:
  _pause_seen=false;_clear_draws();_cycle_queries=0
  game.input_handler.latch_transition_input()
  if reset_count>0 and phase not in ["PREPARE","BLOCKED"]:
   cover.color.a=1.0;label.modulate.a=1.0;_note("PREPARE")

 elapsed+=delta;phase_elapsed+=delta
 if not _settled() or _ledger()!=ledger:_block("settled ledger or contact context changed");return
 match phase:
  "RECOVERY":
   if phase_elapsed>=.60 and _recovery_complete():_note("COVER")
   elif phase_elapsed>=2.0:_physical_fallback("ongoing supported recovery")
  "COVER":
   cover.color.a=clampf(phase_elapsed/.18,0.0,1.0);label.modulate.a=cover.color.a
   if phase_elapsed>=.18:_note("COVER_WAIT")
  "COVER_WAIT":
   last_report.presentation_wait_seconds+=delta
   if _draw_acknowledged():
    _note("RESETTING")
    var expected:int=generation
    var started:int=Time.get_ticks_usec()
    var success:bool=game.request_fast_point_reset(expected)
    var duration:int=Time.get_ticks_usec()-started
    if not active:return
    last_report.reset_inclusive_wall_usec=duration
    if not success or not reset_entered or game._point_reset_generation!=expected+1:_block("reset context was not committed exactly once");return
    reset_count+=1;generation=game._point_reset_generation;prepared_tick=Engine.get_physics_frames();_note("PREPARE")
  "PREPARE":
   if Engine.get_physics_frames()<prepared_tick+2:return
   var support:Dictionary=_support_report()
   if not support.valid:
    if phase_elapsed>=1.0:_block("current support did not settle",support)
    return
   var report:Dictionary=_admit(support)
   if not report.valid:_block("current service presentation rejected",report);return
   last_report.initial_admission=report;_note("REVEAL")
  "REVEAL":
   cover.color.a=1.0-clampf(phase_elapsed/.18,0.0,1.0);label.modulate.a=cover.color.a
   if not _support_report().valid:_block("support changed during reveal");return
   if phase_elapsed>=.18:_note("REVEAL_WAIT")
  "REVEAL_WAIT":
   last_report.presentation_wait_seconds+=delta
   if _draw_acknowledged():
    var report:Dictionary=_admit(_support_report())
    if not report.valid:_block("final current service presentation changed",report);return
    last_report.final_admission=report;last_report.status="READY";last_report.elapsed=elapsed;last_report.reset_count=reset_count;last_report.geometry_queries=geometry_queries;last_report.stamina_before=initial_stamina;last_report.stamina_after={}
    for actor in game.get_players():last_report.stamina_after[actor.get_actor_id()]={"value":actor.stamina.value,"delay":actor.stamina.recovery_delay}
    game.input_handler.latch_transition_input();game.ai_serve_timer=0.0
    active=false;phase="IDLE";canvas.visible=false;history.append(last_report.duplicate(true))
    if history.size()>16:history.pop_front()
  "BLOCKED":pass
func _recovery_complete()->bool:
 for actor in game.get_players():
  if actor.is_jumping or actor.jump_landing_remaining>0.0:return false
  if actor.erne_action!=null and actor.erne_action.active:return false
  if actor.special_reach_driver!=null and actor.special_reach_driver.owns_presentation():return false
  if actor.hitting!=null and actor.hitting.is_in_follow_through:return false
  if actor.posture!=null and actor.posture.human_contact!=null and actor.posture.human_contact.phase>=0:return false
 return true
func _physical_fallback(reason:String)->void:
 if reset_count!=0:_block(reason);return
 last_report.status="PHYSICAL_FALLBACK";last_report.reason=reason
 active=false;phase="IDLE";canvas.visible=false;_clear_draws()
 game.between_point_controller.begin(game.between_point_controller.capture_presentations())
func _support_report()->Dictionary:
 var rows:Array=[];var valid:bool=true
 for actor in game.get_players():
  var arms:Dictionary=Budget.displayed_report(actor)
  var feet:Array=[];var okay:bool=actor.current_velocity.length_squared()<=.000001 and actor.leg_ik.feet_initialized
  for side in 2:
   var leg=actor.right_leg_node if side==0 else actor.left_leg_node
   var locked:bool=actor.leg_ik.right_foot_locked if side==0 else actor.leg_ik.left_foot_locked
   var anchor:Vector3=actor.leg_ik.right_foot_lock_pos if side==0 else actor.leg_ik.left_foot_lock_pos
   var ankle:Vector3=leg.foot_pivot.global_position
   var upper_error:float=absf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position)-leg.thigh_length)
   var lower_error:float=absf(leg.shin_pivot.global_position.distance_to(ankle)-leg.shin_length)
   var sole:float=INF
   var bounds:AABB=leg.foot_mesh.mesh.get_aabb()
   for corner in 8:sole=minf(sole,(leg.foot_mesh.global_transform*bounds.get_endpoint(corner)).y)
   var feasible:bool=sole>=Ball.FLOOR_Y-TOLERANCE and locked and actor.leg_ik.is_support_ready(side) and ankle.distance_to(anchor)<=TOLERANCE and upper_error<=TOLERANCE and lower_error<=TOLERANCE and Foot.reach_report(leg.thigh_pivot.global_position,ankle,leg.thigh_length,leg.shin_length).feasible
   okay=okay and feasible;feet.append({"valid":feasible,"sole":sole,"locked":locked,"anchor_error":ankle.distance_to(anchor),"upper_error":upper_error,"lower_error":lower_error})
  valid=valid and okay and bool(arms.valid);rows.append({"actor":actor.get_actor_id(),"team":actor.team_id,"side":actor.court_side,"arms":arms,"feet":feet,"valid":okay and bool(arms.valid)})
 return {"valid":valid,"actors":rows}
func _admit(support:Dictionary)->Dictionary:
 if not support.valid:return {"valid":false,"support":support}
 if _cycle_queries>=2:return {"valid":false,"reason":"deterministic certificate budget exhausted"}
 geometry_queries+=1;_cycle_queries+=1
 var started:int=Time.get_ticks_usec()
 var server=game.get_server_actor();var certificate=Admission.new(server)
 var pose:Dictionary=certificate.displayed_report()
 var feet:Dictionary=game.game_serve._check_service_feet(server,server.get_court_side())
 var center:Vector3=server.left_arm_node.hand_mesh.global_transform*server.left_arm_node.articulated_hand.cup_ball_center
 var cup_error:float=center.distance_to(game.ball.global_position)
 var fresh:bool=game.contact_authority._query_frame==Engine.get_physics_frames() and game.contact_authority._frame_current.size()==game.get_players().size()
 var okay:bool=fresh and pose.valid and feet.valid and cup_error<=TOLERANCE and game.game_state==game.GameState.WAITING and _settled() and _ledger()==ledger and game.game_serve._server_prepared and game.game_serve._prepared_actor==server.get_actor_id() and not game.game_serve.is_release_pending()
 last_report.geometry_inclusive_wall_usec+=Time.get_ticks_usec()-started
 return {"valid":okay,"fresh_all_actor_authority_snapshot":fresh,"pose":pose,"service_feet":feet,"cup_error":cup_error,"server":server.get_actor_id(),"support":support,"physics_frame":Engine.get_physics_frames()}
func _block(reason:String,detail:Dictionary={})->void:
 if phase=="BLOCKED":return
 _note("BLOCKED");last_report.status="BLOCKED";last_report.reason=reason;last_report.detail=detail;last_report.reset_count=reset_count;last_report.geometry_queries=geometry_queries
 cover.color.a=1.0;label.modulate.a=1.0;label.text="Service setup needs attention\nPause to reset or return to the menu."
func cancel(reason:String)->void:
 if not active:return
 active=false;phase="IDLE";last_report.status="CANCELED";last_report.reason=reason
 if is_instance_valid(canvas):canvas.visible=false
func _exit_tree()->void:
 active=false
 if RenderingServer.frame_pre_draw.is_connected(_pre_draw):RenderingServer.frame_pre_draw.disconnect(_pre_draw)
 if RenderingServer.frame_post_draw.is_connected(_post_draw):RenderingServer.frame_post_draw.disconnect(_post_draw)
