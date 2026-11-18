#!/usr/bin/env python3
"""Bake 2.5D pixel-card atlases for player profiles (visual only).

Each profile (data/sprite_profiles/<id>.json) describes a body and outfit with a few
parameters. This builds every card part (head, torso, shorts, upper_arm, forearm, hand,
thigh, shin, shoe) from simple solids at real size, renders 16 views per part
(22.5 deg steps, 44 deg elevation for head/torso/shorts/shoe, side view for limbs),
quantises to 3 shading tones, pre-compensates colours for the game's Filmic tonemap
and writes one atlas per team:

  assets/pixel_cards/profiles/<id>_blue.png, <id>_red.png
  assets/pixel_cards/cards_meta.json  ("profiles" entry; grid/anchors unchanged)

Usage: python3 tools/bake_pixel_cards.py [id ...]      (no ids = every profile)
       python3 tools/bake_pixel_cards.py --sheet        (also writes a preview sheet)
"""
import json, math, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = os.path.join(ROOT, "assets/pixel_cards/cards_meta.json")
PROFILES = os.path.join(ROOT, "data/sprite_profiles")
OUT = os.path.join(ROOT, "assets/pixel_cards/profiles")

CELL, COLS = 40, 16
SS = 4                  # supersampling per texel
STEP = 0.0045           # solid sampling step (m)
ELEV = math.radians(44)
LIGHT = np.array([-0.45, 0.75, 0.55]); LIGHT /= np.linalg.norm(LIGHT)
OUTLINE = 0.62          # silhouette texels: colour x this

# Team colours as they should look on screen (main, light, dark), read back from the
# original atlases through the tonemap below.
TEAMS = {
    "blue": {"T": (83, 152, 236), "T_light": (168, 208, 236), "T_dark": (35, 85, 182)},
    "red":  {"T": (236, 73, 63),  "T_light": (236, 161, 147), "T_dark": (160, 35, 50)},
}

# ---------------------------------------------------------------- tonemap compensation
# Card shader: ALBEDO = texel(linear) * gain, unshaded; then exposure 1.05, Filmic
# (white 6.0, Godot 4 curve), sRGB out. Invert that per channel so the atlas shows
# the painted colour on screen.
def _filmic(x):
    A, B, C, D, E, F = 0.22 * 4, 0.30 * 2, 0.10, 0.20, 0.01, 0.30
    f = lambda v: (v * (A * v + C * B) + D * E) / (v * (A * v + B) + D * F) - E / F
    return f(x) / f(6.0)

def _s2l(s): return np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)
def _l2s(l): return np.where(l <= 0.0031308, l * 12.92, 1.055 * np.clip(l, 0, None) ** (1 / 2.4) - 0.055)

def make_compensator(gain):
    atlas = np.arange(256) / 255.0
    shown = _l2s(np.clip(_filmic(_s2l(atlas) * gain * 1.05), 0, 1)) * 255.0
    limit = 240  # the original atlases stop at 240: keeps highlights from clipping flat
    return lambda display: np.interp(np.minimum(display, shown[limit]), shown[:limit + 1], np.arange(limit + 1))

# ---------------------------------------------------------------- solids
# A solid is (inside(p) -> bool mask, normal(p) -> n, colour(p) -> list of keys).
# Coordinates: x lateral, y up, z forward (toward the camera in view 0); metres from
# the card's joint.

def _grid(lo, hi):
    axes = [np.arange(a, b + STEP, STEP) for a, b in zip(lo, hi)]
    g = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)
    return g

class Solid:
    def __init__(self, kind, centre, radii, paint, y0=None, y1=None, keep=None, taper=1.0, priority=0):
        self.kind, self.c, self.r = kind, np.array(centre, float), np.array(radii, float)
        self.paint, self.y0, self.y1, self.keep, self.taper, self.priority = paint, y0, y1, keep, taper, priority

    def points(self):
        if not hasattr(self, "_pts"): self._pts = self._points()
        return self._pts

    def _points(self):
        c, r = self.c, self.r
        if self.kind == "ell":
            p = _grid(c - r, c + r)
            q = (p - c) / r
            m = (q ** 2).sum(1) <= 1.0
            p = p[m]; n = (p - c) / r ** 2
        elif self.kind == "cyl":   # elliptical cylinder along y, radius tapers y1 -> y0
            rr = r * max(1.0, self.taper)
            p = _grid([c[0] - rr[0], self.y0, c[2] - rr[2]], [c[0] + rr[0], self.y1, c[2] + rr[2]])
            t = (p[:, 1] - self.y0) / max(self.y1 - self.y0, 1e-6)      # 0 bottom, 1 top
            scale = self.taper + (1.0 - self.taper) * t
            q = (p[:, [0, 2]] - c[[0, 2]]) / (r[[0, 2]] * scale[:, None])
            m = (q ** 2).sum(1) <= 1.0
            p = p[m]; d = (p - c) / (np.array([r[0], 1.0, r[2]]) * scale[m, None]) ** 2; d[:, 1] = 0.0; n = d
        else:                       # box
            p = _grid(c - r, c + r)
            n = (p - c) / r
            n = np.where(np.abs(n) == np.abs(n).max(1, keepdims=True), np.sign(n), 0.0)
        if self.keep is not None and len(p):
            m = self.keep(p); p, n = p[m], n[m]
        n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        return p, n

def ell(c, r, paint, **kw): return Solid("ell", c, r, paint, **kw)
def box(c, r, paint, **kw): return Solid("box", c, r, paint, **kw)
def cyl(c, r, y0, y1, paint, **kw): return Solid("cyl", c, [r[0], 0, r[1]], paint, y0=y0, y1=y1, **kw)

# ---------------------------------------------------------------- colours
def hex_rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def tones(key, team):
    """(light, main, dark) display colours for a colour key: hex, 'T', 'T_dark', 'T_light'."""
    if key.startswith("T"):
        pal = TEAMS[team]
        main = pal.get(key, pal["T"])
        if key == "T": return pal["T_light"], pal["T"], pal["T_dark"]
        c = np.array(main, float)
        return tuple(np.minimum(c * 1.15 + 8, 255)), main, tuple(c * 0.68)
    c = np.array(hex_rgb(key), float)
    return tuple(np.minimum(c * 1.1 + 6, 255)), tuple(c), tuple(c * 0.7)

def const(key): return lambda p: np.full(len(p), key, dtype=object)

def bands(axis, edges, keys):
    """Colour by coordinate bands: keys[i] where edges[i-1] <= p[axis] < edges[i]."""
    def f(p):
        idx = np.searchsorted(np.array(edges), p[:, axis], side="right")
        return np.array(keys, dtype=object)[idx]
    return f

# ---------------------------------------------------------------- body parts
def v(d, k, default): return d.get(k, default)

def head_part(pr):
    h = pr["head"]; skin = pr["skin"]; hair = h.get("hair_color", "#2a1c14")
    s = []
    s.append(ell([0, 0, 0], [0.082, 0.1, 0.09], const(skin)))
    # eyes and nose: a pixel each at this scale
    for x in (-0.03, 0.03):
        s.append(box([x, 0.01, 0.084], [0.009, 0.008, 0.008], const(h.get("eye", "#14161e")), priority=2))
    if h.get("sunglasses"):
        s.append(box([0, 0.012, 0.083], [0.07, 0.014, 0.012], const("#101114"), priority=3))
    style = h.get("hair", "crew")
    cap = {"buzz": 0.005, "crew": 0.01, "bob": 0.014, "ponytail": 0.012, "bun": 0.012, "curly": 0.024}.get(style, 0.01)
    line = {"buzz": 0.065, "crew": 0.065, "curly": 0.06}.get(style, 0.055)
    def hair_keep(p, line=line, style=style):
        front = p[:, 2] > 0.02
        low = p[:, 1] < (-0.075 if style == "bob" else (0.0 if style in ("buzz", "crew", "curly") else -0.03))
        return ~(front & (p[:, 1] < line)) & ~low
    s.append(ell([0, 0.006, -0.004], [0.082 + cap, 0.1 + cap, 0.09 + cap], const(hair), keep=hair_keep, priority=1))
    if style == "ponytail":
        s.append(ell([0, 0.07, -0.11], [0.035, 0.035, 0.04], const(hair), priority=1))
        s.append(ell([0, -0.03, -0.14], [0.03, 0.09, 0.032], const(hair), priority=1))
    if style == "bun":
        s.append(ell([0, 0.12, -0.03], [0.05, 0.045, 0.05], const(hair), priority=1))
    if h.get("beard"):
        s.append(ell([0, -0.05, 0.012], [0.079, 0.055, 0.084], const(h.get("beard_color", hair)),
                     keep=lambda p: (p[:, 1] < -0.04) & (p[:, 2] > 0.0), priority=1))
    wear = h.get("headwear")
    col = h.get("headwear_color", "T")
    if wear == "visor":
        s.append(cyl([0, 0, -0.004], [0.098, 0.106], 0.03, 0.06, const(col), priority=2,
                     keep=lambda p: p[:, 2] > -0.08))
        s.append(box([0, 0.035, 0.1], [0.07, 0.006, 0.025], const(col), priority=2))
    elif wear == "headband":
        s.append(cyl([0, 0, -0.004], [0.099, 0.108], 0.035, 0.035 + v(h, "headband_width", 0.022), const(col), priority=2))
    elif wear == "bucket_hat":
        s.append(cyl([0, 0, -0.01], [0.092, 0.1], 0.06, 0.125, const(col), priority=2, taper=1.06))
        s.append(cyl([0, 0, -0.01], [0.122, 0.128], 0.055, 0.066, const(col), priority=2))
    return s

def torso_part(pr):
    t = pr["torso"]; top = pr["top"]; skin = pr["skin"]
    sh, waist, chest, belly = v(t, "shoulders", 1.0), v(t, "waist", 1.0), v(t, "chest", 0.0), v(t, "belly", 0.0)
    female = pr.get("sex") == "female"
    body = top.get("color", "T")
    kind = top.get("type", "tee")

    def paint_top(p):
        k = np.full(len(p), body, dtype=object)
        ax = np.abs(p[:, 0])
        if "sides" in top: k[ax > 0.105 * waist + 0.02] = top["sides"]
        if "stripe" in top: k[(p[:, 1] > 0.0) & (p[:, 1] < 0.03) & (p[:, 2] > 0)] = top["stripe"]
        if "shoulders" in top: k[p[:, 1] > 0.085] = top["shoulders"]
        if "hem" in top: k[p[:, 1] < -0.22] = top["hem"]
        if "collar" in top: k[(p[:, 1] > 0.12) & (ax < 0.08)] = top["collar"]
        return k

    s = []
    s.append(cyl([0, 0, -0.004], [0.045, 0.045], 0.12, 0.2, const(skin)))                  # neck
    s.append(cyl([0, 0, 0], [0.145 * sh, 0.1], -0.04, 0.13, paint_top, taper=0.95))          # chest
    s.append(cyl([0, 0, 0], [0.13 * waist, 0.09 + belly * 0.03], -0.25, -0.03, paint_top))  # abdomen
    if belly > 0:
        s.append(ell([0, -0.14, 0.035], [0.12 * waist, 0.1, 0.06 + 0.05 * belly], paint_top))
    if female and chest > 0:
        for x in (-0.055, 0.055):
            s.append(ell([x * sh, 0.03, 0.06], [0.06, 0.055, 0.035 + 0.045 * chest], paint_top))
    elif chest > 0:
        s.append(ell([0, 0.05, 0.05], [0.15 * sh, 0.075, 0.035 + 0.045 * chest], paint_top))
    # Shoulder caps: sleeves for tee/polo/compression, bare for tanks.
    cap = top.get("sleeve", body) if kind in ("tee", "polo", "compression") else skin
    r = [0.06 * sh, 0.055, 0.07] if cap != skin else [0.045 * sh, 0.04, 0.05]
    for x in (-1, 1):
        s.append(ell([x * 0.15 * sh, 0.085, 0], r, const(cap)))
    return s

def bottom_part(pr):
    b = pr["bottom"]; kind = b.get("type", "shorts"); col = b.get("color", "T")
    w = v(pr["torso"], "hips", 1.0)
    s = []
    if kind.startswith("skirt"):
        length, flare = v(b, "length", 0.17), v(b, "flare", 0.05)
        y0, y1 = 0.07 - length, 0.075
        taper = (0.15 * w) / (0.15 * w + flare)
        def paint(p, col=col, kind=kind):
            k = np.full(len(p), col, dtype=object)
            if kind == "skirt_pleated":
                ang = np.arctan2(p[:, 0], p[:, 2])
                k[(np.floor(ang / 0.33) % 2 == 0) & (p[:, 1] < 0.02)] = b.get("pleat", "T_dark")
            if "hem" in b: k[p[:, 1] < y0 + 0.022] = b["hem"]
            if kind == "skirt_ruffle":
                tier = np.floor((y1 - p[:, 1]) / (length / 3)).astype(int)
                k[tier % 2 == 1] = b.get("tier", "#f1efe8")
            if "panel" in b: k[np.abs(p[:, 0]) > 0.13] = b["panel"]
            return k
        s.append(cyl([0, 0, 0], [0.15 * w + flare, 0.1 + flare * 0.8], y0, y1, paint, taper=taper))
    else:
        def paint(p, col=col):
            k = np.full(len(p), col, dtype=object)
            if "stripe" in b: k[np.abs(p[:, 0]) > 0.14 * w] = b["stripe"]
            if "hem" in b: k[p[:, 1] < -0.075] = b["hem"]
            return k
        s.append(cyl([0, 0, 0], [0.155 * w, 0.105], -0.095, 0.075, paint))
    if "waistband" in b:
        s.append(cyl([0, 0, 0], [0.152 * w, 0.103], 0.06, 0.08, const(b["waistband"]), priority=1))
    return s

def limb(length, r_top, r_bot, base, covers):
    """Vertical limb from y=0 down to -length. covers: list of (from_frac, to_frac, key, extra_r)."""
    s = [cyl([0, 0, 0], [r_top, r_top * 0.9], -length, 0, const(base), taper=r_bot / r_top)]
    for a, b_, key, extra in covers:
        y1, y0 = -a * length, -b_ * length
        t = (y1 + y0) * 0.5 / -length
        r = r_top + (r_bot - r_top) * t + extra
        s.append(cyl([0, 0, 0], [r, r * 0.9], y0, y1, const(key), priority=1))
    return s

def upper_arm_part(pr, L):
    a = pr["arms"]; g = v(a, "upper", 1.0); top = pr["top"]
    covers = []
    if top.get("type") in ("tee", "polo", "compression"):
        covers.append((0.0, v(top, "sleeve_length", 0.4), top.get("sleeve", top.get("color", "T")), 0.008))
        if "cuff" in top: covers.append((v(top, "sleeve_length", 0.4) - 0.08, v(top, "sleeve_length", 0.4), top["cuff"], 0.01))
    if a.get("tattoo"): covers.append((0.5, 0.6, a["tattoo"], 0.002))
    s = limb(L, 0.042 * g, 0.034 * g, pr["skin"], covers)
    s.append(ell([0, -0.42 * L, 0.008], [0.046 * g, 0.075, 0.05 * g], const(pr["skin"])))   # biceps
    sleeved = top.get("type") in ("tee", "polo", "compression")
    s.append(ell([0, 0, 0], [0.048 * g, 0.045, 0.048 * g], const(covers[0][2] if sleeved else pr["skin"])))
    return s

def forearm_part(pr, L):
    a = pr["arms"]; g = v(a, "fore", 1.0); acc = a.get("forearm", {})
    covers = []
    kind, col = acc.get("type"), acc.get("color", "#1a1a1a")
    if kind == "wristband": covers.append((0.78, 0.98, col, 0.012))
    if kind == "watch": covers.append((0.82, 0.94, col, 0.01))
    if kind == "elbow_sleeve": covers.append((0.0, 0.42, col, 0.006))
    if kind == "compression_sleeve": covers.append((0.0, 0.95, col, 0.004))
    s = limb(L, 0.038 * g, 0.029 * g, a.get("forearm_skin", pr["skin"]), covers)
    s.append(ell([0, -0.25 * L, 0.004], [0.04 * g, 0.07, 0.04 * g], const(covers[0][2] if covers and covers[0][0] == 0.0 else a.get("forearm_skin", pr["skin"]))))
    return s

def hand_part(pr):
    a = pr["arms"]; size = v(a, "hand", 1.0); col = a.get("glove", pr["skin"])
    s = [ell([0, -0.035 * size, 0], [0.034 * size, 0.05 * size, 0.022 * size], const(col))]
    if a.get("tape"):
        s.append(box([0, -0.065 * size, 0], [0.036 * size, 0.008, 0.024 * size], const(a["tape"]), priority=1))
    return s

def thigh_part(pr, L):
    lg = pr["legs"]; g = v(lg, "thigh", 1.0); b = pr["bottom"]
    covers = []
    cov, key = v(b, "thigh_cover", 0.25), b.get("color", "T")
    if b.get("type", "").startswith("skirt"):
        under = b.get("under")
        if under: covers.append((0.0, v(b, "under_length", 0.22), under, 0.004))
        covers.append((0.0, cov, key, 0.012 + v(b, "flare", 0.05) * 0.2))
    elif cov > 0:
        covers.append((0.0, min(cov, 1.0), key, 0.01))
        if "stripe" in b: covers.append((0.0, min(cov, 1.0), b["stripe"], 0.012))   # outer stripe drawn via keep below
    if lg.get("brace") and lg["brace"].get("part") == "thigh":
        covers.append((0.85, 1.0, lg["brace"]["color"], 0.012))
    s = limb(L, 0.062 * g, 0.045 * g, pr["skin"], [c for c in covers if c[2] != b.get("stripe")])
    if "stripe" in b and cov > 0 and not b.get("type", "").startswith("skirt"):
        r = 0.062 * g + 0.013
        s.append(cyl([0, 0, 0], [r, r * 0.9], -min(cov, 1.0) * L, 0, const(b["stripe"]), priority=2,
                     keep=lambda p: np.abs(p[:, 0]) > r * 0.75))
    return s

def shin_part(pr, L):
    lg = pr["legs"]; g = v(lg, "shin", 1.0); sock = lg.get("socks", {})
    covers = []
    b = pr["bottom"]
    over = v(b, "thigh_cover", 0.25) - 1.0
    if over > 0: covers.append((0.0, over * 1.0, b.get("color", "T"), 0.02))
    sh = v(sock, "height", 0.12)
    if sh > 0: covers.append((1.0 - sh, 1.0, sock.get("color", "#f1efe8"), 0.006))
    for st in sock.get("stripes", []):   # [from_frac, to_frac, key]
        covers.append((st[0], st[1], st[2], 0.008))
    if lg.get("calf_sleeve"): covers.append((0.25, 0.7, lg["calf_sleeve"], 0.006))
    if lg.get("brace") and lg["brace"].get("part") == "shin": covers.append((0.0, 0.22, lg["brace"]["color"], 0.012))
    if lg.get("ankle_tape"): covers.append((0.84, 0.98, lg["ankle_tape"], 0.01))
    s = limb(L, 0.045 * g, 0.03 * g, pr["skin"], covers)
    s.append(ell([0, -0.3 * L, -0.012], [0.045 * g, 0.08, 0.045 * g], const(pr["skin"])))   # calf
    return s

def shoe_part(pr):
    sh = pr["shoes"]; col, sole = sh.get("color", "#f1efe8"), sh.get("sole", "#d3d1c7")
    w = v(sh, "width", 1.0)
    s = [box([0, -0.085, 0.045], [0.045 * w, 0.012, 0.13], const(sole)),
         ell([0, -0.05, 0.04], [0.045 * w, 0.04, 0.125], const(col), keep=lambda p: p[:, 1] > -0.075)]
    collar = 0.02 if sh.get("high") else -0.02
    s.append(cyl([0, 0, -0.03], [0.042 * w, 0.05], -0.07, collar, const(col)))
    if "accent" in sh:
        s.append(box([0, -0.058, 0.02], [0.047 * w, 0.01, 0.06], const(sh["accent"]), priority=1,
                     keep=lambda p: np.abs(p[:, 0]) > 0.04 * w))
    if "heel" in sh:
        s.append(box([0, -0.05, -0.075], [0.044 * w, 0.03, 0.012], const(sh["heel"]), priority=1))
    return s

# ---------------------------------------------------------------- rendering
def render(solids, team, view, comp, anchor, elevated):
    """One 40x40 RGBA cell: solids seen from view (0..15), joint at anchor texel."""
    mpt = META_DATA["meters_per_texel"]
    th = math.radians(view * 22.5)
    ry = np.array([[math.cos(th), 0, math.sin(th)], [0, 1, 0], [-math.sin(th), 0, math.cos(th)]])
    e = ELEV if elevated else 0.0
    rx = np.array([[1, 0, 0], [0, math.cos(e), -math.sin(e)], [0, math.sin(e), math.cos(e)]])
    rot = rx @ ry
    n_sub = CELL * SS
    depth = np.full((n_sub, n_sub), -np.inf); prio = np.full((n_sub, n_sub), -1)
    col = np.zeros((n_sub, n_sub, 3))
    for sd in solids:
        p, n = sd.points()
        if not len(p): continue
        keys = sd.paint(p)
        pc, nc = p @ rot.T, n @ rot.T
        u = np.floor((anchor[0] + pc[:, 0] / mpt) * SS).astype(int)
        w = np.floor((anchor[1] - pc[:, 1] / mpt) * SS).astype(int)
        ok = (u >= 0) & (u < n_sub) & (w >= 0) & (w < n_sub)
        u, w, z, nc, keys = u[ok], w[ok], pc[ok, 2], nc[ok], keys[ok]
        lit = nc @ LIGHT
        shade = np.where(lit > 0.72, 0, np.where(lit > -0.1, 1, 2))
        # Front-most point wins; an accessory (higher priority) wins ties within 6 mm.
        score = z + sd.priority * 0.006
        order = np.argsort(score)
        u, w, score, shade, keys = u[order], w[order], score[order], shade[order], keys[order]
        uk, inv = np.unique(keys.astype(str), return_inverse=True)
        table = np.array([[tones(k, team)[i] for i in range(3)] for k in uk], float)
        rgb = table[inv.reshape(-1), shade]
        better = score > depth[w, u]
        u, w, score, rgb = u[better], w[better], score[better], rgb[better]
        depth[w, u] = score
        col[w, u] = rgb
    # Downsample: a texel is solid when >= 40% of its subsamples are; colour = most
    # common subsample colour (keeps flat pixel-art tones, no blending).
    cov = np.isfinite(depth).reshape(CELL, SS, CELL, SS).mean((1, 3))
    out = np.zeros((CELL, CELL, 4), np.uint8)
    blocks = col.reshape(CELL, SS, CELL, SS, 3).transpose(0, 2, 1, 3, 4).reshape(CELL, CELL, SS * SS, 3)
    fin = np.isfinite(depth).reshape(CELL, SS, CELL, SS).transpose(0, 2, 1, 3).reshape(CELL, CELL, SS * SS)
    solid = cov >= 0.4
    disp = np.zeros((CELL, CELL, 3))
    for y, x in zip(*np.nonzero(solid)):
        vals = blocks[y, x][fin[y, x]]
        uniq, cnt = np.unique(vals.round().astype(int), axis=0, return_counts=True)
        disp[y, x] = uniq[cnt.argmax()]
    # Selective outline (pixel-art "selout"): silhouette texels darken to their own
    # shadow tone, so players separate from the court and from each other. Tiny
    # sprites (hands) are left alone or they would turn all dark.
    if solid.sum() > 14:
        pad = np.pad(solid, 1)
        edge = solid & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        disp[edge] *= OUTLINE
    for y, x in zip(*np.nonzero(solid)):
        out[y, x, :3] = np.clip(np.round(comp(disp[y, x])), 0, 255)
        out[y, x, 3] = 255
    return out

def build_parts(pr):
    parts = META_DATA["parts"]
    L = lambda name: (parts[name]["end"][1] - parts[name]["anchor"][1]) * META_DATA["meters_per_texel"]
    return {
        "head": (head_part(pr), True), "torso": (torso_part(pr), True), "shorts": (bottom_part(pr), True),
        "upper_arm": (upper_arm_part(pr, L("upper_arm")), False), "forearm": (forearm_part(pr, L("forearm")), False),
        "hand": (hand_part(pr), False), "thigh": (thigh_part(pr, L("thigh")), False),
        "shin": (shin_part(pr, L("shin")), False), "shoe": (shoe_part(pr), True),
    }

def bake(pid):
    with open(os.path.join(PROFILES, pid + ".json")) as f: pr = json.load(f)
    comp = make_compensator(float(META_DATA.get("gain", 1.0)))
    parts = build_parts(pr)
    rows = int(META_DATA["rows"])
    paths = {}
    for team in TEAMS:
        atlas = np.zeros((rows * CELL, COLS * CELL, 4), np.uint8)
        for name, (solids, elevated) in parts.items():
            info = META_DATA["parts"][name]
            for k in range(COLS):
                atlas[info["row"] * CELL:(info["row"] + 1) * CELL, k * CELL:(k + 1) * CELL] = \
                    render(solids, team, k, comp, info["anchor"], elevated)
        rel = "profiles/%s_%s.png" % (pid, team)
        Image.fromarray(atlas).save(os.path.join(ROOT, "assets/pixel_cards", rel))
        paths[team] = "res://assets/pixel_cards/" + rel
    return {"name": pr.get("name", pid), "sex": pr.get("sex", ""), "paddle": pr.get("paddle", ""), "textures": paths}

# Standing joints (m, body frame: x lateral, y up) for the assembled preview.
_JOINTS = {"head": (0, 0.33), "torso": (0, 0.05), "shorts": (0, -0.37)}
_LIMBS = [("upper_arm", 0.18, 0.15, "forearm"), ("forearm", 0.19, -0.1, "hand"), ("hand", 0.19, -0.35, None),
          ("thigh", 0.11, -0.33, "shin"), ("shin", 0.11, -0.64, "shoe"), ("shoe", 0.11, -0.94, None)]

def _display(atlas):
    """Atlas texels -> on-screen colours (forward tonemap), for previews."""
    a = np.array(atlas).astype(float)
    shown = _l2s(np.clip(_filmic(_s2l(a[..., :3] / 255.0) * float(META_DATA.get("gain", 1.0)) * 1.05), 0, 1)) * 255
    a[..., :3] = shown
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")

def _figure(atlas, k):
    """One standing player at view k assembled from the cards, like pixel_card_rig.gd."""
    mpt, ce = META_DATA["meters_per_texel"], math.cos(ELEV)
    canvas = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    ox, oy = 32, 30
    th = math.radians(k * 22.5)
    items = []
    def cell(name, kk):
        r = META_DATA["parts"][name]["row"]
        return atlas.crop((kk * CELL, r * CELL, (kk + 1) * CELL, (r + 1) * CELL))
    for name, (x, y) in _JOINTS.items():
        items.append((0.001 if name == "head" else 0.0, cell(name, k), x, y, META_DATA["parts"][name]["anchor"], 1.0))
    for side in (-1, 1):   # -1 = player's right (unmirrored cards), +1 = left (mirrored)
        for name, x, y, _ in _LIMBS:
            info = META_DATA["parts"][name]
            img = cell(name, k if side < 0 else (COLS - k) % COLS)
            if side > 0: img = img.transpose(Image.FLIP_LEFT_RIGHT)
            sy = ce if "end" in info and name != "hand" else 1.0
            items.append((-side * x * math.sin(th) * -1.0, img, side * x * -1.0, y, info["anchor"], sy))
    for depth, img, x, y, anc, sy in sorted(items, key=lambda t: t[0]):
        if sy != 1.0: img = img.resize((CELL, max(1, round(CELL * sy))), Image.NEAREST); anc = (anc[0], anc[1] * sy)
        px = ox + x * math.cos(th) / mpt - anc[0]
        py = oy - y * ce / mpt - anc[1]
        canvas.alpha_composite(img, (int(round(px)), int(round(py))))
    return canvas

def sheet(ids, team="blue", views=(0, 2, 4, 6, 8, 12)):
    """Assembled players, one row per profile, views across, on-screen colours, 4x."""
    rows = []
    for pid in ids:
        atlas = _display(Image.open(os.path.join(OUT, "%s_%s.png" % (pid, team))).convert("RGBA"))
        rows.append([_figure(atlas, k) for k in views])
    w, h = 64 * len(views), 96 * len(rows)
    out = Image.new("RGBA", (w, h), (30, 93, 167, 255))
    for r, row in enumerate(rows):
        for c, fig in enumerate(row): out.alpha_composite(fig, (c * 64, r * 96))
    out.convert("RGB").resize((w * 4, h * 4), Image.NEAREST).save(os.path.join(ROOT, "logs/sprite_profiles_%s.png" % team))

if __name__ == "__main__":
    np.seterr(all="ignore")  # numpy 2 + Accelerate raises spurious matmul warnings
    with open(META) as f: META_DATA = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ids = args or sorted(f[:-5] for f in os.listdir(PROFILES) if f.endswith(".json") and not f.startswith("_"))
    profiles = META_DATA.setdefault("profiles", {})
    for pid in ids:
        profiles[pid] = bake(pid)
        print("baked", pid, "->", ", ".join(profiles[pid]["textures"].values()))
    with open(META, "w") as f: json.dump(META_DATA, f, indent=1); f.write("\n")
    if "--sheet" in sys.argv:
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        for team in TEAMS: sheet(ids, team)
        print("preview: logs/sprite_profiles_blue.png, logs/sprite_profiles_red.png")
