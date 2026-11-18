"""Bake pixel card atlases for the Godot prototype: 9 parts x 16 yaw cells, per team."""
import sys, json, os; sys.path.insert(0, '.')
import numpy as np
from PIL import Image
import sprites
from sprites import build, Char
# Match the game's skeleton (player_body_dimensions.gd, right_arm.gd) so cards are not stretched.
sprites.L_UP, sprites.L_FORE, sprites.L_THIGH, sprites.L_SHIN = 0.35, 0.35, 0.43, 0.41
sprites.HEAD_SCALE = 0.8
# Higher-contrast card palettes: the court is mid blue, so shirts go lighter/cleaner,
# shorts and hair darker, shadows deeper (hue-shifted, never black).
sprites.PAL.update({
    'skin':  ['#ffe6d0', '#f7b48f', '#cf7a6c', '#8c4a5e'],
    'hair':  ['#9a77a3', '#5a3d6b', '#33213f', '#1e1229'],
    'blue':  ['#d6f1ff', '#7cc8ff', '#2f7fe0', '#1d3c8f'],
    'red':   ['#ffd0c4', '#ff6d5e', '#cf2f4a', '#7d1d40'],
    'white': ['#ffffff', '#f4f5fb', '#b9b8d8', '#7d78a8'],
    'navy':  ['#4c5285', '#2a2e5c', '#1b1c40', '#100f2a'],
})
from sprites2 import Cam, render_cam
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
S = 0.028; ELEV = 44; CW = CH = 40
REST = dict(pelvis=0.92, lean=0, twist=0, r_up=(0, 0), r_fo=(0, 0), l_up=(0, 0), l_fo=(0, 0),
            r_th=(0, 0), r_sh=(0, 0), l_th=(0, 0), l_sh=(0, 0), r_foot=0, l_foot=0, pad=(0, 8), pad_n=(0, 0, 1))
# name, prim keys, anchor fn, end fn (None = rigid), anchor pixel
PARTS = [
    ('head', ['head', 'hair', 'pony', 'visor'], lambda J, c: J['head'], None, (20, 20)),
    ('torso', ['torso', 'neck'], lambda J, c: J['pelvis'] + J['Rt'] @ [0, 0.28, 0], None, (20, 20)),
    ('shorts', ['shorts'], lambda J, c: J['pelvis'] + [0, 0.03, 0], None, (20, 20)),
    ('upper_arm', ['rup'], lambda J, c: J['rsh'], lambda J, c: J['rel'], (20, 8)),
    ('forearm', ['rfo'], lambda J, c: J['rel'], lambda J, c: J['rwr'], (20, 8)),
    ('hand', ['rhand'], lambda J, c: J['rwr'], lambda J, c: c.hand_r, (20, 14)),
    ('thigh', ['rth'], lambda J, c: J['rhp'], lambda J, c: J['rkn'], (20, 8)),
    ('shin', ['rsh'], lambda J, c: J['rkn'], lambda J, c: J['ran'], (20, 8)),
    ('shoe', ['rshoe'], lambda J, c: J['ran'], None, (20, 14)),
]
meta = {'cell': [CW, CH], 'cols': 16, 'rows': len(PARTS), 'meters_per_texel': S, 'elevation_deg': ELEV, 'parts': {}}
for team in ('blue', 'red'):
    atlas = np.zeros((CH * len(PARTS), CW * 16, 4), np.uint8)
    for r, (name, keys, afn, bfn, (ax, ay)) in enumerate(PARTS):
        for k in range(16):
            J = build(REST, k * 22.5); c = Char(J, team)
            A = afn(J, c)
            # place A at pixel (ax, ay): shift camera target by the screen offset
            cam0 = Cam.ortho(ELEV, S, CW, CH, A)
            target = A + cam0.right * (CW / 2 - ax) * S - cam0.up * (CH / 2 - ay) * S
            cam = Cam.ortho(ELEV, S, CW, CH, target)
            img, _, _ = render_cam(J, team, cam, ss=4, only=keys)
            atlas[r * CH:(r + 1) * CH, k * CW:(k + 1) * CW] = img
            if team == 'blue' and k == 0:
                ent = {'row': r, 'anchor': [ax, ay]}
                if bfn is not None:
                    bx, by, _ = cam.project(bfn(J, c)); ent['end'] = [round(float(bx), 2), round(float(by), 2)]
                meta['parts'][name] = ent
    Image.fromarray(atlas, 'RGBA').save(os.path.join(OUT, 'cards_%s.png' % team))
json.dump(meta, open(os.path.join(OUT, 'cards_meta.json'), 'w'), indent=1)
print(json.dumps(meta['parts']))
