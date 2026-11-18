extends RefCounted
## Preferences only. No reaction, reach, speed, accuracy or collision constants.
const NAMES := ["All-Rounder", "Power Attacker", "Patient Dinker", "Counterpuncher", "Lob Tactician"]
const PROFILES := [
	{"weights": {}, "cover_depth": 0.0, "poach_tendency": 0.0, "placement_risk": 1.0},
	{"weights": {"DRIVE": 2.5, "SMASH": 2.8, "SPEED_UP": 2.0, "DINK": 0.55, "DROP": 0.7, "LOB": 0.3}, "cover_depth": -0.18, "poach_tendency": 0.15, "placement_risk": 1.0},
	{"weights": {"DINK": 2.8, "DROP": 2.6, "RESET": 2.3, "DRIVE": 0.45, "SMASH": 0.55, "SPEED_UP": 0.45, "LOB": 0.6}, "cover_depth": -0.1, "poach_tendency": -0.1, "placement_risk": 0.82},
	{"weights": {"DINK": 1.6, "DROP": 1.9, "RESET": 2.8, "DRIVE": 0.65, "SMASH": 1.1, "SPEED_UP": 1.2, "LOB": 0.35}, "cover_depth": 0.18, "poach_tendency": -0.05, "placement_risk": 0.9},
	{"weights": {"DINK": 1.1, "DROP": 1.3, "DRIVE": 0.8, "SMASH": 0.8, "SPEED_UP": 0.6, "LOB": 3.5}, "cover_depth": 0.12, "poach_tendency": -0.1, "placement_risk": 0.88}
]
const SETTINGS := {1: "gameplay.ai_style_opponent_one", 2: "gameplay.ai_style_partner", 3: "gameplay.ai_style_opponent_two"}
static func valid_id(value: Variant) -> int:
	return value if typeof(value) == TYPE_INT and value >= 0 and value < NAMES.size() else 0
static func profile(value: Variant) -> Dictionary:
	return PROFILES[valid_id(value)].duplicate(true)
static func actor_seed(match_seed: int, actor_id: int) -> int:
	# Stable private streams; consuming actor 1's stream cannot move actor 3's.
	return ((match_seed & 0x7fffffff) * 1103515245 + (actor_id + 1) * 2654435761 + 12345) & 0x7fffffffffffffff
static func reweight(base: Dictionary, style: int) -> Dictionary:
	var weights: Dictionary = PROFILES[valid_id(style)].weights
	var out: Dictionary = {}; var total: float = 0.0
	for kind in base:
		var value: float = float(base[kind]) * float(weights.get(kind, 1.0))
		if value > 0.0: out[kind] = value; total += value
	if total <= 0.0: return {}
	for kind in out: out[kind] /= total
	# A lob specialist still varies play; never add a lob to an ineligible feed.
	if out.size() > 1 and float(out.get("LOB", 0.0)) > 0.30:
		var other: float = 1.0 - float(out.LOB)
		for kind in out:
			if kind != "LOB": out[kind] *= 0.70 / other
		out.LOB = 0.30
	return out
