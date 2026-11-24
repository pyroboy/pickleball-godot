extends RefCounted

# Gameplay viewpoints are separate from the pose editor's orbit controls.
const CENTER: = 0
const THIRD_PERSON: = 1
const POV: = 2
const FIRST_PERSON: = 3
## First person: the camera is your player's head. It sits at the eyes and faces wherever the
## head faces; the head itself turns toward the ball the way a person's does (player_head_gaze.gd:
## authored head angle plus a limited, smoothed pull toward the ball), so the ball can leave the
## view. The eyes then move inside the head toward the ball, up to FP_EYE_RANGE_DEG, as real
## eyes do. Your torso, hands, paddle, legs and shoes are drawn.
const FP_FOV := 78.0               # degrees across the screen width
const FP_EYE_RANGE_DEG := 25.0      # how far the eyes turn inside the head
const FP_EYE_RATE := 8.0            # 1/s: how quickly they settle on the ball (12 read as a whip on screen)
## The view copies the head exactly: its turns, tilt and shake are the look (user's call,
## 2026-11-25: build 78's follow is the one to keep). Between points the eye rides the drawn
## head instead (walks and strolls are drawn-only motion), eased in and out over FP_WALK_RATE.
const FP_WALK_RATE := 3.0           # 1/s
## Extra neck turn, for the view only (the gameplay head is not touched): what this player's
## eyes would follow beyond the head's own small turn.
##  - your partner's ball: the view turns on with the ball so you watch your partner play;
##  - between points: the ball while it is fetched, picked up, thrown and caught; the catcher
##    as you wind up a throw; where you walk when you carry it or walk back (the look leads
##    the body into a turn).
## Zero in every other case, so a ball that is yours looks exactly as before.
const FP_NECK_RATE := 5.0           # 1/s: a head turn, slower than the eyes
const FP_NECK_PARTNER := Vector3(130.0, 15.0, 15.0)  # degrees: sideways (far enough to look back at a partner on the baseline while you are at the kitchen), down, up
## Between points the turn is free: it stands in for the body, which the walk turns right round
## (the 3D head the view sits on keeps facing the net; the drawn walk does not).
const FP_NECK_BETWEEN := Vector3(180.0, 50.0, 20.0)
const FP_PARTNER_NEARER_M := 0.3    # the ball is your partner's when it is this much nearer them
const FP_PARTNER_LEAD_S := 0.4      # ... judged where the ball will be this soon, so the turn starts as it heads their way
const FP_NECK_RATE_PARTNER := 7.0   # 1/s: a quick look round
## Interest: the gaze only leaves the ball for something that has held for a moment, and a look
## behind you needs a stronger reason than a look to the side (it used to look back on any small
## backward step, or the instant a ball was predicted nearer your partner).
const FP_PARTNER_BEHIND_M := 1.5    # partner this much farther from the net than you = behind you
const FP_PARTNER_NEARER_BEHIND_M := 1.0   # then the ball must be this much nearer them
const FP_PARTNER_MINE_M := 1.6      # never while the ball will be this close to you
const FP_PARTNER_DWELL_S := 0.12    # the ball must be theirs this long before the head turns
const FP_PARTNER_HOLD_S := 0.35     # and the look holds this long, so it does not flick back and forth
const FP_WALK_DWELL_S := 0.3        # walking this long before the eyes go where you walk
const FP_WALK_BACK_DWELL_S := 0.6   # ... longer, and at FP_WALK_BACK_SPEED or more, to look behind you
const FP_WALK_BACK_SPEED := 1.0
## Neck damping: the turn eases in and out (speed limited by an acceleration and a top speed)
## instead of starting at full speed.
## Modelled on a person: the eyes jump to the target first (FP_EYE_RATE, within FP_EYE_RANGE_DEG),
## the head follows more slowly and the eyes settle back to centre as it arrives. A head turns
## quickly only through FP_NECK_FREE_DEG either side; past that the body has to turn, which is
## slower (FP_BODY_TURN_SPEED). How brisk the head is depends on what it is for:
## [top speed deg/s, acceleration deg/s2].
const FP_NECK_DYNAMICS := {"rally": [180.0, 600.0],      # a ball in play: your partner's, or one flying past
	"between": [140.0, 420.0],                              # fetching, watching, a throw, a tap
	"walk": [95.0, 260.0]}                                  # looking where you walk: an unhurried turn
const FP_NECK_FREE_DEG := 80.0
const FP_BODY_TURN_SPEED := 105.0
var _fp_neck_speed := 0.0
## Up-and-down steadying (user, 2026-11-25: the view shook up and down on every tap or hold of
## HIT and in slow motion). Pressing HIT changes the pose (split-step dip, wind-up crouch and
## lean), which moves the head's height and tilts it forward and back. The eye's height above
## the body and the head's forward tilt are eased; turning left-right and side tilt are not, so
## the head's own shake stays. The eyes still follow the ball up and down on top of this.
const FP_HEIGHT_RATE := 3.0         # 1/s
const FP_HEIGHT_MAX_OFF := 0.07     # m the steadied eye may sit from the real one
const FP_PITCH_RATE := 3.5          # 1/s
const FP_PITCH_MAX_OFF := 12.0      # degrees
var _fp_height := NAN
var _fp_pitch := NAN
## Left-right steadying at the press: as HIT goes down (and comes up) the wind-up turns the body,
## and the head turned and slid sideways with it (measured: the view's turn changed 5 times more
## sharply in the first quarter second after a press). The head's turn relative to your body
## and the eye's sideways place are eased too; the eyes keep the ball.
const FP_YAW_RATE := 4.0            # 1/s
const FP_YAW_MAX_OFF := 25.0        # degrees
const FP_SIDE_RATE := 5.0           # 1/s
const FP_SIDE_MAX_OFF := 0.06       # m
var _fp_yaw := NAN
var _fp_side := Vector2.INF
## How far the head may turn beyond the 3D head's own turn toward the ball (about 25 degrees).
## The view never goes right round: at the limit the head is about 120 degrees from the way the
## feet face, with the eyes adding 25 more, so a partner on the baseline behind you is in view
## at the side of the screen, not dead centre. A turn that large is not all neck: the drawn
## body turns with it (card_motion_layer.gd _look_turn: chest up to 75 degrees, hips half of
## that), so the head stays within about 50 degrees of the chest you see. (User, 2026-11-25:
## keep seeing the partner and the feet, but no look straight back over the shoulder.)
const FP_NECK_MAX_YAW := 95.0
## ... and, whatever the pose has done with the 3D head, never further than this from the way
## the body itself faces (the body pivot, which the cards and your own arms are drawn from).
const FP_HEAD_MAX_FROM_BODY := 120.0
var _fp_body_local := Vector3.FORWARD   # the body's heading in the head's frame (-z = as the 3D body)
var _fp_body_world := Vector3.ZERO      # set by _fp_gaze: the walk direction, or ZERO for "as the 3D body"
## Balls you cannot play are still watched: one flying past you or going out, and the dead ball
## for a moment after the point ends.
const FP_NECK_PASSING := Vector3(150.0, 40.0, 30.0)
const FP_PASS_BEHIND_M := 0.4       # this far past you (away from the net)
const FP_PASS_OUT_M := 0.2          # this far outside the lines
const FP_PASS_DWELL_S := 0.06
const FP_AFTER_POINT_S := 1.2       # keep watching the ball this long after the point ends
var _fp_pass_t := 0.0
var _fp_dead_t := 99.0
## A ball thrown in by the ball picker outside the court: no swing round to follow it. Only
## whoever catches it looks, and only within these limits.
const FP_NECK_HELPER := Vector3(60.0, 25.0, 20.0)
## Your own serve: the view looks down the line the serve is aimed along (so the aim arc is in
## front of you), tilted down just enough to keep the ball in your hand in the picture. The
## aim is centred left-right; up-down the view sits between the aim point and the ball, and if
## a short screen cannot hold both, the aim wins.
const FP_NECK_SERVE := Vector3(70.0, 45.0, 40.0)
const FP_SERVE_BALL_SHARE := 0.45   # how far down from the aim toward the ball the view sits
const FP_SERVE_EDGE := 0.8          # both are kept inside this share of the half-height of the view
var _fp_half_v := deg_to_rad(40.0)  # half the view's height, set every frame
var _fp_dt := 0.0
var _fp_partner_t := 0.0
var _fp_partner_hold := 0.0
var _fp_walk_t := 0.0
## Reading the head live (instead of interpolated) on frames where the pose was rewritten
## between physics ticks. OFF: measured twice on 2026-11-25. In the same run the live pose is
## about three times jerkier than the interpolated one the game draws (jerk / speed 1.5 against
## 0.5 for the paddle and torso), and the view reversed direction more often with it on. The
## interpolated read is the smooth one, HIT held or not. 0.2 turns it back on.
const FP_LIVE_HOLD_S := 0.0
const FP_LIVE_RATE := 10.0          # 1/s blend in and out
var _fp_live := 0.0
var _fp_live_left := 0.0
var _fp_live_tick := -1
var _fp_live_frame := -1
var _fp_live_rel := Transform3D.IDENTITY
const FP_CHEST_UP := 0.35           # m above a player's origin (which is at the waist, 1 m up): their chest
const FP_WALK_LOOK_SPEED := 0.4     # m/s: from here "ahead" is where you walk
var _fp_neck_local := Vector3.FORWARD   # neck turn in the head's frame (-z = none)
var fp_gaze_kind := ""              # tests: what the eyes are on this frame
var _fp_walk := 0.0                 # 0 = gameplay head (rallies), 1 = drawn head (between points)
var _fp_eye_local := Vector3.FORWARD   # gaze in the head's own frame (-z = straight ahead)
var _fp_indicator: CanvasLayer = null  # ball_offscreen_indicator.gd while first person is on
var _fp_camera: Camera3D = null
var _fp_player: Node3D = null
var _fp_ball: Node3D = null
const TRANSITION_SECONDS: = 0.65
# Doubles serve view: a longer, softer move in and out (smootherstep), a
# damped follow so the server's small shuffles don't jolt the frame, and a
# slow push-in while the serve charges.
const DOUBLES_SERVE_TRANSITION: = 1.05
const DOUBLES_FOLLOW_RATE: = 4.0
var _transition_seconds: float = TRANSITION_SECONDS
var _serve_cam_pos: = Vector3.INF
var _serve_cam_look: = Vector3.INF
var _serve_push: float = 0.0
const Layout = preload("res://scripts/ui/mobile_layout.gd")
var _controls: Node
var _ball_aim: float = 0.0      # 0 = normal framing, 1 = aimed at the ball
var _ball_aim_usec: int = 0

# The camera updates every rendered frame (camera_rig._process), so it follows
# what is drawn: interpolated transforms, not the last 30 Hz physics tick.
static func _d(node: Node3D) -> Vector3:
	return node.get_global_transform_interpolated().origin
var mode: = CENTER
var active_kind: = "center"
var _previous_kind: = ""
var _transition_from: = Transform3D.IDENTITY
var _transition_fov: = 60.0
var _transition_offset: = 0.0
var _transition_elapsed: = TRANSITION_SECONDS
var _last_direction: = Vector3.FORWARD
var _hidden_meshes: Array[Dictionary] = []
var _fp_rig: Node = null

func set_mode(value: int) -> void:
	mode = clampi(value, CENTER, FIRST_PERSON)
	_previous_kind = ""
	restore_avatar()

func suspend() -> void:
	restore_avatar()
	_previous_kind = ""

func restore_avatar() -> void:
	_set_first_person_cards(null)
	if is_instance_valid(_fp_indicator): _fp_indicator.queue_free()
	_fp_indicator = null
	for entry in _hidden_meshes:
		if is_instance_valid(entry.mesh):
			entry.mesh.cast_shadow = entry.shadow
			entry.mesh.layers = entry.layers
	_hidden_meshes.clear()

func _hide_avatar(player: Node3D) -> void:
	if not _hidden_meshes.is_empty(): return
	# Keep pose data, physics and cast shadows. Hide the local avatar surfaces
	# from inside the head, where body/arms would otherwise cover a low ball.
	var body: Node = player.get_node_or_null("BodyPivot")
	if body == null: return
	for node in body.find_children("*", "GeometryInstance3D", true, false):
		_hidden_meshes.append({"mesh": node, "shadow": node.cast_shadow, "layers": node.layers})
		if node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			node.layers = 0
		else:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

func update(rig, delta: float) -> bool:
	var game: Node = rig._game_root
	var camera: Camera3D = rig.camera
	if game == null or camera == null: return false
	_controls = game.get("mobile_controls")
	# The controlled player is Blue. Receiving must retain Blue's centered
	# viewpoint rather than following the opponent's serving perspective.
	var serving: bool = not rig._is_practice() and not game.match_over and game.human_may_serve() and int(game.game_state) in [0, 1]
	var kind: String = "fp" if mode == FIRST_PERSON else "pov" if mode == POV else "third" if mode == THIRD_PERSON else ("serve2" if game.doubles_mode else "serve0") if serving else "center"
	var previous_transform: Transform3D = camera.global_transform
	var previous_fov: float = camera.fov
	var previous_aspect: int = camera.keep_aspect
	var previous_offset: float = camera.v_offset
	var player: Node3D = rig._player_left
	if kind == "fp":
		active_kind = kind
		_previous_kind = kind
		_transition_elapsed = TRANSITION_SECONDS
		update_first_person(camera, player, rig._ball, delta, false)
		return true
	if kind == "serve2":
		var human: Node3D = game.get_human_actor()
		if human != null: player = human
	if kind == "pov":
		active_kind = kind
		_previous_kind = kind
		_transition_elapsed = TRANSITION_SECONDS
		_update_pov(camera, player, rig._ball, delta)
		return true
	restore_avatar()
	if kind == "center":
		rig._update_centered(delta)
	elif kind == "serve2" or kind == "serve0":
		_update_doubles_serve(camera, player, game, delta, _previous_kind != kind, kind == "serve2")
	else:
		_update_third(camera, player, rig._ball, -1.0 if player.court_side == 1 else 1.0)
	var desired: Transform3D = camera.global_transform
	var desired_fov: float = camera.fov
	var desired_offset: float = camera.v_offset
	if kind != _previous_kind:
		_transition_from = previous_transform
		_transition_fov = convert_fov(previous_fov, previous_aspect, camera.keep_aspect, camera.get_viewport().get_visible_rect().size)
		_transition_offset = previous_offset
		# Into and out of the doubles serve view the move is longer and eased
		# at both ends; every other switch keeps the original timing.
		_transition_seconds = DOUBLES_SERVE_TRANSITION if kind in ["serve0", "serve2"] or _previous_kind in ["serve0", "serve2"] else TRANSITION_SECONDS
		_transition_elapsed = 0.0 if not _previous_kind.is_empty() else _transition_seconds
		_previous_kind = kind
	active_kind = kind
	_transition_elapsed = minf(_transition_seconds, _transition_elapsed + maxf(delta, 0.0))
	var blend: float = _ease_transition(_transition_elapsed / _transition_seconds, kind in ["serve0", "serve2"] or _transition_seconds > TRANSITION_SECONDS)
	camera.global_transform = _transition_from.interpolate_with(desired, blend) if blend < 1.0 else desired
	camera.fov = lerpf(_transition_fov, desired_fov, blend)
	camera.v_offset = lerpf(_transition_offset, desired_offset, blend)
	# The centre view is a fixed framing: it never swings round to chase the
	# ball. The behind-the-player view still keeps the ball in frame.
	if kind != "center": _keep_ball_visible(camera, rig._ball)
	return true

func _update_third(camera: Camera3D, player: Node3D, ball: Node3D, side: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.04
	var portrait: bool = Layout.is_portrait(camera.get_viewport().get_visible_rect().size)
	camera.fov = 52.0 if portrait else 64.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var body: Vector3 = _d(player) + Vector3(0, -0.2, 0)
	var position: Vector3 = _d(player) + Vector3((0.45 if portrait else 0.65) * side, 2.8 if portrait else 2.0, 3.5 * side)
	# Stay in front of the far boards and inside the side boards, including a
	# Red baseline serve. This is camera placement, not drawing through scenery.
	position.z = clampf(position.z, -9.12, 9.12)
	position.x = clampf(position.x, -5.05, 5.05)
	camera.global_position = position
	var target: Vector3 = body + Vector3(0, 0.0, -3.0 * side)
	if is_instance_valid(ball): target = body.lerp(_d(ball), 0.55)
	# Lift the aim slightly to lower the scene on screen, while the higher
	# shoulder gives the court a scale/angle closer to the main rally view.
	target.y += 0.45 if portrait else 0.0
	_look_at(camera, target)
	_keep_ball_visible(camera, ball)

func transition_done() -> bool:
	return _transition_elapsed >= _transition_seconds

static func _ease_transition(t: float, soft: bool) -> float:
	t = clampf(t, 0.0, 1.0)
	if not soft: return t * t * (3.0 - 2.0 * t)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

## Doubles serve: behind the server's outside shoulder, looking down the
## diagonal at the receiver's box, so the crosscourt serve reads up the screen
## with the receiver and both partners in frame. Same height/fov family as the
## singles serve view so the two feel like one camera.
## Serve view (singles and doubles): behind the server, turned to follow where the serve
## is aimed (the aim target), so the camera tracks the trajectory's direction while it
## stays behind the player. Damped, with a push-in while the serve charges.
func _update_doubles_serve(camera: Camera3D, player: Node3D, game: Node, delta: float, entering: bool, doubles := true) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.04
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var portrait: bool = Layout.is_portrait(camera.get_viewport().get_visible_rect().size)
	var me: Vector3 = _d(player)
	var forward: float = 1.0 if me.z > 0.0 else -1.0   # toward the net from my side
	forward = -forward
	var aim: Vector3 = _aim_point(game)
	if not aim.is_finite():
		var receiver: Node3D = game.get_receiver_actor()
		aim = _d(receiver) if receiver != null else Vector3(-me.x, 0.0, -me.z * 0.8)
	var diag: Vector3 = Vector3(aim.x - me.x, 0.0, aim.z - me.z)
	if diag.length_squared() < 1.0: diag = Vector3(0, 0, forward)
	diag = diag.normalized()
	# Lean the view only part-way onto the diagonal: fully diagonal hides the
	# near sideline; straight down the court loses the receiver.
	var view_dir: Vector3 = Vector3(0, 0, forward).lerp(diag, 0.8).normalized()
	var outside: Vector3 = Vector3(signf(me.x) if absf(me.x) > 0.05 else 1.0, 0, 0)
	var charging: bool = bool(game.get("serve_is_charging")) and game.game_serve != null
	var charge: float = game.game_serve.get_charge_ratio() if charging else 0.0
	var dt: float = maxf(delta, 0.0)
	_serve_push = move_toward(_serve_push, smoothstep(0.0, 1.0, charge), dt * (1.6 if charging else 2.5))
	var back: float = (3.55 if doubles else 3.5) - 0.55 * _serve_push
	var height: float = ((3.0 if doubles else 2.8) if portrait else 2.1) - 0.25 * _serve_push
	var side: Vector3 = Vector3.UP.cross(view_dir).normalized()      # over the outside shoulder
	if side.dot(outside) < 0.0: side = -side
	var desired_pos: Vector3 = me - view_dir * back + Vector3.UP * height + side * ((0.95 if doubles else 0.5) if portrait else 1.0)
	desired_pos.z = clampf(desired_pos.z, -9.12, 9.12)
	desired_pos.x = clampf(desired_pos.x, -5.05, 5.05)
	# Look a little ahead of the server along the diagonal, lifted like the
	# singles view so the far court sits higher on screen.
	var desired_look: Vector3 = me + view_dir * (0.7 + 0.5 * _serve_push) + Vector3.UP * (0.5 if portrait else 0.2)
	if entering or not _serve_cam_pos.is_finite():
		_serve_cam_pos = desired_pos
		_serve_cam_look = desired_look
	else:
		var k: float = 1.0 - exp(-DOUBLES_FOLLOW_RATE * dt)
		_serve_cam_pos = _serve_cam_pos.lerp(desired_pos, k)
		_serve_cam_look = _serve_cam_look.lerp(desired_look, k)
	camera.fov = ((50.0 if doubles else 52.0) if portrait else 62.0) - 3.0 * _serve_push
	camera.global_position = _serve_cam_pos
	_look_at(camera, _serve_cam_look)

## Where the human is aiming (the landing target), or INF when there is none.
static func _aim_point(game: Node) -> Vector3:
	var aim_controller = game.get("aim_controller")
	if aim_controller == null or not aim_controller.has_method("get_target"): return Vector3.INF
	var t: Vector3 = aim_controller.get_target()
	return t if t.is_finite() else Vector3.INF

func _update_pov(camera: Camera3D, player: Node3D, ball: Node3D, _delta: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 76.0
	camera.near = 0.025
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var head: Node3D = player.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh")
	var desired_eye: Vector3 = head.get_global_transform_interpolated() * (Vector3.UP * 0.022 + player._get_forward_axis() * 0.0735) if head else _d(player) + Vector3.UP * 0.38
	# Use the current rendered eye position, without adding artificial bob or
	# borrowing the head gaze's anatomically limited/smoothed orientation.
	camera.global_position = desired_eye
	camera.frustum_offset = Vector2.ZERO
	_hide_avatar(player)
	if is_instance_valid(ball):
		var direction: Vector3 = _d(ball) - camera.global_position
		if direction.length_squared() < 0.04:
			# A coincident target has no look direction. Keep a tiny safe viewing
			# distance along the last valid ray instead of generating a NaN basis.
			camera.global_position = _d(ball) - _last_direction * 0.2
		_look_at(camera, _d(ball))

## Runs in the camera pass and again after the players are drawn (`place_only`), so the view
## always matches the head as it is drawn this frame.
func update_first_person(camera: Camera3D, player: Node3D, ball: Node3D, delta: float, place_only: bool) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = FP_FOV
	camera.near = 0.03
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.frustum_offset = Vector2.ZERO
	_set_first_person_cards(player)
	var view_size: Vector2 = camera.get_viewport().get_visible_rect().size
	_fp_half_v = atan(tan(deg_to_rad(FP_FOV * 0.5)) * maxf(view_size.y, 1.0) / maxf(view_size.x, 1.0))
	if not is_instance_valid(_fp_indicator) and player.get_parent() != null:
		_fp_indicator = preload("res://scripts/ui/ball_offscreen_indicator.gd").new()
		_fp_indicator.name = "BallOffscreenIndicator"
		player.get_parent().add_child(_fp_indicator)
	if is_instance_valid(_fp_indicator):
		_fp_indicator.camera = camera
		_fp_indicator.ball = ball
		_fp_indicator.player = player
	var head: Node3D = player.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh")
	var body: Node3D = player.get_node_or_null("BodyPivot")
	if head == null or body == null:
		camera.global_position = _d(player) + Vector3.UP * 1.62
		_look_at(camera, camera.global_position + player._get_forward_axis())
		return
	_fp_camera = camera; _fp_player = player; _fp_ball = ball
	var real_dt: float = clampf(camera.get_process_delta_time() / maxf(Engine.time_scale, 0.01), 0.0, 0.1)
	var in_play: bool = is_instance_valid(ball) and (not "is_in_play" in ball or ball.is_in_play)
	var head_xf: Transform3D = head.get_global_transform_interpolated()
	var body_basis: Basis = body.get_global_transform_interpolated().basis
	# Was the pose rewritten between physics ticks? (Checked once a frame.)
	var rel_head: Transform3D = player.global_transform.affine_inverse() * head.global_transform
	if Engine.get_process_frames() != _fp_live_frame:
		_fp_live_frame = Engine.get_process_frames()
		var tick: int = Engine.get_physics_frames()
		if tick == _fp_live_tick and not rel_head.is_equal_approx(_fp_live_rel): _fp_live_left = FP_LIVE_HOLD_S
		else: _fp_live_left = maxf(0.0, _fp_live_left - real_dt)
		_fp_live_tick = tick
		_fp_live_rel = rel_head
		_fp_live = move_toward(_fp_live, 1.0 if _fp_live_left > 0.0 else 0.0, FP_LIVE_RATE * real_dt)
	if _fp_live > 0.001:
		var root_xf: Transform3D = player.get_global_transform_interpolated()
		var live_head: Transform3D = root_xf * rel_head
		var live_body: Basis = (root_xf * (player.global_transform.affine_inverse() * body.global_transform)).basis
		head_xf = head_xf.orthonormalized().interpolate_with(live_head.orthonormalized(), _fp_live)
		body_basis = body_basis.orthonormalized().slerp(live_body.orthonormalized(), _fp_live)
	# Between points: the drawn head (pixel_card_rig.gd), when the cards drew it this frame or the last.
	var drawn_ok: bool = is_instance_valid(_fp_rig) and int(_fp_rig.drawn_head_frame) >= Engine.get_process_frames() - 1
	if not place_only: _fp_walk = move_toward(_fp_walk, 0.0 if in_play or not drawn_ok else 1.0, FP_WALK_RATE * real_dt)
	if drawn_ok and _fp_walk > 0.001:
		var w: float = smoothstep(0.0, 1.0, _fp_walk)
		# Position only: the drawn head also turns left and right in reactions and idle looks
		# (up to 30 degrees), which made the view swing after a point. The facing stays the
		# steady 3D head's; the gaze below does the looking.
		head_xf.origin = head_xf.origin.lerp(Vector3(_fp_rig.drawn_head_xf.origin), w)
	# The head's own facing: the body's forward and up carried through the head's turn.
	var to_head: Basis = body_basis.orthonormalized().inverse()
	var forward: Vector3 = (head_xf.basis.orthonormalized() * (to_head * player._get_forward_axis())).normalized()
	var up: Vector3 = (head_xf.basis.orthonormalized() * (to_head * Vector3.UP)).normalized()
	# In a rally the lines above leave the body's own turn out on purpose: a wind-up swings the
	# chest round and the view should not swing with it. Between points the body really turns
	# to walk (as far as right round, to go back to the baseline), and the view has to turn
	# with it: there the head's true facing is used, eased in and out with the walk blend.
	if _fp_walk > 0.001:
		var w_true: float = smoothstep(0.0, 1.0, _fp_walk)
		forward = _turn_toward(forward, (head_xf.basis.orthonormalized() * player._get_forward_axis()).normalized(), w_true)
		up = _turn_toward(up, (head_xf.basis.orthonormalized() * Vector3.UP).normalized(), w_true)
	var eye: Vector3 = head_xf * (Vector3.UP * 0.03) + forward * 0.08
	if forward.length_squared() > 0.5:
		var root_y: float = player.get_global_transform_interpolated().origin.y
		var height: float = eye.y - root_y
		var pitch: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
		if is_nan(_fp_height) or absf(height - _fp_height) > 0.4: _fp_height = height
		if is_nan(_fp_pitch): _fp_pitch = pitch
		if not place_only:
			_fp_height = lerpf(_fp_height, height, 1.0 - exp(-FP_HEIGHT_RATE * real_dt))
			_fp_pitch = lerpf(_fp_pitch, pitch, 1.0 - exp(-FP_PITCH_RATE * real_dt))
		_fp_height = clampf(_fp_height, height - FP_HEIGHT_MAX_OFF, height + FP_HEIGHT_MAX_OFF)
		_fp_pitch = clampf(_fp_pitch, pitch - FP_PITCH_MAX_OFF, pitch + FP_PITCH_MAX_OFF)
		eye.y = root_y + _fp_height
		var right: Vector3 = forward.cross(up)
		if right.length_squared() > 0.01:
			var turn: float = deg_to_rad(_fp_pitch - pitch)
			forward = forward.rotated(right.normalized(), turn).normalized()
			up = up.rotated(right.normalized(), turn).normalized()
		var root_xf: Transform3D = player.get_global_transform_interpolated().orthonormalized()
		var local_forward: Vector3 = root_xf.basis.inverse() * forward
		var yaw: float = atan2(local_forward.x, -local_forward.z)
		if is_nan(_fp_yaw) or absf(angle_difference(_fp_yaw, yaw)) > deg_to_rad(60.0): _fp_yaw = yaw
		if not place_only: _fp_yaw = lerp_angle(_fp_yaw, yaw, 1.0 - exp(-FP_YAW_RATE * real_dt))
		var yaw_off: float = clampf(angle_difference(yaw, _fp_yaw), -deg_to_rad(FP_YAW_MAX_OFF), deg_to_rad(FP_YAW_MAX_OFF))
		_fp_yaw = yaw + yaw_off
		forward = forward.rotated(Vector3.UP, -yaw_off).normalized()
		up = up.rotated(Vector3.UP, -yaw_off).normalized()
		var local_eye: Vector3 = root_xf.affine_inverse() * eye
		var side := Vector2(local_eye.x, local_eye.z)
		if not _fp_side.is_finite() or _fp_side.distance_to(side) > 0.4: _fp_side = side
		if not place_only: _fp_side = _fp_side.lerp(side, 1.0 - exp(-FP_SIDE_RATE * real_dt))
		_fp_side = side + (_fp_side - side).limit_length(FP_SIDE_MAX_OFF)
		eye = root_xf * Vector3(_fp_side.x, local_eye.y, _fp_side.y)
	if forward.length_squared() < 0.5: return
	var frame: Basis = Basis.looking_at(forward, up if absf(up.dot(forward)) < 0.99 else Vector3.UP)
	# Neck, then eyes: the neck turns toward the gaze point within its limits (none unless the
	# ball is your partner's or it is between points), the eyes cover up to FP_EYE_RANGE_DEG
	# more. Stepped once a frame (not in the late pass), kept in the head's frame.
	if not place_only:
		_fp_dt = real_dt
		var gaze: Dictionary = _fp_gaze(player, ball, eye, forward, in_play)
		fp_gaze_kind = str(gaze.kind)
		var local := Vector3.FORWARD
		var to_point: Vector3 = Vector3(gaze.point) - eye
		if to_point.length() > 0.2: local = (frame.inverse() * to_point).normalized()
		var limits: Vector3 = gaze.neck
		# The body's heading (the 3D body's, or where you walk between points), then the neck within
		# FP_NECK_MAX_YAW of it.
		var body_want := Vector3.FORWARD
		if _fp_body_world.length_squared() > 0.5:
			var heading: Vector3 = frame.inverse() * _fp_body_world
			heading.y = 0.0
			if heading.length_squared() > 0.01: body_want = heading.normalized()
		var body_off: float = rad_to_deg(_fp_body_local.angle_to(body_want))
		if body_off > 0.01 and real_dt > 0.0:
			_fp_body_local = _turn_toward(_fp_body_local, body_want, minf(1.0, minf(body_off * (1.0 - exp(-4.0 * real_dt)), FP_BODY_TURN_SPEED * real_dt) / body_off))
		var body_frame: Basis = Basis.looking_at(_fp_body_local, Vector3.UP)
		var neck_want: Vector3 = body_frame * _clamp_dir(body_frame.inverse() * local, minf(limits.x, FP_NECK_MAX_YAW), limits.y, limits.z)
		# The limit to the body, measured level in the world (the head's frame is tilted when
		# it looks down, and a turn measured in a tilted frame is not the turn you see).
		var body_facing: Vector3 = body_basis * player._get_forward_axis()
		body_facing.y = 0.0
		var has_body: bool = body_facing.length_squared() > 0.01
		if has_body:
			body_facing = body_facing.normalized()
			neck_want = frame.inverse() * _limit_to_body(frame * neck_want, body_facing, FP_HEAD_MAX_FROM_BODY)
		var neck_rate: float = FP_NECK_RATE_PARTNER if fp_gaze_kind in ["partner", "passing"] else FP_NECK_RATE
		var neck_off: float = rad_to_deg(_fp_neck_local.angle_to(neck_want))
		if neck_off > 0.01 and real_dt > 0.0:
			var step: float = neck_off * (1.0 - exp(-neck_rate * real_dt))                 # eases out near the target
			var dynamics: Array = FP_NECK_DYNAMICS["rally" if fp_gaze_kind in ["partner", "passing", "ball"] else ("walk" if fp_gaze_kind in ["walk", "ahead"] else "between")]
			var top: float = float(dynamics[0])
			# Past what a neck does on its own, the body is turning: slower.
			var neck_now: float = rad_to_deg(Vector3.FORWARD.angle_to(_fp_neck_local))
			var neck_goal: float = rad_to_deg(Vector3.FORWARD.angle_to(neck_want))
			if maxf(neck_now, neck_goal) > FP_NECK_FREE_DEG and neck_now > FP_NECK_FREE_DEG - 15.0: top = minf(top, FP_BODY_TURN_SPEED)
			# Never faster than can still stop in time (eases out), never a jump in speed (eases in).
			top = minf(top, sqrt(2.0 * float(dynamics[1]) * neck_off))
			step = minf(step, minf(top, _fp_neck_speed + float(dynamics[1]) * real_dt) * real_dt)
			_fp_neck_speed = step / real_dt
			_fp_neck_local = _turn_toward(_fp_neck_local, neck_want, step / neck_off)
		else: _fp_neck_speed = 0.0
		# A hard limit, whatever the easing was doing: never past FP_NECK_MAX_YAW from the body.
		_fp_neck_local = body_frame * _clamp_dir(body_frame.inverse() * _fp_neck_local, FP_NECK_MAX_YAW, 60.0, 45.0)
		if has_body: _fp_neck_local = (frame.inverse() * _limit_to_body(frame * _fp_neck_local, body_facing, FP_HEAD_MAX_FROM_BODY)).normalized()
		# Where the head points (not the eyes), for the drawn body to turn with it.
		if is_instance_valid(_fp_rig):
			var facing: Vector3 = frame * _fp_neck_local
			facing.y = 0.0
			# Not normalised: its length is how level the look is (looking straight down at a ball
			# at your feet has no left-right direction worth turning the body for).
			_fp_rig.look_dir = facing
		var eye_local: Vector3 = (Basis.looking_at(_fp_neck_local, Vector3.UP).inverse() * local).normalized()
		var angle: float = Vector3.FORWARD.angle_to(eye_local)
		var limit: float = deg_to_rad(FP_EYE_RANGE_DEG)
		var want: Vector3 = eye_local if angle <= limit else _turn_toward(Vector3.FORWARD, eye_local, limit / angle)
		# Real time, so the eyes do not lag and jump in slow motion or a hit-stop.
		_fp_eye_local = _turn_toward(_fp_eye_local, want, 1.0 - exp(-FP_EYE_RATE * real_dt))
	var look: Vector3 = (frame * (Basis.looking_at(_fp_neck_local, Vector3.UP) * _fp_eye_local)).normalized()
	camera.global_position = eye
	camera.look_at(eye + look, up if absf(up.dot(look)) < 0.99 else Vector3.UP)
	_last_direction = look

## What the eyes are on: {"point", "neck": limits in degrees (sideways, down, up), "kind"}.
func _fp_gaze(player: Node3D, ball: Node3D, eye: Vector3, forward: Vector3, in_play: bool) -> Dictionary:
	var ahead: Vector3 = eye + forward * 5.0
	_fp_body_world = Vector3.ZERO
	if not is_instance_valid(ball): return {"point": ahead, "neck": Vector3.ZERO, "kind": "ahead"}
	var ball_at: Vector3 = _d(ball)
	var game: Node = player.get_parent()
	if in_play:
		# Your partner's ball: on your side of the net and clearly nearer them than you.
		var me: Vector3 = _d(player)
		var velocity_now: Vector3 = ball.linear_velocity if "linear_velocity" in ball else Vector3.ZERO
		var soon: Vector3 = ball_at + velocity_now * FP_PARTNER_LEAD_S
		var theirs_now: bool = false
		var mine: float = Vector2(soon.x - me.x, soon.z - me.z).length()
		if game != null and game.has_method("get_players") and soon.z * me.z > 0.0 and mine > FP_PARTNER_MINE_M:
			for other in game.get_players():
				if other == player or other.team_id != player.team_id: continue
				var at: Vector3 = _d(other)
				var theirs: float = Vector2(soon.x - at.x, soon.z - at.z).length()
				var behind: bool = absf(at.z) > absf(me.z) + FP_PARTNER_BEHIND_M
				if theirs + (FP_PARTNER_NEARER_BEHIND_M if behind else FP_PARTNER_NEARER_M) < mine: theirs_now = true
		_fp_partner_t = _fp_partner_t + _fp_dt if theirs_now else 0.0
		if theirs_now and _fp_partner_t >= FP_PARTNER_DWELL_S: _fp_partner_hold = FP_PARTNER_HOLD_S
		else: _fp_partner_hold = maxf(0.0, _fp_partner_hold - _fp_dt)
		# Held only while the ball is still on your side (once it is hit back, eyes front).
		if _fp_partner_hold > 0.0 and (theirs_now or ball_at.z * me.z > 0.0): return {"point": ball_at, "neck": FP_NECK_PARTNER, "kind": "partner"}
		# Flying past you, or going out: watched all the way.
		var past: bool = ball_at.z * me.z > 0.0 and absf(ball_at.z) > absf(me.z) + FP_PASS_BEHIND_M
		var out: bool = absf(ball_at.x) > PickleballConstants.COURT_WIDTH * 0.5 + FP_PASS_OUT_M or absf(ball_at.z) > PickleballConstants.BASELINE_Z + FP_PASS_OUT_M
		_fp_pass_t = _fp_pass_t + _fp_dt if past or out else 0.0
		_fp_dead_t = 0.0
		if _fp_pass_t >= FP_PASS_DWELL_S: return {"point": ball_at, "neck": FP_NECK_PASSING, "kind": "passing"}
		return {"point": ball_at, "neck": Vector3.ZERO, "kind": "ball"}
	# Between points.
	_fp_pass_t = 0.0
	_fp_dead_t += _fp_dt
	_fp_partner_t = 0.0
	_fp_partner_hold = 0.0
	var between = game.get("between_point_controller") if game != null else null
	var velocity: Vector3 = player.current_velocity if "current_velocity" in player else Vector3.ZERO
	velocity.y = 0.0
	# Where you walk: only after walking a moment, and behind you only for a purposeful walk.
	var speed: float = velocity.length()
	_fp_walk_t = _fp_walk_t + _fp_dt if speed > FP_WALK_LOOK_SPEED else 0.0
	var walk_ahead: Vector3 = ahead
	var walking: bool = false
	if _fp_walk_t >= FP_WALK_DWELL_S:
		var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
		var backward: bool = velocity.normalized().dot(flat_forward) < -0.2
		# Not behind you: when you really turn round to walk, the body turns and the view goes
		# with it (so that is "ahead"); stepping backward while facing the net keeps the eyes front.
		if not backward:
			walk_ahead = eye + velocity.normalized() * 5.0
			walking = true
	# A paddle tap with your partner: them as you walk together, then the two paddles.
	if between != null and between.is_active() and between.has_method("_tap_of"):
		var tap: Dictionary = between._tap_of(between._players.find(player))
		if not tap.is_empty():
			for index in tap.pair:
				var mate = between._players[int(index)]
				if mate == player: continue
				if str(tap.state) == "WALK": return {"point": _d(mate) + Vector3.UP * FP_CHEST_UP, "neck": FP_NECK_BETWEEN, "kind": "tap_walk"}
				# The drawn tap (card_partner_tap.gd) brings the paddle tips together over the
				# meeting point at about hand height.
				return {"point": Vector3(tap.meet) + Vector3.UP * 1.0, "neck": FP_NECK_BETWEEN, "kind": "tap"}
	# The point just ended: the eyes stay on the ball a moment (a ball going out is watched out).
	if _fp_dead_t < FP_AFTER_POINT_S: return {"point": ball_at, "neck": FP_NECK_PASSING, "kind": "passing"}
	# The ball picker outside the court has the ball: only the catcher looks, without swinging round.
	if between != null and between.is_active() and bool(between.get("used_offscreen_helper")):
		if int(between.catcher) == between._players.find(player) and str(between.phase) in ["PASS", "CATCH"]:
			return {"point": ball_at, "neck": FP_NECK_HELPER, "kind": "helper_catch"}
		return {"point": walk_ahead, "neck": FP_NECK_HELPER, "kind": "walk" if walking else "ahead"}
	# Your own serve, from standing ready until the ball is struck.
	if game != null and game.has_method("get_server_actor") and game.get_server_actor() == player and int(game.get("game_state")) in [0, 1] \
			and (between == null or not between.is_active() or str(between.phase) == "SET_SERVE"):
		var aim: Vector3 = Vector3.INF
		var aim_controller = game.get("aim_controller")
		if aim_controller != null and aim_controller.has_method("get_target"): aim = aim_controller.get_target()
		if not aim.is_finite(): aim = Vector3(eye.x + forward.x * 9.0, PickleballConstants.FLOOR_Y, eye.z + forward.z * 9.0)
		return {"point": _serve_look_point(eye, aim, ball_at), "neck": FP_NECK_SERVE, "kind": "my_serve"}
	# Your partner serving: watch them (the ball once it is in their hand) until the serve is hit.
	if (between == null or not between.is_active() or str(between.phase) == "SET_SERVE") and not walking and game != null and game.has_method("get_server_actor"):
		var server = game.get_server_actor()
		if server != null and server != player and server.team_id == player.team_id:
			var at: Vector3 = _d(server) + Vector3.UP * FP_CHEST_UP
			return {"point": ball_at if ball_at.distance_to(at) < 1.5 else at, "neck": FP_NECK_BETWEEN, "kind": "partner_serve"}
	if between == null or not between.is_active():
		# Waiting for the serve (as in rallies: the eyes on the ball), or walking to position.
		if walking: return {"point": walk_ahead, "neck": FP_NECK_BETWEEN, "kind": "walk"}
		return {"point": ball_at, "neck": Vector3.ZERO, "kind": "ball"}
	var phase: String = str(between.phase)
	var players: Array = between._players
	var me_index: int = players.find(player)
	var fetching: bool = me_index >= 0 and int(between.retriever) == me_index
	if phase in ["APPROACH", "BEND", "LIFT", "PASS", "CATCH"]: return {"point": ball_at, "neck": FP_NECK_BETWEEN, "kind": "fetch" if fetching else "watch"}
	if phase == "PASS_PREP":
		var to: int = int(between.catcher)
		if fetching and to >= 0 and to < players.size() and players[to] != player:
			return {"point": _d(players[to]) + Vector3.UP * FP_CHEST_UP, "neck": FP_NECK_BETWEEN, "kind": "throw_target"}
		return {"point": ball_at, "neck": FP_NECK_BETWEEN, "kind": "watch"}
	if phase == "CARRY" and not fetching: return {"point": ball_at, "neck": FP_NECK_BETWEEN, "kind": "watch"}
	# Carrying it yourself, settling, changing ends: look where you walk (straight ahead until then).
	return {"point": walk_ahead, "neck": FP_NECK_BETWEEN, "kind": "walk" if walking else "ahead"}

## Where the view looks for your own serve: toward the aim, shifted toward the ball in your
## hand (which is held out to the side) just far enough that both are in the picture.
func _serve_look_point(eye: Vector3, aim: Vector3, ball_at: Vector3) -> Vector3:
	var to_aim: Vector3 = aim - eye
	var flat := Vector3(to_aim.x, 0.0, to_aim.z)
	if flat.length() < 0.5: return aim
	var pitch_aim: float = atan2(to_aim.y, flat.length())
	var centre: float = pitch_aim
	var turn: float = 0.0
	var to_ball: Vector3 = ball_at - eye
	var ball_flat := Vector3(to_ball.x, 0.0, to_ball.z)
	if to_ball.length() < 1.6 and ball_flat.length() > 0.05:      # the ball is in your hand (or just tossed)
		var pitch_ball: float = atan2(to_ball.y, ball_flat.length())
		var reach_v: float = _fp_half_v * FP_SERVE_EDGE
		centre = lerpf(pitch_aim, pitch_ball, FP_SERVE_BALL_SHARE)
		centre = minf(centre, pitch_ball + reach_v)
		centre = maxf(centre, pitch_aim - reach_v)
		# Left-right the same way: the aim stays inside the view first, then the ball.
		var reach_h: float = deg_to_rad(FP_FOV * 0.5) * FP_SERVE_EDGE
		var apart: float = flat.normalized().signed_angle_to(ball_flat.normalized(), Vector3.UP)
		turn = apart * FP_SERVE_BALL_SHARE
		if absf(apart) - absf(turn) > reach_h: turn = signf(apart) * (absf(apart) - reach_h)
		turn = clampf(turn, -reach_h, reach_h)
	var level: Vector3 = flat.normalized().rotated(Vector3.UP, turn)
	return eye + (level * cos(centre) + Vector3.UP * sin(centre)) * 6.0

## A world direction turned back, level, to within `max_deg` of the way the body faces. Its
## up-down part is kept. A look nearly straight up or down has no turn to limit.
static func _limit_to_body(direction: Vector3, body_facing: Vector3, max_deg: float) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.08: return direction
	var angle: float = body_facing.signed_angle_to(flat.normalized(), Vector3.UP)
	var limit: float = deg_to_rad(max_deg)
	if absf(angle) <= limit: return direction
	var turned: Vector3 = body_facing.rotated(Vector3.UP, signf(angle) * limit) * flat.length()
	return Vector3(turned.x, direction.y, turned.z).normalized()

## A direction in a -z-forward frame, held within sideways / down / up limits (degrees).
static func _clamp_dir(local: Vector3, yaw_deg: float, down_deg: float, up_deg: float) -> Vector3:
	var yaw: float = clampf(atan2(local.x, -local.z), -deg_to_rad(yaw_deg), deg_to_rad(yaw_deg))
	var pitch: float = clampf(atan2(local.y, Vector2(local.x, local.z).length()), -deg_to_rad(down_deg), deg_to_rad(up_deg))
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

## `from` turned toward `to` by share `t` of the angle between them (unit vectors). Safe where
## Vector3.slerp is not: a cross product a hair off unit length errors there.
static func _turn_toward(from: Vector3, to: Vector3, t: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle < 1e-5: return to.normalized()
	var axis: Vector3 = from.cross(to)
	if axis.length_squared() < 1e-10:
		if angle < 1.0: return to.normalized()
		axis = Vector3.UP   # straight behind: turn round level
	return from.rotated(axis.normalized(), angle * clampf(t, 0.0, 1.0)).normalized()

## Called by the card rig once it knows where it draws the head this frame. Not while paused:
## photo mode moves the camera then, and redraws the cards for it.
func place_from_drawn() -> void:
	if is_instance_valid(_fp_camera) and _fp_camera.get_tree() != null and _fp_camera.get_tree().paused: return
	if is_instance_valid(_fp_camera) and is_instance_valid(_fp_player):
		update_first_person(_fp_camera, _fp_player, _fp_ball, 0.0, true)

## The local player's cards show only hands, arms, legs and shoes while first person is on.
func _set_first_person_cards(player: Node3D) -> void:
	var rig: Node = null
	if player != null and player.get_parent() != null:
		rig = player.get_parent().get_node_or_null("PixelCards_%d" % player.get_instance_id())
	if rig == _fp_rig: return
	if is_instance_valid(_fp_rig):
		_fp_rig.first_person = false
		_fp_rig.look_dir = Vector3.ZERO
		_fp_rig.on_drawn_head = Callable()
	_fp_rig = rig
	if is_instance_valid(_fp_rig):
		_fp_rig.first_person = true
		_fp_rig.on_drawn_head = place_from_drawn
	_fp_walk = 0.0
	_fp_neck_local = Vector3.FORWARD
	_fp_neck_speed = 0.0
	_fp_height = NAN
	_fp_pitch = NAN
	_fp_yaw = NAN
	_fp_side = Vector2.INF
	_fp_body_local = Vector3.FORWARD
	_fp_body_world = Vector3.ZERO
	_fp_live = 0.0
	_fp_live_left = 0.0

func _look_at(camera: Camera3D, target: Vector3) -> void:
	var direction: Vector3 = target - camera.global_position
	if direction.length_squared() < 1e-8: return
	_last_direction = direction.normalized()
	var up: Vector3 = Vector3.FORWARD if absf(_last_direction.dot(Vector3.UP)) > 0.995 else Vector3.UP
	camera.look_at(target, up)

func _keep_ball_visible(camera: Camera3D, ball: Node3D) -> void:
	if not is_instance_valid(ball): return
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var safe: Rect2 = Layout.safe_rect(camera.get_viewport())
	var band: Rect2 = Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-24.0)
	band = band.grow(-12.0 * Layout.scale_for(size))
	var point: Vector2 = camera.unproject_position(_d(ball))
	var covered: = false
	if is_instance_valid(_controls) and _controls.has_method("camera_occlusion_regions"):
		for region in _controls.camera_occlusion_regions():
			if region.has_point(point): covered = true; break
	var outside: bool = camera.is_position_behind(_d(ball)) or not band.has_point(point) or covered
	# Ease toward aiming at the ball when it leaves the usable band, and back when
	# it returns (was an instant snap both ways). Fast in, so the ball is never
	# lost for more than a few frames.
	var now: int = Time.get_ticks_usec()
	var dt: float = clampf((now - _ball_aim_usec) / 1000000.0, 0.0, 0.1) if _ball_aim_usec > 0 else 0.0
	_ball_aim_usec = now
	_ball_aim = move_toward(_ball_aim, 1.0 if outside else 0.0, dt * (12.0 if outside else 3.0))
	if _ball_aim <= 0.001: return
	var framed: Transform3D = camera.global_transform
	var framed_v: float = camera.v_offset
	var framed_h: float = camera.h_offset
	if camera.global_position.distance_squared_to(_d(ball)) < 0.04:
		camera.global_position = _d(ball) - _last_direction * 0.2
	_look_at(camera, _d(ball))
	var weight: float = smoothstep(0.0, 1.0, _ball_aim)
	camera.global_transform = framed.interpolate_with(camera.global_transform, weight)
	camera.v_offset = lerpf(framed_v, 0.0, weight)
	camera.h_offset = lerpf(framed_h, 0.0, weight)

static func convert_fov(value: float, from_aspect: int, to_aspect: int, size: Vector2) -> float:
	if from_aspect == to_aspect: return value
	var aspect: float = maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var tangent: float = tan(deg_to_rad(value) * 0.5)
	return rad_to_deg(2.0 * atan(tangent / aspect if from_aspect == Camera3D.KEEP_WIDTH else tangent * aspect))
