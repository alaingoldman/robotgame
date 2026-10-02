"""python measure.py -> refs/zoom_front.png, zoom_side.png, zoom_back.png (5x zooms of the colour-
classified sheet with the leg-frame grid drawn on: red = x or z in cells, green = y in cells) and a
table of the silhouette extents every 0.25 cell (the numbers model.py was trimmed against).
Pixel notes in model.py like "(130,408)s" are positions in these zooms ("f" front, "s" side, "b" back)."""
import os

import numpy as np
from PIL import Image, ImageDraw

import refs

T = refs.TOP_PAD
K = 5
HIPY = 13 + T


def zooms():
    im, fg, wh, go, bl, gr = refs.sheet_masks()
    H, W = fg.shape
    seg = np.zeros((H, W, 3), np.uint8) + 255
    seg[fg] = (0, 0, 0)
    seg[wh] = (235, 235, 235)
    seg[go] = (212, 169, 58)
    seg[bl] = (47, 111, 191)
    seg[gr] = (128, 128, 128)

    def make(name, cx, sgn, x0, x1):
        img = Image.fromarray(seg[:, x0:x1]).resize(((x1 - x0) * K, H * K), Image.NEAREST)
        d = ImageDraw.Draw(img)
        for i in range(-40, 41):
            sx = (cx + sgn * i * 0.5 * refs.PX - x0) * K
            if 0 <= sx < img.width:
                d.line([(sx, 0), (sx, img.height)], fill=(255, 0, 0) if i % 2 == 0 else (255, 170, 170))
                if i % 2 == 0:
                    d.text((sx + 2, 2), "%g" % (i * 0.5), fill=(200, 0, 0))
        for i in range(-30, 6):
            sy = (HIPY - i * 0.5 * refs.PY) * K
            if 0 <= sy < img.height:
                d.line([(0, sy), (img.width, sy)], fill=(0, 160, 0) if i % 2 == 0 else (160, 220, 160))
                if i % 2 == 0:
                    d.text((2, sy + 2), "%g" % (i * 0.5), fill=(0, 120, 0))
        img.save(os.path.join(refs.HERE, "refs", "zoom_%s.png" % name))
    make("front", 111.5, -1, 55, 170)  # right leg, x = outward (screen left)
    make("side", 699.5, 1, 590, 780)   # z, negative = forward
    make("back", 1293, 1, 1235, 1355)  # right leg from behind, x = outward (screen right)


def runs(mask, y, x0, x1):
    r = mask[y, x0:x1]
    out, s = [], None
    for i, v in enumerate(r):
        if v and s is None:
            s = i
        if not v and s is not None:
            out.append((s + x0, i - 1 + x0))
            s = None
    if s is not None:
        out.append((s + x0, x1 - 1))
    return out


def table():
    im, fg, *_ = refs.sheet_masks()
    print("y(cells) | FRONT x (outer..inner) | BACK x (inner..outer) | SIDE z (front..back)")
    for k in range(4, -43, -1):
        Y = k * 0.25
        y = int(round(HIPY - Y * refs.PY))
        f = [(round((111.5 - a) / refs.PX, 2), round((111.5 - b) / refs.PX, 2)) for a, b in runs(fg, y, 40, 180)]
        b = [(round((a - 1293) / refs.PX, 2), round((c - 1293) / refs.PX, 2)) for a, c in runs(fg, y, 1235, 1360)]
        s = [(round((a - 699.5) / refs.PX, 2), round((c - 699.5) / refs.PX, 2)) for a, c in runs(fg, y, 585, 790)]
        print(Y, f, b, s)


if __name__ == "__main__":
    zooms()
    table()
