class_name PlayerPaddlePosture extends Node

## PostureLibrary singleton for Phase 2+ wiring.
var _posture_lib: PostureLibrary

## Phase 3: Full-body skeleton applier (wired when skeleton exists)
var _skeleton_applier: PostureSkeletonApplier = null

## Phase 2: Offset/rotation resolver
var _offset_resolver: PostureOffsetResolver

## Phase 3: Commit-selection logic (extracted to RefCounted for headless testability)
var _commit_selector: PostureCommitSelector

## Emitted every physics frame while a posture is committed (and once on clear).
## stage: -1 = no commit / cleared, 0 = PINK (far), 1 = PURPLE (close), 2 = BLUE (contact imminent)
## posture: committed PaddlePosture enum value (-1 when cleared)
## commit_dist: player-to-ball XZ distance in meters
## ball2ghost: current-frame 3D distance from ball to committed ghost
## ttc: estimated seconds until the ball reaches the committed ghost (0.0 when cleared)
signal incoming_stage_changed(stage: int, posture: int, commit_dist: float, ball2ghost: float, ttc: float)

## Emitted once per ball when the posture is graded. Grade is "PERFECT"/"GREAT"/"GOOD"/"OK"/"MISS".
signal grade_flashed(grade: String)

# ── Paddle posture position / height constants (wired via _PC below) ─────────
const PaddleScene = preload("res://scenes/paddle.tscn")
const _PC := preload("res://scripts/posture_constants.gd")

# ── Paddle posture position / height constants ────────────────────────────────
const PADDLE_SIDE_OFFSET := _PC.PADDLE_SIDE_OFFSET
const PADDLE_FORWARD_OFFSET := _PC.PADDLE_FORWARD_OFFSET
const PADDLE_CENTER_OFFSET := _PC.PADDLE_CENTER_OFFSET
const PADDLE_BACKHAND_OFFSET := _PC.PADDLE_BACKHAND_OFFSET
const PADDLE_MEDIUM_OVERHEAD_HEIGHT := _PC.PADDLE_MEDIUM_OVERHEAD_HEIGHT
const PADDLE_MEDIUM_OVERHEAD_FORWARD := _PC.PADDLE_MEDIUM_OVERHEAD_FORWARD
const PADDLE_HIGH_OVERHEAD_HEIGHT := _PC.PADDLE_HIGH_OVERHEAD_HEIGHT
const PADDLE_HIGH_OVERHEAD_FORWARD := _PC.PADDLE_HIGH_OVERHEAD_FORWARD
const PADDLE_OVERHEAD_SIDE_OFFSET := _PC.PADDLE_OVERHEAD_SIDE_OFFSET
const PADDLE_LOW_HEIGHT := _PC.PADDLE_LOW_HEIGHT
const PADDLE_LOW_FORWARD_OFFSET := _PC.PADDLE_LOW_FORWARD_OFFSET
const PADDLE_BACKSWING_DEGREES := _PC.PADDLE_BACKSWING_DEGREES
const PADDLE_FOLLOW_THROUGH_DEGREES := _PC.PADDLE_FOLLOW_THROUGH_DEGREES
const PADDLE_CHARGE_PULLBACK := _PC.PADDLE_CHARGE_PULLBACK
const PADDLE_CHARGE_LIFT := _PC.PADDLE_CHARGE_LIFT
const PADDLE_CHARGE_BEHIND_OFFSET := _PC.PADDLE_CHARGE_BEHIND_OFFSET
const PADDLE_CHARGE_FOREHAND_BEHIND := _PC.PADDLE_CHARGE_FOREHAND_BEHIND
const PADDLE_CHARGE_FOREHAND_HEIGHT := _PC.PADDLE_CHARGE_FOREHAND_HEIGHT
const PADDLE_CHARGE_BACKHAND_BEHIND := _PC.PADDLE_CHARGE_BACKHAND_BEHIND
const PADDLE_CHARGE_BACKHAND_HEIGHT := _PC.PADDLE_CHARGE_BACKHAND_HEIGHT
const PADDLE_POSTURE_SWITCH_DEADZONE := _PC.PADDLE_POSTURE_SWITCH_DEADZONE
const PADDLE_WIDE_LATERAL_THRESHOLD := _PC.PADDLE_WIDE_LATERAL_THRESHOLD

# ── Ghost stretch / intercept clamp limits ──────────────────────────────────
const GHOST_STRETCH_LATERAL_MAX := _PC.GHOST_STRETCH_LATERAL_MAX
const GHOST_STRETCH_HEIGHT_MIN := _PC.GHOST_STRETCH_HEIGHT_MIN
const GHOST_STRETCH_HEIGHT_MAX := _PC.GHOST_STRETCH_HEIGHT_MAX
const GHOST_FORWARD_PLANE := _PC.GHOST_FORWARD_PLANE
const GHOST_CONTACT_MAX_DIST := _PC.GHOST_CONTACT_MAX_DIST
const ZONE_EXIT_MARGIN := _PC.ZONE_EXIT_MARGIN  # margin before triggering zone-exit recommit (hysteresis)

# Posture coverage zones: [x_min, x_max, y_min, y_max] in grid local space
# x = forehand axis lateral, y = height above court floor
var POSTURE_ZONES: Dictionary = {}

func _init_posture_zones() -> void:
	var PP = _player.PaddlePosture
	POSTURE_ZONES = {
		# Normal height — y_min raised so sub-0.48 balls fall OUT of normal zones
		# and mid-low variants get a clean win on descending arcs.
		PP.FOREHAND:        {"x_min": 0.2, "x_max": 0.55, "y_min": 0.5, "y_max": 1.0},
		PP.BACKHAND:        {"x_min": -0.55, "x_max": -0.2, "y_min": 0.5, "y_max": 1.0},
		PP.WIDE_FOREHAND:   {"x_min": 0.5, "x_max": 1.1, "y_min": 0.48, "y_max": 1.0},
		PP.WIDE_BACKHAND:   {"x_min": -1.1, "x_max": -0.5, "y_min": 0.48, "y_max": 1.0},
		PP.FORWARD:         {"x_min": -0.15, "x_max": 0.15, "y_min": 0.5, "y_max": 1.0},
		PP.VOLLEY_READY:    {"x_min": -0.2, "x_max": 0.2, "y_min": 0.55, "y_max": 0.9},
		# Overhead
		PP.MEDIUM_OVERHEAD: {"x_min": -0.35, "x_max": 0.35, "y_min": 0.8, "y_max": 1.3},
		PP.HIGH_OVERHEAD:   {"x_min": -0.35, "x_max": 0.35, "y_min": 1.1, "y_max": 1.8},
		# Mid-low — y_max extended to 0.52 to close the gap left by raising normal y_min
		PP.MID_LOW_FOREHAND:       {"x_min": 0.2, "x_max": 0.55, "y_min": 0.15, "y_max": 0.52},
		PP.MID_LOW_BACKHAND:       {"x_min": -0.55, "x_max": -0.2, "y_min": 0.15, "y_max": 0.52},
		PP.MID_LOW_FORWARD:        {"x_min": -0.15, "x_max": 0.15, "y_min": 0.15, "y_max": 0.52},
		PP.MID_LOW_WIDE_FOREHAND:  {"x_min": 0.5, "x_max": 1.1, "y_min": 0.1, "y_max": 0.50},
		PP.MID_LOW_WIDE_BACKHAND:  {"x_min": -1.1, "x_max": -0.5, "y_min": 0.1, "y_max": 0.50},
		# Low
		PP.LOW_FOREHAND:      {"x_min": 0.2, "x_max": 0.55, "y_min": -0.2, "y_max": 0.2},
		PP.LOW_BACKHAND:      {"x_min": -0.55, "x_max": -0.2, "y_min": -0.2, "y_max": 0.2},
		PP.LOW_FORWARD:       {"x_min": -0.15, "x_max": 0.15, "y_min": -0.2, "y_max": 0.2},
		PP.LOW_WIDE_FOREHAND: {"x_min": 0.5, "x_max": 1.1, "y_min": -0.2, "y_max": 0.15},
		PP.LOW_WIDE_BACKHAND: {"x_min": -1.1, "x_max": -0.5, "y_min": -0.2, "y_max": 0.15},
	}

# ── Posture ghost constants ───────────────────────────────────────────────────
const POSTURE_GHOST_ALPHA := _PC.POSTURE_GHOST_ALPHA
const POSTURE_GHOST_ACTIVE_ALPHA := _PC.POSTURE_GHOST_ACTIVE_ALPHA
const POSTURE_GHOST_NEAR_ALPHA := _PC.POSTURE_GHOST_NEAR_ALPHA
const POSTURE_GHOST_NEAR_EMISSION := _PC.POSTURE_GHOST_NEAR_EMISSION
const POSTURE_GHOST_NEAR_RADIUS := _PC.POSTURE_GHOST_NEAR_RADIUS
const POSTURE_GHOST_SCALE := _PC.POSTURE_GHOST_SCALE

# ── Debug posture name lookup — indexed by PaddlePosture enum value ───────────
const DEBUG_POSTURE_NAMES: Array[String] = [
	"FH","FW","BH","MO","HO","LF","LC","LB","CF","CB","WF","WB","VR",
	"MLF","MLB","MLC","MWF","MWB","LWF","LWB",
]

# ── Posture state ─────────────────────────────────────────────────────────────
var paddle_posture: int = 0  # PaddlePosture enum value (enum defined in player.gd)
var _posture_lerp_pos: Vector3 = Vector3.ZERO
var _posture_lerp_rot: Vector3 = Vector3.ZERO
var _posture_lerp_initialized: bool = false
var _low_look_blend: float = 0.0
var posture_ghosts: Dictionary = {}
var posture_ghost_root: Node3D = null
var _ball_incoming: bool = false
var _incoming_timer: float = 0.0
var _incoming_expired: bool = false
var _ghost_base_color: Color = Color(1, 0.85, 0.2)
var _green_lit_postures: Dictionary = {}  # posture int -> true, persists while _ball_incoming
var _zone_exit_cooldown: float = 0.0  # prevents rapid zone-exit switching
var _green_fade_t: float = 0.0  # counts up during fade-out (0 = just expired, FADE_DURATION = fully yellow)
var _trajectory_points: Array[Vector3] = []  # set by debug_visual via player.gd
var _committed_incoming_posture: int = -1  # locked posture during ball approach
var _contact_point_local: Vector3 = Vector3.ZERO  # grid-driven interception point (player-relative)
var _last_commit_stage: int = -1  # 0=pink(far), 1=purple, 2=blue — for logging
var _commit_count: int = 0  # total commits this ball (FIRST + TRACEs)
var _pose_change_count: int = 0  # total paddle_posture changes this ball
var _last_counted_posture: int = -1  # for detecting actual posture changes
var _green_trigger_count: int = 0  # how many times green ghosts lit up this ball
var _closest_ball2ghost: float = INF  # minimum ball-to-committed-ghost distance seen
var _scored_this_ball: bool = false  # only score once per ball
var _last_move_log_pos: Vector3 = Vector3.ZERO  # for movement logging every 0.5m
var _commit_locked: bool = false  # once committed, lock until bounce/move or reset
var _last_commit_ref_y: float = 0.0  # refY at commit time — bounce detected if it shifts >0.3
var _last_commit_player_pos: Vector3 = Vector3.ZERO  # player pos at commit — movement detected if shifts >0.5
var _blue_hold_timer: float = 0.0
var _blue_latched: bool = false  # one-shot: true after BLUE first fires, cleared in reset_incoming_highlight
var _ghost_frozen_at: Vector3 = Vector3.ZERO  # committed-ghost lerp target locked at BLUE latch
const BLUE_HOLD_DURATION := _PC.BLUE_HOLD_DURATION  # hold blue for at least this long once triggered
const TTC_BLUE := _PC.TTC_BLUE             # seconds-to-contact threshold for BLUE latch
const TTC_PURPLE := _PC.TTC_PURPLE           # seconds-to-contact threshold for PURPLE
const BLUE_DIST_FALLBACK := _PC.BLUE_DIST_FALLBACK  # physical ball-to-ghost fallback for BLUE latch
const POSTURE_HOLD_MIN := _PC.POSTURE_HOLD_MIN  # minimum seconds before allowing posture switch
const INCOMING_GLOW_DURATION := _PC.INCOMING_GLOW_DURATION
const INCOMING_FADE_DURATION := _PC.INCOMING_FADE_DURATION  # gradual fade back to yellow after glow expires
const GHOST_MIN_DISTANCE := _PC.GHOST_MIN_DISTANCE  # anti-overlap: minimum center-to-center
const GHOST_LERP_SPEED := _PC.GHOST_LERP_SPEED
const GHOST_TIGHTEN_RATIO := _PC.GHOST_TIGHTEN_RATIO  # pull 20% toward committed posture

## When non-null, paddle offset/rotation lerp targets use this definition instead of the library
## (used by TransitionPlayer for in-between blended poses).
var transition_pose_blend: PostureDefinition = null

# --- Solo Mode state (Wave 5) ---
var solo_mode: bool = true
var selected_posture_id: int = -1
var _paddle_head_marker: MeshInstance3D = null
var _hit_posture: int = -1
var _hit_flash_t: float = 0.0
const POSTURE_GHOST_HIT_FLASH_DURATION := 0.6
var _first_green_posture: int = -1  # tracks first primary green ghost for debug logging
var _last_lit_postures: Array = []  # previous frame's lit postures for change detection

# Follow-through ghost keys (negative to avoid PaddlePosture enum collision)
const FT_FOREHAND := -1
const FT_BACKHAND := -2
const FT_CENTER := -3
const FT_OVERHEAD := -4
const FT_KEYS := [FT_FOREHAND, FT_BACKHAND, FT_CENTER, FT_OVERHEAD]
var ft_ghosts: Dictionary = {}  # FT_KEY -> Node3D (static, not updated per frame)

var _player: PlayerController

func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_posture_lib = PostureLibrary.instance()
	_skeleton_applier = PostureSkeletonApplier.new(_player)
	_offset_resolver = PostureOffsetResolver.new(_player)
	_commit_selector = PostureCommitSelector.new()
	_init_posture_zones()

# Emits incoming_stage_changed(-1,...) for the human player — called after every
# site that resets the committed incoming posture. Keeps the HIT reaction button
# in sync so it hides and slow-mo restores even if the ball goes out of play.
func _emit_stage_cleared() -> void:
	if _player and _player.player_num == 0:
		incoming_stage_changed.emit(-1, -1, 0.0, 0.0, 0.0)

# ── Public API ────────────────────────────────────────────────────────────────────

func update_paddle_tracking(force: bool = false) -> void:
	if not _player._ensure_paddle_ready():
		return
	if _player.hitting.charge_visual_active and not force:
		return
	# Safety: auto-clear stuck follow-through flag if the tween was killed/finished
	if _player.hitting.is_in_follow_through:
		if _player.hitting.paddle_swing_tween == null or not _player.hitting.paddle_swing_tween.is_valid():
			_player.hitting.is_in_follow_through = false
		elif not force:
			return
	if _player.hitting.paddle_swing_tween != null and _player.hitting.paddle_swing_tween.is_valid() and not force:
		return

	var ball: RigidBody3D = _player._get_ball_ref()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var look_target: Vector3 = _player.global_position + forward_axis * 2.0

	var ball_is_near: bool = false
	if ball != null:
		var to_ball: Vector3 = ball.global_position - _player.global_position
		var ball_dist: float = Vector2(to_ball.x, to_ball.z).length()
		ball_is_near = ball_dist <= 5.0
		# If committed, stay "near" until ball is very far to prevent flickering resets
		if _committed_incoming_posture >= 0 and ball_dist <= 10.0:
			ball_is_near = true

	if ball != null and ball_is_near:
		look_target = ball.global_position

		if _player.is_ai and _player.ai_state == _player.AIState.CHARGING:
			# Don't overwrite — preserve CHARGE_FOREHAND / CHARGE_BACKHAND posture during charge
			pass
		elif _player.is_ai:
			# AI always uses its brain's chosen posture — never auto-overhead-override
			paddle_posture = _player.ai_desired_posture
		else:
			if _player.player_num == 0 and Engine.get_physics_frames() % 30 == 0:
				var pname: String = _player.PaddlePosture.keys()[paddle_posture] if paddle_posture >= 0 and paddle_posture < _player.PaddlePosture.size() else "?"
				var green_names: String = ""
				for gp in _green_lit_postures:
					if gp >= 0 and gp < _player.DEBUG_POSTURE_NAMES.size():
						green_names += _player.DEBUG_POSTURE_NAMES[gp] + " "
				var grid_info: String = ""
				if _player.awareness_grid:
					var info: Dictionary = _player.awareness_grid.get_approach_info()
					grid_info = "gh=%.2f gl=%.2f gu=%.1f gc=%d" % [info.height, info.lateral, info.urgency, info.confidence]
				var dbg_ball_d: float = ball.global_position.distance_to(_player.global_position) if ball else -1.0
				var tag: String = "[PURPLE✓] " if _committed_incoming_posture >= 0 else "[PURPLE✗] "
				print(tag, "commit=%d stage=%d ball_d=%.1f traj=%d pose=%s greens=[%s] %s" % [
					_committed_incoming_posture, _last_commit_stage,
					dbg_ball_d, _trajectory_points.size(),
					pname, green_names.strip_edges(), grid_info])
			if _ball_incoming and not _trajectory_points.is_empty():
				# ── GREEN POOL SYSTEM: trajectory is the single source of truth ──
				# The green set (ghosts near trajectory) determines valid postures.
				# Commit = best green ghost. Recommit when committed ghost leaves green set.
				var contact_pt: Vector3 = _commit_selector.compute_expected_contact_point(_player.global_position, _player.COURT_FLOOR_Y, ball != null and ball.is_in_play and ball.linear_velocity.y < -1.0)
				var ball_d: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()

				var reason: String = ""
				# Lock awareness grid when TTC is small (GAP-38: was distance-based, now TTC-based)
				if _player.awareness_grid:
					var player_ttc: float = _player.awareness_grid.get_ttc_at_world_point(_player.global_position, 0.45)
					_player.awareness_grid.set_locked(player_ttc < 0.35)
				var best_ghost: int = _find_closest_ghost_to_point(contact_pt)

				if _committed_incoming_posture < 0 and best_ghost >= 0:
					# First commit
					_committed_incoming_posture = best_ghost
					_last_commit_player_pos = _player.global_position
					reason = "FIRST"

				if reason != "":
					_commit_count += 1
					var new_name: String = _player.DEBUG_POSTURE_NAMES[_committed_incoming_posture] if _committed_incoming_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
					var gw: Vector3 = _player.global_position + _offset_resolver.get_posture_offset_for(_committed_incoming_posture)
					var ghost_to_contact: float = gw.distance_to(contact_pt)
					print("[COMMIT P%d] %s d=%.1f -> %s g2c=%.2f contact=(%.1f,%.1f,%.1f) pos=(%.1f,%.1f) spd=%.1f" % [_player.player_num, reason, ball_d, new_name, ghost_to_contact, contact_pt.x, contact_pt.y, contact_pt.z, _player.global_position.x, _player.global_position.z, _player.current_velocity.length()])

				paddle_posture = _committed_incoming_posture if _committed_incoming_posture >= 0 else _player.PaddlePosture.READY

			elif _committed_incoming_posture >= 0:
				# Keep committed posture while ball is near
				paddle_posture = _committed_incoming_posture
	else:
		if not ball_is_near:
			paddle_posture = _player.PaddlePosture.READY
			_committed_incoming_posture = -1
			_last_commit_stage = -1
			_contact_point_local = Vector3.ZERO
			_blue_hold_timer = 0.0
			_blue_latched = false
			_ghost_frozen_at = Vector3.ZERO
			_commit_locked = false
			_last_commit_ref_y = 0.0
			_last_commit_player_pos = Vector3.ZERO
			_emit_stage_cleared()
			if _player.awareness_grid:
				_player.awareness_grid.reset()
		elif _committed_incoming_posture >= 0:
			paddle_posture = _committed_incoming_posture
	# Don't reset _commit_count here — SCORE reads it in ghost rendering pass
	# It gets reset in reset_incoming_highlight() after the ball is actually hit

	# Track actual pose changes (any paddle_posture flip, not just commits)
	if paddle_posture != _last_counted_posture:
		if _last_counted_posture >= 0:
			_pose_change_count += 1
		_last_counted_posture = paddle_posture

	# Log body position every 0.5m of movement while ball is incoming
	if _ball_incoming and ball != null:
		var move_d: float = Vector2(_player.global_position.x - _last_move_log_pos.x, _player.global_position.z - _last_move_log_pos.z).length()
		if move_d > 0.5 or _last_move_log_pos == Vector3.ZERO:
			_last_move_log_pos = _player.global_position
			var ball_d: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
			var paddle_d: float = INF
			if _player.has_method("get_paddle_position"):
				paddle_d = _player.get_paddle_position().distance_to(ball.global_position)
			var pname: String = _player.DEBUG_POSTURE_NAMES[paddle_posture] if paddle_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
			print("[MOVE P%d] pos=(%.1f,%.1f) ball_d=%.1f paddle_d=%.1f spd=%.1f pose=%s" % [_player.player_num, _player.global_position.x, _player.global_position.z, ball_d, paddle_d, _player.current_velocity.length(), pname])

	# --- Lerped posture position ---
	# Smoothly interpolate paddle toward target position rather than snapping.
	# Skip lerp during charge (handled by set_serve_charge_visual) or active swing tween.
	var target_pos: Vector3 = _get_posture_offset()
	# Floor clamp — paddle head center must never go below clearance.
	# Now that target_pos represents the HEAD center, clearance is simplified (0.06m).
	var clearance: float = 0.06
	var pivot_y: float = _player.body_pivot.position.y if _player.body_pivot else 0.0
	var floor_local_y: float = _player.COURT_FLOOR_Y - _player.global_position.y - pivot_y + clearance
	target_pos.y = maxf(target_pos.y, floor_local_y)
	var rot_offset: Vector3 = _offset_resolver.get_posture_rotation_offset_for(paddle_posture)
	if force or not _posture_lerp_initialized:
		_posture_lerp_pos = target_pos
		_posture_lerp_rot = rot_offset
		_posture_lerp_initialized = true
	else:
		var is_wide: bool = paddle_posture in [_player.PaddlePosture.WIDE_FOREHAND, _player.PaddlePosture.WIDE_BACKHAND]
		var is_low: bool = paddle_posture in [
			_player.PaddlePosture.LOW_FOREHAND, _player.PaddlePosture.LOW_BACKHAND,
			_player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.LOW_WIDE_FOREHAND,
			_player.PaddlePosture.LOW_WIDE_BACKHAND]
		# Wide: fast snap. Low: slightly slower for deliberate reach. Normal: standard.
		var lerp_spd: float = 22.0 if is_wide else (12.0 if is_low else 16.0)
		var dt: float = get_physics_process_delta_time()
		_posture_lerp_pos = _posture_lerp_pos.lerp(target_pos, minf(dt * lerp_spd, 1.0))
		_posture_lerp_rot = _posture_lerp_rot.lerp(rot_offset, minf(dt * lerp_spd, 1.0))

	# Re-clamp after lerp — intermediate values can dip below floor
	_posture_lerp_pos.y = maxf(_posture_lerp_pos.y, floor_local_y)
	# Only set local position when NOT committed — force_paddle_head_to_ghost handles committed state
	if _committed_incoming_posture < 0 or _last_commit_stage < 0:
		var b := _get_basis_from_rotation(_posture_lerp_rot)
		_player.paddle_node.position = _posture_lerp_pos - b.y * 0.4

	# Update paddle head debug marker — bright orange sphere at actual paddle head center
	if _paddle_head_marker and posture_ghost_root and posture_ghost_root.visible:
		_paddle_head_marker.visible = true
		_paddle_head_marker.global_position = _player.paddle_node.global_position + _player.paddle_node.global_transform.basis.y * 0.4
	elif _paddle_head_marker:
		_paddle_head_marker.visible = false

	# Low postures: face the net (forward axis) instead of the ball
	var is_low_posture: bool = paddle_posture in [
		_player.PaddlePosture.LOW_FOREHAND, _player.PaddlePosture.LOW_BACKHAND,
		_player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.LOW_WIDE_FOREHAND,
		_player.PaddlePosture.LOW_WIDE_BACKHAND]
	var net_target: Vector3 = _player.paddle_node.global_position + _player._get_forward_axis() * 2.0
	var low_blend: float = 1.0 if is_low_posture else 0.0
	_low_look_blend = lerpf(_low_look_blend, low_blend, minf(get_physics_process_delta_time() * 12.0, 1.0))
	# When committed, paddle faces straight at the net — no ball tracking
	if _committed_incoming_posture >= 0 and _last_commit_stage >= 0:
		look_target = net_target
	var actual_look: Vector3 = look_target.lerp(net_target, _low_look_blend)
	_player.paddle_node.look_at(actual_look, Vector3.UP, true)

	if not _posture_lerp_rot.is_zero_approx():
		_player.paddle_node.rotate_object_local(Vector3.RIGHT, deg_to_rad(_posture_lerp_rot.x))
		_player.paddle_node.rotate_object_local(Vector3.UP, deg_to_rad(_posture_lerp_rot.y))
		_player.paddle_node.rotate_object_local(Vector3.FORWARD, deg_to_rad(_posture_lerp_rot.z))

	_player._cache_paddle_rest_transform()

func force_posture_update(def: PostureDefinition) -> void:
	if not _player or not _player._ensure_paddle_ready():
		return
	
	paddle_posture = def.posture_id
	
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = forward_axis.z
	
	_posture_lerp_pos = def.resolve_paddle_offset(forehand_axis, forward_axis)
	_posture_lerp_rot = def.resolve_paddle_rotation_deg(swing_sign, fwd_sign)
	_posture_lerp_initialized = true
	
	if _player.paddle_node:
		var b := _get_basis_from_rotation(_posture_lerp_rot)
		_player.paddle_node.position = _posture_lerp_pos - b.y * 0.4
		_player.paddle_node.rotation_degrees = Vector3.ZERO
		_player.paddle_node.rotate_object_local(Vector3.RIGHT, deg_to_rad(_posture_lerp_rot.x))
		_player.paddle_node.rotate_object_local(Vector3.UP, deg_to_rad(_posture_lerp_rot.y))
		_player.paddle_node.rotate_object_local(Vector3.FORWARD, deg_to_rad(_posture_lerp_rot.z))
		_player._cache_paddle_rest_transform()

	_apply_full_body_posture(def)

func place_paddle_at_side() -> void:
	if _player.paddle_node == null:
		return

	paddle_posture = _player.PaddlePosture.FOREHAND
	_player.paddle_node.position = _get_posture_offset()
	_player.paddle_node.rotation_degrees = Vector3(0.0, 0.0, 0.0)

func set_trajectory_points(points: Array[Vector3]) -> void:
	_trajectory_points = points
	_commit_selector.set_trajectory_points(points)

func _get_contact_point_local() -> Vector3:
	## Find where the trajectory arc crosses the ghost forward plane (z=0.5 in local).
	## Uses actual trajectory points for geometric precision.
	if _trajectory_points.is_empty():
		return _contact_point_local
	var fwd: Vector3 = _player._get_forward_axis()
	var fh: Vector3 = _player._get_forehand_axis()
	var player_pos: Vector3 = _player.global_position
	# The ghost plane is at 0.5m forward from player in local space
	# In world space: player_pos + fwd * 0.5
	# We want the trajectory point closest to this plane
	var best_dist: float = INF
	var best_world: Vector3 = Vector3.ZERO
	for pt in _trajectory_points:
		var offset: Vector3 = pt - player_pos
		var forward_dist: float = offset.dot(fwd)
		if forward_dist < 0.0:
			continue
		var plane_dist: float = abs(forward_dist - GHOST_FORWARD_PLANE)
		if plane_dist < best_dist:
			best_dist = plane_dist
			best_world = pt
	if best_world != Vector3.ZERO and best_dist < GHOST_CONTACT_MAX_DIST:
		var off: Vector3 = best_world - player_pos
		var lx: float = clampf(off.dot(fh), -GHOST_STRETCH_LATERAL_MAX, GHOST_STRETCH_LATERAL_MAX)
		# Allow contact to reach the actual floor — dynamic clamp tracks COURT_FLOOR_Y
		# instead of a hardcoded player-relative offset. Fixes low-ball clamping.
		var min_off_y: float = _player.COURT_FLOOR_Y - player_pos.y
		var ly: float = clampf(off.y, min_off_y, GHOST_STRETCH_HEIGHT_MAX)
		_contact_point_local = fh * lx + Vector3.UP * ly + fwd * GHOST_FORWARD_PLANE
	# If best_dist >= 3.0, player is far from trajectory — keep last valid contact
	return _contact_point_local

func _find_closest_ghost_to_point(ref: Vector3) -> int:
	## Zone-based scoring: distance from contact to zone center. No bias bonuses.
	## Delegates to PostureCommitSelector for green-zone scoring + fallback.
	var awareness_grid = _player.awareness_grid if _player.has_method("awareness_grid") else null
	return _commit_selector.find_best_green_posture(
		ref,
		posture_ghosts,
		POSTURE_ZONES,
		_player.PaddlePosture.CHARGE_FOREHAND,
		_player.PaddlePosture.CHARGE_BACKHAND,
		_player.global_position,
		_player._get_forehand_axis(),
		_player.COURT_FLOOR_Y,
		awareness_grid
	)

func force_paddle_head_to_ghost() -> void:
	## GAP-4: framerate-independent spring chase via _damp_v3.
	## GAP-45: halflife is now Fitts-law-derived (scales with reach distance)
	## and then compressed by commit stage. A ghost 5 cm away snaps tight; a
	## ghost 80 cm away moves deliberately. Matches human reach kinematics.
	if _committed_incoming_posture < 0 or _last_commit_stage < 0:
		return
	var ghost: Node3D = posture_ghosts.get(_committed_incoming_posture)
	if not ghost or not _player.paddle_node:
		return
	var ghost_world: Vector3 = ghost.global_position
	var target: Vector3 = ghost_world - _player.paddle_node.global_transform.basis.y * 0.4

	# Fitts' law: MT = a + b * log2(D/W + 1). Paddle head target width W ≈ 8 cm.
	# Typical human reach constants: a=0.05s, b=0.12 s/bit.
	var reach_D: float = _player.paddle_node.global_position.distance_to(target)
	var fitts_W: float = 0.08
	var fitts_ID: float = log(reach_D / fitts_W + 1.0) / log(2.0)  # bits
	var fitts_MT: float = 0.05 + 0.12 * fitts_ID  # seconds

	# Commit stage compresses the reach time (BLUE wants to snap NOW regardless
	# of what Fitts says). Halflife is ~35% of total movement time for a
	# critically-damped spring to reach the target.
	var stage_compression: float
	match _last_commit_stage:
		2: stage_compression = 0.30  # BLUE — urgent
		1: stage_compression = 0.55  # PURPLE — committed
		_: stage_compression = 0.80  # PINK — deliberate
	var halflife: float = maxf(fitts_MT * 0.35 * stage_compression, 0.02)

	var dt: float = get_process_delta_time()
	_player.paddle_node.global_position = _player._damp_v3(
		_player.paddle_node.global_position, target, halflife, dt
	)

func reset_incoming_highlight() -> void:
	# Safety net: if the ball was ever committed but BLUE never latched (e.g. ball left play
	# before reaching the ghost), still emit a grade using the closest approach. This preserves
	# invariant #1 (exactly one [SCORE] per ball) for every ball that produced a commit.
	if not _scored_this_ball and _closest_ball2ghost < INF and _committed_incoming_posture >= 0:
		var grade: String = _commit_selector.grade_ball_to_ghost(_closest_ball2ghost)
		var pname: String = _player.DEBUG_POSTURE_NAMES[_committed_incoming_posture] if _committed_incoming_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
		print("[SCORE P%d] %s %s closest=%.2f commits=%d poses=%d greens=%d (reset)" % [_player.player_num, grade, pname, _closest_ball2ghost, _commit_count, _pose_change_count, _green_trigger_count])
		if _player.player_num == 0:
			grade_flashed.emit(grade)
		_scored_this_ball = true
	_ball_incoming = false
	_incoming_timer = 0.0
	_incoming_expired = false
	_green_lit_postures.clear()
	_first_green_posture = -1
	_committed_incoming_posture = -1
	_last_commit_stage = -1
	_blue_hold_timer = 0.0
	_blue_latched = false
	_ghost_frozen_at = Vector3.ZERO
	_commit_locked = false
	_emit_stage_cleared()
	_last_commit_ref_y = 0.0
	_last_commit_player_pos = Vector3.ZERO
	_commit_count = 0
	_pose_change_count = 0
	_last_counted_posture = -1
	_green_trigger_count = 0
	_closest_ball2ghost = INF
	_scored_this_ball = false
	_last_move_log_pos = Vector3.ZERO

func notify_ball_hit() -> void:
	_hit_posture = paddle_posture
	_hit_flash_t = POSTURE_GHOST_HIT_FLASH_DURATION


func _create_paddle_ghost(material: StandardMaterial3D, label_text: String = "") -> Node3D:
	var ghost := PaddleScene.instantiate() as Node3D
	ghost.scale = POSTURE_GHOST_SCALE

	var collision := ghost.get_node_or_null("CollisionShape3D")
	if collision:
		collision.queue_free()
	var hitbox := ghost.get_node_or_null("PaddleHitbox")
	if hitbox:
		hitbox.queue_free()

	for mesh_name in ["Handle", "Head", "Head/HeadTopCurve", "Head/HeadBottomCurve"]:
		var mesh := ghost.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			mesh.material_override = material

	if label_text != "":
		var label := Label3D.new()
		label.text = label_text
		label.font_size = 48
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 0.16, 0.0)
		label.modulate = Color(1.0, 1.0, 1.0, 0.9)
		ghost.add_child(label)

	return ghost


func _get_ghost_material(ghost: Node3D) -> StandardMaterial3D:
	if ghost == null:
		return null
	var head := ghost.get_node_or_null("Head") as MeshInstance3D
	return head.material_override as StandardMaterial3D if head else null


func _apply_ghost_material(ghost: Node3D, material: StandardMaterial3D) -> void:
	if ghost == null or material == null:
		return
	for mesh_name in ["Handle", "Head", "Head/HeadTopCurve", "Head/HeadBottomCurve"]:
		var mesh := ghost.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			mesh.material_override = material

func create_posture_ghosts(paddle_color: Color) -> void:
	_ghost_base_color = paddle_color
	posture_ghost_root = Node3D.new()
	posture_ghost_root.name = "PostureGhosts"
	posture_ghost_root.visible = false  # hidden by default — Z key toggles
	_player.add_child(posture_ghost_root)
	posture_ghosts.clear()

	# Bright orange sphere marking the paddle head center (debug)
	_paddle_head_marker = MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.04
	head_mesh.height = 0.08
	head_mesh.radial_segments = 8
	head_mesh.rings = 4
	_paddle_head_marker.mesh = head_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.6, 0.0, 1.0)
	head_mat.emission_energy_multiplier = 3.0
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_paddle_head_marker.material_override = head_mat
	_paddle_head_marker.top_level = true
	posture_ghost_root.add_child(_paddle_head_marker)

	for posture in [
		_player.PaddlePosture.FOREHAND,
		_player.PaddlePosture.FORWARD,
		_player.PaddlePosture.BACKHAND,
		_player.PaddlePosture.MEDIUM_OVERHEAD,
		_player.PaddlePosture.HIGH_OVERHEAD,
		_player.PaddlePosture.LOW_FOREHAND,
		_player.PaddlePosture.LOW_FORWARD,
		_player.PaddlePosture.LOW_BACKHAND,
		_player.PaddlePosture.CHARGE_FOREHAND,
		_player.PaddlePosture.CHARGE_BACKHAND,
		_player.PaddlePosture.WIDE_FOREHAND,
		_player.PaddlePosture.WIDE_BACKHAND,
		_player.PaddlePosture.VOLLEY_READY,
		_player.PaddlePosture.MID_LOW_FOREHAND,
		_player.PaddlePosture.MID_LOW_BACKHAND,
		_player.PaddlePosture.MID_LOW_FORWARD,
		_player.PaddlePosture.MID_LOW_WIDE_FOREHAND,
		_player.PaddlePosture.MID_LOW_WIDE_BACKHAND,
		_player.PaddlePosture.LOW_WIDE_FOREHAND,
		_player.PaddlePosture.LOW_WIDE_BACKHAND,
	]:
		var ghost_material: StandardMaterial3D = StandardMaterial3D.new()

		# Use darker color for charge posture ghosts
		if posture == _player.PaddlePosture.CHARGE_FOREHAND or posture == _player.PaddlePosture.CHARGE_BACKHAND:
			ghost_material.albedo_color = Color(paddle_color.r * 0.5, paddle_color.g * 0.5, paddle_color.b * 0.5, POSTURE_GHOST_ALPHA * 1.5)
			ghost_material.emission = Color(paddle_color.r * 0.4 + 0.1, paddle_color.g * 0.4 + 0.1, paddle_color.b * 0.4 + 0.1, 1.0)
			ghost_material.emission_energy_multiplier = 0.08
		else:
			ghost_material.albedo_color = Color(paddle_color.r, paddle_color.g, paddle_color.b, POSTURE_GHOST_ALPHA)
			ghost_material.emission = Color(paddle_color.r * 0.7 + 0.2, paddle_color.g * 0.7 + 0.2, paddle_color.b * 0.7 + 0.2, 1.0)
			ghost_material.emission_energy_multiplier = 0.12

		ghost_material.emission_enabled = true
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ghost := _create_paddle_ghost(
			ghost_material,
			_player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
		)
		posture_ghost_root.add_child(ghost)
		posture_ghosts[posture] = ghost

	update_posture_ghosts()
	_create_follow_through_ghosts()

func _create_follow_through_ghosts() -> void:
	if posture_ghost_root == null or not _player.hitting:
		return
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var ft_family_postures: Dictionary = {
		FT_FOREHAND: _player.PaddlePosture.FOREHAND,
		FT_BACKHAND: _player.PaddlePosture.BACKHAND,
		FT_CENTER: _player.PaddlePosture.FORWARD,
		FT_OVERHEAD: _player.PaddlePosture.HIGH_OVERHEAD,
	}
	for ft_key in FT_KEYS:
		var base_posture: int = ft_family_postures[ft_key]
		# Compute fixed position: rest + follow-through at max charge
		var saved: int = paddle_posture
		paddle_posture = base_posture
		var ft_sign: float = _offset_resolver.get_posture_charge_sign()
		var ft: Dictionary = _player.hitting._get_follow_through_offsets(1.0, forward_axis, forehand_axis, ft_sign, base_posture)
		paddle_posture = saved
		var ft_pos: Vector3 = _player.paddle_rest_position + ft["pos"]

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.9, 0.95, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.0, 0.8, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.25
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ghost := _create_paddle_ghost(mat)
		# Set position ONCE — these don't move
		ghost.position = ft_pos
		ghost.rotation_degrees = ft["rot"]
		posture_ghost_root.add_child(ghost)
		ft_ghosts[ft_key] = ghost

func set_ghosts_visible(v: bool) -> void:
	if posture_ghost_root:
		posture_ghost_root.visible = v

func _apply_ghost_separation() -> void:
	var keys := posture_ghosts.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Node3D = posture_ghosts[keys[i]]
			var b: Node3D = posture_ghosts[keys[j]]
			if a == null or b == null:
				continue
			var diff: Vector3 = a.position - b.position
			var dist: float = diff.length()
			if dist < GHOST_MIN_DISTANCE and dist > 0.001:
				var push: Vector3 = diff.normalized() * (GHOST_MIN_DISTANCE - dist) * 0.5
				a.position += push
				b.position -= push

func update_posture_ghosts() -> void:
	if posture_ghost_root == null:
		return
	var ball: RigidBody3D = _player._get_ball_ref()

	# Tick down hit flash
	var delta: float = get_process_delta_time()
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(_hit_flash_t - delta, 0.0)

	# ── Pre-commit ring feed ──────────────────────────────────────────────
	# As soon as a ball is heading toward the human player, start collapsing
	# the reaction HIT button's outer ring — even before a posture ghost is
	# committed. This gives the "opponent hits → ring shrinks → contact"
	# timing window the user expects. Uses TTC to the player's position as
	# a proxy until a real ghost gets committed, then PHASE C takes over.
	if _player.player_num == 0 and ball != null and not _scored_this_ball:
		var toward: float = ball.linear_velocity.dot(-_player._get_forward_axis())
		if toward > 0.5 and _committed_incoming_posture < 0:
			var pre_ttc: float = _compute_ttc(ball, _player.global_position)
			var pre_stage: int = 0
			if pre_ttc < TTC_BLUE:
				pre_stage = 2
			elif pre_ttc < TTC_PURPLE:
				pre_stage = 1
			var pre_commit_dist: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
			incoming_stage_changed.emit(pre_stage, -1, pre_commit_dist, 999.0, pre_ttc)

	# Fallback trajectory feed — only if player.gd didn't already feed this frame
	if _trajectory_points.is_empty() and ball != null and ball is RigidBody3D and ball.linear_velocity.length() > 0.5:
			var traj: Array[Vector3] = _commit_selector.compute_simple_trajectory(ball.global_position, ball.linear_velocity, Ball.get_effective_gravity(), _player.COURT_FLOOR_Y)
		if not traj.is_empty():
			set_trajectory_points(traj)
			if _player.awareness_grid:
				_player.awareness_grid.set_trajectory_points(traj)

	# Update incoming state: ball moving toward this player's side
	if ball != null and ball is RigidBody3D:
		var toward_player: float = ball.linear_velocity.dot(-_player._get_forward_axis())
		var ball_d_ghost: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()

		if toward_player > 1.0:
			# Guard 1: expired → full reset so new ball can trigger fresh
			if _incoming_expired:
				_incoming_expired = false
				_ball_incoming = false
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()
				if _player.awareness_grid:
					_player.awareness_grid.reset()

			# Guard 2: stale commit — committed but ball is far and incoming=false
			# means the old commit is from a previous ball, force reset
			if _committed_incoming_posture >= 0 and not _ball_incoming and ball_d_ghost > 5.0:
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()

			if not _ball_incoming and not _incoming_expired:
				_incoming_timer = 0.0
				_ball_incoming = true
				var ppos: Vector3 = _player.global_position
				var pvel: Vector3 = _player.current_velocity
				var fwd: Vector3 = _player._get_forward_axis()
				print("[TRACK P%d] incoming=true toward=%.1f traj_pts=%d pos=(%.1f,%.1f,%.1f) spd=%.1f dir=(%.2f,%.2f)" % [
					_player.player_num, toward_player, _trajectory_points.size(),
					ppos.x, ppos.y, ppos.z,
					pvel.length(),
					fwd.x, fwd.z])
		else:
			_incoming_expired = false  # ball stopped approaching — allow re-trigger

			# Guard 3: ball going away + old commit hanging → clear it
			if _committed_incoming_posture >= 0 and not _ball_incoming:
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()
				if _player.awareness_grid:
					_player.awareness_grid.reset()

	# Fade out green glow after duration
	if _ball_incoming:
		_incoming_timer += delta
		if _incoming_timer >= INCOMING_GLOW_DURATION:
			_ball_incoming = false
			_incoming_expired = true
			_green_fade_t = 0.0

			# Guard 4: incoming expired → clear commit so it doesn't persist
			_committed_incoming_posture = -1
			_last_commit_stage = -1
			_contact_point_local = Vector3.ZERO
			_emit_stage_cleared()
			if _player.awareness_grid:
				_player.awareness_grid.reset()

	# Clear any remaining green ghosts after incoming expires
	if not _ball_incoming and not _green_lit_postures.is_empty():
		_green_fade_t += delta
		if _green_fade_t >= INCOMING_FADE_DURATION * 2.0:
			_green_lit_postures.clear()
	_first_green_posture = -1

	var _frame_lit_postures: Array = []
	for posture in posture_ghosts.keys():
		var ghost: Node3D = posture_ghosts[posture]
		if ghost == null:
			continue
		var base_pos: Vector3 = _offset_resolver.get_posture_offset_for(posture)
		var target_pos: Vector3 = base_pos
		# Ghost flies to interception point from volumetric grid
		if _ball_incoming and _committed_incoming_posture >= 0:
			var contact_local: Vector3 = _get_contact_point_local()
			if contact_local != Vector3.ZERO:
				if posture == _committed_incoming_posture:
					if _blue_latched and _ghost_frozen_at != Vector3.ZERO:
						# BLUE latched — ghost position is frozen for the grade window
						target_pos = _player.to_local(_ghost_frozen_at)
					else:
						# COMMITTED ghost: fly to contact clamped within posture zone
						var zone: Dictionary = POSTURE_ZONES.get(posture, {})
						if not zone.is_empty():
							var fh_z: Vector3 = _player._get_forehand_axis()
							var fwd_z: Vector3 = _player._get_forward_axis()
							var cl_x: float = clampf(contact_local.dot(fh_z), zone.x_min, zone.x_max)
							var cl_y: float = clampf(contact_local.y, zone.y_min, zone.y_max)
							target_pos = fh_z * cl_x + Vector3.UP * cl_y + fwd_z * GHOST_FORWARD_PLANE
						else:
							target_pos = contact_local
				else:
					# Spread/tighten based on ball lateral position
					var fh_axis: Vector3 = _player._get_forehand_axis()
					var contact_lateral: float = contact_local.dot(fh_axis)
					var ghost_lateral: float = base_pos.dot(fh_axis)
					var same_side: bool = (contact_lateral > 0.1 and ghost_lateral > 0.0) or (contact_lateral < -0.1 and ghost_lateral < 0.0)
					if same_side and abs(contact_lateral) > 0.3:
						# Ball is wide AND ghost is on same side → spread outward to reach
						var spread_dir: Vector3 = fh_axis * sign(contact_lateral)
						var reach_amount: float = clampf(abs(contact_lateral) - 0.3, 0.0, 0.6) * 0.8
						target_pos = base_pos + spread_dir * reach_amount
					else:
						# Opposite side → shift toward ball side to extend reach
						var shift_dir: Vector3 = fh_axis * sign(contact_lateral)
						target_pos = base_pos + shift_dir * 0.1
		var gdt: float = get_physics_process_delta_time()
		# Ghost lerp speed scales with ball speed
		var ball_ref: RigidBody3D = _player._get_ball_ref() if _player.has_method("_get_ball_ref") else null
		var ball_speed: float = ball_ref.linear_velocity.length() if ball_ref else 0.0
		var ghost_lerp: float
		if ball_speed > 15.0:
			ghost_lerp = 16.0
		elif ball_speed > 8.0:
			ghost_lerp = 10.0
		else:
			ghost_lerp = 6.0
		ghost.position = ghost.position.lerp(target_pos, ghost_lerp * gdt)
		if posture in [_player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND]:
			ghost.rotation_degrees = _offset_resolver.get_posture_rotation_offset_for(posture)
		else:
			var ghost_look: Vector3 = ghost.global_position + _player._get_forward_axis() * 2.0
			ghost.look_at(ghost_look, Vector3.UP, true)
		
		# Solo mode: hide ghosts that aren't the selected one or the follow-through keys
		if solo_mode and not (posture in FT_KEYS):
			ghost.visible = (posture == selected_posture_id)
		elif not solo_mode and not (posture in FT_KEYS):
			ghost.visible = true
			
		if posture in FT_KEYS:
			continue
		var ghost_material: StandardMaterial3D = _get_ghost_material(ghost)
		if ghost_material != null:
			var is_active: bool = posture == paddle_posture
			var ball_dist: float = INF
			if ball != null:
				ball_dist = ghost.global_position.distance_to(ball.global_position)
			var is_near: bool = ball_dist < POSTURE_GHOST_NEAR_RADIUS
			var near_t: float = clampf(1.0 - ball_dist / POSTURE_GHOST_NEAR_RADIUS, 0.0, 1.0)

			var is_hit_flash: bool = posture == _hit_posture and _hit_flash_t > 0.0
			var hit_t: float = _hit_flash_t / POSTURE_GHOST_HIT_FLASH_DURATION

			if is_hit_flash:
				var hf: Dictionary = PostureColors.hit_flash(hit_t)
				ghost_material.albedo_color = hf.albedo
				ghost_material.emission = hf.emission
				ghost_material.emission_energy_multiplier = hf.em_mult
			elif posture == _committed_incoming_posture and _ball_incoming:
				# ── PHASE A — Measure ─────────────────────────────────────────────
				var ghost_world: Vector3 = ghost.global_position
				var ball_to_ghost: float = ghost_world.distance_to(ball.global_position)
				if ball_to_ghost < _closest_ball2ghost:
					_closest_ball2ghost = ball_to_ghost
				var commit_dist: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
				var ttc: float = _compute_ttc(ball, ghost_world)

				# ── PHASE B — Stage (TTC-driven, one-shot BLUE latch) ─────────────
				if _blue_hold_timer > 0.0:
					_blue_hold_timer -= get_physics_process_delta_time()
				var stage: int = PostureColors.compute_stage(ttc, ball_to_ghost, _blue_hold_timer, _blue_latched)
				if stage == 2 and not _blue_latched:
					_blue_latched = true
					_blue_hold_timer = BLUE_HOLD_DURATION
					_ghost_frozen_at = ghost_world

				var sc: Dictionary = PostureColors.stage_colors(stage)
				ghost_material.albedo_color = Color(sc.albedo.r, sc.albedo.g, sc.albedo.b, sc.alpha)
				ghost_material.emission = sc.emission
				ghost_material.emission_energy_multiplier = sc.em_mult

				# ── PHASE C — Emit every frame; log only on stage transition ─────
				var pname: String = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
				if _player.player_num == 0:
					incoming_stage_changed.emit(stage, _committed_incoming_posture, commit_dist, ball_to_ghost, ttc)
				if stage != _last_commit_stage:
					var stage_names: Array[String] = ["PINK", "PURPLE", "BLUE"]
					print("[COLOR P%d] %s %s ttc=%.2f d=%.1f ball2ghost=%.2f traj_pts=%d pos=(%.1f,%.1f)" % [_player.player_num, stage_names[stage], pname, ttc, commit_dist, ball_to_ghost, _trajectory_points.size(), _player.global_position.x, _player.global_position.z])
					_last_commit_stage = stage

				# ── PHASE D — Score (once per ball, uses closest approach) ───────
					if stage == 2 and not _scored_this_ball:
						_scored_this_ball = true
						var grade: String = _commit_selector.grade_ball_to_ghost(_closest_ball2ghost)
						print("[SCORE P%d] %s %s closest=%.2f commits=%d poses=%d greens=%d" % [_player.player_num, grade, pname, _closest_ball2ghost, _commit_count, _pose_change_count, _green_trigger_count])
						if _player.player_num == 0:
							grade_flashed.emit(grade)

				# ── PHASE E — Zone-exit recommit (gated on stage<2 and ball in front) ──
				if _zone_exit_cooldown > 0.0:
					_zone_exit_cooldown -= get_physics_process_delta_time()
				var ball_in_front: bool = false
				if ball != null:
					var to_ball_fwd: float = (ball.global_position - _player.global_position).dot(_player._get_forward_axis())
					ball_in_front = to_ball_fwd > 0.0
				if stage < 2 and _zone_exit_cooldown <= 0.0 and ball_in_front:
					var traj_pt: Vector3 = _commit_selector.find_closest_trajectory_point(_player.global_position, _player.COURT_FLOOR_Y)
					var fh_r: Vector3 = _player._get_forehand_axis()
					var contact_lat: float = (traj_pt - _player.global_position).dot(fh_r)
					var contact_ht: float = traj_pt.y - _player.COURT_FLOOR_Y
					if _player.awareness_grid:
						var ri: Dictionary = _player.awareness_grid.get_approach_info()
						if ri.confidence > 5:
							contact_lat = ri.lateral
							contact_ht = ri.height
					var zone: Dictionary = POSTURE_ZONES.get(_committed_incoming_posture, {})
					if not zone.is_empty():
						var outside: bool = contact_lat < zone.x_min - ZONE_EXIT_MARGIN or contact_lat > zone.x_max + ZONE_EXIT_MARGIN or contact_ht < zone.y_min - ZONE_EXIT_MARGIN or contact_ht > zone.y_max + ZONE_EXIT_MARGIN
						if outside:
							var better_z: int = _find_closest_ghost_to_point(traj_pt)
							if better_z >= 0 and better_z != _committed_incoming_posture:
								var old_n: String = _player.DEBUG_POSTURE_NAMES[_committed_incoming_posture] if _committed_incoming_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
								var new_n: String = _player.DEBUG_POSTURE_NAMES[better_z] if better_z < _player.DEBUG_POSTURE_NAMES.size() else "?"
								_committed_incoming_posture = better_z
								paddle_posture = better_z
								_zone_exit_cooldown = 0.5
								print("[ZONE_EXIT P%d] %s -> %s (lat=%.2f ht=%.2f)" % [_player.player_num, old_n, new_n, contact_lat, contact_ht])
			elif _commit_selector.is_ghost_near_trajectory(posture, posture_ghosts, _player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND) and _ball_incoming:
				if posture not in _green_lit_postures:
					_green_trigger_count += 1
					# Only track first green for primary postures (the ones that can actually commit)
					var is_primary_green: bool = posture in [
						_player.PaddlePosture.FOREHAND, _player.PaddlePosture.BACKHAND,
						_player.PaddlePosture.WIDE_FOREHAND, _player.PaddlePosture.WIDE_BACKHAND,
						_player.PaddlePosture.FORWARD, _player.PaddlePosture.MEDIUM_OVERHEAD,
						_player.PaddlePosture.HIGH_OVERHEAD, _player.PaddlePosture.VOLLEY_READY]
					if _first_green_posture < 0 and is_primary_green:
						_first_green_posture = posture
					var gname: String = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
					var gw: Vector3 = _player.global_position + _offset_resolver.get_posture_offset_for(posture)
					var first_tag: String = " ★FIRST" if posture == _first_green_posture else ""
					print("[GREEN P%d] +%s (#%d) ghost2traj=%.2f pos=(%.1f,%.1f)%s" % [_player.player_num, gname, _green_trigger_count, gw.distance_to(ball.global_position), _player.global_position.x, _player.global_position.z, first_tag])
				_green_lit_postures[posture] = Engine.get_physics_frames()
				var pname: String = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else str(posture)
				_frame_lit_postures.append(pname)
				ghost_material.albedo_color = Color(0.1, 1.0, 0.2, POSTURE_GHOST_NEAR_ALPHA)
				ghost_material.emission = Color(0.0, 1.0, 0.1, 1.0)
				ghost_material.emission_energy_multiplier = POSTURE_GHOST_NEAR_EMISSION
			elif posture in _green_lit_postures:
				# No longer near trajectory — fade from green to base over INCOMING_FADE_DURATION
				var frames_since_lit: int = Engine.get_physics_frames() - int(_green_lit_postures[posture])
				var secs_since: float = frames_since_lit * get_physics_process_delta_time()
				var fade_t: float = clampf(secs_since / INCOMING_FADE_DURATION, 0.0, 1.0)
				var fade_result: Dictionary = PostureColors.green_fading(fade_t, _ghost_base_color)
				if fade_t >= 1.0:
					_green_lit_postures.erase(posture)
				ghost_material.albedo_color = fade_result.albedo
				ghost_material.emission = fade_result.emission
				ghost_material.emission_energy_multiplier = fade_result.em_mult
			elif is_near:
				var pc: Dictionary = PostureColors.proximity_color(near_t, false, _ghost_base_color)
				ghost_material.albedo_color = pc.albedo
				ghost_material.emission_energy_multiplier = pc.em_mult
			elif is_active:
				var pc: Dictionary = PostureColors.proximity_color(0.0, true, _ghost_base_color)
				ghost_material.albedo_color = pc.albedo
				ghost_material.emission_energy_multiplier = pc.em_mult
			else:
				var pc: Dictionary = PostureColors.proximity_color(0.0, false, _ghost_base_color)
				ghost_material.albedo_color = pc.albedo
				ghost_material.emission_energy_multiplier = pc.em_mult
			var is_purple: bool = posture == _committed_incoming_posture and _ball_incoming
			if not is_purple and not (_commit_selector.is_ghost_near_trajectory(posture, posture_ghosts, _player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND) and _ball_incoming) and not (posture in _green_lit_postures) and not is_hit_flash:
				ghost_material.emission = Color(_ghost_base_color.r * 0.7 + 0.2, _ghost_base_color.g * 0.7 + 0.2, _ghost_base_color.b * 0.7 + 0.2, 1.0)

			# GAP-34: TTC-tiered grid override. Query the volumetric awareness
			# grid for this ghost's TTC. When the grid reports a valid TTC, it
			# becomes the authoritative border color (RED/ORANGE/YELLOW/GREEN).
			# Committed-stage purple and smash-hit flash take precedence so the
			# commit feedback stays readable.
			if _player.awareness_grid and _ball_incoming and not is_purple and not is_hit_flash:
				var g_ttc: float = _player.awareness_grid.get_ttc_at_world_point(ghost.global_position, 0.45)
				if g_ttc < 1.5:
					var tier: Color = _player.awareness_grid._get_time_color(g_ttc)
					var ov: Dictionary = PostureColors.grid_override(g_ttc, tier)
					ghost_material.albedo_color = ov.albedo
					ghost_material.emission = ov.emission
					ghost_material.emission_energy_multiplier = ov.em_mult

			_apply_ghost_material(ghost, ghost_material)

	_update_ft_ghosts()

	_apply_ghost_separation()


func _update_ft_ghosts() -> void:
	# Update follow-through ghost glow — brighten the one matching current charge family
	var is_charging: bool = _player.hitting != null and _player.hitting.charge_visual_active
	for ft_key in ft_ghosts.keys():
		var ft_ghost: Node3D = ft_ghosts[ft_key]
		if ft_ghost == null:
			continue
		var ft_mat: StandardMaterial3D = _get_ghost_material(ft_ghost)
		if ft_mat == null:
			continue
		var matching: bool = false
		if is_charging:
			var cur: int = paddle_posture
			match ft_key:
				FT_FOREHAND: matching = cur in _player.FOREHAND_POSTURES
				FT_BACKHAND: matching = cur in _player.BACKHAND_POSTURES
				FT_CENTER: matching = cur in _player.CENTER_POSTURES
				FT_OVERHEAD: matching = cur in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]
		if matching:
			ft_mat.albedo_color = Color(0.2, 1.0, 0.95, 0.65)
			ft_mat.emission = Color(0.1, 1.0, 0.9, 1.0)
			ft_mat.emission_energy_multiplier = 1.2
		else:
			ft_mat.albedo_color = Color(0.1, 0.9, 0.95, 0.35)
			ft_mat.emission = Color(0.0, 0.8, 0.9, 1.0)
			ft_mat.emission_energy_multiplier = 0.25
		_apply_ghost_material(ft_ghost, ft_mat)


	if _ball_incoming and _frame_lit_postures != _last_lit_postures:
		_last_lit_postures = _frame_lit_postures.duplicate()
	elif not _ball_incoming:
		_last_lit_postures.clear()


# ── Posture offset helpers ────────────────────────────────────────────────────

func get_posture_charge_sign() -> float:
	match paddle_posture:
		_player.PaddlePosture.BACKHAND, _player.PaddlePosture.LOW_BACKHAND, _player.PaddlePosture.CHARGE_BACKHAND, \
		_player.PaddlePosture.WIDE_BACKHAND, _player.PaddlePosture.MID_LOW_BACKHAND, \
		_player.PaddlePosture.MID_LOW_WIDE_BACKHAND, _player.PaddlePosture.LOW_WIDE_BACKHAND:
			return -_player._get_swing_sign()
		_player.PaddlePosture.FORWARD, _player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.MID_LOW_FORWARD, \
		_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD, _player.PaddlePosture.VOLLEY_READY:
			return 0.0
	return _player._get_swing_sign()

# ── Internal helpers ──────────────────────────────────────────────────────────

func _get_posture_offset() -> Vector3:
	# When committed, return the ghost's ACTUAL position (it has flown to contact point)
	if _committed_incoming_posture >= 0 and _last_commit_stage >= 0:
		var ghost: Node3D = posture_ghosts.get(_committed_incoming_posture)
		if ghost:
			return ghost.position
	return get_posture_offset_for(paddle_posture)


## Phase 3: Apply full-body posture fields to skeleton.
## Pass `def_override` when applying a temporary blend (e.g. transition player) not equal to the library entry.
func _apply_full_body_posture(def_override: PostureDefinition = null) -> void:
	if _skeleton_applier == null or _posture_lib == null:
		return
	var def: PostureDefinition = _player.get_runtime_posture_def(def_override)
	if def:
		_skeleton_applier.apply(def)

func _get_basis_from_rotation(rot_deg: Vector3) -> Basis:
	var b := Basis()
	b = b * Basis(Vector3.RIGHT, deg_to_rad(rot_deg.x))
	b = b * Basis(Vector3.UP, deg_to_rad(rot_deg.y))
	b = b * Basis(Vector3.FORWARD, deg_to_rad(rot_deg.z))
	return b
