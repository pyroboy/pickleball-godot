extends RefCounted


static var mobile_runtime: bool = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or OS.get_cmdline_user_args().has("--mobile-runtime")
static var developer_tools: bool = not mobile_runtime
## Benchmark harness flags (user args after "--"): --autoplay, --doubles, --seed=N
static var autoplay: bool = OS.get_cmdline_user_args().has("--autoplay")
static var bench_doubles: bool = OS.get_cmdline_user_args().has("--doubles")
static var bench_seed: int = _arg_int("--seed=", -1)

static func _arg_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return int(arg.trim_prefix(prefix))
	return fallback

## Seed an RNG deterministically under --seed, otherwise randomize.
static func seed_rng(rng: RandomNumberGenerator, salt: int) -> void:
	if bench_seed >= 0: rng.seed = hash([bench_seed, salt])
	else: rng.randomize()
