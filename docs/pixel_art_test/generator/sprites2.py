"""Camera-accurate renderer: perspective (Godot Camera3D match) or ortho, with part isolation."""
import numpy as np
from math import radians, tan, sin, cos
from sprites import (build, Char, smin, nrm, hx, PAL, MATS, EYE, BLUSH, LIGHT, Rx, Ry)

POS_SKIP = {'Rt', 'Rp', 'Rh', 'rfoot', 'lfoot', 'pad_d', 'pad_n', 'ball_on_pad'}

def shift(J, pos):
    pos = np.asarray(pos, float)
    out = {}
    for k, v in J.items():
        if k in POS_SKIP or v is None or isinstance(v, bool): out[k] = v
        else: out[k] = v + pos
    return out

class Cam:
    @classmethod
    def persp(cls, eye, pitch, yaw, fov_h, W, H, v_off=0.0):
        c = cls(); c.kind = 'p'; c.W, c.H = W, H
        B = Ry(radians(yaw)) @ Rx(radians(pitch))
        c.right, c.up, c.fwd = B[:, 0], B[:, 1], -B[:, 2]
        c.eye = np.asarray(eye, float) + c.up * v_off
        c.th = tan(radians(fov_h) / 2); c.tv = c.th * H / W
        return c
    @classmethod
    def ortho(cls, pitch, s, W, H, target):
        c = cls(); c.kind = 'o'; c.W, c.H, c.s = W, H, s
        p = radians(pitch)
        c.fwd = np.array([0, -sin(p), -cos(p)]); c.right = np.array([1.0, 0, 0]); c.up = np.cross(c.right, c.fwd)
        c.eye = np.asarray(target, float) - c.fwd * 30.0
        return c
    def rays(self, ss, rect):
        x0, y0, x1, y1 = rect
        xs = x0 + (np.arange((x1 - x0) * ss) + 0.5) / ss
        ys = y0 + (np.arange((y1 - y0) * ss) + 0.5) / ss
        X, Y = np.meshgrid(xs, ys); X = X.ravel(); Y = Y.ravel()
        if self.kind == 'p':
            xn = X / self.W * 2 - 1; yn = 1 - Y / self.H * 2
            d = self.fwd + np.outer(xn * self.th, self.right) + np.outer(yn * self.tv, self.up)
            d /= np.linalg.norm(d, axis=1, keepdims=True)
            o = np.repeat(self.eye[None], len(d), 0)
        else:
            u = (X - self.W / 2) * self.s; v = (self.H / 2 - Y) * self.s
            o = self.eye + np.outer(u, self.right) + np.outer(v, self.up)
            d = np.repeat(self.fwd[None], len(o), 0)
        return o, d
    def project(self, P):
        v = np.asarray(P, float) - self.eye
        if self.kind == 'p':
            z = v @ self.fwd
            x = ((v @ self.right) / (z * self.th) + 1) / 2 * self.W
            y = (1 - (v @ self.up) / (z * self.tv)) / 2 * self.H
            return x, y, np.linalg.norm(v)
        x = (v @ self.right) / self.s + self.W / 2
        y = self.H / 2 - (v @ self.up) / self.s
        return x, y, v @ self.fwd
    def viewdir(self, P):
        return nrm(np.asarray(P, float) - self.eye) if self.kind == 'p' else self.fwd

class PartChar(Char):
    def __init__(self, J, team, only=None):
        super().__init__(J, team); self.only = only
    def _filt(self, D):
        return D if self.only is None else {k: D[k] for k in self.only if k in D}
    def dist(self, p):
        D = self._filt(self.prims(p))
        body = None
        for k in ['torso', 'shorts', 'rup', 'lup', 'rth', 'lth', 'neck']:
            if k in D: body = D[k] if body is None else smin(body, D[k], 0.03)
        for k in ['rfo', 'lfo', 'rsh', 'lsh']:
            if k in D: body = D[k] if body is None else smin(body, D[k], 0.018)
        d = body
        for k in D:
            if k not in self.BODY: d = D[k] if d is None else np.minimum(d, D[k])
        return d
    def material(self, p):
        if self.only is None: return super().material(p)
        orig = self.prims
        def filtered(q, _o=orig): return self._filt(_o(q))
        self.prims = filtered
        try: return super().material(p)
        finally: self.prims = orig

def render_cam(J, team, cam, rect=None, ss=2, only=None, eyes=True):
    ch = PartChar(J, team, only)
    if rect is None: rect = (0, 0, cam.W, cam.H)
    x0, y0, x1, y1 = [int(v) for v in rect]
    x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, cam.W), min(y1, cam.H)
    W, H = x1 - x0, y1 - y0
    o, D = cam.rays(ss, (x0, y0, x1, y1))
    centre = J['pelvis']
    t0 = max(0.0, np.linalg.norm(centre - cam.eye) - 3.0) if cam.kind == 'p' else 25.0
    tmax = np.linalg.norm(centre - cam.eye) + 3.0 if cam.kind == 'p' else 36.0
    t = np.full(len(o), t0); hit = np.zeros(len(o), bool); alive = np.ones(len(o), bool)
    for _ in range(160):
        idx = np.where(alive)[0]
        if len(idx) == 0: break
        p = o[idx] + D[idx] * t[idx, None]
        d = ch.dist(p)
        t[idx] += d * 0.9
        h = d < 0.0012; hit[idx[h]] = True; alive[idx[h]] = False
        alive[idx[t[idx] > tmax]] = False
    n_s, m_s = W * ss, H * ss
    img = np.zeros((H, W, 4), np.uint8); depth = np.full((H, W), 1e9)
    hi = np.where(hit)[0]
    if len(hi) == 0: return img, depth, (x0, y0)
    p = o[hi] + D[hi] * t[hi, None]
    e = 0.002
    nx = np.stack([ch.dist(p + [e, 0, 0]) - ch.dist(p - [e, 0, 0]),
                   ch.dist(p + [0, e, 0]) - ch.dist(p - [0, e, 0]),
                   ch.dist(p + [0, 0, e]) - ch.dist(p - [0, 0, e])], 1)
    nx /= np.linalg.norm(nx, axis=1, keepdims=True)
    ao = np.clip(ch.dist(p + nx * 0.06) / 0.06, 0, 1)
    v = nx @ LIGHT - (1 - ao) * 0.55 + np.clip(nx @ nrm(np.array([0.6, 0.2, -0.8])), 0, 1) * 0.25
    tone = np.select([v > 0.74, v > 0.2, v > -0.28], [0, 1, 2], 3)
    mat = ch.material(p)
    MAT = np.full(n_s * m_s, -1); MAT[hi] = mat
    TON = np.zeros(n_s * m_s); TON[hi] = tone
    DEP = np.full(n_s * m_s, 1e9); DEP[hi] = t[hi]
    rs = lambda A: A.reshape(H, ss, W, ss).transpose(0, 2, 1, 3).reshape(H, W, ss * ss)
    MAT, TON, DEP = rs(MAT), rs(TON), rs(DEP)
    cover = (MAT >= 0).sum(2)
    counts = np.stack([(MAT == k).sum(2) for k in range(len(MATS))], 2)
    pm = counts.argmax(2)
    sel = MAT == pm[..., None]
    pt = np.clip(np.round(np.where(sel.sum(2) > 0, (TON * sel).sum(2) / np.maximum(sel.sum(2), 1), 0)), 0, 3).astype(int)
    pd = np.where(sel, DEP, 1e9).min(2)
    opaque = cover * 2 >= ss * ss
    pm[~opaque] = -1
    out_t = pt.copy()
    for dy, dx in ((-1, 0), (0, -1), (0, 1), (1, 0)):
        nb_d = np.roll(np.roll(pd, dy, 0), dx, 1); nb_m = np.roll(np.roll(pm, dy, 0), dx, 1)
        behind = opaque & (nb_m >= 0) & (pd - nb_d > 0.09)
        out_t[behind] = np.maximum(out_t[behind], np.minimum(pt[behind] + 1, 3))
    pt = out_t
    for _ in range(2):
        up_, dn = np.roll(pt, 1, 0), np.roll(pt, -1, 0); lf, rt = np.roll(pt, 1, 1), np.roll(pt, -1, 1)
        same_m = (np.roll(pm, 1, 0) == pm) & (np.roll(pm, -1, 0) == pm) & (np.roll(pm, 1, 1) == pm) & (np.roll(pm, -1, 1) == pm)
        lone = same_m & (up_ == dn) & (dn == lf) & (lf == rt) & (up_ != pt)
        pt = np.where(lone, up_, pt)
    for k, name in enumerate(MATS):
        nm = team if name in ('TEAM', 'TEAMDEEP') else name
        pal = [hx(c) for c in PAL[nm]]
        for tn in range(4):
            tt = min(tn + 2, 3) if name == 'TEAMDEEP' else tn
            w = (pm == k) & (pt == tn)
            img[w, :3] = pal[tt]; img[w, 3] = 255
    depth = np.where(opaque, pd, 1e9)
    if eyes and (only is None or 'head' in only):
        hf = ch.Rh @ np.array([0, 0, 1.0])
        for sx in (-1, 1):
            ep = J['head'] + ch.Rh @ np.array([sx * 0.064, 0.02, 0.155])
            vd = cam.viewdir(ep)
            if hf @ (-vd) < 0.05 or (ch.Rh @ np.array([sx * 0.9, 0, 1.0])) @ (-vd) < 0.05: continue
            fx, fy, ed = cam.project(ep)
            x, y = int(np.floor(fx)) - x0, int(np.floor(fy)) - y0
            if not (0 <= x < W and 0 <= y < H - 2): continue
            for _k in range(3):
                if y < H - 2 and pm[y, x] != 0: y += 1
            if pm[y, x] == 0 and abs(pd[y, x] - ed) < 0.1:
                img[y, x, :3] = EYE
                if pm[y + 1, x] == 0 and (H >= 40 or cam.kind == 'o'): img[y + 1, x, :3] = EYE
    return img, depth, (x0, y0)

def bounds(cam, pos, r=1.0, h=2.6):
    pts = [np.array(pos) + [dx, dy, dz] for dx in (-r, r) for dy in (0, h) for dz in (-r, r)]
    P = np.array([cam.project(p)[:2] for p in pts])
    return (int(P[:, 0].min()) - 1, int(P[:, 1].min()) - 1, int(P[:, 0].max()) + 2, int(P[:, 1].max()) + 2)
