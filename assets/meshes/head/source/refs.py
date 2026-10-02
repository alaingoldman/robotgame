"""Reference views (the owner's head crops of refs/full_body_sheet.png) and
their pixel <-> head-space mapping.

Head space = HeadBuilder's frame in grid cells: origin at the neck base
(leg space (0, 31.2, -1.5)), +Y (h) up, the face toward -Z, +X = mech right.
1 cell = 0.816 studs at Scale 1.7.

The crops are 2.08x zooms of the full-body sheet (template-matched: crop px
-> sheet px = off + c * 20 / 41.8..42); grid pitch in the crops ~41.6 px.
"""
import os
from collections import deque

import numpy as np
from PIL import Image

IMG = r"C:\Users\ICEMAN\AppData\Local\Temp\claude\C--Users-ICEMAN-Desktop-testroblox\c56f87ec-4190-4bf0-906e-1c31f885fd54\images"
HERE = os.path.dirname(os.path.abspath(__file__))
REF_DIR = os.path.join(HERE, "refs")  # copies of the crops (so the pipeline doesn't depend on the temp folder)
P = 41.6  # px per cell in the crops

# view -> (file, function head-space (x,h,z) -> (cx, cy, depth)); smaller depth = nearer the viewer
VIEWS = {
    # FRONT: looking at the face (+Z), mech right (+x) on screen left
    "front": ("235.png", lambda x, h, z: (140.5 - x * P, 180 - (h - 2.56) * P, z)),  # h anchored so the spike tip matches SIDE/BACK (6.52)
    # SIDE: from the mech's left (-X), the face to screen left
    "side": ("236.png", lambda x, h, z: (180 + (z - 0.286) * P, 200 - (h - 2.513) * P, x)),
    # BACK: from behind (-Z), mech right on screen right
    "back": ("237.png", lambda x, h, z: (125.5 + x * P, 120 - (h - 4.468) * P, -z)),
}


def ref_path(view):
    f = VIEWS[view][0]
    local = os.path.join(REF_DIR, f)
    return local if os.path.exists(local) else os.path.join(IMG, f)


def load(view):
    return np.asarray(Image.open(ref_path(view)).convert("RGB")).astype(int)


def classify(im):
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    line = im.max(2) < 85
    fill = ((b - r) > 10) & ~line
    return line, fill


def label(mask):
    H, W = mask.shape
    lab = np.zeros((H, W), int)
    n = 0
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not lab[y, x]:
                n += 1
                lab[y, x] = n
                q = deque([(y, x)])
                while q:
                    cy, cx = q.popleft()
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            q.append((ny, nx))
    return lab, n


def dilate(m, r):
    out = m.copy()
    H, W = m.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            sh = np.zeros_like(m)
            ys = slice(max(dy, 0), H + min(dy, 0))
            yd = slice(max(-dy, 0), H + min(-dy, 0))
            xs = slice(max(dx, 0), W + min(dx, 0))
            xd = slice(max(-dx, 0), W + min(-dx, 0))
            sh[ys, xs] = m[yd, xd]
            out |= sh
    return out


def erode(m, r):
    return ~dilate(~m, r)


# fill components that belong to OTHER parts (torso / shoulder pad / chest):
# seeds in crop px. Everything else that is filled is the head assembly.
IGNORE_SEEDS = {
    "front": [(5, 300), (270, 300), (140, 335), (5, 240), (272, 240)],
    "side": [(225, 150), (80, 336), (150, 260), (250, 420), (20, 420), (60, 360), (300, 300), (340, 400), (200, 400), (215, 230), (215, 290),
             (330, 330), (300, 200), (350, 420), (230, 360), (275, 410)],
    "back": [(125, 250), (5, 255), (245, 255)],
}


def masks(view):
    """-> (head_mask, ignore_mask) booleans in crop px."""
    im = load(view)
    line, fill = classify(im)
    lab, n = label(fill)
    ign_ids = set()
    for (x, y) in IGNORE_SEEDS[view]:
        if lab[y, x]:
            ign_ids.add(lab[y, x])
    ign = np.isin(lab, list(ign_ids)) if ign_ids else np.zeros_like(fill)
    sizes = np.bincount(lab.ravel())
    keep = [i for i in range(1, n + 1) if i not in ign_ids and sizes[i] >= 6]
    head = np.isin(lab, keep)
    # the outline strokes: a stroke pixel belongs to whichever region is nearer
    dh = dilate(head, 4)
    di = dilate(ign, 4)
    head = head | (line & dh & ~(di & ~dilate(head, 2)))
    head = erode(dilate(head, 2), 2)
    ign = (ign | (line & di)) & ~head
    # SIDE: the shoulder pad hides the head's lower half; beyond its front
    # edge / below the throat only the pad and torso show -> out of the ROI
    if view == "side":
        H, W = head.shape
        yy, xx = np.mgrid[0:H, 0:W]
        out = (xx > 262) | (yy > 336) | ((yy > 300) & (xx > 95))
        ign = ign | out
        head = head & ~out
    return head, ign, lab
