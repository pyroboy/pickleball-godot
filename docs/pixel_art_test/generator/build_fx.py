import sys; sys.path.insert(0, '.')
import numpy as np
from math import cos, sin, pi
from PIL import Image, ImageDraw
import pixui as U
from pixui import C, BAYER
from sprites import PAL
from sprites import hx as shx

CS = 32  # effect cell size (native px)

def blank(n=CS): return np.zeros((n, n, 4), np.uint8)
def dith(a, x, y): return BAYER[y % 4, x % 4] < a
def put(img, x, y, col, a=1.0):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < img.shape[1] and 0 <= y < img.shape[0] and dith(a, x, y):
        img[y, x, :3] = col; img[y, x, 3] = 255
def disc(img, cx, cy, r, col, a=1.0):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r: put(img, x, y, col, a)
def ringe(img, cx, cy, r, w, col, a=1.0, sq=1.0):
    for y in range(img.shape[0]):
        for x in range(img.shape[1]):
            d = ((x + .5 - cx) ** 2 + ((y + .5 - cy) / sq) ** 2) ** 0.5
            if r - w <= d <= r: put(img, x, y, col, a)
def line(img, x0, y0, x1, y1, col, a=1.0):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for k in range(n + 1):
        u = k / max(n, 1); put(img, x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, col, a)

def impact(f):
    im = blank(); c = CS / 2; t = f / 5
    core = [C['white'], C['white'], C['gold_l'], C['gold'], C['gold_d'], C['gold_d']][f]
    disc(im, c, c, [5, 4, 3, 2, 1, 0][f], core, 1 - t * 0.5)
    for k in range(8):
        a = k * pi / 4 + (pi / 8 if k % 2 else 0)
        r0 = 3 + t * 6; r1 = r0 + (9 - f) * (1.3 if k % 2 == 0 else 0.7)
        col = C['gold_l'] if f < 3 else C['gold']
        line(im, c + cos(a) * r0, c + sin(a) * r0, c + cos(a) * r1, c + sin(a) * r1, col, 1 - t * 0.8)
    return im
def spark_ring(f):
    im = blank(); c = CS / 2
    ringe(im, c, c, 3 + f * 3, 2 if f < 3 else 1, C['cyan'] if f > 1 else C['white'], 1 - f * 0.18)
    return im
def bounce(f):
    im = blank(); c = CS / 2
    ringe(im, c, c + 6, 3 + f * 2.4, 1, C['white'], 1 - f * 0.17, sq=0.45)
    for k, dx in enumerate((-7, 0, 7)):
        if f >= 1:
            y = c + 6 - f * 1.6 - (k == 1) * 2
            disc(im, c + dx * (0.6 + f * 0.12), y, max(0.8, 2.6 - f * 0.4), (200, 196, 230), 1 - f * 0.17)
    return im
def dust(f):
    im = blank(); c = CS / 2
    for side in (-1, 1):
        x = c + side * (3 + f * 2.2); y = c + 8 - f * 1.4
        disc(im, x, y, max(0.7, 3 - f * 0.5), (214, 208, 236), 1 - f * 0.2)
        disc(im, x + side * 2, y + 1, max(0.5, 2 - f * 0.4), (180, 172, 214), 1 - f * 0.22)
    return im
def swing(f):
    im = blank(); c = CS / 2
    a0 = 200 + f * 18; span = 110 - f * 14
    for i in range(48):
        u = i / 47; a = (a0 + span * u) * pi / 180
        w = (1 - abs(u - 0.6) * 1.6) * (3 - f * 0.5)
        for k in range(int(max(w, 0)) + 1):
            r = 11 - k
            col = C['white'] if k == 0 else C['cyan']
            put(im, c + cos(a) * r, c + sin(a) * r * 0.9, col, (1 - f * 0.2) * min(1, u * 3))
    return im
def speed(f):
    im = blank(); rng = np.random.default_rng(f + 4)
    for _ in range(7):
        y = rng.integers(4, CS - 4); x0 = rng.integers(0, 10); L = rng.integers(8, 18)
        line(im, x0 + f * 3, y, x0 + f * 3 + L, y, C['white'] if rng.random() < .5 else C['sub'], 0.85)
    return im
def marker(f):
    im = blank(); c = CS / 2
    ringe(im, c, c + 6, 9 + [0, 1, 2, 1][f], 1, C['gold'], 1, sq=0.5)
    for k in range(2):
        yy = c - 4 - k * 4 + [0, -1, -2, -1][f]
        line(im, c - 3, yy, c, yy + 3, C['gold']); line(im, c, yy + 3, c + 3, yy, C['gold'])
    return im
def smash(f):
    im = blank(); c = CS / 2
    for k in range(12):
        a = k * pi / 6
        r1 = 6 + f * 3 + (k % 2) * 3
        line(im, c + cos(a) * (2 + f * 2), c + sin(a) * (2 + f * 2), c + cos(a) * r1, c + sin(a) * r1, C['white'] if f < 2 else C['red_l'], 1 - f * 0.22)
    disc(im, c, c, max(0, 4 - f), C['white'])
    return im
def out_stamp(f):
    im = Image.new('RGBA', (CS, CS), (0, 0, 0, 0))
    sc = 2
    w = U.text_w('OUT', sc)
    U.text(im, int(CS / 2 - w / 2), int(CS / 2 - 3.5 * sc), 'OUT', C['red_l'] if f > 0 else C['white'], sc, C['red_dd'])
    a = np.array(im)
    if f == 3: a[..., 3] = np.where(dither_mask(a.shape[:2], 0.5), a[..., 3], 0)
    return a
def dither_mask(shape, a):
    H, W = shape; return np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W] < a
def trails(kind):
    im = blank(); c = CS / 2
    col, n, sp = {'dink': (C['green'], 6, 1.2), 'drive': (C['gold_l'], 12, 1.8), 'smash': (C['white'], 14, 2.0)}[kind]
    for k in range(n):
        put(im, 6 + k * sp, c + 6 - k * (0.6 if kind != 'smash' else 0.9), col, 1 - k / n * 0.1 if False else (k + 1) / n)
    disc(im, 6 + n * sp + 1, c + 6 - n * (0.6 if kind != 'smash' else 0.9), 1.6, C['ball'])
    if kind == 'smash':
        for k in range(4): put(im, 8 + k * 5, c + 9 + (k % 2) * 2, C['gold'], 0.8)
    return im

ROWS = [
    ('IMPACT BURST', 'paddle contact', [impact(f) for f in range(6)], '6 frames @ 30 fps'),
    ('SPARK RING', 'sweet spot', [spark_ring(f) for f in range(5)], '5 frames'),
    ('BOUNCE', 'ring + dust', [bounce(f) for f in range(6)], '6 frames'),
    ('FOOTWORK DUST', 'split step, stops', [dust(f) for f in range(5)], '5 frames'),
    ('SWING ARC', 'paddle path', [swing(f) for f in range(5)], '5 frames, additive'),
    ('SPEED LINES', 'dives, sprints', [speed(f) for f in range(3)], '3 frame loop'),
    ('LANDING MARKER', 'ring + chevrons', [marker(f) for f in range(4)], '4 frame pulse'),
    ('SMASH FLASH', 'hard hits only', [smash(f) for f in range(4)], '4 frames + hit-stop'),
    ('OUT STAMP', 'fault call', [out_stamp(f) for f in range(4)], '4 frames'),
    ('BALL TRAILS', 'dink / drive / smash', [trails(k) for k in ('dink', 'drive', 'smash')], 'per shot type'),
]

def fx_sheet(Z=6):
    LW = 230; cw = CS * Z + 14; rh = CS * Z + 14
    out = Image.new('RGB', (LW + 6 * cw + 260, len(ROWS) * rh + 20), C['n0'])
    d = ImageDraw.Draw(out)
    from PIL import ImageFont
    f1 = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 30)
    f2 = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 22)
    for i, (name, sub, frames, timing) in enumerate(ROWS):
        y = 10 + i * rh
        d.text((16, y + rh / 2 - 20), name.title(), fill=C['txt'], font=f1)
        d.text((16, y + rh / 2 + 16), sub, fill=C['sub'], font=f2)
        for k, fr in enumerate(frames):
            x = LW + k * cw
            d.rectangle([x, y, x + cw - 8, y + rh - 8], fill=(56, 84, 168) if name != 'SMASH FLASH' else (40, 46, 80))
            pil = Image.fromarray(fr, 'RGBA').resize((CS * Z, CS * Z), Image.NEAREST)
            out.paste(pil, (x + 3, y + 3), pil)
        d.text((LW + 6 * cw + 10, y + rh / 2 - 12), timing, fill=C['sub'], font=f2)
    out.save('art/fx_sheet.png'); return out

# ---------------- shader demos ----------------
def shader_demos():
    from scene import make_scene, W, H, CAM, apply_vignette
    from scene import paddle_pos
    BP = paddle_pos('Forehand drive', 200, (-0.2, 0, 4.6), 0.3)
    sc = make_scene([('Forehand drive', 200, 'blue', (-0.2, 0, 4.6))], vignette=False, ball=BP)
    base = sc['base']; pm = sc['pmask'] > 0
    cx, cy, _ = CAM.project((-0.3, 0.9, 4.6)); cx, cy = int(cx), int(cy)
    x0, y0 = cx - 50, cy - 62; x1, y1 = x0 + 100, y0 + 110
    crop = lambda a: a[y0:y1, x0:x1].copy()
    B = crop(base); M = crop(pm)
    out = {}
    out['Pixel viewport (base)'] = B
    # palette swap
    sw = B.copy()
    for src, dst in zip(PAL['blue'], ['#3fcf8e', '#2aa874', '#1f7e5e', '#1a5a4a']):
        m = np.all(sw == np.array(shx(src)), axis=2) & M
        sw[m] = shx(dst)
    out['Team palette swap'] = sw
    fl = B.copy(); fl[M] = (fl[M] * 0.25 + 255 * 0.75).astype(np.uint8)
    out['Hit flash (1 frame)'] = fl
    # dither ghost
    bg = crop(make_scene([], vignette=False)['base'])
    gh = bg.copy(); dm = dither_mask(M.shape, 0.5) & M
    gh[dm] = B[dm]
    out['Dither ghost / behind net'] = gh
    # rim light: lit side (light from upper-left) edge pixels one step brighter
    rim = B.copy()
    edge = M & ~np.roll(M, 1, 1) | M & ~np.roll(M, 1, 0)
    rim[edge] = np.clip(rim[edge].astype(int) + [60, 50, 40], 0, 255)
    out['Warm rim light'] = rim
    # dusk grade
    g = B.astype(float) / 255
    dusk = np.clip(np.stack([g[..., 0] * 1.08 + 0.06, g[..., 1] * 0.88 + 0.02, g[..., 2] * 0.92 + 0.08], -1), 0, 1)
    out['Dusk colour grade'] = (dusk * 255).astype(np.uint8)
    # slow-mo grade
    from post import focus_post
    sm, _ = focus_post(B, M, (-0.2, 4.6), ox=x0, oy=y0, z=4, dim=0.3, desat=0.6, blur=0.0, r0=0.0, r1=0.01)
    out['Slow-mo grade (smooth)'] = sm
    from post import dof_post
    fdist = float(np.linalg.norm(np.array([-0.2, 0.9, 4.6]) - CAM.eye))
    fd, _ = dof_post(B, crop(sc['depth']), M, fdist, z=4, in_focus=1.5, dim=0.6, desat=0.4)
    out['Lens depth of field'] = fd
    # kitchen glow
    kg = B.copy(); km = crop(sc['kitchen']) & ~M
    glow = np.tile(BAYER, (28, 25))[:110, :100] < 0.45
    kg[km & glow] = np.clip(kg[km & glow].astype(int) + [30, 60, 70], 0, 255)
    out['Kitchen glow'] = kg
    # ball readability halo
    br = B.copy()
    bx, by, _ = CAM.project(BP); bx, by = int(bx) - x0, int(by) - y0
    for a in np.linspace(0, 2 * pi, 40):
        xx_, yy_ = int(round(bx + 0.5 + cos(a) * 4)), int(round(by + 0.5 + sin(a) * 4))
        if 0 <= xx_ < 100 and 0 <= yy_ < 110 and not M[yy_, xx_]: br[yy_, xx_] = (255, 255, 255)
    out['Ball readability ring'] = br
    return out

def slowmo_strip():
    from scene import make_scene, W, H, CAM, paddle_pos
    from build_ui import arc_pts, trail, ball_px
    from post import dof_post
    inc = arc_pts((0.4, 1.0, -5.6), paddle_pos('Forehand drive', 200, (-0.6, 0, 5.4)), 1.4)
    sc = make_scene([('Forehand drive', 200, 'blue', (-0.6, 0, 5.4))], vignette=True)
    keep = sc['pmask'] == 1
    cx, cy, _ = CAM.project((-0.7, 0.9, 5.1)); cx, cy = int(cx), int(cy)
    box = (cx - 60, cy - 90, cx + 60, cy + 40)
    Z = 3
    frames = []
    modes = (('1X  NORMAL', 170, None), ('0.6X  ENTER', 200, dict(strength=0.45, dim=0.25, desat=0.15)),
             ('0.12X  DEEP', 224, dict(strength=1.0, dim=0.6, desat=0.4)), ('CONTACT + HIT-STOP', 239, dict(strength=1.0, dim=0.6, desat=0.4)))
    for label, i_b, prm in modes:
        if prm is None:
            full = np.asarray(Image.fromarray(sc['img']).resize((W * Z, H * Z), Image.NEAREST))
        else:
            full, _ = dof_post(sc['img'], sc['depth'], keep, 11.7, z=Z, in_focus=1.5, **prm)
        full = full.copy()
        if label.startswith('CONTACT'):
            km = np.asarray(Image.fromarray(keep.astype(np.uint8) * 255).resize((W * Z, H * Z), Image.NEAREST)) > 0
            full[km] = (full[km] * 0.3 + 255 * 0.7).astype(np.uint8)
        im = Image.fromarray(full).convert('RGBA')
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        trail(ov, inc, i_b, n=8 if prm is None else 18, col=(255, 255, 255))
        ball_px(ov, inc[min(i_b, 239)])
        if label.startswith('CONTACT'):
            fx = Image.fromarray(impact(0), 'RGBA'); x, y, _ = CAM.project(inc[239])
            ov.paste(fx, (int(x) - 16, int(y) - 16), fx)
        U.text(ov, box[0] + 4, box[1] + (11 if prm and prm['strength'] >= 1 else 3), label, C['txt'], 1, C['n0'])
        im.alpha_composite(ov.resize((W * Z, H * Z), Image.NEAREST))
        if prm and prm['strength'] >= 1:
            d = ImageDraw.Draw(im)
            d.rectangle([0, box[1] * Z, W * Z, box[1] * Z + 24], fill=(10, 9, 20, 255))
            d.rectangle([0, box[3] * Z - 24, W * Z, box[3] * Z], fill=(10, 9, 20, 255))
            # redraw label above the letterbox
            lab = Image.new('RGBA', (W, H), (0, 0, 0, 0)); U.text(lab, box[0] + 4, box[1] + 11, label, C['txt'], 1, C['n0'])
            im.alpha_composite(lab.resize((W * Z, H * Z), Image.NEAREST))
        frames.append(im.crop(tuple(v * Z for v in box)))
    return frames

if __name__ == '__main__':
    fx_sheet()
    demos = shader_demos()
    Z = 4
    from PIL import ImageFont
    f2 = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 24)
    names = list(demos)
    tw, th = 100 * Z, 110 * Z
    out = Image.new('RGB', (5 * (tw + 16) + 16, 2 * (th + 56) + 16), C['n0'])
    d = ImageDraw.Draw(out)
    for i, n in enumerate(names):
        x = 16 + (i % 5) * (tw + 16); y = 16 + (i // 5) * (th + 56)
        out.paste(Image.fromarray(demos[n]).resize((tw, th), Image.NEAREST) if demos[n].shape[1] != tw else Image.fromarray(demos[n]), (x, y))
        d.text((x, y + th + 10), n, fill=C['txt'], font=f2)
    out.save('art/shaders.png')
    fr = slowmo_strip()
    out = Image.new('RGB', (4 * (fr[0].width + 16) + 16, fr[0].height + 32), C['n0'])
    for i, f in enumerate(fr):
        out.paste(f.convert('RGB'), (16 + i * (f.width + 16), 16))
    out.save('art/slowmo.png')
    print('ok')
