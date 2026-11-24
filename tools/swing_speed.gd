extends SceneTree
## Paddle-head speed through every stroke's strike and follow-through, timed the way the game
## plays them: the AI strike through the stroke's speed ramp (player_ai_brain.gd
## _strike_progress), the human strike linear unless the stroke has a ramp
## (human_swing_playback.gd), the follow-through through stroke_swing_path.gd
## release_progress. Head positions come from the pose fields (stroke_swing_path.gd
## paddle_head, canonical frame), so this measures the authored swing, not charge or the live
## contact tracking. Data only: nothing is played, nothing is written.
## Key number: speed at contact / peak speed. A swing that hits through the ball peaks at
## contact (ratio near 1) and does not dip around it.
## Run: godot --headless --path . -s tools/swing_speed.gd [-- --fps=60 --profile=00]

# Loaded at runtime: these scripts need the game's autoloads (PerfMonitor), which exist only
# once the tree runs.
var Path
var Ramp
var Clock

var _fps := 60.0
var _profile := ""

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	Path = load("res://scripts/stroke_swing_path.gd")
	Ramp = load("res://scripts/stroke_speed_ramp.gd")
	Clock = load("res://scripts/stroke_playback_clock.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps="): _fps = float(arg.trim_prefix("--fps="))
		if arg.begins_with("--profile="): _profile = arg.trim_prefix("--profile=")
	var files: Array = []
	for f in DirAccess.get_files_at("res://data/postures"):
		if f.ends_with(".tres"): files.append(f)
	files.sort()
	print("pose                       | who   | peak m/s | at contact | contact/peak | dip around contact")
	for f in files:
		var def = load("res://data/postures/" + f)
		if def == null or int(def.posture_id) == 20: continue
		for who in ["ai", "human"]:
			var r := _measure(def, who == "human")
			print("%-26s | %-5s | %8.2f | %10.2f | %12.2f | %.2f" % [f.get_basename(), who, r.peak, r.contact, r.contact / maxf(r.peak, 0.001), r.dip / maxf(r.peak, 0.001)])
			if _profile != "" and f.begins_with(_profile):
				print("    speeds: ", r.speeds)
	quit()

func _measure(def, human: bool) -> Dictionary:
	var dt := 1.0 / _fps
	var ts: float = Clock.strike_duration(def)
	var tf: float = Clock.sweep_duration(def)
	var heads: Array = []
	var n_s := int(ceil(ts / dt))
	var n_f := int(ceil(tf / dt))
	for i in n_s + 1:
		var x: float = minf(i * dt / ts, 1.0)
		var p: float = 0.5 * (Ramp.normalized(def, Ramp.STRIKE, x, human))
		heads.append(Path.paddle_head(Path.sample(def, p)))
	for i in range(1, n_f + 1):
		var x: float = minf(i * dt / tf, 1.0)
		heads.append(Path.paddle_head(Path.sample(def, Path.release_progress(def, 1, x))))
	var speeds: Array = []
	for i in range(1, heads.size()):
		speeds.append(snappedf((heads[i] - heads[i - 1]).length() / dt, 0.01))
	var peak: float = 0.0
	for s in speeds: peak = maxf(peak, s)
	# Frame n_s - 1 ends at contact; frame n_s leaves it.
	var into: float = speeds[n_s - 1]
	var out: float = speeds[n_s] if n_s < speeds.size() else 0.0
	var dip: float = INF
	for k in range(maxi(n_s - 2, 0), mini(n_s + 2, speeds.size())): dip = minf(dip, speeds[k])
	return {"peak": peak, "contact": (into + out) * 0.5, "dip": dip, "speeds": speeds}
