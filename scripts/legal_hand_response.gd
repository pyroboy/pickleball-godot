extends RefCounted
## Pure impact response. Caller owns hit order, ball/rally mutation, stroke
## continuity, and separation tracking. This function never aims or teleports.
const BallPhysics = preload("res://scripts/ball.gd")

static func solve(incoming: Vector3, evidence: Dictionary, elapsed: float) -> Dictionary:
	var result := {"qualified": false, "responded": false, "velocity": incoming,
		"kind": "legal_hand", "reason": "unqualified_contact"}
	if not evidence.get("hit", false) or evidence.get("ambiguous", false) or evidence.get("kind", "body") not in ["legal_hand", "legal_paddle"]: return result
	var normal: Vector3 = evidence.get("normal", Vector3.ZERO)
	if not incoming.is_finite() or not normal.is_finite() or normal.length_squared() < 0.5:
		result.reason = "missing_contact_normal"
		return result
	normal = normal.normalized()
	var displacement: Vector3 = evidence.get("surface_displacement", Vector3.ZERO)
	if not displacement.is_finite() or (displacement.length_squared() > 1e-14 and elapsed <= 0.0):
		result.reason = "missing_surface_interval"
		return result
	var surface_velocity: Vector3 = displacement / elapsed if elapsed > 0.0 else Vector3.ZERO
	# Very large animation discontinuities cannot create a fabricated save.
	if surface_velocity.length() > BallPhysics.MAX_SPEED * 2.0:
		result.reason = "surface_motion_discontinuity"
		return result
	result.qualified = true
	result.kind = evidence.kind
	result.normal = normal
	result.surface_velocity = surface_velocity
	var closing_speed: float = (incoming - surface_velocity).dot(normal)
	if closing_speed >= 0.0:
		result.reason = "already_separating"
		return result
	var restitution: float = BallPhysics.cor_for_impact_speed(-closing_speed)
	result.velocity = (incoming - normal * closing_speed * (1.0 + restitution)).limit_length(BallPhysics.MAX_SPEED)
	result.responded = true
	result.reason = "physical_normal_impulse"
	result.restitution = restitution
	result.relative_closing_speed = -closing_speed
	return result

static func classify_contact(previous: Dictionary, player_num: int, last_hitter: int,
		stroke_serial: int, touching: bool, separated_since_contact: bool,
		active_strike: bool = false, continuous_direction: bool = false) -> Dictionary:
	## Classification only. Geometric separation alone is not an illegal
	## double hit: a continuous single-direction stroke may contact twice.
	## The caller supplies an observed stroke identity, never a shot label.
	if not touching: return {"new_contact": false, "classification": "SEPARATED"}
	if previous.is_empty() or int(previous.get("player_num", -1)) != player_num or last_hitter != player_num:
		return {"new_contact": true, "classification": "NEW_CONTACT"}
	if not separated_since_contact:
		return {"new_contact": false, "classification": "CONTIGUOUS_CONTACT"}
	var same_stroke: bool = stroke_serial >= 0 and stroke_serial == int(previous.get("stroke_serial", -2))
	var permitted: bool = same_stroke and active_strike and continuous_direction
	return {"new_contact": true, "classification": "SEPARATED_SAME_STROKE" if permitted else "NEW_SAME_HITTER_STROKE",
		"legal_recontact": permitted, "fault": not permitted}

static func classify_actor_contact(previous: Dictionary, actor_id: int, team_id: int,
		last_actor_id: int, last_team_id: int, stroke_serial: int, touching: bool,
		separated_since_contact: bool, active_strike: bool = false,
		continuous_direction: bool = false) -> Dictionary:
	if touching and last_team_id == team_id and last_actor_id != actor_id:
		return {"new_contact": true, "classification": "PARTNER_DOUBLE_CONTACT", "legal_recontact": false, "fault": true}
	var owned: Dictionary = previous.duplicate()
	owned["player_num"] = int(previous.get("actor_id", -1))
	return classify_contact(owned, actor_id, last_actor_id, stroke_serial,
		touching, separated_since_contact, active_strike, continuous_direction)
