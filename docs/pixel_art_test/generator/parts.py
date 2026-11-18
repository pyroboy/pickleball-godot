import sys; sys.path.insert(0, '.')
import numpy as np, time
from PIL import Image, ImageDraw, ImageFont
from sprites import build, Char, hx
from sprites2 import Cam, render_cam
REST = dict(pelvis=0.92, lean=0, twist=0, r_up=(0, 10), r_fo=(0, 6), l_up=(0, 10), l_fo=(0, 6),
            r_th=(0, 4), r_sh=(0, 2), l_th=(0, 4), l_sh=(0, 2), r_foot=0, l_foot=0, pad=(0, 8), pad_n=(0, 0, 1))
GRIP = dict(REST, r_fo=(0, 6), pad=(180, 0))
PARTS = [  # label, keys, centre fn, pose
    ('Head', ['head', 'hair', 'pony', 'visor'], lambda J, c: J['head'], REST),
    ('Torso', ['torso', 'neck'], lambda J, c: J['pelvis'] + J['Rt'] @ [0, 0.32, 0], REST),
    ('Shorts', ['shorts'], lambda J, c: J['pelvis'] + [0, 0.03, 0], REST),
    ('Upper arm', ['rup'], lambda J, c: (J['rsh'] + J['rel']) / 2, REST),
    ('Forearm', ['rfo'], lambda J, c: (J['rel'] + J['rwr']) / 2, REST),
    ('Hand', ['rhand'], lambda J, c: c.hand_r, REST),
    ('Thigh', ['rth'], lambda J, c: (J['rhp'] + J['rkn']) / 2, REST),
    ('Shin', ['rsh'], lambda J, c: (J['rkn'] + J['ran']) / 2, REST),
    ('Shoe', ['rshoe'], lambda J, c: J['ran'] + [0, -0.04, 0], REST),
    ('Paddle (3D)', ['pface', 'handle'], lambda J, c: c.pad_c, GRIP),
]
TIERS = [('near', 44, 0.0278, 30, 30), ('far', 20, 0.057, 16, 16)]
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 30)
small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 22)
for team in ('blue',):
    for tier, elev, s, CW, CH in TIERS:
        t0 = time.time()
        grid = []
        for label, keys, cfn, pose in PARTS:
            row = []
            for k in range(16):
                yaw = k * 22.5
                J = build(pose, yaw)
                c = Char(J, team)
                ctr = cfn(J, c)
                cam = Cam.ortho(elev, s, CW, CH, ctr)
                img, _, _ = render_cam(J, team, cam, ss=4, only=keys)
                row.append(img)
            grid.append(row)
        print(tier, time.time() - t0)
        # crop each row to the union bbox
        Z = 7
        rows_img = []
        for row in grid:
            a = np.stack([r[..., 3] for r in row]).max(0)
            ys, xs = np.where(a > 0)
            y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            rows_img.append([r[y0:y1, x0:x1] for r in row])
        cellw = max(r[0].shape[1] for r in rows_img) * Z + 26
        LW, TOP = 260, 120
        heights = [r[0].shape[0] * Z + 26 for r in rows_img]
        sheet = Image.new('RGB', (LW + 16 * cellw + 20, TOP + sum(heights) + 20), hx('#1e1b2f'))
        d = ImageDraw.Draw(sheet)
        d.text((24, 30), '%s-court cards  -  %d deg view  -  %.3f m per pixel' % (tier.capitalize(), elev, s), fill=hx('#f4f1ea'), font=font)
        for k in range(16):
            d.text((LW + k * cellw + cellw / 2, TOP - 22), '%g°' % (k * 22.5), fill=hx('#9c95b8'), font=small, anchor='mm')
        y = TOP
        for (label, *_), row, hgt in zip(PARTS, rows_img, heights):
            d.text((24, y + hgt / 2), label, fill=hx('#cfc8e6'), font=small, anchor='lm')
            for k, im in enumerate(row):
                x = LW + k * cellw
                d.rectangle([x + 3, y + 3, x + cellw - 3, y + hgt - 3], fill=hx('#4470c4'))
                pil = Image.fromarray(im, 'RGBA').resize((im.shape[1] * Z, im.shape[0] * Z), Image.NEAREST)
                sheet.paste(pil, (int(x + (cellw - pil.width) / 2), int(y + (hgt - pil.height) / 2)), pil)
            y += hgt
        sheet.save('art/parts_%s_%s.png' % (tier, team)); print(sheet.size)
