"""Reference sheet 255.png (FRONT | SIDE | BACK of the legs) -> masks.

Grid (measured from the grid-line minima of the empty area x 400-580 / y 0-320):
  columns at x = 351, 379.5, 408, 436, 464.5, 493, 521.5, 550, 578.5 -> PX = 28.44 px per cell (horizontal)
  rows    at y = 23, 52, 82, 111, 140.5, 169, 198.5, 227.5, 256.5, 285, 314.5, 343 -> PY = 29.08 px per cell (vertical)
  (the screenshot is slightly anisotropic, so each axis uses its own pitch)
Ground = the major grid row y = 314.5 (all soles stand on it).
254.png is the same pixels as 255.png shifted: 254(x, y) == 255(x + 560, y - 7) (template match, corr 1.00),
i.e. it only adds 7 rows above the top of 255 (the top of the hip ball / thigh spike).
1 cell = 0.816 studs (mech Scale 1.7, cell 0.48 design units).
"""
import os
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PX, PY = 28.44, 29.08
GROUND_Y = 314.5
CELL = 0.816
TOP_PAD = 7  # rows borrowed from 254.png above 255's top


def load_sheet():
    """255.png with 7 extra rows on top from 254.png (side view area only; elsewhere background)."""
    a = np.asarray(Image.open(os.path.join(HERE, "refs", "255.png")).convert("RGB")).astype(int)
    b = np.asarray(Image.open(os.path.join(HERE, "refs", "254.png")).convert("RGB")).astype(int)
    H, W, _ = a.shape
    out = np.full((H + TOP_PAD, W, 3), 228, int)
    out[TOP_PAD:] = a
    out[:TOP_PAD, 560:560 + b.shape[1]] = b[:TOP_PAD]
    # the 7 rows above FRONT/BACK are unknown: copy row 0 upward for the grey balls (cut by the frame) - see masks()
    return out


def segment(im):
    """-> fg, white, gold, blue, grey (bool masks). fg = everything not reachable from the
    image border through light, unsaturated (background / grid) pixels; the drawing's ink
    outlines stop the flood, so white plates (233) separate from the background (228)."""
    H, W, _ = im.shape
    g = im.mean(2)
    sat = im.max(2) - im.min(2)
    passable = (g > 160) & (sat < 20)
    bg = np.zeros((H, W), bool)
    q = deque()
    seeds = [(y, 0) for y in range(H)] + [(y, W - 1) for y in range(H)] + [(H - 1, x) for x in range(W)] + [(0, x) for x in range(W)]
    for y, x in seeds:
        if passable[y, x] and not bg[y, x]:
            bg[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < H and 0 <= nx < W and passable[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    fg = ~bg
    fg[int(GROUND_Y) + TOP_PAD + 2:] = False  # labels below the ground
    r, b = im[..., 0], im[..., 2]
    blue = fg & (b - r > 40)
    gold = fg & (r - b > 30) & ~blue
    grey = fg & (sat < 18) & (g > 85) & (g < 160)
    white = fg & (sat < 18) & (g >= 160)
    return fg, white, gold, blue, grey


_cache = {}


def sheet_masks():
    if "m" not in _cache:
        im = load_sheet()
        _cache["m"] = (im,) + segment(im)
    return _cache["m"]
