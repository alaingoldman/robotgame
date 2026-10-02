"""Orthographic flat-shaded rasterizer (numpy) that draws the legs straight into the sheet's pixel
frame (refs.py), so the silhouettes / colour regions can be compared with 255.png pixel for pixel."""
import math

import numpy as np
from PIL import Image, ImageDraw

import refs

COLOURS = {  # flat colours (RGB) of the four meshes
    "White": (236, 236, 232),
    "Gold": (212, 169, 58),
    "Blue": (47, 111, 191),
    "Joint": (128, 128, 128),
}
T = refs.TOP_PAD
HIP_X_CELLS = (179.5 - 111.5) / refs.PX  # 2.391 cells: half the hip spacing (front balls 111.5 / 247.5 px)
HIP_Y_PX = 13 + T  # hip centre row in the padded sheet

# view -> (fn (X, Y, Z) mech cells -> (sx, sy, depth), sheet x-window); smaller depth = nearer
VIEWS = {
    "front": (lambda X, Y, Z: (179.5 - X * refs.PX, HIP_Y_PX - Y * refs.PY, Z), (30, 330)),
    "side": (lambda X, Y, Z: (699.5 + Z * refs.PX, HIP_Y_PX - Y * refs.PY, X), (575, 795)),
    "back": (lambda X, Y, Z: (1225 + X * refs.PX, HIP_Y_PX - Y * refs.PY, -Z), (1080, 1370)),
}
LIGHTS = {"front": (-0.25, 0.35, -0.9), "side": (-0.9, 0.35, -0.25), "back": (0.25, 0.35, 0.9)}


def raster(items, view, shape, ss=3, light=None, fn=None, ink=False):
    """items: [(V (n,3) mech cells, F (m,3), colour name)] -> rgb (H,W,3) float, mask, colour-id map."""
    fn = fn or VIEWS[view][0]
    H, W = shape
    Hs, Ws = H * ss, W * ss
    zbuf = np.full((Hs, Ws), np.inf)
    col = np.zeros((Hs, Ws, 3))
    cid = -np.ones((Hs, Ws), int)
    nbuf = np.zeros((Hs, Ws, 3))
    L = np.array(light or LIGHTS.get(view, (-0.35, 0.55, -0.75)), float)
    L /= np.linalg.norm(L)
    names = list(COLOURS)
    for V, F, cname in items:
        if len(F) == 0:
            continue
        P = np.array([fn(*p) for p in V], float)
        P[:, :2] *= ss
        nrm = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        nrm /= np.linalg.norm(nrm, axis=1)[:, None] + 1e-12
        base = np.array(COLOURS[cname], float)
        ci = names.index(cname)
        for fi, (a, b, c) in enumerate(F):
            A, B, C = P[a], P[b], P[c]
            x0 = int(max(0, np.floor(min(A[0], B[0], C[0]))))
            x1 = int(min(Ws - 1, np.ceil(max(A[0], B[0], C[0]))))
            y0 = int(max(0, np.floor(min(A[1], B[1], C[1]))))
            y1 = int(min(Hs - 1, np.ceil(max(A[1], B[1], C[1]))))
            if x1 < x0 or y1 < y0:
                continue
            det = (B[1] - C[1]) * (A[0] - C[0]) + (C[0] - B[0]) * (A[1] - C[1])
            if abs(det) < 1e-12:
                continue
            ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            px, py = xs + 0.5, ys + 0.5
            l1 = ((B[1] - C[1]) * (px - C[0]) + (C[0] - B[0]) * (py - C[1])) / det
            l2 = ((C[1] - A[1]) * (px - C[0]) + (A[0] - C[0]) * (py - C[1])) / det
            l3 = 1 - l1 - l2
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            if not inside.any():
                continue
            d = l1 * A[2] + l2 * B[2] + l3 * C[2]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            upd = inside & (d < sub)
            if not upd.any():
                continue
            sub[upd] = d[upd]
            n = nrm[fi]
            lam = 0.7 + 0.3 * max(0.0, float(np.dot(n, L))) + 0.04 * float(n[1])
            col[y0:y1 + 1, x0:x1 + 1][upd] = np.clip(base * lam, 0, 255)
            cid[y0:y1 + 1, x0:x1 + 1][upd] = ci
            nbuf[y0:y1 + 1, x0:x1 + 1][upd] = n
    mask = np.isfinite(zbuf)
    bg = np.array([228, 228, 228], float)
    img = np.where(mask[..., None], col, bg)
    if ink:  # thin dark lines at silhouettes / colour changes / creases, like the drawing
        e = np.zeros_like(mask)
        for dy, dx in ((0, 1), (1, 0)):
            a = (slice(0, Hs - dy), slice(0, Ws - dx))
            b = (slice(dy, Hs), slice(dx, Ws))
            both = mask[a] & mask[b]
            k = (mask[a] != mask[b]) | (both & (cid[a] != cid[b])) | (both & ((nbuf[a] * nbuf[b]).sum(-1) < 0.9))
            e[a] |= k
            e[b] |= k
        img[e] = (30, 32, 36)
    img = img.reshape(H, ss, W, ss, 3).mean((1, 3))
    m = mask.reshape(H, ss, W, ss).mean((1, 3)) >= 0.5
    # majority colour id per pixel
    c = cid.reshape(H, ss, W, ss).transpose(0, 2, 1, 3).reshape(H, W, ss * ss)
    cmap = -np.ones((H, W), int)
    best = np.zeros((H, W), int)
    for k in range(len(names)):
        cnt = (c == k).sum(-1)
        upd = cnt > best
        cmap[upd] = k
        best[upd] = cnt[upd]
    cmap[~m] = -1
    return img, m, cmap


def ref_masks():
    im, fg, white, gold, blue, grey = refs.sheet_masks()
    H, W = fg.shape
    cref = -np.ones((H, W), int)
    for k, mk in enumerate((white, gold, blue, grey)):
        cref[mk] = k
    ign = np.zeros((H, W), bool)
    # FRONT / BACK: the rows above 255.png's top edge are unknown there (the hip balls are cut off)
    ign[:T, :560] = True
    ign[:T, 560 + 271:] = True
    # SIDE: the small white spike above the thigh plate (z -1.9..-0.8, y > 0.3: pelvis/skirt piece,
    # not part of the leg) - 5x zoom (300..430, 0..70)s
    ign[:T + 8, 640:680] = True
    return im, fg, cref, ign


def evaluate(items, views=("front", "side", "back")):
    im, fg, cref, ign = ref_masks()
    H, W = fg.shape
    out = {}
    for v in views:
        x0, x1 = VIEWS[v][1]
        img, m, cmap = raster(items, v, (H, W))
        roi = np.zeros((H, W), bool)
        roi[:, x0:x1] = True
        roi &= ~ign
        r = fg & roi
        mm = m & roi
        iou = (r & mm).sum() / max(1, (r | mm).sum())
        cols = {}
        for k, name in enumerate(COLOURS):
            a = (cref == k) & roi
            b = (cmap == k) & roi
            cols[name] = (a & b).sum() / max(1, (a | b).sum())
        # colour agreement on pixels both call "leg" and the reference has a colour class for
        known = r & mm & (cref >= 0)
        agree = (cref[known] == cmap[known]).mean() if known.any() else 0
        out[v] = dict(iou=float(iou), colour_iou=cols, colour_agree=float(agree), img=img, mask=m, cmap=cmap, roi=roi)
    return out, (im, fg, cref, ign)


def compare_image(view, res, ref, path, scale=3):
    im, fg, cref, ign = ref
    x0, x1 = VIEWS[view][1]
    r = res[view]
    m = r["mask"]
    H = fg.shape[0]
    sl = (slice(0, H), slice(x0, x1))
    W = x1 - x0
    diff = np.full((H, W, 3), 235.0)
    f, mm, ig = fg[sl], m[sl], ign[sl]
    diff[ig] = (200, 200, 200)
    diff[f & mm & ~ig] = (120, 190, 120)
    diff[f & ~mm & ~ig] = (220, 70, 60)
    diff[~f & mm & ~ig] = (60, 110, 230)
    # colour-class map of the reference next to the render's colour classes
    pal = np.array([COLOURS[k] for k in COLOURS] + [(20, 20, 20)], float)
    refcls = np.full((H, W, 3), 235.0)
    cr = cref[sl]
    refcls[f & (cr >= 0)] = pal[cr[f & (cr >= 0)]]
    refcls[f & (cr < 0)] = (20, 20, 20)
    panels = [im[sl].astype(float), refcls, r["img"][sl], diff]
    labels = ["reference 255.png", "reference colour classes", "mesh render (flat, 4 colours)", "silhouette diff"]
    out = Image.new("RGB", (len(panels) * (W * scale + 10), H * scale + 40), "white")
    d = ImageDraw.Draw(out)
    for i, p in enumerate(panels):
        imgp = Image.fromarray(np.clip(p, 0, 255).astype("uint8")).resize((W * scale, H * scale), Image.NEAREST)
        out.paste(imgp, (i * (W * scale + 10), 40))
        d.text((i * (W * scale + 10) + 4, 24), labels[i], fill=(0, 0, 0))
    ci = "  ".join("%s %.2f" % (k, v) for k, v in r["colour_iou"].items())
    d.text((4, 4), "%s   silhouette IoU %.3f   colour IoU: %s   colour agreement %.2f   (diff: green both, red ref only, blue mesh only, grey ignored)"
           % (view.upper(), r["iou"], ci, r["colour_agree"]), fill=(0, 0, 0))
    out.save(path)
