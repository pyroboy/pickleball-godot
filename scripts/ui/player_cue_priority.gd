extends RefCounted
## One player cue at a time (presentation only: reads game state, never writes it).
## The cues around your player used to stack (YOU ring, landing ring + chevrons, the
## timing ring, HOLD HIT pill, aim arc). Each one now asks `current()` and draws only
## when it is the winner, highest first:
##   AIM      HIT (or Space) held: the aim arc and its landing target. The timing ring
##            shrinks onto the HIT pad (release cue stays on the button, off the court).
##   MOVE     the incoming movement guide (when that setting is on) has a target.
##   SMASH    the smash guide (stand here) is up.
##   OUT      the incoming ball is landing out (orange ring + OUT).
##   TIMING   a ball you can prepare for is coming: the timing ring around HIT.
##   LANDING  a ball is coming down on your side with no contact to time yet (cyan ring).
##   YOU      otherwise (waiting, serving, between points): the YOU ring only.
## Worked out once per rendered frame from what each cue published the frame before.
enum { NONE, YOU, LANDING, TIMING, OUT, SMASH, MOVE, AIM }

static var _frame := -1
static var _cue := YOU
static var _rect_frame := -1
static var _rect := Rect2()

static func current(game) -> int:
	var frame: int = Engine.get_process_frames()
	if frame == _frame: return _cue
	_frame = frame
	_cue = _resolve(game)
	return _cue

static func _resolve(game) -> int:
	if game == null or not is_instance_valid(game): return NONE
	if game.get("hud") == null or not game.hud._gameplay_visible or game._tool_state_active() or bool(game.get("match_over")): return NONE
	if holding(game): return AIM
	if game.game_state != game.GameState.PLAYING: return YOU
	var guide = game.get("movement_guide")
	if guide != null and is_instance_valid(guide) and not guide._presentation.is_empty(): return MOVE
	var trajectory = game.get("game_trajectory")
	if trajectory != null and bool(trajectory.get("smash_wanted")): return SMASH
	var feel = game.get_node_or_null("MatchFeel")
	var landing: int = int(feel.get("landing_state")) if feel != null else 0
	if landing == 2: return OUT
	var controls = game.get("mobile_controls")
	if controls != null and controls.enabled and controls._hit_timing.active: return TIMING
	if landing == 1: return LANDING
	return YOU

## HIT held (touch), Space held (desktop charge) or the aim focus is running.
static func holding(game) -> bool:
	var controls = game.get("mobile_controls")
	if controls != null and controls.enabled and controls._charge_id != -1: return true
	var handler = game.get("input_handler")
	if handler != null and bool(handler.serve_is_charging): return true
	var focus = game.get("aim_focus")
	return focus != null and bool(focus.active)

## Screen rect of your drawn player (feet on the floor to just over the head, arms'
## width), for cues that must not cross the sprite. Empty when off camera.
static func player_screen_rect(game, camera: Camera3D) -> Rect2:
	var frame: int = Engine.get_process_frames()
	if frame == _rect_frame: return _rect
	_rect_frame = frame
	_rect = Rect2()
	if game == null or camera == null: return _rect
	var actor = game.get_human_actor() if game.has_method("get_human_actor") else game.get("player_left")
	if actor == null or not is_instance_valid(actor) or not actor.is_visible_in_tree(): return _rect
	var at: Vector3 = actor.get_global_transform_interpolated().origin
	var side: Vector3 = camera.global_basis.x * 0.55
	var found := false
	for point in [Vector3(at.x, PickleballConstants.FLOOR_Y, at.z), at + Vector3.UP * 1.15]:
		for offset in [-side, side]:
			var p: Vector3 = point + offset
			if camera.is_position_behind(p): return Rect2()
			var screen: Vector2 = camera.unproject_position(p)
			_rect = _rect.expand(screen) if found else Rect2(screen, Vector2.ZERO)
			found = true
	return _rect
