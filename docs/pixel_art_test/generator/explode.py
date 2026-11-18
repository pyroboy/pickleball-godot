import sys; sys.path.insert(0, '.')
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from sprites import build, Char, hx
from sprites2 import Cam, render_cam
from poses import POSES
GROUPS = [('head', ['head', 'hair', 'pony', 'visor']), ('torso', ['torso', 'neck']), ('shorts', ['shorts']),
          ('L upper arm', ['lup']), ('R upper arm', ['rup']), ('L forearm', ['lfo']), ('R forearm', ['rfo']),
          ('L hand', ['lhand']), ('R hand', ['rhand']), ('L thigh', ['lth']), ('R thigh', ['rth']),
          ('L shin', ['lsh']), ('R shin', ['rsh']), ('L shoe', ['lshoe']), ('R shoe', ['rshoe']),
          ('paddle (3D)', ['pface', 'handle', 'ball'])]
W, H, S, Z = 70, 84, 0.0278, 8
J = build(POSES['Forehand drive'], 200); ch = Char(J, 'blue')
cam = Cam.ortho(44, S, W, H, (0, 0.85, 0.05))
full, fdep, _ = render_cam(J, 'blue', cam, ss=4)
cards = []
for name, keys in GROUPS:
    img, dep, _ = render_cam(J, 'blue', cam, ss=4, only=keys)
    a = img[..., 3] > 0
    if not a.any(): continue
    ys, xs = np.where(a); cy, cx = ys.mean(), xs.mean()
    md = dep[a].mean()
    cards.append((name, img, dep, cx, cy, md))
# composite from cards (painter by card depth, far first)
comp = np.zeros_like(full)
for name, img, dep, cx, cy, md in sorted(cards, key=lambda c: -c[5]):
    m = img[..., 3] > 0; comp[m] = img[m]
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 30)
small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 20)
PW = 760
out = Image.new('RGB', (PW * 3 + 80, 940), hx('#1e1b2f'))
d = ImageDraw.Draw(out)
# panel 1 exploded
ox, oy = 20, 110
d.rectangle([ox, oy, ox + PW, oy + 800], fill=hx('#4470c4'))
ccx, ccy = W / 2, H / 2
for name, img, dep, cx, cy, md in sorted(cards, key=lambda c: -c[5]):
    a = img[..., 3] > 0; ys, xs = np.where(a)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop = img[y0:y1, x0:x1]
    k = 1.9
    px = ox + PW / 2 + ((cx - ccx) * k) * 6.5 - (x1 - x0) * 6.5 / 2
    py = oy + 400 + ((cy - ccy) * k) * 6.5 - (y1 - y0) * 6.5 / 2
    pil = Image.fromarray(crop, 'RGBA').resize((int((x1 - x0) * 6.5), int((y1 - y0) * 6.5)), Image.NEAREST)
    d.rectangle([px - 3, py - 3, px + pil.width + 3, py + pil.height + 3], outline=hx('#9fc0ff'))
    out.paste(pil, (int(px), int(py)), pil)
d.text((ox, 40), '1  Cards (one per bone)', fill=hx('#f4f1ea'), font=font)
d.text((ox, 78), '16 cards picked from the 202.5° column of the near-court sheet', fill=hx('#9c95b8'), font=small)
for i, (title, sub, im) in enumerate((('2  Assembled from cards', 'Drawn back-to-front by depth', comp),
                                      ('3  Single 3D render', 'Reference: what the cards must match', full))):
    x = 40 + PW * (i + 1) + 20 * i
    d.rectangle([x, oy, x + PW, oy + 800], fill=hx('#4470c4'))
    pil = Image.fromarray(im, 'RGBA').resize((W * 9, H * 9), Image.NEAREST)
    out.paste(pil, (int(x + (PW - pil.width) / 2), int(oy + (800 - pil.height) / 2)), pil)
    d.text((x, 40), title, fill=hx('#f4f1ea'), font=font); d.text((x, 78), sub, fill=hx('#9c95b8'), font=small)
out.save('art/exploded.png'); print(len(cards), out.size)
