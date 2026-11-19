"""Python copy of the ball model in scripts/ball.gd (flight + floor bounce), for the
proposal's charts. Constants are copied from ball.gd; keep them in step by hand.
Checked against tools/flight_tests.gd (the game's own predictor) on 2026-11-19."""
import math

MASS, R, G = 0.024, 0.0375, 9.8
RHO, CD, MAGNUS, AERO = 1.225, 0.47, 0.0003, 0.79
LINEAR_DAMP, ANGULAR_DAMP, MAX_SPEED, FLOOR = 0.1, 0.1, 20.0, 0.075 + 0.0375
SPIN_TRANSFER, SPIN_DECAY = 0.25, 0.7
DT = 1.0 / 30.0

def cor(v):
    t = min(1.0, max(0.0, (v - 3.0) / 15.0))
    return 0.78 + (0.56 - 0.78) * t

def step(p, v, top):
    """One tick, same order as Ball.predict_aero_step. 2D: p=(z, y), v=(vz, vy);
    top = topspin rad/s (negative = slice)."""
    vz, vy = v
    sp = math.hypot(vz, vy)
    if sp > 0.1:
        a = 0.5 * RHO * CD * math.pi * R * R * sp * sp / MASS * AERO
        vz -= vz / sp * a * DT; vy -= vy / sp * a * DT
    if abs(top) > 0.1 and sp > 0.5:
        # omega = (UP x travel) * top; in the flight plane omega x v = top * (vy, -vz)
        k = MAGNUS * top / MASS * AERO * DT
        vz, vy = vz + k * vy, vy - k * vz
    top *= math.exp(-DT * 0.693 / (150.0 * AERO))
    sp = math.hypot(vz, vy)
    if sp > MAX_SPEED: vz, vy = vz / sp * MAX_SPEED, vy / sp * MAX_SPEED
    damp = max(0.0, 1.0 - LINEAR_DAMP * DT); vz *= damp; vy *= damp
    top *= max(0.0, 1.0 - ANGULAR_DAMP * DT)
    vy -= G * DT
    z, y = p[0] + vz * DT, p[1] + vy * DT
    bounced = False
    if y < FLOOR and vy < 0:
        y = FLOOR
        surf = top * R                      # surface speed along travel from spin
        vz = vz - SPIN_TRANSFER * (vz - surf) * AERO
        top *= 1.0 + (SPIN_DECAY - 1.0) * AERO
        vy = abs(vy) * cor(abs(vy)); bounced = True
    return (z, y), (vz, vy), top, bounced

def fly(z0, y0, speed, angle_deg, top=0.0, bounces=1, tmax=6.0):
    p, v = (z0, y0), (speed * math.cos(math.radians(angle_deg)), speed * math.sin(math.radians(angle_deg)))
    pts, marks, t = [p], [], 0.0
    while t < tmax:
        p, v, top, b = step(p, v, top); t += DT; pts.append(p)
        if b:
            marks.append((p[0], t, v))
            if len(marks) > bounces: break
    return pts, marks

if __name__ == "__main__":
    # 1. Equipment drop test: 78 in (1.981 m) drop, rebound height (bottom of ball)
    p, v, peak, hit = (0.0, FLOOR + 1.981), (0.0, 0.0), 0.0, False
    for _ in range(200):
        p, v, _, b = step(p, v, 0.0)
        if b: hit = True
        if hit: peak = max(peak, p[1] - FLOOR)
    print("drop 78 in -> rebound %.3f m = %.1f in (spec 30-34 in)" % (peak, peak / 0.0254))
    # 2. Same launch, three spins
    for name, top in (("flat", 0), ("topspin 34", 34), ("slice -26", -26)):
        pts, m = fly(-6.7, 0.9, 14.0, 22.0, top, bounces=1)
        apex = max(q[1] for q in pts)
        (z1, t1, v1), (z2, t2, _) = m[0], m[1]
        print("%-11s lands %.2f m past net at %.2fs, apex %.2f, after bounce vz %.1f vy %.1f, 2nd bounce +%.2f m" % (name, z1, t1, apex, v1[0], v1[1], z2 - z1))
    # 3. Travel times at the speed cap
    for d, lab in ((4.27, "kitchen line to kitchen line"), (13.4, "baseline to baseline")):
        for s in (20.0,):
            p, v, t = (0.0, 1.0), (s * math.cos(0.12), s * math.sin(0.12)), 0.0
            while p[0] < d and t < 5: p, v, _, _ = step(p, v, 0.0); t += DT
            print("%s at %.0f m/s launch: %.2f s (speed on arrival %.1f)" % (lab, s, t, math.hypot(*v)))
    print("decel at 15 m/s: drag %.1f + damp %.1f m/s2; magnus at 34 rad/s: %.1f m/s2" % (
        0.5 * RHO * CD * math.pi * R * R * 225 / MASS * AERO, 1.5, MAGNUS * 34 * 15 / MASS * AERO))
