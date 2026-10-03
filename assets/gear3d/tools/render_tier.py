"""Turnaround renders of an assembled tier (as worn): front, side (from the right), back, 3/4 front-right, 3/4
front-left, plus a part-coded front view (R parts warm, L parts cool) to check cuts and mirroring."""
import os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
from rend import render, strip
from dec import decimate

ROOT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d'
OUT = ROOT + r'\renders'
os.makedirs(OUT, exist_ok=True)
COL = {'Head': (220, 220, 60), 'Torso_Upper': (90, 160, 230), 'Torso_Lower': (60, 90, 170),
       'Upper': (230, 80, 60), 'Lower': (240, 160, 60), 'Hand': (200, 60, 160), 'Foot': (200, 60, 160)}


def code_col(nm):
    if nm in COL:
        return COL[nm]
    c = np.array(COL[nm.split('_')[1]], float)
    return tuple(c * (0.55 if ('L_' in nm[:5]) else 1.0))


def preview_parts(nodes, mats, tris=3500):
    out = []
    for nm, p, n, t, ix, mi in nodes:
        pp, nn, tt, ff = decimate(p, n, t, ix, tris)
        out.append((nm, pp, ff, tt, np.asarray(mats[mi]['base'].convert('RGB').resize((512, 512)))))
    return out


def render_tier(T, nodes, mats, size=420):
    pv = preview_parts(nodes, mats)
    tex = [(p, f, t, im) for nm, p, f, t, im in pv]
    coded = [(p, f, None, code_col(nm)) for nm, p, f, t, im in pv]
    allp = np.vstack([p for _, p, *_ in pv])
    ims = [render(tex, v, size, title='T%02d %s' % (T, v)) for v in ('front', 'side', 'back', 'threeq', 'threeq_l')]
    ims.append(render(coded, 'front', size, title='parts (L darker)'))
    strip(ims, os.path.join(OUT, 'T%02d_turnaround.png' % T))
