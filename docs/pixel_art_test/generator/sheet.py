import sys; sys.path.insert(0, '.')
import numpy as np, time
from PIL import Image, ImageDraw, ImageFont
from sprites import render, shadow_mask, hx
from poses import POSES
BG = hx('#5a9a73'); SH = hx('#43716a'); LINE = hx('#dfeee4')
S = 0.027; W, H = 80, 92; Z = 5
views = [(25, 'red', 'Far side (front 3/4)'), (-90, 'blue', 'Profile'), (200, 'blue', 'Near side (back 3/4)')]
names = list(POSES)
rows = []
t0 = time.time()
for name in names:
    row = []
    for yaw, team, _ in views:
        img, feet, tgt, J = render(POSES[name], yaw, team, W=W, H=H, s=S, target=(0, 0.92, 0.05))
        base = np.zeros((H, W, 3), np.uint8); base[:] = BG
        base[shadow_mask(J, tgt, W, H, S)] = SH
        a = img[..., 3:] / 255
        row.append((img[..., :3] * a + base * (1 - a)).astype(np.uint8))
    rows.append(row)
print('render', time.time() - t0)
# layout: poses as columns (8), views as rows (3)
gap = 4; lab_h = 0  # native px
cw, chh = W * Z, H * Z
LW = 300; TH = 120
sheet = Image.new('RGB', (LW + len(names) * (cw + gap * Z), TH + len(views) * (chh + gap * Z) + 40), hx('#1e1b2f'))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 34)
    small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Futura.ttc', 26)
except Exception:
    font = small = ImageFont.load_default()
for j, name in enumerate(names):
    d.text((LW + j * (cw + gap * Z) + cw / 2, TH - 50), name, fill=hx('#f4f1ea'), font=font, anchor='mm')
for i, (_, team, lab) in enumerate(views):
    y = TH + i * (chh + gap * Z)
    d.text((24, y + chh / 2), lab, fill=hx('#cfc8e6'), font=small, anchor='lm')
    for j in range(len(names)):
        x = LW + j * (cw + gap * Z)
        sheet.paste(Image.fromarray(rows[j][i]).resize((cw, chh), Image.NEAREST), (x, y))
sheet.save('art/pose_sheet.png')
small_prev = sheet.resize((sheet.width // 3, sheet.height // 3), Image.NEAREST); small_prev.save('art/pose_sheet_preview.png')
print(sheet.size)
