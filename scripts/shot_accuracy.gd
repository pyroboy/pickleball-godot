extends RefCounted
## Game-tuning values, not measured professional-player statistics.
## Center-weighted bounded ellipse: uniform angle, uniform radius. E[r^2]=1/3.
## Pure geometry never consumes RNG; only accepted physical contacts sample.
const SOLVER_ALLOWANCE: float = 0.10
var rng: = RandomNumberGenerator.new()
var samples: int = 0

func _init() -> void:
	rng.randomize()

static func radii(charge: float, mode: int = 0, intent: String = "AUTO", serve: bool = false) -> Vector2:
	var power: float = clampf(charge, 0.0, 1.0)
	var axes: Vector2
	if intent == "DROP" and not serve:
		axes = Vector2(0.14, 0.20).lerp(Vector2(0.20, 0.28), power)
	elif serve:
		axes = Vector2(0.16, 0.22).lerp(Vector2(0.26, 0.34), power)
	else:
		axes = Vector2(0.20, 0.28).lerp(Vector2(0.34, 0.46), power)
	return axes * (1.06 if mode != 0 else 1.0)

static func display_radii(charge: float, mode: int = 0, intent: String = "AUTO", serve: bool = false) -> Vector2:
	# Homothetic enlargement encloses the ellipse plus a circular solver residual.
	var axes: Vector2 = radii(charge, mode, intent, serve)
	return axes * (1.0 + SOLVER_ALLOWANCE / minf(axes.x, axes.y))

func sample(target: Vector3, charge: float, mode: int = 0, intent: String = "AUTO", serve: bool = false) -> Dictionary:
	var axes: Vector2 = radii(charge, mode, intent, serve)
	var angle: float = rng.randf() * TAU
	var radius: float = rng.randf()
	var offset: = Vector3(cos(angle) * radius * axes.x, 0, sin(angle) * radius * axes.y)
	samples += 1
	return {"intended": target, "sampled": target + offset, "radii": axes, "sample_index": samples}

static func annotate(launch: Dictionary, accuracy: Dictionary) -> void:
	if launch.is_empty(): return
	launch["sampled_target"] = accuracy.sampled
	launch["target"] = accuracy.intended
	var profile: Dictionary = launch.profile.duplicate(true)
	profile["accuracy_intended_target"] = accuracy.intended
	profile["accuracy_sampled_target"] = accuracy.sampled
	profile["accuracy_radii"] = accuracy.radii
	profile["accuracy_sample_index"] = accuracy.sample_index
	profile["accuracy_solver_residual"] = launch.landing.distance_to(accuracy.sampled)
	profile["accuracy_region_reliable"] = bool(launch.get("feasible", false)) and float(profile.accuracy_solver_residual) <= SOLVER_ALLOWANCE
	launch.profile = profile
