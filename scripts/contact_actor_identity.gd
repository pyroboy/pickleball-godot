extends RefCounted
## Three separate identities. Legacy player_num and team-only events never
## choose between partners; geometry follows court_side after end changes.
static func actor_id(actor) -> int:
	if not is_instance_valid(actor): return -1
	if actor.has_method("get_actor_id"): return int(actor.get_actor_id())
	return int(actor.player_num) if "player_num" in actor else int(actor.get_meta("legacy_contact_actor_id", -1))
static func team_id(actor) -> int:
	if not is_instance_valid(actor): return -1
	if actor.has_method("get_team_id"): return int(actor.get_team_id())
	return int(actor.player_num) if "player_num" in actor else int(actor.get_meta("legacy_contact_actor_id", -1))
static func court_side(actor) -> int:
	if not is_instance_valid(actor): return -1
	if actor.has_method("get_court_side"): return int(actor.get_court_side())
	return team_id(actor)
static func valid(actor) -> bool:
	return actor_id(actor) >= 0 and team_id(actor) in [0, 1] and court_side(actor) in [0, 1]
static func players(registry, fallback: Array = []) -> Array:
	var result: Array = registry.get_players() if is_instance_valid(registry) and registry.has_method("get_players") else fallback.duplicate()
	var seen: Dictionary = {}
	for actor in result:
		if not valid(actor) or seen.has(actor_id(actor)): return []
		seen[actor_id(actor)] = true
	result.sort_custom(func(a, b): return actor_id(a) < actor_id(b))
	return result
static func find_actor(registry, number: int, fallback: Array = []):
	for actor in players(registry, fallback):
		if actor_id(actor) == number: return actor
	return null
static func unique_team_actor(registry, team: int, fallback: Array = []):
	var found = null
	for actor in players(registry, fallback):
		if team_id(actor) != team: continue
		if found != null: return null
		found = actor
	return found
static func team_side(registry, team: int, fallback: Array = []) -> int:
	var side := -1
	for actor in players(registry, fallback):
		if team_id(actor) != team: continue
		if side >= 0 and court_side(actor) != side: return -1
		side = court_side(actor)
	return side
static func evidence_actor(evidence: Dictionary, registry, fallback: Array = []) -> int:
	if evidence.has("actor_id"):
		var actor = find_actor(registry, int(evidence.actor_id), fallback)
		if actor == null: return -1
		if evidence.has("team_id") and int(evidence.team_id) != team_id(actor): return -1
		if evidence.has("player_num") and int(evidence.player_num) != team_id(actor): return -1
		if evidence.has("court_side") and int(evidence.court_side) != court_side(actor): return -1
		return actor_id(actor)
	# Explicitly a legacy TEAM alias. Only a unique actor can be recovered.
	return actor_id(unique_team_actor(registry, int(evidence.get("player_num", -1)), fallback))
static func annotate(evidence: Dictionary, actor) -> Dictionary:
	evidence["actor_id"] = actor_id(actor)
	evidence["team_id"] = team_id(actor)
	evidence["court_side"] = court_side(actor)
	evidence["player_num"] = team_id(actor) # retained legacy team alias
	return evidence

static func earliest(first: Dictionary, next: Dictionary) -> Dictionary:
	## Exact equal normalized TOIs retain both physical observations. There is
	## no widened temporal tie epsilon and no roster-order rule permission.
	if not next.get("blocked", false): return first
	if not first.get("blocked", false): return next
	var a: float = first.get("fraction", 0.0)
	var b: float = next.get("fraction", 0.0)
	if b < a: return next
	if b > a: return first
	if first.get("ambiguous", false): return first
	if next.get("ambiguous", false): return next
	if int(first.get("actor_id", -1)) == int(next.get("actor_id", -1)): return first
	var contacts: Array = first.get("simultaneous_contacts", [first.duplicate(true)]).duplicate(true)
	contacts.append(next.duplicate(true))
	contacts.sort_custom(func(x, y): return int(x.actor_id) < int(y.actor_id))
	var result: Dictionary = contacts[0].duplicate(true)
	result["simultaneous_contacts"] = contacts
	if int(first.team_id) != int(next.team_id):
		result["ambiguous"] = true
		result["reason"] = "simultaneous_opposing_actor_contacts"
		return result
	for contact in contacts:
		if contact.get("kind", "body") not in ["legal_hand", "legal_paddle"]:
			result = contact.duplicate(true); result["simultaneous_contacts"] = contacts
			return result
	result["simultaneous_partner_contact"] = true
	return result
