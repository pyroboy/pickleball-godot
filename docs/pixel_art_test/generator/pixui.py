"""Pixel UI toolkit: 5x7 bitmap font, bevelled panels without black outlines, controls, banners."""
import numpy as np
from math import cos, sin, pi, atan2
from PIL import Image, ImageDraw

def hx(h):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
C = {k: hx(v) for k, v in dict(
    n0='#121022', n1='#1d1a30', n2='#2b2746', n3='#3e3863', n4='#5a5290', txt='#f4f1ea', sub='#b8b0d8',
    blue='#3f90e8', blue_d='#2d62b9', blue_l='#86c8ff', blue_dd='#203f80',
    red='#ef5b53', red_d='#c13b4f', red_l='#ffa08f', red_dd='#7e2a46',
    ball='#d6f23c', ball_d='#a0c42b', gold='#ffd548', gold_d='#e0a032', gold_l='#fff3a8',
    cyan='#7fe3ff', cyan_d='#3aa6d8', green='#3fcf8e', green_d='#26966a', white='#ffffff').items()}

F = {
'A': "01110 10001 10001 11111 10001 10001 10001", 'B': "11110 10001 10001 11110 10001 10001 11110",
'C': "01110 10001 10000 10000 10000 10001 01110", 'D': "11110 10001 10001 10001 10001 10001 11110",
'E': "11111 10000 10000 11110 10000 10000 11111", 'F': "11111 10000 10000 11110 10000 10000 10000",
'G': "01110 10001 10000 10111 10001 10001 01111", 'H': "10001 10001 10001 11111 10001 10001 10001",
'I': "111 010 010 010 010 010 111", 'J': "00111 00010 00010 00010 00010 10010 01100",
'K': "10001 10010 10100 11000 10100 10010 10001", 'L': "10000 10000 10000 10000 10000 10000 11111",
'M': "10001 11011 10101 10101 10001 10001 10001", 'N': "10001 10001 11001 10101 10011 10001 10001",
'O': "01110 10001 10001 10001 10001 10001 01110", 'P': "11110 10001 10001 11110 10000 10000 10000",
'Q': "01110 10001 10001 10001 10101 10010 01101", 'R': "11110 10001 10001 11110 10100 10010 10001",
'S': "01111 10000 10000 01110 00001 00001 11110", 'T': "11111 00100 00100 00100 00100 00100 00100",
'U': "10001 10001 10001 10001 10001 10001 01110", 'V': "10001 10001 10001 10001 10001 01010 00100",
'W': "10001 10001 10001 10101 10101 10101 01010", 'X': "10001 10001 01010 00100 01010 10001 10001",
'Y': "10001 10001 01010 00100 00100 00100 00100", 'Z': "11111 00001 00010 00100 01000 10000 11111",
'0': "01110 10001 10011 10101 11001 10001 01110", '1': "010 110 010 010 010 010 111",
'2': "01110 10001 00001 00010 00100 01000 11111", '3': "11110 00001 00001 01110 00001 00001 11110",
'4': "00010 00110 01010 10010 11111 00010 00010", '5': "11111 10000 11110 00001 00001 10001 01110",
'6': "00110 01000 10000 11110 10001 10001 01110", '7': "11111 00001 00010 00100 01000 01000 01000",
'8': "01110 10001 10001 01110 10001 10001 01110", '9': "01110 10001 10001 01111 00001 00010 01100",
' ': "00 00 00 00 00 00 00", '-': "000 000 000 111 000 000 000", '!': "1 1 1 1 1 0 1",
'.': "0 0 0 0 0 0 1", ':': "0 0 1 0 0 1 0", '/': "001 001 010 010 010 100 100",
'+': "000 000 010 111 010 000 000", '?': "01110 10001 00001 00010 00100 00000 00100",
'%': "11001 11010 00010 00100 01000 01011 10011", "'": "1 1 0 0 0 0 0", 'x': "000 000 101 010 101 000 000",
}
GLY = {k: [r for r in v.split()] for k, v in F.items()}

def text_w(s, sc=1):
    return sum((len(GLY.get(ch, GLY['?'])[0]) + 1) * sc for ch in s.upper()) - sc

def text(im, x, y, s, col, sc=1, shadow=None):
    px = im.load()
    W, H = im.size
    def put(xx, yy, c):
        if 0 <= xx < W and 0 <= yy < H: px[xx, yy] = c + (255,)
    for pass_, c in ((0, shadow), (1, col)):
        if c is None: continue
        off = 1 if pass_ == 0 else 0
        cx = x
        for ch in s.upper():
            g = GLY.get(ch, GLY['?'])
            for r, row in enumerate(g):
                for k, bit in enumerate(row):
                    if bit == '1':
                        for a in range(sc):
                            for b in range(sc): put(cx + k * sc + a, y + r * sc + b + off * sc, c)
            cx += (len(g[0]) + 1) * sc
    return text_w(s, sc)

def ctext(im, cx, y, s, col, sc=1, shadow=None):
    return text(im, int(cx - text_w(s, sc) / 2), y, s, col, sc, shadow)

def panel(im, x0, y0, x1, y1, fill=None, top=None, bot=None, cut=2):
    fill = fill or C['n1']; top = top or C['n3']; bot = bot or C['n0']
    d = ImageDraw.Draw(im)
    d.rectangle([x0, y0, x1, y1], fill=fill + (235,))
    d.line([x0 + cut, y0, x1 - cut, y0], fill=top + (255,))
    d.line([x0 + cut, y1, x1 - cut, y1], fill=bot + (255,))
    d.line([x0, y0 + cut, x0, y1 - cut], fill=top + (255,))
    d.line([x1, y0 + cut, x1, y1 - cut], fill=bot + (255,))
    px = im.load()
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        for i in range(cut):
            for j in range(cut - i):
                px[cx + sx * i, cy + sy * j] = (0, 0, 0, 0)
        px[cx + sx * 1, cy + sy * 1] = (top if sy > 0 else bot) + (255,)

def disc(im, cx, cy, r, col, a=255):
    d = ImageDraw.Draw(im); d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (a,))

def ring(im, cx, cy, r, col, w=1, a=255):
    d = ImageDraw.Draw(im); d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col + (a,), width=w)

def arc_fill(im, cx, cy, r0, r1, a0, a1, col, a=255):
    px = im.load(); W, H = im.size
    for yy in range(int(cy - r1) - 1, int(cy + r1) + 2):
        for xx in range(int(cx - r1) - 1, int(cx + r1) + 2):
            dx, dy = xx + 0.5 - cx, yy + 0.5 - cy
            rr = (dx * dx + dy * dy) ** 0.5
            if r0 <= rr <= r1:
                ang = (atan2(dy, dx) * 180 / pi + 360) % 360
                ok = (a0 <= ang <= a1) if a0 <= a1 else (ang >= a0 or ang <= a1)
                if ok and 0 <= xx < W and 0 <= yy < H: px[xx, yy] = col + (a,)

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
def dither_alpha(alpha):
    """alpha float array -> bool mask using ordered dithering."""
    H, W = alpha.shape
    th = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    return alpha > th

# ---------- icons ----------
def icon_pause(im, cx, cy, col):
    d = ImageDraw.Draw(im); d.rectangle([cx - 3, cy - 3, cx - 2, cy + 3], fill=col + (255,)); d.rectangle([cx + 1, cy - 3, cx + 2, cy + 3], fill=col + (255,))
def icon_book(im, cx, cy, col):
    d = ImageDraw.Draw(im)
    d.line([cx - 4, cy - 2, cx - 1, cy - 3], fill=col + (255,)); d.line([cx + 4, cy - 2, cx + 1, cy - 3], fill=col + (255,))
    d.line([cx - 4, cy - 2, cx - 4, cy + 3], fill=col + (255,)); d.line([cx + 4, cy - 2, cx + 4, cy + 3], fill=col + (255,))
    d.line([cx, cy - 3, cx, cy + 3], fill=col + (255,)); d.line([cx - 4, cy + 3, cx - 1, cy + 2], fill=col + (255,)); d.line([cx + 4, cy + 3, cx + 1, cy + 2], fill=col + (255,))
def icon_ball(im, cx, cy, r=3):
    disc(im, cx, cy, r, C['ball']); im.load()[cx - 1, cy - 1] = C['gold_l'] + (255,); im.load()[cx + 1, cy + 1] = C['ball_d'] + (255,)
def icon_paddle(im, cx, cy, col=None):
    d = ImageDraw.Draw(im); d.ellipse([cx - 3, cy - 5, cx + 3, cy + 2], fill=(col or C['gold']) + (255,)); d.line([cx, cy + 2, cx, cy + 5], fill=C['n4'] + (255,))

# ---------- components ----------
def score_pill(im, cx, y, a, b, srv, serving_blue=True):
    w = 92; x0 = cx - w // 2
    panel(im, x0, y, x0 + w, y + 18)
    disc(im, x0 + 9, y + 9, 5, C['blue']); im.load()[x0 + 8, y + 7] = C['blue_l'] + (255,)
    disc(im, x0 + w - 9, y + 9, 5, C['red']); im.load()[x0 + w - 10, y + 7] = C['red_l'] + (255,)
    s = '%d - %d - %d' % (a, b, srv)
    ctext(im, cx, y + 6, s, C['txt'], 1, C['n0'])
    # server chevron under serving team
    sx = x0 + 9 if serving_blue else x0 + w - 9
    d = ImageDraw.Draw(im)
    d.polygon([(sx - 2, y + 20), (sx + 2, y + 20), (sx, y + 22)], fill=C['gold'] + (255,))

def round_button(im, cx, cy, kind):
    disc(im, cx, cy, 8, C['n1'], 235); ring(im, cx, cy, 8, C['n3'])
    arc_fill(im, cx, cy, 7.2, 8.6, 20, 160, C['n0'])
    (icon_pause if kind == 'pause' else icon_book)(im, cx, cy, C['txt'])

def joystick(im, cx, cy, state='idle', knob=(0, 0)):
    r = 24
    disc(im, cx, cy, r, C['n1'], 150)
    ring(im, cx, cy, r, C['n3'])
    arc_fill(im, cx, cy, r - 1, r + 0.6, 20, 160, C['n0'])
    if state == 'active':
        ang = atan2(knob[1], knob[0]) * 180 / pi
        arc_fill(im, cx, cy, r - 3, r - 0.5, (ang - 35) % 360, (ang + 35) % 360, C['cyan'])
    for k in range(4):
        a = k * pi / 2; im.load()[int(cx + cos(a) * (r - 5)), int(cy + sin(a) * (r - 5))] = C['n4'] + (255,)
    kx, ky = cx + knob[0], cy + knob[1]
    disc(im, kx, ky, 9, C['n3'] if state == 'idle' else C['cyan_d'])
    arc_fill(im, kx, ky, 0, 9.5, 190, 300, C['n4'] if state == 'idle' else C['cyan'])
    disc(im, kx, ky, 5, C['n2'] if state == 'idle' else C['cyan_d'])

def hit_button(im, cx, cy, state='idle', charge=0.0, aim=(0, 0)):
    r = 22
    base = {'idle': C['n2'], 'pressed': C['blue_d'], 'charge': C['blue_d'], 'aim': C['blue_d'], 'perfect': C['green_d']}[state]
    disc(im, cx, cy, r, base, 235)
    arc_fill(im, cx, cy, r - 1.5, r + 0.6, 200, 340, C['n4'] if state == 'idle' else C['blue_l'])
    arc_fill(im, cx, cy, r - 1.5, r + 0.6, 20, 160, C['n0'])
    if state in ('charge', 'aim', 'perfect'):
        a1 = (270 + 360 * charge) % 360
        arc_fill(im, cx, cy, r + 1.5, r + 3.6, 270, a1 if charge < 1 else 269.9, C['gold'] if state != 'perfect' else C['green'])
    lab = 'HIT' if state != 'perfect' else 'NICE'
    ctext(im, cx, cy - 3, lab, C['txt'], 1, C['n0'])
    if state == 'aim':
        d = ImageDraw.Draw(im)
        ex, ey = cx + aim[0], cy + aim[1]
        d.line([cx, cy, ex, ey], fill=C['gold'] + (255,), width=1)
        disc(im, ex, ey, 3, C['gold'])

WHEEL = ['FLAT', 'TOPSPIN', 'SLICE', 'DROP']
def shot_wheel(im, cx, cy, sel=0, open_=True):
    r = 19
    disc(im, cx, cy, r, C['n1'], 220)
    cols = [C['gold'], C['red'], C['cyan'], C['green']]
    for i in range(4):
        a0 = (i * 90 - 135 + 4) % 360; a1 = (i * 90 - 45 - 4) % 360
        arc_fill(im, cx, cy, r - 5, r, a0, a1, cols[i] if i == sel else C['n3'])
    disc(im, cx, cy, r - 7, C['n2'])
    # spin glyph in centre
    g = {0: [(-4, 0), (4, 0)], 1: [(-4, 2), (0, -3), (4, 2)], 2: [(-4, -2), (0, 3), (4, -2)], 3: [(-4, -3), (-1, 3), (4, 3)]}[sel]
    d = ImageDraw.Draw(im); d.line([(cx + a, cy + b) for a, b in g], fill=cols[sel] + (255,), width=1)
    if open_:
        ctext(im, cx, cy + r + 4, WHEEL[sel], C['txt'], 1, C['n0'])

def banner(im, cx, y, s, col, col_d, sc=2):
    w = text_w(s, sc) + 16
    x0 = int(cx - w / 2)
    panel(im, x0, y, x0 + w, y + 7 * sc + 9, fill=col_d, top=col, bot=C['n0'])
    ctext(im, cx, y + 5, s, C['txt'], sc, C['n0'])

def toast(im, x0, y0, s, icon='paddle'):
    w = text_w(s) + 22
    panel(im, x0, y0, x0 + w, y0 + 15)
    icon_paddle(im, x0 + 8, y0 + 8) if icon == 'paddle' else icon_ball(im, x0 + 8, y0 + 7)
    text(im, x0 + 16, y0 + 4, s, C['txt'], 1, C['n0'])

def stamina(im, x0, y0, frac, segs=8):
    for i in range(segs):
        c = C['green'] if i < frac * segs else C['n3']
        ImageDraw.Draw(im).rectangle([x0 + i * 5, y0, x0 + i * 5 + 3, y0 + 2], fill=c + (255,))

def team_badge(im, x0, y0, s, blue=True):
    col, cd = (C['blue'], C['blue_dd']) if blue else (C['red'], C['red_dd'])
    w = text_w(s) + 10
    panel(im, x0, y0, x0 + w, y0 + 12, fill=cd, top=col, bot=C['n0'])
    text(im, x0 + 5, y0 + 3, s, C['txt'], 1, C['n0'])
