extends RefCounted
## Change-of-ends walk. Each player jogs past the net post on their team's side
## straight to their new spot: one smooth path per player, eased speed, corners
## rounded by steering at a point LOOKAHEAD ahead on the path, nobody waits for
## the others. The old route (8.3 m behind the baseline, a side corridor, every
## corner gated on all four players) was ~30 m at 2.65 m/s and looked robotic.
## The scene owns pose and the ledger commit (unchanged).
const SPEED: float = 4.2          # brisk jog
const ACCEL: float = 7.0
const BRAKE: float = 6.0
const LOOKAHEAD: float = 1.1
const POST_X: float = 3.75        # just outside the net post (court half-width 3.05)
const LANE_SEPARATION: float = .85
const POST_Z: float = 1.0         # pass the post this far either side of the net
const ARRIVE: float = .08
var actors: Array = []
var routes: Array = []            # per actor: Array[Vector3] polyline
var progress: Array = []          # per actor: distance travelled along its polyline
var lengths: Array = []
var speeds: Array = []
var top_speeds: Array = []        # per actor: own jog pace
var delays: Array = []            # per actor: staggered start (s)
var stage: int = 0                # kept for status reports: 0 walking, 5 arrived
var active: bool = false
var arrived: bool = false
var deadline_seconds: float = 0.0
var elapsed: float = 0.0
var server_actor_id: int = -1

func begin(game, roster: Array) -> bool:
	if game == null or not game.doubles_mode or not game.doubles_state.end_change_pending: return false
	actors = roster.duplicate(); routes.clear(); progress.clear(); lengths.clear(); speeds.clear(); top_speeds.clear(); delays.clear()
	stage = 0; elapsed = 0.0; arrived = false
	server_actor_id = game.get_server_actor().get_actor_id()
	var longest: float = 0.0
	for actor in actors:
		var peers: Array = game.get_team_players(actor.team_id)
		var ordinal: int = peers.find(actor)
		var side_x: float = 1.0 if actor.team_id == 0 else -1.0
		var lane_x: float = side_x * (POST_X + LANE_SEPARATION * ordinal)
		var old_sign: float = 1.0 if actor.court_side == 0 else -1.0
		var target: Vector3 = game.doubles_controller.reset_spawn_position(actor)
		target.x = -target.x; target.z = -target.z
		var y: float = actor.ground_y
		var start := Vector3(actor.global_position.x, y, actor.global_position.z)
		var points: Array = [start, Vector3(lane_x, y, old_sign * POST_Z), Vector3(lane_x, y, -old_sign * POST_Z), Vector3(target.x, y, target.z)]
		var distance: float = 0.0
		for i in range(1, points.size()): distance += points[i - 1].distance_to(points[i])
		routes.append(points); progress.append(0.0); lengths.append(distance); speeds.append(0.0)
		# Own pace, fixed per player (no RNG): -12%..+8% of SPEED, start 0..0.45 s later.
		var trait_value: float = fposmod(float(actor.actor_id) * 0.618034 + 0.27, 1.0)
		top_speeds.append(SPEED * lerpf(0.88, 1.08, trait_value))
		delays.append(0.45 * fposmod(trait_value * 2.7 + 0.13, 1.0))
		longest = maxf(longest, distance / float(top_speeds[-1]) * SPEED + float(delays[-1]) * SPEED)
	deadline_seconds = longest / SPEED + 6.0
	active = true
	return true

## Point at distance s along actor index's polyline.
func _point_at(index: int, s: float) -> Vector3:
	var points: Array = routes[index]
	var left: float = maxf(s, 0.0)
	for i in range(1, points.size()):
		var seg: float = points[i - 1].distance_to(points[i])
		if left <= seg and seg > 0.0: return points[i - 1].lerp(points[i], left / seg)
		left -= seg
	return points[-1]

func advance(delta: float) -> Dictionary:
	if not active: return {"active": false, "arrived": arrived}
	elapsed += maxf(0.0, delta)
	if elapsed > deadline_seconds:
		active = false
		return {"active": false, "arrived": false, "reason": "finite end-change route deadline"}
	var all_arrived: bool = true
	for index in actors.size():
		# Progress follows the actor's real position: the furthest path point it has reached.
		var here: Vector3 = actors[index].global_position
		var best_s: float = float(progress[index])
		for step in 12:
			var s: float = float(progress[index]) + step * .1
			var p: Vector3 = _point_at(index, s)
			if Vector2(p.x - here.x, p.z - here.z).length() < .35: best_s = maxf(best_s, s)
		progress[index] = minf(best_s, float(lengths[index]))
		var final: Vector3 = routes[index][-1]
		if Vector2(final.x - here.x, final.z - here.z).length() > ARRIVE: all_arrived = false
	if all_arrived:
		stage = 5; arrived = true; active = false
	return {"active": active, "arrived": arrived, "stage": stage, "elapsed": elapsed}

## Steering point: LOOKAHEAD ahead of the actor's progress, the end point near the finish.
func target_for(index: int) -> Vector3:
	if index >= routes.size(): return Vector3.ZERO
	return _point_at(index, minf(float(progress[index]) + LOOKAHEAD, float(lengths[index])))

func remaining(index: int) -> float:
	if index >= routes.size(): return 0.0
	var here: Vector3 = actors[index].global_position
	var final: Vector3 = routes[index][-1]
	return maxf(float(lengths[index]) - float(progress[index]), Vector2(final.x - here.x, final.z - here.z).length())

## Eased jog velocity toward the steering point: accelerate to SPEED, brake to stop
## exactly at the end of the path.
func velocity_for(index: int, dt: float) -> Vector3:
	if index >= routes.size(): return Vector3.ZERO
	var here: Vector3 = actors[index].global_position
	var aim: Vector3 = target_for(index) - here
	aim.y = 0.0
	var left: float = remaining(index)
	if left < .02 or aim.length() < .005:
		speeds[index] = 0.0
		return Vector3.ZERO
	if elapsed < float(delays[index]):
		speeds[index] = 0.0
		return Vector3.ZERO
	var cap: float = minf(float(top_speeds[index]), sqrt(2.0 * BRAKE * left))
	var speed: float = move_toward(float(speeds[index]), cap, (ACCEL if cap > float(speeds[index]) else BRAKE * 2.0) * dt)
	speeds[index] = speed
	var step: Vector3 = aim.normalized() * speed
	if step.length() * dt > aim.length() and left <= LOOKAHEAD + .05: step = aim / maxf(dt, 1e-5)
	return step

func cancel() -> void:
	active = false; arrived = false; actors.clear(); routes.clear(); progress.clear(); lengths.clear(); speeds.clear(); top_speeds.clear(); delays.clear()
