"""Crop each concept sheet into single square views (front/side/back for armour, side/threeq for weapons).
Views are found as x-runs of foreground columns separated by background gaps; each is cropped to its bbox,
padded to a square on the sheet's own background grey, resized to 1024."""
import json, os, numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = r'C:\Users\ICEMAN\Desktop\robotgame\assets'
SRC = ROOT + r'\gear_concepts'
OUT = ROOT + r'\gear3d\work\crops'


def views_of(fn, n):
    im = np.asarray(Image.open(fn).convert('RGB')).astype(int)
    H, W, _ = im.shape
    corners = np.concatenate([im[:20, :20].reshape(-1, 3), im[:20, -20:].reshape(-1, 3), im[-20:, :20].reshape(-1, 3), im[-20:, -20:].reshape(-1, 3)])
    bg = np.median(corners, 0)
    d = np.abs(im - bg).max(2)
    fg = d > 22
    fg = ndi.binary_opening(fg, np.ones((3, 3)))
    lab, k = ndi.label(fg)
    sizes = ndi.sum(fg, lab, range(1, k + 1))
    fg = np.isin(lab, np.where(sizes > 150)[0] + 1)
    if n == 2:   # weapons: big side view + smaller 3/4 view, may overlap in x -> use blobs
        cl = ndi.binary_fill_holes(ndi.binary_closing(fg, np.ones((15, 15))))
        lab, k = ndi.label(cl)
        sizes = ndi.sum(cl, lab, range(1, k + 1))
        order = np.argsort(-sizes)[:2]
        out = []
        for oi in order:
            m = lab == oi + 1
            ys, xs = np.where(m)
            y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
            crop = np.where(m[y0:y1 + 1, x0:x1 + 1, None], im[y0:y1 + 1, x0:x1 + 1], bg).astype(np.uint8)
            h, w = crop.shape[:2]; S = int(max(h, w) * 1.1)
            can = np.zeros((S, S, 3), np.uint8) + bg.astype(np.uint8)
            oy, ox = (S - h) // 2, (S - w) // 2
            can[oy:oy + h, ox:ox + w] = crop
            out.append(Image.fromarray(can).resize((1024, 1024), Image.LANCZOS))
        return out, len(out)
    col = fg.sum(0) > 0
    # runs
    runs = []; x = 0
    while x < W:
        if col[x]:
            s = x
            while x < W and col[x]: x += 1
            runs.append([s, x - 1])
        x += 1
    # merge runs separated by small gaps until n remain
    while len(runs) > n:
        gaps = [runs[i + 1][0] - runs[i][1] for i in range(len(runs) - 1)]
        i = int(np.argmin(gaps)); runs[i] = [runs[i][0], runs[i + 1][1]]; runs.pop(i + 1)
    out = []
    for x0, x1 in runs:
        ys = np.where(fg[:, x0:x1 + 1].any(1))[0]
        y0, y1 = ys.min(), ys.max()
        crop = im[y0:y1 + 1, x0:x1 + 1].astype(np.uint8)
        h, w = crop.shape[:2]; S = int(max(h, w) * 1.1)
        can = np.zeros((S, S, 3), np.uint8) + bg.astype(np.uint8)
        oy, ox = (S - h) // 2, (S - w) // 2
        can[oy:oy + h, ox:ox + w] = crop
        out.append(Image.fromarray(can).resize((1024, 1024), Image.LANCZOS))
    return out, len(runs)


if __name__ == '__main__':
    jobs = json.load(open(SRC + r'\jobs.json'))['jobs']
    for key, j in jobs.items():
        slot = j['slot']
        n = 2 if slot in ('melee', 'ranged') else 3
        names = ['side', 'threeq'] if n == 2 else ['front', 'side', 'back']
        ims, got = views_of(os.path.join(SRC, j['file']), n)
        if got != n:
            print('WARN', key, 'found', got, 'views')
        for nm, im in zip(names, ims):
            im.save(os.path.join(OUT, f'{key}_{nm}.png'))
    print('done', len(jobs))
