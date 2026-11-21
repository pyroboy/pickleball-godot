class_name PostureCommitSelector
extends RefCounted




















const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const POSTURE_GHOST_NEAR_RADIUS: float = 0.3


const TRAJECTORY_STEP_TIME: float = 0.04


const GRADE_PERFECT: float = 0.25
const GRADE_GREAT: float = 0.4
const GRADE_GOOD: float = 0.6
const GRADE_OK: float = 0.8


const REACH_XZ: float = 1.2


const COURT_FLOOR_Y: float = 0.08



var _trajectory_points: Array[Vector3] = []




func set_trajectory_points(points: Array[Vector3]) -> void :
    _trajectory_points = points




func _get_ghost_head_world(ghost: Node3D) -> Vector3:
    if ghost == null:
        return Vector3.ZERO

    return ghost.global_position + ghost.global_transform.basis.y * PaddleSize.HEAD_CENTER_Y


func is_ghost_near_trajectory(posture: int, posture_ghosts: Dictionary, 
        forehand_charge: int, backhand_charge: int) -> bool:
    if _trajectory_points.is_empty():
        return false
    if posture == forehand_charge or posture == backhand_charge:
        return false
    var ghost: Node3D = posture_ghosts.get(posture)
    if ghost == null:
        return false
    var ghost_head: Vector3 = _get_ghost_head_world(ghost)
    for pt in _trajectory_points:
        if ghost_head.distance_to(pt) < POSTURE_GHOST_NEAR_RADIUS:
            return true
    return false




func build_green_set(posture_ghosts: Dictionary, 
        forehand_charge: int, backhand_charge: int) -> Dictionary:
    var greens: Dictionary = {}
    for posture in posture_ghosts.keys():
        if is_ghost_near_trajectory(posture, posture_ghosts, 
                forehand_charge, backhand_charge):
            greens[posture] = true
    return greens





func find_best_green_posture(ref_pos: Vector3, posture_ghosts: Dictionary, 
        posture_zones: Dictionary, forehand_charge: int, 
        backhand_charge: int, player_pos: Vector3, 
        forehand_axis: Vector3, court_floor_y: float, 
        awareness_grid = null) -> int:

    var local_lat: float = (ref_pos - player_pos).dot(forehand_axis)
    var local_ht: float = ref_pos.y - court_floor_y


    if awareness_grid:
        var info: Dictionary = awareness_grid.get_approach_info()
        if info.confidence > 5:
            local_lat = info.lateral
            local_ht = info.height




    var _ball_ref = null
    if awareness_grid and awareness_grid.has_method("_get_ball_ref"):
        _ball_ref = awareness_grid._get_ball_ref()


    var green_set: Dictionary = build_green_set(posture_ghosts, 
            forehand_charge, backhand_charge)
    if not green_set.is_empty():
        var best: int = -1
        var best_score: float = INF
        for posture in green_set:
            if posture not in posture_zones:
                continue
            var zone: Dictionary = posture_zones[posture]
            var lat_miss: float = 0.0
            if local_lat < zone.x_min:
                lat_miss = zone.x_min - local_lat
            elif local_lat > zone.x_max:
                lat_miss = local_lat - zone.x_max
            var ht_miss: float = 0.0
            if local_ht < zone.y_min:
                ht_miss = zone.y_min - local_ht
            elif local_ht > zone.y_max:
                ht_miss = local_ht - zone.y_max
            var score: float = ht_miss * 2.5 + lat_miss


            if awareness_grid:
                var posture_scores: Dictionary = awareness_grid.get_posture_zone_scores()
                var grid_score: float = posture_scores.get(posture, 0.0)
                score -= grid_score * 0.12

            var ghost: Node3D = posture_ghosts.get(posture)
            if ghost:
                score += 0.05 * _get_ghost_head_world(ghost).distance_to(ref_pos)
            if score < best_score:
                best_score = score
                best = posture
        if best >= 0:
            return best


    var best_fallback: int = -1
    var best_d: float = INF
    for posture in posture_zones:
        var zone: Dictionary = posture_zones[posture]
        var cx: float = (zone.x_min + zone.x_max) / 2.0
        var cy: float = (zone.y_min + zone.y_max) / 2.0
        var dx: float = local_lat - cx
        var dy: float = local_ht - cy
        var d: float = sqrt(dx * dx + dy * dy)
        if d < best_d:
            best_d = d
            best_fallback = posture
    return best_fallback




func find_closest_trajectory_point(player_pos: Vector3, 
        court_floor_y: float) -> Vector3:
    if _trajectory_points.is_empty():
        return player_pos
    var player_xz: = Vector2(player_pos.x, player_pos.z)
    var best_pt: = _trajectory_points[0]
    var best_dist: = INF
    for pt in _trajectory_points:
        if pt.y < (court_floor_y - 0.02) or pt.y > 1.8:
            continue
        var d: = player_xz.distance_to(Vector2(pt.x, pt.z))
        if d < best_dist:
            best_dist = d
            best_pt = pt
    return best_pt





func compute_contact_at_player_z(ball_pos: Vector3, ball_vel: Vector3, 
        player_pos: Vector3, court_floor_y: float, 
        gravity: float, cor_func: Callable) -> Vector3:
    var player_z: float = player_pos.z
    var bpos: Vector3 = ball_pos
    var bvel: Vector3 = ball_vel

    if abs(bvel.z) < 0.1:
        return bpos

    var t: float = (player_z - bpos.z) / bvel.z
    if t < 0.0:
        return bpos


    var qa: float = -0.5 * gravity
    var qb: float = bvel.y
    var qc: float = bpos.y - court_floor_y
    var disc: float = qb * qb - 4.0 * qa * qc
    if disc >= 0.0 and qa != 0.0:
        var t_floor: float = ( - qb - sqrt(disc)) / (2.0 * qa)
        if t_floor > 0.0 and t_floor < t:

            var bounce_x: float = bpos.x + bvel.x * t_floor
            var bounce_z: float = bpos.z + bvel.z * t_floor
            var vy_at_floor: float = bvel.y - gravity * t_floor
            var bounce_vy: float = abs(vy_at_floor) * cor_func.call(abs(vy_at_floor))
            var rem_t: float = (player_z - bounce_z) / bvel.z
            if rem_t > 0.0:
                return Vector3(
                    bounce_x + bvel.x * rem_t, 
                    court_floor_y + bounce_vy * rem_t - 0.5 * gravity * rem_t * rem_t, 
                    player_z)


    return Vector3(
        bpos.x + bvel.x * t, 
        bpos.y + bvel.y * t - 0.5 * gravity * t * t, 
        player_z)



func compute_simple_trajectory(ball_pos: Vector3, ball_vel: Vector3, 
        gravity: float, court_floor_y: float, 
        max_steps: int = 80) -> Array[Vector3]:
    var points: Array[Vector3] = []
    var pos: Vector3 = ball_pos
    var vel: Vector3 = ball_vel
    var has_bounced: bool = false
    for _step in range(max_steps):
        vel.y -= gravity * 0.04
        pos += vel * 0.04
        if pos.y <= court_floor_y:
            pos.y = court_floor_y
            if not has_bounced:
                has_bounced = true

                var impact_speed: float = abs(vel.y)
                vel.y = impact_speed * 0.685
            else:
                points.append(pos)
                break
        points.append(pos)
    return points





func compute_ttc(ball_pos: Vector3, ball_vel: Vector3, 
        ghost_world: Vector3) -> float:
    var ttc: float = -1.0
    if _trajectory_points.size() >= 2:
        var best_ball_i: int = 0
        var best_ghost_i: int = 0
        var best_ball_d: float = INF
        var best_ghost_d: float = INF
        for i in _trajectory_points.size():
            var d_ball: float = _trajectory_points[i].distance_to(ball_pos)
            if d_ball < best_ball_d:
                best_ball_d = d_ball
                best_ball_i = i
            var d_ghost: float = _trajectory_points[i].distance_to(ghost_world)
            if d_ghost < best_ghost_d:
                best_ghost_d = d_ghost
                best_ghost_i = i
        if best_ghost_i > best_ball_i:
            ttc = float(best_ghost_i - best_ball_i) * TRAJECTORY_STEP_TIME
    if ttc < 0.0:
        var speed: float = ball_vel.length()
        if speed < 0.5:
            return 3.0
        ttc = ghost_world.distance_to(ball_pos) / speed
    return clampf(ttc, 0.0, 3.0)



func grade_ball_to_ghost(d: float) -> String:
    if d < GRADE_PERFECT: return "PERFECT"
    if d < GRADE_GREAT: return "GREAT"
    if d < GRADE_GOOD: return "GOOD"
    if d < GRADE_OK: return "OK"
    return "MISS"



func height_tier(ball_y: float, court_floor_y: float) -> int:
    var rel_h: float = ball_y - court_floor_y
    if rel_h < 0.22: return 0
    if rel_h < 0.55: return 1
    if rel_h < 1.05: return 2
    return 3


