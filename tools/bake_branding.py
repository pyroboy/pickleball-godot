#!/usr/bin/env python3
"""Bake Barangay Pickleball branding (visual only).

  assets/branding/app-icon.png         1024 px app icon: a pixelated neon-green pickleball
                                       (a real sphere with 40 drilled holes, ray-cast on a
                                       64 px grid, three tones, no glow) on a dark ground
  assets/branding/barangay-pickleball.png   court floor wordmark (alpha mask, 3:1) in the
                                       game's own pixel font (assets/fonts/arjo_pixel.*)

Usage: python3 tools/bake_branding.py [--preview]
Run Godot with --import afterwards so the new PNGs load.
"""
import math, os, re, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/branding")


def hexc(code):
    code = code.lstrip("#")
    return np.array([int(code[i:i + 2], 16) for i in (0, 2, 4)], float)


# ------------------------------------------------------------------ the ball

def fib_sphere(n):
    pts = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        y = 1.0 - 2.0 * (i + 0.5) / n
        r = math.sqrt(1.0 - y * y)
        a = golden * i
        pts.append((math.cos(a) * r, y, math.sin(a) * r))
    return np.array(pts)


def rot(ax, ay):
    cx, sx, cy, sy = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    return ry @ rx


def bake_icon(grid=64, scale=16):
    holes = fib_sphere(40) @ rot(0.5, 0.35).T
    hole_r = 0.17                      # radians on the unit sphere
    light = np.array([-0.55, 0.65, 0.52]); light /= np.linalg.norm(light)
    bg = hexc("#06110a")
    tones = [hexc("#0f8f3c"), hexc("#2cf06b"), hexc("#a8ffb8")]
    rim = hexc("#e6ffd9")
    hole_dark = hexc("#063d1a")
    hole_lip = hexc("#11a646")
    outline = hexc("#021a0a")
    img = np.zeros((grid, grid, 3))
    img[:] = bg
    c = (grid - 1) / 2.0
    R = grid * 0.36
    mask = np.zeros((grid, grid), bool)
    for y in range(grid):
        for x in range(grid):
            px, py = (x - c) / R, (c - y) / R
            r2 = px * px + py * py
            if r2 > 1.0: continue
            mask[y, x] = True
            n = np.array([px, py, math.sqrt(1.0 - r2)])
            lam = max(0.0, float(n @ light))
            # nearest hole: inside -> dark, with a lit lip on the side away from the light
            dots = holes @ n
            j = int(np.argmax(dots))
            ang = math.acos(min(1.0, dots[j]))
            if ang < hole_r:
                to_c = holes[j] - n * dots[j]
                lip = float(to_c @ light) < -0.02 and ang > hole_r * 0.55
                col = hole_lip if lip else hole_dark
            else:
                t = 0 if lam < 0.3 else (1 if lam < 0.72 else 2)
                col = tones[t]
                if lam > 0.93: col = rim
            img[y, x] = col
    # one-texel outline
    for y in range(grid):
        for x in range(grid):
            if mask[y, x]: continue
            if any(0 <= y + dy < grid and 0 <= x + dx < grid and mask[y + dy, x + dx] for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0))):
                img[y, x] = outline
    # two sparkle pixels
    for sx, sy in ((-0.42, 0.5), (-0.3, 0.6)):
        img[int(c - sy * R), int(c + sx * R)] = rim
    out = Image.fromarray(img.clip(0, 255).astype(np.uint8)).resize((grid * scale, grid * scale), Image.NEAREST)
    out.save(os.path.join(OUT, "app-icon.png"))
    return out


# ------------------------------------------------------------------ the wordmark

def load_font():
    fnt = open(os.path.join(ROOT, "assets/fonts/arjo_pixel.fnt")).read()
    atlas = np.array(Image.open(os.path.join(ROOT, "assets/fonts/arjo_pixel.png")).convert("RGBA"))
    chars = {}
    for m in re.finditer(r"char id=(\d+) x=(\d+) y=(\d+) width=(\d+) height=(\d+) xoffset=(-?\d+) yoffset=(-?\d+) xadvance=(\d+)", fnt):
        i, x, y, w, h, xo, yo, adv = map(int, m.groups())
        chars[chr(i)] = (atlas[y:y + h, x:x + w, 3] > 127, xo, yo, adv)
    return chars


def text_mask(chars, text, spacing=1):
    width = sum(chars[ch][3] + spacing for ch in text)
    m = np.zeros((11, width), bool)
    pen = 0
    for ch in text:
        g, xo, yo, adv = chars[ch]
        h, w = g.shape
        m[yo:yo + h, pen + xo:pen + xo + w] |= g
        pen += adv + spacing
    cols = np.nonzero(m.any(0))[0]
    rows = np.nonzero(m.any(1))[0]
    return m[rows.min():rows.max() + 1, cols.min():cols.max() + 1]


def bake_wordmark():
    chars = load_font()
    top = text_mask(chars, "BARANGAY", 2)
    big = text_mask(chars, "PICKLEBALL", 1)
    big = big.repeat(2, 0).repeat(2, 1)
    w = max(top.shape[1], big.shape[1]) + 8
    h = top.shape[0] + big.shape[0] + 3 + 6
    # 3:1 canvas (the decal plane is 3 x 1 m)
    W = max(w, h * 3)
    H = W // 3
    m = np.zeros((H, W), bool)
    y0 = (H - (top.shape[0] + 3 + big.shape[0])) // 2
    m[y0:y0 + top.shape[0], (W - top.shape[1]) // 2:(W - top.shape[1]) // 2 + top.shape[1]] = top
    y1 = y0 + top.shape[0] + 3
    m[y1:y1 + big.shape[0], (W - big.shape[1]) // 2:(W - big.shape[1]) // 2 + big.shape[1]] = big
    s = 16
    rgba = np.zeros((H, W, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = m * 255
    Image.fromarray(rgba).resize((W * s, H * s), Image.NEAREST).save(os.path.join(OUT, "barangay-pickleball.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon = bake_icon()
    bake_wordmark()
    if "--preview" in sys.argv:
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        icon.resize((256, 256), Image.NEAREST).save(os.path.join(ROOT, "logs/app_icon_preview.png"))
    print("baked app-icon.png and barangay-pickleball.png")
