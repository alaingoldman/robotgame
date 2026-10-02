"""Plot horizontal cross-section outlines (x,z) at given heights; front (-Z) is drawn at the top."""
import sys, numpy as np
from PIL import Image, ImageDraw
from glbio import load_raw
pos, uv, nrm, idx, jpg, mime = load_raw(r'..\source\mech_raw.glb')
p = pos * [-1, 1, -1]; S = 20 / (p[:, 1].max() - p[:, 1].min()); p *= S; p[:, 1] -= p[:, 1].min()
c = (p.max(0) + p.min(0)) / 2; p[:, 0] -= c[0]; p[:, 2] -= c[2]
ys = [float(a) for a in sys.argv[2].split(',')]
sc = 90; W = int(11 * sc); Hh = int(5 * sc)
out = Image.new('RGB', (W, Hh * len(ys)), 'white'); d = ImageDraw.Draw(out)
T = p[idx]
for k, y in enumerate(ys):
    oy = k * Hh
    for gx in np.arange(-5.5, 5.51, 0.5):
        X = W / 2 + gx * sc; d.line([(X, oy), (X, oy + Hh)], fill=(150, 150, 255) if gx % 1 == 0 else (225, 225, 255))
        if gx % 1 == 0: d.text((X + 2, oy + Hh - 12), f'{gx:g}', fill=(0, 0, 200))
    for gz in np.arange(-2.5, 2.51, 0.5):
        Y = oy + Hh / 2 - gz * sc; d.line([(0, Y), (W, Y)], fill=(255, 150, 150) if gz % 1 == 0 else (255, 225, 225))
        if gz % 1 == 0: d.text((2, Y - 10), f'z{-gz:g}', fill=(200, 0, 0))
    d.text((W - 80, oy + 4), f'y={y}', fill=(0, 0, 0))
    s = T[:, :, 1] - y
    for tri, sv in zip(T, s):
        pts = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            if (sv[a] > 0) != (sv[b] > 0):
                t = sv[a] / (sv[a] - sv[b]); q = tri[a] + t * (tri[b] - tri[a]); pts.append(q)
        if len(pts) == 2:
            d.line([(W / 2 + q[0] * sc, oy + Hh / 2 + q[2] * sc) for q in pts], fill=(0, 0, 0), width=2)
out.save(sys.argv[1])
