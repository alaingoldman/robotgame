"""Close-ups of joint cuts on a GLB (textured, per-pixel), e.g. both elbows from front, outer side and below.
usage: python elbow_closeup.py file.glb out.png [joint]  joint in elbow|shoulder|wrist|knee|ankle|neck|waist|wing"""
import sys, numpy as np
from PIL import Image, ImageDraw
from tex_closeup import load, rot, render

J = {'elbow': (3.39, 13.85, 0.4, 1.5), 'shoulder': (2.6, 15.8, 0.1, 1.8), 'wrist': (4.4, 10.85, -0.6, 1.3),
     'knee': (1.52, 7.2, -0.1, 1.8), 'ankle': (1.85, 1.6, 0.4, 1.6), 'neck': (0.0, 17.45, -0.1, 1.6),
     'waist': (0.0, 12.4, 0.0, 2.2), 'wing': (3.0, 16.8, 1.0, 2.0)}
fn, out = sys.argv[1], sys.argv[2]
joints = sys.argv[3].split(',') if len(sys.argv) > 3 else ['elbow']
parts, texs = load(fn)
S = 420
tiles = []
for j in joints:
    x, y, z, h = J[j]
    for sx, side in ((1, 'R'), (-1, 'L')):
        if x == 0 and sx < 0:
            continue
        c = np.array([sx * x, y, z])
        for name, R in (('front', rot(np.pi, 0.05)), ('outer side', rot(-sx * np.pi / 2, 0.05)), ('below', rot(np.pi - sx * 0.6, -0.75)), ('back', rot(0, 0.1))):
            im = render(parts, texs, R, c, h, S, metal=len(texs) > 1)
            ImageDraw.Draw(im).text((6, 6), f'{j} {side} {name}', fill=(0, 0, 0))
            tiles.append(im)
cols = 4
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new('RGB', (S * cols, S * rows), 'white')
for i, t in enumerate(tiles):
    sheet.paste(t, (S * (i % cols), S * (i // cols)))
sheet.save(out)
