extends CanvasLayer
## Opt-in touch workspace. Created only from Pause and destroyed on Back.
## Edits remain private copies until Save. The match stays paused throughout.
signal editor_closed
signal poses_saved
const Ui = preload("res://scripts/ui/game_ui_theme.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const ViewSettings = preload("res://scripts/mobile_pose_view_settings.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Timeline = preload("res://scripts/ui/mobile_pose_timeline.gd")
const ElbowPresetPanel = preload("res://scripts/ui/mobile_elbow_preset_panel.gd")
var _elbow_preset_panel
var _timeline = Timeline.new()
const PaddleRotation = preload("res://scripts/paddle_rotation.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Keyframe = preload("res://scripts/stroke_body_keyframe.gd")
const Icons = preload("res://scripts/ui/mobile_pose_icons.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const Gimbal = preload("res://scripts/ui/mobile_paddle_gimbal.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const GripStyles = preload("res://scripts/paddle_grip_styles.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
const FootEditValidator=preload("res://scripts/pose_foot_edit_validator.gd")
const FOOT_GUARDED_FIELDS=["body_position_offset","body_yaw_deg","body_pitch_deg","body_roll_deg","hip_yaw_deg","torso_yaw_deg","torso_pitch_deg","torso_roll_deg","spine_curve_deg","shoulder_protraction_m","crouch_amount","weight_shift"]
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const WindupVariants = preload("res://scripts/ui/mobile_pose_windup_variants.gd")
const GizmoFields = preload("res://scripts/ui/mobile_pose_gizmo_fields.gd")
const GizmoAxes = preload("res://scripts/ui/mobile_pose_gizmo_axes.gd")
const POS = ["paddle_forehand_mul","paddle_y_offset","paddle_forward_mul"]
const ROT = ["paddle_pitch_base_deg","paddle_yaw_base_deg","paddle_roll_base_deg"]
var _root: Control
var _content: VBoxContainer
var _body: BoxContainer
var _visual_scroll:ScrollContainer
var _visual_panel: VBoxContainer
var _view_options:VBoxContainer
var _view_toggle:Button
var _edit_panel: VBoxContainer
var _preview
var _pose_picker: OptionButton
var _workspace: OptionButton
var _group: OptionButton
var _category: OptionButton
var _scroll: ScrollContainer
var _fields: VBoxContainer
var _status: Label
var _phase: Button
var _field_help := ""
var _scrub: HSlider
var _play: Button
var _save: Button
var _revert: Button
var _stages: Array[Button] = []
var _copies: Dictionary = {}
var _dirty: Dictionary = {}
var _rotation_undo: Dictionary = {}
var _definitions: Array = []
var _current: Resource
var _edit: Resource
var _key := ""
var _stage := 1
var _base := false
var _serve := false
var _playing := false
var _resume_playback := false
var _progress := .5
var _dialog: Control
var _dialog_box: PanelContainer
var _dialog_title: Label
var _dialog_buttons: VBoxContainer
var _s := 1.0
var _controls: Array[Control] = []
var _sliders: Dictionary = {}
var _closing := false
var _last_tick := 0
var _copy_action: Button
var _copy_layer: Control
var _copy_box: VBoxContainer
var _copy_text: TextEdit
var _copy_status: Label
var _copy_payload := ""
var _motion_dirty := true
var _stage_row: HBoxContainer
var _motion_hint: Label
var _icons := {}
var _fine := true
var _fine_button: Button
var _joint_picker: OptionButton
var _selected_joint := "torso"
var _gimbal: Control
var _angle_inputs: Dictionary = {}
var _gimbal_axis_buttons: Array[Button] = []
var _angle_sync := false
var _rotation_refresh_pending := false
var _grip_picker: OptionButton
var _grip_input: SpinBox
var _grip_source: Label
var _paddle_view := 0
var _slider_labels: Dictionary = {}
var _global_copy_snapshots: Dictionary = {}
var _lag_direction := 0
var _variant_mode := 0
var _variant
var _strong_play:Button
var _weak_play:Button
var _ghost_slider: HSlider
var _ghost_label: Label
var _ghost_row: HBoxContainer
var _stance_preset:=0
var _body_position_status:Label
var _body_inputs:Dictionary = {}
var _body_input_sync := false
var _serve_contact_status:Label
var _foot_pitch_status:Label
var _elbow_guide_status:Label
var _upper_body_status:Label
var _gizmo_mode: OptionButton
var _gizmo_show: Button
var _gizmo_hint: Label
var _camera_row: HBoxContainer
var _gizmo_row: HBoxContainer
var _gizmo_channels: Dictionary = {}
# Secondary tools share the inspector space instead of shrinking/scrolling the scene.
var _title: Label
var _picker_row: HBoxContainer
var _group_row: HBoxContainer
var _scene_focus: Button
var _tools_toggle: Button
var _tools_scroll: ScrollContainer
var _tools_panel: VBoxContainer
var _expanded_scene := false

func _ready()->void:
	name="MobilePoseEditor";layer=110;process_mode=Node.PROCESS_MODE_WHEN_PAUSED
	_root=Control.new();_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter=Control.MOUSE_FILTER_STOP;_root.theme=Ui.create();add_child(_root)
	var backdrop:=ColorRect.new();backdrop.color=Ui.PANEL
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(backdrop)
	_content=VBoxContainer.new();_root.add_child(_content);_content.add_theme_constant_override("separation",8)
	var header:=HBoxContainer.new();_content.add_child(header)
	var title:=Label.new();_title=title;title.text="POSE EDITOR";title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	_copy_action=button(header,"Copy pose JSON",_copy_current_pose)
	_copy_action.size_flags_horizontal=0
	_copy_action.tooltip_text="Copy this pose's current values for chat, including unsaved edits. Does not Save."
	var back_button:=button(header,"Back",close);back_button.size_flags_horizontal=0;back_button.custom_minimum_size.x=112
	var pickers:=HBoxContainer.new();_picker_row=pickers;_content.add_child(pickers)
	_workspace=option(pickers,["Strokes","Body stances","Serves"]);_workspace.size_flags_horizontal=0;_workspace.custom_minimum_size.x=200;_workspace.item_selected.connect(_select_workspace)
	_pose_picker=option(pickers,[]);_pose_picker.item_selected.connect(_select_pose)
	_body=BoxContainer.new();_body.vertical=true;_body.size_flags_vertical=Control.SIZE_EXPAND_FILL;_content.add_child(_body)
	_visual_scroll=ScrollContainer.new();_visual_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_visual_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_child(_visual_scroll)
	_visual_panel=VBoxContainer.new();_visual_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_visual_scroll.add_child(_visual_panel)
	_visual_panel.minimum_size_changed.connect(func():call_deferred("_fit_content"))
	_edit_panel=VBoxContainer.new();_edit_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_edit_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.add_child(_edit_panel)
	_tools_panel=VBoxContainer.new();_tools_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_preview=Preview.new();_preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_visual_panel.add_child(_preview)
	var scene_border:=Panel.new();scene_border.mouse_filter=Control.MOUSE_FILTER_IGNORE
	scene_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border_style:=StyleBoxFlat.new();border_style.bg_color=Color.TRANSPARENT;border_style.border_color=Color("395665")
	border_style.set_border_width_all(1);border_style.set_corner_radius_all(10)
	scene_border.add_theme_stylebox_override("panel",border_style);_preview.add_child(scene_border)
	var view_toggle:=button(_tools_panel,"View & gizmo options ▸",func():pass);_view_toggle=view_toggle;view_toggle.toggle_mode=true;view_toggle.set_meta("compact_pose_row",true)
	var view_options:=VBoxContainer.new();_view_options=view_options;view_options.visible=false;_tools_panel.add_child(view_options)
	view_toggle.toggled.connect(func(on):
		view_options.visible=on
		if on:_timeline.close_options()
		view_toggle.text="View & gizmo options"+(" ▾" if on else " ▸")
		call_deferred("_fit_content"))
	var camera_row:=HBoxContainer.new();view_options.add_child(camera_row)
	_camera_row=camera_row
	for direction in ["Front","Side","Back"]:button(camera_row,direction,_preview.view.bind(direction.to_lower()))
	_gizmo_row=HBoxContainer.new();view_options.add_child(_gizmo_row)
	button(_gizmo_row,"−",_preview.zoom.bind(.3));button(_gizmo_row,"+",_preview.zoom.bind(-.3))
	_gizmo_mode=option(_gizmo_row,["Move", "Rotate"]);_gizmo_mode.custom_minimum_size.x=110
	_gizmo_show=button(_gizmo_row,"Show",_toggle_gizmo);_gizmo_show.toggle_mode=true
	var gizmo_settings:Dictionary=ViewSettings.load_gizmo()
	_gizmo_mode.select(gizmo_settings.mode);_gizmo_show.set_pressed_no_signal(gizmo_settings.shown)
	_gizmo_mode.item_selected.connect(_select_gizmo_mode)
	_preview.gizmo.dragged.connect(_drag_selected_gizmo)
	_gizmo_hint=Label.new();_gizmo_hint.text="Select joint for gizmo · drag elsewhere to orbit";_gizmo_hint.modulate=Ui.MUTED;_gizmo_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;view_options.add_child(_gizmo_hint)
	_stage_row=HBoxContainer.new();_visual_panel.add_child(_stage_row)
	for i in range(3):
		var b:=button(_stage_row,["Wind-up","Contact","Finish"][i],_select_stage.bind(i));b.toggle_mode=true;_style_stage_button(b,i);_stages.append(b)
	_motion_hint=Label.new();_motion_hint.text="3 keys · purple Wind-up / gold Contact / cyan Finish";_motion_hint.modulate=Ui.MUTED;_motion_hint.hide();_visual_panel.add_child(_motion_hint)
	_ghost_row=HBoxContainer.new();view_options.add_child(_ghost_row)
	_ghost_label=Label.new();_ghost_label.modulate=Ui.MUTED;_ghost_row.add_child(_ghost_label)
	_ghost_slider=HSlider.new();_ghost_slider.scrollable=false;_ghost_slider.min_value=0;_ghost_slider.max_value=ViewSettings.MAX_INBETWEEN_COUNT;_ghost_slider.step=1
	_ghost_slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_ghost_slider.custom_minimum_size=Vector2(100,88);_ghost_row.add_child(_ghost_slider);_controls.append(_ghost_slider)
	_ghost_slider.tooltip_text="Faint solved body + paddle poses in each gap: Wind-up → Contact and Contact → Finish. 0 switches them off. View setting only; the 3 editable keys stay unchanged."
	_ghost_slider.set_value_no_signal(ViewSettings.load_inbetween_count());_preview.set_inbetween_count(int(_ghost_slider.value));_update_ghost_label()
	_ghost_slider.value_changed.connect(_ghost_count_changed)
	var scrub_row:=HBoxContainer.new();_visual_panel.add_child(scrub_row)
	_play=button(scrub_row,"Play",_toggle_play);_play.size_flags_horizontal=0;_icons["stop"]=Icons.texture("stop")
	_strong_play=button(scrub_row,"Strong",_play_variant.bind(WindupVariants.STRONG));_strong_play.size_flags_horizontal=0;_strong_play.toggle_mode=true
	_weak_play=button(scrub_row,"Weak",_play_variant.bind(WindupVariants.WEAK));_weak_play.size_flags_horizontal=0;_weak_play.toggle_mode=true
	for b in [_strong_play,_weak_play]:b.icon=Icons.texture("play")
	_strong_play.tooltip_text="Play a generated backswing up to 6 inches farther along the curve. Saved poses stay unchanged."
	_weak_play.tooltip_text="Play a generated backswing up to 6 inches shorter along the curve. Saved poses stay unchanged."
	_scrub=HSlider.new();_scrub.scrollable=false;_scrub.max_value=1;_scrub.step=.005;_scrub.value=.5;_scrub.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_scrub.custom_minimum_size=Vector2(100,88);scrub_row.add_child(_scrub);_controls.append(_scrub);_scrub.value_changed.connect(_scrubbed)
	_phase=button(scrub_row,"Contact",_show_field_help);_phase.size_flags_horizontal=0;_phase.custom_minimum_size.x=120;_phase.tooltip_text="About the selected keyframe and controls"
	_play.tooltip_text="Charge gradually from Ready, then release at gameplay speed. Strong charges longer. Pause/Resume anywhere; authored key controls stay separate."
	_timeline.mount(self,_visual_panel,_tools_panel)
	_elbow_preset_panel=ElbowPresetPanel.new();add_child(_elbow_preset_panel);_elbow_preset_panel.mount(self,_tools_panel)
	get_tree().root.focus_entered.connect(_reset_preview_wall_clock)
	var workspace_row:=HBoxContainer.new();_edit_panel.add_child(workspace_row)
	_scene_focus=button(workspace_row,"Expand scene",func():pass);_scene_focus.toggle_mode=true
	_scene_focus.tooltip_text="Give the 3D scene more room. Phase, Play, scrub, Save and Copy stay available."
	_scene_focus.toggled.connect(_set_scene_expanded)
	_tools_toggle=button(workspace_row,"Preview tools ▸",func():pass);_tools_toggle.toggle_mode=true
	_tools_toggle.tooltip_text="View, gizmo, charge-preview and elbow-smoothing options. Pose controls remain one tap away."
	_tools_toggle.toggled.connect(_show_preview_tools)
	_style_workspace_buttons()
	var group_row:=HBoxContainer.new();_group_row=group_row;_edit_panel.add_child(group_row)
	_group=option(group_row,Fields.GROUPS);_group.hide();_group.select(6)
	_category=option(group_row,Fields.CATEGORIES);_category.item_selected.connect(_select_category)
	_joint_picker=option(group_row,["Select joint…"]+Fields.JOINT_LABELS);_joint_picker.item_selected.connect(func(i):
		if i>0:_joint_chosen(Fields.JOINT_IDS[i-1]))
	_fine_button=button(group_row,"Fine",_toggle_fine);_fine_button.toggle_mode=true;_fine_button.button_pressed=true;_fine_button.size_flags_horizontal=0
	_tools_scroll=ScrollContainer.new();_tools_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_tools_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_tools_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_tools_scroll.visible=false;_edit_panel.add_child(_tools_scroll);_tools_scroll.add_child(_tools_panel)
	var tools_scroll_adapter=preload("res://scripts/ui/mobile_pose_scroll.gd").new();_tools_scroll.add_child(tools_scroll_adapter);tools_scroll_adapter.configure(_tools_scroll)
	_scroll=ScrollContainer.new();_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_scroll.custom_minimum_size.y=160;_edit_panel.add_child(_scroll)
	_fields=VBoxContainer.new();_fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_scroll.add_child(_fields)
	var scroll_adapter=preload("res://scripts/ui/mobile_pose_scroll.gd").new();_scroll.add_child(scroll_adapter);scroll_adapter.configure(_scroll)
	var save_row:=HBoxContainer.new();_edit_panel.add_child(save_row)
	_save=button(save_row,"Save pose",_save_current);_revert=button(save_row,"Revert",_request_revert);button(save_row,"Default",_request_default)
	_status=Label.new();_status.modulate=Ui.MUTED;_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.text="Preview is private. Save applies edits to gameplay on this device.";_status.custom_minimum_size.y=54;_edit_panel.add_child(_status)
	_build_dialog();get_viewport().size_changed.connect(_layout);_layout();_select_workspace(0)
	_last_tick=Time.get_ticks_usec()

func button(parent:Node,caption:String,callback:Callable)->Button:
	var b:=Button.new();b.text=caption;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y=76*_s;b.pressed.connect(callback);parent.add_child(b);_controls.append(b)
	var symbol:String=Icons.for_caption(caption)
	if not symbol.is_empty():
		if not _icons.has(symbol):_icons[symbol]=Icons.texture(symbol)
		b.icon=_icons[symbol];b.expand_icon=false;b.add_theme_constant_override("icon_max_width",roundi(25*_s))
	return b

func _style_stage_button(b: Button, stage: int) -> void:
	var color: Color = Preview.STAGE_COLORS[stage]
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var selected: bool = state in ["pressed", "hover_pressed"]
		var style := Ui.button_style(color if selected else Ui.PANEL.lerp(color, 0.24 if state == "hover" else 0.14))
		style.border_color = color
		style.set_border_width_all(3 if selected else 1)
		b.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_focus_color"]: b.add_theme_color_override(state, color)
	for state in ["font_pressed_color", "font_hover_pressed_color"]: b.add_theme_color_override(state, Ui.PANEL)


func option(parent:Node,items:Array)->OptionButton:
	var o:=OptionButton.new();o.size_flags_horizontal=Control.SIZE_EXPAND_FILL;o.custom_minimum_size.y=76*_s
	o.fit_to_longest_item=false;o.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	for item in items:o.add_item(item)
	parent.add_child(o);_controls.append(o)
	o.get_popup().about_to_popup.connect(func():
		o.get_popup().max_size=Vector2i(roundi(get_viewport().get_visible_rect().size.x-24*_s),roundi(get_viewport().get_visible_rect().size.y*.7))
		o.get_popup().add_theme_font_size_override("font_size",roundi(24*_s))
		o.get_popup().add_theme_constant_override("v_separation",roundi(52*_s)))
	return o

func _layout()->void:
	var full:=get_viewport().get_visible_rect().size;var safe:=Layout.safe_rect(get_viewport())
	var landscape:bool=full.x>full.y
	_s=clampf(safe.size.y/900.0,.65,1.15) if landscape else minf(Layout.scale_for(full),clampf(safe.size.y/1560.0,.4,2.0));_root.theme.default_font_size=roundi(24*_s)
	_body.vertical=not landscape;_body.add_theme_constant_override("separation",roundi(12*_s))
	_content.position=safe.position+Vector2(14,12)*_s;_content.size=safe.size-Vector2(28,24)*_s
	_content.add_theme_constant_override("separation",roundi(6*_s))
	_preview.custom_minimum_size.y=220*_s if landscape else safe.size.y*(.61 if _expanded_scene else .34)
	_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL if landscape else Control.SIZE_FILL
	for c in _controls:
		if is_instance_valid(c):
			c.custom_minimum_size.y=(72 if c.has_meta("compact_pose_row") else 76)*_s
			if c is Button:c.add_theme_constant_override("icon_max_width",roundi(25*_s))
	_scroll.custom_minimum_size.y=120*_s;_tools_scroll.custom_minimum_size.y=120*_s;_status.custom_minimum_size.y=64*_s
	_phase.custom_minimum_size.x=115*_s
	_style_scrollbar()
	if is_instance_valid(_gimbal):
		_gimbal.ui_scale=_s;_gimbal.custom_minimum_size.y=310*_s;_gimbal.queue_redraw()
	if _preview.gizmo:_preview.gizmo.ui_scale=_s;_preview.gizmo.queue_redraw()
	for row in [_camera_row,_gizmo_row]:
		for control in row.get_children():control.add_theme_font_size_override("font_size",roundi(20*_s))
	_gizmo_mode.custom_minimum_size.x=154*_s
	_gizmo_hint.add_theme_font_size_override("font_size",roundi(18*_s))
	_motion_hint.add_theme_font_size_override("font_size",roundi(19*_s))
	_status.add_theme_font_size_override("font_size",roundi(20*_s))
	_timeline._label.add_theme_font_size_override("font_size",roundi(20*_s))
	_ghost_label.add_theme_font_size_override("font_size",roundi(20*_s))
	_ghost_label.custom_minimum_size.x=256*_s
	_layout_copy()
	call_deferred("_fit_content")
	if _dialog_box:
		_dialog_box.position=Vector2(20*_s,safe.position.y+safe.size.y*.24)
		_dialog_box.size=Vector2(safe.size.x-40*_s,0)

func _select_workspace(index:int)->void:
	_base=index==1;_serve=index==2;_workspace.select(index);_pose_picker.clear()
	_group.set_item_disabled(5,_serve)
	_category.set_item_disabled(8,_serve)
	if _serve and _group.selected==5:_group.select(6);_category.select(0);_selected_joint="torso"
	_definitions=ServeStore.all_definitions() if _serve else BasePoseLibrary.instance().all_definitions() if _base else PostureLibrary.instance().all_definitions()
	for d in _definitions:_pose_picker.add_item(d.display_name)
	for b in _stages:b.disabled=_base
	_scrub.editable=not _base;_play.disabled=_base
	_select_pose(0)

func _select_pose(index:int)->void:
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("",false)
	_timeline.invalidate()
	if index<0 or index>=_definitions.size():return
	_stop();_pose_picker.select(index)
	var d:Resource=_definitions[index]
	_key="serve:"+str(ServeStore.style_id(d)) if _serve else ("base:" if _base else "stroke:")+str(d.get("base_pose_id" if _base else "posture_id"))
	if not _copies.has(_key):
		_copies[_key]=d.duplicate(true)
		if not _base:PaddleRotation.normalize_pose(_copies[_key])
	_current=_copies[_key];_motion_dirty=true;_select_stage(1)
	if _elbow_preset_panel:_elbow_preset_panel.source_selected()

func _select_stage(index:int)->void:
	if _elbow_preset_panel:_elbow_preset_panel.context_changed()
	_timeline.invalidate()
	_preview.cancel_gesture()
	_clear_variant()
	_stop();_stage=clampi(index,0,2) if _has_motion() else 1;_progress=float(_stage)*.5
	_ghost_row.visible=_has_motion();_ghost_slider.editable=_has_motion()
	_stage_row.visible=_has_motion();_scrub.editable=_has_motion();_play.disabled=not _has_motion()
	_strong_play.disabled=not _has_motion();_weak_play.disabled=not _has_motion()
	_motion_hint.text="3 keys · purple Wind-up / gold Contact / cyan Finish" if _has_motion() else "Static body stance" if _base else "Ready · static paddle pose"
	for i in range(3):_stages[i].set_pressed_no_signal(i==_stage)
	_edit=ServeStore.endpoint(_current,_stage) if _serve and _stage!=1 else Path.endpoint(_current,_stage) if not _base and _stage!=1 else _current
	_scrub.set_value_no_signal(_progress);_build_fields();_refresh_preview();_refresh_status();_preview.request_camera_fit()

func _select_category(index:int)->void:
	_category.select(index)
	_group.select(5 if index==8 else 6)
	if index!=8:_selected_joint=Fields.CATEGORY_JOINTS[index]
	_build_fields()

func _build_fields()->void:
	_preview.cancel_gesture()
	for child in _fields.get_children():_fields.remove_child(child);child.queue_free()
	_controls=_controls.filter(func(c):return is_instance_valid(c) and c.is_inside_tree() and not c.is_queued_for_deletion())
	_sliders.clear();_slider_labels.clear();_body_inputs.clear()
	_angle_inputs.clear();_gimbal=null;_gimbal_axis_buttons.clear();_grip_picker=null;_grip_input=null;_grip_source=null;_body_position_status=null;_serve_contact_status=null;_foot_pitch_status=null;_elbow_guide_status=null;_upper_body_status=null
	if _edit==null:return
	var category:int=_category.selected
	_joint_picker.visible=false
	if category==8:_preview.clear_joint_selection()
	else:
		_joint_picker.select(Fields.JOINT_IDS.find(_selected_joint)+1);_preview.select_joint(_selected_joint)
	var descriptors:Array=Fields.category_fields(category,_base)
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED
	var phase:String="Body stance" if _base else "Ready" if not _has_motion() else ["Wind-up","Contact","Finish"][_stage]
	help.text=phase+" · tap number to type · ↺ last save"
	_field_help=help.text+". Fine/Normal changes horizontal slider steps. Selecting a body part does not change pose values. "
	_fields.add_child(help)
	if _serve:
		_field_help+="Serve feet are authored in Wind-up and stay planted; ball contact and held-ball hand are protected. "
		if _stage==1:
			_serve_contact_status=Label.new();_serve_contact_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_serve_contact_status.modulate=Color("ffdc62");_fields.add_child(_serve_contact_status);_sync_serve_contact_status()
	if category==0:
		_build_upper_body_rotation();descriptors=descriptors.filter(func(d):return d.field!="torso_yaw_deg")
	elif category in [2,3]:
		_build_elbow_feedback();_build_elbow_guide()
	elif category in [4,5]:
		_build_foot_pitch_help()
		button(_fields,"Shared crouch & stance…",_select_category.bind(1)).set_meta("compact_pose_row",true)
		if _serve and _stage!=0:button(_fields,"Edit Wind-up feet",_select_stage.bind(0))
	elif category==6:
		help.text+="\nBall tracking affects live idle body motion."
	elif category==8:
		help.text+="\nTiming affects gameplay, not the static keyframe."
	if category==7 and not _base:
		var modes:=HBoxContainer.new();_fields.add_child(modes)
		for mode in range(3):
			var tab:=button(modes,["Rotation","Position","Hands & grip"][mode],func():_paddle_view=mode;_build_fields());tab.toggle_mode=true;tab.button_pressed=_paddle_view==mode;tab.set_meta("compact_pose_row",true)
		if _paddle_view==0:
			_build_normalize_paddle_row()
			descriptors=descriptors.filter(func(d):return d.field in ROT or d.field.contains("signed") or d.field.contains("sign_source"))
		elif _paddle_view==1:
			descriptors=descriptors.filter(func(d):return d.field in POS or d.field=="paddle_floor_clearance")
		else:
			descriptors=descriptors.filter(func(d):return not (d.field in ROT or d.field in POS or d.field.contains("signed") or d.field.contains("sign_source") or d.field=="paddle_floor_clearance"))
	var scalar_parent:Node=_compact_section("Tilt & shape") if category==0 else _fields
	for d in descriptors:
		var field:String=d.field
		if _serve and not ServeStore.is_field_editable(_stage,field):continue
		var target:Resource=_current if category==8 else _edit
		if target.get(field)==null:continue
		if d.type=="option":
			var label:=Label.new();label.text=d.label;scalar_parent.add_child(label)
			var opt:=option(scalar_parent,d.items);opt.select(int(target.get(field)));opt.item_selected.connect(func(i):_changed(field,i));continue
		if d.type=="vector":
			var fold:=button(scalar_parent,d.label+" ▸",func():pass);fold.alignment=HORIZONTAL_ALIGNMENT_LEFT;fold.toggle_mode=true;fold.set_meta("compact_pose_row",true)
			var details:=VBoxContainer.new();details.visible=false;scalar_parent.add_child(details)
			fold.toggled.connect(func(on):details.visible=on;fold.text=d.label+(" ▾" if on else " ▸"))
			for axis in range(3):_slider(details,d,axis,target.get(field)[axis])
		else:_slider(scalar_parent,d,-1,float(target.get(field)))
	if category==1 and not _base:
		_body_position_status=Label.new();_body_position_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fields.add_child(_body_position_status);_sync_body_position_status(_preview.pose)
		var preset_start:int=_fields.get_child_count()
		_build_stance_presets()
		_collapse_tail(preset_start,"Stance presets")
	if category==7 and not _base and _paddle_view==2:
		var grip_start:int=_fields.get_child_count()
		_build_paddle_grip()
		_collapse_tail(grip_start,"Paddle-in-hand grip presets")
	if category==7 and not _base and _paddle_view==0:
		var extras_start:int=_fields.get_child_count()
		_build_paddle_rotation()
		_collapse_tail(extras_start,"Rotation rings & presets")
	_scroll.scroll_vertical=0;_sync_selected_gizmo();_sync_upper_body_status();call_deferred("_layout")

func _collapse_tail(start:int,caption:String)->void:
	var nodes:Array=[]
	for index in range(start,_fields.get_child_count()):nodes.append(_fields.get_child(index))
	var container:=_compact_section(caption)
	for child in nodes:child.reparent(container)

func _slider(parent:Node,d:Dictionary,axis:int,value:float)->void:
	var unavailable:String=_inactive_control_reason(d.field,axis)
	if not unavailable.is_empty():
		var note:=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.modulate=Ui.MUTED
		note.text=Fields.axis_label(d,axis,_is_main_hand_field(d.field))+": "+unavailable+" Stored value kept.";parent.add_child(note);return
	if axis<0 and d.field in ROT:
		_angle_slider(parent,d,value);return
	if d.type!="component" and not Fields.body_descriptor(d.field).is_empty():
		_body_slider(parent,d,axis,value);return
	var label:=Label.new();parent.add_child(label)
	var title:String=d.label if axis<0 or d.type=="component" else Fields.axis_label(d,axis,_is_main_hand_field(d.field))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);parent.add_child(row)
	var slider:=HSlider.new();slider.scrollable=false;slider.min_value=minf(d.min,value);slider.max_value=maxf(d.max,value);slider.step=float(d.step)*(.1 if _fine else 1.0);slider.value=value
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size=Vector2(120,88*_s)
	var minus:=button(row,"−",func():slider.value-=slider.step);minus.size_flags_horizontal=0;minus.custom_minimum_size.x=88*_s
	row.add_child(slider);_controls.append(slider)
	var plus:=button(row,"+",func():slider.value+=slider.step);plus.size_flags_horizontal=0;plus.custom_minimum_size.x=88*_s
	var reset:=button(row,"↺",func():_reset_field(d.field,axis));reset.tooltip_text="Reset this value to its last saved value";reset.size_flags_horizontal=0;reset.custom_minimum_size.x=76*_s
	var label_value:=func(v):label.text="%s  %s"%[title,("%.4f" if float(d.step)<.01 else "%.3f" if _fine else "%.2f")%v]
	label_value.call(value)
	_sliders[d.field+("" if axis<0 else ":"+str(axis))]=slider;slider.set_meta("pose_field_key",d.field+("" if axis<0 else ":"+str(axis)))
	_slider_labels[d.field+("" if axis<0 else ":"+str(axis))]=label_value
	slider.value_changed.connect(func(v):
		label_value.call(v)
		if axis<0:_changed(d.field,v)
		else:
			var vec:Vector3=_edit.get(d.field);vec[axis]=v;_changed(d.field,vec))

func _build_body_input_help()->void:
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED
	help.text="Tap a number to type. Fine/Normal sets slider steps."
	_field_help+=" New body entries stay within their shown limits; full body/foot turns and elbow guide rotations wrap at 360°. Joint guides steer IK, not limb length. Existing saved values stay unchanged until edited."
	help.tooltip_text=_field_help
	_fields.add_child(help)
	if not _base and (_group.selected==0 or (_group.selected==6 and _selected_joint=="hips")):
		_body_position_status=Label.new();_body_position_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fields.add_child(_body_position_status)
		_sync_body_position_status(_preview.pose)

func _compact_section(caption:String)->VBoxContainer:
	var fold:=button(_fields,caption+" ▸",func():pass)
	fold.alignment=HORIZONTAL_ALIGNMENT_LEFT;fold.toggle_mode=true;fold.set_meta("compact_pose_row",true)
	var details:=VBoxContainer.new();details.visible=false;_fields.add_child(details)
	fold.toggled.connect(func(on):details.visible=on;fold.text=caption+(" ▾" if on else " ▸"))
	return details

func _build_upper_body_rotation()->void:
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED
	help.text="Chest + both shoulders together · hips and feet stay fixed."
	help.tooltip_text="Y is the body's upright axis at the waist, not the screen's vertical direction. It follows existing body lean. Values are degrees for this keyframe; orbiting the camera does not change the axis."
	_fields.add_child(help)
	_slider(_fields,Fields.body_descriptor("torso_yaw_deg"),-1,float(_edit.torso_yaw_deg))
	_upper_body_status=Label.new();_upper_body_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_upper_body_status.modulate=Ui.MUTED;_fields.add_child(_upper_body_status)
	_field_help+=" Upper body Y turns chest and both shoulders around the waist's upright Y axis in degrees. Existing body lean tilts that axis; camera orbit does not change it. Hips/feet and paddle targets remain authored. Arms follow with IK within their reach."

func _sync_upper_body_status()->void:
	if not is_instance_valid(_upper_body_status):return
	var notes:PackedStringArray=[]
	var player=_preview.player
	for right in [true,false]:
		var arm=player.right_arm_node if right else player.left_arm_node
		var span:float=arm.upper_pivot.global_position.distance_to(arm.anatomical_wrist_world)
		var budget:float=arm.upper_arm_length+arm.forearm_length
		if span>budget+.001:notes.append(("Right" if right else "Left")+" arm target exceeds reach; reduce turn or adjust pose.")
		elif budget-span<.015:notes.append(("Right" if right else "Left")+" arm near full reach.")
	_upper_body_status.text=" ".join(notes) if not notes.is_empty() else "Y follows the waist, independent of camera · tap number to type."
	_upper_body_status.modulate=Color("ffdc62") if not notes.is_empty() else Ui.MUTED

func _body_slider(parent:Node,d:Dictionary,axis:int,value:float)->void:
	var key:String=d.field+("" if axis<0 else ":"+str(axis))
	var number_row:=HBoxContainer.new();number_row.add_theme_constant_override("separation",8);parent.add_child(number_row)
	var title:=Label.new();title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var caption:String=d.label if axis<0 else Fields.axis_label(d,axis,_is_main_hand_field(d.field))
	title.text=caption;title.tooltip_text="Range %.3f to %.3f. Tap the number to type."%[float(d.min),float(d.max)];number_row.add_child(title)
	var input:=SpinBox.new();input.min_value=d.min;input.max_value=d.max;input.allow_greater=true;input.allow_lesser=true
	# Typed requests retain sub-slider precision and are never replaced by the
	# physical solver's applied value. +/- and slider retain Fine/Normal steps.
	input.step=.0001;input.value=value;input.size_flags_horizontal=Control.SIZE_FILL;input.custom_minimum_size=Vector2(164*_s,72*_s);input.set_meta("compact_pose_row",true)
	input.get_line_edit().select_all_on_focus=true;input.get_line_edit().virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	number_row.add_child(input);_controls.append(input);_body_inputs[key]=input
	var reset:=button(number_row,"↺",func():_reset_field(d.field,axis));reset.tooltip_text="Reset this value to its last saved value";reset.size_flags_horizontal=0;reset.custom_minimum_size.x=64*_s;reset.set_meta("compact_pose_row",true)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);parent.add_child(row)
	var slider:=HSlider.new();slider.scrollable=false;slider.min_value=minf(d.min,value);slider.max_value=maxf(d.max,value)
	slider.step=float(d.step)*(.1 if _fine else 1.0);slider.value=value;slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size=Vector2(120,72*_s);slider.set_meta("compact_pose_row",true)
	var minus:=button(row,"−",func():_set_body_value(d,axis,_body_current_value(d.field,axis)-slider.step));minus.size_flags_horizontal=0;minus.custom_minimum_size.x=72*_s;minus.set_meta("compact_pose_row",true)
	row.add_child(slider);_controls.append(slider)
	var plus:=button(row,"+",func():_set_body_value(d,axis,_body_current_value(d.field,axis)+slider.step));plus.size_flags_horizontal=0;plus.custom_minimum_size.x=72*_s;plus.set_meta("compact_pose_row",true)
	_sliders[key]=slider;slider.set_meta("pose_field_key",key)
	input.value_changed.connect(func(v):if not _body_input_sync:_set_body_value(d,axis,v))
	slider.value_changed.connect(func(v):if not _body_input_sync:_set_body_value(d,axis,v))
	input.get_line_edit().text_submitted.connect(func(text):_submit_body_text(d,axis,text))



func _inactive_control_reason(field:String,axis:int)->String:
	if field in ["split_step_hop_height","lunge_distance"]:return "Inactive in the current motion system."
	if axis==1 and field in ["right_foot_offset","left_foot_offset"] and (_serve or (not _base and _edit.body_position_offset!=Vector3.ZERO)):
		return "Height locked to the court floor."
	if field=="swing_path_blend" and not _base and _current.family==1:
		var all_gripping:bool=true
		for stage in [0,1,2]:
			if Path.endpoint(_current,stage).left_hand_mode!=1:all_gripping=false
		if all_gripping:return "Two-hand Backhand uses a linked body-frame path."
	if _base:
		var states={"recovery_time":_preview.player.BasePoseState.RECOVERY_READY,"landing_lockout_time":_preview.player.BasePoseState.LANDING_RECOVERY,"jump_window":_preview.player.BasePoseState.JUMP_TAKEOFF}
		if states.has(field) and _current.base_pose_id!=states[field]:return "Used only by the corresponding recovery / landing / takeoff stance."
	return ""

func _is_main_hand_field(field:String)->bool:
	return field == ("left_hand_offset" if not _base and _current!=null and _current.paddle_hand==1 else "right_hand_offset")

func _guide_elbow_position(field:String)->Vector3:
	if not (field.ends_with("_shoulder_rotation_deg") or field.ends_with("_elbow_pole")):return Vector3.INF
	var arm=_preview.player.left_arm_node if field.begins_with("left") else _preview.player.right_arm_node
	return arm.forearm_pivot.global_position

func _build_elbow_feedback()->void:
	_elbow_guide_status=Label.new();_elbow_guide_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_elbow_guide_status.modulate=Ui.MUTED;_fields.add_child(_elbow_guide_status)
	_sync_elbow_feedback()

func _sync_elbow_feedback()->void:
	if not is_instance_valid(_elbow_guide_status):return
	var text:String="Elbow guides steer bend direction, not shoulder position. Grip/wrist and reach limits apply."
	var player=_preview.player
	for left in [false,true]:
		if _group.selected==6 and (_selected_joint=="left_elbow")!=left:continue
		var arm=player.left_arm_node if left else player.right_arm_node
		var shoulder:Vector3=arm.upper_pivot.global_position
		var wrist:Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
		var span:float=shoulder.distance_to(wrist)
		var limit:float=arm.upper_arm_length+arm.forearm_length
		if limit-span<.015:text+=" %s arm near full reach: little bend freedom." % ("Left" if left else "Right")
	_elbow_guide_status.text=text

func _body_current_value(field:String,axis:int)->float:
	return float(_edit.get(field)) if axis<0 else float(_edit.get(field)[axis])

func _submit_body_text(d:Dictionary,axis:int,text:String)->void:
	var clean:=text.strip_edges()
	if not clean.is_valid_float() or not is_finite(clean.to_float()):
		_sync_body_input(d,axis);_refresh_status("Enter a finite number. The previous value is kept.");return
	_set_body_value(d,axis,clean.to_float())

func _sync_body_input(d:Dictionary,axis:int)->void:
	var key:String=d.field+("" if axis<0 else ":"+str(axis))
	var value:=_body_current_value(d.field,axis)
	_body_input_sync=true
	if _body_inputs.has(key):_body_inputs[key].set_value_no_signal(value)
	if _sliders.has(key):_sliders[key].set_value_no_signal(value)
	_body_input_sync=false

func _set_body_value(d:Dictionary,axis:int,requested:float)->void:
	if _edit==null or (_serve and not ServeStore.is_field_editable(_stage,d.field)):return
	var value:float=Fields.body_input_value(d,requested)
	if not is_finite(value):
		_sync_body_input(d,axis);_refresh_status("Enter a finite number. The previous value is kept.");return
	if d.field in FOOT_GUARDED_FIELDS and not is_equal_approx(value,_body_current_value(d.field,axis)):
		var reason:String=_body_edit_limit(d,axis,value)
		if not reason.is_empty():
			_sync_body_input(d,axis);_refresh_status("Requested %.3f, kept %.3f. "%[value,_body_current_value(d.field,axis)]+reason);return
	if axis<0:_changed(d.field,value)
	else:
		var vector:Vector3=_edit.get(d.field);vector[axis]=value;_changed(d.field,vector)
	_sync_body_input(d,axis)
	if not is_equal_approx(requested,value):
		_refresh_status(("Full turn wrapped to %.3f°. " % value if d.field in Fields.WRAPPED_BODY_FIELDS else "Entry limited to %.3f (range %.3f to %.3f). " % [value,float(d.min),float(d.max)])+"Save when ready.")

func _body_edit_limit(d:Dictionary,axis:int,value:float)->String:
	if _timeline.active or not is_equal_approx(_progress,float(_stage)*.5):
		_timeline.invalidate();_stop();_progress=float(_stage)*.5;_refresh_preview()
	# Simulate privately, validate anchored feet and nominal reach, restore,
	# then commit only the existing authored setter if the request is safe.
	var original:PostureDefinition=_preview.pose
	if original==null:return ""
	var player=_preview.player
	var foot_baseline:Dictionary=FootEditValidator.snapshot(player)
	var upper_only:bool=d.field=="torso_yaw_deg"
	var fixed:Array=[player.body_pivot,player.body_pivot.get_node("HipsMesh"),player.right_leg_node.foot_pivot,player.left_leg_node.foot_pivot,player.paddle_node]
	var before:Array=[]
	for node in fixed:before.append(node.global_transform)
	var arm_limits:Array=[]
	for arm in [player.right_arm_node,player.left_arm_node]:
		arm_limits.append(maxf(arm.upper_arm_length+arm.forearm_length,arm.upper_pivot.global_position.distance_to(arm.anatomical_wrist_world)))
	var candidate:PostureDefinition=original.duplicate(true)
	if axis<0:candidate.set(d.field,value)
	else:
		var vector:Vector3=candidate.get(d.field);vector[axis]=value;candidate.set(d.field,vector)
	_preview.show_pose(candidate)
	var validation:Dictionary=FootEditValidator.validate(player,candidate,foot_baseline)
	var limited:=false
	if upper_only:
		for index in range(fixed.size()):
			var old:Transform3D=before[index]
			var now:Transform3D=fixed[index].global_transform
			if old.origin.distance_to(now.origin)>.00002 or not old.basis.orthonormalized().is_equal_approx(now.basis.orthonormalized()) or old.basis.get_scale().distance_to(now.basis.get_scale())>.00005:limited=true
		for index in range(2):
			var arm=player.right_arm_node if index==0 else player.left_arm_node
			if arm.upper_pivot.global_position.distance_to(arm.anatomical_wrist_world)>arm_limits[index]+.00002:limited=true
	_preview.show_pose(original)
	if not validation.accepted:return "Reach limit: "+str(validation.violations[0])+". Change not applied; reduce the move or explicitly edit the foot."
	return "Reach limit: that turn would move hips, feet, paddle or exceed arm reach. Reduce the turn or adjust Hips & stance first." if limited else ""


func _changed(field:String,value:Variant,refresh:bool=true)->void:
	_timeline.invalidate()
	if not _base:value=PaddleRotation.field_value(field,value)
	if (value is float and not is_finite(value)) or (value is Vector3 and not value.is_finite()):
		_refresh_status("Enter a finite number. The previous value is kept.");return
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("Pose edited. Previous smoothing preview cleared.",true)
	var elbow_before:Vector3=_guide_elbow_position(field)
	_clear_variant()
	_stop()
	# Endpoints store paddle deltas and may inherit missing body fields from
	# Contact. Freeze only this selected field before changing that shared base.
	var preserved_endpoints:Array=[]
	if not _base and _stage==1 and _has_motion() and (field in POS or field in ROT or field in Keyframe.FIELDS):
		preserved_endpoints=[Path.endpoint(_current,0),Path.endpoint(_current,2)]
	if _group.selected==5:_current.set(field,value)
	else:
		_edit.set(field,value)
		if not _base and _stage!=1:
			if field in POS or field in ROT:
				var offset:=Vector3.ZERO;var rotation:=Vector3.ZERO
				for i in range(3):offset[i]=_edit.get(POS[i])-_current.get(POS[i]);rotation[i]=_edit.get(ROT[i])-_current.get(ROT[i])
				_current.set("charge_paddle_offset" if _stage==0 else "ft_paddle_offset",offset)
				_current.set("charge_paddle_rotation_deg" if _stage==0 else "ft_paddle_rotation_deg",PaddleRotation.vector(rotation))
			elif field in Keyframe.FIELDS:
				var property:String="windup_body" if _stage==0 else "follow_through_body"
				var keyframe:Resource=_current.get(property)
				if keyframe==null:keyframe=Keyframe.new();keyframe.capture(_edit);_current.set(property,keyframe)
				keyframe.values[field]=value
			else:_current.set(field,value)
	for index in range(preserved_endpoints.size()):
		var endpoint:Resource=preserved_endpoints[index]
		if field in POS or field in ROT:
			var property:String=("charge_paddle_offset" if index==0 else "ft_paddle_offset") if field in POS else ("charge_paddle_rotation_deg" if index==0 else "ft_paddle_rotation_deg")
			var delta:Vector3=_current.get(property)
			delta[(POS if field in POS else ROT).find(field)]=endpoint.get(field)-_current.get(field)
			_current.set(property,PaddleRotation.vector(delta) if field in ROT else delta)
		else:
			var property:String="windup_body" if index==0 else "follow_through_body"
			var keyframe:Resource=_current.get(property)
			if keyframe==null:keyframe=Keyframe.new();_current.set(property,keyframe)
			if not keyframe.values.has(field):keyframe.values[field]=endpoint.get(field)
	if not _base and not _serve and field in ["right_elbow_pole","left_elbow_pole"]:_update_elbow_path(field,value)
	_motion_dirty=true;_dirty[_key]=true;_progress=float(_stage)*.5;_scrub.set_value_no_signal(_progress)
	if refresh:
		_refresh_preview();_refresh_status()
		if elbow_before.is_finite():
			var moved:float=elbow_before.distance_to(_guide_elbow_position(field))*100.0
			var side:String="Left" if field.begins_with("left") else "Right"
			var notice:String="%s elbow moved %.2f cm. " % [side,moved]
			if moved<.1:notice+="Very small effect: guide direction, grip/wrist alignment or arm reach limits this pose. "
			_refresh_status(notice+"Requested guide kept; Save applies it to gameplay.")
	_sync_rotation_controls()
	_sync_grip_controls()
	if field=="paddle_hand":call_deferred("_build_fields")

func _refresh_preview()->void:
	if _current==null:return
	var display_source:Resource=_elbow_preset_panel.preview_source(_current) if _elbow_preset_panel else _current
	if _variant_mode!=0 and (_motion_dirty or _variant==null):
		_variant=WindupVariants.new();_variant.configure(display_source,_variant_mode,ServeStore.sample if _serve else Callable(),_preview.player)
	var p:PostureDefinition=display_source.to_preview_posture(PostureLibrary.instance().get_def(20)) if _base else _variant.sample(display_source,_progress) if _variant_mode!=0 else ServeStore.sample(display_source,_progress) if _serve else Path.sample(display_source,_progress)
	p=_timeline.pose(p)
	if _elbow_preset_panel:p=_elbow_preset_panel.preview_pose(p)
	_preview.show_pose(p)
	_sync_body_position_status(p)
	_sync_upper_body_status()
	_sync_foot_pitch_status()
	_sync_elbow_feedback()
	_sync_serve_contact_status()
	if _motion_dirty:
		_preview.set_motion_sampler(_variant.sample if _variant_mode!=0 else ServeStore.sample if _serve else Callable())
		_preview.set_motion(null if _base else display_source,_has_motion())
		_preview.set_contact_preview(null if _base else display_source,ServeStore.style_id(_current) if _serve else -1,_has_motion());_motion_dirty=false
	_timeline.refresh_joint_guide()
	_preview.set_preview_progress(_progress)
	_phase.text="Body stance" if _base else "Ready" if not _has_motion() else ("Wind-up" if is_equal_approx(_progress,0) else "Contact" if is_equal_approx(_progress,.5) else "Finish" if is_equal_approx(_progress,1) else "Preview")
	if _variant_mode!=0:_motion_hint.text=_variant.status_text()
	_sync_selected_gizmo()
	_timeline.after_refresh()
	if _elbow_preset_panel:_elbow_preset_panel.after_refresh()

func _select_gizmo_mode(_index:int)->void:
	_preview.cancel_gesture();_sync_selected_gizmo();_save_gizmo_view();_preview.request_camera_fit()

func _toggle_gizmo()->void:
	_preview.cancel_gesture();_sync_selected_gizmo();_save_gizmo_view();_preview.request_camera_fit()

func _save_gizmo_view()->void:
	if ViewSettings.save_gizmo(_gizmo_mode.selected,_gizmo_show.button_pressed)!=OK:
		_refresh_status("Gizmo setting applies for now, but could not be saved on this device.")

func _sync_selected_gizmo()->void:
	if _edit==null or not is_instance_valid(_gizmo_mode):return
	var id:String=_preview.selected_joint
	var gripping:bool=_preview.player.arm_ik._support_mode(_preview.pose)==1 if _preview.pose!=null else false
	var move_channels:Dictionary=GizmoFields.channels(id,false,_edit,_base,_serve,_stage,gripping)
	var rotate_channels:Dictionary=GizmoFields.channels(id,true,_edit,_base,_serve,_stage,gripping)
	_gizmo_mode.set_item_disabled(0,not GizmoFields.available(move_channels))
	_gizmo_mode.set_item_disabled(1,not GizmoFields.available(rotate_channels))
	_gizmo_channels=move_channels if _gizmo_mode.selected==0 else rotate_channels
	var at_key:bool=not _playing and not _timeline.active and _variant_mode==0 and is_equal_approx(_progress,float(_stage)*.5)
	var note:String=_gizmo_channels.note
	if not at_key and not id.is_empty():note="Select a keyframe to edit · preview only"
	_gizmo_hint.text=note+" · drag elsewhere to orbit"
	_gizmo_mode.tooltip_text="Move: "+str(move_channels.note)+"\nRotate: "+str(rotate_channels.note)
	_gizmo_show.tooltip_text="Show or hide the selected-part gizmo"
	_gizmo_show.text="Show" if _gizmo_show.button_pressed else "Hidden"
	_preview.gizmo.visible=_gizmo_show.button_pressed
	var stage_name:String="Stance" if _base else "Ready" if not _has_motion() else ["Wind-up","Contact","Finish"][_stage]
	var caption:String=("Move" if _gizmo_mode.selected==0 else "Rotate")+" · "+stage_name+" · "+("Bend guide" if id.ends_with("elbow") or id.ends_with("knee") else str(Preview.JOINT_NAMES.get(id,"")))
	_preview.gizmo.configure(_gizmo_channels.axes,caption,at_key and GizmoFields.available(_gizmo_channels),_gizmo_mode.selected)
	_preview.gizmo.world_axes=GizmoAxes.for_selection(_preview.player,_preview.pose,id,_gizmo_mode.selected==1)
	_preview.gizmo.sync_scene()

func _drag_selected_gizmo(axis:int,amount:float)->void:
	if _edit==null or _group.selected!=6 or axis<0 or axis>2:return
	var channel:Dictionary=_gizmo_channels.axes[axis]
	if channel.is_empty():return
	var field:String=channel.field
	var component:int=channel.component
	if _serve and not ServeStore.is_field_editable(_stage,field):return
	if field in ROT:
		_rotate_paddle_axis(ROT.find(field),amount);return
	var descriptor:Dictionary=Fields.body_descriptor(field)
	if descriptor.is_empty():
		for candidate in Fields.fields(4,false):
			if candidate.field==field:descriptor=candidate;break
	if descriptor.is_empty():return
	var current:float=_body_current_value(field,component)
	if component>=0 and field.ends_with("_pole") and (_edit.get(field) as Vector3).length_squared()<.00000001:
		# Zero means an automatic guide in the solver, not world origin. Start
		# from that same guide so the first tiny drag cannot flip the limb.
		var guide:=Vector3(0,.5,1) if field.contains("knee") else Vector3(-.5 if field.begins_with("left") else .5,-1,-.5)
		_changed(field,guide,false);current=guide[component]
	var requested:float=current+amount
	if not Fields.body_descriptor(field).is_empty():
		if field.ends_with("hand_offset") and _gizmo_channels.space=="paddle":
			requested=clampf(requested,-.05,.05)
		_set_body_value(descriptor,component,requested)
	else:
		_changed(field,clampf(requested,descriptor.min,descriptor.max))
	# Update every vector component after an automatic-guide seed. Existing
	# sliders, typed numbers, paddle gimbal and save payload use one value path.
	for key in _body_inputs:
		var chunks:PackedStringArray=key.split(":")
		if chunks[0]==field:_sync_body_input(descriptor,int(chunks[1]) if chunks.size()>1 else -1)
	if _sliders.has(field):
		_sliders[field].set_value_no_signal(float(_edit.get(field)))
		if _slider_labels.has(field):_slider_labels[field].call(float(_edit.get(field)))

func _update_ghost_label()->void:
	var count:=int(_ghost_slider.value)
	_ghost_label.text="Ghosts: Off" if count==0 else "Ghosts: %d / gap · %d total"%[count,count*2]

func _ghost_count_changed(value:float)->void:
	_preview.set_inbetween_count(int(value));_update_ghost_label()
	if ViewSettings.save_inbetween_count(int(value))!=OK:
		_refresh_status("Ghost count applies for now, but could not be saved on this device.")

func _scrubbed(value:float)->void:
	if _elbow_preset_panel:_elbow_preset_panel.context_changed()
	_timeline.invalidate()
	_stop();_progress=value;_refresh_preview()

func _toggle_play()->void:
	if _elbow_preset_panel:_elbow_preset_panel.context_changed()
	_preview.cancel_gesture()
	if not _has_motion():return
	if _variant_mode!=0:
		_clear_variant();_stop();_progress=0;_refresh_preview()
	if _playing:_stop();_resume_playback=true;_play.text="Resume";return
	_playing=true
	_timeline.start(_resume_playback)
	if not _resume_playback:_progress=0
	_resume_playback=false;_play.text="Pause";_play.icon=_icons["stop"];_last_tick=Time.get_ticks_usec()
	_sync_selected_gizmo()

func _stop()->void:
	_playing=false;_resume_playback=false
	if _play:_play.text="Play";_play.icon=_icons.get("play")
	_update_variant_buttons()

func _clear_variant()->void:
	if _variant_mode==0:return
	if _elbow_preset_panel:_elbow_preset_panel.context_changed()
	_variant_mode=0;_variant=null;_motion_dirty=true
	if is_instance_valid(_motion_hint):_motion_hint.text="3 keys · purple Wind-up / gold Contact / cyan Finish"
	_update_variant_buttons()

func _play_variant(mode:int)->void:
	if _elbow_preset_panel:_elbow_preset_panel.context_changed()
	if not _has_motion():return
	if _variant_mode==mode and _playing:
		_stop();_resume_playback=true;_update_variant_buttons();return
	if _variant_mode!=mode:
		_stop();_variant_mode=mode;_variant=null;_motion_dirty=true;_progress=0
	elif not _resume_playback:_progress=0
	_timeline.start(_resume_playback)
	_playing=true;_resume_playback=false;_last_tick=Time.get_ticks_usec();_scrub.set_value_no_signal(_progress)
	_refresh_preview();_update_variant_buttons()

func _update_variant_buttons()->void:
	for mode in [1,2]:
		var b:Button=_strong_play if mode==1 else _weak_play
		if not is_instance_valid(b):continue
		b.set_pressed_no_signal(_variant_mode==mode)
		b.icon=_icons.get("stop") if _variant_mode==mode and _playing else _icons.get("play")

func _reset_preview_wall_clock()->void:
	_last_tick=Time.get_ticks_usec()

func _process(_delta:float)->void:
	# Pause/solo-focus time scale cannot distort the private preview clock.
	var now:=Time.get_ticks_usec();var dt:=maxf(float(now-_last_tick)/1000000.0,0.0);_last_tick=now
	if not _playing or _dialog.visible:return
	if get_tree().root.get_node("PauseController")._focus_paused:return
	if _timeline.advance(dt):_stop()
	_scrub.set_value_no_signal(_progress);_refresh_preview()

func _refresh_status(message:String="")->void:
	_save.disabled=not _dirty.has(_key);_revert.disabled=not _dirty.has(_key)
	_status.text=message if not message.is_empty() else ("Unsaved preview · Save changes gameplay on this device." if _dirty.has(_key) else "Preview is private. Save applies edits to gameplay on this device.")
	if message.is_empty() and _current is PostureDefinition and not _current.elbow_preset_bake.is_empty():
		_status.text="Authored edits affect gameplay. Saved elbow smoothing remains stroke-only."
	if message.is_empty() and is_instance_valid(_preview.player):
		var limited:PackedStringArray=[]
		for right in [true,false]:
			var leg=_preview.player.right_leg_node if right else _preview.player.left_leg_node
			if "reach_report" in leg and bool(leg.reach_report.get("limited",false)):limited.append("Right" if right else "Left")
		if not limited.is_empty():_status.text="/".join(limited)+" leg reach limit in this pose. Existing saved values are kept."


func _publish(value:Resource)->void:
	var is_base:bool=value is BasePoseDefinition
	var live:Resource=BasePoseLibrary.instance().get_def(value.base_pose_id) if is_base else PostureLibrary.instance().get_def(value.posture_id)
	Store.copy_values(value,live);poses_saved.emit()

func _save_key(key:String)->bool:
	var err:Error=ServeStore.save(_copies[key]) if key.begins_with("serve:") else Store.save(_copies[key])
	if err!=OK:_refresh_status("Could not save: "+(ServeStore.last_error if key.begins_with("serve:") else Store.last_error)+". Edits kept.");return false
	if key.begins_with("serve:"):
		ServeStore.copy_values(_copies[key],ServeStore.get_def(ServeStore.style_id(_copies[key])));poses_saved.emit()
	else:_publish(_copies[key])
	_dirty.erase(key);return true

func _save_current()->void:
	if _save_key(_key):
		var core_only:bool=_current is PostureDefinition and not _current.elbow_preset_bake.is_empty()
		_refresh_status("Saved. Authored edits affect gameplay; elbow smoothing remains stroke-only." if core_only else "Saved on this device. Gameplay will use this pose.")

func _request_revert()->void:
	_confirm("Discard unsaved changes to this pose?",[["Revert pose",_revert_current],["Keep editing",_hide_dialog]])

func _revert_current()->void:
	_copies.erase(_key);_dirty.erase(_key);_rotation_undo.erase(_key);_hide_dialog();_select_pose(_pose_picker.selected)

func _request_default()->void:
	_confirm("Restore this pose's packaged default? This removes its saved edits on this device. An active global main grip is retained.",[["Restore default",_reset_default],["Keep editing",_hide_dialog]])

func _reset_default()->void:
	var def:Resource=ServeStore.packaged_default(ServeStore.style_id(_current)) if _serve else Store.packaged_default(int(_current.get("base_pose_id" if _base else "posture_id")),_base)
	if def==null:_hide_dialog();_refresh_status("Packaged default unavailable. Existing pose kept.");return
	var err:Error=ServeStore.reset(_current) if _serve else Store.reset(_current)
	if err!=OK:_hide_dialog();_refresh_status("Could not restore default: "+(ServeStore.last_error if _serve else Store.last_error));return
	_rotation_undo.erase(_key)
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("",false)
	GripStore.apply_to_definition(def,true)
	if _serve:ServeStore.copy_values(def,ServeStore.get_def(ServeStore.style_id(_current)));poses_saved.emit()
	else:_publish(def)
	_copies[_key]=def.duplicate(true);_current=_copies[_key];_motion_dirty=true;_dirty.erase(_key);_hide_dialog();_select_stage(_stage);_refresh_status("Packaged default restored and saved.")

func close()->void:
	if _closing:return
	if is_instance_valid(_copy_layer) and _copy_layer.visible:
		if _copy_text.get_menu().visible:_copy_text.get_menu().hide()
		else:_hide_copy()
		return
	for control in _controls:
		if is_instance_valid(control) and control is OptionButton and control.get_popup().visible:
			control.get_popup().hide()
			return
	if _dialog.visible:_hide_dialog();return
	_stop();_preview.cancel_gesture()
	if not _dirty.is_empty():
		_confirm("Save edited poses before going back to Pause?",[["Save all & back",_save_and_close],["Discard & back",_finish_close],["Keep editing",_hide_dialog]])
	else:_finish_close()

func _save_and_close()->void:
	for key in _dirty.keys():
		if not _save_key(key):_hide_dialog();return
	_finish_close()

func _finish_close()->void:
	if _closing:return
	if is_instance_valid(_gimbal):_gimbal.cancel_gesture()
	_closing=true;_stop();_preview.cancel_gesture()
	if _elbow_preset_panel:
		_elbow_preset_panel.prepare_close()
		while _elbow_preset_panel.busy():await get_tree().process_frame
	editor_closed.emit()

func _build_dialog()->void:
	_dialog=Control.new();_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_dialog.mouse_filter=Control.MOUSE_FILTER_STOP;_root.add_child(_dialog)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.8);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_dialog.add_child(shade)
	_dialog_box=PanelContainer.new();_dialog_box.minimum_size_changed.connect(func(): _dialog_box.size.y = _dialog_box.get_combined_minimum_size().y);_dialog_box.add_theme_stylebox_override("panel",Ui.panel_style());_dialog.add_child(_dialog_box)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",16);_dialog_box.add_child(box)
	_dialog_title=Label.new();_dialog_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(_dialog_title)
	_dialog_buttons=VBoxContainer.new();_dialog_buttons.add_theme_constant_override("separation",12);box.add_child(_dialog_buttons);_dialog.hide()

func _confirm(caption:String,actions:Array)->void:
	_stop();_preview.cancel_gesture();_dialog_title.text=caption
	if is_instance_valid(_gimbal):_gimbal.cancel_gesture()
	for child in _dialog_buttons.get_children():_dialog_buttons.remove_child(child);child.queue_free()
	for action in actions:button(_dialog_buttons,action[0],action[1])
	_dialog.show();_layout();call_deferred("_layout")

func _hide_dialog()->void:
	_dialog.hide();_last_tick=Time.get_ticks_usec()


func _copy_current_pose()->void:
	_stop();_preview.cancel_gesture()
	var json:String=ServeStore.export_pose_json(_current,_stage) if _serve else Store.export_pose_json(_current,_stage if not _base else 1)
	if json.is_empty():
		_refresh_status("Could not copy pose: "+(ServeStore.last_error if _serve else Store.last_error))
		return
	var kind:String="Serve pose" if _serve else "Body stance" if _base else "Stroke pose"
	var phase:String="Body stance" if _base else "Ready (static)" if not _has_motion() else ["Wind-up","Contact","Finish"][_stage]
	var scope:String="Whole selected body stance" if _base else "Whole selected static Ready pose" if not _has_motion() else "Whole selected pose, including Wind-up, Contact and Finish"
	_copy_payload="Pose: %s\nKind: %s\nSelected phase: %s (context only)\nScope: %s\n\nThis is the data of this pose. Update this pose and apply it to the app.\n\n%s"%[_current.display_name,kind,phase,scope,json]
	if not is_instance_valid(_copy_layer):_build_copy_view()
	_copy_text.deselect();_copy_text.set_caret_line(0);_copy_text.set_caret_column(0)
	_copy_text.set_line_as_first_visible(0);_copy_text.scroll_vertical=0
	_copy_text.text=_copy_payload
	_copy_text.set_caret_line(0);_copy_text.set_caret_column(0)
	_copy_text.scroll_vertical=0;_copy_text.scroll_horizontal=0
	_copy_layer.show();_layout_copy();call_deferred("_layout_copy")
	_copy_to_clipboard()

func _build_copy_view()->void:
	_copy_layer=Control.new();_copy_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_copy_layer.mouse_filter=Control.MOUSE_FILTER_STOP;_root.add_child(_copy_layer)
	var backdrop:=ColorRect.new();backdrop.color=Ui.PANEL;backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_copy_layer.add_child(backdrop)
	_copy_box=VBoxContainer.new();_copy_box.add_theme_constant_override("separation",12);_copy_layer.add_child(_copy_box)
	var header:=HBoxContainer.new();_copy_box.add_child(header)
	var title:=Label.new();title.text="POSE JSON FOR CHAT";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var back_button:=button(header,"Back",_hide_copy);back_button.size_flags_horizontal=0
	_copy_status=Label.new();_copy_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_copy_status.custom_minimum_size.y=90*_s;_copy_box.add_child(_copy_status)
	var actions:=HBoxContainer.new();_copy_box.add_child(actions)
	button(actions,"Copy again",_copy_to_clipboard)
	button(actions,"Select all",func():_copy_text.grab_focus();_copy_text.select_all())
	_copy_text=TextEdit.new();_copy_text.editable=false;_copy_text.virtual_keyboard_enabled=false
	_copy_text.middle_mouse_paste_enabled=false;_copy_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	_copy_text.size_flags_vertical=Control.SIZE_EXPAND_FILL;_copy_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_copy_text.custom_minimum_size.y=120*_s
	var font:=SystemFont.new();font.font_names=PackedStringArray(["DejaVu Sans Mono","monospace"])
	_copy_text.add_theme_font_override("font",font)
	_copy_text.add_theme_color_override("font_color",Ui.INK)
	_copy_text.add_theme_color_override("font_readonly_color",Ui.INK)
	var panel:=Ui.panel_style();panel.bg_color=Color("0b1c27")
	_copy_text.add_theme_stylebox_override("normal",panel);_copy_text.add_theme_stylebox_override("read_only",panel)
	_copy_box.add_child(_copy_text)

func _layout_copy()->void:
	if not is_instance_valid(_copy_layer):return
	var safe:=Layout.safe_rect(get_viewport())
	_copy_box.position=safe.position+Vector2(14,12)*_s
	_copy_box.size=safe.size-Vector2(28,24)*_s
	_copy_box.add_theme_constant_override("separation",roundi(12*_s))
	_copy_status.custom_minimum_size.y=90*_s
	_copy_text.custom_minimum_size.y=120*_s
	_copy_text.add_theme_font_size_override("font_size",roundi(20*_s))

func _copy_to_clipboard()->void:
	# User-triggered writes only. Never read, monitor or automatically import clipboard contents.
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(_copy_payload)
		_copy_status.text="Copied this pose's current values. Paste into chat when ready. Copy does not Save or change gameplay."
	else:
		_copy_status.text="Select the text below and copy it for chat. Clipboard access is unavailable here. Nothing has been saved."
		_copy_text.select_all()

func _hide_copy()->void:
	if is_instance_valid(_copy_layer):
		_copy_text.deselect();_copy_text.set_caret_line(0);_copy_text.set_line_as_first_visible(0);_copy_text.scroll_vertical=0;_copy_layer.hide()
	_copy_action.grab_focus()

func _has_motion()->bool:
	return not _base and _current is PostureDefinition and (_serve or _current.posture_id!=20)

func _style_scrollbar()->void:
	for scroll in [_scroll,_tools_scroll]:
		var bar:VScrollBar=scroll.get_v_scroll_bar()
		bar.custom_minimum_size.x=58*_s
		for state in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
			var style:=StyleBoxFlat.new()
			style.bg_color=Ui.SURFACE if state=="scroll" else Ui.BLUE if state=="grabber_pressed" else Ui.ACCENT
			style.content_margin_left=24*_s;style.content_margin_right=24*_s
			style.content_margin_top=30*_s;style.content_margin_bottom=30*_s
			style.set_corner_radius_all(roundi(16*_s));bar.add_theme_stylebox_override(state,style)

func _toggle_fine()->void:
	_fine=not _fine;_fine_button.text="Fine" if _fine else "Normal";_build_fields()

func _reset_field(field:String,axis:int)->void:
	var saved:Resource=ServeStore.get_def(ServeStore.style_id(_current)) if _serve else BasePoseLibrary.instance().get_def(_current.base_pose_id) if _base else PostureLibrary.instance().get_def(_current.posture_id)
	var source:Resource=ServeStore.endpoint(saved,_stage) if _serve and _stage!=1 else Path.endpoint(saved,_stage) if not _base and _stage!=1 and _group.selected!=5 else saved
	var value:Variant=source.get(field)
	if axis>=0:
		var vector:Vector3=_edit.get(field);vector[axis]=value[axis];value=vector
	_changed(field,value);_build_fields()

func _style_workspace_buttons()->void:
	# Quiet secondary navigation; selected modes use the scene's cool-blue palette.
	for control in [_scene_focus,_tools_toggle]:
		for state in ["normal","hover","pressed","hover_pressed"]:
			var selected:bool=state in ["pressed","hover_pressed"]
			var style:=Ui.button_style(Color("234a5c") if selected else Color("182f3e"))
			style.border_color=Ui.BLUE if selected else Color("365566")
			style.set_border_width_all(1);style.set_corner_radius_all(12)
			control.add_theme_stylebox_override(state,style)
		control.add_theme_color_override("font_color",Ui.BLUE)
		control.add_theme_color_override("font_pressed_color",Ui.INK)

func _set_scene_expanded(expanded:bool)->void:
	_expanded_scene=expanded
	_scene_focus.set_pressed_no_signal(expanded)
	_scene_focus.text="Show controls" if expanded else "Expand scene"
	# End a live drag before its projection/layout changes; do not restart playback.
	_preview.cancel_gesture()
	if expanded:_tools_toggle.set_pressed_no_signal(false)
	_update_workspace_visibility()
	_layout()

func _show_preview_tools(show_tools:bool)->void:
	if show_tools and _expanded_scene:
		_expanded_scene=false;_scene_focus.set_pressed_no_signal(false);_scene_focus.text="Expand scene"
	_tools_toggle.set_pressed_no_signal(show_tools)
	_preview.cancel_gesture()
	_update_workspace_visibility()
	_layout()

func _update_workspace_visibility()->void:
	_title.text=str(_current.display_name) if _expanded_scene and _current else "POSE EDITOR"
	var tools_visible:bool=_tools_toggle.button_pressed and not _expanded_scene
	_picker_row.visible=not _expanded_scene
	_group_row.visible=not _expanded_scene and not tools_visible
	_scroll.visible=not _expanded_scene and not tools_visible
	_tools_scroll.visible=tools_visible
	_tools_toggle.text="Pose controls ◂" if tools_visible else "Preview tools ▸"

func _fit_content()->void:
	if not is_instance_valid(_preview) or not is_instance_valid(_tools_scroll):return
	var landscape:bool=get_viewport().get_visible_rect().size.x>get_viewport().get_visible_rect().size.y
	var safe:=Layout.safe_rect(get_viewport())
	# The scene and transport never scroll out of sight. Secondary options scroll
	# inside the same bounded space as the manual inspector, above a pinned Save.
	var natural:float=_visual_panel.get_combined_minimum_size().y
	if not landscape:
		var outside:float=_content.get_combined_minimum_size().y-_body.get_combined_minimum_size().y
		var transport:float=natural-_preview.get_combined_minimum_size().y
		var available:float=_content.size.y-outside-_edit_panel.get_combined_minimum_size().y-_body.get_theme_constant("separation")-transport
		var target:float=minf(safe.size.y*(.61 if _expanded_scene else .34),maxf(160*_s,available))
		if not is_equal_approx(_preview.custom_minimum_size.y,target):
			_preview.custom_minimum_size.y=target
			natural=_visual_panel.get_combined_minimum_size().y
	_visual_scroll.custom_minimum_size.y=0 if landscape else natural
	_visual_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL if landscape else Control.SIZE_FILL
	_visual_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_content.size=safe.size-Vector2(28,24)*_s

func _joint_chosen(id:String)->void:
	if not id in Fields.JOINT_IDS:return
	_selected_joint=id;_group.select(6);_category.select(Fields.category_for_joint(id));_joint_picker.select(Fields.JOINT_IDS.find(id)+1)
	if id.ends_with("hand"):_paddle_view=2
	elif id=="paddle":_paddle_view=0
	_preview.select_joint(id);_build_fields();_preview.request_camera_fit()

func _show_field_help()->void:
	_confirm(_field_help,[["Keep editing",_hide_dialog]])

func _build_elbow_guide()->void:
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.text="Bend −/+ swivels the guide around the arm. Grip and body set its limits."
	_fields.add_child(help)
	var row:=HBoxContainer.new();_fields.add_child(row)
	button(row,"Bend −",_swivel_elbow_guide.bind(-1));button(row,"Bend +",_swivel_elbow_guide.bind(1))
	button(row,"Paddle target",_joint_chosen.bind("paddle"))
	var hint:=Label.new();hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.modulate=Ui.MUTED
	hint.text="Fine: 5° / Normal: 15° around the arm. A nearly straight arm has little bend to steer. Guide position uses meters; guide rotation uses degrees about stance axes. Grip/wrist limits may reduce both."
	_fields.add_child(hint)

func _swivel_elbow_guide(direction:int)->void:
	if not _selected_joint in ["right_elbow","left_elbow"] or _edit==null:return
	var left:bool=_selected_joint=="left_elbow"
	var player=_preview.player
	# Restore the selected key before deriving a guide, rather than a scrubbed frame.
	var sampled:PostureDefinition=_current.to_preview_posture(PostureLibrary.instance().get_def(20)) if _base else ServeStore.sample(_current,float(_stage)*.5) if _serve else Path.sample(_current,float(_stage)*.5)
	_preview.show_pose(sampled)
	var arm=player.left_arm_node if left else player.right_arm_node
	var shoulder:Vector3=arm.upper_pivot.global_position
	var wrist:Vector3=arm.hand_mesh.global_transform*arm.articulated_hand.wrist_socket
	var axis:Vector3=(wrist-shoulder).normalized()
	if axis.length_squared()<.5:return
	var field:String="left_elbow_pole" if left else "right_elbow_pole"
	var local:Vector3=_edit.get(field)
	var fh:Vector3=player._get_forehand_axis();var fwd:Vector3=player._get_forward_axis()
	var pole:Vector3=player.global_position+fh*local.x+Vector3.UP*local.y+fwd*local.z
	if local.length_squared()<1e-10:pole=player.global_position+fh*(-.5 if left else .5)+Vector3.DOWN-fwd*.5
	var angles:Vector3=_edit.get("left_shoulder_rotation_deg" if left else "right_shoulder_rotation_deg")
	var stance:Basis=Basis(fh,Vector3.UP,-fwd)
	var guide_rotation:Basis=stance*Basis.from_euler(angles*(PI/180.0))*stance.inverse()
	pole=shoulder+guide_rotation*(pole-shoulder)
	var radial:Vector3=pole-shoulder;radial-=axis*radial.dot(axis)
	if radial.length_squared()<.0001:
		radial=fh*(-1 if left else 1);radial-=axis*radial.dot(axis)
	if radial.length_squared()<.0001:radial=axis.cross(Vector3.FORWARD)
	var turned:Vector3=radial.normalized().rotated(axis,deg_to_rad(float(direction)*(5.0 if _fine else 15.0)))*maxf(radial.length(),.35)
	var relative:Vector3=shoulder+guide_rotation.inverse()*turned-player.global_position
	_changed(field,Vector3(relative.dot(fh),relative.y,relative.dot(fwd)))
	_build_fields()

func _update_elbow_path(field:String,value:Vector3)->void:
	# Preserve authored intermediate curve keys. Only change the selected endpoint
	# (or the two center knots that bracket Contact in an even-sized curve).
	var path_field:String="right_elbow_path" if field=="right_elbow_pole" else "left_elbow_path"
	var points:PackedVector3Array=_current.get(path_field)
	if points.size()<2:return
	points=points.duplicate()
	var position:float=float(_stage)*.5*float(points.size()-1)
	var a:int=int(floor(position));var b:int=int(ceil(position))
	var existing:Vector3=points[a].lerp(points[b],position-float(a))
	var delta:Vector3=value-existing
	points[a]+=delta
	if b!=a:points[b]+=delta
	_current.set(path_field,points)

func _build_paddle_rotation()->void:
	var title:=Label.new();title.text="Paddle rotation · "+("Ready" if not _has_motion() else ["Wind-up","Contact","Finish"][_stage]);_fields.add_child(title)
	if _serve and not ServeStore.is_field_editable(_stage,ROT[0]):
		var locked:=Label.new();locked.text="Contact orientation follows the serve ball.\nEdit rotation in Wind-up or Finish.";locked.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fields.add_child(locked)
		if _has_motion():_build_contact_curve()
		return
	_gimbal=Gimbal.new();_gimbal.ui_scale=_s;_gimbal.custom_minimum_size.y=310*_s;_gimbal.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_fields.add_child(_gimbal);_gimbal.rotation_dragged.connect(_rotate_paddle_axis)
	var help:=Label.new();help.text="Rings and numbers edit authored Pitch, Yaw and Roll. Full turns wrap; playback takes the shortest turn. Hand and paddle turn together around the wrist. Grip styles rotate the paddle inside the hand.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED;_fields.add_child(help)
	if _serve and _stage==1:help.text="Rings and numbers edit Contact Pitch, Yaw and Roll around the fixed ball surface point. Full turns wrap. Reach and floor warnings show when the requested orientation cannot seat safely."
	var lag_row:=HBoxContainer.new();_fields.add_child(lag_row);lag_row.visible=not (_serve and _stage==1)
	var lag_choice:=option(lag_row,["Behind player","Away from net"]);lag_choice.select(_lag_direction);lag_choice.item_selected.connect(func(i):_lag_direction=i)
	button(lag_row,"Wrist Lag",_apply_wrist_lag).tooltip_text="Orientation preset: point the paddle top backward while retaining the seated wrist. Fine-tune afterward."
	if _has_motion():_build_contact_curve()
	_select_gimbal_axis(0);_sync_rotation_controls()

func _build_normalize_paddle_row()->void:
	var normalize_row:=HBoxContainer.new();_fields.add_child(normalize_row)
	button(normalize_row,"Normalize all keys",_normalize_paddle_angles).tooltip_text="Remove full turns from paddle and grip angles in this pose. Positions and visible keyframe orientations stay the same. Save keeps the change."
	if _rotation_undo.has(_key):button(normalize_row,"Undo normalize",_undo_normalize_paddle_angles)

func _normalize_paddle_angles()->void:
	if _base or _current==null:return
	var original:Resource=_current.duplicate(true)
	if not PaddleRotation.normalize_pose(_current):
		# Loading is non-destructive. Explicit Normalize also lets Save persist
		# canonical values from an older file that was cleaned only in memory.
		_dirty[_key]=true
		_refresh_status("Paddle angles are already normalized. Save writes the normalized values on this device.");return
	_rotation_undo[_key]=original
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("Angles normalized. Previous smoothing preview cleared.",true)
	_motion_dirty=true;_dirty[_key]=true;_select_stage(_stage)
	_refresh_status("Paddle and grip angles normalized for all keys. Keyframe positions and orientations preserved. Save keeps it.")

func _undo_normalize_paddle_angles()->void:
	if not _rotation_undo.has(_key):return
	# Restore only the removed whole turns, including after later fine tuning.
	# Undo normalization must not undo any later visible pose/orientation edit.
	var before:Resource=_rotation_undo[_key]
	for field in PaddleRotation.BASE+PaddleRotation.SIGNED+PaddleRotation.GRIP+PaddleRotation.DELTAS:
		var original=before.get(field)
		_current.set(field,_current.get(field)+original-PaddleRotation.field_value(field,original))
	for field in ["windup_body","follow_through_body"]:
		var old:Resource=before.get(field);var body:Resource=_current.get(field)
		if body==null:continue
		for angle in PaddleRotation.SIGNED+PaddleRotation.GRIP:
			if old!=null and old.values.has(angle) and body.values.has(angle):
				var original=old.values[angle]
				body.values[angle]+=original-PaddleRotation.field_value(angle,original)
	_rotation_undo.erase(_key)
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("Normalization undone. Previous smoothing preview cleared.",true)
	_motion_dirty=true;_dirty[_key]=true;_select_stage(_stage);_refresh_status("Previous paddle angle values restored. Other edits are kept.")

func _build_contact_curve()->void:
	_slider(_fields,Fields.f("contact_curve","Contact curve · whole motion",0,1,.01),-1,float(_current.contact_curve))
	var help:=Label.new();help.text="0 straighter · 0.5 original · 1 rounder. Wind-up, Contact and Finish stay fixed. Saved curve shaping also applies in gameplay.";help.modulate=Ui.MUTED;help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fields.add_child(help)
	var bend:Vector3=Path.ContactCurve.bend(Path.ContactCurve.position(Path.endpoint(_current,0)),Path.ContactCurve.position(_current),Path.ContactCurve.position(Path.endpoint(_current,2)))
	if bend.length_squared()<.00000001:help.text+=" These anchors are straight; move an existing phase to define a bend."

func _build_body_position()->void:
	var title:=Label.new();title.text="Whole body · "+("Ready" if not _has_motion() else ["Wind-up","Contact","Finish"][_stage]);_fields.add_child(title)
	var help:=Label.new();help.text="Move the body relative to the fixed paddle target. X moves sideways, Y changes body height, Z moves forward/back. Soles stay on the floor; body movement stops at reach/grounding limits. Type numbers for precise values; XYZ accepts ±1.5 m. The saved request remains unchanged when the applied movement is capped.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED;_fields.add_child(help)
	if _serve:help.text+=" Serve feet remain planted while the body moves over them."
	_body_position_status=Label.new();_body_position_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fields.add_child(_body_position_status)
	_sync_body_position_status(_preview.pose)
	var descriptor:Dictionary=Fields.body_descriptor("body_position_offset")
	var position:Variant=_edit.get("body_position_offset")
	if position is Vector3:
		for axis in range(3):_slider(_fields,descriptor,axis,position[axis])
	_build_stance_presets()

func _sync_body_position_status(pose:PostureDefinition)->void:
	if not is_instance_valid(_body_position_status) or pose==null:return
	var report:Dictionary=BodyPose.position_report(_preview.player,pose)
	var requested:Vector3=report.requested
	var applied:Vector3=report.applied
	_body_position_status.text="Requested XYZ: %.3f / %.3f / %.3f m\nApplied XYZ: %.3f / %.3f / %.3f m"%[requested.x,requested.y,requested.z,applied.x,applied.y,applied.z]
	if report.limited:_body_position_status.text+="\n"+str(report.reason)+". Request kept; paddle stays fixed."
	_body_position_status.modulate=Color("ffdc62") if report.limited else Ui.MUTED

func _sync_serve_contact_status()->void:
	if not is_instance_valid(_serve_contact_status) or not _serve:return
	_serve_contact_status.text=ServeStore.contact_warning(_current,_preview.player)
	_serve_contact_status.visible=not _serve_contact_status.text.is_empty()

func _build_foot_pitch_help()->void:
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED
	help.text="Foot pitch: + toes down / − toes up (−30° to 45° game tuning). A planted sole stays flat. Lift the foot or preview a hop; floor clearance limits the applied angle."
	_fields.add_child(help)
	_foot_pitch_status=Label.new();_foot_pitch_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fields.add_child(_foot_pitch_status)
	_sync_foot_pitch_status()

func _sync_foot_pitch_status()->void:
	if not is_instance_valid(_foot_pitch_status) or _edit==null:return
	var lines:=PackedStringArray()
	var limited:=false
	for right in [true,false]:
		var id:String="right_foot" if right else "left_foot"
		if _group.selected==6 and _selected_joint!=id:continue
		var report:Dictionary={"requested":float(_edit.get(id+"_pitch_deg"))}
		if _preview.player.leg_ik.has_method("foot_pitch_report"):report=_preview.player.leg_ik.foot_pitch_report(right)
		var text:String=("Right" if right else "Left")+" pitch: requested %.2f°"%float(_edit.get(id+"_pitch_deg"))
		if report.has("applied"):text+=" · applied %.2f°"%float(report.applied)
		if bool(report.get("limited",false)):
			limited=true;text+=" · grounded / clearance limit"
		lines.append(text)
	_foot_pitch_status.text="\n".join(lines);_foot_pitch_status.modulate=Color("ffdc62") if limited else Ui.MUTED

func _select_gimbal_axis(axis:int)->void:
	if is_instance_valid(_gimbal):_gimbal.select_axis(axis)
	for i in range(_gimbal_axis_buttons.size()):_gimbal_axis_buttons[i].set_pressed_no_signal(i==axis)

func _angle_slider(parent:Node,d:Dictionary,value:float)->void:
	var number_row:=HBoxContainer.new();parent.add_child(number_row)
	var title:=Label.new();title.text=d.label;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;number_row.add_child(title)
	var input:=SpinBox.new();input.min_value=-180;input.max_value=180;input.allow_greater=true;input.allow_lesser=true
	input.step=.1 if _fine else 1.0;input.value=value;input.size_flags_horizontal=Control.SIZE_FILL;input.custom_minimum_size=Vector2(164*_s,72*_s);input.set_meta("compact_pose_row",true)
	input.get_line_edit().select_all_on_focus=true;input.get_line_edit().virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	number_row.add_child(input);_controls.append(input);_angle_inputs[d.field]=input
	var reset:=button(number_row,"↺",func():_reset_field(d.field,-1));reset.size_flags_horizontal=0;reset.custom_minimum_size.x=64*_s;reset.set_meta("compact_pose_row",true)
	var row:=HBoxContainer.new();parent.add_child(row)
	var slider:=HSlider.new();slider.scrollable=false;slider.min_value=minf(-180,value);slider.max_value=maxf(180,value);slider.allow_greater=true;slider.allow_lesser=true;slider.step=input.step;slider.value=value
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size=Vector2(120,72*_s);slider.set_meta("compact_pose_row",true)
	var minus:=button(row,"−",func():_set_paddle_angle(ROT.find(d.field),float(_edit.get(d.field))-input.step));minus.size_flags_horizontal=0;minus.custom_minimum_size.x=72*_s;minus.set_meta("compact_pose_row",true)
	row.add_child(slider);_controls.append(slider)
	var plus:=button(row,"+",func():_set_paddle_angle(ROT.find(d.field),float(_edit.get(d.field))+input.step));plus.size_flags_horizontal=0;plus.custom_minimum_size.x=72*_s;plus.set_meta("compact_pose_row",true)
	_sliders[d.field]=slider;slider.set_meta("pose_field_key",d.field)
	input.value_changed.connect(func(v):if not _angle_sync:_set_paddle_angle(ROT.find(d.field),v))
	slider.value_changed.connect(func(v):if not _angle_sync:_set_paddle_angle(ROT.find(d.field),v))

func _rotate_paddle_axis(axis:int,degrees:float)->void:
	_select_gimbal_axis(axis)
	_set_paddle_angle(axis,float(_edit.get(ROT[axis]))+degrees)

func _set_paddle_angle(axis:int,degrees:float)->void:
	if axis<0 or axis>2 or _edit==null:return
	if not is_finite(degrees):_sync_rotation_controls();_refresh_status("Enter a finite angle.");return
	if _serve and not ServeStore.is_field_editable(_stage,ROT[axis]):return
	var value:=wrapf(degrees,-180.0,180.0)
	# A full-turn input is only a new number for the same pose. Re-solving its
	# wrist pivot could move an already reach-limited authored head unintentionally.
	if absf(PaddleRotation.degrees(value-float(_edit.get(ROT[axis]))))<.00005:
		if not is_equal_approx(value,float(_edit.get(ROT[axis]))):_changed(ROT[axis],value,false)
		_sync_rotation_controls();return
	if _serve and _stage==1:
		# Serve Contact rotates around the ball surface, not the wrist. Keep its
		# authored position channels untouched; the sampler performs that pivot.
		_changed(ROT[axis],value,false);_sync_rotation_controls()
		if not _rotation_refresh_pending:
			_rotation_refresh_pending=true;call_deferred("_flush_rotation_preview")
		return
	# Compute from the selected key, not an arbitrary in-between playback frame.
	# A wrist pivot keeps the seated grip while its arm follows normal reach/IK.
	var candidate:PostureDefinition=_edit.duplicate(true)
	candidate.set(ROT[axis],value)
	var player=_preview.player
	var old_transform:Transform3D=Path.world_transform(player,_edit)
	var wrist:Vector3=Wrist.wrist_world(old_transform,_edit)
	var new_basis:Basis=Path.paddle_basis(player,candidate)
	var seated:Transform3D=Transform3D(new_basis,wrist-new_basis*(Wrist.grip_local(candidate)+Wrist.socket_in_grip(candidate)))
	# POS stores the raw head before in-hand spin. Undo that presentation
	# transform before authoring it, or an off-axis grip would drift twice.
	var raw:Transform3D=Path.remove_in_hand_transform(seated,candidate)
	var head:Vector3=raw*Path.PaddleSize.HEAD_OFFSET-player.global_position
	var offset:=Vector3(head.dot(player._get_forehand_axis()),head.y,head.dot(player._get_forward_axis()))
	_changed(ROT[axis],value,false)
	for i in range(3):_changed(POS[i],offset[i],false)
	_sync_rotation_controls()
	# One cached-arc rebuild per input frame, even if multiple touch events arrive.
	if not _rotation_refresh_pending:
		_rotation_refresh_pending=true;call_deferred("_flush_rotation_preview")

func _flush_rotation_preview()->void:
	_rotation_refresh_pending=false
	if _closing or not is_instance_valid(_preview):return
	_refresh_preview();_refresh_status()

func _sync_rotation_controls()->void:
	if _edit==null or _base:return
	_angle_sync=true
	var angles:=Vector3.ZERO
	for i in range(3):
		angles[i]=float(_edit.get(ROT[i]))
		if _angle_inputs.has(ROT[i]):_angle_inputs[ROT[i]].set_value_no_signal(angles[i])
		if _sliders.has(ROT[i]):_sliders[ROT[i]].set_value_no_signal(angles[i])
		if _sliders.has(POS[i]):
			_sliders[POS[i]].set_value_no_signal(float(_edit.get(POS[i])))
			if _slider_labels.has(POS[i]):_slider_labels[POS[i]].call(float(_edit.get(POS[i])))
	if is_instance_valid(_gimbal):_gimbal.set_angles(angles,_edit.resolve_paddle_rotation_deg(-1,-1),_edit.paddle_in_hand_rotation_deg)
	_angle_sync=false

func _build_paddle_grip()->void:
	_build_support_hold()
	var title:=Label.new();title.text="Paddle-in-hand rotation · selected keyframe";_fields.add_child(title)
	_grip_picker=option(_fields,GripStyles.PRESET_NAMES);_grip_picker.item_selected.connect(_choose_grip_style)
	var row:=HBoxContainer.new();_fields.add_child(row)
	var label:=Label.new();label.text="Grip °";row.add_child(label)
	_grip_input=SpinBox.new();_grip_input.min_value=-180;_grip_input.max_value=180;_grip_input.allow_greater=true;_grip_input.allow_lesser=true;_grip_input.step=.1 if _fine else 1.0
	_grip_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_grip_input.custom_minimum_size.y=88*_s;_grip_input.get_line_edit().select_all_on_focus=true;_grip_input.get_line_edit().virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	row.add_child(_grip_input);_controls.append(_grip_input);_grip_input.value_changed.connect(func(v):if not _angle_sync:_set_grip_angle(v))
	var less:=button(row,"−",func():_set_grip_angle(GripStyles.relative_rotation(_edit)-(.1 if _fine else 1.0)));less.size_flags_horizontal=0;less.custom_minimum_size.x=76*_s
	var more:=button(row,"+",func():_set_grip_angle(GripStyles.relative_rotation(_edit)+(.1 if _fine else 1.0)));more.size_flags_horizontal=0;more.custom_minimum_size.x=76*_s
	var reset:=button(row,"↺",func():_reset_field("paddle_in_hand_rotation_deg",-1));reset.size_flags_horizontal=0;reset.custom_minimum_size.x=76*_s
	_grip_source=Label.new();_grip_source.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_grip_source.modulate=Ui.MUTED;_fields.add_child(_grip_source)
	button(_fields,"Set as global paddle grip",_request_global_grip)
	if GripStore.can_undo_global():button(_fields,"Undo last global grip",_undo_global_grip)
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED
	help.text="Illustrative bevel presets, mirrored for left hand. Custom angles keep the handle seated. Ready is its own resting pose. Save changes this pose; global applies the main grip to every stroke and serve."
	if _serve and _stage==1:help.text+=" Serve Contact rotations keep the ball surface point fixed; grip changes adjust the hold around the handle."
	_fields.add_child(help)
	_sync_grip_controls()

func _choose_grip_style(index:int)->void:
	if index<0 or index>=GripStyles.PRESET_ANGLES.size():return
	_set_grip_angle(GripStyles.PRESET_ANGLES[index])

func _set_grip_angle(degrees:float)->void:
	if _edit==null:return
	if not is_finite(degrees):_sync_grip_controls();_refresh_status("Enter a finite grip angle.");return
	_changed("paddle_in_hand_rotation_deg",GripStyles.spin_for_relative(_edit,wrapf(degrees,-180,180)))
	_sync_grip_controls()

func _sync_grip_controls()->void:
	if _edit==null or _base or not is_instance_valid(_grip_input):return
	_angle_sync=true
	_grip_input.set_value_no_signal(GripStyles.relative_rotation(_edit));_grip_picker.select(GripStyles.preset_index(_edit))
	_grip_source.text=GripStore.source_label(_edit)
	_angle_sync=false

func _request_global_grip()->void:
	_confirm("Use this main paddle grip for every stroke, Ready and serve? This replaces earlier grip overrides only. Body poses and motion keys stay intact; Undo is available.",[["Set global grip",_set_global_grip],["Keep editing",_hide_dialog]])

func _set_global_grip()->void:
	var previous:Dictionary={}
	for key in _copies:
		if _copies[key] is PostureDefinition:previous[key]=_copies[key].duplicate(true)
	var error:Error=GripStore.set_global_from_pose(_edit)
	_hide_dialog()
	if error!=OK:_refresh_status("Could not save global grip. Your pose edits are kept.");return
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("Global grip changed. Previous smoothing cleared.",true)
	_global_copy_snapshots=previous
	for value in _copies.values():
		if value is PostureDefinition:GripStore.apply_to_definition(value,true)
	poses_saved.emit();_motion_dirty=true;_select_stage(_stage);_refresh_status("Global main grip saved for all poses. Individual pose grips can still override it.")

func _undo_global_grip()->void:
	var error:Error=GripStore.undo_global()
	if error!=OK:_refresh_status("Could not undo global grip. Existing saved poses are kept.");return
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("Global grip changed. Previous smoothing cleared.",true)
	for key in _copies:
		var value:Resource=_copies[key]
		if not value is PostureDefinition:continue
		if _global_copy_snapshots.has(key):
			var previous:Resource=_global_copy_snapshots[key]
			value.paddle_in_hand_rotation_deg=previous.paddle_in_hand_rotation_deg
			for property in ["windup_body","follow_through_body"]:
				var body:Resource=value.get(property);var before:Resource=previous.get(property)
				if before!=null and before.values.has("paddle_in_hand_rotation_deg"):
					if body==null:body=Keyframe.new();value.set(property,body)
					body.values.paddle_in_hand_rotation_deg=before.values.paddle_in_hand_rotation_deg
				elif body!=null:body.values.erase("paddle_in_hand_rotation_deg")
		else:GripStore.refresh_copy_grips(value)
	_global_copy_snapshots.clear()
	poses_saved.emit();_motion_dirty=true;_select_stage(_stage);_refresh_status("Previous global grip restored.")

func _wrist_lag_direction()->Vector3:
	var player=_preview.player
	var backward:Vector3=-player._get_forward_axis()
	if _lag_direction==0:
		var body:Basis=BodyPose.pivot_transform(player,_edit).basis*BodyPose.torso_transform(player,_edit,false).basis
		backward=body*backward
	backward.y=0
	return backward.normalized()

func _apply_wrist_lag()->void:
	if _base or _edit==null or (_serve and not ServeStore.is_field_editable(_stage,ROT[0])):return
	var player=_preview.player
	var current:Transform3D=Path.world_transform(player,_edit)
	var wrist:Vector3=Wrist.wrist_world(current,_edit)
	var y:Vector3=_wrist_lag_direction()
	if y.length_squared()<.5:return
	var x:Vector3=current.basis.x-y*current.basis.x.dot(y)
	if x.length_squared()<.00001:x=current.basis.z.cross(y)
	if x.length_squared()<.00001:x=Vector3.UP.cross(y)
	x=x.normalized()
	var desired:=Basis(x,y,x.cross(y).normalized())
	var candidate:PostureDefinition=_edit.duplicate(true)
	var displayed:=Transform3D(desired,wrist-desired*(Wrist.grip_local(candidate)+Wrist.socket_in_grip(candidate)))
	var raw:Transform3D=Path.remove_in_hand_transform(displayed,candidate)
	var stance:=Basis(player._get_forehand_axis(),Vector3.UP,-player._get_forward_axis())
	var directional:Vector3=_edit.resolve_paddle_rotation_deg(-1,-1)-Vector3(_edit.paddle_pitch_base_deg,_edit.paddle_yaw_base_deg,_edit.paddle_roll_base_deg)
	Orientation.set_canonical_basis(candidate,stance.inverse()*raw.basis)
	var head:Vector3=raw*Path.PaddleSize.HEAD_OFFSET-player.global_position
	var offset:=Vector3(head.dot(player._get_forehand_axis()),head.y,head.dot(player._get_forward_axis()))
	for i in range(3):_changed(ROT[i],wrapf(float(candidate.get(ROT[i]))-directional[i],-180,180),false)
	if not (_serve and _stage==1):
		for i in range(3):_changed(POS[i],offset[i],false)
	_sync_rotation_controls();_refresh_preview();_refresh_status("Wrist Lag preset · "+("behind player" if _lag_direction==0 else "away from net")+". Fine-tune or Save this keyframe.")

func _build_support_hold()->void:
	var label:=Label.new();label.text="Support hand · whole pose";_fields.add_child(label)
	var holds:bool=_current.paddle_hand==1 or Path._support_mode(_edit)==1
	var toggle:=button(_fields,"Left hand holds paddle",_set_left_support_hold.bind(not holds));toggle.toggle_mode=true;toggle.button_pressed=holds
	toggle.disabled=_serve or _current.paddle_hand==1
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED
	help.text=("Join or release the left support hand for all three phases. " if _has_motion() else "Join or release the left support hand for this static Ready pose. ")+"Main hand stays right. If the arm cannot reach, adjust Body position. Advanced Support hand controls can still vary by keyframe."
	if _serve:help.text="Serve support hand is reserved for the ball; its release/contact sequence stays protected."
	elif _current.paddle_hand==1:help.text="Left is already the main paddle hand. This toggle does not switch handedness."
	_fields.add_child(help)

func _set_left_support_hold(enabled:bool)->void:
	if _base or _serve or _current==null or _current.paddle_hand==1:return
	if _elbow_preset_panel:_elbow_preset_panel.invalidate("Support-hand mode changed. Previous smoothing cleared.",true)
	_clear_variant();_stop()
	_current.left_hand_mode=1 if enabled else 4
	if enabled:_current.left_hand_offset=Vector3.ZERO
	if _has_motion():
		for property in ["windup_body","follow_through_body"]:
			var key:Resource=_current.get(property)
			if key==null:key=Keyframe.new();_current.set(property,key)
			key.values.left_hand_mode=1 if enabled else 4
			# A free-hand offset is not a valid handle anchor when joining.
			if enabled:key.values.left_hand_offset=Vector3.ZERO
	_motion_dirty=true;_dirty[_key]=true;_select_stage(_stage)
	_refresh_status("Left support hand "+("joined the handle" if enabled else "released")+" for this whole pose. Save when ready.")

func _build_stance_presets()->void:
	var label:=Label.new();label.text="Stance presets · "+("Wind-up planted stance" if _serve else "Ready" if not _has_motion() else ["Wind-up","Contact","Finish"][_stage]);_fields.add_child(label)
	var stance_row:=HBoxContainer.new();_fields.add_child(stance_row)
	var open:=button(stance_row,"Open · wide + bent",_apply_stance_style.bind(false))
	open.tooltip_text="Net-facing chest and foot line, wide base and bent knees. Changes only after tapping this button."
	var closed:=button(stance_row,"Closed · side-on",_apply_stance_style.bind(true))
	closed.tooltip_text="75° side-on body turn, staggered feet and bent knees. Mirrored for the shot side and paddle hand."
	var scope:=Label.new();scope.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;scope.modulate=Ui.MUTED
	scope.text="Tap to apply to this keyframe only, then Save. Existing imported poses stay unchanged until you choose a preset. Runtime setup uses the stroke's Wind-up stance."
	if not _has_motion():scope.text="Tap to apply to this static Ready pose, then Save. Existing imported poses stay unchanged until you choose a preset."
	if _serve:scope.text="Tap to apply to Wind-up; feet stay planted through the serve. Contact/Finish body keys and ball contact stay unchanged. Save when ready."
	_fields.add_child(scope)
	var fine_title:=Label.new();fine_title.text="Foot placement only";_fields.add_child(fine_title)
	var row:=HBoxContainer.new();_fields.add_child(row)
	var picker:=option(row,["Left foot forward","Right foot forward","Square / neutral"]);picker.select(_stance_preset);picker.item_selected.connect(func(i):_stance_preset=i)
	button(row,"Apply stance",_apply_stance_preset)
	var help:=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.modulate=Ui.MUTED;help.text="Grounded starting stance, then fine-tune. Paddle target and upper-body settings stay unchanged."
	if _serve:help.text+=" Serve presets change Wind-up feet and stay planted through Contact/Finish."
	_fields.add_child(help)

func _apply_stance_style(closed:bool)->void:
	if _base or _current==null:return
	var selected:int=_stage
	if _serve and _stage!=0:_select_stage(0)
	# Existing persisted fields are the stance profile. No new enum, implicit
	# defaults or imports are written. Preserve paddle targets/rotations, arms,
	# body translation and all nonselected body keys through the normal setter.
	var side:float=(-1.0 if _current.family==1 else 1.0)*(-1.0 if _current.paddle_hand==1 else 1.0)
	var yaw:float=side*75.0 if closed else 0.0
	# Turn the entire support frame, not just the chest. Knee poles follow
	# the shoes in court-local coordinates on either court side.
	var knee:=Vector3(sin(deg_to_rad(yaw)),.5,cos(deg_to_rad(yaw)))
	var fields:Dictionary={
		"stance_width":.24 if closed else .66,
		"front_foot_forward":.30 if closed else 0.0,"back_foot_back":-.30 if closed else 0.0,
		"right_foot_offset":Vector3.ZERO,"left_foot_offset":Vector3.ZERO,
		"right_foot_yaw_deg":yaw,"left_foot_yaw_deg":yaw,
		"right_knee_pole":knee,"left_knee_pole":knee,
		"lead_foot":1 if side>0 else 0,"crouch_amount":.14 if closed else .18,
		"body_yaw_deg":yaw,"hip_yaw_deg":0.0,"torso_yaw_deg":0.0,
	}
	for field in fields:
		if not _serve or ServeStore.is_field_editable(_stage,field):_changed(field,fields[field],false)
	_select_stage(selected)
	_refresh_status(("Closed side-on" if closed else "Open wide + bent")+" applied to "+("the serve's Wind-up stance" if _serve else "this keyframe" if _has_motion() else "Ready")+". Paddle target unchanged. Save when ready.")

func _apply_stance_preset()->void:
	if _base or _current==null:return
	var selected:int=_stage
	if _serve and _stage!=0:_select_stage(0)
	var fields:Dictionary={"stance_width":.5,"front_foot_forward":.18 if _stance_preset!=2 else 0.0,"back_foot_back":-.14 if _stance_preset!=2 else 0.0,"right_foot_offset":Vector3.ZERO,"left_foot_offset":Vector3.ZERO,"right_foot_yaw_deg":0.0,"left_foot_yaw_deg":0.0}
	if _stance_preset!=2:fields.lead_foot=1 if _stance_preset==0 else 0
	for field in fields:_changed(field,fields[field],false)
	_select_stage(selected);_refresh_status("Footwork preset applied to "+("the serve's planted Wind-up stance" if _serve else "this keyframe")+". Fine-tune and Save when ready.")
