extends RefCounted


static var mobile_runtime: bool = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or OS.get_cmdline_user_args().has("--mobile-runtime")
static var developer_tools: bool = not mobile_runtime
## Benchmark harness flags (user args after "--"): --autoplay, --doubles, --seed=N
static var autoplay: bool = OS.get_cmdline_user_args().has("--autoplay")
static var bench_doubles: bool = OS.get_cmdline_user_args().has("--doubles")
static var bench_seed: int = _arg_int("--seed=", -1)
## --bench-human=N: team coordination treats actor N as the human partner (it is
## still AI-driven), so the bench can test how the AI partner shares the court.
static var bench_human: int = _arg_int("--bench-human=", -1)
## --pressure-team=N (bench only): team N plays every rally ball as a full-power
## drive, or a smash when high, to measure how the other team defends hard balls.
static var pressure_team: int = _arg_int("--pressure-team=", -1)
## --end-change-at=N (bench only): doubles teams change ends at N points instead of
## 6/8/11, so the change-ends sequence can be measured in a short run.
static var end_change_at: int = _arg_int("--end-change-at=", -1)

## --set=<key>=<value> (bench only): pins one setting for the run. Under --autoplay every
## "gameplay." setting comes from these or the defaults, never the saved file, so a bench
## cannot drift with what this Mac has saved (GAME_MECHANICS_PLAN step 0).
static func setting_override(key: String) -> Variant:
	var prefix: String = "--set=" + key + "="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return str_to_var(arg.trim_prefix(prefix))
	return null

## --stamina-pin=A:V[,A:V] (bench only): actor A's stamina stays at V (0 = exhausted,
## 100 = unlimited) while everyone else drains normally. Stamina experiments.
## --position-team=N (bench only): only team N uses the position rules (position read,
## smash bracing, deep reset); 9 = nobody. A/B test of positional play.
static var position_team: int = _arg_int("--position-team=", -1)
## --smart-team=N (bench only): only team N uses the stamina strategy; 9 = nobody.
static var smart_team: int = _arg_int("--smart-team=", -1)
static func stamina_strategy_for(team: int) -> bool:
	return smart_team < 0 or smart_team == team

static func position_rules_for(team: int) -> bool:
	return position_team < 0 or position_team == team

static func stamina_pins() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stamina-pin="):
			for part in arg.trim_prefix("--stamina-pin=").split(","):
				var kv: PackedStringArray = part.split(":")
				if kv.size() == 2: out[int(kv[0])] = clampf(float(kv[1]), 0.0, 100.0)
	return out

static func _arg_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return int(arg.trim_prefix(prefix))
	return fallback

## Seed an RNG deterministically under --seed, otherwise randomize.
static func seed_rng(rng: RandomNumberGenerator, salt: int) -> void:
	if bench_seed >= 0: rng.seed = hash([bench_seed, salt])
	else: rng.randomize()
