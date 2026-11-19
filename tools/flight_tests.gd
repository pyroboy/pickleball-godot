extends SceneTree
## Headless fixed-flight tests for the ball model (static predictors in scripts/ball.gd).
## They pin today's flight and bounce numbers, so a change to drag, spin, bounce or the
## tick rate shows up here before it shows up in play. Golden values were recorded on
## 2026-11-19 at 30 Hz; change them only on purpose (Gameplay v2), never to make a test pass.
## This checks the predictor the shot solvers use, not the live rigid body: the seeded
## bench (tools/bench.sh) covers that.
## Run: godot --headless --path . -s tools/flight_tests.gd   (add `-- --print` to list values)

const FLOOR := 0.075 + 0.0375
const TOL := 0.01

var _fails := 0
var _checks := 0
var _print := false
var Ball

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond: _fails += 1
	print("PASS  " if cond else "FAIL  ", label)

func _near(value: float, golden: float, label: String, tol: float = TOL) -> void:
	if _print: print("VALUE %s = %.4f" % [label, value])
	_check(absf(value - golden) <= tol, "%s: %.3f (expected %.3f)" % [label, value, golden])

## Fly until the second floor contact. Returns landing point, apex, speeds after the bounce.
func _fly(pos: Vector3, vel: Vector3, omega: Vector3) -> Dictionary:
	var gravity: float = Ball.get_effective_gravity()
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var out := {"apex": pos.y, "time": 0.0}
	var bounces := 0
	for step in 600:
		var next: Array = Ball.predict_aero_step(pos, vel, omega, gravity, dt)
		pos = next[0]; vel = next[1]; omega = next[2]
		out.apex = maxf(out.apex, pos.y)
		if pos.y < FLOOR and vel.y < 0.0:
			pos.y = FLOOR
			var bounced: Array = Ball.predict_bounce_spin(vel, omega)
			vel = bounced[0]; omega = bounced[1]
			bounces += 1
			if bounces == 1:
				out.land = pos; out.time = (step + 1) * dt; out.after = vel; out.rebound_apex = FLOOR
			else:
				out.second = pos
				break
		if bounces == 1: out.rebound_apex = maxf(out.rebound_apex, pos.y)
	return out

func _launch(speed: float, angle_deg: float, topspin: float) -> Dictionary:
	# From the +z baseline toward -z, as team 0 hits. Topspin axis as in shot_profile.gd.
	var a := deg_to_rad(angle_deg)
	var vel := Vector3(0.0, speed * sin(a), -speed * cos(a))
	var axis := Vector3.UP.cross(Vector3(0, 0, -1))
	return _fly(Vector3(0.0, 0.9, 6.7), vel, axis * topspin)

func _initialize() -> void:
	_print = "--print" in OS.get_cmdline_user_args()
	Ball = load("res://scripts/ball.gd")
	_check(Engine.physics_ticks_per_second == 30, "physics runs at 30 Hz (golden values assume it)")

	# Bounce curve.
	_near(Ball.cor_for_impact_speed(1.0), 0.78, "bounce keeps 0.78 of a soft impact", 0.0001)
	_near(Ball.cor_for_impact_speed(10.5), 0.67, "bounce keeps 0.67 at 10.5 m/s", 0.0001)
	_near(Ball.cor_for_impact_speed(25.0), 0.56, "bounce keeps 0.56 of a hard impact", 0.0001)

	# Equipment drop test: 78 inches onto the court must rebound 30 to 34 inches.
	var drop := _fly(Vector3(0, FLOOR + 78.0 * 0.0254, 0), Vector3.ZERO, Vector3.ZERO)
	var rebound_in: float = (drop.rebound_apex - FLOOR) / 0.0254
	_check(rebound_in >= 30.0 and rebound_in <= 34.0, "78 inch drop rebounds %.1f inches (rule: 30 to 34)" % rebound_in)
	_near(rebound_in, GOLD.drop_in, "drop rebound, inches", 0.2)

	# Same launch, three spins: 14 m/s at 22 degrees from the baseline.
	var flat := _launch(14.0, 22.0, 0.0)
	var top := _launch(14.0, 22.0, 34.0)
	var slice := _launch(14.0, 22.0, -26.0)
	_near(-flat.land.z, GOLD.flat_land, "flat: lands past the net, m")
	_near(flat.apex, GOLD.flat_apex, "flat: peak height, m")
	_near(flat.time, GOLD.flat_time, "flat: flight time, s", 0.001)
	_near(-flat.after.z, GOLD.flat_after, "flat: forward speed after bounce, m/s")
	_near(-top.land.z, GOLD.top_land, "topspin: lands past the net, m")
	_near(top.apex, GOLD.top_apex, "topspin: peak height, m")
	_near(-top.after.z, GOLD.top_after, "topspin: forward speed after bounce, m/s")
	_near(-slice.land.z, GOLD.slice_land, "slice: lands past the net, m")
	_near(slice.apex, GOLD.slice_apex, "slice: peak height, m")
	_near(-slice.after.z, GOLD.slice_after, "slice: forward speed after bounce, m/s")
	_check(-top.land.z < -flat.land.z and -flat.land.z < -slice.land.z, "topspin lands shortest, slice longest")
	_check(-top.after.z > -flat.after.z and -flat.after.z > -slice.after.z, "topspin kicks forward, slice sits up")
	_check(absf(flat.land.x) < 0.0001 and absf(top.land.x) < 0.0001, "no sideways drift without sidespin")

	# Sidespin curves the ball; the sign is fixed so serves keep curving the same way.
	var side := _fly(Vector3(0.0, 0.9, 6.7), Vector3(0, 14.0 * sin(deg_to_rad(22.0)), -14.0 * cos(deg_to_rad(22.0))), Vector3.UP * 18.0)
	_near(side.land.x, GOLD.side_x, "sidespin 18 rad/s: sideways curve at landing, m")

	# Speed cap.
	_check(Ball.predict_aero_step(Vector3(0, 2, 0), Vector3(0, 0, -30), Vector3.ZERO, 9.8, 1.0 / 30.0)[1].length() <= Ball.MAX_SPEED,
		"one step clamps any speed to the %d m/s cap" % int(Ball.MAX_SPEED))

	# The batch predictor (used by solvers) must match stepping one tick at a time.
	var gravity: float = Ball.get_effective_gravity()
	var p := Vector3(0.3, 1.1, 5.0); var v := Vector3(1.5, 4.0, -12.0); var w := Vector3(20, 3, -5)
	var batch: Array = Ball.predict_aero_steps(p, v, w, gravity, 1.0 / 30.0, 12)
	for i in 12:
		var one: Array = Ball.predict_aero_step(p, v, w, gravity, 1.0 / 30.0)
		p = one[0]; v = one[1]; w = one[2]
	_check(p.distance_to(batch[0]) < 0.00001 and v.distance_to(batch[1]) < 0.00001 and w.distance_to(batch[2]) < 0.00001,
		"batch predictor equals 12 single steps")

	print("\nflight tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)

const GOLD := {
	"drop_in": 33.57,
	"flat_land": 3.808, "flat_apex": 1.951, "flat_time": 1.1, "flat_after": 5.805,
	"top_land": 1.856, "top_apex": 1.663, "top_after": 6.604,
	"slice_land": 5.675, "slice_apex": 2.311, "slice_after": 5.170,
	"side_x": -0.925,
}
