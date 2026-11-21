extends Control
## Desktop Pose Studio: mouse / trackpad layer over the engine preview (ed._preview, a TextureRect).
## Blender-style camera around preview.camera_target (the hips when framed; pan moves it):
##   middle-drag orbit, Shift+middle-drag pan, Ctrl+middle-drag or wheel zoom;
##   trackpad two-finger scroll (InputEventPanGesture) orbits, Shift+scroll pans, pinch zooms.
## Left-drag on empty space orbits too (Shift = pan). On a joint dot or gizmo handle the left
## button picks the joint dots drawn here (one per Fields.JOINT_IDS joint) and drags gizmo handles through the engine's own gizmo ->
## _drag_selected_gizmo path; the whole drag is one undo step (studio.begin_edit / end_edit),
## Esc aborts it. Gizmo handles win over dots under the cursor, except on the visible disc of
## another joint's dot (DOT_CORE): a ring or arrow is grabbable anywhere along it, a dot only there.
## Full-rect child of the preview, so event positions are preview-local (same as the gizmo's).
## Paddle tip: an extra dot (orange diamond) at the far end of the paddle head, like a rig's aim
## handle. Dragging it aims the paddle (studio.aim_paddle_tip: grip stays, the tip follows the
## mouse, the arm follows through the engine's IK); Shift+drag moves the paddle (studio.move_paddle).
## It is not a joint: never selected, picked like a dot (its core beats gizmo handles).
## Alt on a mouse event or key switches the paddle hand's Move gizmo to the grip slide (studio.set_hand_slide).
##
## AutoPose mode (toolbar AutoPose, key P; docs/POSE_STUDIO_SPEC.md Stage 6b): a separate mode that
## REPLACES the joint dots, the paddle tip diamond and the gizmo with AutoPose handles (rings coloured
## by region: arm blue, legs green, body violet; paddle tip an orange diamond ring; grey = locked).
## Left-drag a handle: it follows the mouse in the camera-facing plane through it (Shift held:
## mouse up / down pushes it away from / pulls it toward the camera instead) and the whole body
## follows live (studio.autopose_drag_move -> autopose_solver.move, animation fields only). Release =
## one undo step; Esc or a right-click during the drag cancels back to the pose before it. Off
## (P again) gives back the joint dots, gizmo and tip aim exactly as before.
## Pins: a lock icon up-right of a handle (always shown when pinned, on hover otherwise); a click
## on it (or Alt+click on the handle) pins / unpins it (studio.set_autopose_pin).

const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const TIP_ID := "paddle_tip"
const TIP_LOCAL := Vector3(0, PaddleSize.LENGTH, 0)   # paddle node: +Y handle -> head, origin at the butt
const TIP_COLOR := Color("ff9f43")
const TIP_NAME := "Paddle tip - drag to aim (Shift = move the paddle)"
const PICK_RADIUS := 13.0         # points: click / hover distance to a joint dot
const DOT_RADIUS := 4.5
const DOT_CORE := 6.5             # points: the drawn dot (+ outline); here a dot beats a handle
const ORBIT_RAD_PER_PT := 0.0075  # mouse: 420 pt of drag = half a turn
const GESTURE_PT := 16.0          # trackpad pan-gesture unit (macOS: 0.03 x scroll points) -> drag points
const PITCH_LIMIT := 1.45         # rad, about 83 degrees up
const PITCH_MIN := -0.35          # rad, about 20 degrees below the hips: camera stays above the floor
const DIST_MIN := 0.6
const DIST_MAX := 12.0
const WHEEL_STEP := 0.88          # distance factor per wheel notch
const DRAG_ZOOM_PER_PT := 0.006   # Ctrl+middle-drag: up = closer
const FRAME_MIN_DIST := 1.4
const TARGET_BOX := Vector3(3.0, 2.5, 3.0)   # pan limit around (0, 1, 0)
const DOT_COLOR := Color("e8f4f8")
const DOT_HOVER := Color("ffdc62")
const DOT_OUTLINE := Color("122630")
const SELECT_COLOR := Color("71f5da")
const AP_IDS := ["right_hand", "left_hand", "paddle_tip", "right_elbow", "left_elbow", "right_knee", "left_knee",
	"right_foot", "left_foot", "hips", "chest", "head", "right_shoulder", "left_shoulder", "right_hip", "left_hip",
	"paddle_edge_a", "paddle_edge_b"]
## Rotate handles (ring with a turn arc): drag turns that part, it does not move it.
const AP_ROTATE := ["right_shoulder", "left_shoulder", "right_hip", "left_hip"]
const AP_EDGES := ["paddle_edge_a", "paddle_edge_b"]
const AP_NAMES := {"right_hand": "Right hand", "left_hand": "Left hand", "paddle_tip": "Paddle tip", "right_elbow": "Right elbow",
	"left_elbow": "Left elbow", "right_knee": "Right knee", "left_knee": "Left knee", "right_foot": "Right foot",
	"left_foot": "Left foot", "hips": "Hips", "chest": "Chest", "head": "Head",
	"right_shoulder": "Right shoulder (turn upper body)", "left_shoulder": "Left shoulder (turn upper body)",
	"right_hip": "Right hip (turn hips)", "left_hip": "Left hip (turn hips)",
	"paddle_edge_a": "Paddle edge (roll the face)", "paddle_edge_b": "Paddle edge (roll the face)"}
const AP_ARM := Color("5fb8ff")
const AP_LEG := Color("7ee081")
const AP_BODY := Color("d59cff")
const AP_LOCKED := Color("7d8b93")
const AP_RADIUS := 6.0
const LOCK_OFF := Vector2(11, -11)   # lock icon centre from its handle (points)
const LOCK_PICK := 7.0
const PIN_COLOR := Color("71f5da")
enum Drag { NONE, ORBIT, PAN, ZOOM, GIZMO, TIP, AUTOPOSE, PATH }
const LINK_DEVICE := 77           # device id of mouse events the TCP link pushes (pose_studio_link.gd _mods)

var studio
var preview
var drag := Drag.NONE
var _left_nav := false   # current orbit/pan was started with the left button
## Phone (touch) mode: finger-sized hit areas and rings; two fingers pan and pinch-zoom.
var touch := false
const TOUCH_SCALE := 2.6          # phone: hit areas (canvas points per desktop point), finger-sized
const TOUCH_DRAW := 1.5           # phone: drawn rings (smaller than their hit areas, so the body shows)
var _touches := {}                # finger index -> position (touch mode)
var _pinch := {}                  # two-finger gesture: {mid, dist}
var _touch_block := false         # after a two-finger gesture: ignore the last finger until it lifts
var auto_fit := true     # camera follows pose / stage switches until the user zooms or pans (F = on again)
var hover_joint := ""
var _dots := PackedVector2Array()
var _last_mouse := Vector2.INF
var _tip := Vector2.INF            # paddle tip dot, preview points (INF = hidden)
var _tip_shift := false            # this tip drag moves the paddle instead of aiming it
var _tip_offset := Vector2.ZERO    # mouse - tip at press: the tip keeps it (no jump on grab)
var _tip_plane := Plane()          # Shift move: camera-facing plane through the tip at press
var _tip_hit := Vector3.ZERO
var drag_kind := ""                # "pos" / "rot" / "" while dragging: hint warning at Contact
var _ap := PackedVector2Array()    # AutoPose handles, preview points (AP_IDS order; INF = hidden)
var _ap_world := PackedVector3Array()
var hover_ap := ""                 # AutoPose handle under the mouse
var ap_handle := ""                # handle being dragged
var _ap_plane := Plane()           # camera-facing plane through the handle (re-anchored after a Shift depth move)
var _ap_offset := Vector2.ZERO     # mouse - handle at press: the handle keeps it (no jump on grab)
var ap_target := Vector3.INF       # world point the handle is being dragged to
var hover_lock := false            # the mouse is on hover_ap's lock icon
## Momentum arc (preview.momentum_heads, Trajectory layer, AutoPose): a dot per game tick (their
## spacing is the paddle's speed) and the Wind-up / Finish points. Dragging a point goes to that
## key and drags its paddle (the paddle tip handle); a tap opens the swing options (phone).
const ARC_KEY_RADIUS := 7.0
var _arc_dots := PackedVector2Array()
var _arc_keys := PackedVector2Array()   # Wind-up, Contact, Finish points (preview points)
var arc_stage := -1                     # key of the arc point being dragged (0 / 2), -1 = none
## Paddle path keys on the arc (strokes): a filled square per key, a hollow one (bend point) in
## the middle of each half that has no key. Drag one to bend / place the path there (a bend point
## becomes a key); press a tick dot to add a key at that moment; a tap opens the key's options.
const PATH_COLOR := Color("ff8fb1")
var _path_pts := PackedVector2Array()   # screen points of preview.momentum_path_heads
var path_t := -1.0                       # progress of the key being dragged (-1 = none)
var _path_head0 := Vector3.INF
var _path_off0 := Vector3.ZERO
var _path_plane := Plane()
var _path_grab := Vector2.ZERO
var _path_moved := false
var _pick_head := Vector3.INF          # arc head of the lead-in tick path_pick last returned

func attach(owner_studio, pv) -> void:
	studio = owner_studio; preview = pv
	name = "ViewportInput"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dots.resize(Fields.JOINT_IDS.size())
	_dots.fill(Vector2.INF)
	pv.add_child(self)

# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if preview == null: return
	if studio.link_driving and event.device != LINK_DEVICE:   # a link test drives the mouse: a real hover / click is not part of it
		accept_event(); return
	if event is InputEventMouseButton:
		_button(event)
	elif event is InputEventMouseMotion:
		_last_mouse = event.position
		match drag:
			Drag.GIZMO: preview.gizmo.input(event)
			Drag.TIP: _tip_motion(event.position)
			Drag.PATH: if event.button_mask & MOUSE_BUTTON_MASK_LEFT: _path_motion(event.position)
			Drag.AUTOPOSE:   # only motion with the left button held moves the handle (a stray hover event is not the drag)
				if event.button_mask & MOUSE_BUTTON_MASK_LEFT: _ap_motion(event)
			Drag.ORBIT: if not _touch_block: orbit(event.relative)
			Drag.PAN: pan_by(event.relative)
			Drag.ZOOM: set_distance(current_distance() * exp(event.relative.y * DRAG_ZOOM_PER_PT))
			_:
				studio.set_hand_slide(event.alt_pressed)
				_hover(event.position)
	elif event is InputEventPanGesture:
		if drag == Drag.NONE:
			var rel: Vector2 = -event.delta * GESTURE_PT
			if event.shift_pressed: pan_by(rel)
			elif event.ctrl_pressed or event.meta_pressed: set_distance(current_distance() * exp(-rel.y * DRAG_ZOOM_PER_PT))
			else: orbit(rel)
	elif event is InputEventMagnifyGesture:
		if drag == Drag.NONE and event.factor > 0.0: set_distance(current_distance() / event.factor)
	elif touch and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_touch_event(event)
	else:
		return
	accept_event()

## Hit / ring size in this view's points (finger-sized on the phone).
func _r(desktop_points: float) -> float:
	return desktop_points * (TOUCH_SCALE if touch else 1.0)

## Phone fingers. One finger arrives as the emulated left mouse (ring drag or orbit, above). A
## second finger stops that orbit (or cancels a ring drag) and the two pan by their midpoint and
## zoom by their spread; the finger left over does nothing until it lifts (no jump back to orbit).
func _touch_event(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed: _touches[e.index] = e.position
		else: _touches.erase(e.index)
	else:
		_touches[e.index] = e.position
	if _touches.size() >= 2:
		if drag == Drag.AUTOPOSE: cancel()
		elif drag in [Drag.ORBIT, Drag.PAN]: drag = Drag.NONE; _left_nav = false
		_touch_block = true
		var ids: Array = _touches.keys()
		var a: Vector2 = _touches[ids[0]]; var b: Vector2 = _touches[ids[1]]
		var mid := (a + b) * 0.5
		var dist := maxf(a.distance_to(b), 1.0)
		if not _pinch.is_empty():
			pan_by(mid - Vector2(_pinch.mid))
			set_distance(current_distance() * float(_pinch.dist) / dist)
		_pinch = {"mid": mid, "dist": dist}
	else:
		_pinch = {}
		if _touches.is_empty(): _touch_block = false

func _button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed and drag == Drag.NONE:
				var notches: float = e.factor if e.factor > 0.0 else 1.0
				set_distance(current_distance() * pow(WHEEL_STEP, notches if e.button_index == MOUSE_BUTTON_WHEEL_UP else -notches))
		MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				if drag != Drag.NONE: return
				grab_focus()
				drag = Drag.PAN if e.shift_pressed else Drag.ZOOM if (e.ctrl_pressed or e.meta_pressed) else Drag.ORBIT
				mouse_default_cursor_shape = Control.CURSOR_MOVE if drag == Drag.PAN else Control.CURSOR_DRAG
			elif drag in [Drag.ORBIT, Drag.PAN, Drag.ZOOM]:
				drag = Drag.NONE
				_hover(e.position)
		MOUSE_BUTTON_RIGHT:
			if e.pressed and drag in [Drag.GIZMO, Drag.TIP, Drag.AUTOPOSE]: cancel()   # right-click cancels a drag
		MOUSE_BUTTON_LEFT:
			if not e.pressed:
				if drag == Drag.PATH:
					drag = Drag.NONE
					var t := path_t
					path_t = -1.0
					studio.end_edit(); studio.drag_changed()
					if not _path_moved: studio.handle_tapped.emit("pathkey:%f" % t)
					queue_redraw(); return
				if drag == Drag.AUTOPOSE:
					drag = Drag.NONE
					var tapped: bool = int(studio.last_autopose.get("moves", 0)) == 0
					studio.autopose_drag_end(true, "released")
					if tapped: studio.handle_tapped.emit("swing" if arc_stage >= 0 else ap_handle)
					arc_stage = -1
					ap_handle = ""; ap_target = Vector3.INF
					studio.drag_changed()
					_hover(e.position); queue_redraw()
				elif drag == Drag.GIZMO or drag == Drag.TIP:
					if drag == Drag.GIZMO: preview.gizmo.input(e)
					drag = Drag.NONE
					drag_kind = ""
					studio.end_edit()
					studio.drag_changed()
				elif drag in [Drag.ORBIT, Drag.PAN] and _left_nav:
					drag = Drag.NONE
					_left_nav = false
					_hover(e.position)
				return
			if drag != Drag.NONE: return
			grab_focus()
			if studio.autopose_on:   # AutoPose mode: handles only (no joint dots, no gizmo)
				var core := ap_pick(e.position, _r(AP_RADIUS + 2.0))   # on a ring: the handle wins over a nearby lock
				var lk := ap_lock_pick(e.position) if core == "" and not touch else ""
				if lk != "":
					studio.set_autopose_pin(lk); queue_redraw(); return
				var pk := path_pick(e.position) if core == "" else -1.0
				if pk >= 0.0:
					_begin_path(pk, e); return
				var ak := arc_pick(e.position) if core == "" else -1
				if ak >= 0:
					if ak != studio.stage: studio.set_stage(ak)
					arc_stage = ak
					_begin_ap("paddle_tip", e)
					if drag != Drag.AUTOPOSE: arc_stage = -1
					return
				var h := core if core != "" else ap_pick(e.position, _r(PICK_RADIUS))
				if h != "":
					if e.alt_pressed: studio.set_autopose_pin(h); queue_redraw(); return
					_begin_ap(h, e); return
				drag = Drag.PAN if e.shift_pressed else Drag.ORBIT
				_left_nav = true
				mouse_default_cursor_shape = Control.CURSOR_MOVE if drag == Drag.PAN else Control.CURSOR_DRAG
				return
			studio.set_hand_slide(e.alt_pressed)
			var core := pick(e.position, DOT_CORE)
			if core == TIP_ID:
				if _begin_tip(e): return
			elif core != "" and core != preview.selected_joint:
				studio.select_joint(core); return
			var gz = preview.gizmo
			if gz and gz.visible and gz.enabled:
				studio.begin_edit("gizmo")
				if gz.input(e):
					drag = Drag.GIZMO
					drag_kind = _gizmo_kind()
					studio.drag_changed()
					return
				studio.cancel_edit()
			var id := pick(e.position)
			if id == TIP_ID:
				if _begin_tip(e): return
			elif id != "": studio.select_joint(id); return
			# Empty space: left-drag orbits (Shift = pan), like the middle button.
			drag = Drag.PAN if e.shift_pressed else Drag.ORBIT
			_left_nav = true
			mouse_default_cursor_shape = Control.CURSOR_MOVE if drag == Drag.PAN else Control.CURSOR_DRAG

# ---------------------------------------------------------------- camera

func current_distance() -> float:
	return preview.distance if preview._manual_zoom else maxf(preview.distance, preview._fitted_distance)

func orbit(rel: Vector2) -> void:
	preview.yaw = wrapf(preview.yaw - rel.x * ORBIT_RAD_PER_PT, -PI, PI)
	preview.pitch = clampf(preview.pitch + rel.y * ORBIT_RAD_PER_PT, PITCH_MIN, PITCH_LIMIT)
	preview.update_camera()

## Move the orbit centre in the camera plane; the scene follows the cursor at the centre's depth.
func pan_by(rel: Vector2) -> void:
	var cam: Camera3D = preview.camera
	if cam == null or size.y <= 0: return
	var dist: float = cam.global_position.distance_to(preview.camera_target)
	var k: float = dist * 2.0 * tan(deg_to_rad(cam.fov * 0.5)) / size.y
	var b: Basis = cam.global_transform.basis
	set_target(preview.camera_target - b.x * rel.x * k + b.y * rel.y * k)

func set_target(t: Vector3) -> void:
	var c := Vector3(0, 1, 0)
	preview.camera_target = c + (t - c).clamp(-TARGET_BOX, TARGET_BOX)
	auto_fit = false
	preview.update_camera()

func set_distance(d: float) -> void:
	preview.distance = clampf(d, DIST_MIN, DIST_MAX)
	preview._manual_zoom = true
	auto_fit = false
	preview.update_camera()

## Pose centre: the solved hips (fallback: the phone's fixed target).
func pose_centre() -> Vector3:
	var p: Vector3 = preview.joint_world_position("hips")
	return p if p.is_finite() else Vector3(0, 1, 0)

## F: orbit centre back to the hips, fit the distance on the pose, and follow poses again
## (auto_fit). Until the user zooms or pans, a pose switch refits and a stage switch only pulls
## out (never in), so the paddle stays on screen and the zoom holds while comparing stages.
## Once the user zooms or pans, the camera stays where they put it until F.
func frame_pose() -> void:
	preview.cancel_gesture()
	auto_fit = true
	_fit(FRAME_MIN_DIST)

## Pose / stage switch while auto_fit: `grow_only` keeps the current distance as the minimum.
func follow_pose(grow_only: bool) -> void:
	if not auto_fit or drag != Drag.NONE: return
	_fit(current_distance() if grow_only else FRAME_MIN_DIST)

func _fit(minimum: float) -> void:
	preview.camera_target = pose_centre()
	preview.distance = minimum
	preview._manual_zoom = false
	preview._fitted_distance = minimum
	preview._fit_camera_to_pose()
	preview.distance = clampf(maxf(preview.distance, preview._fitted_distance), DIST_MIN, DIST_MAX)
	preview._manual_zoom = true
	preview.update_camera()

## Fixed views keep the orbit centre and distance (Blender numpad 1 / 3 / 7).
func set_view(yaw: float) -> void:
	preview.cancel_gesture()
	preview.yaw = yaw
	preview.pitch = 0.08
	preview.update_camera()

## End the open gizmo / tip drag and keep what it did as one undo step (stage or pose switch,
## play): the engine gizmo lets go, later motion with the button still held only hovers.
func finish_drag() -> void:
	if drag == Drag.AUTOPOSE:   # kept as one undo step when it still edits its own key, else dropped
		drag = Drag.NONE
		studio.autopose_drag_end(true, "switch")
		ap_handle = ""; ap_target = Vector3.INF
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		studio.drag_changed(); queue_redraw()
		return
	if drag == Drag.PATH:
		drag = Drag.NONE; path_t = -1.0
		studio.end_edit(); studio.drag_changed(); queue_redraw()
		return
	if drag != Drag.GIZMO and drag != Drag.TIP: return
	drag = Drag.NONE
	preview.cancel_gesture()
	drag_kind = ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	studio.end_edit()
	studio.drag_changed()

func cancel() -> void:
	if drag == Drag.AUTOPOSE:   # Esc / right-click / focus loss: back to the pose from before the drag
		drag = Drag.NONE
		studio.autopose_drag_end(false, "cancelled")
		ap_handle = ""; ap_target = Vector3.INF; arc_stage = -1
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		studio.drag_changed(); queue_redraw()
	elif drag == Drag.PATH:
		drag = Drag.NONE; path_t = -1.0
		studio.abort_edit(); studio.drag_changed(); queue_redraw()
	elif drag == Drag.GIZMO or drag == Drag.TIP:
		drag = Drag.NONE
		preview.cancel_gesture()
		studio.abort_edit()   # Esc / focus loss: back to the pose from before the drag
		drag_kind = ""
		studio.drag_changed()
	drag = Drag.NONE

# ---------------------------------------------------------------- paddle tip

func tip_world() -> Vector3:
	var p = preview.player if preview else null
	if p == null or not is_instance_valid(p.paddle_node): return Vector3.INF
	return p.paddle_node.global_transform * TIP_LOCAL

## Fields the dragged gizmo writes: paddle position ("pos"), paddle angles ("rot", the engine
## also re-seats the head: position changes too), or neither ("").
func _gizmo_kind() -> String:
	for b in preview.gizmo.bindings:
		if b is Dictionary and not b.is_empty():
			if str(b.field) in studio.POS: return "pos"
			if str(b.field).begins_with("paddle_") and str(b.field).ends_with("_base_deg"): return "rot"
	return ""

func _begin_tip(e: InputEventMouseButton) -> bool:
	if not studio.tip_available() or not _tip.is_finite(): return false
	if not studio.at_key():
		studio._set_status("Paddle tip: go to a key (wind-up, contact, finish) to aim it"); return true
	if studio.gameplay_locked("paddle_forehand_mul" if e.shift_pressed else "paddle_pitch_base_deg"):
		studio._set_status("Locked: at Contact the paddle position and face are gameplay. Turn on Gameplay edit (top bar) to change them.")
		var under := pick(e.position, PICK_RADIUS, false)   # the click still selects a joint dot under the tip
		if under != "" and under != preview.selected_joint: studio.select_joint(under)
		return true
	preview.cancel_gesture()
	studio.begin_edit("move paddle (tip)" if e.shift_pressed else "aim paddle (tip)")
	drag = Drag.TIP
	_tip_shift = e.shift_pressed
	_tip_offset = e.position - _tip
	var cam: Camera3D = preview.camera
	_tip_plane = Plane(-cam.global_transform.basis.z, tip_world())
	_tip_hit = _plane_hit(e.position)
	drag_kind = "pos" if _tip_shift else "rot"
	if not _tip_shift: studio.aim_begin()
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	studio.drag_changed()
	return true

func _plane_hit(point: Vector2, plane = null) -> Vector3:
	var cam: Camera3D = preview.camera
	var pixel: Vector2 = point * Vector2(preview.viewport.size) / preview.size
	var pl: Plane = _tip_plane if plane == null else plane
	var hit = pl.intersects_ray(cam.project_ray_origin(pixel), cam.project_ray_normal(pixel))
	return hit if hit != null else Vector3.INF

func _tip_motion(point: Vector2) -> void:
	if _tip_shift:
		var hit := _plane_hit(point)
		if not (hit.is_finite() and _tip_hit.is_finite()): return
		studio.move_paddle(hit - _tip_hit)
		_tip_hit = hit
	else:
		studio.aim_paddle_tip(point - _tip_offset)
	_update_dots(); queue_redraw()

# ---------------------------------------------------------------- AutoPose handles

## Nearest AutoPose handle within `radius` points ("" = none). Locked handles are picked too
## (the press explains the lock instead of orbiting).
func ap_pick(point: Vector2, radius: float = PICK_RADIUS) -> String:
	_update_ap()
	var best := ""
	var best_d := radius
	for i in _ap.size():
		var p: Vector2 = _ap[i]
		if not p.is_finite(): continue
		var d := p.distance_to(point)
		if d < best_d: best_d = d; best = AP_IDS[i]
	return best

## Handle whose lock icon is under `point` ("" = none): locks are shown (and clickable) on pinned
## handles and on the hovered one.
func ap_lock_pick(point: Vector2) -> String:
	_update_ap()
	var best := ""
	var best_d := LOCK_PICK
	for i in _ap.size():
		var p: Vector2 = _ap[i]
		if not p.is_finite(): continue
		var id: String = AP_IDS[i]
		if not (studio.autopose_pinned(id) or id == hover_ap): continue
		var d := (p + LOCK_OFF).distance_to(point)
		if d < best_d: best_d = d; best = id
	return best

## Screen point of a handle (AutoPose handle in AutoPose mode, else the joint dot / tip diamond).
func handle_screen(id: String) -> Vector2:
	if studio != null and studio.autopose_on:
		_update_ap()
		var i := AP_IDS.find(id)
		return _ap[i] if i >= 0 else Vector2.INF
	_update_dots()
	if id == TIP_ID: return _tip
	var j := Fields.JOINT_IDS.find(id)
	return _dots[j] if j >= 0 else Vector2.INF

func _begin_ap(h: String, e: InputEventMouseButton) -> void:
	var b: Dictionary = studio.autopose_drag_begin(h)
	if not b.get("ok", false):
		studio._set_status("AutoPose: " + str(b.get("error", "cannot drag " + h)))
		if touch: studio.handle_tapped.emit(h)   # phone: a locked ring still opens its options (they say why)
		return
	preview.cancel_gesture()
	var w: Vector3 = b.get("handle_start", Vector3.INF)
	if not w.is_finite():
		studio.autopose_drag_end(false, "cancelled"); return
	var cam: Camera3D = preview.camera
	_ap_plane = Plane(-cam.global_transform.basis.z, w)
	ap_target = w
	_ap_offset = e.position - preview._world_screen_position(w)
	if not _ap_offset.is_finite(): _ap_offset = Vector2.ZERO
	ap_handle = h
	drag = Drag.AUTOPOSE
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	studio.drag_changed(); queue_redraw()

## World metres per preview point at the depth of `p` (vertical field of view).
func _metres_per_point(p: Vector3) -> float:
	var cam: Camera3D = preview.camera
	if size.y <= 0: return 0.0
	return cam.global_position.distance_to(p) * 2.0 * tan(deg_to_rad(cam.fov * 0.5)) / size.y

func _ap_motion(e: InputEventMouseMotion) -> void:
	var cam: Camera3D = preview.camera
	if e.shift_pressed:   # depth: mouse up = away from the camera, down = toward it
		var fwd: Vector3 = -cam.global_transform.basis.z
		ap_target += fwd * (-e.relative.y * _metres_per_point(ap_target))
		_ap_plane = Plane(fwd, ap_target)
		var s: Vector2 = preview._world_screen_position(ap_target)
		if s.is_finite(): _ap_offset = e.position - s
	else:
		var hit := _plane_hit(e.position - _ap_offset, _ap_plane)
		if not hit.is_finite(): return
		ap_target = hit
	var r: Dictionary = studio.autopose_drag_move(ap_target)
	if not r.get("ok", false):   # the pose / key changed under the drag: the solver already let go
		drag = Drag.NONE
		studio.autopose_drag_end(false, "ended")
		ap_handle = ""; ap_target = Vector3.INF; arc_stage = -1
		studio.drag_changed()
	_update_ap(); _update_dots(); queue_redraw()

func _arc_shown() -> bool:
	return studio != null and studio.autopose_on and preview._arc_visible and preview.momentum_heads.size() > 1 \
		and preview.motion_root != null and preview.motion_root.visible

func _update_arc() -> bool:
	var dots := PackedVector2Array()
	var keys := PackedVector2Array()
	if _arc_shown():
		for h in preview.momentum_heads: dots.append(preview._world_screen_position(h))
		for h in preview.momentum_keys: keys.append(preview._world_screen_position(h))
	var changed := dots.size() != _arc_dots.size() or keys.size() != _arc_keys.size()
	for i in (dots.size() if not changed else 0):
		if dots[i].is_finite() != _arc_dots[i].is_finite() or (dots[i].is_finite() and dots[i].distance_squared_to(_arc_dots[i]) > 0.04): changed = true; break
	for i in (keys.size() if not changed else 0):
		if keys[i].is_finite() != _arc_keys[i].is_finite() or (keys[i].is_finite() and keys[i].distance_squared_to(_arc_keys[i]) > 0.04): changed = true; break
	var pp := PackedVector2Array()
	if _arc_shown() and studio.path_keys_supported():
		for h in preview.momentum_path_heads: pp.append(preview._world_screen_position(h))
	if pp.size() != _path_pts.size(): changed = true
	for i in (pp.size() if not changed else 0):
		if pp[i].is_finite() != _path_pts[i].is_finite() or (pp[i].is_finite() and pp[i].distance_squared_to(_path_pts[i]) > 0.04): changed = true; break
	_arc_dots = dots; _arc_keys = keys; _path_pts = pp
	return changed

## Wind-up (0) or Finish (2) arc point under `point` (-1 = none). The current key's point is
## left to its rings.
func arc_pick(point: Vector2) -> int:
	_update_arc()
	if _arc_keys.size() < 3: return -1
	var best := -1
	var best_d := _r(ARC_KEY_RADIUS + 3.0)
	for st in [0, 2]:
		if st == studio.stage or not _arc_keys[st].is_finite(): continue
		var d := _arc_keys[st].distance_to(point)
		if d < best_d: best_d = d; best = st
	return best

func _draw_arc(rect: Rect2) -> void:
	if _arc_keys.size() < 3: return
	var k := TOUCH_DRAW if touch else 1.0
	for p in _arc_dots:
		if not p.is_finite() or not rect.has_point(p): continue
		draw_circle(p, 3.2 * k, DOT_OUTLINE, true, -1.0, true)
		draw_circle(p, 2.0 * k, Color(1, 1, 1, 0.92), true, -1.0, true)
	for i in _path_pts.size():
		var p: Vector2 = _path_pts[i]
		if not p.is_finite() or not rect.has_point(p): continue
		var bend: bool = preview.momentum_path_virtual[i] == 1
		var hot: bool = drag == Drag.PATH and absf(preview.momentum_path_t[i] - path_t) < 0.001
		var r := (5.5 if bend else 6.5) * k + (1.5 if hot else 0.0)
		var sq := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_rect(sq.grow(2.0), DOT_OUTLINE, true)
		if bend: draw_rect(sq, DOT_HOVER if hot else PATH_COLOR, false, 2.0)
		else: draw_rect(sq, DOT_HOVER if hot else PATH_COLOR, true)
	var cols: Array = preview.STAGE_COLORS
	for st in 3:
		var p: Vector2 = _arc_keys[st]
		if not p.is_finite() or not rect.has_point(p): continue
		if st == 1:   # Contact, with the strike's peak paddle speed
			draw_circle(p, 4.0 * k, DOT_OUTLINE, true, -1.0, true)
			draw_circle(p, 2.8 * k, cols[1], true, -1.0, true)
			_draw_label(p + Vector2(4, 18) * k, "peak %.0f m/s" % float(preview.momentum_contact_speed))
			continue
		if st == studio.stage: continue
		var hot: bool = arc_stage == st
		var r := ARC_KEY_RADIUS * k + (1.5 if hot else 0.0)
		draw_circle(p, r + 2.0, DOT_OUTLINE, true, -1.0, true)
		draw_circle(p, r, DOT_HOVER if hot else cols[st], false, 2.5, true)
		var font := get_theme_default_font()
		var fs := int(round(get_theme_default_font_size() * 0.8 * k))
		var tw := font.get_string_size("WF"[st / 2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, p + Vector2(-tw.x * 0.5, fs * 0.36), "WF"[st / 2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[st])

## Path key / bend point (or a tick dot: a new key there) under `point`: its progress, -1 = none.
func path_pick(point: Vector2) -> float:
	_update_arc()
	if not studio.path_keys_supported(): return -1.0
	var best := -1.0
	var best_d := _r(ARC_KEY_RADIUS + 2.0)
	for i in _path_pts.size():
		if not _path_pts[i].is_finite(): continue
		var d := _path_pts[i].distance_to(point)
		if d < best_d: best_d = d; best = preview.momentum_path_t[i]
	if best >= 0.0: return best
	best_d = _r(4.0)
	_pick_head = Vector3.INF
	var w: float = preview.momentum_key_times[0] if preview.momentum_key_times.size() > 0 else 0.0
	for i in _arc_dots.size():
		var pr: float = preview.momentum_progress[i] if i < preview.momentum_progress.size() else -1.0
		if pr < 0.0 and w > 0.0:   # a lead-in tick: a new Ready -> Wind-up key there
			var v: float = Ramp.lead(preview._motion_definition, i * preview.TICK / w)
			if v < 0.05 or v > 0.95: continue
			pr = studio.LEAD_IN + v
		elif pr < 0.03 or pr > 0.97 or absf(pr - 0.5) < 0.04: continue
		if not _arc_dots[i].is_finite(): continue
		var d := _arc_dots[i].distance_to(point)
		if d < best_d: best_d = d; best = pr; _pick_head = preview.momentum_heads[i]
	return best

func _begin_path(t: float, e: InputEventMouseButton) -> void:
	var keys: Array = studio.path_keys()
	var idx := -1
	for i in keys.size(): if absf(float(keys[i][0]) - t) < 0.001: idx = i
	var head := Vector3.INF
	for i in preview.momentum_path_t.size(): if absf(preview.momentum_path_t[i] - t) < 0.001: head = preview.momentum_path_heads[i]
	if not head.is_finite():   # a tick dot: its head on the arc
		for i in preview.momentum_progress.size(): if absf(preview.momentum_progress[i] - t) < 0.0001: head = preview.momentum_heads[i]
	if not head.is_finite() and studio.is_lead_in(t): head = _pick_head
	if not head.is_finite(): return
	preview.cancel_gesture()
	studio.begin_edit("path key")
	if idx < 0:
		keys.append([t, Vector3.ZERO])
		studio.set_path_keys(keys)
		t = float(studio.path_keys().filter(func(k): return absf(float(k[0]) - t) < 0.03)[0][0]) if studio.path_keys().size() > 0 else t
		_path_off0 = Vector3.ZERO
	else: _path_off0 = keys[idx][1]
	path_t = t
	_path_head0 = head
	_path_plane = Plane(-preview.camera.global_transform.basis.z, head)
	_path_grab = e.position - preview._world_screen_position(head)
	if not _path_grab.is_finite(): _path_grab = Vector2.ZERO
	_path_moved = false
	drag = Drag.PATH
	studio.drag_changed(); queue_redraw()

func _path_motion(point: Vector2) -> void:
	var hit := _plane_hit(point - _path_grab, _path_plane)
	if not hit.is_finite(): return
	var d: Vector3 = hit - _path_head0
	if d.length() > 0.002: _path_moved = true
	var p = preview.player
	var off: Vector3 = _path_off0 + Vector3(d.dot(p._get_forehand_axis()), d.y, d.dot(p._get_forward_axis()))
	var keys: Array = studio.path_keys()
	for k in keys: if absf(float(k[0]) - path_t) < 0.001: k[1] = off
	studio.set_path_keys(keys)
	_update_arc(); queue_redraw()

## Data for ui_dump / the link: the momentum arc in preview points.
func arc_state() -> Dictionary:
	_update_arc()
	var pt = func(p: Vector2): return [p.x, p.y] if p.is_finite() else null
	return {"shown": _arc_shown(), "ticks": _arc_dots.size(), "dots": Array(_arc_dots).map(pt), "keys": Array(_arc_keys).map(pt),
		"key_times": Array(preview.momentum_key_times), "contact_speed": preview.momentum_contact_speed,
		"heads": Array(preview.momentum_heads).map(func(h: Vector3): return [snappedf(h.x, 0.001), snappedf(h.y, 0.001), snappedf(h.z, 0.001)]),
		"dragging": arc_stage, "path": Array(_path_pts).map(pt), "path_t": Array(preview.momentum_path_t),
		"path_bend": Array(preview.momentum_path_virtual), "progress": Array(preview.momentum_progress)}

func _update_ap() -> bool:
	var n := AP_IDS.size()
	var changed := false
	if _ap.size() != n:
		_ap.resize(n); _ap.fill(Vector2.INF); _ap_world.resize(n); changed = true
	var on: bool = studio != null and studio.autopose_on and studio._ok() and preview.player != null
	var w: Dictionary = studio.autopose_solver().handle_points(preview.player) if on else {}
	var tip_ok: bool = on and studio.tip_available()
	for i in n:
		var id: String = AP_IDS[i]
		var p3: Vector3 = w.get(id, Vector3.INF)
		if (id == "paddle_tip" or id in AP_EDGES) and not tip_ok: p3 = Vector3.INF
		_ap_world[i] = p3
		var p: Vector2 = preview._world_screen_position(p3) if p3.is_finite() else Vector2.INF
		var old: Vector2 = _ap[i]
		if p.is_finite() != old.is_finite() or (p.is_finite() and p.distance_squared_to(old) > 0.04):
			_ap[i] = p; changed = true
	return changed

func _ap_color(id: String) -> Color:
	if id in ["hips", "chest", "head"] or id in AP_ROTATE: return AP_BODY
	if id in AP_EDGES: return TIP_COLOR
	if id.ends_with("_knee") or id.ends_with("_foot"): return AP_LEG
	return TIP_COLOR if id == TIP_ID else AP_ARM

func _ap_label(id: String) -> String:
	var t: String = AP_NAMES.get(id, id)
	var why: String = studio.autopose_lock_reason(id)
	var pin: String = " · pinned" if studio.autopose_pinned(id) else ""
	return t + pin + (" - locked: " + why if why != "" else " - drag: the body follows (Shift = depth)")

func _lock_label(id: String) -> String:
	var t: String = AP_NAMES.get(id, id)
	if studio.autopose_pinned(id):
		if studio._contact_paddle_handle(id) and not studio.gameplay_edit: return t + " pinned (Contact paddle, gameplay): Gameplay edit unpins it"
		return t + " pinned: holds while you drag others · click to unpin"
	return t + ": click to pin (holds while you drag others)"

func _draw_lock(c: Vector2, pinned: bool, hot: bool) -> void:
	var col: Color = DOT_HOVER if hot else PIN_COLOR if pinned else Color(DOT_COLOR, 0.85)
	draw_circle(c, 7.0, Color(DOT_OUTLINE, 0.9), true, -1.0, true)
	var body := Rect2(c + Vector2(-3.5, -0.5), Vector2(7, 5))
	if pinned: draw_rect(body, col, true)
	else: draw_rect(body, col, false, 1.4)
	var sh := c + Vector2(0, -0.5) if pinned else c + Vector2(1.6, -1.6)   # open shackle lifts and swings out
	draw_arc(sh, 2.4, PI, TAU, 10, col, 1.4, true)
	draw_line(sh + Vector2(-2.4, 0), sh + Vector2(-2.4, 0.6 if pinned else -0.2), col, 1.4, true)
	draw_line(sh + Vector2(2.4, 0), sh + Vector2(2.4, 0.6), col, 1.4, true)

func _draw_ap(rect: Rect2) -> void:
	for i in _ap.size():
		var p: Vector2 = _ap[i]
		if not p.is_finite() or not rect.has_point(p): continue
		var id: String = AP_IDS[i]
		var locked: bool = studio.autopose_lock_reason(id) != ""
		var hot: bool = id == ap_handle or id == hover_ap
		var col: Color = DOT_HOVER if hot else AP_LOCKED if locked else _ap_color(id)
		var r := AP_RADIUS * (TOUCH_DRAW if touch else 1.0) + (1.5 if hot else 0.0)
		if id in AP_EDGES:   # small diamond on the rim
			r -= 1.5
			var o := r + 2.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -o), p + Vector2(o, 0), p + Vector2(0, o), p + Vector2(-o, 0)]), DOT_OUTLINE)
			draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), col, 2.0, true)
		elif id in AP_ROTATE:   # ring + turn arc with an arrow head
			draw_circle(p, r + 2.0, DOT_OUTLINE, true, -1.0, true)
			draw_circle(p, r, col, false, 2.5, true)
			draw_arc(p, r + 4.5, -PI * 0.9, -PI * 0.1, 10, DOT_OUTLINE, 3.5, true)
			draw_arc(p, r + 4.5, -PI * 0.9, -PI * 0.1, 10, col, 1.6, true)
			var a := p + Vector2(cos(-PI * 0.1), sin(-PI * 0.1)) * (r + 4.5)
			draw_line(a, a + Vector2(-3.5, -2.0), col, 1.6, true); draw_line(a, a + Vector2(0.5, -4.0), col, 1.6, true)
		elif id == TIP_ID:
			var o := r + 2.5
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -o), p + Vector2(o, 0), p + Vector2(0, o), p + Vector2(-o, 0)]), DOT_OUTLINE)
			draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), col, 2.5, true)
		else:
			draw_circle(p, r + 2.0, DOT_OUTLINE, true, -1.0, true)
			draw_circle(p, r, col, false, 2.5, true)
		draw_circle(p, 1.8, col, true, -1.0, true)
		if locked: draw_line(p + Vector2(-r, r), p + Vector2(r, -r), col, 2.0, true)
		var pinned: bool = studio.autopose_pinned(id)
		if pinned or (id == hover_ap and drag != Drag.AUTOPOSE): _draw_lock(p + LOCK_OFF, pinned, id == hover_ap and hover_lock)
	if drag == Drag.AUTOPOSE and ap_target.is_finite():   # where the mouse wants the handle
		var t: Vector2 = preview._world_screen_position(ap_target)
		var i := AP_IDS.find(ap_handle)
		if t.is_finite():
			if i >= 0 and _ap[i].is_finite() and _ap[i].distance_to(t) > 2.0: draw_dashed_line(_ap[i], t, DOT_HOVER, 1.5, 4.0)
			draw_line(t + Vector2(-5, 0), t + Vector2(5, 0), DOT_HOVER, 1.5); draw_line(t + Vector2(0, -5), t + Vector2(0, 5), DOT_HOVER, 1.5)
	var lab := ap_handle if ap_handle != "" else hover_ap
	var li := AP_IDS.find(lab)
	if li >= 0 and _ap[li].is_finite():
		_draw_label(_ap[li] + (LOCK_OFF if hover_lock else Vector2.ZERO), String(AP_NAMES.get(lab, lab)) if drag == Drag.AUTOPOSE
			else _lock_label(lab) if hover_lock else _ap_label(lab))

func _draw_label(p: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := Vector2(clampf(p.x + 12.0, 2.0, maxf(2.0, size.x - tw.x - 10.0)), clampf(p.y - 10.0, tw.y + 2.0, size.y - 4.0))
	draw_rect(Rect2(at + Vector2(-5, -tw.y), tw + Vector2(10, 6)), Color(DOT_OUTLINE, 0.85))
	draw_string(font, at + Vector2(0, -3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DOT_HOVER)

## Data for ui_dump / the link `autopose_handles`: every AutoPose handle in preview points.
func autopose_state() -> Dictionary:
	_update_ap()
	var rect := Rect2(Vector2.ZERO, size)
	var hs: Array = []
	for i in _ap.size():
		var id: String = AP_IDS[i]
		var p: Vector2 = _ap[i]
		var w: Vector3 = _ap_world[i]
		var lk: Vector2 = p + LOCK_OFF
		hs.append({"id": id, "name": AP_NAMES[id], "x": p.x if p.is_finite() else null, "y": p.y if p.is_finite() else null,
			"inside": p.is_finite() and rect.has_point(p), "world": [w.x, w.y, w.z] if w.is_finite() else null,
			"locked": studio.autopose_lock_reason(id) != "", "reason": studio.autopose_lock_reason(id), "hover": id == hover_ap,
			"pinned": studio.autopose_pinned(id), "lock": [lk.x, lk.y] if p.is_finite() else null,
			"lock_shown": p.is_finite() and (studio.autopose_pinned(id) or id == hover_ap)})
	var t: Vector2 = preview._world_screen_position(ap_target) if ap_target.is_finite() else Vector2.INF
	return {"on": studio.autopose_on, "dragging": drag == Drag.AUTOPOSE, "handle": ap_handle, "hover_lock": hover_lock,
		"target": [ap_target.x, ap_target.y, ap_target.z] if ap_target.is_finite() else null,
		"target_screen": [t.x, t.y] if t.is_finite() else null, "handles": hs}

# ---------------------------------------------------------------- joint dots

## Nearest joint dot within `radius` points of `point`.
func pick(point: Vector2, radius: float = PICK_RADIUS, with_tip := true) -> String:
	_update_dots()
	var best := ""
	var best_d := radius
	for i in _dots.size():
		var p: Vector2 = _dots[i]
		if not p.is_finite(): continue
		var d := p.distance_to(point)
		if d < best_d: best_d = d; best = Fields.JOINT_IDS[i]
	if with_tip and _tip.is_finite() and _tip.distance_to(point) < best_d: best = TIP_ID
	return best

func _hover(point: Vector2) -> void:
	if studio != null and studio.autopose_on:
		var core := ap_pick(point, _r(AP_RADIUS + 2.0))
		var lk := ap_lock_pick(point) if core == "" else ""
		var h := core if core != "" else lk if lk != "" else ap_pick(point)
		var on_lock: bool = lk != ""
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
		if hover_joint != "": hover_joint = ""
		if h == hover_ap and on_lock == hover_lock: return
		hover_ap = h; hover_lock = on_lock
		tooltip_text = (_lock_label(h) if on_lock else _ap_label(h)) if h != "" else ""
		queue_redraw(); return
	if hover_ap != "": hover_ap = ""
	var gz = preview.gizmo
	var core := pick(point, DOT_CORE)
	if core == preview.selected_joint: core = ""
	var on_handle: bool = core == "" and gz != null and gz.visible and gz.enabled and gz.hit_axis(point) >= 0
	var id := core if core != "" else "" if on_handle else pick(point)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (id != "" or on_handle) else Control.CURSOR_ARROW
	if id == hover_joint: return
	hover_joint = id
	tooltip_text = _name(id) if id != "" else ""
	queue_redraw()

func _name(id: String) -> String:
	return TIP_NAME if id == TIP_ID else String(preview.JOINT_NAMES.get(id, id))

func _update_dots() -> bool:
	var changed := false
	var t: Vector2 = preview._world_screen_position(tip_world()) if studio != null and studio.tip_available() else Vector2.INF
	if t.is_finite() != _tip.is_finite() or (t.is_finite() and t.distance_squared_to(_tip) > 0.04):
		_tip = t; changed = true
	for i in Fields.JOINT_IDS.size():
		var p: Vector2 = preview.joint_screen_position(Fields.JOINT_IDS[i])
		var old: Vector2 = _dots[i]
		if p.is_finite() != old.is_finite() or (p.is_finite() and p.distance_squared_to(old) > 0.04):
			_dots[i] = p; changed = true
	return changed

func _process(_delta: float) -> void:
	if preview != null and is_visible_in_tree():
		var a := _update_dots()
		var b := _update_ap()
		var c := _update_arc()
		if a or b or c: queue_redraw()

func _draw() -> void:
	if preview == null: return
	var rect := Rect2(Vector2.ZERO, size)
	if studio != null and studio.autopose_on: _draw_arc(rect); _draw_ap(rect); return
	var sel: String = preview.selected_joint
	for i in _dots.size():
		var p: Vector2 = _dots[i]
		if not p.is_finite() or not rect.has_point(p): continue
		var id: String = Fields.JOINT_IDS[i]
		var hov := id == hover_joint
		var r := DOT_RADIUS + (1.5 if hov else 0.0)
		if id == sel:
			draw_circle(p, r + 4.0, DOT_OUTLINE, false, 4.0, true)
			draw_circle(p, r + 4.0, SELECT_COLOR, false, 2.0, true)
		draw_circle(p, r + 1.5, DOT_OUTLINE, true, -1.0, true)
		draw_circle(p, r, DOT_HOVER if hov else SELECT_COLOR if id == sel else DOT_COLOR, true, -1.0, true)
	if _tip.is_finite() and rect.has_point(_tip):
		var hov := hover_joint == TIP_ID or drag == Drag.TIP
		var r := DOT_RADIUS + 1.0 + (1.5 if hov else 0.0)
		var o := r + 1.8
		draw_colored_polygon(PackedVector2Array([_tip + Vector2(0, -o), _tip + Vector2(o, 0), _tip + Vector2(0, o), _tip + Vector2(-o, 0)]), DOT_OUTLINE)
		draw_colored_polygon(PackedVector2Array([_tip + Vector2(0, -r), _tip + Vector2(r, 0), _tip + Vector2(0, r), _tip + Vector2(-r, 0)]),
			DOT_HOVER if hov else TIP_COLOR if studio.at_key() else Color(TIP_COLOR, 0.45))
	if hover_joint != "":
		var i := Fields.JOINT_IDS.find(hover_joint)
		var p: Vector2 = _tip if hover_joint == TIP_ID else _dots[i] if i >= 0 else Vector2.INF
		if p.is_finite():
			var font := get_theme_default_font()
			var fs := get_theme_default_font_size()
			var text := _name(hover_joint)
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var at := Vector2(clampf(p.x + 12.0, 2.0, maxf(2.0, size.x - tw.x - 10.0)), clampf(p.y - 10.0, tw.y + 2.0, size.y - 4.0))
			draw_rect(Rect2(at + Vector2(-5, -tw.y), tw + Vector2(10, 6)), Color(DOT_OUTLINE, 0.85))
			draw_string(font, at + Vector2(0, -3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DOT_HOVER)

## Data for ui_dump: every joint dot in preview-local points.
func dots_state() -> Array:
	_update_dots()
	var out: Array = []
	var rect := Rect2(Vector2.ZERO, size)
	for i in _dots.size():
		var p: Vector2 = _dots[i]
		out.append({"id": Fields.JOINT_IDS[i], "x": p.x if p.is_finite() else null, "y": p.y if p.is_finite() else null,
			"inside": p.is_finite() and rect.has_point(p), "selected": Fields.JOINT_IDS[i] == preview.selected_joint,
			"hover": Fields.JOINT_IDS[i] == hover_joint})
	if studio != null and studio.tip_available():
		var tw := tip_world()
		out.append({"id": TIP_ID, "kind": "tip", "x": _tip.x if _tip.is_finite() else null, "y": _tip.y if _tip.is_finite() else null,
			"inside": _tip.is_finite() and rect.has_point(_tip), "selected": false, "hover": hover_joint == TIP_ID,
			"tooltip": TIP_NAME, "world": [tw.x, tw.y, tw.z] if tw.is_finite() else null})
	return out

## Alt alone (no mouse move) also switches the paddle hand's Move gizmo to the grip slide.
func _input(event: InputEvent) -> void:
	if studio == null or not (event is InputEventKey): return
	if event.keycode == KEY_ALT or event.physical_keycode == KEY_ALT: studio.set_hand_slide(event.pressed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and drag == Drag.NONE:
		if hover_joint != "" or hover_ap != "": hover_joint = ""; hover_ap = ""; hover_lock = false; queue_redraw()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel()
