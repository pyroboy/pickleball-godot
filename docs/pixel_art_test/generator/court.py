import sys; sys.path.insert(0, '.')
import numpy as np, time
from PIL import Image
import sprites
from sprites import render, hx, F, RIGHT, UP
from poses import POSES
W, H, S = 400, 225, 0.042
TGT = np.array([0, 0, 0.3])
ys, xs = np.mgrid[0:H, 0:W]
O = (TGT - F * 30)[None, None, :] + ((xs - W / 2 + 0.5) * S)[..., None] * RIGHT + ((H / 2 - ys - 0.5) * S)[..., None] * UP
t = -O[..., 1] / F[1]; P = O + t[..., None] * F
x, z = P[..., 0], P[..., 2]
rng = np.random.default_rng(3)
img = np.zeros((H, W, 3), np.uint8)
grass = np.array(hx('#4c8a5c')); grass2 = np.array(hx('#5a9a66')); grass3 = np.array(hx('#3f7a55'))
noise = rng.random((H, W))
img[:] = grass
img[noise > 0.93] = grass2; img[noise < 0.05] = grass3
apron = (np.abs(x) < 3.05 + 1.2) & (np.abs(z) < 6.7 + 1.6)
img[apron] = hx('#b9a27c')
court = (np.abs(x) < 3.05) & (np.abs(z) < 6.705)
img[court] = hx('#3c7f9e')
kitchen = court & (np.abs(z) < 2.13)
img[kitchen] = hx('#4f93b0')
lw = S * 0.6
lines = court & ((np.abs(np.abs(x) - 3.05) < lw) | (np.abs(np.abs(z) - 6.705) < lw) | (np.abs(np.abs(z) - 2.13) < lw) | ((np.abs(x) < lw) & (np.abs(z) > 2.13)))
img[lines] = hx('#f1f4f8')
depth = t.copy()
# blob shadows + players
players = [ # name, pose, yaw, team, pos
    ('Ready', 20, 'red', (-1.4, 0, -5.2)),
    ('Dink', -10, 'red', (1.3, 0, -2.6)),
    ('Forehand drive', 200, 'blue', (1.6, 0, 3.0)),
    ('Ready', 175, 'blue', (-1.5, 0, 5.4)),
]
def put_shadow(cx, cz, rx, rz):
    m = ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2 < 1
    img[m] = (img[m] * np.array([0.62, 0.66, 0.78])).astype(np.uint8)
for _, _, _, (px, _, pz) in players: put_shadow(px, pz, 0.35, 0.22)
ball = np.array([0.4, 1.35, 0.9])
put_shadow(ball[0], ball[2], 0.09, 0.06)
# net: ray hits plane z=0 before ground with y in [0, 0.91]
tn = (0 - O[..., 2]) / F[2]; Pn = O + tn[..., None] * F
netm = (tn < t) & (Pn[..., 1] > 0) & (Pn[..., 1] < 0.91) & (np.abs(Pn[..., 0]) < 3.35)
mesh = ((np.floor(Pn[..., 0] / 0.09) + np.floor(Pn[..., 1] / 0.09)) % 2 == 0)
img[netm] = hx('#2a2740'); img[netm & mesh] = hx('#3a3656')
img[netm & (Pn[..., 1] > 0.83)] = hx('#f1f4f8')
post = (tn < t) & (Pn[..., 1] > 0) & (Pn[..., 1] < 0.95) & (np.abs(np.abs(Pn[..., 0]) - 3.4) < 0.05)
img[post] = hx('#5b6392')
depth = np.where(netm | post, tn, depth)
# players sorted far->near (painter)
t0 = time.time()
for name, yaw, team, pos in sorted(players, key=lambda p: p[3][2]):
    pos = np.array(pos)
    spr, feet, tgt, J = render(POSES[name], yaw, team, W=W, H=H, s=S, ss=3, target=TGT - pos)
    m = spr[..., 3] > 0
    # net occludes far-side players' lower body? players are in front/behind net by z
    if pos[2] < 0:
        m = m & ~netm
    img[m] = spr[m, :3]
print('players', time.time() - t0)
# ball with pixel trail
def proj(p):
    d = p - (TGT - F * 30); return int(np.floor(d @ RIGHT / S + W / 2)), int(np.floor(H / 2 - d @ UP / S))
for i in range(7):
    q = ball + np.array([0.18, -0.06, 0.32]) * (i + 1) * 0.7
    bx, by = proj(q); a = 0.55 - i * 0.07
    if 0 <= bx < W and 0 <= by < H: img[by, bx] = (img[by, bx] * (1 - a) + np.array(hx('#fff6c8')) * a).astype(np.uint8)
bx, by = proj(ball)
for dx, dy, c in ((0, 0, '#d6f23c'), (1, 0, '#d6f23c'), (0, 1, '#a0c42b'), (1, 1, '#a0c42b'), (0, -1, '#f4ffa6')):
    img[by + dy, bx + dx] = hx(c)
# vignette
yy, xx = (ys - H / 2) / (H / 2), (xs - W / 2) / (W / 2)
v = np.clip(1 - 0.28 * (xx ** 2 + yy ** 2) ** 1.3, 0.55, 1)[..., None]
tint = np.array([0.92, 0.9, 1.0])
img = (img * (v * 1 + (1 - v) * tint * 0.6)).clip(0, 255).astype(np.uint8)
Image.fromarray(img).save('art/court_1x.png')
Image.fromarray(img).resize((W * 4, H * 4), Image.NEAREST).save('art/court_4x.png')
print('ok')
