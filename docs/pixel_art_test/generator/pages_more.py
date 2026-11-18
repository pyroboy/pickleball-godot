# Executed inside make_pdf.py after the Effects page. Effects, trajectories, slow-mo, shaders, UI, controls.
from reportlab.lib.utils import ImageReader

def table(c, x, y, cols, rows, widths, size=9, gap=17, head_col=MUTED):
    for i, r in enumerate([cols] + rows):
        yy = y - i * gap
        if i: c.setStrokeColor(LINE); c.setLineWidth(0.6); c.line(x, yy + gap - 5, x + sum(widths), yy + gap - 5)
        xx = x
        for v, wv in zip(r, widths):
            c.setFont("Helvetica-Bold" if i == 0 or xx == x else "Helvetica", size)
            c.setFillColor(head_col if i == 0 else (INK if xx == x else SUB))
            c.drawString(xx, yy, v); xx += wv
    return y - len(rows) * gap

# ---- B1 effects sprite sheet
header(c, "Effects · sprites", "Effects sprite sheet (generated)")
pimg(c, 'fx_sheet.png', M, 34, 400, 430, 'l')
rx = M + 400
para(c, "Every effect is a short, pooled sprite animation played on a 3D quad in the world, so it sits at the right depth and scale. "
        "Fades use ordered dithering, which keeps the pixel look and is free on the GPU (alpha-scissor, no blending).",
     rx, 448, W - M - rx, P(10, SUB))
table(c, rx, 380, ("Effect", "Trigger", "Frames", "Hooks into"),
      [("Impact burst", "paddle contact", "6", "fx/impact_burst.gd"),
       ("Spark ring", "sweet-spot hit", "5", "fx/hit_feedback.gd"),
       ("Bounce", "ball lands", "6", "fx/bounce_decal.gd"),
       ("Footwork dust", "split step / stop", "5", "new, fx_pool.gd"),
       ("Swing arc", "every swing", "5", "new, additive"),
       ("Speed lines", "dives, sprints", "3 loop", "new"),
       ("Landing marker", "ball in flight", "4 pulse", "game_trajectory.gd"),
       ("Smash flash", "hard hits", "4", "hit_feedback + hit-stop"),
       ("Out stamp", "fault call", "4", "rally_scorer signal"),
       ("Ball trails", "per shot type", "-", "fx/ball_trail.gd")],
      [110, 110, 52, 190], 9.2, 21)
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(rx, 52, "All effects are visual only. Shot physics, scoring and timing are untouched.")
c.showPage()

# ---- B2 trajectories
header(c, "Trajectories", "Three arcs, one visual language")
tw3 = (W - 2 * M - 2 * 16) / 3
for i, (nm, title, col, desc) in enumerate((
        ('traj_serve.png', 'Serve preview', YELLOW, 'Gold dashes from the paddle to a pulsing landing ring. A dotted ground line shows depth.'),
        ('traj_incoming.png', 'Incoming ball guide', RED, 'Opponent shots in red: where to move. Short dashes plus a ball trail.'),
        ('traj_aim.png', 'Aim arc (hit)', BLUE, 'Cyan arc while dragging HIT, ending in a target ring with chevrons.'))):
    x = M + i * (tw3 + 16)
    pimg(c, nm, x, 150, tw3, 300)
    c.setFillColor(col); c.rect(x, 136, 26, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(x, 118, title)
    para(c, desc, x, 110, tw3, P(9.2, SUB))
box(c, M, 30, W - 2 * M, 44)
para(c, "<b>Rules:</b> dash 4 px on / 3 px off in the pixel viewport (12 / 9 screen px, close to today's 14 / 9 in aim_arc_style.gd) · colour = who owns the ball · "
        "arcs come from the existing prediction in game_trajectory.gd, only the drawing changes · drawn above blur and dim, never softened.",
     M + 12, 66, W - 2 * M - 24, P(9.2, SUB))
c.showPage()

# ---- B3 slow-mo
header(c, "Slow motion", "Aim-focus slow-mo: lens depth of field, in the 3D world")
pimg(c, 'slowmo.png', M, 300, W - 2 * M, 150)
# chart: time scale vs time to contact (simplified)
gx, gy, gw, gh = M + 10, 60, 380, 170
c.setStrokeColor(LINE); c.setLineWidth(0.8)
for v in (0, 0.25, 0.5, 0.75, 1.0):
    yy = gy + gh * v; c.line(gx, yy, gx + gw, yy)
    c.setFont("Helvetica", 8); c.setFillColor(MUTED); c.drawRightString(gx - 6, yy - 3, "%.2fx" % v)
X = lambda s: gx + gw * (1.0 - s / 1.2)
Y = lambda v: gy + gh * v
pts = [(1.2, 1.0), (0.86, 1.0), (0.85, 0.6)]
import math
for k in range(1, 21):
    s = 0.85 - (0.85 - 0.03) * k / 20
    pts.append((s, 0.6 + (0.12 - 0.6) * (1 - (1 - k / 20) ** 2)))
pts += [(0.0, 0.02), (-0.05, 0.02), (-0.06, 1.0)]
c.setStrokeColor(BLUE); c.setLineWidth(2)
pth = c.beginPath(); pth.moveTo(X(pts[0][0]), Y(pts[0][1]))
for s, v in pts[1:]: pth.lineTo(min(X(s), gx + gw), Y(v))
c.drawPath(pth, stroke=1, fill=0)
for s, lab in ((0.85, "enter 0.85 s"), (0.0, "contact")):
    c.setDash(2, 2); c.setStrokeColor(MUTED); c.setLineWidth(0.8); c.line(X(s), gy, X(s), gy + gh); c.setDash()
    c.setFont("Helvetica", 8); c.setFillColor(SUB); c.drawCentredString(X(s), gy - 12, lab)
c.setFont("Helvetica-Bold", 10.5); c.setFillColor(INK); c.drawString(gx, gy + gh + 14, "Time scale as the ball approaches (today's values)")
c.setFont("Helvetica", 8); c.setFillColor(MUTED)
c.drawString(gx, gy - 26, "From solo_aim_focus.gd: starts at 0.6x, eases to 0.12x; hit-stop near 0 at contact. Curve shape simplified.")
rx = M + 430
c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(rx, 270, "Look: real lens depth of field (no dithering)")
bullets(c, ["<b>Focus plane at the hitter's depth</b> (~11.7 m from the camera), with a 1.5 m in-focus band. Blur grows with |depth - focus| / depth, like a thin lens.",
            "From the high camera this reads as a <b>natural tilt-shift</b>: far court, net and walls soften by depth, the foreground baseline only slightly. Light cool dim and desaturation follow the same blur amount.",
            "<b>Opponent kept readable:</b> a per-player focus mask (feathered) caps their blur at ~1.6 px and halves the dim, so you can read their position and paddle.",
            "<b>Never touched:</b> the hitter, ball, trail, aim arc and all UI are drawn after the blur, crisp.",
            "Gameplay timing is unchanged: this only restyles the slow-mo that already exists."],
        rx, 254, W - M - rx, 9.6, 6, SUB)
c.showPage()

# ---- B3b blur shader choice
header(c, "Slow motion · blur shader", "Choosing the cheapest good blur for iPhone")
opts = [("Dual-filter (Kawase)", "Recommended", AQUA, "Small pyramid (1/2, 1/4 res) built with 4-5 taps per pass; each pixel picks the level its depth asks for. Smooth, wide blur for ~10-16 taps. Canvas shaders, Compatibility-friendly.", "~0.1 ms*"),
        ("Separable Gaussian", "Fallback", YELLOW, "Two passes (horizontal, vertical) of 9-13 taps on a 1/2-res copy. Very smooth, ~2x the taps of Kawase for the same width.", "~0.2 ms*"),
        ("Mip / box blur", "Cheapest", BLUE, "Sample a lower mip of the viewport texture. Nearly free, but blocky and can shimmer in motion.", "~0.03 ms*"),
        ("Full-res Gaussian", "Avoid", RED, "Blur at 720x1280 with big kernels. Fill-rate heavy on mobile; no visual gain at this blur size.", "1 ms+*")]
cw4 = (W - 2 * M - 3 * 14) / 4
for i, (t, tg, col, d, cost) in enumerate(opts):
    x = M + i * (cw4 + 14)
    box(c, x, 270, cw4, 176)
    tag(c, x + 12, 414, tg.upper(), col)
    c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x + 12, 388, t)
    para(c, d, x + 12, 378, cw4 - 24, P(9.2, SUB))
    c.setFont("Helvetica-Bold", 18); c.setFillColor(col); c.drawString(x + 12, 284, cost)
# pipeline
steps = ["3D renders the pixel viewport + depth (240 x 427)", "Blur level per pixel from depth: |d - focus| / d", "Kawase pyramid at 1/2 and 1/4 res", "Blend level by blur; cap it on the opponent mask", "Draw hitter, ball, arcs, UI on top, sharp"]
sw5 = (W - 2 * M - 4 * 26) / 5
for i, s in enumerate(steps):
    x = M + i * (sw5 + 26)
    box(c, x, 150, sw5, 70, HexColor("#f4f2ff"), HexColor("#d9d3f5"))
    para(c, s, x + 10, 208, sw5 - 20, P(9.6, INK))
    if i < 4: arrow(c, x + sw5 + 4, 185, x + sw5 + 22, 185)
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(M, 236, "Pipeline")
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(M, 110, "* Rough per-frame estimates for a modern iPhone at these sizes, for comparing options. Measure on device with the PerfMonitor before committing.")
c.drawString(M, 82, "Depth source: the viewport depth texture, or computed from the known court plane + player depths if depth reads are limited in Compatibility (verify).")
c.drawString(M, 96, "Because the blur runs on the small pixel-viewport texture (~25k pixels at 1/2 res), it costs far less than a full-screen blur.")
c.showPage()

# ---- B4 shaders
header(c, "Shader effects", "Shader effects on the pixel viewport")
pimg(c, 'shaders.png', M, 200, W - 2 * M, 260)
table(c, M, 176, ("Shader", "What it does", "Cost", "Status"),
      [("Team palette swap", "Recolours shirt shades per team / skin", "1 lookup", "New"),
       ("Hit flash", "Card goes white for 1-2 frames on contact", "trivial", "New"),
       ("Lens depth of field", "Blur by depth; opponent capped slightly soft", "low", "Restyles solo_aim_focus(_dim)"),
       ("Kitchen glow / ball ring", "Soft tint in the NVZ; ring keeps the ball readable", "trivial", "Restyles court_surface, ball_readability"),
       ("Rim light, colour grade", "Warm lit edge; dusk / indoor looks per venue", "trivial", "New, optional")],
      [150, 330, 80, 240], 9.2, 21)
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(M, 40, "Existing shaders kept and restyled: ground_shadow, ball_ground_shadow, net_fabric, court_brand, player_reach_rings, athlete_kit (replaced by cards).")
c.showPage()

# ---- C1 UI today
header(c, "UI · audit", "The UI today, element by element")
ox, oy, dw, dh = pimg(c, 'ingame_240.png', M, 40, 250, 420, 'l')
sx = dw / 720.0; sy = dh / 1280.0
marks = [(1, 360, 60), (2, 240, 195), (3, 600, 170), (4, 382, 585), (5, 128, 1130), (6, 348, 1140), (7, 568, 1130)]
for n, px, py in marks:
    X0, Y0 = ox + px * sx, oy + dh - py * sy
    c.setFillColor(ORANGE); c.circle(X0, Y0, 9, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10); c.setFillColor(HexColor("#ffffff")); c.drawCentredString(X0, Y0 - 3.5, str(n))
rx = M + 280
table(c, rx, 440, ("#", "Today", "Plan"),
      [("1", "Big two-team scoreboard", "Compact pixel score pill, server chevron"),
       ("2", "3-line coach panel", "One toast line, hides after first serves"),
       ("3", "Guide / Pause buttons", "Small round pixel icons"),
       ("4", "Floating 0-0 bubble", "Remove (duplicates the pill)"),
       ("5", "MOVE joystick", "Pixel stick, cyan direction glow"),
       ("6", "Serve wheel", "4 coloured shot segments + icon"),
       ("7", "HIT (hold + aim)", "Charge ring, aim drag, PERFECT state")],
      [26, 200, 330], 9.6, 26)
box(c, rx, 40, W - M - rx, 150, HexColor("#eefaf4"), HexColor("#bfe8d3"))
c.setFont("Helvetica-Bold", 11); c.setFillColor(AQUA); c.drawString(rx + 14, 168, "Goals")
bullets(c, ["Free the court: today the top ~22% of the screen is UI. Target under 10%.",
            "Same controls and same thumb positions; only the look changes.",
            "All UI drawn on the 1/3 pixel grid with the 5x7 font, so it matches the art.",
            "No black outlines: panels use a light top edge and a dark bottom edge."],
        rx + 14, 154, W - M - rx - 28, 9.6, 5, SUB, AQUA)
c.showPage()

# ---- C2 UI kit
header(c, "UI · kit", "Pixel UI kit")
pimg(c, 'ui_kit.png', M, 60, 600, 400, 'l')
rx = M + 620
c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(rx, 440, "Kit rules")
bullets(c, ["Built at the pixel-viewport scale: 1 UI pixel = 3 screen pixels on a 720-wide phone.",
            "Custom 5x7 bitmap font with a 1 px drop shadow, no anti-aliasing.",
            "Panels: dark plum fill, lighter top edge, darker bottom edge, cut corners.",
            "Team colours match the character palettes; gold is reserved for the ball, serve and charge.",
            "Every piece is a 9-slice or a small sprite, so it scales to any phone width."],
        rx, 424, W - M - rx, 9.6, 7, SUB)
c.showPage()

# ---- C3 mockups
header(c, "UI · mockups", "Four moments of a point, on the real camera")
pw = (W - 2 * M - 3 * 18) / 4
for i, (nm, t, d) in enumerate((('ui_rally.png', 'Rally', 'Incoming ball guide in red, joystick active.'),
                                ('ui_serve.png', 'Serve', 'Gold serve preview, HIT charging, coach toast.'),
                                ('ui_focus.png', 'Aim slow-mo', 'Lens DOF; opponent kept readable.'),
                                ('ui_point.png', 'Point won', 'Banner, confetti, PERFECT HIT state.'))):
    x = M + i * (pw + 18)
    c.setFillColor(HexColor("#16151a")); c.roundRect(x - 4, 92, pw + 8, 366, 14, stroke=0, fill=1)
    pimg(c, nm, x, 98, pw, 354)
    c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(x, 72, t)
    c.setFont("Helvetica", 8.8); c.setFillColor(SUB); c.drawString(x, 58, d)
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(M, 36, "Generated at 240x427 and upscaled x3 to the phone's 720x1281. Same camera, court, player positions and control layout as the current build.")
c.showPage()

# ---- C4 controls
header(c, "Controls", "Controls: same inputs, new look")
pimg(c, 'ui_controls.png', M, 200, 520, 260, 'l')
rx = M + 545
table(c, rx, 440, ("Control", "Gesture", "States"),
      [("MOVE stick", "drag", "idle · moving"),
       ("HIT", "tap / hold", "idle · press · charge"),
       ("", "hold + drag", "aim (arc follows drag)"),
       ("", "good timing", "PERFECT (green)"),
       ("Shot wheel", "rotate / tap", "flat · topspin · slice · drop")],
      [92, 92, 140], 9.4, 24)
box(c, M, 46, W - 2 * M, 130)
c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(M + 16, 154, "Unchanged under the hood")
bullets(c, ["Same input actions (move_left/right/up/down, hit, serve wheel) from mobile_controls.gd and input_handler.gd.",
            "Same positions and touch targets; the visible sprite can be smaller than the hit area.",
            "Charge, aim and timing values come from the existing systems; the art only shows them.",
            "New, optional: a light haptic tap on PERFECT and on smash contact."],
        M + 16, 138, W - 2 * M - 32, 9.6, 5, SUB)
c.showPage()
