"""Reusable pixel court scene from the real in-game rally camera (240x427 = 1/3 of 720x1280)."""
import sys; sys.path.insert(0, '.')
import numpy as np
from sprites import build, hx
from sprites2 import Cam, render_cam, shift, bounds
from poses import POSES

W, H = 240, 427
CAM = Cam.persp((0, 8.386, 14.429), -31.4548, 0, 34.0, W, H, v_off=-0.378)

def make_scene(players, vignette=True, ball=None, shadows=True):
    cam = CAM
    o, d = cam.rays(1, (0, 0, W, H))
    o = o.reshape(H, W, 3); d = d.reshape(H, W, 3)
    t = np.where(d[..., 1] < -1e-6, -o[..., 1] / np.minimum(d[..., 1], -1e-6), 1e9)
    P = o + d * t[..., None]; x, z = P[..., 0], P[..., 2]
    rng = np.random.default_rng(5)
    img = np.zeros((H, W, 3), np.uint8); img[:] = hx('#2a3350')
    nz = rng.random((H, W))
    img[(nz > 0.9) & (t < 1e8)] = hx('#2f3958'); img[t > 1e8] = hx('#1f2438')
    img[(np.abs(x) < 3.8) & (np.abs(z) < 8.1)] = hx('#3a5db0')
    court = (np.abs(x) < 3.05) & (np.abs(z) < 6.705)
    img[court] = hx('#4470c4'); img[court & (nz > 0.93)] = hx('#4a77ca')
    kitchen = court & (np.abs(z) < 2.13)
    LINEC = np.array(hx('#eef2fb'))
    def seg(a, b, w=1):
        xa, ya, _ = cam.project(a); xb, yb, _ = cam.project(b)
        n = int(max(abs(xb - xa), abs(yb - ya)) * 2) + 2
        for k in range(n + 1):
            u = k / n; xx = xa + (xb - xa) * u; yy = ya + (yb - ya) * u
            for dx in range(w):
                xi, yi = int(np.floor(xx)) + dx, int(np.floor(yy))
                if 0 <= xi < W and 0 <= yi < H: img[yi, xi] = LINEC
    X, Z = 3.05, 6.705
    for zz in (Z, -Z, 2.13, -2.13): seg((-X, 0, zz), (X, 0, zz), 2 if zz == Z else 1)
    for xx in (-X, X): seg((xx, 0, -Z), (xx, 0, Z))
    seg((0, 0, 2.13), (0, 0, Z)); seg((0, 0, -Z), (0, 0, -2.13))
    for kind in ('back', 'side'):
        if kind == 'back':
            tw = np.where(np.abs(d[..., 2]) > 1e-6, (-10.4 - o[..., 2]) / d[..., 2], 1e9)
        else:
            tw = np.minimum(np.where(d[..., 0] > 1e-6, (5.6 - o[..., 0]) / d[..., 0], 1e9),
                            np.where(d[..., 0] < -1e-6, (-5.6 - o[..., 0]) / d[..., 0], 1e9))
        Pw = o + d * tw[..., None]
        wm = (tw > 0) & (tw < t) & (Pw[..., 1] >= 0) & (Pw[..., 1] < 3.2)
        wm &= (Pw[..., 2] > -10.4) if kind == 'side' else (np.abs(Pw[..., 0]) < 5.6)
        img[wm] = hx('#2c3658') if kind == 'back' else hx('#27304e')
        img[wm & (Pw[..., 1] > 0.95) & (Pw[..., 1] < 1.05)] = hx('#5fb8ff')
        if kind == 'back':
            img[wm & (Pw[..., 1] > 1.6) & (Pw[..., 1] < 2.6) & (np.abs(Pw[..., 0]) < 2.2)] = hx('#33406a')
        t = np.where(wm, tw, t)
    def shade(cx, cz, rx, rz, k=(0.72, 0.72, 0.86)):
        m = ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2 < 1
        img[m] = (img[m] * np.array(k)).astype(np.uint8)
    if shadows:
        for _, _, _, pos in players: shade(pos[0], pos[2], 0.36, 0.22)
        if ball is not None: shade(ball[0], ball[2], 0.09, 0.06, (0.6, 0.62, 0.8))
    tn = np.where(np.abs(d[..., 2]) > 1e-6, -o[..., 2] / d[..., 2], 1e9)
    Pn = o + d * tn[..., None]
    netm = (tn > 0) & (tn < t) & (Pn[..., 1] > 0) & (Pn[..., 1] < 0.9 + 0.03 * np.abs(Pn[..., 0])) & (np.abs(Pn[..., 0]) < 3.35)
    mesh = ((np.floor(Pn[..., 0] / 0.07) + np.floor(Pn[..., 1] / 0.07)) % 2 == 0)
    netcol = img.copy()
    img[netm] = (img[netm] * 0.55 + np.array(hx('#1e2238')) * 0.45).astype(np.uint8)
    img[netm & mesh] = (netcol[netm & mesh] * 0.75 + np.array(hx('#1e2238')) * 0.25).astype(np.uint8)
    img[netm & (Pn[..., 1] > 0.83 + 0.03 * np.abs(Pn[..., 0]))] = hx('#f1f4f8')
    post = (tn > 0) & (tn < t) & (Pn[..., 1] > 0) & (Pn[..., 1] < 0.98) & (np.abs(np.abs(Pn[..., 0]) - 3.38) < 0.04)
    img[post] = hx('#56607f')
    netdepth = np.where(netm | post, tn, 1e9)
    depth = np.where(netm | post, tn, np.minimum(t, 40.0))
    pmask = np.zeros((H, W), int)  # 0 none, i+1 player index
    for i, (name, yaw, team, pos) in sorted(enumerate(players), key=lambda e: e[1][3][2]):
        J = shift(build(POSES[name] if isinstance(name, str) else name, yaw), pos)
        spr, dep, (ox, oy) = render_cam(J, team, cam, rect=bounds(cam, pos), ss=3)
        h_, w_ = spr.shape[:2]
        m = (spr[..., 3] > 0) & (dep < netdepth[oy:oy + h_, ox:ox + w_])
        img[oy:oy + h_, ox:ox + w_][m] = spr[m, :3]
        pmask[oy:oy + h_, ox:ox + w_][m] = i + 1
        depth[oy:oy + h_, ox:ox + w_][m] = dep[m]
    if ball is not None:
        bx, by, _ = cam.project(ball); bx, by = int(bx), int(by)
        for dx, dy, cc in ((0, 0, '#d6f23c'), (1, 0, '#d6f23c'), (0, 1, '#a0c42b'), (1, 1, '#a0c42b')):
            if 0 <= bx + dx < W and 0 <= by + dy < H: img[by + dy, bx + dx] = hx(cc)
    base = img.copy()
    if vignette: img = apply_vignette(img)
    return dict(img=img, base=base, pmask=pmask, depth=depth, cam=cam, court=court, kitchen=kitchen, x=x, z=z, t=t)

def apply_vignette(img):
    ys, xs = np.mgrid[0:H, 0:W]
    r = ((xs - W / 2) / (W / 2)) ** 2 + ((ys - H * 0.55) / (H * 0.6)) ** 2
    v = np.clip(1.08 - 0.3 * r, 0.6, 1)[..., None]
    return (img * v).clip(0, 255).astype(np.uint8)

def paddle_pos(pose_name, yaw, pos, ahead=0.08):
    from sprites import Char
    J = shift(build(POSES[pose_name], yaw), pos)
    c = Char(J, 'blue')
    return c.pad_c + J['pad_n'] * ahead
