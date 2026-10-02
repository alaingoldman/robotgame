"""Crop FRONT / SIDE / BACK out of source/sheet.png into square white-background PNGs (same scale, same feet level)."""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3\source'
im = np.asarray(Image.open(D + r'\sheet.png').convert('RGB')).astype(int)
lum = im.mean(2); sat = im.max(2) - im.min(2)
fg = (lum < 118) | (sat > 25)                      # grid lines (~179) and guide line (~138) are excluded
fg = ndi.binary_closing(fg, np.ones((5, 5)))
fg = ndi.binary_fill_holes(fg)
lab, n = ndi.label(fg)
sizes = ndi.sum(fg, lab, range(1, n + 1))
keep = np.isin(lab, np.where(sizes > 400)[0] + 1)
mask = ndi.binary_fill_holes(keep)
# columns ranges of the 3 views
VIEWS = {'front': (90, 830), 'side': (840, 1230), 'back': (1240, 1960)}
boxes = {}
for k, (a, b) in VIEWS.items():
    m = mask[:, a:b]
    ys, xs = np.where(m)
    boxes[k] = (a + xs.min(), ys.min(), a + xs.max(), ys.max())
    print(k, boxes[k])
top = min(b[1] for b in boxes.values()); bot = max(b[3] for b in boxes.values())
H = bot - top
S = int(H * 1.12)
OUT = 1024
for k, (x0, y0, x1, y1) in boxes.items():
    cx = (x0 + x1) // 2
    canvas = np.full((S, S, 3), 255, np.uint8)
    pad_top = (S - H) // 2
    for yy in range(top, bot + 1):
        row = mask[yy, x0:x1 + 1]
        dst = yy - top + pad_top
        xx0 = S // 2 - (cx - x0)
        canvas[dst, xx0:xx0 + (x1 - x0 + 1)][row] = im[yy, x0:x1 + 1][row]
    Image.fromarray(canvas).resize((OUT, OUT), Image.LANCZOS).save(D + rf'\view_{k}.png')
print('scale px/sheet', OUT / S, 'height px', H)
