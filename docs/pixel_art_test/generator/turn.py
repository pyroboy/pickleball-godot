import sys; sys.path.insert(0, '.')
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from sprites import render, shadow_mask, hx
from poses import POSES
BG = hx('#5a9a73'); SH = hx('#43716a')
S = 0.027; W, H = 56, 76; Z = 6
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 28)
cells = []
for k in range(16):
    yaw = k * 22.5
    img, feet, tgt, J = render(POSES['Ready'], yaw, 'blue', W=W, H=H, s=S, target=(0, 0.86, 0.05))
    base = np.zeros((H, W, 3), np.uint8); base[:] = BG
    base[shadow_mask(J, tgt, W, H, S)] = SH
    a = img[..., 3:] / 255
    cells.append((img[..., :3] * a + base * (1 - a)).astype(np.uint8))
cw, chh, g = W * Z, H * Z, 18
out = Image.new('RGB', (8 * cw + 9 * g, 2 * (chh + 50) + 3 * g), hx('#1e1b2f'))
d = ImageDraw.Draw(out)
for k, c in enumerate(cells):
    x = g + (k % 8) * (cw + g); y = g + (k // 8) * (chh + 50 + g)
    out.paste(Image.fromarray(c).resize((cw, chh), Image.NEAREST), (x, y))
    d.text((x + cw / 2, y + chh + 26), '%d: %.1f°' % (k, k * 22.5), fill=hx('#cfc8e6'), font=font, anchor='mm')
out.save('art/turnaround_16.png'); print(out.size)
# close-up of one cell
img, feet, tgt, J = render(POSES['Forehand drive'], 200, 'blue', W=80, H=92, s=S, target=(0, 0.92, 0.05))
base = np.zeros((92, 80, 3), np.uint8); base[:] = BG; base[shadow_mask(J, tgt, 80, 92, S)] = SH
a = img[..., 3:] / 255
Image.fromarray((img[..., :3] * a + base * (1 - a)).astype(np.uint8)).resize((80 * 10, 92 * 10), Image.NEAREST).save('art/closeup.png')
