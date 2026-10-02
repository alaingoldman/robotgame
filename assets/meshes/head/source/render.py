"""Orthographic flat-shaded rasterizer (numpy) for the head meshes, drawn in
the reference crops' pixel frames (refs.VIEWS), with crease / silhouette
lines like the sheet's ink. Also the silhouette IoU against the crops."""
import numpy as np
from PIL import Image, ImageDraw

import refs

ROLE_RGB = {
    "main": (106, 125, 142),
    "hi": (150, 132, 92),  # brass (TitanConfig palette hi)
    "trim": (150, 160, 170),
    "glow": (70, 210, 205),
    "recess": (58, 69, 79),
    "dark": (75, 89, 100),
}
LIGHT = np.array([-0.35, 0.55, -0.75])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def raster(items, view, shape, ss=2):
    """items: [(Mesh in head space cells, role)]. -> rgb (H,W,3) float,
    mask, plus buffers. Supersampled by ss."""
    fn = refs.VIEWS[view][1]
    H, W = shape
    Hs, Ws = H * ss, W * ss
    zbuf = np.full((Hs, Ws), np.inf)
    col = np.zeros((Hs, Ws, 3))
    nbuf = np.zeros((Hs, Ws, 3))
    pid = -np.ones((Hs, Ws), int)
    light = {"front": LIGHT, "side": np.array([-0.75, 0.55, -0.35]), "back": LIGHT * np.array([1, 1, -1])}.get(view, LIGHT)
    light = light / np.linalg.norm(light)
    for k, (m, role) in enumerate(items):
        V, F = m.arrays()
        if len(F) == 0:
            continue
        P = np.array([fn(*p) for p in V])  # cx, cy, depth
        P[:, :2] = P[:, :2] * ss
        nrm = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        nrm /= np.linalg.norm(nrm, axis=1)[:, None] + 1e-12
        base = np.array(ROLE_RGB[role], float)
        for fi, (a, b, c) in enumerate(F):
            A, B, C = P[a], P[b], P[c]
            x0 = int(max(0, np.floor(min(A[0], B[0], C[0]))))
            x1 = int(min(Ws - 1, np.ceil(max(A[0], B[0], C[0]))))
            y0 = int(max(0, np.floor(min(A[1], B[1], C[1]))))
            y1 = int(min(Hs - 1, np.ceil(max(A[1], B[1], C[1]))))
            if x1 < x0 or y1 < y0:
                continue
            det = (B[1] - C[1]) * (A[0] - C[0]) + (C[0] - B[0]) * (A[1] - C[1])
            if abs(det) < 1e-9:
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
            lam = 0.55 + 0.45 * max(0.0, float(np.dot(n, light))) + 0.1 * float(n[1])
            col[y0:y1 + 1, x0:x1 + 1][upd] = np.clip(base * lam, 0, 255)
            nbuf[y0:y1 + 1, x0:x1 + 1][upd] = n
            pid[y0:y1 + 1, x0:x1 + 1][upd] = k
    mask = np.isfinite(zbuf)
    # ink: silhouette, piece boundaries, creases > 28 deg, depth steps
    ink = np.zeros_like(mask)
    for dy, dx in ((0, 1), (1, 0)):
        a = (slice(0, Hs - dy), slice(0, Ws - dx))
        b = (slice(dy, Hs), slice(dx, Ws))
        e = (mask[a] != mask[b])
        both = mask[a] & mask[b]
        e |= both & (pid[a] != pid[b])
        e |= both & ((nbuf[a] * nbuf[b]).sum(-1) < 0.88)
        e |= both & (np.abs(np.where(both, np.nan_to_num(zbuf[a] - zbuf[b], posinf=0, neginf=0), 0)) > 0.12)
        ink[a] |= e
        ink[b] |= e
    bg = np.array([225, 225, 225], float)
    img = np.where(mask[..., None], col, bg)
    img[ink] = (25, 28, 32)
    # downsample
    img = img.reshape(H, ss, W, ss, 3).mean((1, 3))
    m = mask.reshape(H, ss, W, ss).mean((1, 3)) >= 0.5
    return img, m


def iou(view, items):
    head, ign, _ = refs.masks(view)
    img, m = raster(items, view, head.shape)
    roi = ~ign
    inter = (m & head & roi).sum()
    union = ((m | head) & roi).sum()
    return inter / union, img, m, head, ign


def compare_image(view, items, path=None, scale=2):
    v, img, m, head, ign = iou(view, items)
    ref = refs.load(view).astype(float)
    H, W = head.shape
    # diff: green = both, red = reference only, blue = mesh only, grey = ignored (other parts)
    diff = np.full((H, W, 3), 235.0)
    diff[ign] = (200, 200, 200)
    diff[head & m & ~ign] = (120, 190, 120)
    diff[head & ~m & ~ign] = (220, 70, 60)
    diff[~head & m & ~ign] = (60, 110, 230)
    panels = [ref, img, diff]
    out = Image.new("RGB", (W * 3 * scale + 20, H * scale + 26), "white")
    for i, p in enumerate(panels):
        im = Image.fromarray(np.clip(p, 0, 255).astype("uint8")).resize((W * scale, H * scale), Image.NEAREST if i == 2 else Image.LANCZOS)
        out.paste(im, (i * (W * scale + 10), 26))
    d = ImageDraw.Draw(out)
    d.text((4, 6), "%s  reference | mesh render (same scale) | silhouette diff: green both, red ref only, blue mesh only, grey = torso/pad (ignored)   IoU %.3f" % (view.upper(), v), fill=(0, 0, 0))
    if path:
        out.save(path)
    return v, out
