import sys; sys.path.insert(0, '.')
import numpy as np
from math import cos, sin, pi
from PIL import Image, ImageDraw
from scene import make_scene, W, H, CAM, apply_vignette
import pixui as U
from pixui import C

def to_rgba(img):
    return Image.fromarray(np.dstack([img, np.full(img.shape[:2], 255, np.uint8)]), 'RGBA').copy()

# ---------------- trajectory helpers ----------------
def arc_pts(p0, p1, lift, n=240):
    p0, p1 = np.array(p0, float), np.array(p1, float)
    u = np.linspace(0, 1, n)[:, None]
    return p0 + (p1 - p0) * u + np.outer(4 * u[:, 0] * (1 - u[:, 0]) * lift, [0, 1, 0])

def draw_path(im, pts3, col, dash=(4, 3), w=1, ground=False, shadow_col=None, start=0.0):
    px = im.load()
    P = np.array([CAM.project(p)[:2] for p in pts3])
    seglen = np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]
    on, off = dash
    seen = set()
    for (x, y), L in zip(P, seglen):
        if L < start: continue
        if off and int(L) % (on + off) >= on: continue
        xi, yi = int(np.floor(x)), int(np.floor(y))
        for dx in range(w):
            if 0 <= xi + dx < W and 0 <= yi < H and (xi + dx, yi) not in seen:
                px[xi + dx, yi] = col + (255,); seen.add((xi + dx, yi))
    return P

def ground_ellipse(im, c, r, col, chevrons=False, fill=None):
    px = im.load()
    pts = [np.array(c) + [r * cos(a), 0, r * 0.62 * sin(a)] for a in np.linspace(0, 2 * pi, 160)]
    if fill is not None:
        d = ImageDraw.Draw(im)
        d.polygon([tuple(CAM.project(p)[:2]) for p in pts], fill=fill)
    for p in pts:
        x, y, _ = CAM.project(p)
        if 0 <= x < W and 0 <= y < H: px[int(x), int(y)] = col + (255,)
    if chevrons:
        x, y, _ = CAM.project(c)
        d = ImageDraw.Draw(im)
        for k in range(2):
            yy = int(y) - 7 - k * 4
            d.line([(int(x) - 3, yy - 2), (int(x), yy + 1), (int(x) + 3, yy - 2)], fill=col + (255,))

def trail(im, pts3, i_ball, n=14, col=(255, 246, 200)):
    px = im.load()
    for k in range(1, n):
        j = i_ball - k * 3
        if j < 0: break
        x, y, _ = CAM.project(pts3[j]); a = 1 - k / n
        xi, yi = int(x), int(y)
        if 0 <= xi < W and 0 <= yi < H and U.BAYER[yi % 4, xi % 4] < a * 0.9:
            px[xi, yi] = col + (255,)

def ball_px(im, p, r=1):
    x, y, _ = CAM.project(p); x, y = int(x), int(y)
    d = ImageDraw.Draw(im)
    d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=C['ball'] + (255,))
    im.load()[x - 1, y - 1] = C['gold_l'] + (255,); im.load()[x + 1, y + 1] = C['ball_d'] + (255,)

def hud(im, a=4, b=2, srv=1, serve_blue=True):
    U.score_pill(im, W // 2, 6, a, b, srv, serve_blue)
    U.round_button(im, W - 14, 15, 'pause'); U.round_button(im, W - 34, 15, 'guide')

# ---------------- mockups ----------------
def mock_rally():
    ball = np.array([0.6, 1.05, 2.4])
    sc = make_scene([('Ready', 5, 'red', (-0.9, 0, -5.9)), ('Side shuffle', 195, 'blue', (0.7, 0, 5.6))], ball=None)
    im = to_rgba(sc['img'])
    pts = arc_pts((-0.6, 1.0, -5.5), (0.9, 0.04, 4.6), 1.6)
    i_ball = 150
    land = (0.9, 0, 4.6)
    ground_ellipse(im, land, 0.28, C['red_l'], chevrons=True)
    draw_path(im, pts[i_ball:], C['red_l'], dash=(2, 3))
    trail(im, pts, i_ball)
    # ball shadow
    bp = pts[i_ball]; sx, sy, _ = CAM.project((bp[0], 0, bp[2]))
    ImageDraw.Draw(im).ellipse([sx - 2, sy - 1, sx + 2, sy + 1], fill=(28, 34, 70, 255))
    ball_px(im, bp)
    hud(im)
    U.joystick(im, 36, 392, 'active', (8, -5)); U.shot_wheel(im, 120, 392, 1, True); U.hit_button(im, 204, 392, 'idle')
    return im

def mock_serve():
    sc = make_scene([('Ready', 0, 'red', (-0.6, 0, -6.4)), ('Serve', 195, 'blue', (1.5, 0, 6.95))])
    im = to_rgba(sc['img'])
    p0 = (1.35, 0.95, 6.75); land = (-1.5, 0, -4.7)
    pts = arc_pts(p0, land, 2.0)
    draw_path(im, pts, C['gold'], dash=(4, 3), start=8)
    draw_path(im, [np.array([p[0], 0.0, p[2]]) for p in pts], (34, 52, 110), dash=(1, 2), start=8)
    ground_ellipse(im, land, 0.34, C['gold'], chevrons=True)
    # service box highlight (dithered)
    hud(im, 0, 0, 2)
    U.toast(im, 8, 30, 'HOLD HIT TO SERVE')
    U.joystick(im, 36, 392, 'idle'); U.shot_wheel(im, 120, 392, 0, True); U.hit_button(im, 204, 392, 'charge', 0.62)
    return im

def mock_focus(level='deep'):
    """Aim-focus slow-mo: smooth world-space dim + Kawase blur, sharp player/ball/UI."""
    from scene import paddle_pos
    from post import dof_post
    players = [('Ready', 0, 'red', (0.4, 0, -5.8)), ('Forehand drive', 200, 'blue', (-0.6, 0, 5.4))]
    sc = make_scene(players)
    keep = sc['pmask'] == 2
    prm = dict(deep=dict(strength=1.0, dim=0.6, desat=0.4), enter=dict(strength=0.45, dim=0.25, desat=0.15))[level]
    full, _ = dof_post(sc['img'], sc['depth'], keep, 11.7, z=3, in_focus=1.5, soft_focus=sc['pmask'] == 1, **prm)
    ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pp = paddle_pos('Forehand drive', 200, (-0.6, 0, 5.4))
    inc = arc_pts((0.4, 1.0, -5.6), pp, 1.4)
    i_b = 226
    trail(ov, inc, i_b, n=18, col=(255, 255, 255))
    ball_px(ov, inc[i_b])
    tgt = (1.8, 0, -5.2)
    aim = arc_pts(pp, tgt, 0.9)
    draw_path(ov, aim, C['cyan'], dash=(3, 2), start=6)
    ground_ellipse(ov, tgt, 0.36, C['cyan'], chevrons=True)
    hud(ov, 6, 5, 1)
    U.banner(ov, W // 2, 34, 'SLOW 0.25X', C['cyan'], C['blue_dd'], 1)
    U.joystick(ov, 36, 392, 'idle'); U.shot_wheel(ov, 120, 392, 1, True); U.hit_button(ov, 204, 392, 'aim', 1.0, (10, -14))
    base = Image.fromarray(full).convert('RGBA')
    big = ov.resize((W * 3, H * 3), Image.NEAREST)
    base.alpha_composite(big)
    return base

def mock_point():
    sc = make_scene([('Ready', 20, 'red', (-0.5, 0, -6.0)), ('Overhead smash', 185, 'blue', (0.4, 0, 4.2))])
    im = to_rgba(sc['img'])
    rng = np.random.default_rng(2); px = im.load()
    cols = [C['gold'], C['blue_l'], C['ball'], C['white'], C['red_l']]
    for _ in range(90):
        x = int(rng.random() * W); y = int(40 + rng.random() * 140)
        c = cols[rng.integers(len(cols))]
        px[x, y] = c + (255,)
        if rng.random() < 0.5 and x + 1 < W: px[x + 1, y] = c + (255,)
    hud(im, 7, 2, 1)
    U.banner(im, W // 2, 150, 'POINT BLUE!', C['blue_l'], C['blue_dd'], 2)
    U.ctext(im, W // 2, 178, 'SMASH WINNER  +1', C['gold'], 1, C['n0'])
    U.joystick(im, 36, 392, 'idle'); U.shot_wheel(im, 120, 392, 0, True); U.hit_button(im, 204, 392, 'perfect', 1.0)
    return im

def kit():
    KW, KH = 300, 210
    im = Image.new('RGBA', (KW, KH), C['n0'] + (255,))
    lab = lambda x, y, s: U.text(im, x, y, s, C['sub'])
    lab(6, 4, 'SCOREBOARD'); U.score_pill(im, 56, 14, 4, 2, 1)
    lab(112, 4, 'BADGES'); U.team_badge(im, 112, 14, 'YOU', True); U.team_badge(im, 140, 14, 'AI', False)
    lab(176, 4, 'BUTTONS'); U.round_button(im, 186, 22, 'pause'); U.round_button(im, 206, 22, 'guide')
    lab(232, 4, 'STAMINA'); U.stamina(im, 232, 18, 0.62)
    lab(6, 44, 'COACH TOAST'); U.toast(im, 6, 54, 'HOLD HIT TO SERVE')
    lab(140, 44, 'BANNERS'); U.banner(im, 200, 54, 'NICE DINK!', C['gold'], C['gold_d'], 1); U.banner(im, 200, 74, 'SIDE OUT', C['red_l'], C['red_dd'], 1)
    lab(6, 98, 'BIG BANNER'); U.banner(im, 70, 110, 'POINT BLUE!', C['blue_l'], C['blue_dd'], 2)
    lab(160, 98, 'SERVE MARKER'); U.icon_ball(im, 168, 116, 3); U.text(im, 176, 113, 'SERVER 2', C['txt'], 1, C['n0'])
    lab(6, 150, 'PALETTE')
    for i, k in enumerate(['n0', 'n1', 'n2', 'n3', 'n4', 'txt', 'sub', 'blue', 'blue_l', 'red', 'red_l', 'ball', 'gold', 'cyan', 'green']):
        ImageDraw.Draw(im).rectangle([6 + i * 19, 162, 6 + i * 19 + 15, 176], fill=C[k] + (255,))
    lab(6, 186, '5X7 FONT: ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 !?-/:+')
    return im

def controls():
    KW, KH = 300, 150
    im = Image.new('RGBA', (KW, KH), C['n0'] + (255,))
    lab = lambda x, y, s: U.ctext(im, x, y, s, C['sub'])
    xs = [30, 90]
    U.joystick(im, 30, 34, 'idle'); lab(30, 62, 'IDLE')
    U.joystick(im, 90, 34, 'active', (9, -6)); lab(90, 62, 'MOVING')
    hb = [('idle', 0, (0, 0), 'IDLE'), ('pressed', 0, (0, 0), 'PRESS'), ('charge', 0.55, (0, 0), 'CHARGE'), ('aim', 1.0, (11, -13), 'AIM DRAG'), ('perfect', 1.0, (0, 0), 'PERFECT')]
    for i, (st, ch, aim, l) in enumerate(hb):
        x = 30 + i * 60
        U.hit_button(im, x, 104, st, ch, aim); lab(x, 132, l)
    for i in range(4):
        U.shot_wheel(im, 150 + i * 40, 30, i, False); lab(150 + i * 40, 56, U.WHEEL[i])
    return im

def save(im, name, z):
    im.resize((im.width * z, im.height * z), Image.NEAREST).save('art/%s.png' % name)

if __name__ == '__main__':
    for fn, nm in ((mock_rally, 'ui_rally'), (mock_serve, 'ui_serve'), (mock_point, 'ui_point')):
        save(fn(), nm, 3)
    mock_focus().convert('RGB').save('art/ui_focus.png')
    save(kit(), 'ui_kit', 5)
    save(controls(), 'ui_controls', 5)
    print('ok')
