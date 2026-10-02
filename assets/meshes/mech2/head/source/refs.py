"""Reference sheets -> silhouette mask, colour labels, head ROI and the
pixel <-> cell mapping for each view.

Grid measured with a dark-grey line profile (see README):
  front 256.png: vertical lines x = 28, 56.5, 85, 113.5, 142  -> 28.5 px / cell
                 horizontal lines y = 9, 38, 68, 97.5, 127, 156.5 -> 29.4 px / cell
  side  257.png: x = 17, 45, 73.5, 102, 130.5, 159, 188 (28.5) ; y = 12, 41, 71, 100, 129.5, 159 (29.4)
  back  258.png: x = 6.5, 35.5, 64, 92.5, 120.5, 149.5, 178, 206.5 (28.5) ; y = 14, 43, 73, 101.5 (29.4)
(the screenshots are ~3% taller than wide, so x and y use separate scales).

Vertical datum: the gold crown peak sits 0.2 cells above one grid line in
all three views (front y=62 vs line 68, side y=65 vs 71, back y=66 vs 73).
That line is called G. Model Y (cells) = 2.75 - (y - yG) / 29.4, i.e. the
origin (neck base, top of the torso collar: front y~149, side y~152, back
y~154) is 2.75 cells below G.
Horizontal: front centre x=85 (crown peak / chevron tip), back centre
x=112.3 (gold cap), side: Z = (x - 115) / 28.5, x=115 = neck axis (centre of
the blue side strip / behind the gold crown back edge x=107).
"""
import numpy as np
from PIL import Image
from collections import deque
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SX, SY = 28.5, 29.4
Y0 = 2.75

VIEWS = {
    "front": dict(file="refs/front_256.png", yG=68.0, cx=85.0),
    "side": dict(file="refs/side_257.png", yG=71.0, cx=115.0),
    "back": dict(file="refs/back_258.png", yG=73.0, cx=112.3),
}

# class ids
BG, GOLD, WHITE, BLUE, GREY = 0, 1, 2, 3, 4
CLASS_RGB = {GOLD: (212, 169, 58), WHITE: (238, 238, 238), BLUE: (47, 111, 191), GREY: (120, 122, 128)}


def to_px(view, a, Y):
    """model coords -> reference pixel. a = screen-horizontal model coordinate:
    front: -X, back: +X, side: Z."""
    v = VIEWS[view]
    return v["cx"] + a * SX, v["yG"] + (Y0 - Y) * SY


def roi(view, h, w):
    yy, xx = np.mgrid[0:h, 0:w]
    if view == "front":
        # exclude the gold shoulder pads (x<31 / x>139 below y=95) and the torso
        # collar / blue chest below y=150 outside the chin
        r = (yy < 95) & (xx >= 20) & (xx <= 150)
        r |= (yy >= 95) & (yy < 150) & (xx >= 31) & (xx <= 139)
        r |= (yy >= 150) & (yy <= 166) & (xx >= 62) & (xx <= 108)
    elif view == "side":
        # exclude the white torso block (x 108-180, y>=136) and the gold shoulder + its outline (x>=171 below y=120)
        r = (yy < 120) | ((yy < 136) & (xx < 171))
        r |= (yy >= 136) & (yy <= 166) & (xx < 106)
    else:
        # exclude the gold shoulder pads (x<52 / x>172 below y=98, x<61 / x>164 below y=122) and the torso band y>=149
        r = (yy < 98) | ((yy < 122) & (xx >= 52) & (xx <= 172)) | ((yy < 149) & (xx >= 61) & (xx <= 164))
    return r


def load(view):
    v = VIEWS[view]
    a = np.asarray(Image.open(os.path.join(HERE, v["file"])).convert("RGB")).astype(int)
    h, w, _ = a.shape
    mx, mn = a.max(2), a.min(2)
    sat = mx - mn
    passable = (mn > 180) & (sat < 22)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if passable[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < h and 0 <= xx < w and not seen[yy, xx] and passable[yy, xx]:
                seen[yy, xx] = True
                q.append((yy, xx))
    sil = ~seen
    # drop specks (grid-crossing noise): connected components < 25 px
    comp = np.zeros((h, w), int)
    cid = 0
    for sy, sx in np.argwhere(sil):
        if comp[sy, sx]:
            continue
        cid += 1
        comp[sy, sx] = cid
        st = [(sy, sx)]
        pts = []
        while st:
            y, x = st.pop()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and sil[yy, xx] and not comp[yy, xx]:
                    comp[yy, xx] = cid
                    st.append((yy, xx))
        if len(pts) < 25:
            for y, x in pts:
                sil[y, x] = False
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    lab = np.zeros((h, w), int)
    gold = (R > 120) & (R - B > 60) & (G - B > 30)
    blue = (B - R > 35)
    dark = mx < 105
    g0 = (sat < 22) & (mn >= 100) & (mx < 150)
    grey = g0.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            grey &= np.roll(np.roll(g0, dy, 0), dx, 1)  # flat grey fill only (not outline AA)
    white = (sat < 25) & (mn >= 200)
    lab[gold] = GOLD
    lab[blue & ~gold] = BLUE
    lab[grey] = GREY
    lab[white] = WHITE
    unk = sil & ((lab == 0) | dark)
    lab[~sil] = BG
    lab[unk] = -1
    # outline / anti-alias pixels take the most common neighbouring fill class
    for _ in range(6):
        idx = np.argwhere(lab == -1)
        if len(idx) == 0:
            break
        new = lab.copy()
        for y, x in idx:
            nb = lab[max(0, y - 1):y + 2, max(0, x - 1):x + 2].ravel()
            nb = nb[nb > 0]
            if len(nb):
                new[y, x] = np.bincount(nb).argmax()
        lab = new
    lab[lab == -1] = WHITE
    r = roi(view, h, w)
    return dict(img=a, sil=sil & r, lab=np.where(r, lab, BG), roi=r, h=h, w=w)


def label_rgb(lab):
    out = np.full(lab.shape + (3,), 255, np.uint8)
    for k, c in CLASS_RGB.items():
        out[lab == k] = c
    return out


if __name__ == "__main__":
    tiles = []
    for vname in VIEWS:
        d = load(vname)
        im = label_rgb(d["lab"])
        im[~d["roi"]] = (255, 200, 200)
        tiles.append(np.concatenate([d["img"].astype(np.uint8), im], 1))
    H = max(t.shape[0] for t in tiles)
    W = sum(t.shape[1] for t in tiles)
    canvas = np.full((H, W, 3), 255, np.uint8)
    x = 0
    for t in tiles:
        canvas[:t.shape[0], x:x + t.shape[1]] = t
        x += t.shape[1]
    Image.fromarray(canvas).resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(HERE, "..", "ref_labels.png"))
    print("ok")
