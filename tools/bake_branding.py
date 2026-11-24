#!/usr/bin/env python3
"""Bake Pixel Pickleball branding (visual only).

  assets/branding/app-icon.png         1024 px app icon: a pixelated neon yellow-green pickleball
                                       (a real sphere with 40 drilled holes, ray-cast on a
                                       64 px grid, three tones, no glow) on court blue
  assets/branding/title-logo.png       main-menu title art (bunting, ribbon, chunky letters)
  assets/branding/pixel-pickleball.png   court floor wordmark (alpha mask, 3:1) in the
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
    bg = hexc("#2f73b5")                # pickleball-court blue (no black)
    tones = [hexc("#a0bf1d"), hexc("#d2ee2c"), hexc("#e8fa66")]   # standard neon yellow-green
    rim = hexc("#f6ffc4")
    hole_dark = hexc("#46600a")
    hole_lip = hexc("#b3d324")
    outline = hexc("#1c3d5e")
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
    top = text_mask(chars, "PIXEL", 2)
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
    Image.fromarray(rgba).resize((W * s, H * s), Image.NEAREST).save(os.path.join(OUT, "pixel-pickleball.png"))


def bake_title_logo(scale=8):
    """Main-menu title art: a string of banderitas, PIXEL in cream on a red ribbon
    (the colour of the court curb) with a tiny ball, and PICKLEBALL in big chunky
    yellow-green letters with a pixel highlight, a blocky 3D extrusion and a dark
    outline. Flat colours only (no glow). Transparent background."""
    chars = load_font()
    big = text_mask(chars, "PICKLEBALL", 1).repeat(2, 0).repeat(2, 1)
    small = text_mask(chars, "PIXEL", 2)
    bw = big.shape[1]
    H = 6 + small.shape[0] + 6 + 3 + big.shape[0] + 4
    W = bw + 6
    img = np.zeros((H, W, 4))
    def put(y, x, rgb, a=255):
        if 0 <= y < H and 0 <= x < W: img[y, x] = list(rgb) + [a]
    # bunting: a sagging line with alternating flags
    flags = ["#e0473b", "#f2c84b", "#3e7fd0", "#f2f0ea", "#7cc490", "#f29ac0"]
    for x in range(W):
        y = 1 + int(round(1.5 * math.sin(math.pi * x / max(W - 1, 1))))
        put(y, x, hexc("#e9e2cf"))
        if x % 6 == 1:
            c = hexc(flags[(x // 6) % len(flags)])
            for dy in range(3):
                for dx in range(-(2 - dy), 3 - dy):
                    put(y + 1 + dy, x + 1 + dx, c)
    # red ribbon with notched ends and PIXEL in cream
    ry = 6
    rh = small.shape[0] + 4
    rw = small.shape[1] + 8
    red, red_dk, cream = hexc("#c0473b"), hexc("#8f3029"), hexc("#f3ead2")
    for y in range(rh):
        for x in range(rw + 4):
            notch = (x < 2 or x >= rw + 2) and abs(y - rh // 2) <= (rh // 2 - 1) - min(x, rw + 3 - x)
            if notch: continue
            put(ry + y, x, red_dk if y >= rh - 1 else red)
    for y in range(small.shape[0]):
        for x in range(small.shape[1]):
            if small[y, x]: put(ry + 2 + y, 6 + x, cream)
    # a tiny pickleball at the ribbon's end
    bx, byc = rw + 9, ry + rh // 2
    ball = [hexc("#a0bf1d"), hexc("#d2ee2c"), hexc("#e8fa66")]
    for y in range(-3, 4):
        for x in range(-3, 4):
            if x * x + y * y <= 10:
                t = 2 if (x + y) < -2 else (1 if (x + y) < 2 else 0)
                put(byc + y, bx + x, ball[t])
    for (hx, hy) in ((-1, -1), (1, 0), (-1, 2), (2, -2)):
        put(byc + hy, bx + hx, hexc("#46600a"))
    # PICKLEBALL: extrusion, outline, fill with a highlight row
    top = ry + rh + 3
    left = 2
    fill, fill_hi, fill_lo = hexc("#d2ee2c"), hexc("#effc8c"), hexc("#b3d324")
    side, outline = hexc("#6f8a12"), hexc("#1c2b3a")
    m = big
    mh, mw = m.shape
    def inside(y, x): return 0 <= y < mh and 0 <= x < mw and m[y, x]
    ext = np.zeros((mh + 2, mw + 2), bool)
    for d in (1, 2):
        ext[d:d + mh, d:d + mw] |= m
    for y in range(mh + 2):
        for x in range(mw + 2):
            if ext[y, x] and not inside(y, x): put(top + y, left + x, side)
    solid = ext.copy()
    solid[:mh, :mw] |= m
    for y in range(-1, mh + 3):
        for x in range(-1, mw + 3):
            if 0 <= y < mh + 2 and 0 <= x < mw + 2 and solid[y, x]: continue
            if any(0 <= y + dy < mh + 2 and 0 <= x + dx < mw + 2 and solid[y + dy, x + dx] for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0))):
                put(top + y, left + x, outline)
    for y in range(mh):
        for x in range(mw):
            if not m[y, x]: continue
            c = fill_hi if not inside(y - 1, x) else (fill_lo if not inside(y + 1, x) else fill)
            put(top + y, left + x, c)
    out = Image.fromarray(img.astype(np.uint8)).resize((W * scale, H * scale), Image.NEAREST)
    out.save(os.path.join(OUT, "title-logo.png"))
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon = bake_icon()
    bake_wordmark()
    logo = bake_title_logo()
    if "--preview" in sys.argv:
        os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
        icon.resize((256, 256), Image.NEAREST).save(os.path.join(ROOT, "logs/app_icon_preview.png"))
        bg = Image.new("RGBA", logo.size, (40, 60, 80, 255)); bg.alpha_composite(logo); bg.save(os.path.join(ROOT, "logs/title_logo_preview.png"))
    print("baked app-icon.png, title-logo.png and pixel-pickleball.png")
