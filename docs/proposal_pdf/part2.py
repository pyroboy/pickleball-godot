"""Part 2 of the proposal PDF: physics and mechanics (pages 32 onward).
Usage: python part2.py out.pdf   (build.sh appends the result to the original 31 pages)
Figures come from the code on branch visual-pass (19 Nov 2026) and from ball_model.py."""
import sys
from reportlab.pdfgen import canvas
from style import *
import ball_model as bm

FIRST_PAGE = 32
page = [FIRST_PAGE - 1]
PINK = HexColor("#e87ba4")
WHITE = HexColor("#ffffff")

def head(c, kicker, title, dark=False):
    page[0] += 1
    bg(c, NIGHT if dark else BG)
    c.setFillColor(ORANGE); c.rect(M, H - 38, 26, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.5); c.setFillColor(ORANGE)
    c.drawString(M + 34, H - 40, kicker.upper())
    c.setFont("Helvetica-Bold", 25); c.setFillColor(HexColor("#f4f1ea") if dark else INK)
    c.drawString(M, H - 70, title)
    foot(c)

def foot(c):
    c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
    c.drawRightString(W - M, 22, "Pickleball 2.5D  ·  part 2: physics & mechanics  ·  %d" % page[0])

def label(c, x, y, text, color=MUTED, size=8.5, bold=True):
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size); c.setFillColor(color); c.drawString(x, y, text)

def note(c, text, y=40):
    para(c, text, M, y + 9, W - 2 * M, P(8.8, MUTED))

def rows(c, x, ytop, items, wk, wv, size=9.6, gap=6):
    """Two-column fact list: bold key, value paragraph. Returns the y below it."""
    y = ytop
    for k, v in items:
        c.setFont("Helvetica-Bold", size); c.setFillColor(INK); c.drawString(x, y - size, k)
        h = para(c, v, x + wk, y, wv, P(size, SUB))
        y -= max(h, size * 1.38) + gap
        c.setStrokeColor(LINE); c.setLineWidth(0.6); c.line(x, y + gap / 2, x + wk + wv, y + gap / 2)
    return y

c = canvas.Canvas(sys.argv[1], pagesize=(W, H))
c.setTitle("Pickleball 2.5D - Part 2: Physics and mechanics")

# ---- 32. Divider
page[0] += 1
bg(c, NIGHT)
c.setFillColor(ORANGE); c.rect(M, 400, 30, 4, stroke=0, fill=1)
c.setFont("Helvetica-Bold", 10); c.drawString(M + 40, 398, "PART 2  ·  ADDED 19 NOVEMBER 2026")
c.setFont("Helvetica-Bold", 40); c.setFillColor(HexColor("#f6f2ea")); c.drawString(M, 340, "Physics and mechanics")
c.setFont("Helvetica", 21); c.setFillColor(HexColor("#cfc8e6"))
c.drawString(M, 306, "What the game simulates today,")
c.drawString(M, 280, "where it stops, and a plan for Gameplay v2")
para(c, "Part 1 kept gameplay locked and changed only the look. This part opens the box: how the ball flies and "
        "bounces, how a hit is decided, which shots, rules and AI behaviours exist, and what to build next. "
        "Nothing here changes the lock on the visual update. It is the plan for after it.",
     M, 240, 430, P(11.5, HexColor("#d9d4ea")))
for i, (k, v, col) in enumerate((("Ball model", "Gravity, air drag, spin lift, spin-aware bounce", BLUE),
                                 ("Hits", "Solved to a target, then perturbed by contact quality", ORANGE),
                                 ("Biggest gap", "The paddle does not strike the ball; skill shows only as error", AQUA))):
    x = 540 + 0 * i; y = 330 - i * 96
    c.setFillColor(NIGHT2); c.roundRect(x, y, 372, 80, 8, stroke=0, fill=1)
    c.setFillColor(col); c.roundRect(x, y, 5, 80, 2, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9); c.setFillColor(col); c.drawString(x + 22, y + 56, k.upper())
    para(c, v, x + 22, y + 46, 330, P(13, HexColor("#f4f1ea"), font="Helvetica-Bold"))
c.setFont("Helvetica", 9); c.setFillColor(HexColor("#9c95b8"))
c.drawString(M, 70, "Numbers are read from the code on branch visual-pass. Flight figures match the game's own flight predictor (tools/flight_tests.gd).")
foot(c)
c.showPage()

# ---- 33. Status
head(c, "Status · 19 November", "Where the project stands since Part 1")
phases = [("0", "Performance baseline", "In progress", YELLOW, "Monitor, bench and 30 Hz physics done. iPhone baseline still open."),
          ("1", "Pixel-card players", "Prototype done", AQUA, "Cards on the real skeleton, on by default. Settings toggle and far-court tier open."),
          ("2", "Pixel viewport and camera", "Next", BLUE, "1/3-resolution 3D view with nearest upscale. Not started."),
          ("3", "Art pass", "Later", MUTED, "Hand-painted cards, palette swaps, six player profiles."),
          ("4", "Effects and feel", "Started", YELLOW, "Wrist lag on every swing is in and being tuned by eye."),
          ("5", "UI", "Later", MUTED, "Pixel UI kit, score pill, controls restyle."),
          ("6", "Ship, retire classic bodies", "Later", MUTED, "Only after gameplay stops reading body meshes.")]
box(c, M, 60, 430, 390)
label(c, M + 18, 428, "VISUAL UPDATE, BY PHASE")
for i, (n, t, st, col, d) in enumerate(phases):
    y = 388 - i * 49
    c.setFillColor(col); c.circle(M + 30, y + 10, 10, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10); c.setFillColor(WHITE); c.drawCentredString(M + 30, y + 6.5, n)
    c.setFont("Helvetica-Bold", 10.8); c.setFillColor(INK); c.drawString(M + 50, y + 12, t)
    tw = c.stringWidth(t, "Helvetica-Bold", 10.8)
    tag(c, M + 58 + tw, y + 8, st, col, size=7.2)
    para(c, d, M + 50, y + 5, 360, P(8.8, SUB))
x2 = M + 448; w2 = W - M - x2
box(c, x2, 200, w2, 250)
label(c, x2 + 18, 428, "AI RALLY QUALITY: POINT ENDINGS PER 100 SHOTS (LOWER IS BETTER)")
steps = [("Baseline", 20.3), ("Low paddle turn earlier", 17.6), ("Legs pass own ball", 16.3), ("Meet bounce higher", 14.9),
         ("Reset placement", 17.4), ("Prefer spare run", 14.3), ("Early turn, every pose", 11.8)]
for i, (n, v) in enumerate(steps):
    y = 398 - i * 26
    c.setFont("Helvetica", 9.2); c.setFillColor(INK); c.drawRightString(x2 + 150, y + 4, n)
    wv = 200 * v / 20.3
    c.setFillColor(ORANGE if i == len(steps) - 1 else BLUE); c.roundRect(x2 + 158, y, wv, 15, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.2); c.setFillColor(INK); c.drawString(x2 + 164 + wv, y + 4, "%.1f" % v)
para(c, "All-AI doubles, same 6 seeds at 300 s each, one change per step. Rally length went from 4.9 to 8.4 shots per point.",
     x2 + 18, 226, w2 - 36, P(8.6, MUTED))
box(c, x2, 60, w2, 126, HexColor("#eefaf4"), HexColor("#bfe8d3"))
label(c, x2 + 18, 164, "WHY THIS MATTERS FOR PART 2", AQUA, 9.5)
para(c, "The visual lock held for the look, but gameplay has already moved: the physics tick is now 30 Hz, and AI "
        "contact timing was retuned against the bench. The bench and its shot report are the tool that makes a "
        "deliberate Gameplay v2 possible, so Part 2 plans around them.", x2 + 18, 156, w2 - 36, P(9.6, SUB))
c.showPage()

# ---- 34. Ball flight
head(c, "Physics · flight", "Ball flight: gravity, drag and spin are all simulated")
box(c, M, 60, 372, 390)
label(c, M + 18, 428, "THE MODEL (scripts/ball.gd)")
rows(c, M + 18, 414, [
    ("Body", "A physics rigid body, 24 g, 75 mm across. Both sit inside the official ball range."),
    ("Gravity", "9.8 m/s², applied by the engine."),
    ("Air drag", "Grows with speed squared (drag coefficient 0.47), plus a small linear damping. "
                 "At 15 m/s the ball loses about 11 m/s every second."),
    ("Spin lift", "A sideways force from spin x velocity. Full topspin at 15 m/s pushes the ball down at "
                  "about 5 m/s², half of gravity again."),
    ("Spin state", "A full 3D spin vector, so topspin, slice and sidespin can all exist. Spin barely "
                   "fades in the air."),
    ("Limits", "Speed is clamped to 20 m/s (45 mph) every tick. Height is clamped at 5 m."),
    ("Tick", "30 steps per second, drawn smoothly between steps."),
    ("Not modelled", "Wind, indoor and outdoor balls, drag that changes with spin, ball wear."),
], 74, 262, 9.3, 7)
# chart: same launch, three spins
cx0, cy0, cw_, ch_ = M + 390, 200, W - M - (M + 390), 250
box(c, cx0, cy0, cw_, ch_)
label(c, cx0 + 18, 428, "SAME LAUNCH, THREE SPINS  (14 m/s, 22° up, from the baseline at 0.9 m)")
sx = (cw_ - 60) / 14.6; sy = sx * 1.6
gx = cx0 + 30; gy = cy0 + 46
def X(z): return gx + (z + 6.7) * sx
def Y(h): return gy + (h - bm.FLOOR) * sy
c.setFillColor(HexColor("#e8f0f8")); c.rect(X(-6.7), gy - 8, 13.4 * sx, 8, stroke=0, fill=1)
c.setFillColor(HexColor("#cfe0f1")); c.rect(X(-2.134), gy - 8, 4.268 * sx, 8, stroke=0, fill=1)
c.setStrokeColor(SUB); c.setLineWidth(1); c.line(X(-6.7) - 6, gy, X(7.9), gy)
c.setStrokeColor(INK); c.setLineWidth(2); c.line(X(0), gy, X(0), gy + 0.864 * sy)
c.setFont("Helvetica", 7.8); c.setFillColor(MUTED)
c.drawCentredString(X(0), gy - 20, "net"); c.drawCentredString(X(-6.7), gy - 20, "baseline")
c.drawCentredString(X(6.7), gy - 20, "baseline"); c.drawCentredString(X(2.134), gy - 20, "kitchen"); c.drawCentredString(X(-2.134), gy - 20, "kitchen")
for hh in (1.0,):
    c.setStrokeColor(LINE); c.setDash(2, 3); c.line(X(-6.7), gy + hh * sy, X(7.9), gy + hh * sy); c.setDash()
    c.drawString(X(7.9) - 22, gy + hh * sy + 3, "1 m")
results = []
for name, top, col in (("Slice", -26, VIOLET), ("Flat", 0, BLUE), ("Topspin", 34, ORANGE)):
    pts, marks = bm.fly(-6.7, 0.9, 14.0, 22.0, top, bounces=1)
    pts = [q for q in pts if q[0] <= 7.9]
    pth = c.beginPath(); pth.moveTo(X(pts[0][0]), Y(pts[0][1]))
    for q in pts[1:]: pth.lineTo(X(q[0]), Y(q[1]))
    c.setStrokeColor(col); c.setLineWidth(2); c.drawPath(pth, stroke=1, fill=0)
    c.setFillColor(col); c.circle(X(marks[0][0]), gy, 3.2, stroke=0, fill=1)
    results.append((name, col, marks[0][0], marks[0][2][0], max(q[1] for q in pts)))
lx = cx0 + 18
for name, col, land, vz, apex in results:
    c.setFillColor(col); c.roundRect(lx, cy0 + 220 - 26, 10, 10, 2, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9); c.setFillColor(INK); c.drawString(lx + 15, cy0 + 196, name)
    lx += 78
c.setFont("Helvetica", 7.8); c.setFillColor(MUTED); c.drawRightString(cx0 + cw_ - 18, cy0 + 196, "height drawn 1.6x for clarity")
# result tiles
tw_ = (cw_ - 2 * 12) / 3
for i, (name, col, land, vz, apex) in enumerate(reversed(results)):
    x = cx0 + i * (tw_ + 12)
    box(c, x, 60, tw_, 126)
    c.setFillColor(col); c.roundRect(x, 178, tw_, 8, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(x + 14, 156, name)
    for j, (k, v) in enumerate((("Lands past the net", "%.1f m" % land), ("Peak height", "%.2f m" % apex),
                                ("Speed after bounce", "%.1f m/s" % vz))):
        yy = 134 - j * 24
        c.setFont("Helvetica", 8.6); c.setFillColor(SUB); c.drawString(x + 14, yy, k)
        c.setFont("Helvetica-Bold", 9.6); c.setFillColor(INK); c.drawRightString(x + tw_ - 14, yy, v)
R = {n: (land, vz) for n, _, land, vz, _ in results}
note(c, "Spin is strong: the same swing lands %.1f m shorter with full topspin and %.1f m longer with full slice. In play the shot solver "
        "corrects for this, so spin changes the shape of the arc and the bounce, not where the ball lands."
        % (R["Flat"][0] - R["Topspin"][0], R["Slice"][0] - R["Flat"][0]), 34)
c.showPage()

# ---- 35. Bounce, net, tick
head(c, "Physics · bounce, net, tick", "Bounce, net and the 30 Hz step")
cw3 = (W - 2 * M - 2 * 18) / 3
# col 1: restitution curve
x = M; box(c, x, 60, cw3, 390)
label(c, x + 18, 428, "BOUNCE: FASTER BALLS BOUNCE LESS")
ax0, ay0, aw, ah = x + 44, 250, cw3 - 70, 150
c.setStrokeColor(LINE); c.setLineWidth(0.8)
for v in (0.5, 0.6, 0.7, 0.8):
    yy = ay0 + (v - 0.5) / 0.35 * ah
    c.line(ax0, yy, ax0 + aw, yy)
    c.setFont("Helvetica", 7.8); c.setFillColor(MUTED); c.drawRightString(ax0 - 5, yy - 3, "%.1f" % v)
for s in (0, 5, 10, 15, 20):
    c.setFont("Helvetica", 7.8); c.setFillColor(MUTED); c.drawCentredString(ax0 + s / 20 * aw, ay0 - 12, "%d" % s)
c.drawCentredString(ax0 + aw / 2, ay0 - 25, "downward speed at impact, m/s")
pth = c.beginPath()
for i in range(41):
    s = i * 0.5; px = ax0 + s / 20 * aw; py = ay0 + (bm.cor(s) - 0.5) / 0.35 * ah
    (pth.moveTo if i == 0 else pth.lineTo)(px, py)
c.setStrokeColor(BLUE); c.setLineWidth(2.2); c.drawPath(pth, stroke=1, fill=0)
c.setFont("Helvetica-Bold", 8.4); c.setFillColor(BLUE); c.drawString(ax0 + 4, ay0 + (0.78 - 0.5) / 0.35 * ah + 6, "0.78")
c.drawRightString(ax0 + aw - 2, ay0 + (0.56 - 0.5) / 0.35 * ah + 7, "0.56")
bullets(c, ["Share of vertical speed kept: 0.78 for soft balls, down to 0.56 for an 18 m/s impact.",
            "<b>Drop test passes:</b> a 78 inch drop rebounds 33.6 inches in the model. The equipment rule asks for 30 to 34.",
            "The floor grips the ball: about a fifth of the sliding speed between ball and court is removed.",
            "Spin survives the bounce at 76%% and changes the kick: on the previous page topspin leaves at %.1f m/s, slice at %.1f (flat %.1f)." % (R["Topspin"][1], R["Slice"][1], R["Flat"][1])],
        x + 18, 204, cw3 - 36, 9.2, 6, SUB, BLUE)
# col 2: net
x = M + cw3 + 18; box(c, x, 60, cw3, 390)
label(c, x + 18, 428, "NET AND COURT: RULEBOOK SIZES")
nx0, ny0, nw = x + 30, 330, cw3 - 60
import math
c.setStrokeColor(INK); c.setLineWidth(3)
c.line(nx0, ny0, nx0, ny0 + 62); c.line(nx0 + nw, ny0, nx0 + nw, ny0 + 62)
pth = c.beginPath()
for i in range(21):
    t = i / 20.0; yy = ny0 + 58 - 14 * (1 - (2 * t - 1) ** 2)
    (pth.moveTo if i == 0 else pth.lineTo)(nx0 + t * nw, yy)
c.setLineWidth(2.4); c.setStrokeColor(SUB); c.drawPath(pth, stroke=1, fill=0)
c.setStrokeColor(LINE); c.setLineWidth(0.6)
for i in range(1, 12):
    c.line(nx0 + i * nw / 12, ny0, nx0 + i * nw / 12, ny0 + 46)
c.setStrokeColor(SUB); c.setLineWidth(1); c.line(nx0 - 8, ny0, nx0 + nw + 8, ny0)
c.setFont("Helvetica-Bold", 8.6); c.setFillColor(INK)
c.drawCentredString(nx0 + nw / 2, ny0 + 52, "0.864 m centre"); c.drawString(nx0 + 6, ny0 + 68, "0.914 m at the sidelines")
bullets(c, ["Court 13.4 x 6.1 m, kitchen 2.134 m, lines count as in. The net sags in the middle, as on a real court.",
            "A ball that hits the net keeps 86% of its sliding speed and 32% of its speed into the net, so tape clips can still drop over.",
            "No serve let: a serve that clips the net and lands in is live. This matches the current rulebook.",
            "Hitting a post is a fault. Going around the post is allowed for rally shots, not for serves.",
            "Out is judged at the first bounce only."],
        x + 18, 306, cw3 - 36, 9.2, 6, SUB, AQUA)
# col 3: tick
x = M + 2 * (cw3 + 18); box(c, x, 60, cw3, 390)
label(c, x + 18, 428, "THE 30 HZ STEP: FAST BALLS, FEW SAMPLES")
tiles = [("0.67 m", "travelled per step at the 20 m/s cap", ORANGE),
         ("0.27 s", "kitchen line to kitchen line at full speed", BLUE),
         ("0.13 to 0.30 s", "AI reaction delay, hard to easy", VIOLET)]
for i, (v, k, col) in enumerate(tiles):
    yy = 366 - i * 52
    c.setFillColor(col); c.roundRect(x + 18, yy, 4, 40, 2, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 16); c.setFillColor(INK); c.drawString(x + 32, yy + 20, v)
    c.setFont("Helvetica", 9); c.setFillColor(SUB); c.drawString(x + 32, yy + 5, k)
bullets(c, ["The engine's own fast-object protection is off. Custom swept tests cover the net, posts, floor, bodies and the paddle face.",
            "Contacts inside one step are resolved in time order: body, net, then floor.",
            "<b>Open:</b> after the move from 60 to 30 Hz the all-AI bench showed more balls into the net (15 against 9). Not yet explained.",
            "A full-speed exchange at the kitchen gives the easy AI no time to react. That is a difficulty lever, not a bug."],
        x + 18, 250, cw3 - 36, 9.2, 6, SUB, ORANGE)
c.showPage()

# ---- 36. Contact
head(c, "Mechanics · the hit", "A hit is solved to a target, then perturbed")
stages = [("1", "Your input", BLUE, ["Aim cursor on the far court", "Charge: hold HIT up to 0.45 s", "Spin: Flat, Topspin or Slice", "Arc higher or lower, Drop intent"]),
          ("2", "Is it legal and reachable?", VIOLET, ["Paddle head within 1.35 m of the shoulder", "Two-bounce rule and kitchen feet checked first", "An illegal swing is refused, not faulted"]),
          ("3", "Solve the launch", AQUA, ["Finds speed and angle that land on the target", "Clears the net by 8 cm (serves 14 cm)", "Peak no higher than 4.6 m", "Accounts for drag and the chosen spin"]),
          ("4", "Execution error", ORANGE, ["One random nudge at contact", "Up to 4.4° sideways, 3.5° up or down", "Up to 14% speed, 18% spin", "AI: x1.25 easy, x1.0 medium, x0.75 hard"])]
sw = (W - 2 * M - 3 * 30) / 4
for i, (n, t, col, items) in enumerate(stages):
    x = M + i * (sw + 30)
    box(c, x, 286, sw, 164)
    c.setFillColor(col); c.circle(x + 24, 426, 11, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(WHITE); c.drawCentredString(x + 24, 422.5, n)
    c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(x + 42, 422, t)
    bullets(c, items, x + 16, 400, sw - 30, 9.2, 5, SUB, col)
    if i < 3: arrow(c, x + sw + 5, 368, x + sw + 25, 368, SUB)
# error weights
box(c, M, 60, 400, 210)
label(c, M + 18, 248, "WHAT MAKES A HIT HARDER (SHARE OF THE ERROR)")
wts = [("Timing, within 0.10 s", 24), ("Off-centre on the paddle", 24), ("Balance: moving, feet planted", 20),
       ("Arm at full stretch", 15), ("Incoming ball speed", 12), ("Your own shot power", 5)]
for i, (n, v) in enumerate(wts):
    y = 220 - i * 24
    c.setFont("Helvetica", 9.4); c.setFillColor(INK); c.drawString(M + 18, y + 3, n)
    c.setFillColor(ORANGE); c.roundRect(M + 190, y, 160 * v / 24, 14, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.2); c.setFillColor(INK); c.drawString(M + 196 + 160 * v / 24, y + 3, "%d%%" % v)
xr = M + 418; wr = (W - M - xr - 18) / 2
box(c, xr, 60, wr, 210, HexColor("#eefaf4"), HexColor("#bfe8d3"))
label(c, xr + 16, 248, "CHANGES THE SHOT", AQUA, 9.5)
y = 232
for t in ["Where you aim and how long you charge", "Spin mode and arc", "How clean the contact was (list on the left)",
          "Off-centre hits lose up to 15% pace"]:
    check(c, xr + 16, y - 9, AQUA, 0.8); y -= para(c, t, xr + 32, y, wr - 46, P(9.2, SUB)) + 9
box(c, xr + wr + 18, 60, wr, 210, HexColor("#fdf1ef"), HexColor("#f3c9c4"))
label(c, xr + wr + 34, 248, "DOES NOT CHANGE THE SHOT", RED, 9.5)
y = 232
for t in ["Paddle face angle (only checked for validity)", "How fast the paddle or the player is moving",
          "The PERFECT / GREAT / GOOD grade on screen", "The PERFECT flash on the reaction ring"]:
    cross(c, xr + wr + 34, y - 8, RED, 0.8); y -= para(c, t, xr + wr + 50, y, wr - 62, P(9.2, SUB)) + 9
note(c, "The grade on screen measures distance to the planned contact point; the error model measures timing in seconds. "
        "They are two different yardsticks, so a PERFECT can still miss.", 34)
c.showPage()

# ---- 37. Mechanics inventory
head(c, "Mechanics · inventory", "What exists today: shots, movement, rules, AI")
BUILT, PART, MISS = AQUA, YELLOW, RED
cards = [
    ("Shots", [(BUILT, "Drive, dink, drop, lob, volley, smash, return, reset, speed-up"),
               (BUILT, "Overheads reach up to 2.5 m; smash from 1.5 m"),
               (PART, "Erne: a sideways jump you choose, 2 s cooldown"),
               (PART, "Dive: written, switched off"),
               (MISS, "Around-the-post: the path is legal, no shot aims for it")]),
    ("Serves", [(BUILT, "Seven styles: flat, topspin, slice, high soft, drop drive"),
                (PART, "Banana and screwball (sidespin) marked experimental"),
                (BUILT, "Foot faults from real shoe positions"),
                (BUILT, "Short serve and wrong service court faults"),
                (MISS, "Underhand and below-the-waist motion not checked")]),
    ("Movement", [(BUILT, "Run 5.8 m/s with sharp acceleration and braking"),
                  (BUILT, "Hold HIT: feet carry you to the contact (up to 2.4 m)"),
                  (BUILT, "Aim plants your feet 0.85 s before contact"),
                  (BUILT, "Solo slow-motion aim, 3 s budget per ball"),
                  (PART, "Stamina: only top speed, down to 85% when low")]),
    ("Rules and scoring", [(BUILT, "16 fault types, each with a plain explanation"),
                           (BUILT, "Kitchen volley and momentum faults from shoe contact"),
                           (BUILT, "Doubles side-out scoring, 0-0-2 start, to 11, 15 or 21"),
                           (PART, "Singles fixed at 11, no end change"),
                           (MISS, "Rally scoring; tests cover only the doubles score")]),
    ("AI opponents", [(BUILT, "Three levels: reaction delay, speed, accuracy, aggression"),
                      (BUILT, "Five styles: all-rounder, power, dinker, counter, lob"),
                      (BUILT, "Partner cover: who takes the middle, poaching, spacing"),
                      (PART, "Misses come only from the shared error model"),
                      (MISS, "Stacking, and reading the opponent's habits")]),
    ("Modes", [(BUILT, "Singles, and doubles with an AI partner"),
               (BUILT, "Practice: wall, serve placement, baseline drive"),
               (BUILT, "Practice: serve return, crosscourt dinks, fast hands"),
               (MISS, "Two humans (the switch exists, nothing sets it)"),
               (MISS, "Career, tournaments, difficulty shown as a choice")]),
]
cw3 = (W - 2 * M - 2 * 16) / 3; chh = 182
for i, (t, items) in enumerate(cards):
    x = M + (i % 3) * (cw3 + 16); y = 268 - (i // 3) * (chh + 12)
    box(c, x, y, cw3, chh)
    c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x + 16, y + chh - 24, t)
    yy = y + chh - 38
    for col, text in items:
        c.setFillColor(col); c.roundRect(x + 16, yy - 9.5, 8, 8, 2, stroke=0, fill=1)
        yy -= para(c, text, x + 32, yy, cw3 - 46, P(9, SUB)) + 5.5
lx = M
for col, t in ((BUILT, "Built"), (PART, "Partly built"), (MISS, "Missing")):
    c.setFillColor(col); c.roundRect(lx, 40, 8, 8, 2, stroke=0, fill=1)
    c.setFont("Helvetica", 8.8); c.setFillColor(SUB); c.drawString(lx + 13, 41, t); lx += 30 + c.stringWidth(t, "Helvetica", 8.8)
c.showPage()

# ---- 38. Gaps
head(c, "Gaps", "Where the game stops short of real pickleball")
gaps = [("The paddle does not strike the ball", "Face angle and swing speed are only validity checks.",
         "Every clean hit sends the solved shot. Skill shows only as random error.", "Large", RED),
        ("The on-screen grade is cosmetic", "Grade uses distance; error uses timing. PERFECT changes nothing.",
         "You cannot learn from it what made a shot better.", "Small", AQUA),
        ("Hard 20 m/s speed cap", "Clamped every step (45 mph).",
         "Smashes and hard drives top out at the same pace.", "Small", AQUA),
        ("Narrow spin control", "Three modes. Sidespin only in two experimental serves.",
         "No curving rally shots; the AI never has to read spin.", "Medium", YELLOW),
        ("Shallow stamina", "Only top speed, to 85% below a quarter tank.",
         "Long rallies never change what the right shot is.", "Small", AQUA),
        ("Signature shots missing", "No around-the-post shot, dive off, Erne is a movement option.",
         "The highlight plays of the sport are not in the game.", "Medium", YELLOW),
        ("Rules partly enforced and tested", "Serve motion unchecked. Tests cover only the doubles score.",
         "Fault, kitchen and serve rules can break without anyone noticing.", "Medium", YELLOW),
        ("Loose ends in the code", "Old ball size, net height and gravity values; unused solvers; open 30 Hz net question.",
         "Easy to tune the wrong number.", "Small", AQUA)]
cols = [(M + 16, "GAP"), (M + 250, "EVIDENCE IN THE CODE"), (M + 530, "WHAT THE PLAYER FEELS"), (W - M - 74, "SIZE")]
box(c, M, 52, W - 2 * M, 398)
for xx, t in cols: label(c, xx, 430, t)
for i, (g, ev, feel, size, col) in enumerate(gaps):
    y = 416 - i * 45
    c.setStrokeColor(LINE); c.setLineWidth(0.6); c.line(M + 16, y + 5, W - M - 16, y + 5)
    c.setFillColor(ORANGE); c.circle(M + 24, y - 14, 8.5, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9); c.setFillColor(WHITE); c.drawCentredString(M + 24, y - 17, str(i + 1))
    para(c, "<b>%s</b>" % g, M + 40, y - 4, 196, P(9.8, INK))
    para(c, ev, M + 250, y - 4, 264, P(9.1, SUB))
    para(c, feel, M + 530, y - 4, 250, P(9.1, SUB))
    tag(c, W - M - 74, y - 22, size, col, size=8)
note(c, "Size is build effort, not importance. Gap 1 is both the largest to build and the one that most changes how the game feels.", 28)
c.showPage()

# ---- 39. Gameplay v2 proposal
head(c, "Gameplay v2 · proposal", "Keep the solved shot; make skill visible")
box(c, M, 366, W - 2 * M, 84, HexColor("#eef4fc"), HexColor("#c5d9f2"))
label(c, M + 18, 428, "DESIGN STANCE", BLUE, 9.5)
para(c, "The ball is already a simulation. The hands are assisted: you pick a target and the game finds the swing. "
        "That is the right trade for a phone and should stay. Gameplay v2 does not replace the solver. It makes what "
        "the player does well (timing, balance, clean contact, paddle angle) show up in the result, and adds the "
        "shots and rules that are missing.", M + 18, 418, W - 2 * M - 36, P(10.2, SUB))
packs = [("G0", "Safety net first", AQUA, "Rule tests for faults, kitchen, serve and singles. A fixed-flight test from the ball model. "
          "Clean the stale constants. Explain the 30 Hz net result."),
         ("G1", "Contact skill", BLUE, "One yardstick for the grade and the error. Good timing narrows the error; PERFECT rewards "
          "accuracy, not power. On a miss, say why: late, off-centre, off-balance."),
         ("G2", "The paddle matters", ORANGE, "Let face angle and swing speed bend the solved shot inside limits: an open face adds "
          "height, a fast swing adds pace. Behind a setting, judged by playtest."),
         ("G3", "Spin and pace", VIOLET, "Sidespin for rally shots. Spin shown on the aim arc. AI reads spin. Test a higher speed cap "
          "for smashes only."),
         ("G4", "Body and stamina", PINK, "Low stamina widens the error and slows recovery. Turn on the dive. A split-step bonus "
          "for timing your stop."),
         ("G5", "Shots, rules, modes", YELLOW, "Around-the-post shot, a full Erne, lob defence. Difficulty as a menu choice. Singles "
          "options, rally scoring, serve-motion rule.")]
pw = (W - 2 * M - 2 * 16) / 3
for i, (n, t, col, d) in enumerate(packs):
    x = M + (i % 3) * (pw + 16); y = 216 - (i // 3) * 150
    box(c, x, y, pw, 136)
    c.setFillColor(col); c.roundRect(x + 16, y + 102, 34, 20, 5, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10); c.setFillColor(WHITE); c.drawCentredString(x + 33, y + 108.5, n)
    c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x + 60, y + 107, t)
    para(c, d, x + 16, y + 92, pw - 32, P(9.4, SUB))
note(c, "AI difficulty needs no new system: three levels and five playing styles already exist and only need tuning and a menu.", 34)
c.showPage()

# ---- 40. Roadmap
head(c, "Gameplay v2 · roadmap", "Six packages, each proven on the bench")
plan = [("G0", "Safety net", 0, 2, AQUA, "Tests and clean-up. Does not change play, so it can start now."),
        ("G1", "Contact skill", 2, 2, BLUE, "Grade and error share one measure; miss reasons on screen."),
        ("G2", "The paddle matters", 4, 3, ORANGE, "Prototype behind a setting; keep only if playtests prefer it."),
        ("G3", "Spin and pace", 6, 2, VIOLET, "Sidespin shots, AI spin reading, smash speed test."),
        ("G4", "Body and stamina", 8, 2, PINK, "Stamina on accuracy, dive, split step."),
        ("G5", "Shots, rules, modes", 9, 3, YELLOW, "New shots, difficulty menu, singles and scoring options.")]
gx0, gx1 = M + 250, W - M; weeks = 12; unit = (gx1 - gx0) / weeks
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
for wk in range(weeks + 1):
    xx = gx0 + wk * unit
    c.setStrokeColor(LINE); c.setLineWidth(0.8); c.line(xx, 134, xx, 440)
    if wk < weeks: c.drawCentredString(xx + unit / 2, 446, "W%d" % (wk + 1))
for i, (n, t, s, d, col, desc) in enumerate(plan):
    y = 404 - i * 50
    c.setFillColor(col); c.roundRect(M, y - 2, 30, 20, 5, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.5); c.setFillColor(WHITE); c.drawCentredString(M + 15, y + 4.5, n)
    c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(M + 40, y + 10, t)
    para(c, desc, M + 40, y + 2, 200, P(8.3, SUB, 10.5))
    c.setFillColor(col); c.roundRect(gx0 + s * unit + 2, y - 2, d * unit - 4, 22, 6, stroke=0, fill=1)
box(c, M, 46, W - 2 * M, 76, HexColor("#eefaf4"), HexColor("#bfe8d3"))
c.setFont("Helvetica-Bold", 10.5); c.setFillColor(AQUA); c.drawString(M + 16, 100, "GATE FOR EVERY PACKAGE")
para(c, "All-AI bench on the same 6 seeds at 300 s, before and after · the shot report row the change targets must improve and no other row "
        "may get worse · rule tests pass · a short hand-played check on the phone. Weeks count from the start of Gameplay v2 and are rough "
        "sizing, not commitments. G0 fits beside the visual phases; G1 onward should wait for the iPhone baseline so feel is judged on the device.",
     M + 16, 93, W - 2 * M - 32, P(9.3, SUB))
c.showPage()

# ---- 41. Decisions
head(c, "Decisions", "Six choices that shape Gameplay v2")
qs = [("How real should the hands be?", "Keep assisted aiming (pick a target, the game finds the swing).",
       "A struck-ball model would be closer to the sport but far harder to play on a phone."),
      ("When does v2 start?", "G0 now. G1 onward after the pixel viewport and the iPhone baseline.",
       "Tests change nothing in play. Feel work should be judged on the device."),
      ("What does perfect timing earn?", "A tighter shot, not a faster one.",
       "Rewarding power turns every rally into a drive contest; accuracy rewards the same skill without that."),
      ("Should paddle angle bend the shot?", "Prototype it behind a setting and decide by playtest.",
       "It is the largest change to feel in this plan, and the one most likely to surprise."),
      ("Raise the 20 m/s speed cap?", "Test a higher cap for smashes only.",
       "Faster drives shorten reaction time at the kitchen to under 0.27 s, below the easy AI's delay."),
      ("How deep should stamina go?", "One step deeper: low stamina widens the error.",
       "Enough to make a long rally matter, without adding a meter to manage.")]
qw = (W - 2 * M - 18) / 2
for i, (q, rec, why) in enumerate(qs):
    x = M + (i % 2) * (qw + 18); y = 330 - (i // 2) * 130
    box(c, x, y, qw, 118)
    c.setFillColor(BLUE); c.circle(x + 24, y + 94, 11, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(WHITE); c.drawCentredString(x + 24, y + 90.5, str(i + 1))
    c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x + 44, y + 90, q)
    label(c, x + 44, y + 68, "RECOMMENDED", AQUA, 7.8)
    h = para(c, "<b>%s</b>" % rec, x + 44, y + 62, qw - 62, P(9.8, INK))
    para(c, why, x + 44, y + 62 - h - 4, qw - 62, P(9.1, SUB))
note(c, "Sources for this part: scripts/ball.gd, shot_physics.gd, shot_execution_error.gd, shot_profile.gd, rally_scorer.gd, "
        "player_stamina.gd, ai_match_tactics.gd, docs/ROADMAP.md, and the model copy in docs/proposal_pdf/ball_model.py.", 34)
c.showPage()
c.save()
print("ok, pages %d to %d" % (FIRST_PAGE, page[0]))
