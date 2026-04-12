extends Node
## Rules.gd - Pickleball game rules

# ==================== RULE CONSTANTS ====================

# Court dimensions (from shared constants)
const COURT_LENGTH := PickleballConstants.COURT_LENGTH
const COURT_WIDTH := PickleballConstants.COURT_WIDTH
const NET_HEIGHT := PickleballConstants.NET_HEIGHT
const NON_VOLLEY_ZONE := PickleballConstants.NON_VOLLEY_ZONE

# Serve rules
const MAX_SERVERS_PER_TURN := 1
const SERVE_MUST_BE_DIAGONAL := true

# Double bounce rule
const DOUBLE_BOUNCE_ENABLED := true
var bounces_in_rally := 0

# Faults
enum FaultType {
	NONE,
	OUT_OF_BOUNDS,
	NET_BALL,
	NON_VOLLEY_ZONE_VOLLEY,
	WRONG_SERVICE_COURT,
	BALL_HIT_TWICE,
	FAULT_SERVE
}

# ==================== STATE ====================
var rally_bounces := 0
var serving_in_nz := false
var last_fault := FaultType.NONE

# ==================== SERVE RULES ====================

func get_valid_serve_positions(team: int, side: int) -> Array:
	var half_len := COURT_LENGTH / 2.0
	var half_wid := COURT_WIDTH / 2.0
	
	if team == 0:
		if side == 0:
			return [Vector3(-half_wid/2, 0, -half_len/4), Vector3(-half_wid/2, 0, half_len/4)]
		else:
			return [Vector3(half_wid/2, 0, -half_len/4), Vector3(half_wid/2, 0, half_len/4)]
	else:
		if side == 0:
			return [Vector3(half_wid/2, 0, half_len/4), Vector3(half_wid/2, 0, -half_len/4)]
		else:
			return [Vector3(-half_wid/2, 0, half_len/4), Vector3(-half_wid/2, 0, -half_len/4)]

func is_valid_serve(ball_pos: Vector3, serve_team: int) -> bool:
	var bounds: Dictionary = get_service_court_bounds(serve_team)
	if ball_pos.x >= bounds.left and ball_pos.x <= bounds.right:
		if ball_pos.z >= bounds.top and ball_pos.z <= bounds.bottom:
			return true
	return false

func get_service_court_bounds(team: int) -> Dictionary:
	var half_len := COURT_LENGTH / 2.0
	var half_wid := COURT_WIDTH / 2.0
	
	if team == 0:
		return {"left": 0, "right": half_wid, "top": -half_len, "bottom": half_len}
	else:
		return {"left": -half_wid, "right": 0, "top": -half_len, "bottom": half_len}

func get_serving_court_for_team(team: int) -> Dictionary:
	var half_len := COURT_LENGTH / 2.0
	var half_wid := COURT_WIDTH / 2.0
	
	if team == 0:
		return {"left": 0, "right": half_wid, "top": -half_len, "bottom": half_len}
	else:
		return {"left": -half_wid, "right": 0, "top": -half_len, "bottom": half_len}

# ==================== DOUBLE BOUNCE RULE ====================

func can_hit_volley(_team_hit: int, ball_has_bounced: bool) -> bool:
	if not DOUBLE_BOUNCE_ENABLED:
		return true
	if not ball_has_bounced:
		return false
	return true

func record_bounce() -> void:
	rally_bounces += 1

func get_rally_bounce_count() -> int:
	return rally_bounces

func reset_rally_state() -> void:
	rally_bounces = 0
	serving_in_nz = false
	last_fault = FaultType.NONE

# ==================== NON-VOLLEY ZONE ====================

func is_in_non_volley_zone(pos: Vector3) -> bool:
	return abs(pos.z) < NON_VOLLEY_ZONE

func can_hit_at_position(player_pos: Vector3, _ball_pos: Vector3, ball_is_airborne: bool) -> bool:
	if not is_in_non_volley_zone(player_pos):
		return true
	if not ball_is_airborne:
		return true
	last_fault = FaultType.NON_VOLLEY_ZONE_VOLLEY
	return false

# ==================== OUT OF BOUNDS ====================

func check_out_of_bounds(ball_pos: Vector3) -> bool:
	var bounds: Dictionary = get_court_bounds()
	if ball_pos.x < bounds.left or ball_pos.x > bounds.right:
		last_fault = FaultType.OUT_OF_BOUNDS
		return true
	if ball_pos.z < bounds.top or ball_pos.z > bounds.bottom:
		last_fault = FaultType.OUT_OF_BOUNDS
		return true
	return false

func check_net_fault(ball_pos: Vector3, ball_vel: Vector3) -> bool:
	if ball_pos.y < NET_HEIGHT and abs(ball_pos.z) < 0.1:
		if ball_vel.length() < 2.0:
			last_fault = FaultType.NET_BALL
			return true
	return false

# ==================== SCORING ====================

func can_scoring_team_score(_current_server: int, _winning_team: int) -> bool:
	return true

func is_match_over(score_left: int, score_right: int) -> bool:
	if score_left >= 11 or score_right >= 11:
		var diff: int = abs(score_left - score_right)
		return diff >= 2
	return false

# ==================== HELPERS ====================

func get_court_bounds() -> Dictionary:
	var half_len := COURT_LENGTH / 2.0
	var half_wid := COURT_WIDTH / 2.0
	return {
		"left": -half_wid,
		"right": half_wid,
		"top": -half_len,
		"bottom": half_len,
		"net_z": 0,
		"nz_back": -NON_VOLLEY_ZONE,
		"nz_front": NON_VOLLEY_ZONE
	}

func get_nz_bounds() -> Dictionary:
	return {
		"top": -NON_VOLLEY_ZONE,
		"bottom": NON_VOLLEY_ZONE,
		"left": -COURT_WIDTH / 2.0,
		"right": COURT_WIDTH / 2.0
	}

func get_fault_name() -> String:
	match last_fault:
		FaultType.OUT_OF_BOUNDS:
			return "Out of Bounds"
		FaultType.NET_BALL:
			return "Net Ball"
		FaultType.NON_VOLLEY_ZONE_VOLLEY:
			return "Volley in Kitchen"
		FaultType.WRONG_SERVICE_COURT:
			return "Wrong Service Court"
		FaultType.BALL_HIT_TWICE:
			return "Ball Hit Twice"
		FaultType.FAULT_SERVE:
			return "Fault Serve"
		_:
			return "None"
