#!/usr/bin/env python3
"""Bake 2.5D pixel-card atlases for player profiles (visual only).

Each profile (data/sprite_profiles/<id>.json) describes a body and outfit. This builds
every card part (head, torso, shorts, upper_arm, forearm, hand, thigh, shin, shoe) from
solids at real size, renders 16 views per part, adds pixel-exact details ("decals":
eyes, brows, mouth, nose, ears, laces, buttons, logo, finger lines, knee caps) where
they face the camera, quantises to 3 tones plus a selective outline, pre-compensates
colours for the game's Filmic tonemap and writes one atlas per team:

  assets/pixel_cards/profiles/<id>_blue.png, <id>_red.png
  assets/pixel_cards/profiles/<id>_blue_far.png, <id>_red_far.png  (far tier: half size, 20 degrees)
  assets/pixel_cards/cards_meta.json  ("profiles" entry with its own grid)

Profiles use a finer grid than the original cards (TEXEL m per texel, CELL px cells):
near players are drawn ~2 screen pixels per original texel, so the extra detail shows.
Heads, hands and shoes are drawn slightly larger than life (PART_SCALE) and heads at a
lower camera angle (PART_ELEV) so faces read, like most pixel-art sports games.

Usage: python3 tools/bake_pixel_cards.py [id ...] [--sheet]
  --sheet: assembled standing players, on-screen colours -> logs/sprite_profiles_<team>.png
Run Godot with --import afterwards so the new PNGs load.
"""
import json, math, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = os.path.join(ROOT, "assets/pixel_cards/cards_meta.json")
PROFILES = os.path.join(ROOT, "data/sprite_profiles")
OUT = os.path.join(ROOT, "assets/pixel_cards/profiles")

COLS = 16
TEXEL = 0.028           # m per texel: chunky pixels, ~2x2 screen pixels each up close
CELL = 40               # px per cell
SS = 4                  # supersampling per texel
STEP = 0.005            # solid sampling step (m), < TEXEL / SS
DETAIL = False          # True: fine marks (brows, ears, laces, logo, strands...) for finer grids
ELEV = 44.0             # game camera elevation the cards were measured at
PART_ELEV = {"head": 30.0, "torso": 40.0, "shorts": 44.0, "shoe": 44.0}   # limbs/hand: side view
PART_SCALE = {"head": 1.25, "hand": 1.3, "shoe": 1.15}                      # drawn larger than life
# Limbs were 2-3 texels wide and read as sticks, most of all close up (first person). Radius x this.
LIMB_THICK = {"upper_arm": 1.32, "forearm": 1.36, "thigh": 1.16, "shin": 1.22}
# Hands are drawn on a finer grid (this many texels per normal texel) so fingers can be shown.
PART_DETAIL = {"hand": 2.0}
HAND_STEP = 0.002       # solid sampling step for the hand (its texels are a third of a normal one)
HAND_STATES = ["open", "grip", "reach", "cup"]   # rows: hand, hand_grip, hand_reach, hand_cup
# The same parts seen from other heights. The normal rows are drawn for the match camera
# (PART_ELEV, 30-44 degrees up). "low": about level, another player seen from eye height in
# first person. "top": from almost overhead, your own body when you look down, top cameras.
# Limbs and hands seen along their length. The normal limb and hand rows are pure side views; a
# limb that points toward or away from the eye (your own arm in first person, a leg from above)
# then has no drawing and was squashed into a block. These rows are the same part tilted
# toward the camera by this many degrees: "a" seen from its root end (shoulder, elbow, hip, knee,
# wrist), "b" from its far end. Row names: <part>_a42, <part>_b70, hand_grip_a50, ...
LIMB_AXIAL = (42.0, 70.0)
HAND_AXIAL = (50.0,)
LIMB_PARTS = ["upper_arm", "forearm", "thigh", "shin"]
VIEW_ELEV = {"low": 8.0, "top": 78.0}
VIEW_PARTS = ["head", "torso", "shorts", "shoe"]
LIGHT = np.array([-0.45, 0.75, 0.55]); LIGHT /= np.linalg.norm(LIGHT)
OUTLINE = 0.62          # silhouette texels: colour x this
# Far tier (players across the net): the same rows at half the texel density, with the match
# rows seen from the lower angle the camera has on the far court. Baked next to the near set
# as <id>_<team>_far.png; its grid is the near grid at exactly half size, so the card rig only
# swaps the texture (scripts/graphics/pixel_card_rig.gd).
FAR_TEXEL = 0.056
FAR_CELL = 20
FAR_ELEV = 20.0
FAR_PART_ELEV = {"head": 20.0, "torso": 20.0, "shorts": 20.0, "shoe": 20.0}

TEAMS = {
    "blue": {"T": (83, 152, 236), "T_light": (168, 208, 236), "T_dark": (35, 85, 182)},
    "red":  {"T": (236, 73, 63),  "T_light": (236, 161, 147), "T_dark": (160, 35, 50)},
}

# ---------------------------------------------------------------- tonemap compensation
# Card shader: ALBEDO = texel(linear) * gain, unshaded; then exposure 1.05, Filmic
# (white 6.0, Godot 4 curve), sRGB out. Inverted per channel.
def _filmic(x):
    A, B, C, D, E, F = 0.22 * 4, 0.30 * 2, 0.10, 0.20, 0.01, 0.30
    f = lambda v: (v * (A * v + C * B) + D * E) / (v * (A * v + B) + D * F) - E / F
    return f(x) / f(6.0)

def _s2l(s): return np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)
def _l2s(l): return np.where(l <= 0.0031308, l * 12.92, 1.055 * np.clip(l, 0, None) ** (1 / 2.4) - 0.055)

LUT = os.path.join(ROOT, "assets/pixel_cards/card_tonemap_lut.json")
POST_SATURATION = 1.08   # shaders/pixel_post.gdshader `saturation`

def make_compensator(gain):
    """display colour -> atlas value. Uses the in-engine measurement from
    tools/calibrate_cards.gd when present (card shader + environment + PixelPost),
    else the Filmic model above."""
    if os.path.exists(LUT):
        with open(LUT) as f: lut = json.load(f)
        atlas, screen = np.array(lut["atlas"], float), np.array(lut["screen"], float)
        xs, ys = [], []
        for a_, s_ in zip(atlas, screen):          # strictly increasing for interp
            if not xs or s_ > xs[-1]: xs.append(s_); ys.append(a_)
        xs, ys = np.array(xs), np.array(ys)
        def comp(d):
            d = np.asarray(d, float)
            if d.ndim == 1 and d.shape[0] == 3:   # undo the post's saturation boost
                l = d @ np.array([0.299, 0.587, 0.114])
                d = l + (d - l) / POST_SATURATION
            return np.interp(np.clip(d, xs[0], xs[-1]), xs, ys)
        return comp
    atlas = np.arange(256) / 255.0
    shown = _l2s(np.clip(_filmic(_s2l(atlas) * gain * 1.05), 0, 1)) * 255.0
    limit = 240
    return lambda d: np.interp(np.minimum(d, shown[limit]), shown[:limit + 1], np.arange(limit + 1))

def display_of(atlas_rgb):
    """atlas value -> on-screen colour (for previews), same source as make_compensator."""
    a = np.asarray(atlas_rgb, float)
    if os.path.exists(LUT):
        with open(LUT) as f: lut = json.load(f)
        d = np.interp(a, lut["atlas"], lut["screen"])
        l = d @ np.array([0.299, 0.587, 0.114])
        return np.clip(l[..., None] + (d - l[..., None]) * POST_SATURATION, 0, 255)
    return _l2s(np.clip(_filmic(_s2l(a / 255.0) * 2.2 * 1.05), 0, 1)) * 255

# ---------------------------------------------------------------- colours
def hex_rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def to_hex(c): return "#%02x%02x%02x" % tuple(int(max(0, min(255, round(x)))) for x in c)
def scale_hex(h, f): return to_hex(np.array(hex_rgb(h), float) * f)

def tones(key, team):
    """(light, main, dark) display colours for 'T', 'T_dark', 'T_light' or a hex colour."""
    if key.startswith("T"):
        pal = TEAMS[team]
        if key == "T": return pal["T_light"], pal["T"], pal["T_dark"]
        c = np.array(pal[key], float)
        return tuple(np.minimum(c * 1.15 + 8, 255)), tuple(c), tuple(c * 0.68)
    c = np.array(hex_rgb(key), float)
    return tuple(np.minimum(c * 1.1 + 6, 255)), tuple(c), tuple(c * 0.7)

def const(key): return lambda p: np.full(len(p), key, dtype=object)

# ---------------------------------------------------------------- solids and decals
# Part-local coordinates: x lateral, y up, z forward (toward the camera in view 0),
# metres from the card's joint.

def _grid(lo, hi, step=None):
    step = step or STEP
    axes = [np.arange(a, b + step, step) for a, b in zip(lo, hi)]
    return np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)

class Solid:
    def __init__(self, kind, centre, radii, paint, y0=None, y1=None, keep=None, taper=1.0, priority=0, step=None, end=None):
        self.kind, self.c, self.r = kind, np.array(centre, float), np.array(radii, float)
        self.paint, self.y0, self.y1, self.keep, self.taper, self.priority = paint, y0, y1, keep, taper, priority
        self.step = step or STEP
        self.end = None if end is None else np.array(end, float)
        self._pts = None

    def points(self):
        if self._pts is None: self._pts = self._points()
        return self._pts

    def _points(self):
        c, r = self.c, self.r
        st = self.step
        if self.kind == "cap":     # capsule from c to end, radius r[0] (tapering to r[1] at the end)
            e = self.end; rm = float(max(r[0], r[1]))
            p = _grid(np.minimum(c, e) - rm, np.maximum(c, e) + rm, st)
            ax = e - c; L2 = max(float(ax @ ax), 1e-12)
            t = np.clip(((p - c) @ ax) / L2, 0.0, 1.0)
            near = c + t[:, None] * ax
            rad = r[0] + (r[1] - r[0]) * t
            off = p - near
            m = (off ** 2).sum(1) <= rad ** 2
            p = p[m]; n = off[m]
            n[np.linalg.norm(n, axis=1) < 1e-9] = [0, 0, 1]
        elif self.kind == "ell":
            p = _grid(c - r, c + r, st)
            m = (((p - c) / r) ** 2).sum(1) <= 1.0
            p = p[m]; n = (p - c) / r ** 2
        elif self.kind == "cyl":   # elliptical cylinder along y; radius x taper at y0
            rr = r * max(1.0, self.taper)
            p = _grid([c[0] - rr[0], self.y0, c[2] - rr[2]], [c[0] + rr[0], self.y1, c[2] + rr[2]], st)
            t = (p[:, 1] - self.y0) / max(self.y1 - self.y0, 1e-6)
            scale = self.taper + (1.0 - self.taper) * t
            q = (p[:, [0, 2]] - c[[0, 2]]) / (r[[0, 2]] * scale[:, None])
            m = (q ** 2).sum(1) <= 1.0
            p = p[m]; n = (p - c) / (np.array([r[0], 1.0, r[2]]) * scale[m, None]) ** 2; n[:, 1] = 0.0
            ends = np.zeros(len(p))      # flat caps
            n[p[:, 1] > self.y1 - st * 1.5] += [0, 2.0, 0]
        else:
            p = _grid(c - r, c + r, st)
            n = (p - c) / r
            n = np.where(np.abs(n) == np.abs(n).max(1, keepdims=True), np.sign(n), 0.0)
        if self.keep is not None and len(p):
            m = self.keep(p); p, n = p[m], n[m]
        n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        return p, n

def ell(c, r, paint, **kw): return Solid("ell", c, r, paint, **kw)
def box(c, r, paint, **kw): return Solid("box", c, r, paint, **kw)
def cyl(c, r, y0, y1, paint, **kw): return Solid("cyl", c, [r[0], 0, r[1]], paint, y0=y0, y1=y1, **kw)
def cap(p0, p1, r0, r1, paint, **kw): return Solid("cap", p0, [r0, r1, 0], paint, end=p1, **kw)

class Decal:
    """Pixel-exact mark at a surface point: drawn only when that point is the visible
    surface and faces the camera. pattern: texel offsets; dx > 0 means 'outward' for
    a mark with a side (eyes, brows), i.e. away from the face centre on screen."""
    def __init__(self, p, n, key, pattern=((0, 0),), shade=1, side=0, facing=0.2, essential=False):
        self.p, self.n = np.array(p, float), np.array(n, float) / np.linalg.norm(n)
        self.key, self.pattern, self.shade, self.side, self.facing = key, pattern, shade, side, facing
        self.essential = essential   # drawn even when DETAIL is off (eyes)

def on_ell(c, r, x, y, front=1.0):
    """Point and normal on an ellipsoid's front (z) surface at lateral x, height y."""
    c, r = np.array(c, float), np.array(r, float)
    q = 1.0 - ((x - c[0]) / r[0]) ** 2 - ((y - c[1]) / r[1]) ** 2
    z = c[2] + front * r[2] * math.sqrt(max(q, 0.0))
    p = np.array([x, y, z]); n = (p - c) / r ** 2
    return p, n

# ---------------------------------------------------------------- body parts
def v(d, k, default): return d.get(k, default)

def hair_paint(hair):
    """Hair with strand texture: every third band around the head is a darker strand."""
    dark = scale_hex(hair, 0.72)
    if not DETAIL: return const(hair)
    def f(p):
        k = np.full(len(p), hair, dtype=object)
        band = np.floor(np.arctan2(p[:, 0], p[:, 2] + 0.02) * 9.0 + p[:, 1] * 30.0).astype(int)
        k[band % 3 == 0] = dark
        return k
    return f

HEAD_R = [0.08, 0.1, 0.088]

def head_part(pr):
    h = pr["head"]; skin = pr["skin"]; hair = h.get("hair_color", "#2a1c14")
    female = pr.get("sex") == "female"
    s, d = [], []
    s.append(ell([0, 0, 0], HEAD_R, const(skin)))
    s.append(ell([0, -0.06, 0.02], [0.055, 0.04, 0.06], const(skin)))                   # jaw / chin
    style = h.get("hair", "crew")
    cap = {"buzz": 0.004, "crew": 0.009, "bob": 0.014, "ponytail": 0.01, "bun": 0.01, "curly": 0.018}.get(style, 0.01)
    line = {"buzz": 0.065, "crew": 0.06, "curly": 0.058, "bob": 0.035}.get(style, 0.052)
    low = {"bob": -0.08, "ponytail": -0.035, "bun": -0.035}.get(style, 0.0)
    def keep(p, line=line, low=low):
        face = (p[:, 2] > 0.02) & (p[:, 1] < line)
        sideburn = (np.abs(p[:, 0]) > 0.07) & (p[:, 2] > 0.035) & (p[:, 1] < line + 0.01)
        return ~(face & ~(sideburn & (style == "bob"))) & (p[:, 1] > low)
    s.append(ell([0, 0.006, -0.004], [HEAD_R[0] + cap, HEAD_R[1] + cap, HEAD_R[2] + cap], hair_paint(hair), keep=keep, priority=1))
    if style == "curly":
        for x, y, z in [(-0.05, 0.08, 0.02), (0.05, 0.08, 0.02), (0, 0.1, -0.02), (-0.06, 0.05, -0.05), (0.06, 0.05, -0.05), (0, 0.07, 0.05)]:
            s.append(ell([x, y, z], [0.035, 0.03, 0.035], hair_paint(hair), priority=1))
    if style == "bob":   # fringe
        s.append(ell([0, 0.045, 0.05], [0.075, 0.03, 0.05], hair_paint(hair), priority=1, keep=lambda p: p[:, 2] > 0.02))
    tie = h.get("tie", "T")
    if style == "ponytail":
        s.append(ell([0, 0.06, -0.105], [0.03, 0.03, 0.03], const(tie), priority=2))
        s.append(ell([0, 0.0, -0.13], [0.03, 0.06, 0.03], hair_paint(hair), priority=1))
        s.append(ell([0, -0.08, -0.135], [0.022, 0.05, 0.024], hair_paint(hair), priority=1))
    if style == "bun":
        s.append(ell([0, 0.12, -0.03], [0.048, 0.042, 0.048], hair_paint(hair), priority=1))
        s.append(cyl([0, 0, -0.03], [0.034, 0.034], 0.085, 0.1, const(tie), priority=2))
    if h.get("beard"):
        s.append(ell([0, -0.05, 0.012], [0.079, 0.055, 0.084], const(h.get("beard_color", hair)),
                     keep=lambda p: (p[:, 1] < -0.035) & (p[:, 2] > -0.01), priority=1))
    # Face: eyes, brows, nose, mouth, ears, cheeks. Pixel-exact so they survive the bake.
    eye = h.get("eye", "#1d1a22")
    for sx in (-1, 1):
        p, n = on_ell([0, 0, 0], HEAD_R, sx * 0.03, 0.006)
        d.append(Decal(p, n, "#ece8e2", ((1, 0), (1, 1)), side=sx))      # eye white (outer side)
        d.append(Decal(p, n, eye, (((0, 0), (0, 1)) if not female else ((0, 0), (0, 1), (1, -1))) if DETAIL else ((0, 0),),
                       side=sx, essential=True))
        p, n = on_ell([0, 0, 0], HEAD_R, sx * 0.032, 0.032)
        d.append(Decal(p, n, scale_hex(hair, 0.8), ((-1, 0), (0, 0), (1, 0)) if not female else ((0, 0), (1, 0)), side=sx))
        p, n = on_ell([0, 0, 0], HEAD_R, sx * 0.079, -0.005)
        d.append(Decal(p, n, skin, ((0, 0), (0, 1)), shade=2, facing=-0.6))
        if female:
            p, n = on_ell([0, 0, 0], HEAD_R, sx * 0.048, -0.028)
            d.append(Decal(p, n, "#e39a8a", ((0, 0),)))
    p, n = on_ell([0, 0, 0], HEAD_R, 0.0, -0.016)
    d.append(Decal(p, n, skin, ((0, 0), (0, 1)), shade=2))
    p, n = on_ell([0, -0.06, 0.02], [0.055, 0.04, 0.06], 0.0, -0.05)
    d.append(Decal(p, n, "#b4565c" if female else scale_hex(skin, 0.62), ((-1, 0), (0, 0), (1, 0)) if female else ((-1, 0), (0, 0))))
    if h.get("sunglasses"):
        s.append(box([0, 0.008, 0.08], [0.068, 0.013, 0.012], const("#101114"), priority=3))
        p, n = on_ell([0, 0, 0], HEAD_R, -0.03, 0.012)
        d.append(Decal(p + [0, 0, 0.012], [0, 0.2, 1], "#8fa8c8", ((0, 0),), shade=0))
    wear = h.get("headwear")
    col = h.get("headwear_color", "T")
    if wear == "visor":
        s.append(cyl([0, 0, -0.004], [0.094, 0.104], 0.05, 0.072, const(col), priority=2, keep=lambda p: p[:, 2] > -0.06))
        s.append(box([0, 0.068, 0.098], [0.068, 0.005, 0.026], const(col), priority=2))
    elif wear == "headband":
        s.append(cyl([0, 0, -0.004], [0.095, 0.105], 0.04, 0.04 + v(h, "headband_width", 0.022), const(col), priority=2))
    elif wear == "bucket_hat":
        s.append(cyl([0, 0, -0.01], [0.09, 0.098], 0.06, 0.125, const(col), priority=2, taper=1.06))
        s.append(cyl([0, 0, -0.01], [0.09, 0.098], 0.06, 0.072, const(scale_hex(col, 0.7)), priority=3, taper=1.06))
        s.append(cyl([0, 0, -0.01], [0.12, 0.126], 0.052, 0.062, const(col), priority=2))
    return s, d

def torso_part(pr):
    t = pr["torso"]; top = pr["top"]; skin = pr["skin"]
    sh, waist, chest, belly = v(t, "shoulders", 1.0), v(t, "waist", 1.0), v(t, "chest", 0.0), v(t, "belly", 0.0)
    female = pr.get("sex") == "female"
    body = top.get("color", "T")
    kind = top.get("type", "tee")
    tank = kind in ("tank", "racerback", "muscle_tank")

    def paint_top(p):
        k = np.full(len(p), body, dtype=object)
        ax = np.abs(p[:, 0])
        if "sides" in top: k[ax > 0.105 * waist + 0.02] = top["sides"]
        if "stripe" in top: k[(p[:, 1] > 0.0) & (p[:, 1] < 0.03) & (p[:, 2] > 0)] = top["stripe"]
        if "shoulders" in top: k[p[:, 1] > 0.085] = top["shoulders"]
        if "hem" in top: k[p[:, 1] < -0.22] = top["hem"]
        # side seam: a darker line down each side
        if DETAIL: k[(ax > 0.125 * waist) & (ax < 0.125 * waist + 0.008) & (np.abs(p[:, 2]) < 0.02)] = \
            "T_dark" if body == "T" else scale_hex(body, 0.8)
        if tank:   # scoop neckline front, deeper armholes for a muscle tank
            k[(p[:, 1] > 0.08) & (ax < 0.055) & (p[:, 2] > 0.0)] = skin
            if kind == "muscle_tank": k[(ax > 0.105 * sh) & (p[:, 1] > -0.02)] = skin
            if kind == "racerback": k[(p[:, 1] > 0.06) & (ax > 0.06) & (p[:, 2] < 0.0)] = skin
        if "collar" in top: k[(p[:, 1] > 0.115) & (ax < 0.075)] = top["collar"]
        return k

    s, d = [], []
    s.append(cyl([0, 0, -0.004], [0.042, 0.042], 0.12, 0.2, const(skin)))                    # neck
    # Silhouette: shoulders -> ribcage -> narrowest waist -> flare to the hips. The torso
    # runs down to the shorts' waistband so the two cards overlap and never gap.
    # Exaggerated a little: at 2.8 cm pixels a true-to-life waist is under one pixel.
    rw = (0.088 if female else 0.1) * waist + 0.03 * belly       # waist (narrowest)
    rh = (0.14 if female else 0.125) * v(t, "hips", 1.0)         # top of the hips, meets the waistband
    rib = 0.135 * sh
    s.append(cyl([0, 0, 0], [0.145 * sh, 0.1], 0.0, 0.13, paint_top, taper=rib / (0.145 * sh)))     # chest
    s.append(cyl([0, 0, 0], [rib, 0.095], -0.16, 0.0, paint_top, taper=rw / rib))                   # ribcage -> waist
    s.append(cyl([0, 0, 0], [rw, 0.08 + belly * 0.03], -0.36, -0.16, paint_top, taper=rh / rw))     # waist -> hips
    if belly > 0:
        s.append(ell([0, -0.14, 0.035], [0.12 * waist, 0.1, 0.06 + 0.05 * belly], paint_top))
    if female and chest > 0:
        for x in (-0.055, 0.055):
            s.append(ell([x * sh, 0.03, 0.06], [0.06, 0.055, 0.035 + 0.045 * chest], paint_top))
    elif chest > 0:
        for x in (-0.06, 0.06):   # pecs
            s.append(ell([x * sh, 0.05, 0.05], [0.075 * sh, 0.06, 0.03 + 0.04 * chest], paint_top))
    cap = top.get("sleeve", body) if not tank else skin
    r = [0.06 * sh, 0.055, 0.07] if not tank else [0.045 * sh, 0.04, 0.05]
    for x in (-1, 1):
        s.append(ell([x * 0.15 * sh, 0.085, 0], r, const(cap)))
    # collar band / crew neck rib
    if kind == "polo":
        s.append(cyl([0, 0, 0.0], [0.06, 0.055], 0.11, 0.14, const(top.get("collar", body)), priority=1))
        for y in (0.085, 0.06):
            d.append(Decal([0, y, 0.1], [0, 0, 1], scale_hex(top["collar"], 0.7) if top.get("collar", "T") != "T" else "T_dark"))
    elif not tank:
        s.append(cyl([0, 0, 0.0], [0.05, 0.048], 0.12, 0.135, const("T_dark" if body == "T" else scale_hex(body, 0.8)), priority=1))
    # chest logo (left chest) and back number stripe
    logo = top.get("logo", "#f4f4f2" if body == "T" else "T")
    d.append(Decal([0.065 * sh, 0.06, 0.1 + (0.03 if female and chest > 0 else 0.0)], [0, 0, 1], logo, ((0, 0), (1, 0), (0, 1), (1, 1))))
    return s, d

def bottom_part(pr):
    b = pr["bottom"]; kind = b.get("type", "shorts"); col = b.get("color", "T")
    w = v(pr["torso"], "hips", 1.0) * (1.08 if pr.get("sex") == "female" else 1.0)
    s, d = [], []
    if kind.startswith("skirt"):
        length, flare = v(b, "length", 0.17), v(b, "flare", 0.05)
        y0, y1 = 0.07 - length, 0.075
        taper = (0.15 * w + flare) / (0.13 * w)          # waist-fitted top, flared hem
        def paint(p, col=col, kind=kind):
            k = np.full(len(p), col, dtype=object)
            ang = np.arctan2(p[:, 0], p[:, 2])
            if kind == "skirt_pleated":
                k[(np.floor(ang / (0.26 if DETAIL else 0.5)) % 2 == 0) & (p[:, 1] < 0.03)] = b.get("pleat", "T_dark")
            if kind == "skirt_aline":
                k[(np.abs(np.sin(ang * 3)) < 0.08) & (p[:, 1] < 0.04)] = scale_hex(col, 0.75) if col[0] == "#" else "T_dark"
            if kind == "skirt_ruffle":
                tier = np.floor((y1 - p[:, 1]) / (length / 3)).astype(int)
                k[tier % 2 == 1] = b.get("tier", "T_dark")
            if "panel" in b: k[np.abs(p[:, 0]) > 0.13] = b["panel"]
            if "hem" in b: k[p[:, 1] < y0 + 0.016] = b["hem"]
            return k
        s.append(cyl([0, 0, 0], [0.13 * w, 0.092], y0, y1, paint, taper=taper))
    else:
        def paint(p, col=col):
            k = np.full(len(p), col, dtype=object)
            if "stripe" in b: k[np.abs(p[:, 0]) > 0.14 * w] = b["stripe"]
            if "hem" in b: k[p[:, 1] < -0.08] = b["hem"]
            if b.get("pockets"): k[(np.abs(p[:, 0]) > 0.11 * w) & (p[:, 1] < -0.02) & (p[:, 1] > -0.07)] = scale_hex(col, 0.82)
            return k
        s.append(cyl([0, 0, 0], [0.128 * w, 0.09], 0.0, 0.075, paint, taper=1.25))     # waist -> widest hip
        s.append(cyl([0, 0, 0], [0.16 * w, 0.112], -0.095, 0.0, paint, taper=0.95))   # hip -> leg openings
        d.append(Decal([0.012, 0.055, 0.094], [0, 0, 1], b.get("drawstring", "#f1efe8"), ((0, 0), (0, 1))))
        d.append(Decal([-0.012, 0.055, 0.094], [0, 0, 1], b.get("drawstring", "#f1efe8"), ((0, 0), (0, 1))))
    band = b.get("waistband", "T_dark" if col == "T" else scale_hex(col, 0.78))
    s.append(cyl([0, 0, 0], [0.132 * w, 0.094], 0.058, 0.08, const(band), priority=1))
    return s, d

def limb(length, r_top, r_bot, base, covers):
    """Vertical limb from y=0 down to -length. covers: (from_frac, to_frac, key, extra_r)."""
    s = [cyl([0, 0, 0], [r_top, r_top * 0.9], -length, 0, const(base), taper=r_bot / r_top)]
    for a, b_, key, extra in covers:
        y1, y0 = -a * length, -b_ * length
        t = (y1 + y0) * 0.5 / -length
        r = r_top + (r_bot - r_top) * t + extra
        s.append(cyl([0, 0, 0], [r, r * 0.9], y0, y1, const(key), priority=1))
    return s

def upper_arm_part(pr, L):
    a = pr["arms"]; g = v(a, "upper", 1.0) * LIMB_THICK["upper_arm"]; top = pr["top"]
    sleeved = top.get("type") in ("tee", "polo", "compression")
    covers = []
    sl = v(top, "sleeve_length", 0.4)
    if sleeved:
        covers.append((0.0, sl, top.get("sleeve", top.get("color", "T")), 0.008))
        covers.append((sl - 0.06, sl, top.get("cuff", "T_dark" if top.get("sleeve", top.get("color", "T")) == "T" else scale_hex(top.get("sleeve", "#888888"), 0.8)), 0.01))
    if a.get("tattoo"):
        covers.append((0.5, 0.56, a["tattoo"], 0.002)); covers.append((0.6, 0.64, a["tattoo"], 0.002))
    s = limb(L, 0.042 * g, 0.034 * g, pr["skin"], covers)
    if DETAIL:
        s.append(ell([0, -0.42 * L, 0.01], [0.046 * g, 0.075, 0.052 * g], const(pr["skin"])))      # biceps
        s.append(ell([0, -0.5 * L, -0.012], [0.04 * g, 0.08, 0.045 * g], const(pr["skin"])))      # triceps
    s.append(ell([0, 0, 0], [0.05 * g, 0.045, 0.05 * g], const(covers[0][2] if sleeved else pr["skin"])))
    # The elbow end is rounded so it meets the forearm's elbow as a joint, not a seam.
    s.append(ell([0, -L, 0], [0.037 * g, 0.03, 0.037 * g], const(pr["skin"] if not (sleeved and sl >= 0.95) else covers[0][2])))
    return s, []

def forearm_part(pr, L):
    a = pr["arms"]; g = v(a, "fore", 1.0) * LIMB_THICK["forearm"]; acc = a.get("forearm", {})
    skin = a.get("forearm_skin", pr["skin"])
    covers = []
    kind, col = acc.get("type"), acc.get("color", "#1a1a1a")
    if kind == "wristband": covers.append((0.78, 0.97, col, 0.012))
    if kind == "watch":
        covers.append((0.84, 0.94, "#2a2a2e", 0.006)); covers.append((0.86, 0.92, col, 0.012))
    if kind == "elbow_sleeve": covers.append((0.0, 0.42, col, 0.006))
    if kind == "compression_sleeve": covers.append((0.0, 0.95, col, 0.004))
    s = limb(L, 0.038 * g, 0.027 * g, skin, covers)
    if DETAIL: s.append(ell([0, -0.22 * L, 0.004], [0.042 * g, 0.075, 0.04 * g], const(covers[0][2] if covers and covers[0][0] == 0.0 else skin)))
    elbow = skin if not covers or covers[0][0] > 0 else covers[0][2]
    # The elbow: a knob a little wider than the arm, with its point shaded at the back.
    s.append(ell([0, -0.004, -0.004], [0.043 * g, 0.036, 0.045 * g], const(elbow)))
    d = [Decal([0, -0.012, -0.047 * g], [0, 0, -1], elbow, ((0, 0), (0, 1)), shade=2, essential=True)]
    return s, d

def hand_part(pr, state="open"):
    """A hand with a palm, four fingers and a thumb, on the hand's finer grid (PART_DETAIL).
    y runs down from the wrist, x across the palm (+ = thumb side), z out of the palm.
    open:  ready for the ball: fingers straight and a little apart, thumb out.
    grip:  closed round the paddle handle (either hand that is on the paddle).
    reach: fingers straight and spread wide, at full stretch.
    cup:   holding the ball: fingers and thumb curled forward round it, palm hollowed."""
    a = pr["arms"]; S = v(a, "hand", 1.0); col = a.get("glove", pr["skin"])
    kw = {"step": HAND_STEP}
    paint = const(col)
    s, d = [], []
    s.append(ell([0, -0.036 * S, 0], [0.037 * S, 0.040 * S, 0.016 * S], paint, **kw))                   # palm
    s.append(cap([0, 0.004 * S, 0], [0, -0.014 * S, 0], 0.024 * S, 0.028 * S, paint, **kw))             # wrist
    xs = (0.026, 0.0088, -0.0088, -0.026)          # index, middle, ring, little across the knuckles
    lens = (0.058, 0.064, 0.059, 0.046)
    ky = -0.068
    r = 0.0086 * S
    line_z = 0.016
    if state == "grip":
        for x in xs:    # over the knuckle, down the front, tips tucked back toward the palm
            s.append(cap([x * S, ky * S, 0.002 * S], [x * S, (ky - 0.020) * S, 0.022 * S], r, r, paint, **kw))
            s.append(cap([x * S, (ky - 0.020) * S, 0.022 * S], [x * S, (ky + 0.004) * S, 0.032 * S], r, r * 0.92, paint, **kw))
        s.append(cap([0.034 * S, -0.026 * S, 0.010 * S], [-0.006 * S, -0.058 * S, 0.036 * S], 0.0105 * S, 0.0095 * S, paint, **kw))   # thumb across
        line_z = 0.030
    elif state == "cup":
        for x, L in zip(xs, lens):   # out from the knuckle, then curling forward and up round the ball
            mid = [x * 1.12 * S, (ky - L * 0.5) * S, 0.022 * S]
            tip = [x * 1.16 * S, (ky - L * 0.62) * S, 0.048 * S]
            s.append(cap([x * S, ky * S, 0.002 * S], mid, r, r * 0.95, paint, **kw))
            s.append(cap(mid, tip, r * 0.95, r * 0.86, paint, **kw))
        s.append(cap([0.030 * S, -0.022 * S, 0.008 * S], [0.050 * S, -0.050 * S, 0.026 * S], 0.0105 * S, 0.0098 * S, paint, **kw))   # thumb, curling in
        s.append(cap([0.050 * S, -0.050 * S, 0.026 * S], [0.040 * S, -0.064 * S, 0.046 * S], 0.0098 * S, 0.009 * S, paint, **kw))
        line_z = 0.026
    else:
        spread = 1.55 if state == "reach" else 1.24
        curl = 0.004 if state == "reach" else 0.009
        grow = 1.06 if state == "reach" else 1.0
        for x, L in zip(xs, lens):
            tip = [x * spread * S, (ky - L * grow) * S, curl * S]
            s.append(cap([x * S, ky * S, 0.0], tip, r, r * 0.86, paint, **kw))
        if state == "reach":
            s.append(cap([0.030 * S, -0.020 * S, 0.004 * S], [0.070 * S, -0.050 * S, 0.006 * S], 0.0105 * S, 0.009 * S, paint, **kw))
        else:
            s.append(cap([0.030 * S, -0.022 * S, 0.006 * S], [0.062 * S, -0.058 * S, 0.012 * S], 0.0105 * S, 0.009 * S, paint, **kw))
    # The lines between the fingers, on both faces (pixel-exact, so they survive the downsample).
    line = ((0, 0), (0, 1), (0, 2)) if state in ("grip", "cup") else ((0, 0), (0, 1), (0, 2), (0, 3))
    for x in (0.0174, 0.0, -0.0174):
        y = (ky - 0.008) * S if state in ("grip", "cup") else (ky - 0.006) * S
        sx = x * {"reach": 1.12, "open": 1.06, "cup": 1.06}.get(state, 1.0)
        d.append(Decal([sx * S, y, line_z * S], [0, 0, 1], col, line, shade=2, essential=True, facing=0.3))
        d.append(Decal([sx * S, y, -0.012 * S], [0, 0, -1], col, line, shade=2, essential=True, facing=0.3))
    for x in xs:      # knuckles, a light spot each on the back of the hand
        d.append(Decal([x * S, (ky + 0.004) * S, -0.012 * S], [0, 0, -1], col, ((0, 0),), shade=0, essential=True, facing=0.3))
    if a.get("tape"):
        s.append(box([0, -0.062 * S, 0], [0.036 * S, 0.006, 0.018 * S], const(a["tape"]), priority=1, **kw))
    return s, d

def thigh_part(pr, L):
    lg = pr["legs"]; g = v(lg, "thigh", 1.0) * LIMB_THICK["thigh"]; b = pr["bottom"]
    covers = []
    cov, key = v(b, "thigh_cover", 0.25), b.get("color", "T")
    skirt = b.get("type", "").startswith("skirt")
    if skirt:
        if b.get("under"): covers.append((0.0, v(b, "under_length", 0.22), b["under"], 0.004))
        covers.append((0.0, cov, key, 0.012 + v(b, "flare", 0.05) * 0.2))
    elif cov > 0:
        covers.append((0.0, min(cov, 1.0), key, 0.01))
        if "hem" in b: covers.append((min(cov, 1.0) - 0.06, min(cov, 1.0), b["hem"], 0.012))
    s = limb(L, 0.062 * g, 0.045 * g, pr["skin"], covers)
    if DETAIL: s.append(ell([0, -0.45 * L, 0.012], [0.058 * g, 0.12, 0.05 * g], const(covers[-1][2] if cov > 0.5 and not skirt else pr["skin"])))  # quads
    if "stripe" in b and cov > 0 and not skirt:
        r = 0.062 * g + 0.013
        s.append(cyl([0, 0, 0], [r, r * 0.9], -min(cov, 1.0) * L, 0, const(b["stripe"]), priority=2,
                     keep=lambda p: np.abs(p[:, 0]) > r * 0.75))
    d = []
    if cov < 0.85:   # kneecap highlight
        d.append(Decal([0, -L + 0.015, 0.046 * g], [0, 0, 1], pr["skin"], ((0, 0), (1, 0)), shade=0, essential=True))
    return s, d

def shin_part(pr, L):
    lg = pr["legs"]; g = v(lg, "shin", 1.0) * LIMB_THICK["shin"]; sock = lg.get("socks", {})
    covers = []
    b = pr["bottom"]
    over = v(b, "thigh_cover", 0.25) - 1.0
    if over > 0: covers.append((0.0, over, b.get("color", "T"), 0.02))
    if lg.get("brace") and lg["brace"].get("part") == "shin":
        covers.append((0.0, 0.22, lg["brace"]["color"], 0.012)); covers.append((0.06, 0.1, "#2a2a2e", 0.014))
    sh = v(sock, "height", 0.12)
    scol = sock.get("color", "#f1efe8")
    if sh > 0:
        covers.append((1.0 - sh, 1.0, scol, 0.006))
        covers.append((1.0 - sh, 1.0 - sh + 0.04, scale_hex(scol, 0.85) if scol[0] == "#" else "T_dark", 0.008))   # cuff rib
    for st in sock.get("stripes", []):
        covers.append((st[0], st[1], st[2], 0.008))
    if lg.get("calf_sleeve"): covers.append((0.25, 0.7, lg["calf_sleeve"], 0.006))
    if lg.get("ankle_tape"):
        covers.append((0.84, 0.98, lg["ankle_tape"], 0.01)); covers.append((0.9, 0.92, scale_hex(lg["ankle_tape"], 0.8), 0.011))
    s = limb(L, 0.045 * g, 0.028 * g, pr["skin"], covers)
    if DETAIL: s.append(ell([0, -0.3 * L, -0.014], [0.045 * g, 0.085, 0.046 * g], const(pr["skin"] if not lg.get("calf_sleeve") else lg["calf_sleeve"])))   # calf
    knee = covers[0][2] if covers and covers[0][0] == 0.0 and covers[0][1] > 0.05 else pr["skin"]
    s.append(ell([0, -0.004, 0.006], [0.049 * g, 0.04, 0.05 * g], const(knee)))                    # the knee, a knob
    return s, []

def shoe_part(pr):
    sh = pr["shoes"]; col, sole = sh.get("color", "#f1efe8"), sh.get("sole", "#d3d1c7")
    w = v(sh, "width", 1.0)
    s = [box([0, -0.087, 0.045], [0.046 * w, 0.011, 0.13], const(sole)),
         ell([0, -0.052, 0.04], [0.045 * w, 0.04, 0.125], const(col), keep=lambda p: p[:, 1] > -0.076),
         ell([0, -0.06, 0.13], [0.04 * w, 0.025, 0.05], const(sh.get("toe", scale_hex(col, 0.9) if col[0] == "#" else col)), priority=1,
             keep=lambda p: p[:, 1] > -0.076)]
    collar = 0.02 if sh.get("high") else -0.02
    s.append(cyl([0, 0, -0.03], [0.042 * w, 0.05], -0.07, collar, const(col)))
    s.append(cyl([0, 0, -0.03], [0.043 * w, 0.051], collar - 0.012, collar, const(sh.get("collar", scale_hex(col, 0.82))), priority=1))
    if "accent" in sh:
        s.append(box([0, -0.056, 0.02], [0.047 * w, 0.009, 0.06], const(sh["accent"]), priority=1,
                     keep=lambda p: np.abs(p[:, 0]) > 0.04 * w))
    if "heel" in sh:
        s.append(box([0, -0.05, -0.078], [0.03 * w, 0.028, 0.01], const(sh["heel"]), priority=1))
    lace = sh.get("laces", "#c9c6bc" if hex_rgb(col if col[0] == "#" else "#ffffff")[0] > 200 else "#f1efe8")
    d = [Decal([0, -0.014 - z * 0.25, z], [0, 1, 0.35], lace, ((-1, 0), (1, 0)), facing=0.1) for z in (0.02, 0.05, 0.08)]
    return s, d

# ---------------------------------------------------------------- rendering
def render(solids, decals, view, anchor, elev_deg, mpt):
    """One view of a part -> (code[CELL,CELL] int: key_id*3+shade or -1, keys, edge mask).
    Joint at `anchor` texel. Front-most surface wins; accessories (priority) win ties."""
    th, e = math.radians(view * 22.5), math.radians(elev_deg)
    ry = np.array([[math.cos(th), 0, math.sin(th)], [0, 1, 0], [-math.sin(th), 0, math.cos(th)]])
    rx = np.array([[1, 0, 0], [0, math.cos(e), -math.sin(e)], [0, math.sin(e), math.cos(e)]])
    rot = rx @ ry
    n_sub = CELL * SS
    depth = np.full((n_sub, n_sub), -np.inf); rawz = np.full((n_sub, n_sub), -np.inf)
    code = np.full((n_sub, n_sub), -1)
    keys, key_id = [], {}
    for sd in solids:
        p, n = sd.points()
        if not len(p): continue
        kk = sd.paint(p)
        pc, nc = p @ rot.T, n @ rot.T
        u = np.floor((anchor[0] + pc[:, 0] / mpt) * SS).astype(int)
        w = np.floor((anchor[1] - pc[:, 1] / mpt) * SS).astype(int)
        ok = (u >= 0) & (u < n_sub) & (w >= 0) & (w < n_sub)
        u, w, z, nc, kk = u[ok], w[ok], pc[ok, 2], nc[ok], kk[ok]
        lit = nc @ LIGHT
        shade = np.where(lit > 0.72, 0, np.where(lit > -0.1, 1, 2))
        uk, inv = np.unique(kk.astype(str), return_inverse=True)
        ids = np.array([key_id.setdefault(k, len(key_id)) for k in uk])
        for k in uk:
            if k not in keys: keys.append(k)
        c = ids[inv.reshape(-1)] * 3 + shade
        score = z + sd.priority * 0.006
        order = np.argsort(score)
        u, w, score, z, c = u[order], w[order], score[order], z[order], c[order]
        better = score > depth[w, u]
        u, w, score, z, c = u[better], w[better], score[better], z[better], c[better]
        depth[w, u] = score; rawz[w, u] = z; code[w, u] = c
    keys = sorted(key_id, key=key_id.get)
    # Downsample: solid when >= 40% of subsamples are; value = most common subsample code.
    blk = code.reshape(CELL, SS, CELL, SS).transpose(0, 2, 1, 3).reshape(CELL, CELL, SS * SS)
    zb = rawz.reshape(CELL, SS, CELL, SS).max((1, 3))
    solid = (blk >= 0).mean(2) >= 0.4
    out = np.full((CELL, CELL), -1)
    for y, x in zip(*np.nonzero(solid)):
        vals = blk[y, x][blk[y, x] >= 0]
        out[y, x] = np.bincount(vals).argmax()
    # Cleanup: a texel matching none of its 4 neighbours, while 3+ of them agree, takes
    # their colour. Removes speckles where shading tones meet; 1-px lines survive.
    for _ in range(2):
        pad = np.pad(out, 1, constant_values=-1)
        nb = np.stack([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]])
        for y, x in zip(*np.nonzero(solid)):
            n = nb[:, y, x]
            if (n == out[y, x]).any(): continue
            vals, cnt = np.unique(n[n >= 0], return_counts=True)
            if len(cnt) and cnt.max() >= 3: out[y, x] = vals[cnt.argmax()]
    edge = np.zeros_like(solid)
    if solid.sum() > 14:
        pad = np.pad(solid, 1)
        edge = solid & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    # Decals: pixel-exact marks on visible, camera-facing surface points.
    centre_x = anchor[0]
    for dc in decals:
        if not (DETAIL or dc.essential): continue
        pc, nc = rot @ dc.p, rot @ dc.n
        if nc[2] < dc.facing: continue
        x = int(math.floor(anchor[0] + pc[0] / mpt)); y = int(math.floor(anchor[1] - pc[1] / mpt))
        if not (0 <= x < CELL and 0 <= y < CELL) or not solid[y, x] or zb[y, x] > pc[2] + 0.012: continue
        out_sign = 1 if (rot @ np.array([dc.side, 0, 0]))[0] >= 0 else -1
        kid = key_id.setdefault(dc.key, len(key_id))
        if kid >= len(keys): keys.append(dc.key)
        for dx, dy in dc.pattern:
            xx, yy = x + dx * (out_sign if dc.side else 1), y + dy
            if 0 <= xx < CELL and 0 <= yy < CELL and solid[yy, xx]:
                out[yy, xx] = kid * 3 + dc.shade
                edge[yy, xx] = False
    return out, keys, edge

def colourise(out, keys, edge, team, comp):
    img = np.zeros((CELL, CELL, 4), np.uint8)
    table = {}
    for y, x in zip(*np.nonzero(out >= 0)):
        c = out[y, x]
        if c not in table: table[c] = np.array(tones(keys[c // 3], team)[c % 3], float)
        rgb = table[c] * (OUTLINE if edge[y, x] else 1.0)
        img[y, x, :3] = np.clip(np.round(comp(rgb)), 0, 255)
        img[y, x, 3] = 255
    return img

def grid_for(meta):
    """Profile grid: the original nine rows at TEXEL / CELL, then the extra rows.
    hand rows carry "detail" (texels per normal texel); *_low / *_top are other view heights."""
    k = meta["meters_per_texel"] / TEXEL
    off = (CELL - meta["cell"][0] * k) / 2.0
    parts = {}
    for name, info in meta["parts"].items():
        q = {"row": info["row"], "anchor": [info["anchor"][0] * k + off, info["anchor"][1] * k + off]}
        if "end" in info: q["end"] = [info["end"][0] * k + off, info["end"][1] * k + off]
        if name in PART_DETAIL: q["detail"] = PART_DETAIL[name]
        parts[name] = q
    row = int(meta["rows"])
    for state in HAND_STATES[1:]:
        q = dict(parts["hand"]); q["row"] = row; row += 1
        parts["hand_" + state] = q
    for tag in VIEW_ELEV:
        for name in VIEW_PARTS:
            q = dict(parts[name]); q["row"] = row; q["elev"] = VIEW_ELEV[tag]; row += 1
            parts["%s_%s" % (name, tag)] = q
    def axial(base, degrees):
        nonlocal row
        for e in degrees:
            for tag, sign in (("a", 1.0), ("b", -1.0)):
                q = dict(parts[base]); q["row"] = row; q["axial"] = sign * e; q["of"] = base; row += 1
                if "end" in q:      # the far joint, where the tilted drawing puts it
                    q["end"] = [q["end"][0], q["anchor"][1] + (q["end"][1] - q["anchor"][1]) * math.cos(math.radians(e))]
                parts["%s_%s%d" % (base, tag, int(e))] = q
    for name in LIMB_PARTS: axial(name, LIMB_AXIAL)
    for state in HAND_STATES: axial("hand" if state == "open" else "hand_" + state, HAND_AXIAL)
    return {"cell": [CELL, CELL], "cols": COLS, "rows": row, "meters_per_texel": TEXEL, "parts": parts,
            "view_elev": dict(VIEW_ELEV, mid=ELEV)}

def build_parts(pr, grid):
    parts = grid["parts"]
    L = lambda name: (parts[name]["end"][1] - parts[name]["anchor"][1]) * TEXEL
    built = {
        "head": head_part(pr), "torso": torso_part(pr), "shorts": bottom_part(pr),
        "upper_arm": upper_arm_part(pr, L("upper_arm")), "forearm": forearm_part(pr, L("forearm")),
        "hand": hand_part(pr, "open"), "thigh": thigh_part(pr, L("thigh")), "shin": shin_part(pr, L("shin")),
        "shoe": shoe_part(pr),
    }
    for state in HAND_STATES[1:]: built["hand_" + state] = hand_part(pr, state)
    return built

def bake_far(pid, meta):
    """The far-tier set of one profile: {"textures", "grid"} for its "far" meta entry."""
    global TEXEL, CELL, PART_ELEV
    keep = (TEXEL, CELL, PART_ELEV)
    TEXEL, CELL, PART_ELEV = FAR_TEXEL, FAR_CELL, FAR_PART_ELEV
    try: out = bake(pid, meta, "_far")
    finally: TEXEL, CELL, PART_ELEV = keep
    out["grid"]["elevation_deg"] = FAR_ELEV
    return {"textures": out["textures"], "grid": out["grid"]}

def bake(pid, meta, suffix=""):
    with open(os.path.join(PROFILES, pid + ".json")) as f: pr = json.load(f)
    comp = make_compensator(float(meta.get("gain", 1.0)))
    grid = grid_for(meta)
    parts = build_parts(pr, grid)
    rows = int(grid["rows"])
    atlases = {team: np.zeros((rows * CELL, COLS * CELL, 4), np.uint8) for team in TEAMS}
    jobs = []     # (row name, solids, decals, base part, elevation)
    for name, (solids, decals) in parts.items():
        base = "hand" if name.startswith("hand") else name
        jobs.append((name, solids, decals, base, PART_ELEV.get(base, 0.0)))
    for tag, elev in VIEW_ELEV.items():
        for name in VIEW_PARTS:
            jobs.append(("%s_%s" % (name, tag), parts[name][0], parts[name][1], name, elev))
    for name, info in grid["parts"].items():
        if "axial" in info:
            src = info["of"]
            jobs.append((name, parts[src][0], parts[src][1], "hand" if src.startswith("hand") else src, float(info["axial"])))
    for name, solids, decals, base, elev in jobs:
        info = grid["parts"][name]
        mpt = TEXEL / PART_SCALE.get(base, 1.0) / PART_DETAIL.get(base, 1.0)
        for k in range(COLS):
            out, keys, edge = render(solids, decals, k, info["anchor"], elev, mpt)
            for team, atlas in atlases.items():
                atlas[info["row"] * CELL:(info["row"] + 1) * CELL, k * CELL:(k + 1) * CELL] = colourise(out, keys, edge, team, comp)
    paths = {}
    for team, atlas in atlases.items():
        rel = "profiles/%s_%s%s.png" % (pid, team, suffix)
        Image.fromarray(atlas).save(os.path.join(ROOT, "assets/pixel_cards", rel))
        paths[team] = "res://assets/pixel_cards/" + rel
    return {"name": pr.get("name", pid), "sex": pr.get("sex", ""), "paddle": pr.get("paddle", ""),
            "textures": paths, "grid": grid}

# ---------------------------------------------------------------- previews
_JOINTS = {"head": (0, 0.33), "torso": (0, 0.05), "shorts": (0, -0.37)}
_LIMBS = [("upper_arm", 0.18, 0.15), ("forearm", 0.19, -0.1), ("hand", 0.19, -0.35),
          ("thigh", 0.11, -0.33), ("shin", 0.11, -0.64), ("shoe", 0.11, -0.94)]

def _display(atlas, gain):
    a = np.array(atlas).astype(float)
    a[..., :3] = display_of(a[..., :3])
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")

def _figure(atlas, k, grid):
    """One standing player at view k assembled from the cards, like pixel_card_rig.gd."""
    mpt, ce = grid["meters_per_texel"], math.cos(math.radians(ELEV))
    canvas = Image.new("RGBA", (CELL * 3 // 2, CELL * 9 // 4), (0, 0, 0, 0))
    ox, oy = canvas.width // 2, int(CELL * 0.75)
    th = math.radians(k * 22.5)
    items = []
    def cell(name, kk):
        r = grid["parts"][name]["row"]
        return atlas.crop((kk * CELL, r * CELL, (kk + 1) * CELL, (r + 1) * CELL))
    for name, (x, y) in _JOINTS.items():
        items.append((0.001 if name == "head" else 0.0, cell(name, k), x, y, grid["parts"][name]["anchor"], 1.0))
    for side in (-1, 1):
        for name, x, y in _LIMBS:
            info = grid["parts"][name]
            img = cell(name, k if side < 0 else (COLS - k) % COLS)
            if side > 0: img = img.transpose(Image.FLIP_LEFT_RIGHT)
            img.info["detail"] = float(info.get("detail", 1.0))
            sy = ce if "end" in info and name != "hand" else 1.0
            items.append((side * x * math.sin(th), img, -side * x, y, info["anchor"], sy))
    for depth, img, x, y, anc, sy in sorted(items, key=lambda t: t[0]):
        if sy != 1.0: img = img.resize((CELL, max(1, round(CELL * sy))), Image.NEAREST); anc = (anc[0], anc[1] * sy)
        if img.info.get("detail", 1.0) != 1.0:     # finer-grid parts (hands) are drawn at 1 / detail, as in the game
            dt = img.info["detail"]
            img = img.resize((max(1, round(img.width / dt)), max(1, round(img.height / dt))), Image.BOX); anc = (anc[0] / dt, anc[1] / dt)
        px = ox + x * math.cos(th) / mpt - anc[0]
        py = oy - y * ce / mpt - anc[1]
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))
    return canvas

def sheet(ids, meta, team, views=(0, 2, 4, 6, 8, 12)):
    figs = []
    for pid in ids:
        grid = meta["profiles"][pid]["grid"]
        atlas = _display(Image.open(os.path.join(OUT, "%s_%s.png" % (pid, team))).convert("RGBA"), float(meta.get("gain", 1.0)))
        figs.append([_figure(atlas, k, grid) for k in views])
    fw, fh = figs[0][0].size
    out = Image.new("RGBA", (fw * len(views), fh * len(figs)), (30, 93, 167, 255))
    for r, row in enumerate(figs):
        for c, fig in enumerate(row): out.alpha_composite(fig, (c * fw, r * fh))
    out.convert("RGB").resize((out.width * 2, out.height * 2), Image.NEAREST).save(os.path.join(ROOT, "logs/sprite_profiles_%s.png" % team))

def detail_sheet(pid, meta, team="blue", scale=6):
    """Close-ups for review: the three hand rows, and head / torso / shorts / shoe at the three
    view heights, eight views each -> logs/sprite_detail_<id>_<team>.png (on-screen colours)."""
    grid = meta["profiles"][pid]["grid"]
    atlas = _display(Image.open(os.path.join(OUT, "%s_%s.png" % (pid, team))).convert("RGBA"), float(meta.get("gain", 1.0)))
    names = ["hand", "hand_a50", "hand_b50", "hand_grip", "hand_grip_a50", "hand_cup", "hand_cup_a50", "hand_cup_b50"]
    for limb_name in ("upper_arm", "forearm", "thigh"):
        names += [limb_name + "_b70", limb_name + "_b42", limb_name, limb_name + "_a42", limb_name + "_a70"]
    for part in VIEW_PARTS: names += [part + "_low", part, part + "_top"]
    views = (0, 2, 4, 6, 8, 10, 12, 14)
    out = Image.new("RGBA", (CELL * len(views), CELL * len(names)), (30, 93, 167, 255))
    for r, name in enumerate(names):
        row = grid["parts"][name]["row"]
        for c, k in enumerate(views):
            out.alpha_composite(atlas.crop((k * CELL, row * CELL, (k + 1) * CELL, (row + 1) * CELL)), (c * CELL, r * CELL))
    path = os.path.join(ROOT, "logs/sprite_detail_%s_%s.png" % (pid, team))
    out.convert("RGB").resize((out.width * scale, out.height * scale), Image.NEAREST).save(path)
    return path

if __name__ == "__main__":
    np.seterr(all="ignore")  # numpy 2 + Accelerate raises spurious matmul warnings
    with open(META) as f: meta = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ids = args or sorted(f[:-5] for f in os.listdir(PROFILES) if f.endswith(".json") and not f.startswith("_"))
    profiles = meta.setdefault("profiles", {})
    for pid in ids:
        profiles[pid] = bake(pid, meta)
        profiles[pid]["far"] = bake_far(pid, meta)
        print("baked", pid)
    with open(META, "w") as f: json.dump(meta, f, indent=1); f.write("\n")
    if "--sheet" in sys.argv:
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        all_ids = sorted(profiles)
        for team in TEAMS: sheet(all_ids, meta, team)
        print("preview: logs/sprite_profiles_blue.png, logs/sprite_profiles_red.png")
    if "--detail" in sys.argv:
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        for pid in ids: print("detail:", detail_sheet(pid, meta))
