extends Node
## Editor-only transactions. Search/Preview never mutate the editable source.
const Store = preload("res://scripts/mobile_pose_store.gd")
const SERVICE_PATH := "res://scripts/mobile_elbow_preset_service.gd"
var editor
var service
var smooth_button: Button
var details_button: Button
var details: VBoxContainer
var preview_button: Button
var apply_button: Button
var undo_button: Button
var cancel_button: Button
var allow_angle: CheckButton
var arm: OptionButton
var axes: Array[SpinBox] = []
var update_button: Button
var reset_button: Button
var status: Label
var guide_hint: Label
var scope_hint: Label
var candidate: PostureDefinition
var accepted: Dictionary = {}
var offsets: Array = [Vector3.ZERO, Vector3.ZERO]
var undo_history: Array = []
var pending := false
var generation := 0
var source_key := ""
var source_signature := ""
var awaiting := false
var closing := false
var completion: Callable
var last_busy := false
var guide_dirty := false
var requested_offsets: Array = [Vector3.ZERO, Vector3.ZERO]

func mount(owner_editor, parent: Container) -> void:
	editor = owner_editor
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	var row := HBoxContainer.new(); parent.add_child(row)
	smooth_button = _button(row,"Smooth elbows",smooth)
	details_button = _button(row,"Elbow preview ▸",func():pass)
	details_button.toggle_mode = true
	details = VBoxContainer.new(); details.visible = false; parent.add_child(details)
	details_button.toggled.connect(func(on):
		details.visible=on; details_button.text="Elbow preview"+(" ▾" if on else " ▸")
		editor.call_deferred("_fit_content"))
	var actions := HBoxContainer.new(); details.add_child(actions)
	preview_button = _button(actions,"Preview",_toggle_preview); preview_button.toggle_mode=true
	apply_button = _button(actions,"Apply",apply_preview)
	undo_button = _button(actions,"Undo Apply",undo_apply)
	cancel_button = _button(details,"Cancel smoothing",cancel)
	allow_angle = CheckButton.new(); allow_angle.text="Allow paddle-angle adjustment (Preview first)"; allow_angle.button_pressed=true
	allow_angle.set_meta("compact_pose_row",true); details.add_child(allow_angle); editor._controls.append(allow_angle)
	allow_angle.toggled.connect(func(_on):cancel("Search option changed. Accepted Preview retained."))
	arm = editor.option(details,["Right arm","Left arm"]);arm.set_meta("compact_pose_row",true)
	arm.item_selected.connect(_select_arm)
	for axis in range(3):
		var axis_row := HBoxContainer.new();details.add_child(axis_row)
		var label := Label.new();label.text=["X right (cm)","Y up (cm)","Z back (cm)"][axis];label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;axis_row.add_child(label)
		var input := SpinBox.new();input.min_value=-20;input.max_value=20;input.step=.5;input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		input.get_line_edit().virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL;input.get_line_edit().select_all_on_focus=true
		input.set_meta("compact_pose_row",true);axis_row.add_child(input);editor._controls.append(input);axes.append(input)
		input.value_changed.connect(_offset_edited)
	var offset_actions := HBoxContainer.new();details.add_child(offset_actions)
	update_button=_button(offset_actions,"Update Preview",update_offset)
	reset_button=_button(offset_actions,"Reset all XYZ",reset_offsets)
	guide_hint=Label.new();guide_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.add_child(guide_hint)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(status)
	scope_hint=Label.new();scope_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;scope_hint.visible=false;parent.add_child(scope_hint)
	if ResourceLoader.exists(SERVICE_PATH):
		service=load(SERVICE_PATH).new();add_child(service)
		if service.has_signal("progress_changed"):service.progress_changed.connect(func(message:String):if awaiting and not closing:set_status(message))
	refresh_controls()

func _button(parent:Node,caption:String,callback:Callable)->Button:
	var value:Button=editor.button(parent,caption,callback);value.set_meta("compact_pose_row",true);return value

func busy()->bool:
	return is_instance_valid(service) and bool(service.busy)

func _process(_delta:float)->void:
	var now:=busy()
	if now!=last_busy:
		last_busy=now;refresh_controls()

func unavailable_reason()->String:
	if editor._current==null:return "Select a pose to smooth its elbows."
	if editor._base:return "Unavailable for static body stances. Use the existing elbow guides for manual adjustment."
	if editor._serve:return "Serve smoothing is unavailable in this version. Serve contact and ball-hand constraints stay unchanged."
	if not editor._has_motion():return "Ready is static. Use its elbow guides for manual adjustment."
	if not is_instance_valid(service):return "Elbow smoothing is unavailable: its solver could not be loaded."
	return ""

func signature(value:Resource)->String:
	if value==null:return ""
	if value is PostureDefinition:return Store.authored_fingerprint(value,"stroke_runtime")+":"+str(value.elbow_preset_bake.get("payload_sha256",""))
	return str(hash(var_to_bytes(Store._encode_fields(value))))

func source_selected()->void:
	invalidate("",false)
	var reason:=unavailable_reason()
	if not reason.is_empty():set_status(reason);return
	var bake:Dictionary=editor._current.elbow_preset_bake
	if not bake.is_empty():
		if str(bake.get("source_sha256",""))!=Store.authored_fingerprint(editor._current,str(bake.get("scope","stroke_runtime"))):
			set_status("Saved smoothing is stale / inactive for the current pose or grip. Regenerate with Smooth elbows or refine the pose manually. Saved data is unchanged.")
		else:
			var rotation:Array=bake.get("rotation_deg",[0,0,0])
			accepted={"active_sides":bake.get("active_sides",[false,false]),"angle_deg":float(bake.get("max_angle_deg",rad_to_deg(Basis.from_euler(Vector3(rotation[0],rotation[1],rotation[2])*(PI/180.0)).get_rotation_quaternion().get_angle()))),"varying_angle":bake.has("orientation_path"),"scope":"Stored core-only preset. Full-animation rebake needed; full Play retains the original. Select Stroke only · diagnostic to inspect the core and finish Hold."}
			set_status("Saved core-only smoothing retained. "+describe_result())
	else:set_status("Smooth elbows creates a stroke-only Preview. Saved smoothing stays diagnostic-only; full animation needs a new bake.")

func context_changed()->void:
	if awaiting or busy():cancel("Preview context changed. Pending smoothing discarded; last accepted Preview retained.")

func invalidate(message:String="Pose edited. Previous smoothing preview cleared.",clear_applied:bool=false)->void:
	generation+=1;awaiting=false
	if is_instance_valid(service):service.cancel()
	_disconnect_completion()
	candidate=null;accepted={};pending=false;guide_dirty=false;undo_history.clear();offsets=[Vector3.ZERO,Vector3.ZERO]
	requested_offsets=offsets.duplicate();preview_button.set_pressed_no_signal(false)
	if clear_applied and editor._current is PostureDefinition and "elbow_preset_bake" in editor._current:
		editor._current.elbow_preset_bake={}
		# Selected Wind-up / Finish is a detached sampling copy.
		if editor._edit is PostureDefinition:editor._edit.elbow_preset_bake={}
	_sync_axes();refresh_controls()
	if not message.is_empty():set_status(message)

func cancel(message:String="Search cancelled. Last accepted Preview and pose retained.")->void:
	generation+=1;awaiting=false
	if is_instance_valid(service):service.cancel()
	_disconnect_completion();refresh_controls()
	if not message.is_empty():set_status(message)

func _disconnect_completion()->void:
	if is_instance_valid(service) and completion.is_valid() and service.completed.is_connected(completion):service.completed.disconnect(completion)
	completion=Callable()

func _begin()->bool:
	if closing or busy():return false
	generation+=1;source_key=editor._key;source_signature=signature(editor._current);awaiting=true
	var ticket:=generation
	_disconnect_completion()
	completion=func(result:Dictionary):_completed(result,ticket)
	service.completed.connect(completion)
	editor._stop();editor._preview.cancel_gesture()
	return true

func smooth()->void:
	var reason:=unavailable_reason()
	if not reason.is_empty():set_status(reason);return
	if not _begin():return
	details_button.set_pressed_no_signal(true);details.visible=true;details_button.text="Elbow preview ▾"
	set_status("Building a cloned elbow Preview. Editing the source or Cancel discards pending work.")
	service.start(editor._current.duplicate(true),allow_angle.button_pressed)
	refresh_controls();editor.call_deferred("_fit_content")

func _completed(result:Dictionary,ticket:int)->void:
	if closing or not awaiting or ticket!=generation or editor._key!=source_key or signature(editor._current)!=source_signature:return
	awaiting=false;_disconnect_completion()
	var result_pose=result.get("pose")
	if not bool(result.get("valid",false)) or not result_pose is PostureDefinition:
		set_status("Manual adjustment needed: "+str(result.get("status","no validated route"))+". Existing pose and last accepted Preview retained.")
		refresh_controls();return
	var incoming_bake:Dictionary=result_pose.elbow_preset_bake
	var incoming_scope:String=str(incoming_bake.get("scope","stroke_runtime"))
	var expected:String=Store.authored_fingerprint(editor._current,incoming_scope)
	if str(incoming_bake.get("source_sha256",""))!=expected or Store.authored_fingerprint(result_pose,incoming_scope)!=expected or (result.has("source_sha256") and str(result.source_sha256)!=expected):
		set_status("Stale smoothing result rejected: source pose or grip changed. Regenerate from the current pose; existing edits retained.")
		refresh_controls();return
	candidate=result_pose.duplicate(true);accepted=result.duplicate(true);pending=true;guide_dirty=false
	offsets=result.get("offsets",requested_offsets).duplicate();requested_offsets=offsets.duplicate()
	preview_button.set_pressed_no_signal(true)
	var active:Array=result.get("active_sides",[false,false])
	if not bool(active[arm.selected]):arm.select(0 if bool(active[0]) else 1)
	_sync_axes();set_status("Preview ready. Pose unchanged until Apply. "+describe_result())
	refresh_controls();_open_runtime_preview()

func _open_runtime_preview()->void:
	# Preserve the selected action. Accepting a core result never silently opts
	# the user into diagnostic playback or changes their stance/variant choice.
	var elapsed:float=editor._timeline.elapsed
	editor._timeline._signature="";editor._timeline._update_settings_caption()
	editor._motion_dirty=true;editor._variant=null
	if editor._timeline._configure():
		editor._timeline._seek(clampf(elapsed/maxf(editor._timeline.sequence.duration,.001),0.0,1.0))
	else:_render()

func describe_result()->String:
	var active:Array=accepted.get("active_sides",[false,false])
	var dominant:int=1 if editor._current!=null and editor._current.paddle_hand==1 else 0
	var main:String="Left" if dominant==1 else "Right"
	var support:String="Right" if dominant==1 else "Left"
	var message:String="%s main: %s. %s support: %s."%[main,"active" if bool(active[dominant]) else "inherited / unchanged",support,"active" if bool(active[1-dominant]) else "inherited / unchanged"]
	if candidate!=null and candidate.elbow_preset_bake.has("orientation_path") or bool(accepted.get("varying_angle",false)):
		message+=" Paddle angle varies, up to %.2f° (sampled). The face direction changes; inspect Contact before Apply."%float(accepted.get("max_angle_deg",accepted.get("angle_deg",0.0)))
	else:message+=" Paddle angle %.2f°."%float(accepted.get("angle_deg",0.0))
	if not accepted.get("inherited_issues",[]).is_empty():message+=" Inherited arm issues remain; manual adjustment may be needed."
	if bool(accepted.get("manual_needed",false)):message+=" Manual adjustment needed."
	message+=" Core-only preset: full-animation rebake needed. Full Play retains the original; select Stroke only · diagnostic to inspect core and finish Hold."
	return message

func _candidate_source_matches()->bool:
	if candidate==null or not editor._current is PostureDefinition:return false
	var bake:Dictionary=candidate.elbow_preset_bake
	var scope:String=str(bake.get("scope","stroke_runtime"))
	var expected:String=Store.authored_fingerprint(editor._current,scope)
	return not expected.is_empty() and str(bake.get("source_sha256",""))==expected and Store.authored_fingerprint(candidate,scope)==expected

func preview_source(original:Resource)->Resource:
	return candidate if candidate!=null and preview_button.button_pressed and _candidate_source_matches() else original

func preview_pose(original:PostureDefinition)->PostureDefinition:
	return preview_pose_at(original,float(editor._timeline.sample.get("progress",0.0)),_matching_runtime_context())

func preview_pose_at(original:PostureDefinition,progress:float,matching_runtime:bool)->PostureDefinition:
	if candidate==null or not preview_button.button_pressed or not _candidate_source_matches():return original
	# The candidate bake is immutable after admission. Share its identity so the
	# runtime can reuse its verified cache instead of cloning ~900 KB per frame.
	var value:PostureDefinition=original.duplicate(false)
	value.elbow_preset_bake=candidate.elbow_preset_bake
	var runtime:Script=load("res://scripts/elbow_preset_runtime.gd")
	runtime.clear_tag(value)
	if matching_runtime:runtime.tag(value,candidate,progress,"stroke_runtime")
	return value

func _matching_runtime_context()->bool:
	var timeline=editor._timeline
	if not timeline.active or timeline.sample.is_empty() or not timeline.sequence.permits_core_overlay():return false
	# Saved Sequence playback retains its p=1 bake throughout the finish Hold.
	# Pending Preview must have exactly that interval too. Preparation and
	# recovery still use their original context; this is not a join certificate.
	var hold_seconds:float=maxf(0.0,timeline.sequence.source.ft_duration_hold)
	return timeline.elapsed>=timeline.sequence.prefix_seconds and timeline.elapsed<=timeline.sequence.prefix_seconds+timeline.sequence.stroke_seconds+hold_seconds

func _toggle_preview()->void:
	_render()

func after_refresh()->void:
	if not is_instance_valid(scope_hint):return
	var has_bake:bool=editor._current is PostureDefinition and not editor._current.elbow_preset_bake.is_empty()
	scope_hint.visible=candidate!=null or has_bake
	var showing_candidate:bool=candidate!=null and preview_button.button_pressed
	var prefix:String="Original pose fallback for the complete action. Stored core-only preset needs a full-animation rebake. "
	if not showing_candidate and not has_bake:prefix="Original pose · smoothing Preview off. "
	elif _matching_runtime_context():
		var report:Dictionary=editor._preview.player.get_meta("elbow_preset_report",{})
		prefix="Stroke-only diagnostic / finish Hold · smoothing applied. " if bool(report.get("applied",false)) else "Stroke-only diagnostic / finish Hold · original fallback: "+str(report.get("status","saved smoothing is stale or does not match this context"))+". "
	scope_hint.text=prefix+"Only explicit Stroke only · diagnostic can apply a matching core preset. Joint curves follow the current stroke preview; phase ghosts show authored keys. Full Play and blended/retargeted gameplay retain the original."
	refresh_controls()

func _render()->void:
	if closing or editor._current==null:return
	editor._motion_dirty=true;editor._variant=null;editor._refresh_preview();editor._refresh_status()

func _apply_context_ready()->bool:
	if not is_instance_valid(preview_button) or not preview_button.button_pressed or not _matching_runtime_context():return false
	if editor._preview.pose==null or not editor._preview.pose.has_meta("elbow_preset_sample"):return false
	return bool(editor._preview.player.get_meta("elbow_preset_report",{}).get("applied",false))

func apply_preview()->void:
	if busy() or guide_dirty or not pending or candidate==null or source_key!=editor._key or signature(editor._current)!=source_signature or not _candidate_source_matches():return
	if not _apply_context_ready():
		set_status("Select Stroke only · diagnostic with Preview on and a matching applied frame before Apply. Full Play remains original; full-animation rebake needed.");return
	undo_history.append({"bake":editor._current.elbow_preset_bake.duplicate(true),"dirty":editor._dirty.has(editor._key)})
	editor._current.elbow_preset_bake=candidate.elbow_preset_bake.duplicate(true)
	editor._dirty[editor._key]=true;pending=false;source_signature=signature(editor._current)
	editor._timeline.invalidate();editor._select_stage(editor._stage);_open_runtime_preview()
	set_status("Applied to this editable pose. Save persists it on this device. Undo Apply restores the prior smoothing. "+describe_result())
	refresh_controls()

func undo_apply()->void:
	if busy() or undo_history.is_empty() or source_key!=editor._key or signature(editor._current)!=source_signature:return
	var prior:Dictionary=undo_history.pop_back()
	editor._current.elbow_preset_bake=prior.bake.duplicate(true)
	# A Save may have occurred after Apply: Undo is then a new unsaved edit.
	var saved:Resource=editor._definitions[editor._pose_picker.selected]
	if signature(editor._current)==signature(saved):editor._dirty.erase(editor._key)
	else:editor._dirty[editor._key]=true
	pending=candidate!=null;source_signature=signature(editor._current)
	preview_button.set_pressed_no_signal(false);editor._timeline.invalidate();editor._select_stage(editor._stage);_open_runtime_preview()
	set_status("Undo restored the previous smoothing. Preview remains available; Save persists any remaining edits.")
	refresh_controls()

func _select_arm(_index:int)->void:
	if guide_dirty:set_status("Unsubmitted XYZ cleared on arm change. Last accepted Preview retained.");guide_dirty=false
	if busy():cancel("Arm selection changed. Pending guide result discarded; accepted Preview retained.")
	_sync_axes();refresh_controls()

func _sync_axes()->void:
	if axes.is_empty():return
	var value:Vector3=offsets[arm.selected]
	for index in range(3):axes[index].set_value_no_signal(value[index]*100.0)

func _offset_edited(_value:float)->void:
	if busy():cancel("Requested guide changed. Pending result discarded; accepted Preview retained.")
	if candidate!=null:
		guide_dirty=true;refresh_controls();set_status("Requested body-local guide preference only. Update Preview re-solves it; Apply accepts it.")

func update_offset()->void:
	if candidate==null or busy():return
	if not _candidate_source_matches():invalidate("Source pose or grip changed. Regenerate before editing guide preferences.",false);return
	var active:Array=accepted.get("active_sides",[false,false])
	if not bool(active[arm.selected]):return
	var wanted:=Vector3(axes[0].value,axes[1].value,axes[2].value)*.01
	if not wanted.is_finite():set_status("Enter finite XYZ guide values.");return
	if not _begin():return
	requested_offsets=offsets.duplicate();requested_offsets[arm.selected]=wanted
	set_status("Re-solving requested guide preference. Last accepted Preview retained.")
	service.request_offset(arm.selected,wanted);refresh_controls()

func reset_offsets()->void:
	if candidate==null or busy():return
	if not _candidate_source_matches():invalidate("Source pose or grip changed. Regenerate before resetting guide preferences.",false);return
	if not _begin():return
	requested_offsets=[Vector3.ZERO,Vector3.ZERO]
	set_status("Resetting both active-arm guide preferences in Preview.")
	service.reset_offsets();refresh_controls()

func refresh_controls()->void:
	if not is_instance_valid(smooth_button):return
	var running:=busy();var available:=unavailable_reason().is_empty()
	smooth_button.disabled=running or not available or closing
	preview_button.disabled=candidate==null or closing
	apply_button.disabled=running or guide_dirty or not pending or candidate==null or closing or not _candidate_source_matches() or not _apply_context_ready()
	apply_button.tooltip_text="Select Stroke only · diagnostic with Preview on and a matching applied frame before Apply. Full Play requires a full-animation rebake."
	undo_button.disabled=running or undo_history.is_empty() or closing
	cancel_button.disabled=not running;allow_angle.disabled=closing
	var active:Array=accepted.get("active_sides",[false,false])
	var selected_active:=candidate!=null and bool(active[arm.selected])
	for axis in axes:axis.editable=selected_active and not closing
	update_button.disabled=running or not selected_active or closing
	reset_button.disabled=running or candidate==null or closing
	guide_hint.text="Requested whole-guide offset in body-local centimeters; re-solving may limit actual movement." if selected_active else "This arm is inherited / unchanged; XYZ is unavailable." if candidate!=null else "XYZ becomes available for each active arm after a validated Preview."

func set_status(message:String)->void:
	if is_instance_valid(status):status.text=message

func prepare_close()->void:
	closing=true;cancel("");refresh_controls()

func _exit_tree()->void:
	closing=true
	if is_instance_valid(service):service.cancel()
	_disconnect_completion()
