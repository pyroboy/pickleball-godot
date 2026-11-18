import sys
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle

OUT = sys.argv[1]
W, H = 960, 540
M = 48

BG = HexColor("#fbfaf7"); INK = HexColor("#16151a"); SUB = HexColor("#4f4d48")
MUTED = HexColor("#8a877f"); LINE = HexColor("#e2ded5"); CARD = HexColor("#ffffff")
ORANGE = HexColor("#eb6834"); BLUE = HexColor("#2a78d6"); AQUA = HexColor("#1baf7a")
VIOLET = HexColor("#6250d6"); YELLOW = HexColor("#eda100"); RED = HexColor("#e34948")
NIGHT = HexColor("#1e1b2f"); NIGHT2 = HexColor("#2c2745")
GRASS = HexColor("#5f9a4a"); GRASS_D = HexColor("#3f7340"); GRASS_SH = HexColor("#35585a")
COURT = HexColor("#2f6fae"); KITCHEN = HexColor("#4a8cc9"); DIRT = HexColor("#c9b48a")

def P(size=11, color=INK, lead=None, font="Helvetica", align=0):
    return ParagraphStyle("p", fontName=font, fontSize=size, leading=lead or size * 1.38,
                          textColor=color, alignment=align)

def para(c, text, x, ytop, w, style):
    p = Paragraph(text, style)
    _, h = p.wrap(w, 1000)
    p.drawOn(c, x, ytop - h)
    return h

def bullets(c, items, x, ytop, w, size=11, gap=5, color=INK, dot=ORANGE):
    y = ytop
    for it in items:
        c.setFillColor(dot); c.circle(x + 3, y - size * 0.55, 2.4, stroke=0, fill=1)
        h = para(c, it, x + 13, y, w - 13, P(size, color))
        y -= h + gap
    return ytop - y

def bg(c, color=BG):
    c.setFillColor(color); c.rect(0, 0, W, H, stroke=0, fill=1)

page_no = [0]
def header(c, kicker, title, dark=False):
    page_no[0] += 1
    bg(c, NIGHT if dark else BG)
    c.setFillColor(ORANGE); c.rect(M, H - 38, 26, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.5); c.setFillColor(ORANGE)
    c.drawString(M + 34, H - 40, kicker.upper())
    c.setFont("Helvetica-Bold", 25); c.setFillColor(HexColor("#f4f1ea") if dark else INK)
    c.drawString(M, H - 70, title)
    c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
    c.drawRightString(W - M, 22, "Pickleball 2.5D  ·  graphics & performance proposal  ·  %d" % page_no[0])

def box(c, x, y, w, h, fill=CARD, stroke=LINE, r=8, lw=1):
    c.setFillColor(fill); c.setStrokeColor(stroke); c.setLineWidth(lw)
    c.roundRect(x, y, w, h, r, stroke=1 if stroke else 0, fill=1)

def tag(c, x, y, text, color, txt=HexColor("#ffffff"), size=8.5):
    c.setFont("Helvetica-Bold", size)
    tw = c.stringWidth(text, "Helvetica-Bold", size)
    c.setFillColor(color); c.roundRect(x, y, tw + 12, size + 8, 4, stroke=0, fill=1)
    c.setFillColor(txt); c.drawString(x + 6, y + 4.6, text)
    return tw + 12

def arrow(c, x1, y1, x2, y2, color=SUB, lw=1.6, head=7):
    import math
    c.setStrokeColor(color); c.setFillColor(color); c.setLineWidth(lw)
    c.line(x1, y1, x2, y2)
    a = math.atan2(y2 - y1, x2 - x1)
    p = c.beginPath()
    p.moveTo(x2, y2)
    p.lineTo(x2 - head * math.cos(a - 0.45), y2 - head * math.sin(a - 0.45))
    p.lineTo(x2 - head * math.cos(a + 0.45), y2 - head * math.sin(a + 0.45))
    p.close(); c.drawPath(p, stroke=0, fill=1)

def check(c, x, y, color=AQUA, s=1.0):
    c.setStrokeColor(color); c.setLineWidth(2.2 * s)
    p = c.beginPath(); p.moveTo(x, y + 4 * s); p.lineTo(x + 3.5 * s, y); p.lineTo(x + 10 * s, y + 9 * s)
    c.drawPath(p, stroke=1, fill=0)

def cross(c, x, y, color=RED, s=1.0):
    c.setStrokeColor(color); c.setLineWidth(2.2 * s)
    c.line(x, y, x + 8 * s, y + 8 * s); c.line(x, y + 8 * s, x + 8 * s, y)

# ---------- pixel characters (original design) ----------
FRONT = [
    "...kkkkkk...",
    "..khhhhhhk..",
    ".khhhhhhhhk.",
    ".khsssssshk.",
    ".ksesssseskk"[:12],
    ".kssssssssk.",
    "..kSssssSk..",
    "...kcccck...",
    "..kcccccck..",
    ".ksccccccsk.",
    ".ksccCCccsk.",
    ".kskcccckskk"[:12],
    "..kkppppkk..",
    "..kppPPppk..",
    "..kppkkppk..",
    "..kpk..kpk..",
    "..kwk..kwk..",
    ".kwwk..kwwk.",
    ".kkkk..kkkk.",
]
FRONT[4] = ".ksesssesk.."[:0] + ".kseSssSesk."
FRONT[11] = ".kskcccksk.."
FRONT[11] = ".kskcccckskk"[:11] + "."
BACK = list(FRONT)
BACK[3] = ".khhhhhhhhk."
BACK[4] = ".khhhhhhhhk."
BACK[5] = ".kHhhhhhhHk."
SIDE = [
    "....kkkkk...",
    "...khhhhhk..",
    "..khhhhhhhk.",
    "..khhhssssk.",
    "..khhsssesk.",
    "..khssssssk.",
    "...kSsssk...",
    "....kcck....",
    "...kcccck...",
    "...kcccsk...",
    "...kcCcsk...",
    "...kcccksk..",
    "...kkppkk...",
    "...kpPpk....",
    "...kppPk....",
    "...kpk.kpk..",
    "...kwk.kwk..",
    "..kwwk.kwwk.",
    "..kkkk.kkkk.",
]

def pal(team):
    shirt, shade = (HexColor("#2a78d6"), HexColor("#1b4f93")) if team == "blue" else (HexColor("#e34948"), HexColor("#9e2d3a"))
    return {"k": HexColor("#1b1a26"), "h": HexColor("#3b2f4a"), "H": HexColor("#2a2138"),
            "s": HexColor("#f2c7a5"), "S": HexColor("#c98f7a"), "e": HexColor("#1b1a26"),
            "c": shirt, "C": shade, "p": HexColor("#ece6da"), "P": HexColor("#b9b1c6"),
            "w": HexColor("#ffffff")}

def pixel_sprite(c, rows, x, y, px, team="blue", flip=False, shadow=True):
    colors = pal(team)
    n = len(rows)
    if shadow:
        c.setFillColor(Color(0.1, 0.08, 0.2, alpha=0.28))
        c.ellipse(x + px * 1, y - px * 1.2, x + px * 11, y + px * 1.2, stroke=0, fill=1)
    for r, row in enumerate(rows):
        row = row[::-1] if flip else row
        for col, ch in enumerate(row):
            if ch in colors:
                c.setFillColor(colors[ch])
                c.rect(x + col * px, y + (n - 1 - r) * px, px + 0.15, px + 0.15, stroke=0, fill=1)

def paddle3d(c, x, y, s=1.0, angle=0):
    c.saveState(); c.translate(x, y); c.rotate(angle)
    c.setFillColor(HexColor("#24304a")); c.roundRect(-1.5 * s, -14 * s, 3 * s, 12 * s, 1, stroke=0, fill=1)
    c.setFillColor(HexColor("#f7c948")); c.setStrokeColor(HexColor("#1b1a26")); c.setLineWidth(1.2)
    c.ellipse(-7 * s, -2 * s, 7 * s, 15 * s, stroke=1, fill=1)
    c.setFillColor(HexColor("#fff3c4")); c.ellipse(-4 * s, 6 * s, 1 * s, 12 * s, stroke=0, fill=1)
    c.restoreState()

def ball(c, x, y, r=4.5, h=0):
    c.setFillColor(Color(0.1, 0.08, 0.2, alpha=0.30)); c.ellipse(x - r, y - r * 0.5, x + r, y + r * 0.5, stroke=0, fill=1)
    c.setFillColor(HexColor("#d9ff3a")); c.setStrokeColor(HexColor("#4b5a10")); c.setLineWidth(0.8)
    c.circle(x, y + h, r, stroke=1, fill=1)

def tuft(c, x, y, s=1, col=GRASS_D):
    c.setFillColor(col)
    for dx, hh in ((0, 4), (2, 6), (4, 3)):
        c.rect(x + dx * s, y, 1.4 * s, hh * s, stroke=0, fill=1)

def pixel_tree(c, x, y, s, top=HexColor("#7c5cc4"), mid=HexColor("#9b7fe0"), hi=HexColor("#c6b4f5")):
    c.setFillColor(Color(0.1, 0.08, 0.2, alpha=0.3)); c.ellipse(x - 16 * s, y - 4 * s, x + 18 * s, y + 4 * s, stroke=0, fill=1)
    c.setFillColor(HexColor("#4b3428")); c.rect(x - 2 * s, y, 4 * s, 12 * s, stroke=0, fill=1)
    for (dx, dy, r, col) in ((0, 22, 14, top), (-8, 18, 9, top), (8, 18, 9, top), (-3, 25, 9, mid), (5, 27, 7, mid), (-1, 30, 4, hi)):
        c.setFillColor(col); c.circle(x + dx * s, y + dy * s, r * s, stroke=0, fill=1)

def court_scene(c, x, y, w, h, players=True, fx=True, label=False):
    """3/4 high-angle court mockup (original art)."""
    c.saveState()
    pth = c.beginPath(); pth.roundRect(x, y, w, h, 10); c.clipPath(pth, stroke=0)
    c.setFillColor(GRASS); c.rect(x, y, w, h, stroke=0, fill=1)
    import random
    rnd = random.Random(7)
    for _ in range(int(w * h / 900)):
        tuft(c, x + rnd.random() * w, y + rnd.random() * h, 1, GRASS_D if rnd.random() < .7 else HexColor("#79b35a"))
    for _ in range(int(w * h / 4000)):
        fx_ = x + rnd.random() * w; fy = y + rnd.random() * h
        c.setFillColor(HexColor("#f2a6c8") if rnd.random() < .5 else HexColor("#fff1a8"))
        c.rect(fx_, fy, 2, 2, stroke=0, fill=1)
    # court trapezoid (high pitch => mild taper)
    cx = x + w / 2
    bw, tw = w * 0.50, w * 0.40
    by, ty = y + h * 0.10, y + h * 0.88
    def lerp(a, b, t): return a + (b - a) * t
    def edge(t):  # t 0 bottom -> 1 top
        hw = lerp(bw, tw, t) / 2; yy = lerp(by, ty, t); return cx - hw, cx + hw, yy
    c.setFillColor(DIRT)
    l0, r0, y0 = edge(-0.04); l1, r1, y1 = edge(1.04)
    p = c.beginPath(); p.moveTo(l0 - 14, y0); p.lineTo(r0 + 14, y0); p.lineTo(r1 + 12, y1); p.lineTo(l1 - 12, y1); p.close(); c.drawPath(p, stroke=0, fill=1)
    def quad(t0, t1, col):
        a, b, ya = edge(t0); cc, d, yc = edge(t1)
        q = c.beginPath(); q.moveTo(a, ya); q.lineTo(b, ya); q.lineTo(d, yc); q.lineTo(cc, yc); q.close()
        c.setFillColor(col); c.drawPath(q, stroke=0, fill=1)
    quad(0, 1, COURT); quad(0.5 - 0.159, 0.5 + 0.159, KITCHEN)
    c.setStrokeColor(HexColor("#ffffff")); c.setLineWidth(1.6)
    for t in (0, 0.341, 0.659, 1):
        a, b, yy = edge(t); c.line(a, yy, b, yy)
    a0, b0, y0 = edge(0); a1, b1, y1 = edge(1)
    c.line(a0, y0, a1, y1); c.line(b0, y0, b1, y1)
    ma, mb, ym = edge(0.341); na, nb, yn = edge(0.0)
    c.line((a0 + b0) / 2, y0, (ma + mb) / 2, ym)
    ma, mb, ym = edge(0.659); a1, b1, y1 = edge(1)
    c.line((ma + mb) / 2, ym, (a1 + b1) / 2, y1)
    # net
    a, b, yy = edge(0.5)
    c.setFillColor(Color(0.08, 0.07, 0.15, alpha=0.35)); c.rect(a - 6, yy - 5, b - a + 12, 5, stroke=0, fill=1)
    c.setFillColor(HexColor("#22202e")); c.rect(a - 6, yy, b - a + 12, 11, stroke=0, fill=1)
    c.setFillColor(HexColor("#f4f1ea")); c.rect(a - 6, yy + 10, b - a + 12, 2.2, stroke=0, fill=1)
    c.setStrokeColor(HexColor("#4a4660")); c.setLineWidth(0.5)
    for i in range(int((b - a) / 5)):
        c.line(a - 6 + i * 5 + 5, yy, a - 6 + i * 5 + 5, yy + 10)
    # trees + fence
    for tx, ty_, s, cols in ((x + 34, y + h - 70, 1.1, None), (x + w - 40, y + h - 80, 1.25, None), (x + 30, y + 40, 1.0, "g"), (x + w - 34, y + 30, 0.95, "g")):
        if cols == "g":
            pixel_tree(c, tx, ty_, s, HexColor("#2f7d6a"), HexColor("#3f9a7f"), HexColor("#7fd1b0"))
        else:
            pixel_tree(c, tx, ty_, s)
    # vignette
    for i in range(14):
        c.setStrokeColor(Color(0.07, 0.05, 0.16, alpha=0.05)); c.setLineWidth(10)
        c.roundRect(x - 4 + i * 2, y - 4 + i * 2, w + 8 - i * 4, h + 8 - i * 4, 10, stroke=1, fill=0)
    if players:
        px = max(1.6, h / 150)
        # far team (red, facing camera -> FRONT view)
        l, r, yy = edge(0.80); pixel_sprite(c, FRONT, lerp(l, r, 0.28) - 6 * px, yy, px * 0.9, "red")
        paddle3d(c, lerp(l, r, 0.28) + 6 * px, yy + 9 * px, 0.8 * px / 2, -20)
        l, r, yy = edge(0.70); pixel_sprite(c, FRONT, lerp(l, r, 0.70) - 6 * px, yy, px * 0.9, "red", flip=True)
        paddle3d(c, lerp(l, r, 0.70) - 6 * px, yy + 9 * px, 0.8 * px / 2, 25)
        # near team (blue, back to camera -> BACK view)
        l, r, yy = edge(0.13); pixel_sprite(c, BACK, lerp(l, r, 0.30) - 6 * px, yy, px, "blue")
        l, r, yy = edge(0.22); pixel_sprite(c, SIDE, lerp(l, r, 0.68) - 6 * px, yy, px, "blue")
        bx = lerp(l, r, 0.68) + 6.5 * px; by_ = yy + 10 * px
        paddle3d(c, bx, by_, px / 2, -55)
    if fx:
        # ball + trail + landing marker
        l, r, yy = edge(0.42)
        bxx = lerp(l, r, 0.55)
        for i in range(10):
            c.setFillColor(Color(1, 1, 0.75, alpha=0.06 + i * 0.05))
            c.circle(bxx - 40 + i * 4, yy - 26 + i * 3.3 + 22, 1.5 + i * 0.35, stroke=0, fill=1)
        ball(c, bxx, yy - 14, 4.5, 0)
        c.setFillColor(HexColor("#d9ff3a")); c.setStrokeColor(HexColor("#4b5a10"))
        c.circle(bxx + 2, yy + 20, 4.6, stroke=1, fill=1)
        c.setStrokeColor(Color(1, 1, 1, alpha=0.6)); c.setLineWidth(0.8); c.setDash(2, 2)
        c.line(bxx + 2, yy + 15, bxx, yy - 12); c.setDash()
        lx, rx, ly = edge(0.82); mx = lerp(lx, rx, 0.62)
        c.setStrokeColor(HexColor("#ffe27a")); c.setLineWidth(1.6)
        c.ellipse(mx - 13, ly - 5, mx + 13, ly + 5, stroke=1, fill=0)
        c.setFillColor(HexColor("#ffe27a"))
        for k in range(3):
            pth2 = c.beginPath(); yb = ly + 10 + k * 6
            pth2.moveTo(mx - 4, yb + 4); pth2.lineTo(mx, yb); pth2.lineTo(mx + 4, yb + 4); pth2.lineTo(mx + 4, yb + 6); pth2.lineTo(mx, yb + 2); pth2.lineTo(mx - 4, yb + 6); pth2.close()
            c.drawPath(pth2, stroke=0, fill=1)
        # swing arc on near player
        l, r, yy = edge(0.22); sx = lerp(l, r, 0.68) + 4; sy = yy + 28
        for i, al in enumerate((0.15, 0.3, 0.55, 0.85)):
            c.setStrokeColor(Color(0.85, 0.97, 1, alpha=al)); c.setLineWidth(4 - i * 0.7)
            c.arc(sx - 22 + i * 2, sy - 18, sx + 22 - i * 2, sy + 20, 200, 120)
    # HUD
    c.setFillColor(Color(0.08, 0.07, 0.15, alpha=0.75)); c.roundRect(x + 12, y + h - 30, 112, 20, 10, stroke=0, fill=1)
    c.setFillColor(BLUE); c.circle(x + 24, y + h - 20, 6, stroke=0, fill=1)
    c.setFillColor(RED); c.circle(x + 112, y + h - 20, 6, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10); c.setFillColor(HexColor("#ffffff"))
    c.drawCentredString(x + 68, y + h - 24, "7 - 5 - 2")
    c.restoreState()

# =============== PAGES ===============
c = canvas.Canvas(OUT, pagesize=(W, H))
c.setTitle("Pickleball 2.5D — Graphics & Performance Proposal")
c.setAuthor("Pickleball Godot project")

# ---- 1. Cover
page_no[0] += 1
bg(c, NIGHT)
for i in range(60):
    import random
    rr = random.Random(i)
    c.setFillColor(Color(1, 1, 1, alpha=0.15 + rr.random() * 0.4)); c.rect(rr.random() * W * 0.45, rr.random() * H, 1.6, 1.6, stroke=0, fill=1)
court_scene(c, 470, 50, 450, 440)
c.setFillColor(ORANGE); c.rect(M, 400, 30, 4, stroke=0, fill=1)
c.setFont("Helvetica-Bold", 10); c.drawString(M + 40, 398, "PLANNING PROPOSAL  ·  NOVEMBER 2026")
c.setFont("Helvetica-Bold", 40); c.setFillColor(HexColor("#f6f2ea"))
c.drawString(M, 340, "Pickleball 2.5D")
c.setFont("Helvetica", 21); c.setFillColor(HexColor("#cfc8e6"))
c.drawString(M, 306, "Pixel-card players, a 3D world,")
c.drawString(M, 280, "and a faster game on iPhone")
para(c, "How to move the game toward a fast, high-angle 2.5D pixel look in the spirit of <b>Alabaster Dawn</b>, using the "
        "bone-card technique from the Cor Mundi short — without changing how pickleball plays. Ball, court physics, "
        "scoring, AI and effects stay in 3D.", M, 240, 380, P(11.5, HexColor("#d9d4ea")))
c.setFont("Helvetica", 9); c.setFillColor(HexColor("#9c95b8"))
c.drawString(M, 70, "Mockup on the right is an original illustration of the target look, not a screenshot.")
c.showPage()

# ---- 2. Executive summary
header(c, "Summary", "The proposal on one page")
cols = [
    (ORANGE, "LOOK", "Pixel-card players on a 3D court",
     ["Players become flat pixel-art <b>cards pinned to the existing 19-bone skeleton</b>.",
      "High 3/4 camera, saturated palette, hue-shifted shadows, vignette — the Alabaster Dawn mood.",
      "World and effects render at a low pixel resolution so everything shares one pixel grid."]),
    (BLUE, "PERFORMANCE", "Same game, far less work per frame",
     ["Player bodies today: <b>~40,400 triangles each</b> (measured), ~161k for 4 players.",
      "Cards: ~34 triangles per player, 1 draw call per player.",
      "Low-res 3D viewport shades ~1/9 of the pixels at native retina."]),
    (AQUA, "GAMEPLAY", "Rules and feel locked",
     ["Shot physics, ball flight, scoring, AI decisions and input timing are <b>not touched</b>.",
      "The existing IK + pose library keeps driving the bones; only what is drawn on them changes.",
      "Test suites (shot physics, rally scorer, hitting) must pass unchanged at every phase."]),
]
cw = (W - 2 * M - 2 * 18) / 3
for i, (col, k, t, items) in enumerate(cols):
    x = M + i * (cw + 18)
    box(c, x, 70, cw, 350)
    c.setFillColor(col); c.roundRect(x, 412, cw, 8, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9); c.setFillColor(col); c.drawString(x + 18, 388, k)
    para(c, "<b>%s</b>" % t, x + 18, 380, cw - 36, P(15, INK))
    bullets(c, items, x + 18, 330, cw - 36, 10.5, 9, SUB, col)
    c.setStrokeColor(LINE); c.line(x + 18, 196, x + cw - 18, 196)
    if i == 0:
        pixel_sprite(c, BACK, x + 30, 96, 4, "blue"); pixel_sprite(c, SIDE, x + 100, 96, 4, "blue")
        pixel_sprite(c, FRONT, x + 196, 96, 4, "red"); paddle3d(c, x + 156, 146, 2.0, -40)
    elif i == 1:
        for k_, (n_, v_, cl) in enumerate((("Today", 161568, BLUE), ("Phase 0", 8992, BLUE), ("Cards", 136, ORANGE))):
            yy = 160 - k_ * 32
            c.setFont("Helvetica", 9.5); c.setFillColor(INK); c.drawString(x + 18, yy + 4, n_)
            wv = max(3, 150 * v_ / 161568); c.setFillColor(cl); c.roundRect(x + 72, yy, wv, 14, 4, stroke=0, fill=1)
            c.setFont("Helvetica-Bold", 9); c.setFillColor(INK); c.drawString(x + 78 + wv, yy + 3.5, "{:,}".format(v_))
        c.setFont("Helvetica", 8); c.setFillColor(MUTED); c.drawString(x + 18, 84, "Body triangles per frame, 4 players")
    else:
        c.setFillColor(AQUA); c.roundRect(x + 24, 104, 46, 38, 6, stroke=0, fill=1)
        c.setStrokeColor(AQUA); c.setLineWidth(5); c.arc(x + 32, 128, x + 62, 166, 0, 180)
        c.setFillColor(HexColor("#ffffff")); c.circle(x + 47, 124, 5, stroke=0, fill=1)
        c.setFont("Helvetica", 9); c.setFillColor(SUB)
        for k_, f_ in enumerate(["shot_physics.gd", "ball.gd (flight)", "rally_scorer.gd", "player_ai_brain.gd", "input_handler.gd"]):
            c.drawString(x + 92, 166 - k_ * 17, f_)
c.setFont("Helvetica-Bold", 10.5); c.setFillColor(INK)
c.drawString(M, 46, "Recommendation:")
c.setFont("Helvetica", 10.5); c.setFillColor(SUB)
c.drawString(M + 98, 46, "Option A (bone cards) + low-res pixel viewport, built in 6 phases behind a Classic / Pixel toggle.")
c.showPage()

# ---- 3. Video decoded
header(c, "Reference 1 · Cor Mundi Studios short", "What the short actually shows")
steps = [
    ("0-4s", "Final look", "Pixel character walks a 3D pier; turns and moves like a 3D model."),
    ("6-10s", "Debug viewer", "Toggles for cards, shadows, mesh, bones, axes and part colours."),
    ("~16s", "Card painter", "Each body part is painted as its own small pixel sprite with a palette."),
    ("14-18s", "Hidden mesh", "An orange 3D mannequin underneath carries the normal 3D animation."),
    ("20-24s", "The rig", "Named bones (hand, spine, thigh); each card pins to one."),
    ("27s", "Payoff", "Jump with arms up: cards follow the 3D animation and cast real 3D shadows."),
]
sw = (W - 2 * M - 5 * 12) / 6
for i, (t, name, desc) in enumerate(steps):
    x = M + i * (sw + 12)
    box(c, x, 196, sw, 240)
    # mini illustration
    ix, iy = x + sw / 2, 330
    if i == 0:
        c.setFillColor(HexColor("#7fb2d9")); c.rect(x + 8, 300, sw - 16, 92, stroke=0, fill=1)
        c.setFillColor(HexColor("#e9e6df")); c.rect(x + 8, 300, sw - 16, 22, stroke=0, fill=1)
        pixel_sprite(c, SIDE, ix - 14, 312, 2.3, "blue")
    elif i == 1:
        for j, lab in enumerate(["Cards", "Shadows", "Mesh", "Bones", "Card axes"]):
            c.setFillColor(HexColor("#2c2745")); c.rect(x + 10, 376 - j * 15, 70, 13, stroke=0, fill=1)
            c.setFillColor(HexColor("#ffffff")); c.setFont("Helvetica", 7.5); c.drawString(x + 14, 380 - j * 15, lab)
            (check if j != 2 else cross)(c, x + 66, 379 - j * 15, AQUA if j != 2 else RED, 0.7)
        pixel_sprite(c, FRONT, x + sw - 46, 300, 2.0, "blue")
    elif i == 2:
        for j in range(6):
            for k_ in range(6):
                c.setFillColor(HexColor(["#3b2f4a", "#f2c7a5", "#2a78d6", "#ece6da", "#1b1a26", "#c98f7a"][(j + k_) % 6]))
                c.rect(x + 14 + j * 9, 304 + k_ * 9, 8, 8, stroke=0, fill=1)
        c.setStrokeColor(ORANGE); c.setLineWidth(1.5); c.rect(x + sw - 52, 320, 38, 50, stroke=1, fill=0)
        pixel_sprite(c, FRONT[:7], x + sw - 50, 328, 2.8, "blue", shadow=False)
    elif i == 3:
        c.setFillColor(HexColor("#f08a2c"))
        c.circle(ix, 384, 10, stroke=0, fill=1); c.roundRect(ix - 11, 334, 22, 40, 8, stroke=0, fill=1)
        for dx in (-7, 7): c.roundRect(ix + dx - 4, 300, 8, 34, 4, stroke=0, fill=1)
        for dx in (-17, 17): c.roundRect(ix + dx - 4, 340, 8, 32, 4, stroke=0, fill=1)
    elif i == 4:
        pts = [(ix, 388), (ix, 368), (ix, 340), (ix - 16, 366), (ix - 20, 344), (ix + 16, 366), (ix + 20, 344), (ix - 7, 336), (ix - 8, 304), (ix + 7, 336), (ix + 8, 304)]
        c.setStrokeColor(HexColor("#7bd88f")); c.setLineWidth(1.4)
        for a_, b_ in ((0, 1), (1, 2), (1, 3), (3, 4), (1, 5), (5, 6), (2, 7), (7, 8), (2, 9), (9, 10)):
            c.line(*pts[a_], *pts[b_])
        c.setFillColor(HexColor("#ffffff")); c.setStrokeColor(INK); c.setLineWidth(0.6)
        for p_ in pts: c.circle(*p_, 2.4, stroke=1, fill=1)
    else:
        c.setFillColor(Color(0.1, 0.08, 0.2, alpha=0.25)); c.ellipse(ix - 30, 300, ix + 10, 310, stroke=0, fill=1)
        pixel_sprite(c, FRONT, ix - 14, 318, 2.3, "blue", shadow=False)
        c.setFillColor(HexColor("#f2c7a5")); c.rect(ix - 18, 362, 4, 18, stroke=0, fill=1); c.rect(ix + 14, 362, 4, 18, stroke=0, fill=1)
    tag(c, x + 10, 266, t, NIGHT2)
    c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(x + 10, 250, name)
    para(c, desc, x + 10, 244, sw - 20, P(9, SUB))
box(c, M, 60, W - 2 * M, 118, HexColor("#fff4ee"), HexColor("#f6c6ae"))
c.setFont("Helvetica-Bold", 12); c.setFillColor(ORANGE); c.drawString(M + 18, 156, "The trick, in one line")
para(c, "<b>Animate a normal 3D skeleton. Draw each body part once as a flat pixel card. Pin each card to its bone.</b> "
        "The cards inherit 3D motion, lighting and shadows, but read as hand-made pixel art. A tooltip in the video says each card "
        "has a sprite-up axis and a front axis that its pixel cells are drawn against, so cards are oriented per bone and per view, "
        "not just pasted flat to the screen. A frame counter showing x/16 suggests a set of drawn views per part.",
     M + 18, 146, W - 2 * M - 36, P(10.5, INK))
c.showPage()

# ---- 4. Your question
header(c, "Your question", "\"So I won't have to animate hands anymore?\"")
para(c, "<b>Mostly yes — but for a better reason than you might think.</b> You never hand-drew animation frames; your hands are already "
        "driven by code (arm IK + pose library + posture editor). The card approach <b>keeps all of that</b> and only swaps what is drawn "
        "on each bone. What disappears is modelling and tuning 3D body parts, and any future need to draw frame-by-frame sprite sheets.",
     M, 440, W - 2 * M, P(11.5, SUB))
rows_y = [300, 186]
for ri, (label, col, parts) in enumerate([
    ("TODAY", BLUE, ["Pose library\n+ posture editor", "Arm / leg IK\n(procedural)", "19-bone\nSkeleton3D", "Capsules, spheres\n& boxes (~40k tris)"]),
    ("PROPOSED", ORANGE, ["Pose library\n+ posture editor", "Arm / leg IK\n(procedural)", "19-bone\nSkeleton3D", "Pixel cards\n(~34 tris)"]),
]):
    y = rows_y[ri]
    tag(c, M, y + 66, label, col)
    bw = 170
    for j, txt in enumerate(parts):
        x = M + j * (bw + 50)
        last = j == 3
        box(c, x, y, bw, 58, HexColor("#fff4ee") if (last and ri == 1) else CARD, col if last else LINE, lw=1.6 if last else 1)
        lines = txt.split("\n")
        c.setFont("Helvetica-Bold", 11); c.setFillColor(INK)
        c.drawCentredString(x + bw / 2, y + 34, lines[0])
        c.setFont("Helvetica", 10); c.setFillColor(SUB); c.drawCentredString(x + bw / 2, y + 18, lines[1])
        if j < 3: arrow(c, x + bw + 6, y + 29, x + bw + 44, y + 29)
    if ri == 1:
        c.setStrokeColor(AQUA); c.setLineWidth(1.2); c.setDash(3, 3)
        c.roundRect(M - 8, y - 8, 3 * bw + 2 * 50 + 16, 74 + 114, 10, stroke=1, fill=0); c.setDash()
        c.setFont("Helvetica-Bold", 9); c.setFillColor(AQUA); c.drawString(M, y - 21, "UNCHANGED — your existing animation investment carries over")
cx0 = M
box(c, M, 40, (W - 2 * M) / 2 - 9, 100)
c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(M + 16, 120, "What you stop doing")
bullets(c, ["Tweaking capsule radii / sphere sizes to make a body look right",
            "Fighting 3D-mesh hand detail (fingers, grip shape)",
            "Ever needing per-frame sprite sheets for each swing"], M + 16, 112, (W - 2 * M) / 2 - 40, 9.8, 4, SUB, AQUA)
x2 = M + (W - 2 * M) / 2 + 9
box(c, x2, 40, (W - 2 * M) / 2 - 9, 100)
c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(x2 + 16, 120, "What you still do")
bullets(c, ["Pose the skeleton (already done in the posture editor)",
            "Paint a few <b>hand cards</b>: open, paddle grip, reach — swapped by state",
            "Paint each part from ~5 views (mirrored for the other side)"], x2 + 16, 112, (W - 2 * M) / 2 - 40, 9.8, 4, SUB, ORANGE)
c.showPage()

# ---- 5. Alabaster Dawn DNA
header(c, "Reference 2 · Alabaster Dawn (Radical Fish Games)", "The look you want — broken into parts we can build")
para(c, "Fast-paced top-down 2.5D action RPG from the makers of CrossCode, in Steam Early Access since 7 May 2026, built on their own "
        "in-house engine. Below are traits observed in its store screenshots, turned into things we can build in Godot. We copy the "
        "<b>principles</b>, never its art, characters or UI.", M, 446, W - 2 * M, P(10.5, SUB))
traits = [
    (VIOLET, "High fixed 3/4 camera", "Steep, steady view; never orbits. Sprites only need a few facings."),
    (BLUE, "Small, readable sprites", "Characters ~1/12 of screen height; dark outline + strong silhouette."),
    (AQUA, "Saturated, hue-shifted palette", "Shadows go purple/teal, not black. Pink and lilac foliage accents."),
    (YELLOW, "Soft blob shadows", "Simple dark ellipse under every actor anchors them to the ground."),
    (ORANGE, "Bright additive VFX", "White-cyan slash arcs, speed lines, dust puffs, glowing hit flashes."),
    (RED, "Telegraph markers", "Chevrons and rings show where something will land or strike."),
    (HexColor("#e87ba4"), "Framing + vignette", "Darker edges and lit centre pull the eye to the action area."),
    (GRASS_D, "Minimal corner HUD", "Small round icons in corners; the playfield stays clear."),
]
tw_ = (W - 2 * M - 3 * 14) / 4
for i, (col, t, d) in enumerate(traits):
    x = M + (i % 4) * (tw_ + 14); y = 248 if i < 4 else 82
    box(c, x, y, tw_, 150)
    c.setFillColor(col); c.rect(x, y + 142, tw_, 8, stroke=0, fill=1)
    # mini glyph
    gx, gy = x + 18, y + 96
    if i == 0:
        c.setStrokeColor(SUB); c.setLineWidth(1.2); c.line(gx, gy, gx + 60, gy); arrow(c, gx + 50, gy + 34, gx + 30, gy + 4, col)
        c.setFillColor(col); c.circle(gx + 52, gy + 36, 5, stroke=0, fill=1)
    elif i == 1:
        pixel_sprite(c, FRONT, gx, gy - 6, 2.2, "red")
    elif i == 2:
        for k_, hx in enumerate(["#5f9a4a", "#3f7340", "#35585a", "#7c5cc4", "#c6b4f5", "#f2a6c8"]):
            c.setFillColor(HexColor(hx)); c.rect(gx + k_ * 16, gy, 14, 26, stroke=0, fill=1)
    elif i == 3:
        c.setFillColor(Color(0.1, 0.08, 0.2, alpha=0.35)); c.ellipse(gx, gy, gx + 50, gy + 12, stroke=0, fill=1)
        ball(c, gx + 25, gy + 6, 6, 18)
    elif i == 4:
        for k_, al in enumerate((0.2, 0.45, 0.9)):
            c.setStrokeColor(Color(0.4, 0.8, 1, alpha=al)); c.setLineWidth(5 - k_)
            c.arc(gx - 4 + k_ * 3, gy - 14, gx + 70 - k_ * 3, gy + 40, 20, 140)
    elif i == 5:
        c.setStrokeColor(col); c.setLineWidth(1.8); c.ellipse(gx + 10, gy, gx + 60, gy + 14, stroke=1, fill=0)
        c.setFillColor(col)
        for k_ in range(3):
            yb = gy + 18 + k_ * 7; q = c.beginPath(); q.moveTo(gx + 30, yb + 5); q.lineTo(gx + 35, yb); q.lineTo(gx + 40, yb + 5); q.lineTo(gx + 40, yb + 7); q.lineTo(gx + 35, yb + 2); q.lineTo(gx + 30, yb + 7); q.close(); c.drawPath(q, stroke=0, fill=1)
    elif i == 6:
        c.setFillColor(HexColor("#2c2745")); c.rect(gx, gy - 4, 80, 40, stroke=0, fill=1)
        c.setFillColor(HexColor("#6c63a8")); c.ellipse(gx + 14, gy + 2, gx + 66, gy + 30, stroke=0, fill=1)
        c.setFillColor(HexColor("#a99fe0")); c.ellipse(gx + 28, gy + 9, gx + 52, gy + 23, stroke=0, fill=1)
    else:
        c.setFillColor(GRASS_D); c.circle(gx + 8, gy + 20, 9, stroke=0, fill=1); c.circle(gx + 30, gy + 20, 9, stroke=0, fill=1)
        c.setFillColor(HexColor("#ffffff")); c.circle(gx + 8, gy + 20, 4, stroke=0, fill=1); c.circle(gx + 30, gy + 20, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(x + 14, y + 66, t)
    para(c, d, x + 14, y + 58, tw_ - 28, P(9.3, SUB))
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(M, 60, "Illustrative glyphs only. Engine and release facts: GamingOnLinux, RPGFan, Steam store page (see Sources).")
c.showPage()

# ---- 6. Translating to pickleball
header(c, "Art direction", "What that means on a pickleball court")
court_scene(c, M, 60, 420, 380)
x0 = M + 450
para(c, "<b>Target frame (original mockup)</b>", x0, 440, 420, P(13, INK))
items = [
    "<b>Camera:</b> raise pitch from behind-player view to a steep 3/4 (about 50-60 degrees) with a narrow FOV, so the court reads almost "
    "isometric but the ball still flies in real 3D. Kept as an A/B option until playtests agree.",
    "<b>Near team seen from behind, far team from the front.</b> That decides which card views need the most art.",
    "<b>Ball height readability:</b> high cameras flatten height. Fix with the ball's ground shadow (shader already exists), "
    "a height line, and a landing ring + chevrons like a combat telegraph.",
    "<b>Court world:</b> park setting — grass tufts, flower specks, pastel trees, dirt apron — as low-poly 3D with nearest-filtered "
    "pixel textures and baked colour. Cheap to draw.",
    "<b>Effects:</b> swing arc, ball trail, impact flash, bounce ring stay 3D, styled bright and additive.",
    "<b>HUD:</b> one compact score pill in a corner; everything else gets out of the way.",
]
bullets(c, items, x0, 414, W - M - x0, 10.2, 7, SUB)
c.showPage()

# ---- 7. Options compared
header(c, "Options", "Four ways to get there")
opts = ["A  Bone cards\n(the short's technique)", "B  Pre-rendered\nsprite sheets", "C  Low-poly 3D +\npixelation shader", "D  Keep meshes,\noptimise only"]
crit = [("Keeps procedural IK & poses", [2, 0, 2, 2]),
        ("Paddle contact stays exact", [2, 0, 2, 2]),
        ("Alabaster-style pixel look", [2, 2, 1, 0]),
        ("Art effort", [1, 0, 1, 2]),
        ("GPU cost on iPhone", [2, 2, 1, 1]),
        ("Engineering risk", [1, 1, 2, 2]),
        ("Gameplay unchanged", [2, 1, 2, 2])]
tx, ty = M + 220, 410
colw = (W - M - tx) / 4
for j, o in enumerate(opts):
    x = tx + j * colw
    if j == 0:
        c.setFillColor(HexColor("#fff4ee")); c.roundRect(x + 4, 96, colw - 8, 352, 8, stroke=0, fill=1)
        tag(c, x + 12, 424, "RECOMMENDED", ORANGE)
    l1, l2 = o.split("\n")
    c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(x + 14, ty - 12, l1)
    c.setFont("Helvetica", 10); c.setFillColor(SUB); c.drawString(x + 30, ty - 26, l2)
labels = {2: ("Strong", AQUA), 1: ("OK", YELLOW), 0: ("Weak", RED)}
for i, (name, vals) in enumerate(crit):
    y = ty - 64 - i * 38
    c.setStrokeColor(LINE); c.setLineWidth(1); c.line(M, y - 12, W - M, y - 12)
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(INK); c.drawString(M, y, name)
    for j, v in enumerate(vals):
        x = tx + j * colw + 14
        lab, col = labels[v]
        for k_ in range(3):
            c.setFillColor(col if k_ < v + 1 else LINE); c.roundRect(x + k_ * 15, y - 2, 12, 12, 3, stroke=0, fill=1)
        c.setFont("Helvetica", 9.5); c.setFillColor(SUB); c.drawString(x + 52, y, lab)
para(c, "<b>Why not B?</b> Full-body sprite sheets (Dead Cells-style pre-render) bake each swing into frames, so the procedural IK, "
        "the posture editor and exact paddle placement are lost. <b>Why not only C?</b> It keeps 3D meshes, so it improves the look less and "
        "saves little GPU time. <b>D is still worth doing first</b> — it is Phase 0 below and helps whatever we pick.",
     M, 82, W - 2 * M, P(10, SUB))
c.showPage()

# ---- 8. Architecture
header(c, "Architecture", "Two layers: pixel cards on top of a 3D game")
# left: layers stack
lx, lw_ = M, 520
layers = [
    (ORANGE, "Character layer (NEW)", "Sprite cards on BoneAttachment3D nodes · facing picker · hand-state swap · team palette swap"),
    (VIOLET, "Pose layer (UNCHANGED)", "Skeleton3D (19 bones) · arm/leg IK · pose library · posture editor"),
    (BLUE, "3D world + effects (UNCHANGED)", "Court · net · ball · trail · bounce decals · impact bursts · shadows · 3D paddle"),
    (AQUA, "Pixel viewport (NEW)", "3D renders into a low-res SubViewport, nearest-neighbour upscale to screen"),
    (NIGHT2, "Post (NEW, light)", "Vignette · colour grade · optional glow (check support on device)"),
]
for i, (col, t, d) in enumerate(layers):
    y = 384 - i * 66
    box(c, lx, y, lw_, 54)
    c.setFillColor(col); c.roundRect(lx, y, 10, 54, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(lx + 24, y + 32, t)
    c.setFont("Helvetica", 9.5); c.setFillColor(SUB); c.drawString(lx + 24, y + 14, d)
    if i < 4: arrow(c, lx + lw_ / 2, y - 2, lx + lw_ / 2, y - 10, MUTED, 1.2, 5)
# right: node tree
rx = M + 560
box(c, rx, 60, W - M - rx, 380, HexColor("#f4f2ff"), HexColor("#d9d3f5"))
c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(rx + 16, 416, "Per-player node tree (sketch)")
tree = [(0, "Player (CharacterBody3D)", INK), (1, "Skeleton3D", VIOLET),
        (2, "BoneAttachment3D  Head", SUB), (3, "Card  head  [5 views]", ORANGE),
        (2, "BoneAttachment3D  Chest", SUB), (3, "Card  torso  [5 views]", ORANGE),
        (2, "BoneAttachment3D  RightHand", SUB), (3, "Card  hand  [open|grip|reach]", ORANGE),
        (3, "Paddle  (stays 3D mesh)", BLUE), (2, "... 14 more bones", MUTED),
        (1, "CardSorter (1 script)", ORANGE), (1, "BlobShadow (existing)", BLUE)]
for i, (lvl, t, col) in enumerate(tree):
    y = 392 - i * 25
    x = rx + 22 + lvl * 18
    if lvl: c.setStrokeColor(LINE); c.setLineWidth(1); c.line(x - 10, y + 4, x - 3, y + 4)
    c.setFillColor(col); c.circle(x + 2, y + 4, 3, stroke=0, fill=1)
    c.setFont("Helvetica-Bold" if col in (ORANGE, VIOLET) else "Helvetica", 9.8); c.setFillColor(INK); c.drawString(x + 10, y, t)
para(c, "One script per player picks each card's view and draw order each frame — a cheap loop over ~17 cards.",
     rx + 16, 92, W - M - rx - 32, P(9, SUB))
c.setFont("Helvetica", 9); c.setFillColor(MUTED)
c.drawString(M, 60, "Godot pieces: Skeleton3D, BoneAttachment3D, Sprite3D or quad MeshInstance3D, SubViewport, texture_filter = nearest.")
c.showPage()

# ---- 9. Card spec
header(c, "Character cards", "How a pixel player is built")
# left: facings
box(c, M, 230, 520, 200)
c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(M + 16, 408, "5 drawn views, 3 mirrored = 8 directions")
views = [("Front", FRONT, False, True), ("3/4 F", SIDE, False, True), ("Side", SIDE, False, True), ("3/4 B", BACK, False, True), ("Back", BACK, False, True),
         ("Side", SIDE, True, False), ("3/4 F", SIDE, True, False), ("3/4 B", BACK, True, False)]
for i, (n, rows, flip, drawn) in enumerate(views):
    x = M + 22 + i * 61
    pixel_sprite(c, rows, x, 280, 3.6, "blue", flip)
    c.setFont("Helvetica-Bold" if drawn else "Helvetica", 8.5); c.setFillColor(ORANGE if drawn else MUTED)
    c.drawCentredString(x + 21, 256, n); c.drawCentredString(x + 21, 244, "drawn" if drawn else "mirror")
# right: hand states
box(c, M + 540, 230, W - 2 * M - 540, 200)
c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(M + 556, 408, "Hand cards swap by state")
hs = [("Ready", "open"), ("Swing", "grip"), ("Reach", "stretch")]
hc = pal("blue")
for i, (n, d) in enumerate(hs):
    x = M + 566 + i * 98; y = 290
    c.setFillColor(hc["k"]); c.rect(x - 2, y - 2, 40, 44, stroke=0, fill=1)
    c.setFillColor(hc["s"]); c.rect(x, y, 36, 40, stroke=0, fill=1)
    c.setFillColor(hc["S"])
    if i == 0:
        for f in range(4): c.rect(x + 2 + f * 9, y + 26, 6, 14, stroke=0, fill=1)
    elif i == 1:
        c.rect(x, y + 16, 36, 8, stroke=0, fill=1); paddle3d(c, x + 18, y + 48, 1.4, 0)
    else:
        for f in range(4): c.rect(x + 2 + f * 9, y + 28, 6, 12, stroke=0, fill=1)
        c.rect(x + 30, y + 10, 6, 14, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10); c.setFillColor(INK); c.drawCentredString(x + 18, 262, n)
    c.setFont("Helvetica", 8.5); c.setFillColor(SUB); c.drawCentredString(x + 18, 249, d)
rules = [
    ("Paddle stays a 3D mesh", "Its face angle decides shot direction, so the player must read it exactly. Style it with a pixel texture."),
    ("Alpha-scissor, not alpha-blend", "Hard pixel edges sort correctly in the depth buffer and can cast shadows; blended cards flicker."),
    ("Draw order by bone + camera", "Near-side arm in front of torso, far-side arm behind, with a small per-part depth bias."),
    ("Team colours by palette swap", "Paint one set; a tiny shader swaps shirt/shade colours for blue/red (and future skins)."),
    ("1-px dark outline baked in", "Keeps small sprites readable at phone size, as in the reference style."),
    ("Debug toggles like the short", "Cards / Bones / Card axes / Mesh in the posture editor so problems are visible."),
]
cw3 = (W - 2 * M - 2 * 14) / 3
for i, (t, d) in enumerate(rules):
    x = M + (i % 3) * (cw3 + 14); y = 128 if i < 3 else 52
    box(c, x, y, cw3, 66)
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(INK); c.drawString(x + 14, y + 46, t)
    para(c, d, x + 14, y + 40, cw3 - 28, P(9, SUB))
c.showPage()

exec(open('/private/tmp/claude-501/-Users-arjomagno--claude-spares-spare-NyRAqp/da740810-5ae9-4e29-a263-0cde91478894/scratchpad/pages_art.py').read())

# ---- 10. Effects stay 3D
header(c, "Effects", "Effects stay 3D — restyled to match")
fxs = [
    ("Ball trail", "exists · fx/ball_trail.gd", "Thicker, brighter streak; fades to warm white.", True),
    ("Impact burst", "exists · fx/impact_burst.gd", "Pixel-star flash + 2-3 frame hit spark on paddle contact.", True),
    ("Bounce decal", "exists · fx/bounce_decal.gd", "Expanding ring + dust puff on the court surface.", True),
    ("Ground shadows", "exists · fx/ground_shadows.gd", "Keep blob shadows; they now carry ball-height reading.", True),
    ("Camera shake", "exists · camera/camera_shake.gd", "Tiered: dink = none, drive = light, smash = strong.", True),
    ("FX pool", "exists · fx/fx_pool.gd", "Reuse for all new effects — no per-hit allocations.", True),
    ("Swing arc", "new", "Additive ribbon along the paddle path for 0.15 s.", False),
    ("Landing marker", "new", "Ring + chevrons where the ball will land (readability).", False),
    ("Footwork dust", "new", "Tiny puffs on split-step, lunge and stop.", False),
    ("Speed lines", "new", "On dives and fast lateral shuffles only.", False),
    ("Hit-stop", "exists · time/time_scale_manager.gd", "Tune to 40-60 ms on hard hits, paired with the smash flash.", True),
    ("Kitchen glow", "new", "Non-volley zone tints softly when a player steps in.", False),
]
cw4 = (W - 2 * M - 3 * 12) / 4
for i, (n, s, d, exists) in enumerate(fxs):
    x = M + (i % 4) * (cw4 + 12); y = 336 - (i // 4) * 116
    box(c, x, y, cw4, 102)
    tag(c, x + 12, y + 74, "EXISTS" if exists else "NEW", BLUE if exists else ORANGE)
    c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x + 12, y + 56, n)
    c.setFont("Helvetica", 8); c.setFillColor(MUTED); c.drawString(x + 12, y + 44, s if exists else "")
    para(c, d, x + 12, y + 38, cw4 - 24, P(9.2, SUB))
c.setFont("Helvetica", 9); c.setFillColor(MUTED)
c.drawString(M, 86, "Note: the Compatibility renderer has no compute shaders, so GPUParticles do not work there. Use CPUParticles3D or pooled meshes (as fx_pool does).")
c.showPage()

exec(open('/private/tmp/claude-501/-Users-arjomagno--claude-spares-spare-NyRAqp/da740810-5ae9-4e29-a263-0cde91478894/scratchpad/pages_more.py').read())

# ---- 11. Performance
header(c, "Performance", "Where the frame time goes today — and after")
# chart 1: tris per player by part (measured with Godot 4 default primitives)
box(c, M, 70, 420, 360)
c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(M + 18, 406, "Triangles per player, by body part")
c.setFont("Helvetica", 9); c.setFillColor(SUB); c.drawString(M + 18, 391, "Measured in Godot from the default primitive meshes the bodies use")
data = [("8 limb capsules", 27648), ("2 eye spheres", 8448), ("Head sphere", 4224), ("Torso, hips, hands, feet", 72)]
mx_ = 28000; bx0 = M + 160; bwmax = 220
for i, (n, v) in enumerate(data):
    y = 340 - i * 52
    c.setFont("Helvetica", 10); c.setFillColor(INK); c.drawRightString(bx0 - 10, y + 6, n)
    wv = max(2, bwmax * v / mx_)
    c.setFillColor(BLUE); c.roundRect(bx0, y, wv, 18, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10); c.setFillColor(INK); c.drawString(bx0 + wv + 6, y + 5, "{:,}".format(v))
c.setStrokeColor(LINE); c.line(bx0, 140, bx0, 360)
para(c, "<b>Total ~40,400 per player · ~161,600 for 4 players</b>, before the sun-shadow pass draws casters again. "
        "Eyes alone cost twice the head: two tiny spheres at 64x32 segments.", M + 18, 128, 384, P(9.8, SUB))
# chart 2: before/after
x2 = M + 440
box(c, x2, 250, W - M - x2, 180)
c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x2 + 18, 406, "Player-body triangles per frame, 4 players")
rows2 = [("Today", 161568, BLUE), ("Phase 0: fewer segments", 8992, BLUE), ("Bone cards", 136, ORANGE)]
for i, (n, v, col) in enumerate(rows2):
    y = 360 - i * 36
    c.setFont("Helvetica", 9.8); c.setFillColor(INK); c.drawString(x2 + 18, y + 4, n)
    wv = max(3, 210 * v / 161568)
    c.setFillColor(col); c.roundRect(x2 + 170, y, wv, 16, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.8); c.setFillColor(INK); c.drawString(x2 + 170 + wv + 6, y + 4, "{:,}".format(v))
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(x2 + 18, 262, "Phase 0 = head 16x8, eyes 8x4, capsules 12x2 segments (measured).")
box(c, x2, 70, W - M - x2, 166)
c.setFont("Helvetica-Bold", 12); c.setFillColor(INK); c.drawString(x2 + 18, 212, "Pixels shaded per frame (iPhone 2556 x 1179 screen)")
rows3 = [("Native", 3.01, BLUE), ("1/2 scale", 0.75, BLUE), ("1/3 pixel view", 0.33, ORANGE)]
for i, (n, v, col) in enumerate(rows3):
    y = 172 - i * 34
    c.setFont("Helvetica", 9.8); c.setFillColor(INK); c.drawString(x2 + 18, y + 4, n)
    wv = 210 * v / 3.01
    c.setFillColor(col); c.roundRect(x2 + 170, y, wv, 16, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.8); c.setFillColor(INK); c.drawString(x2 + 170 + wv + 6, y + 4, "%.2f M" % v)
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(x2 + 18, 82, "Fill rate is usually the main GPU cost on retina phones. Confirm on device.")
c.showPage()

# ---- 12. Performance checklist
header(c, "Performance", "Performance plan — measure, then cut")
items_l = [
    ("Baseline first", "Use the PerfMonitor already on the iphone-duos branch (spike log, F3 graph, report) on a real iPhone. Record fps, frame time, spikes during a 4-player rally."),
    ("Cut primitive segments", "Head, eyes, capsules down to the Phase 0 counts: about 94% fewer body triangles with no visible change at phone size."),
    ("Share materials", "Each body part creates its own StandardMaterial3D. Share one per team/part so the renderer can switch state less often."),
    ("Shadow budget", "The Compatibility renderer draws lights with shadows in extra passes. Players and paddle can rely on the blob shadows that already exist; test turning the sun shadow off on iPhone."),
]
items_r = [
    ("Low-res pixel viewport", "Render 3D to a SubViewport at 1/3 resolution with nearest-neighbour upscale. This gives the pixel look and shades ~1/9 of the pixels."),
    ("Unshaded, baked world", "Court and park use unshaded materials with lighting painted into textures. No real-time lights on scenery."),
    ("No GPU particles", "The Compatibility renderer has no compute shaders. Keep the pooled meshes from fx_pool.gd or CPUParticles3D."),
    ("Debug off in builds", "Keep the awareness grid, debug visuals and per-frame prints out of release builds (see CLAUDE.md logging rule)."),
]
for colx, its in ((M, items_l), (W / 2 + 9, items_r)):
    for i, (t, d) in enumerate(its):
        y = 352 - i * 88
        box(c, colx, y, W / 2 - M - 9, 76)
        c.setFillColor(ORANGE if colx > M else BLUE); c.circle(colx + 22, y + 52, 10, stroke=0, fill=1)
        c.setFont("Helvetica-Bold", 10); c.setFillColor(HexColor("#ffffff"))
        c.drawCentredString(colx + 22, y + 48.5, str(i + 1 + (4 if colx > M else 0)))
        c.setFont("Helvetica-Bold", 11.5); c.setFillColor(INK); c.drawString(colx + 42, y + 48, t)
        para(c, d, colx + 42, y + 40, W / 2 - M - 9 - 58, P(9.2, SUB))
c.setFont("Helvetica", 9); c.setFillColor(MUTED)
c.drawString(M, 40, "Draw-call figures elsewhere in this document are estimates from node counts (~17 mesh instances per player). Verify them with Godot's monitors.")
c.showPage()

# ---- 13. Other improvements (gameplay locked)
header(c, "Beyond graphics", "Other improvements — same gameplay")
para(c, "<b>Locked:</b> shot_physics.gd, ball flight, rally_scorer.gd, AI decision logic, hitting windows and input timing. "
        "Everything below changes how the game <b>feels and reads</b>, not how it scores or plays.", M, 446, W - 2 * M, P(11, SUB))
groups = [
    (ORANGE, "Game feel", ["Hit-stop on hard hits (visual only)", "Tiered camera shake by shot power", "Squash-and-stretch on cards at contact", "Swing anticipation frames from poses"]),
    (BLUE, "Readability", ["Ball ground shadow + height line", "Landing ring and chevrons", "Kitchen tint when a player steps in", "Serve-side and server indicator"]),
    (AQUA, "Audio", ["Distinct pop for dink / drive / smash", "Footstep scuffs synced to dust", "Light park ambience + crowd swell on long rallies", "Hit pitch varies with shot power"]),
    (VIOLET, "HUD & flow", ["Corner score pill (score-score-server)", "Round icons for pause / settings", "Short pixel-style rally banners", "Classic / Pixel art toggle in Settings"]),
]
gw = (W - 2 * M - 3 * 14) / 4
for i, (col, t, its) in enumerate(groups):
    x = M + i * (gw + 14)
    box(c, x, 172, gw, 226)
    c.setFillColor(col); c.roundRect(x, 390, gw, 8, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 14); c.setFillColor(INK); c.drawString(x + 16, 366, t)
    bullets(c, its, x + 16, 348, gw - 32, 10.2, 10, SUB, col)
box(c, M, 48, W - 2 * M, 112, HexColor("#f4f2ff"), HexColor("#d9d3f5"))
c.setFont("Helvetica-Bold", 10.5); c.setFillColor(VIOLET); c.drawString(M + 16, 138, "LATER: GAMEPLAY v2 (SEPARATE PLAN, AFTER THE VISUAL UPDATE SHIPS)")
later = [("AI difficulty tiers", "Easy / club / pro, tuned via existing AI brain parameters"),
         ("More shot types", "Lob, Erne, around-the-post, as new rules-tested shots"),
         ("Practice drills", "Dinking and serve-return drills using the same court"),
         ("Cosmetics", "Outfits and paddles come almost free with palette-swap cards")]
lw4 = (W - 2 * M - 32) / 4
for k_, (t_, d_) in enumerate(later):
    xx = M + 16 + k_ * lw4
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(INK); c.drawString(xx, 116, t_)
    para(c, d_, xx, 110, lw4 - 16, P(9.2, SUB))
c.showPage()

# ---- 14. Roadmap
header(c, "Roadmap", "Six phases, each shippable on its own")
phases = [
    ("0", "Quick wins + baseline", 0, 1, BLUE, "Perf baseline on device; fewer mesh segments; shared materials; shadow budget."),
    ("1", "Camera + pixel viewport", 1, 2, VIOLET, "Low-res SubViewport, nearest upscale, 3/4 camera A/B toggle, vignette."),
    ("2", "Card prototype (1 player)", 3, 2, ORANGE, "Placeholder cards on bones; view picker; draw order; hand states; debug toggles."),
    ("3", "Art pass", 5, 4, ORANGE, "Final cards x 5 views; team palette swap; park court with baked pixel textures."),
    ("4", "FX + game feel", 8, 2, AQUA, "Effects sprite sheet, landing marker, slow-mo restyle with smooth blur, shake tiers, sounds."),
    ("5", "HUD, polish, ship", 10, 2, HexColor("#e87ba4"), "Pixel UI kit, controls restyle, Classic/Pixel toggle, final on-device perf check."),
]
gx0, gx1 = M + 250, W - M
weeks = 12
unit = (gx1 - gx0) / weeks
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
for wk in range(weeks + 1):
    xx = gx0 + wk * unit
    c.setStrokeColor(LINE); c.setLineWidth(0.8); c.line(xx, 120, xx, 440)
    if wk < weeks: c.drawCentredString(xx + unit / 2, 446, "W%d" % (wk + 1))
for i, (n, t, s, d, col, desc) in enumerate(phases):
    y = 404 - i * 52
    c.setFillColor(col); c.circle(M + 12, y + 8, 11, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(HexColor("#ffffff")); c.drawCentredString(M + 12, y + 4.5, n)
    c.setFont("Helvetica-Bold", 11); c.setFillColor(INK); c.drawString(M + 32, y + 10, t)
    para(c, desc, M + 32, y + 2, 205, P(8.3, SUB, 10.5))
    c.setFillColor(col); c.roundRect(gx0 + s * unit + 2, y - 2, d * unit - 4, 22, 6, stroke=0, fill=1)
box(c, M, 46, W - 2 * M, 60, HexColor("#eefaf4"), HexColor("#bfe8d3"))
c.setFont("Helvetica-Bold", 10.5); c.setFillColor(AQUA); c.drawString(M + 16, 84, "GATE AFTER EVERY PHASE")
para(c, "Test suites pass unchanged (shot physics, rally scorer, player hitting) · headless smoke check clean · on-device fps no worse than "
        "the Phase 0 baseline · Classic mode still works. Week counts are rough sizing for planning, not commitments.",
     M + 16, 78, W - 2 * M - 32, P(9.5, SUB))
c.showPage()

# ---- 15. Risks & metrics
header(c, "Risks", "What could go wrong — and how we would know it is working")
risks = [
    ("Cards flicker where limbs overlap", "Alpha-scissor + per-part depth bias + a fixed sort by bone and camera side."),
    ("Paddle angle hard to read", "Paddle stays a 3D mesh; face tinted, with a thin rim highlight."),
    ("High camera hides ball height", "Ground shadow, height line, landing marker; keep the camera as an A/B toggle until playtests agree."),
    ("Art cost balloons", "5 views + mirroring, palette swaps for teams, placeholder cards first so code never waits on art."),
    ("Glow / post not in Compatibility", "Fake glow with additive sprites; test each post effect on device before relying on it."),
    ("Godot know-how is thin", "Few public guides for this exact setup (forum threads are open questions). Prototype one player early in Phase 2."),
]
for i, (r, m) in enumerate(risks):
    y = 404 - i * 50
    box(c, M, y, 560, 42)
    c.setFillColor(RED); c.roundRect(M, y, 6, 42, 3, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10.5); c.setFillColor(INK); c.drawString(M + 18, y + 25, r)
    c.setFont("Helvetica", 9.2); c.setFillColor(SUB); c.drawString(M + 18, y + 10, m)
rx = M + 580
box(c, rx, 104, W - M - rx, 342, HexColor("#f4f2ff"), HexColor("#d9d3f5"))
c.setFont("Helvetica-Bold", 13); c.setFillColor(INK); c.drawString(rx + 16, 420, "Success metrics")
mets = [("60 fps", "steady on the target iPhone in 4-player rallies"),
        ("< 10", "draw calls for all player bodies"),
        ("0", "gameplay test regressions"),
        ("Fewer", "PerfMonitor spikes than the Phase 0 baseline"),
        ("Better", "landing-spot guesses in a 5-person playtest")]
for i, (big, small) in enumerate(mets):
    y = 372 - i * 56
    c.setFont("Helvetica-Bold", 20); c.setFillColor(VIOLET); c.drawString(rx + 16, y, big)
    para(c, small, rx + 16, y - 6, W - M - rx - 32, P(9.3, SUB))
c.showPage()

# ---- 16. Sources
header(c, "Sources", "Research notes and links")
srcs = [
    ("Cor Mundi Studios - \"My Gamedev Secret on How I Render Stylized 2.5D Characters\" (YouTube Short)", "https://www.youtube.com/shorts/84clZXpwRc0"),
    ("Alabaster Dawn - Steam store page (screenshots, description, release date)", "https://store.steampowered.com/app/3110760/Alabaster_Dawn/"),
    ("GamingOnLinux - Alabaster Dawn enters Early Access (custom engine)", "https://www.gamingonlinux.com/2026/05/alabaster-dawn-from-the-developers-of-the-excellent-crosscode-is-now-in-early-access/"),
    ("RPGFan - Alabaster Dawn preview (top-down 2.5D, animation)", "https://www.rpgfan.com/2025/09/18/alabaster-dawn-gorgeous-pixel-art-rpg/"),
    ("80.lv - Alabaster Dawn features (fast-paced combat; DMC / Kingdom Hearts / CrossCode influences)", "https://80.lv/articles/a-glimpse-into-the-latest-features-of-this-beautiful-upcoming-arpg"),
    ("Godot forum - Alabaster Dawn engine discussion (not Godot)", "https://forum.godotengine.org/t/alabaster-dawn-in-early-access/138343"),
    ("Godot forum - Attaching 2D pixel sprites to a 3D bone structure in Godot 4", "https://forum.godotengine.org/t/attaching-2d-pixel-sprites-to-a-3d-bone-structure-in-godot-4/71223"),
    ("Godot docs - BoneAttachment3D", "https://docs.godotengine.org/en/4.3/classes/class_boneattachment3d.html"),
    ("PaperSkeleton - Godot addon rendering Skeleton2D rigs in 3D", "https://bunkwire2x8.itch.io/paperskeleton"),
    ("Godot docs - Internal rendering architecture (Compatibility renderer, shadows as extra passes)", "https://docs.godotengine.org/en/4.6/engine_details/architecture/internal_rendering_architecture.html"),
    ("HD-2D overview (pixel sprites in 3D worlds)", "https://en.wikipedia.org/wiki/HD-2D"),
    ("80.lv - Dead Cells character art pipeline (3D to pixel pre-render)", "https://80.lv/articles/case-study-dead-cells-character-art-pipeline"),
]
y = 440
for t, u in srcs:
    c.setFont("Helvetica-Bold", 9.8); c.setFillColor(INK); c.drawString(M, y, t)
    c.setFont("Helvetica", 8.5); c.setFillColor(BLUE); c.drawString(M, y - 12, u)
    c.linkURL(u, (M, y - 15, M + c.stringWidth(u, "Helvetica", 8.5), y - 4), relative=0)
    y -= 30
c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
c.drawString(M, 36, "Codebase numbers: Godot primitive triangle counts measured headless; node counts from player_body_builder.gd, arm/leg scenes (iphone-duos branch).")
c.showPage()
c.save()
print("ok", page_no[0])
