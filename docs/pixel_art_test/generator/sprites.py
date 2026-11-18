"""Pixel-art player renderer: 3D SDF character -> low-res toon pixels, no outlines."""
import numpy as np
from math import sin, cos, radians

# ---------------- palettes (hi, base, shade, deep) ----------------
def hx(h): h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
PAL = {
    'skin':   ['#ffdcc2', '#f5b594', '#de8c7a', '#a9606e'],
    'hair':   ['#8c6b93', '#5c4268', '#3e2b4c', '#2a1d37'],
    'blue':   ['#86c8ff', '#3f90e8', '#2d62b9', '#283f86'],
    'red':    ['#ffa08f', '#ef5b53', '#c13b4f', '#862d49'],
    'white':  ['#ffffff', '#eef0f8', '#c4c4de', '#9290b6'],
    'navy':   ['#5b6392', '#3c4272', '#2b2e57', '#1f2041'],
    'paddle': ['#fff6b8', '#ffe05c', '#fbbd3c', '#de8a32'],
    'pedge':  ['#6d7ba9', '#45517f', '#2f3761', '#232848'],
    'ball':   ['#f4ffa6', '#d6f23c', '#a0c42b', '#6f902b'],
}
MATS = ['skin', 'hair', 'TEAM', 'white', 'navy', 'paddle', 'pedge', 'ball', 'TEAMDEEP']
EYE = hx('#2a1d37'); BLUSH = hx('#ee8f8b')

# ---------------- math helpers ----------------
def Ry(a):
    c, s = cos(a), sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rx(a):
    c, s = cos(a), sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Rz(a):
    c, s = cos(a), sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def nrm(v): return v / np.linalg.norm(v)
def ldir(flex, abd, side):
    f, a = radians(flex), radians(abd)
    return np.array([side * sin(a), -cos(a) * cos(f), cos(a) * sin(f)])

# ---------------- SDF primitives ----------------
def sd_capsule(p, a, b, ra, rb):
    pa = p - a; ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)
    return np.linalg.norm(pa - h[:, None] * ba, axis=1) - (ra + (rb - ra) * h), h
def sd_ellipsoid(q, r):
    k0 = np.linalg.norm(q / r, axis=1); k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1) / np.maximum(k1, 1e-9)
def sd_rbox(q, half, r):
    d = np.abs(q) - (np.array(half) - r)
    return np.linalg.norm(np.maximum(d, 0), axis=1) + np.minimum(d.max(axis=1), 0) - r
def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)

# ---------------- skeleton / FK ----------------
L_UP, L_FORE, L_THIGH, L_SHIN = 0.23, 0.21, 0.33, 0.33
HEAD_SCALE = 1.0

def build(pose, yaw_deg):
    P = dict(pelvis=0.84, twist=0, lean=12, roll=0,
             r_up=(40, 22), r_fo=(115, 5), l_up=(35, 18), l_fo=(105, 25),
             r_th=(25, 12), r_sh=(-5, 8), l_th=(25, 12), l_sh=(-5, 8),
             r_foot=-12, l_foot=12, pad=(172, 12), pad_n=(0, 0, 1), ball=None)
    P.update(pose)
    Rt = Rz(radians(P['roll'])) @ Ry(radians(P['twist'])) @ Rx(radians(P['lean']))
    Rp = Ry(radians(P['twist'] * 0.35))
    pel = np.array([0, P['pelvis'], 0.0])
    J = {}
    J['pelvis'] = pel
    J['chest'] = pel + Rt @ [0, 0.36, 0]
    J['neck'] = pel + Rt @ [0, 0.50, 0]
    J['head'] = pel + Rt @ [0, 0.50, 0] + [0, 0.17, 0.01]
    J['Rt'] = Rt; J['Rp'] = Rp
    J['Rh'] = Ry(radians(P['twist'] * 0.6 + P.get('look', 0))) @ Rx(radians(P.get('nod', 0)))
    for side, s in (('r', -1), ('l', 1)):
        sh = pel + Rt @ [s * 0.165, 0.44, 0]
        el = sh + Rt @ (ldir(*P[side + '_up'], s) * L_UP)
        wr = el + Rt @ (ldir(*P[side + '_fo'], s) * L_FORE)
        hp = pel + Rp @ [s * 0.095, -0.03, 0]
        kn = hp + Rp @ (ldir(*P[side + '_th'], s) * L_THIGH)
        an = kn + Rp @ (ldir(*P[side + '_sh'], s) * L_SHIN)
        J[side + 'sh'], J[side + 'el'], J[side + 'wr'] = sh, el, wr
        J[side + 'hp'], J[side + 'kn'], J[side + 'an'] = hp, kn, an
        J[side + 'foot'] = Rp @ Ry(radians(P[side + '_foot'])) @ [0, 0, 1]
    J['pad_d'] = nrm(Rt @ ldir(*P['pad'], -1))
    n = Rt @ np.array(P['pad_n'], float)
    n = nrm(n - (n @ J['pad_d']) * J['pad_d'])
    J['pad_n'] = n
    J['ball'] = None if P['ball'] in (None, 'pad') else np.array(P['ball'], float)
    J['ball_on_pad'] = P['ball'] == 'pad'
    # plant lowest foot on the floor
    drop = min(J['ran'][1], J['lan'][1]) - 0.075
    Y = Ry(radians(yaw_deg))
    out = {}
    for k, v in J.items():
        if k in ('Rt', 'Rp', 'Rh'): out[k] = Y @ v
        elif k in ('rfoot', 'lfoot', 'pad_d', 'pad_n'): out[k] = Y @ v
        elif v is None or isinstance(v, bool): out[k] = v
        elif k == 'ball' and P.get('ball_world'): out[k] = Y @ v
        else: out[k] = Y @ (v - [0, drop, 0])
    return out

# ---------------- scene ----------------
class Char:
    def __init__(self, J, team):
        self.J = J; self.team = team
        Rt = J['Rt']; self.RtT = Rt.T
        self.Rh = J['Rh']  # head frame (stays upright)
        pd, pn = J['pad_d'], J['pad_n']
        self.Pax = np.stack([nrm(np.cross(pd, pn)), pd, pn], axis=1)  # columns x,y,z
        self.hand_r = J['rwr'] + (J['rwr'] - J['rel']) / L_FORE * 0.045
        self.hand_l = J['lwr'] + (J['lwr'] - J['lel']) / L_FORE * 0.045
        self.pad_c = self.hand_r + pd * 0.24
        if J.get('ball_on_pad'): J['ball'] = self.pad_c + pd * 0.02 + pn * 0.07

    def prims(self, p):
        J = self.J; D = {}
        # head (head-local coords)
        hs = HEAD_SCALE
        qh = (p - J['head']) @ self.Rh / hs
        D['head'] = sd_ellipsoid(qh, np.array([0.165, 0.165, 0.155]))
        hair = sd_ellipsoid(qh - [0, 0.02, -0.012], np.array([0.177, 0.17, 0.168]))
        mask = np.minimum(0.105 - qh[:, 1] + np.maximum(qh[:, 0] * 0.4, 0) * 0, np.maximum(qh[:, 2] + 0.03, -0.13 - qh[:, 1]))
        D['hair'] = np.maximum(hair, mask)
        D['pony'] = sd_ellipsoid(qh - [0, 0.0, -0.185], np.array([0.065, 0.1, 0.065]))
        band = sd_ellipsoid(qh - [0, 0.0, 0], np.array([0.183, 0.18, 0.175]))
        D['visor'] = np.maximum(band, np.abs(qh[:, 1] - 0.118 + qh[:, 2] * 0.15) - 0.02)
        for _k in ('head', 'hair', 'pony', 'visor'): D[_k] = D[_k] * hs
        D['neck'], _ = sd_capsule(p, J['neck'], J['head'] - self.Rh @ [0, 0.1, 0], 0.045, 0.045)
        # torso / shorts
        qt = (p - J['pelvis']) @ J['Rt']
        D['torso'] = sd_rbox(qt - [0, 0.28, 0], (0.16, 0.19, 0.105), 0.075)
        qp = (p - J['pelvis']) @ J['Rp']
        D['shorts'] = sd_rbox(qp - [0, 0.03, 0], (0.16, 0.1, 0.11), 0.06)
        self.qt, self.qp, self.qh = qt, qp, qh
        H = {}
        for s in 'rl':
            D[s + 'up'], H[s + 'up'] = sd_capsule(p, J[s + 'sh'], J[s + 'el'], 0.055, 0.046)
            D[s + 'fo'], H[s + 'fo'] = sd_capsule(p, J[s + 'el'], J[s + 'wr'], 0.044, 0.037)
            hand = self.hand_r if s == 'r' else self.hand_l
            D[s + 'hand'] = np.linalg.norm(p - hand, axis=1) - 0.046
            D[s + 'th'], H[s + 'th'] = sd_capsule(p, J[s + 'hp'], J[s + 'kn'], 0.075, 0.058)
            D[s + 'sh'], H[s + 'sh'] = sd_capsule(p, J[s + 'kn'], J[s + 'an'], 0.056, 0.04)
            f = J[s + 'foot']; f = nrm(np.array([f[0], 0, f[2]]))
            Rf = np.stack([np.cross([0, 1, 0], f), [0, 1, 0], f], axis=1)
            qf = (p - (J[s + 'an'] + f * 0.045 + [0, -0.04, 0])) @ Rf
            D[s + 'shoe'] = sd_rbox(qf, (0.05, 0.038, 0.105), 0.032)
            H[s + 'shoe'] = qf
        # paddle (3D object)
        qpad = (p - self.pad_c) @ self.Pax
        D['pface'] = sd_rbox(qpad, (0.095, 0.125, 0.012), 0.011)
        self.qpad = qpad
        D['handle'], _ = sd_capsule(p, self.hand_r - self.J['pad_d'] * 0.03, self.hand_r + self.J['pad_d'] * 0.13, 0.017, 0.017)
        if J['ball'] is not None:
            D['ball'] = np.linalg.norm(p - J['ball'], axis=1) - 0.04
        self.H = H
        return D

    BODY = ['torso', 'shorts', 'rup', 'lup', 'rfo', 'lfo', 'rth', 'lth', 'rsh', 'lsh', 'neck']
    def dist(self, p):
        D = self.prims(p)
        body = D['torso']
        for k in ['shorts', 'rup', 'lup', 'rth', 'lth', 'neck']:
            body = smin(body, D[k], 0.03)
        for k in ['rfo', 'lfo', 'rsh', 'lsh']:
            body = smin(body, D[k], 0.018)
        d = body
        for k in D:
            if k not in self.BODY: d = np.minimum(d, D[k])
        return d

    def material(self, p):
        D = self.prims(p)
        keys = list(D.keys()); arr = np.stack([D[k] for k in keys], 1)
        idx = arr.argmin(1); m = np.zeros(len(p), int)
        TEAM, WHITE, SKIN, NAVY = 2, 3, 0, 4
        for i, k in enumerate(keys):
            sel = idx == i
            if not sel.any(): continue
            if k == 'head': m[sel] = SKIN
            elif k in ('hair', 'pony'): m[sel] = 1
            elif k == 'visor': m[sel] = TEAM
            elif k == 'neck': m[sel] = SKIN
            elif k == 'torso':
                qt = self.qt[sel]
                v = np.full(sel.sum(), TEAM)
                v[np.abs(qt[:, 0]) > 0.125] = WHITE
                v[(qt[:, 1] > 0.41) & (np.abs(qt[:, 0]) < 0.07) & (qt[:, 2] > 0)] = WHITE  # collar
                m[sel] = v
            elif k == 'shorts': m[sel] = NAVY
            elif k.endswith('up'):
                h = self.H[k][sel]; m[sel] = np.where(h < 0.42, TEAM, SKIN)
            elif k.endswith('fo'):
                h = self.H[k][sel]; m[sel] = np.where((h > 0.72) & (h < 0.9), WHITE, SKIN)
            elif k.endswith('hand'): m[sel] = SKIN
            elif k.endswith('th'):
                h = self.H[k][sel]; m[sel] = np.where(h < 0.5, NAVY, SKIN)
            elif k.endswith('sh'):
                h = self.H[k][sel]; m[sel] = np.where(h > 0.72, WHITE, SKIN)
            elif k.endswith('shoe'):
                qf = self.H[k][sel]; m[sel] = np.where(qf[:, 1] < -0.018, 8, WHITE)
            elif k == 'pface':
                q = self.qpad[sel]
                rim = np.maximum(np.abs(q[:, 0]) - 0.078, np.abs(q[:, 1]) - 0.108) > 0
                m[sel] = np.where(rim, 6, 5)
            elif k == 'handle': m[sel] = 6
            elif k == 'ball': m[sel] = 7
        return m

# ---------------- renderer ----------------
PITCH = radians(38)
CAMD = 30.0
F = np.array([0, -sin(PITCH), -cos(PITCH)]); RIGHT = np.array([1.0, 0, 0]); UP = np.cross(RIGHT, F)
LIGHT = nrm(np.array([-0.55, 0.85, 0.5]))

def render(pose, yaw, team='blue', W=64, H=72, s=0.027, ss=3, target=(0, 0.82, 0)):
    J = build(pose, yaw)
    ch = Char(J, team)
    target = np.array(target, float)
    n = W * ss; m = H * ss
    us = (np.arange(n) - n / 2 + 0.5) * s / ss
    vs = (m / 2 - np.arange(m) - 0.5) * s / ss
    U, V = np.meshgrid(us, vs)
    o = target + U.reshape(-1, 1) * RIGHT + V.reshape(-1, 1) * UP - F * CAMD
    t = np.zeros(len(o)); hit = np.zeros(len(o), bool); alive = np.ones(len(o), bool)
    for _ in range(140):
        idx = np.where(alive)[0]
        if len(idx) == 0: break
        p = o[idx] + F * t[idx, None]
        d = ch.dist(p)
        t[idx] += d * 0.9
        h = d < 0.0012; hit[idx[h]] = True; alive[idx[h]] = False
        alive[idx[t[idx] > CAMD + 6]] = False
    hi = np.where(hit)[0]
    p = o[hi] + F * t[hi, None]
    e = 0.002
    nx = np.stack([ch.dist(p + [e, 0, 0]) - ch.dist(p - [e, 0, 0]),
                   ch.dist(p + [0, e, 0]) - ch.dist(p - [0, e, 0]),
                   ch.dist(p + [0, 0, e]) - ch.dist(p - [0, 0, e])], 1)
    nx /= np.linalg.norm(nx, axis=1, keepdims=True)
    ao = np.clip(ch.dist(p + nx * 0.06) / 0.06, 0, 1)
    lam = nx @ LIGHT
    back = np.clip(nx @ nrm(np.array([0.6, 0.2, -0.8])), 0, 1)  # cool rim from behind-right
    v = lam - (1 - ao) * 0.55 + back * 0.25
    tone = np.select([v > 0.74, v > 0.2, v > -0.28], [0, 1, 2], 3)
    mat = ch.material(p)
    # aggregate supersamples
    MAT = np.full(n * m, -1); MAT[hi] = mat
    TON = np.zeros(n * m); TON[hi] = tone
    DEP = np.full(n * m, 99.0); DEP[hi] = t[hi]
    MAT = MAT.reshape(H, ss, W, ss).transpose(0, 2, 1, 3).reshape(H, W, ss * ss)
    TON = TON.reshape(H, ss, W, ss).transpose(0, 2, 1, 3).reshape(H, W, ss * ss)
    DEP = DEP.reshape(H, ss, W, ss).transpose(0, 2, 1, 3).reshape(H, W, ss * ss)
    cover = (MAT >= 0).sum(2)
    counts = np.stack([(MAT == k).sum(2) for k in range(len(MATS))], 2)
    pm = counts.argmax(2)
    sel = MAT == pm[..., None]
    pt = np.where(sel.sum(2) > 0, (TON * sel).sum(2) / np.maximum(sel.sum(2), 1), 0)
    pt = np.clip(np.round(pt), 0, 3).astype(int)
    pd = np.where(sel, DEP, 99).min(2)
    opaque = cover * 2 >= ss * ss
    pm[~opaque] = -1
    # occlusion darkening: pixel behind a much nearer neighbour gets one tone darker
    out_t = pt.copy()
    for dy, dx in ((-1, 0), (0, -1), (0, 1), (1, 0)):
        nb_d = np.roll(np.roll(pd, dy, 0), dx, 1); nb_m = np.roll(np.roll(pm, dy, 0), dx, 1)
        behind = opaque & (nb_m >= 0) & (pd - nb_d > 0.09)
        out_t[behind] = np.maximum(out_t[behind], np.minimum(pt[behind] + 1, 3))
    pt = out_t
    # despeckle: lone tone pixel surrounded by one other tone of same material
    for _ in range(2):
        up_, dn = np.roll(pt, 1, 0), np.roll(pt, -1, 0); lf, rt = np.roll(pt, 1, 1), np.roll(pt, -1, 1)
        same_m = (np.roll(pm, 1, 0) == pm) & (np.roll(pm, -1, 0) == pm) & (np.roll(pm, 1, 1) == pm) & (np.roll(pm, -1, 1) == pm)
        lone = same_m & (up_ == dn) & (dn == lf) & (lf == rt) & (up_ != pt)
        pt = np.where(lone, up_, pt)
    # to RGBA
    img = np.zeros((H, W, 4), np.uint8)
    for k, name in enumerate(MATS):
        if name == 'TEAM': name = team
        if name == 'TEAMDEEP': name = team
        pal = [hx(c) for c in PAL[name]]
        for tn in range(4):
            tt = min(tn + 2, 3) if MATS[k] == 'TEAMDEEP' else tn
            w = (pm == k) & (pt == tn)
            img[w, :3] = pal[tt]; img[w, 3] = 255
    # eyes + blush
    head_fwd = J['Rt'] @ np.array([0, 0, 1.0]) if False else ch.Rh @ np.array([0, 0, 1.0])
    if head_fwd @ (-F) > 0.05:
        for sx in (-1, 1):
            ep = J['head'] + ch.Rh @ np.array([sx * 0.064, 0.005, 0.155])
            side_vis = (ch.Rh @ np.array([sx * 0.9, 0, 1.0])) @ (-F)
            if side_vis < 0.05: continue
            d = ep - (target - F * CAMD)
            x = int(np.floor(d @ RIGHT / s + W / 2)); y = int(np.floor(H / 2 - d @ UP / s))
            if not (0 <= x < W and 0 <= y < H - 2): continue
            if pm[y, x] != 0 and pm[y + 1, x] == 0: y += 1
            if pm[y, x] == 0 and pm[y + 1, x] == 0 and abs(pd[y, x] - (d @ F)) < 0.08:
                img[y, x, :3] = EYE; img[y + 1, x, :3] = EYE
                if y + 2 < H and pm[y + 2, x] == 0 and head_fwd @ (-F) > 0.5:
                    bx = x + (1 if sx * (RIGHT @ (ch.Rh @ [1, 0, 0])) > 0 else -1)
                    if 0 <= bx < W and pm[y + 2, bx] == 0: img[y + 2, bx, :3] = BLUSH
    # ground shadow (behind character) - returned separately
    feet = (J['ran'] + J['lan']) / 2
    return img, feet, target, J

def shadow_mask(J, target, W, H, s, rx=0.30, rz=0.17):
    c = (J['ran'] + J['lan']) / 2; c = np.array([c[0], 0.0, c[2]])
    ys, xs = np.mgrid[0:H, 0:W]
    # ray from each pixel to ground plane y=0
    O = (target - F * CAMD)[None, None, :] + ((xs - W / 2 + 0.5) * s)[..., None] * RIGHT + ((H / 2 - ys - 0.5) * s)[..., None] * UP
    t = -O[..., 1] / F[1]
    P = O + t[..., None] * F
    span = abs(J['ran'][0] - J['lan'][0]) + abs(J['ran'][2] - J['lan'][2])
    return ((P[..., 0] - c[0]) / (rx + span * 0.35)) ** 2 + ((P[..., 2] - c[2]) / (rz + span * 0.2)) ** 2 < 1
