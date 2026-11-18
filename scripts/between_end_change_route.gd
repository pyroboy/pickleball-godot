extends RefCounted
## Finite outside-net walking plan. The scene owns pose and ledger commit.
const SPEED: float = 2.65
const CORRIDOR_INNER: float = 4.6
const CORRIDOR_SEPARATION: float = .9
const STAGING_DEPTH: float = 8.3
var actors: Array = []
var routes: Array = []
var stage: int = 0
var active: bool = false
var arrived: bool = false
var deadline_seconds: float = 0.0
var elapsed: float = 0.0
var server_actor_id: int = -1

func begin(game, roster: Array) -> bool:
 if game == null or not game.doubles_mode or not game.doubles_state.end_change_pending: return false
 actors = roster.duplicate(); routes.clear(); stage = 0; elapsed = 0.0; arrived = false
 server_actor_id = game.get_server_actor().get_actor_id()
 var longest: float = 0.0
 for actor in actors:
  var peers: Array = game.get_team_players(actor.team_id)
  var ordinal: int = peers.find(actor)
  var corridor_sign: float = 1.0 if actor.team_id == 0 else -1.0
  var lane_x: float = corridor_sign * (CORRIDOR_INNER + CORRIDOR_SEPARATION * ordinal)
  var old_sign: float = 1.0 if actor.court_side == 0 else -1.0
  var target: Vector3 = game.doubles_controller.reset_spawn_position(actor)
  target.x = -target.x; target.z = -target.z
  var exit_z: float = old_sign * (STAGING_DEPTH + float(ordinal) * .9)
  var entry_z: float = -old_sign * (STAGING_DEPTH + float(ordinal) * .9)
  var points: Array[Vector3] = [Vector3(actor.global_position.x, actor.ground_y, exit_z), Vector3(lane_x, actor.ground_y, exit_z), Vector3(lane_x, actor.ground_y, entry_z), Vector3(target.x, actor.ground_y, entry_z), target]
  routes.append(points)
  var distance: float = 0.0; var previous: Vector3 = actor.global_position
  for point in points: distance += previous.distance_to(point); previous = point
  longest = maxf(longest, distance)
 deadline_seconds = longest / SPEED + 8.0
 active = true
 return true

func advance(delta: float) -> Dictionary:
 if not active: return {"active": false, "arrived": arrived}
 elapsed += maxf(0.0, delta)
 if elapsed > deadline_seconds:
  active = false
  return {"active": false, "arrived": false, "reason": "finite end-change route deadline"}
 var all_arrived: bool = true
 for index in actors.size():
  if actors[index].global_position.distance_to(routes[index][stage]) > .06: all_arrived = false
 if all_arrived:
  stage += 1
  if stage >= 5: arrived = true; active = false
 return {"active": active, "arrived": arrived, "stage": stage, "elapsed": elapsed}

func target_for(index: int) -> Vector3:
 return routes[index][mini(stage, 4)]

func cancel() -> void:
 active = false; arrived = false; actors.clear(); routes.clear()
