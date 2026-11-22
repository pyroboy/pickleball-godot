#!/usr/bin/env python3
"""Bake the beach world's pixel sprites into one atlas (visual only).

Every sprite is drawn here in code (no hand-drawn files): coconut palms, spectators,
lifeguard tower, umbrellas, tiki hut, ice-cream cart, gulls, pelican, crab, turtle, dog,
dolphin, swimmer, sailboat, towels, bunting and small props. Colours are
picked as they should look on screen and pre-compensated for the game's Filmic tonemap
with the same measured curve as the player cards (tools/bake_pixel_cards.py), so the
sprite shader can draw them unshaded with the cards' gain.

  assets/beach/beach_atlas.png   one atlas, nearest filtered
  assets/beach/beach_meta.json   per sprite: frames (atlas rects), size in metres
                                 + "palette": compensated colours for the ground shader

Usage: python3 tools/bake_beach_sprites.py [--sheet]
  --sheet: on-screen colours preview -> logs/beach_sheet.png
Run Godot with --import afterwards so the new PNG loads.
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bake_pixel_cards import make_compensator, display_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/beach")
PPM = 20.0          # atlas pixels per metre for near-court sprites (~ the screen's grid there)
GAIN = 2.2          # same as the player cards (cards_meta.json "gain")
ATLAS_W = 1024
# Brightest colour the tonemap + PixelPost chain shows for an unshaded texel at GAIN (the
# measured curve tops out at 218). Colours are scaled down to fit, keeping their hue.
CEIL = 210.0


def fit(rgb):
    rgb = np.asarray(rgb, float)
    m = np.max(rgb, axis=-1, keepdims=True)
    return rgb * np.minimum(1.0, CEIL / np.maximum(m, 1.0))


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def dark(c, f=0.72):
    """Shadow tone: darker and shifted toward violet (no black outlines)."""
    return mix(tuple(int(v * f) for v in c), (70, 55, 120), 0.16)


def light(c, t=0.28):
    return mix(c, (255, 248, 222), t)


# ---------------------------------------------------------------- drawing helpers
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def rect(self, x0, y0, x1, y1, c):
        if x1 < x0: x0, x1 = x1, x0
        if y1 < y0: y0, y1 = y1, y0
        self.d.rectangle([x0, y0, x1, y1], fill=c + (255,))

    def ell(self, cx, cy, rx, ry, c):
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=c + (255,))

    def poly(self, pts, c):
        self.d.polygon([(round(x), round(y)) for x, y in pts], fill=c + (255,))

    def line(self, pts, c, w=1):
        self.d.line([(round(x), round(y)) for x, y in pts], fill=c + (255,), width=w)

    def px(self, x, y, c, a=255):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((x, y), c + (a,))

    def flip(self):
        out = Canvas(self.w, self.h)
        out.img = self.img.transpose(Image.FLIP_LEFT_RIGHT)
        out.d = ImageDraw.Draw(out.img)
        return out

    def rotated(self, deg):
        out = Canvas(self.w, self.h)
        out.img = self.img.rotate(deg, resample=Image.NEAREST, expand=False)
        out.d = ImageDraw.Draw(out.img)
        return out


# ---------------------------------------------------------------- palette
P = {k: hx(v) for k, v in {
    "sand": "efd6a2", "sand_dk": "dcbc88", "sand_lt": "f8e6bd", "sand_sh": "c9a98a",
    "wet": "cfae84", "wet_dk": "b8966f", "foam": "f6f4ea", "shallow": "7fdccf",
    "water": "45b6cb", "deep": "2b8bbb", "deeper": "246fa6", "haze": "bfe3ef",
    "pad": "e9dfcb", "pad_dk": "d8cbb2", "curb": "f3eee2",
    "trunk": "b98a5a", "ring": "9c7048", "frond": "5bb65a", "frond_lt": "8fd66b",
    "frond_dk": "3c8a5c", "coco": "7a5434",
    "bamboo": "d9b36a", "bamboo_dk": "a98446", "rope": "f1e6cc",
    "white": "f4f1ea", "red": "e0503f", "blue": "3f7fdc", "yellow": "ffd35a",
    "green": "6cc46a", "pink": "f59bb4", "orange": "ff9a52", "purple": "a98ae6",
    "teal": "43c2b5", "navy": "2f4f86", "wood": "a87850", "wood_dk": "7d5638",
    "thatch": "dcb75e", "thatch_dk": "b08c3e", "metal": "c2ccd6",
    "gull": "f4f3ee", "gull_wing": "a2adb9", "gull_tip": "56606e", "beak": "f2b233",
    "leg": "e9904d", "pelican": "ebe5d8", "pel_brown": "9c7c5d", "pouch": "f1b86b",
    "crab": "e5563f", "crab_lt": "f68d5d", "shell": "6f9b4c", "shell_lt": "93bb61",
    "turtle_skin": "a6c27d", "dog": "d99b4f", "dog_lt": "f1c27c", "dog_dk": "ad713a",
    "nose": "3e2c27", "dolphin": "7f9dbb", "belly": "d2dfe9", "rock": "a89a8c",
    "rock_lt": "c4b8aa", "eye": "2a2230",
}.items()}

SKINS = [hx(h) for h in ("f3cba9", "e0ab84", "c08458", "93603f", "68432f")]
HAIR = [hx(h) for h in ("2d211c", "5a3a22", "c98f3e", "ead39f", "8f8a86", "b3462f")]
SHIRTS = [P[k] for k in ("red", "blue", "yellow", "green", "pink", "orange", "purple", "teal", "white", "navy")]
SHORTS = [hx(h) for h in ("2f4f86", "f4f1ea", "3a3a48", "6cc46a", "c9a46a", "e0503f")]


# ---------------------------------------------------------------- sprites
# Each function returns a list of frames (Canvas). Origin: bottom centre unless noted.

def palm(seed, h_m=6.2, lean=1.0):
    rng = np.random.default_rng(seed)
    w, h = 104, int(h_m * PPM) + 4
    cv = Canvas(w, h)
    cx = w // 2
    top = (cx + lean * rng.uniform(10, 18), 30.0)
    base = (cx - lean * 4.0, h - 1.0)
    ctrl = (cx + lean * rng.uniform(-6, 2), h * 0.55)
    # trunk: tapering bezier, light on the left half, rings every 5 px
    n = 60
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * base[0] + 2 * (1 - t) * t * ctrl[0] + t * t * top[0]
        y = (1 - t) ** 2 * base[1] + 2 * (1 - t) * t * ctrl[1] + t * t * top[1]
        r = 3.6 - 1.5 * t
        ring = int(y) % 5 == 0
        c = P["ring"] if ring else P["trunk"]
        cv.rect(x - r, y, x + r, y + 1, dark(c, 0.8))
        cv.rect(x - r, y, x - r * 0.15, y + 1, light(c, 0.18) if not ring else c)
    # coconuts under the crown
    for dx, dy in ((-3, 3), (2, 4), (-1, 6), (4, 1)):
        cv.ell(top[0] + dx, top[1] + dy, 2.2, 2.2, P["coco"])
        cv.px(top[0] + dx - 1, top[1] + dy - 1, light(P["coco"], 0.3))
    # fronds: drooping pinnate arcs; back fronds darker, front ones lighter
    k = rng.integers(8, 11)
    fronds = []
    for i in range(k):
        a = math.pi * (i / (k - 1)) + rng.uniform(-0.12, 0.12)
        fronds.append((a, rng.uniform(30, 44), rng.uniform(0.9, 1.4), i % 2 == 0))
    fronds.sort(key=lambda f: f[3])       # back ones first
    for a, L, droop, back in fronds:
        base_c = P["frond_dk"] if back else P["frond"]
        hi = P["frond"] if back else P["frond_lt"]
        pts = []
        for j in range(22):
            s = j / 21
            x = top[0] + math.cos(a) * s * L
            y = top[1] - math.sin(a) * s * L * 0.55 + droop * (s * L) ** 2 / 40.0
            pts.append((x, y))
        for j in range(1, len(pts)):
            x0, y0 = pts[j - 1]; x1, y1 = pts[j]
            s = j / len(pts)
            leaf = max(1.0, 6.0 * (1 - s) * (0.6 + s))
            # leaflets hang down from the rib
            cv.line([(x1, y1), (x1 + (x1 - x0) * 0.4, y1 + leaf)], base_c, 1)
            if j % 2 == 0:
                cv.line([(x1, y1), (x1 - (x1 - x0) * 0.3, y1 + leaf * 0.8)], dark(base_c, 0.85), 1)
        cv.line(pts, hi, 2 if not back else 1)
    cv.ell(top[0], top[1], 3, 2, P["frond_dk"])
    return [cv]


def person(skin, hair, hair_style, shirt, shorts, seated, frame, hat=None):
    """Front-facing spectator. frames: 0 idle, 1 look, 2 clap open, 3 clap shut, 4 cheer, 5 cheer high."""
    w, h = 22, (30 if seated else 38)
    cv = Canvas(w, h)
    cx = 11
    lift = -1 if frame == 5 else 0
    if seated:
        y_head, y_torso0, y_torso1, y_lap = 8, 12, 19, 20
        # shins + feet, knees forward
        cv.rect(cx - 4, y_lap, cx + 3, y_lap + 2, shorts)
        cv.rect(cx - 4, y_lap + 3, cx - 2, h - 3, skin); cv.rect(cx + 1, y_lap + 3, cx + 3, h - 3, dark(skin, 0.9))
        cv.rect(cx - 5, h - 2, cx - 2, h - 1, P["white"]); cv.rect(cx + 1, h - 2, cx + 4, h - 1, P["white"])
    else:
        y_head, y_torso0, y_torso1, y_lap = 8 + lift, 12 + lift, 21 + lift, 22 + lift
        cv.rect(cx - 4, y_lap, cx + 3, y_lap + 4, shorts)
        cv.rect(cx - 4, y_lap + 5, cx - 2, h - 3 + lift, skin); cv.rect(cx + 1, y_lap + 5, cx + 3, h - 3 + lift, dark(skin, 0.9))
        cv.rect(cx - 5, h - 2 + lift, cx - 2, h - 1 + lift, P["white"]); cv.rect(cx + 1, h - 2 + lift, cx + 4, h - 1 + lift, P["white"])
    # torso
    cv.rect(cx - 4, y_torso0, cx + 3, y_torso1, shirt)
    cv.rect(cx + 2, y_torso0, cx + 3, y_torso1, dark(shirt, 0.82))
    cv.rect(cx - 4, y_torso0, cx - 3, y_torso0 + 2, light(shirt, 0.25))
    cv.rect(cx - 1, y_torso0, cx, y_torso0, skin)               # neck
    # arms
    sk_d = dark(skin, 0.88)
    if frame in (0, 1):
        cv.rect(cx - 6, y_torso0 + 1, cx - 5, y_torso1 - 1, skin)
        cv.rect(cx + 4, y_torso0 + 1, cx + 5, y_torso1 - 1, sk_d)
    elif frame in (2, 3):
        gap = 2 if frame == 2 else 0
        cv.rect(cx - 6, y_torso0 + 1, cx - 5, y_torso0 + 4, skin)
        cv.rect(cx + 4, y_torso0 + 1, cx + 5, y_torso0 + 4, sk_d)
        cv.rect(cx - 4 - gap // 2, y_torso0 + 3, cx - 1 - gap // 2 + 1, y_torso0 + 4, skin)
        cv.rect(cx - gap // 2 + gap, y_torso0 + 3, cx + 3, y_torso0 + 4, sk_d)
        cv.rect(cx - 1 - gap, y_torso0 + 1, cx - gap, y_torso0 + 3, skin)
        cv.rect(cx + gap, y_torso0 + 1, cx + 1 + gap, y_torso0 + 3, sk_d)
    else:
        hi = 6 if frame == 4 else 8
        cv.line([(cx - 5, y_torso0 + 1), (cx - 8, y_torso0 - hi)], skin, 2)
        cv.line([(cx + 4, y_torso0 + 1), (cx + 7, y_torso0 - hi)], sk_d, 2)
        cv.rect(cx - 9, y_torso0 - hi - 1, cx - 8, y_torso0 - hi, skin)
        cv.rect(cx + 7, y_torso0 - hi - 1, cx + 8, y_torso0 - hi, sk_d)
    # head
    look = -1 if frame == 1 else 0
    hx0 = cx + look
    if hair_style == "long":
        cv.rect(hx0 - 4, y_head - 3, hx0 + 3, y_head + 4, hair)
    cv.ell(hx0 - 0.5, y_head, 3.5, 3.6, skin)
    cv.rect(hx0 + 1, y_head - 2, hx0 + 3, y_head + 3, dark(skin, 0.9))
    # face: two eyes, a smile when cheering
    cv.px(hx0 - 2, y_head, P["eye"]); cv.px(hx0 + 1, y_head, P["eye"])
    if frame in (4, 5):
        cv.rect(hx0 - 1, y_head + 2, hx0, y_head + 2, dark(P["red"], 0.8))
    if hair_style in ("short", "long", "bun"):
        cv.rect(hx0 - 4, y_head - 4, hx0 + 3, y_head - 2, hair)
        cv.px(hx0 - 4, y_head - 1, hair); cv.px(hx0 + 3, y_head - 1, hair)
    if hair_style == "bun":
        cv.ell(hx0 - 0.5, y_head - 5, 2, 1.6, hair)
    if hat == "cap":
        cv.rect(hx0 - 4, y_head - 5, hx0 + 3, y_head - 3, P["red"] if shirt != P["red"] else P["blue"])
        cv.rect(hx0 - 6 + (2 if look else 0), y_head - 3, hx0 - 1, y_head - 3, dark(P["red"], 0.8))
    elif hat == "sunhat":
        cv.rect(hx0 - 7, y_head - 3, hx0 + 6, y_head - 3, P["thatch"])
        cv.rect(hx0 - 4, y_head - 6, hx0 + 3, y_head - 4, P["thatch"])
        cv.rect(hx0 - 4, y_head - 4, hx0 + 3, y_head - 4, P["red"])
    elif hat == "shades":
        cv.rect(hx0 - 3, y_head, hx0 + 2, y_head, P["eye"])
    return cv


def spectators():
    out = {}
    styles = ["short", "long", "bun", "short", "long", "bald", "short", "long", "bun", "short", "long", "short"]
    hats = [None, "sunhat", None, "cap", "shades", None, "cap", None, "shades", "sunhat", None, None]
    for i in range(12):
        rng = np.random.default_rng(100 + i)
        skin = SKINS[i % len(SKINS)]
        hair = HAIR[(i * 3 + 1) % len(HAIR)]
        shirt = SHIRTS[(i * 7) % len(SHIRTS)]
        shorts = SHORTS[(i * 5 + 2) % len(SHORTS)]
        seated = i < 8
        name = ("fan_sit_%d" if seated else "fan_stand_%d") % (i if seated else i - 8)
        out[name] = [person(skin, hair, styles[i], shirt, shorts, seated, f, hats[i]) for f in range(6)]
    return out


def bench():
    cv = Canvas(72, 12)
    cv.rect(0, 2, 71, 4, P["bamboo"]); cv.rect(0, 4, 71, 4, P["bamboo_dk"])
    for x in range(0, 72, 9): cv.px(x, 3, P["bamboo_dk"])
    for x in (3, 34, 66):
        cv.rect(x, 5, x + 2, 11, P["bamboo_dk"]); cv.px(x, 8, P["bamboo"])
    return [cv]


def lifeguard_tower():
    frames = []
    for f in range(3):
        cv = Canvas(56, 76)
        # legs and cross braces
        for x in (12, 42):
            cv.rect(x, 38, x + 2, 75, P["white"]); cv.rect(x + 2, 38, x + 2, 75, dark(P["white"], 0.85))
        cv.line([(13, 74), (43, 50)], P["wood"], 1); cv.line([(43, 74), (13, 50)], P["wood"], 1)
        # ladder
        for y in range(44, 76, 4): cv.rect(24, y, 31, y, P["wood"])
        cv.rect(23, 40, 23, 75, P["wood_dk"]); cv.rect(32, 40, 32, 75, P["wood_dk"])
        # platform + hut
        cv.rect(6, 36, 49, 39, P["wood"]); cv.rect(6, 39, 49, 39, P["wood_dk"])
        cv.rect(10, 16, 45, 35, P["red"]); cv.rect(41, 16, 45, 35, dark(P["red"], 0.8))
        cv.rect(14, 20, 41, 31, dark(P["navy"], 0.9))             # window
        cv.poly([(6, 17), (28, 8), (50, 17)], P["white"]); cv.rect(6, 17, 50, 18, dark(P["white"], 0.85))
        cv.rect(10, 33, 45, 35, P["white"])                          # stripe
        # lifeguard in the window
        skin = SKINS[2]
        cv.ell(27, 24, 3, 3, skin); cv.rect(24, 21, 30, 22, HAIR[0])
        cv.rect(23, 27, 31, 31, P["red"])
        if f == 1:   # binoculars
            cv.rect(24, 23, 29, 25, P["eye"]); cv.rect(22, 26, 24, 28, skin); cv.rect(30, 26, 32, 28, skin)
        else:
            cv.px(26, 24, P["eye"]); cv.px(28, 24, P["eye"])
        if f == 2:   # wave
            cv.line([(31, 28), (36, 20)], skin, 2)
        # flag pole and flag (flutters)
        cv.rect(50, 0, 50, 36, P["metal"])
        fl = [(51, 1), (58 if f != 1 else 57, 3 + (f % 2)), (51, 7)]
        cv.poly(fl, P["yellow"] if f != 2 else P["red"])
        cv.poly([(51, 1), (58 if f != 1 else 57, 3 + (f % 2)), (51, 7)], P["red"])
        cv.rect(51, 4, 54, 4, P["yellow"])
        frames.append(cv)
    return frames


def umbrella(c1, c2):
    cv = Canvas(52, 50)
    cx = 26
    cv.rect(cx, 12, cx + 1, 49, P["white"]); cv.rect(cx + 1, 12, cx + 1, 49, dark(P["white"], 0.85))
    # canopy: dome with 8 alternating panels, scalloped hem
    for y in range(4, 19):
        t = (y - 4) / 14
        half = int(6 + 19 * math.sqrt(t))
        for x in range(cx - half, cx + half + 1):
            seg = int(((x - cx) / max(half, 1) + 1) * 4) % 2
            c = c1 if seg == 0 else c2
            if x > cx + half * 0.4: c = dark(c, 0.86)
            if y < 7: c = light(c, 0.15)
            cv.px(x, y, c)
    for i, x in enumerate(range(cx - 25, cx + 26, 6)):
        cv.ell(x + 3, 19, 3, 1.5, c1 if i % 2 == 0 else c2)
    cv.rect(cx - 1, 1, cx + 2, 3, P["white"])
    return [cv]


def sunbather():
    frames = []
    for f in range(2):
        cv = Canvas(44, 12)
        cv.rect(1, 10, 42, 11, P["teal"]); cv.rect(1, 10, 42, 10, light(P["teal"], 0.2))
        for x in range(4, 42, 6): cv.rect(x, 10, x + 2, 11, P["white"])
        skin = SKINS[1]
        cv.ell(6, 7, 3, 3, skin); cv.rect(3, 4, 9, 5, HAIR[2]); cv.rect(5, 6, 9, 6, P["eye"])   # shades
        cv.rect(9, 6, 22, 9, skin); cv.rect(11, 6, 20, 8, P["pink"])
        cv.rect(22, 6, 27, 9, P["pink"])
        if f == 0:
            cv.rect(27, 7, 39, 9, skin)
        else:   # one knee up
            cv.line([(27, 8), (32, 3), (38, 9)], skin, 2)
            cv.rect(27, 8, 39, 9, dark(skin, 0.9))
        cv.rect(39, 7, 41, 9, skin)
        frames.append(cv)
    return frames


def kid_sandcastle():
    frames = []
    for f in range(2):
        cv = Canvas(34, 26)
        # castle
        s, sd = P["sand_dk"], dark(P["sand_dk"], 0.85)
        cv.rect(16, 14, 31, 25, s); cv.rect(28, 14, 31, 25, sd)
        cv.rect(15, 8, 19, 25, s); cv.rect(28, 8, 32, 25, sd)
        cv.rect(21, 10, 25, 14, s)
        for x in (15, 17, 19, 28, 30, 32, 21, 23, 25):
            cv.px(x, 7 if x not in (21, 23, 25) else 9, s)
        cv.rect(23, 3, 23, 9, P["wood_dk"]); cv.poly([(24, 3), (28, 4), (24, 6)], P["red"])
        cv.rect(21, 18, 24, 25, dark(P["sand_dk"], 0.7))             # door
        # kid kneeling at the left
        skin = SKINS[3]
        cv.ell(7, 10, 3, 3, skin); cv.rect(4, 7, 10, 8, HAIR[0])
        cv.px(6, 10, P["eye"]); cv.px(8, 10, P["eye"])
        cv.rect(4, 14, 10, 20, P["yellow"]); cv.rect(4, 21, 11, 25, P["blue"])
        if f == 0: cv.line([(10, 15), (15, 12)], skin, 2)
        else: cv.line([(10, 16), (15, 18)], skin, 2)
        # bucket
        cv.rect(0, 20, 3, 25, P["red"]); cv.rect(0, 19, 3, 19, P["yellow"])
        frames.append(cv)
    return frames


def icecream_cart():
    frames = []
    for f in range(2):
        cv = Canvas(48, 46)
        # parasol
        cv.rect(24, 4, 24, 22, P["metal"])
        for y in range(2, 8):
            half = 4 + (y - 2) * 3
            for x in range(24 - half, 24 + half + 1):
                cv.px(x, y, P["pink"] if ((x - 24) // 4) % 2 == 0 else P["white"])
        # vendor behind
        skin = SKINS[0]
        cv.ell(33, 17, 3, 3, skin); cv.rect(30, 13, 36, 15, P["white"])
        cv.px(32, 17, P["eye"]); cv.px(34, 17, P["eye"])
        cv.rect(30, 21, 37, 27, P["blue"])
        if f == 1:
            cv.line([(37, 22), (41, 16)], skin, 2); cv.rect(41, 13, 43, 15, P["yellow"])   # bell
        # cart body
        cv.rect(4, 26, 43, 39, P["white"]); cv.rect(39, 26, 43, 39, dark(P["white"], 0.85))
        cv.rect(4, 26, 43, 28, P["pink"]); cv.rect(4, 37, 43, 39, P["pink"])
        for i, c in enumerate((P["pink"], P["yellow"], P["green"])):           # cone sign
            cv.ell(14 + i * 9, 31, 2.5, 2.5, c)
            cv.poly([(12 + i * 9, 33), (16 + i * 9, 33), (14 + i * 9, 36)], P["thatch"])
        for x in (10, 36):
            cv.ell(x, 41, 4, 4, dark(P["navy"], 0.9)); cv.px(x, 41, P["metal"])
        frames.append(cv)
    return frames


def tiki_hut():
    frames = []
    for f in range(2):
        cv = Canvas(80, 70)
        # posts
        for x in (8, 70):
            cv.rect(x, 22, x + 3, 69, P["wood"]); cv.rect(x + 3, 22, x + 3, 69, P["wood_dk"])
        # bartender
        skin = SKINS[4]
        bx = 40 + (2 if f else 0)
        cv.ell(bx, 34, 3.5, 3.5, skin); cv.rect(bx - 4, 30, bx + 3, 31, HAIR[0])
        cv.px(bx - 2, 34, P["eye"]); cv.px(bx + 1, 34, P["eye"])
        cv.rect(bx - 5, 38, bx + 4, 46, P["orange"])
        for x in range(bx - 5, bx + 5, 3): cv.px(x, 41, P["yellow"])
        shaker_y = 33 if f else 38
        cv.line([(bx + 4, 40), (bx + 8, shaker_y)], skin, 2); cv.rect(bx + 8, shaker_y - 3, bx + 10, shaker_y, P["metal"])
        # counter
        cv.rect(4, 46, 76, 69, P["bamboo"]); cv.rect(4, 46, 76, 48, light(P["bamboo"], 0.25))
        for x in range(6, 76, 5): cv.rect(x, 49, x, 69, P["bamboo_dk"])
        cv.rect(26, 52, 54, 62, P["wood_dk"]); cv.rect(27, 53, 53, 61, P["wood"])
        for i in range(4): cv.rect(30 + i * 6, 55, 32 + i * 6, 59, (P["teal"], P["red"], P["yellow"], P["green"])[i])
        # coconut drinks on the counter
        for x in (12, 18, 62):
            cv.ell(x, 43, 2.6, 2.6, P["coco"]); cv.rect(x, 37, x, 41, P["pink"])
        # thatch roof with fringe
        cv.poly([(0, 24), (16, 4), (64, 4), (80, 24)], P["thatch"])
        cv.poly([(0, 24), (16, 4), (22, 4), (8, 24)], light(P["thatch"], 0.2))
        for x in range(0, 80, 3):
            cv.rect(x, 24, x + 1, 27 + (x * 7) % 4, P["thatch_dk"] if x % 2 else P["thatch"])
        for y in range(8, 24, 5): cv.line([(16 - (y - 4) * 0.8, y), (64 + (y - 4) * 0.8, y)], P["thatch_dk"], 1)
        frames.append(cv)
    return frames


def surfboard(c, stripe):
    cv = Canvas(12, 44)
    cv.ell(6, 22, 5, 21, c)
    cv.rect(5, 2, 6, 42, stripe)
    cv.ell(8, 22, 2, 18, dark(c, 0.86))
    return [cv]


def cooler():
    cv = Canvas(16, 12)
    cv.rect(1, 3, 14, 11, P["blue"]); cv.rect(11, 3, 14, 11, dark(P["blue"], 0.8))
    cv.rect(0, 1, 15, 3, P["white"]); cv.rect(5, 0, 10, 0, P["metal"])
    return [cv]


def beach_ball():
    cv = Canvas(10, 10)
    for y in range(10):
        for x in range(10):
            dx, dy = x - 4.5, y - 4.5
            if dx * dx + dy * dy <= 20:
                a = math.atan2(dy, dx)
                seg = int((a + math.pi) / (math.pi / 3)) % 6
                c = (P["red"], P["white"], P["blue"], P["white"], P["yellow"], P["white"])[seg]
                if dx + dy > 3: c = dark(c, 0.85)
                cv.px(x, y, c)
    cv.px(4, 4, P["white"])
    return [cv]


def rock(seed, w, h):
    rng = np.random.default_rng(seed)
    cv = Canvas(w, h)
    pts = []
    for i in range(9):
        a = math.pi * i / 8
        r = rng.uniform(0.8, 1.0)
        pts.append((w / 2 + math.cos(a) * (w / 2 - 1) * r, h - 1 - math.sin(a) * (h - 2) * r))
    cv.poly(pts, P["rock"])
    cv.poly([(p[0], p[1]) for p in pts[4:]] + [(w / 2, h - 1)], light(P["rock"], 0.25))
    cv.rect(0, h - 2, w - 1, h - 1, dark(P["rock"], 0.85))
    return [cv]


def driftwood():
    cv = Canvas(40, 8)
    cv.line([(1, 6), (20, 4), (38, 5)], P["rock_lt"], 3)
    cv.line([(12, 4), (16, 0)], P["rock_lt"], 2)
    cv.line([(1, 7), (38, 6)], P["rock"], 1)
    return [cv]


def shell():
    cv = Canvas(5, 4)
    cv.ell(2, 2, 2, 1.5, P["pink"]); cv.px(2, 1, P["white"])
    return [cv]


def starfish():
    cv = Canvas(7, 6)
    for a in range(5):
        ang = -math.pi / 2 + a * 2 * math.pi / 5
        cv.line([(3, 3), (3 + math.cos(ang) * 3, 3 + math.sin(ang) * 2.6)], P["orange"], 1)
    cv.px(3, 3, P["yellow"])
    return [cv]


def gull_fly():
    frames = []
    for f in range(4):
        cv = Canvas(22, 12)
        wy = (-4, 0, 3, 0)[f]
        cv.rect(8, 5, 14, 7, P["gull"]); cv.rect(14, 5, 16, 6, P["gull"]); cv.px(17, 6, P["beak"])
        cv.px(15, 5, P["eye"])
        cv.rect(5, 6, 7, 6, P["gull_wing"])
        cv.line([(9, 5), (4, 5 + wy), (0, 6 + wy)], P["gull_wing"], 2)
        cv.line([(13, 5), (17, 5 + wy), (21, 6 + wy)], P["gull_wing"], 2)
        cv.px(0, 6 + wy, P["gull_tip"]); cv.px(21, 6 + wy, P["gull_tip"])
        frames.append(cv)
    return frames


def gull_ground():
    frames = []
    for f in range(3):   # 0 stand, 1 peck, 2 step
        cv = Canvas(14, 12)
        cv.ell(6, 7, 4, 2.5, P["gull"]); cv.rect(2, 6, 7, 7, P["gull_wing"]); cv.px(1, 6, P["gull_tip"])
        if f == 1:
            cv.rect(9, 7, 11, 9, P["gull"]); cv.px(12, 10, P["beak"]); cv.px(10, 8, P["eye"])
        else:
            cv.rect(9, 2, 11, 5, P["gull"]); cv.rect(12, 3, 13, 3, P["beak"]); cv.px(10, 3, P["eye"])
        cv.px(5, 10, P["leg"]); cv.px(5, 11, P["leg"])
        cv.px(7 + (1 if f == 2 else 0), 10, P["leg"]); cv.px(7 + (1 if f == 2 else 0), 11, P["leg"])
        frames.append(cv)
    return frames


def pelican():
    frames = []
    for f in range(2):
        cv = Canvas(20, 22)
        cv.ell(9, 13, 6, 5, P["pelican"]); cv.rect(4, 11, 10, 16, P["pel_brown"])
        cv.rect(11, 4, 13, 11, P["pelican"])
        if f == 0:
            cv.ell(13, 4, 2.5, 2.2, P["pelican"]); cv.rect(15, 4, 19, 5, P["pouch"]); cv.rect(15, 6, 18, 7, P["pouch"])
            cv.px(13, 3, P["eye"])
        else:
            cv.ell(12, 4, 2.5, 2.2, P["pelican"]); cv.rect(5, 4, 9, 5, P["pouch"]); cv.rect(6, 6, 9, 7, P["pouch"])
            cv.px(11, 3, P["eye"])
        cv.rect(7, 18, 7, 21, P["leg"]); cv.rect(10, 18, 10, 21, P["leg"])
        frames.append(cv)
    return frames


def crab():
    frames = []
    for f in range(2):
        cv = Canvas(14, 9)
        cv.ell(7, 5, 4, 2.5, P["crab"]); cv.rect(4, 3, 10, 4, P["crab_lt"])
        cv.px(5, 1, P["eye"]); cv.px(9, 1, P["eye"]); cv.px(5, 2, P["crab"]); cv.px(9, 2, P["crab"])
        up = 0 if f == 0 else 1
        cv.rect(0, 2 - up, 2, 3 - up, P["crab"]); cv.rect(12, 2 - up, 13, 3 - up, P["crab"])
        cv.px(2, 4, P["crab"]); cv.px(11, 4, P["crab"])
        for i, x in enumerate((3, 4, 10, 11)):
            cv.px(x - (1 if (i + f) % 2 else 0), 8, dark(P["crab"], 0.8))
            cv.px(x, 7, dark(P["crab"], 0.8))
        frames.append(cv)
    return frames


def turtle():
    frames = []
    for f in range(2):
        cv = Canvas(18, 9)
        cv.ell(8, 4, 6, 3.5, P["shell"]); cv.rect(4, 2, 11, 3, P["shell_lt"])
        for x in (5, 8, 11): cv.px(x, 4, dark(P["shell"], 0.8))
        cv.ell(15, 5, 2, 1.6, P["turtle_skin"]); cv.px(16, 4, P["eye"])
        fx = 1 if f else 0
        cv.rect(3 + fx, 7, 5 + fx, 8, P["turtle_skin"]); cv.rect(10 - fx, 7, 12 - fx, 8, P["turtle_skin"])
        cv.rect(4, 7, 13, 7, dark(P["shell"], 0.75))
        frames.append(cv)
    return frames


def dog():
    frames = []
    for f in range(6):   # 0-3 run, 4-5 stand (tail wag)
        cv = Canvas(24, 16)
        run = f < 4
        bob = (0, -1, 0, 1)[f] if run else 0
        cv.rect(5, 6 + bob, 16, 10 + bob, P["dog"]); cv.rect(5, 9 + bob, 16, 10 + bob, P["dog_lt"])
        cv.rect(15, 2 + bob, 20, 7 + bob, P["dog"]); cv.rect(20, 4 + bob, 22, 6 + bob, P["dog_lt"])
        cv.px(22, 4 + bob, P["nose"]); cv.px(18, 3 + bob, P["eye"])
        cv.rect(15, 1 + bob, 16, 4 + bob, P["dog_dk"])                     # ear
        cv.rect(12, 6 + bob, 13, 6 + bob, P["red"])                         # collar
        tail = (-2, 0, -1, 1)[f] if run else (-3 if f == 4 else 1)
        cv.line([(5, 7 + bob), (1, 4 + bob + tail)], P["dog"], 2)
        if run:
            spread = (4, 1, -2, 1)[f]
            for x0 in (7, 14):
                cv.line([(x0, 10 + bob), (x0 - spread, 15)], P["dog_dk"], 2)
        else:
            for x in (6, 8, 13, 15): cv.rect(x, 11, x + 1, 15, P["dog_dk"] if x in (8, 15) else P["dog"])
        frames.append(cv)
    return frames


def dolphin():
    base = Canvas(40, 40)
    c = P["dolphin"]
    base.ell(20, 20, 12, 4, c); base.rect(10, 21, 30, 23, P["belly"])
    base.rect(31, 19, 35, 21, c); base.px(29, 18, P["eye"])
    base.poly([(17, 16), (22, 10), (23, 16)], dark(c, 0.85))            # dorsal fin
    base.poly([(8, 20), (3, 15), (5, 20), (3, 25)], c)                  # tail flukes
    base.poly([(20, 23), (17, 28), (23, 24)], dark(c, 0.85))            # flipper
    return [base.rotated(35), base, base.rotated(-35)]


def splash():
    frames = []
    for f in range(3):
        cv = Canvas(26, 18)
        hgt = (6, 14, 8)[f]
        for i, x in enumerate(range(3, 24, 3)):
            hh = hgt - abs(x - 13) * 0.7 + (i % 2) * 2
            if hh > 1: cv.rect(x, 17 - int(hh), x + 1, 17, P["foam"])
        if f == 2:
            for x, y in ((2, 6), (23, 5), (8, 2), (18, 3)): cv.px(x, y, P["foam"])
        cv.rect(0, 16, 25, 17, light(P["shallow"], 0.3))
        frames.append(cv)
    return frames


def swimmer():
    frames = []
    for f in range(2):
        cv = Canvas(16, 9)
        skin = SKINS[1]
        cv.ell(7, 4, 3, 3, skin); cv.rect(4, 1, 10, 2, P["yellow"])        # swim cap
        cv.px(6, 4, P["eye"]); cv.px(8, 4, P["eye"])
        if f == 0: cv.line([(10, 6), (14, 1)], skin, 2)
        else: cv.line([(4, 6), (1, 2)], skin, 2)
        cv.rect(0, 7, 15, 8, P["foam"])
        frames.append(cv)
    return frames


def buoy():
    cv = Canvas(8, 12)
    cv.ell(3.5, 7, 3.5, 4, P["red"]); cv.rect(0, 6, 7, 7, P["white"]); cv.rect(3, 0, 4, 3, P["metal"])
    cv.rect(0, 10, 7, 11, P["foam"])
    return [cv]


def sailboat():
    frames = []
    for f in range(2):
        cv = Canvas(34, 44)
        cv.rect(16, 4, 16, 36, P["wood_dk"])
        cv.poly([(17, 5), (17, 34), (31, 34)], P["white"]); cv.poly([(15, 9), (15, 34), (4, 34)], light(P["yellow"], 0.4))
        cv.rect(24, 30, 26, 32, P["red"])
        cv.poly([(16, 3), (22 - f, 4 + f), (16, 6)], P["red"])
        cv.poly([(2, 36), (32, 36), (28, 41), (6, 41)], P["navy"]); cv.rect(4, 36, 30, 37, P["white"])
        cv.rect(0, 42, 33, 43, P["foam"])
        frames.append(cv)
    return frames


def towel(c1, c2, pattern):
    cv = Canvas(20, 36)
    cv.rect(0, 0, 19, 35, c1)
    if pattern == "stripes":
        for y in range(2, 34, 6): cv.rect(0, y, 19, y + 2, c2)
    elif pattern == "dots":
        for y in range(3, 34, 6):
            for x in range(3 + (y // 6 % 2) * 3, 19, 6): cv.rect(x, y, x + 1, y + 1, c2)
    else:
        cv.rect(2, 2, 17, 33, c2); cv.rect(4, 4, 15, 31, c1)
    for x in range(0, 20, 2): cv.px(x, 0, P["white"]); cv.px(x, 35, P["white"])
    return [cv]


def bunting(c):
    cv = Canvas(8, 9)
    cv.poly([(0, 0), (7, 0), (3.5, 8)], c)
    cv.rect(0, 0, 7, 0, light(c, 0.3))
    return [cv]


def shadow():
    cv = Canvas(32, 16)
    cv.ell(15.5, 7.5, 15.5, 7.5, (60, 45, 90))
    return [cv]


# ---------------------------------------------------------------- catalogue
# name -> (frames, metres per pixel). Default PPM; far things are drawn coarser.
def catalogue():
    cat = {}
    def add(name, frames, ppm=PPM, kind="sprite"):
        cat[name] = (frames, ppm, kind)
    add("palm_0", palm(1, 6.2, 1.0)); add("palm_1", palm(2, 5.4, -1.0)); add("palm_2", palm(3, 6.8, 1.0))
    add("palm_3", palm(4, 4.6, -1.0))
    for k, v in spectators().items(): add(k, v)
    add("bench", bench())
    add("lifeguard_tower", lifeguard_tower())
    add("umbrella_0", umbrella(P["red"], P["white"])); add("umbrella_1", umbrella(P["blue"], P["yellow"]))
    add("umbrella_2", umbrella(P["green"], P["white"])); add("umbrella_3", umbrella(P["orange"], P["purple"]))
    add("sunbather", sunbather()); add("kid_sandcastle", kid_sandcastle())
    add("icecream_cart", icecream_cart()); add("tiki_hut", tiki_hut())
    add("surfboard_0", surfboard(P["orange"], P["white"])); add("surfboard_1", surfboard(P["teal"], P["yellow"]))
    add("surfboard_2", surfboard(P["pink"], P["white"]))
    add("cooler", cooler()); add("beach_ball", beach_ball())
    add("rock_0", rock(5, 30, 16)); add("rock_1", rock(6, 20, 12)); add("driftwood", driftwood())
    add("shell", shell()); add("starfish", starfish())
    add("gull_fly", gull_fly()); add("gull_ground", gull_ground()); add("pelican", pelican())
    add("crab", crab()); add("turtle", turtle()); add("dog", dog())
    add("dolphin", dolphin()); add("splash", splash()); add("swimmer", swimmer()); add("buoy", buoy())
    add("sailboat", sailboat(), ppm=8.0)
    add("towel_0", towel(P["red"], P["white"], "stripes"), kind="decal")
    add("towel_1", towel(P["blue"], P["yellow"], "dots"), kind="decal")
    add("towel_2", towel(P["purple"], P["pink"], "border"), kind="decal")
    add("towel_3", towel(P["teal"], P["white"], "stripes"), kind="decal")
    for i, c in enumerate((P["red"], P["yellow"], P["blue"], P["green"], P["pink"])):
        add("bunting_%d" % i, bunting(c))
    add("shadow", shadow(), kind="shadow")
    return cat


def main():
    os.makedirs(OUT, exist_ok=True)
    comp = make_compensator(GAIN)
    cat = catalogue()
    # shelf-pack every frame, tallest first; 1 px gutter
    items = []
    for name, (frames, ppm, kind) in cat.items():
        for i, fr in enumerate(frames):
            items.append((name, i, fr))
    items.sort(key=lambda it: -it[2].h)
    x = y = shelf = 0
    rects = {}
    for name, i, fr in items:
        if x + fr.w + 1 > ATLAS_W:
            x, y, shelf = 0, y + shelf + 1, 0
        rects[(name, i)] = (x, y, fr.w, fr.h)
        x += fr.w + 1
        shelf = max(shelf, fr.h)
    height = 1
    while height < y + shelf + 1: height *= 2
    atlas = Image.new("RGBA", (ATLAS_W, height), (0, 0, 0, 0))
    preview = Image.new("RGBA", (ATLAS_W, height), (40, 44, 60, 255))
    for name, i, fr in items:
        x0, y0, w, h = rects[(name, i)]
        a = np.array(fr.img).astype(float)
        mask = a[..., 3] > 0
        a[..., 3] = np.where(mask, 255, 0)
        shown = a.copy()
        if cat[name][2] != "shadow":
            rgb = a[..., :3]
            l = (rgb @ np.array([0.299, 0.587, 0.114]))[..., None]
            rgb = fit(l + (rgb - l) / 1.08)     # undo PixelPost's saturation boost, like the cards
            for ch in range(3):
                a[..., ch] = np.where(mask, comp(rgb[..., ch]), 0)
        else:
            a[..., 3] = np.where(mask, 80, 0)
        atlas.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), ), (x0, y0))
        pv = Image.fromarray(np.clip(shown, 0, 255).astype(np.uint8))
        preview.alpha_composite(pv, (x0, y0))
    atlas.save(os.path.join(OUT, "beach_atlas.png"))
    meta = {"atlas_px": [ATLAS_W, height], "gain": GAIN, "sprites": {}, "palette": {}}
    for name, (frames, ppm, kind) in cat.items():
        w, h = frames[0].w, frames[0].h
        meta["sprites"][name] = {
            "kind": kind, "size_m": [round(w / ppm, 3), round(h / ppm, 3)],
            "frames": [[r / meta["atlas_px"][j % 2] for j, r in enumerate(rects[(name, i)])] for i in range(len(frames))]}
    for k in ("sand", "sand_dk", "sand_lt", "sand_sh", "wet", "wet_dk", "foam", "shallow", "water", "deep",
              "deeper", "haze", "pad", "pad_dk", "curb", "bamboo", "bamboo_dk", "rope", "white", "wood", "wood_dk", "navy", "red"):
        c = fit(np.array(P[k], float))
        meta["palette"][k] = "#%02x%02x%02x" % tuple(int(round(v)) for v in comp(c))
    with open(os.path.join(OUT, "beach_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    if "--sheet" in sys.argv:
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        preview.save(os.path.join(ROOT, "logs/beach_sheet.png"))
    print("beach atlas %dx%d, %d sprites, %d frames" % (ATLAS_W, height, len(cat), len(items)))


if __name__ == "__main__":
    main()
