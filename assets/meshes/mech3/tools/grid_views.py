"""Flipped + scaled (20 studs, front -Z) textured views with a 1-stud grid, for choosing cut planes."""
import sys, io, numpy as np
from PIL import Image, ImageDraw
from glbio import load_raw
from raster import render, view_matrix
D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
pos, uv, nrm, idx, jpg, mime = load_raw(D + r'\source\mech_raw.glb')
p = pos * [-1, 1, -1]
S = 20.0 / (p[:, 1].max() - p[:, 1].min()); p = p * S; p[:, 1] -= p[:, 1].min()
c = (p.max(0) + p.min(0)) / 2; p[:, 0] -= c[0]; p[:, 2] -= c[2]
print('bounds', p.min(0), p.max(0))
tex = np.asarray(Image.open(io.BytesIO(bytes(jpg))).convert('RGB')); H, W = tex.shape[:2]
fuv = uv[idx].mean(1)
fc = tex[np.clip(fuv[:, 1] * (H - 1), 0, H - 1).astype(int), np.clip(fuv[:, 0] * (W - 1), 0, W - 1).astype(int)]
size = 1000
if len(sys.argv) > 3:
    y0, y1 = map(float, sys.argv[3].split(':'))
    cy = p[idx].mean(1)[:, 1]; keep = (cy >= y0) & (cy <= y1); idx = idx[keep]; fc = fc[keep]
    used, inv = np.unique(idx.ravel(), return_inverse=True); p = p[used]; idx = inv.reshape(-1, 3)
else:
    p0 = p
out = []
for v in sys.argv[2].split(','):
    im = render([(p, idx, fc)], v, size, title=v)
    R = view_matrix(v); allv = p @ R.T; mn, mx = allv.min(0), allv.max(0)
    span = max(mx[0] - mn[0], mx[1] - mn[1]) * 1.08; cc = (mn + mx) / 2; sc = size / span
    d = ImageDraw.Draw(im)
    for y in np.arange(0, 20.01, 0.5 if len(sys.argv) > 3 else 1):
        sy = size / 2 - (y - cc[1]) * sc
        d.line([(0, sy), (size, sy)], fill=(255, 0, 0) if y % 1 == 0 else (255, 160, 160))
        d.text((2, sy - 10), f'{y:g}', fill=(200, 0, 0))
    for x in np.arange(-10, 10.01, 0.5 if len(sys.argv) > 3 else 1):
        sx = (x - cc[0]) * sc + size / 2
        d.line([(sx, 0), (sx, size)], fill=(0, 0, 255) if x % 1 == 0 else (170, 170, 255))
        d.text((sx + 2, size - 12), f'{x:g}', fill=(0, 0, 200))
    out.append(im)
im = Image.new('RGB', (size * len(out), size), 'white')
for i, x in enumerate(out): im.paste(x, (size * i, 0))
im.save(sys.argv[1])
