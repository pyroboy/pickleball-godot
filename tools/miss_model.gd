extends SceneTree
## Size the large-miss rule (GAME_MECHANICS_PLAN change 3) in seconds, before a bench.
## Replays every rally launch in bench logs (ai_launch origin + velocity, with the contact
## pressure from the execution note that follows) through the flight predictor: for each
## launch, the large-miss chance from shot_execution_error at that pressure, and where a
## missed ball goes (net / out / still in) over DRAWS draws of the miss direction.
## Usage: godot --headless --path . -s tools/miss_model.gd -- logs/bench_x_s1.perf.jsonl [...]
##   Optional: --line=0.25 --at-line=0.04 --max=0.22 --pitch=7 --yaw=6 --speed=0.12 (override tuning)
var Flight
var Tuning
const DRAWS := 64

func _initialize() -> void:
	Flight = load("res://scripts/ball_flight_predictor.gd")
	Tuning = load("res://scripts/gameplay_tuning.gd")
	var paths: Array = []
	var o := {"line": Tuning.FORCED_LINE, "at-line": Tuning.MISS_CHANCE_AT_LINE, "max": Tuning.MISS_CHANCE_MAX,
		"pitch": Tuning.MISS_PITCH_DEG, "yaw": Tuning.MISS_YAW_DEG, "speed": Tuning.MISS_SPEED_FRACTION}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv: PackedStringArray = a.trim_prefix("--").split("=")
			o[kv[0]] = float(kv[1])
		else: paths.append(a)
	var by_kind: Dictionary = {}   # kind -> [shots, expected misses, expected net, expected out]
	var shots := 0
	var points := 0
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null: continue
		var pending: Dictionary = {}   # actor -> launch
		while not f.eof_reached():
			var line := f.get_line()
			if line.is_empty(): continue
			var r = JSON.parse_string(line)
			if typeof(r) != TYPE_DICTIONARY: continue
			if r.get("kind") == "note" and r.get("note") == "point_ending": points += 1
			if r.get("kind") != "note": continue
			var d: Dictionary = r.get("data", {})
			if r.note == "ai_launch": pending[int(d.actor)] = d
			elif r.note == "execution" and not bool(d.get("serve", false)) and pending.has(int(d.actor)):
				var L: Dictionary = pending[int(d.actor)]; pending.erase(int(d.actor))
				var pressure: float = float(d.get("pressure", 0.0))
				var chance := 0.0
				if pressure >= o.line:
					chance = lerpf(o["at-line"], o["max"], clampf((pressure - o.line) / (1.0 - o.line), 0.0, 1.0))
				var row: Array = by_kind.get(L.kind, [0, 0.0, 0.0, 0.0])
				row[0] += 1; shots += 1
				if chance > 0.0:
					var origin := Vector3(L.origin[0], L.origin[1], L.origin[2])
					var vel := Vector3(L.vel[0], L.vel[1], L.vel[2])
					var team: int = 0 if vel.z < 0.0 else 1
					var direction: float = -1.0 if team == 0 else 1.0
					var nets := 0; var outs := 0
					for k in DRAWS:
						var u: float = (k + 0.5) / DRAWS
						var down: bool = u < 0.55
						var side: float = 1.0 if fposmod(u * 7.0, 1.0) < 0.5 else -1.0
						var horizontal := Vector3(vel.x, 0.0, vel.z)
						var axis: Vector3 = horizontal.normalized().cross(Vector3.UP)
						var b := Basis(Vector3.UP, deg_to_rad(side * o.yaw * fposmod(u * 3.0, 1.0))) * Basis(axis, deg_to_rad((-1.0 if down else 1.0) * o.pitch))
						var v2: Vector3 = b * vel * (1.0 + (-1.0 if down else 1.0) * o.speed)
						var fl: Dictionary = Flight.trace(origin, v2, Vector3.ZERO, 3.0, 1, false)
						var land: Vector3 = fl.first_bounce
						if fl.net_hit or fl.net_crossing.is_empty(): nets += 1
						elif absf(land.x) > 3.05 or land.z * direction > 6.7 or land.z * direction < 0.0: outs += 1
					row[1] += chance
					row[2] += chance * nets / DRAWS
					row[3] += chance * outs / DRAWS
				by_kind[L.kind] = row
	print("miss model: %d rally launches, %d points in the logs; line %.2f, chance %.2f..%.2f, pitch %.1f yaw %.1f" % [shots, points, o.line, o["at-line"], o.max, o.pitch, o.yaw])
	var tot := [0, 0.0, 0.0, 0.0]
	for kind in by_kind:
		var r: Array = by_kind[kind]
		for i in 4: tot[i] += r[i]
		print("  %-8s n=%4d  large misses %5.1f  -> net %5.1f  out %5.1f  (per 100 shots: %.1f net+out)" % [kind, r[0], r[1], r[2], r[3], 100.0 * (r[2] + r[3]) / maxf(1, r[0])])
	print("  all      n=%4d  large misses %5.1f  -> net %5.1f  out %5.1f  (per 100 shots: %.1f net+out)" % [tot[0], tot[1], tot[2], tot[3], 100.0 * (tot[2] + tot[3]) / maxf(1, tot[0])])
	quit()
