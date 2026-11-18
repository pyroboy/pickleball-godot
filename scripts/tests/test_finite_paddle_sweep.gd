extends SceneTree

const D = preload("res://scripts/paddle_dimensions.gd")
const F = preload("res://scripts/finite_paddle_contact.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const R: = 0.0375
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
var timing: Array = []
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func around_head(angle: float) -> Transform3D:
	var basis: = Basis(Vector3.RIGHT, angle)
	return Transform3D(basis, D.HEAD_OFFSET - basis * D.HEAD_OFFSET)
func sweep(label: String, a: Vector3, b: Vector3, p: Transform3D, q: Transform3D, expected: bool, clip: float = 1.0, entry: float = -1.0) -> void :
	var f: float = F.first_sweep_fraction(a, b, p, q, R, clip)
	check((f >= 0.0) == expected, label + " detection")
	if f >= 0.0:
		check(f <= clip and f >= 0.0, label + " time window")
		var actual: Transform3D = F.interpolate_head_transform(p, q, f)
		check(F.touches(actual, a.lerp(b, f), R), label + " returned fraction must touch actual finite head")
		if entry >= 0.0: check(absf(f - entry) < 0.001, label + " first entry error")
	rows.append({"label": label, "fraction": f, "clip": clip})
func _initialize(): call_deferred("run")
func run() -> void :
	var t: = Transform3D.IDENTITY
	var y: float = D.HEAD_CENTER_Y
	sweep("co-moving face", Vector3(0, y, 0.06), Vector3(0, y, 0.1), t, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.06)), true, 1.0, 0.497932739)
	sweep("oblique face", Vector3( - 0.05, y, 0.055), Vector3(0.05, y, 0.035), t, t, true, 1.0, 0.247932739)
	sweep("endpoints separated pass-through", Vector3( - 0.2, y, 0.055), Vector3(0.2, y, 0.035), t, t, true, 1.0, 0.254)
	sweep("tiny inward", Vector3(0, 0.461073578616, 0.010403640866), Vector3(0, 0.461043627685, 0.010401925709), t, t, true)
	sweep("axial crossing", Vector3(0, y, 0.06), Vector3(0, y, - 0.06), t, t, true, 1.0, 0.08298879)
	sweep("expired before entry", Vector3(0, y, 0.06), Vector3(0, y, - 0.06), t, t, false, 0.05)
	sweep("clipped after entry", Vector3(0, y, 0.06), Vector3(0, y, - 0.06), t, t, true, 0.1, 0.08298879)
	var fixed: = Vector3(0, y, 0.11)
	sweep("rotation only", fixed, fixed, around_head(0), around_head(PI), true, 1.0, 0.349668)
	sweep("rotation clipped before", fixed, fixed, around_head(0), around_head(PI), false, 0.34)
	sweep("rotation clipped after", fixed, fixed, around_head(0), around_head(PI), true, 0.36, 0.349668)
	sweep("shortest wrap", fixed, fixed, around_head(deg_to_rad(179)), around_head(deg_to_rad(-179)), false)
	sweep("remote", Vector3(1, y, -1), Vector3(1, y, 1), t, t, false)
	sweep("handle-only crossing", Vector3(0, 0.055, - 0.08), Vector3(0, 0.055, 0.08), t, t, false)
	var observed: = Vector3(0.006319, 0.130699, - 0.052816)
	sweep("observed handle first", observed, observed, t, t, false)
	for offset in [ - 0.1, 0.1]:
		var face: = Vector3(0, y + offset, 0.0445)
		sweep("off-center broad face %s" % offset, face, face, t, t, true)

	var threshold: = Vector3(0.136630249863, 0.33730690505, 0.008)
	check(absf(G.distance_to_head_shape(threshold) - R - G.contact_surface_tolerance()) < 1e-07, "midfacet physical threshold")
	check( not F.touches(t, threshold + Vector3(1e-05, 0, 0), R), "outward from physical5mm boundary rejects")
	check(F.MAX_SWEEP_QUERIES <= 40, "bounded mobile query count")
	if OS.get_cmdline_user_args().has("--timing"): measure_timing()
	var file = FileAccess.open("/tmp/finite-paddle-sweep.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows, "host_timing": timing}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("FINITE PADDLE SWEEP: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func measure_timing() -> void :
	var identity: = Transform3D.IDENTITY
	var y: float = D.HEAD_CENTER_Y
	var cases: Array = [
		["fast pass-through", Vector3( - 0.2, y, 0.055), Vector3(0.2, y, 0.035), identity, identity], 
		["rotating", Vector3(0, y, 0.11), Vector3(0, y, 0.11), around_head(0), around_head(PI)], 
		["closest candidate max-work", Vector3( - 0.31, 0.461131345216, 0), Vector3(0.29, 0.461131345216, 0), identity, identity], 
		["remote rejected", Vector3(1, y, -1), Vector3(1, y, 1), identity, identity], 
		["handle rejected", Vector3(0, 0.055, - 0.08), Vector3(0, 0.055, 0.08), identity, identity]]
	for item in cases:
		for warm in 100: F.first_sweep_fraction(item[1], item[2], item[3], item[4], R)
		var samples: Array[int] = []
		var total: = 0
		for trial in 400:
			var start: int = Time.get_ticks_usec()
			F.first_sweep_fraction(item[1], item[2], item[3], item[4], R)
			var cost: int = Time.get_ticks_usec() - start
			samples.append(cost);total += cost
		samples.sort()
		timing.append({"case": item[0], "warmup": 100, "samples": 400, "mean_usec": float(total) / 400.0, "p95_usec": samples[379], "max_usec": samples[-1], "scope": "isolated host micro-cost, not phone frame time"})
	print("FINITE SWEEP HOST TIMING ", JSON.stringify(timing))
