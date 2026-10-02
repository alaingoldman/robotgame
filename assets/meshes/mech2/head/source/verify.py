"""Orthographic flat-shaded renders, silhouette / colour IoU against the
reference sheets, side-by-side comparison and depth_check.png."""
import os
import numpy as np
from PIL import Image, ImageDraw

import refs
import geom

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, ".."))
CLS = {"Gold": refs.GOLD, "White": refs.WHITE, "Blue": refs.BLUE, "Neck": refs.GREY}
RGB = {"Gold": (212, 169, 58), "White": (236, 236, 236), "Blue": (47, 111, 191), "Neck": (120, 122, 128)}
LIGHT = np.array([-0.45, 0.7, -0.55])
LIGHT /= np.linalg.norm(LIGHT)


def gather(parts):
    Vs, Fs, C, K = [], [], [], []
    off = 0
    for name, m in parts.items():
        V, F = m.arrays()
        Vs.append(V)
        Fs.append(F + off)
        off += len(V)
        C += [RGB[name]] * len(F)
        K += [CLS[name]] * len(F)
    return np.concatenate(Vs), np.concatenate(Fs), np.array(C, float), np.array(K)


def raster(P2, depth, F, h, w, fcol, fcls):
    """P2: projected vertex pixel coords (N,2); depth (N,) smaller = nearer."""
    zb = np.full((h, w), np.inf)
    img = np.full((h, w, 3), 255.0)
    lab = np.zeros((h, w), int)
    for i, (a, b, c) in enumerate(F):
        p = P2[[a, b, c]]
        x0, y0 = np.floor(p.min(0)).astype(int)
        x1, y1 = np.ceil(p.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, w - 1), min(y1, h - 1)
        if x1 < x0 or y1 < y0:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        px, py = xx + 0.5, yy + 0.5
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        l3 = 1 - l1 - l2
        ins = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
        if not ins.any():
            continue
        d = l1 * depth[a] + l2 * depth[b] + l3 * depth[c]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        upd = ins & (d < sub)
        sub[upd] = d[upd]
        img[y0:y1 + 1, x0:x1 + 1][upd] = fcol[i]
        lab[y0:y1 + 1, x0:x1 + 1][upd] = fcls[i]
    return img, lab, np.isfinite(zb)


SHEET_LIGHT = {"front": (-0.35, 0.6, -0.72), "back": (0.35, 0.6, 0.72), "side": (-0.72, 0.6, -0.35)}


def shade(V, F, C, light=LIGHT):
    light = np.array(light, float)
    light /= np.linalg.norm(light)
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    k = 0.5 + 0.5 * np.clip(n @ light, 0, 1)
    return np.clip(C * k[:, None], 0, 255), n


def view_axes(view):
    """-> (screen-horizontal fn, depth fn) for the three sheets."""
    if view == "front":   # camera at -Z, screen right = -X
        return (lambda V: -V[:, 0]), (lambda V: V[:, 2])
    if view == "back":    # camera at +Z, screen right = +X
        return (lambda V: V[:, 0]), (lambda V: -V[:, 2])
    return (lambda V: V[:, 2]), (lambda V: V[:, 0])  # side: camera at -X, screen right = +Z


def render_sheet(view, parts, scale=1):
    d = refs.load(view)
    V, F, C, K = gather(parts)
    hor, dep = view_axes(view)
    a = hor(V)
    px, py = refs.to_px(view, a, V[:, 1])
    P2 = np.stack([px, py], 1) * scale
    col, nrm = shade(V, F, C, SHEET_LIGHT[view])
    # light relative to the camera so every sheet is lit from upper-left
    img, lab, mask = raster(P2, dep(V), F, d["h"] * scale, d["w"] * scale, col, K)
    return d, img, lab, mask


def iou(a, b):
    u = (a | b).sum()
    return float((a & b).sum() / u) if u else 1.0


def compare(parts):
    res = {}
    tiles = []
    for view in ("front", "side", "back"):
        d, img, lab, mask = render_sheet(view, parts)
        r = d["roi"]
        sil_m = mask & r
        s_raw = iou(sil_m, d["sil"])
        # the sheets draw a ~2.5 px ink outline centred on each edge; the flood-fill
        # silhouette includes all of it, so the true edge is ~1 px inside: compare
        # against the reference silhouette eroded by 1 px (4-neighbour)
        e = d["sil"].copy()
        e[1:] &= d["sil"][:-1]; e[:-1] &= d["sil"][1:]; e[:, 1:] &= d["sil"][:, :-1]; e[:, :-1] &= d["sil"][:, 1:]
        s = iou(sil_m, e)
        cols = {}
        for name, k in (("gold", refs.GOLD), ("white", refs.WHITE), ("blue", refs.BLUE)):
            cols[name] = iou((lab == k) & r, d["lab"] == k)
        # pixel agreement of colour classes over the union silhouette
        u = sil_m | d["sil"]
        agree = float(((np.where(r, lab, 0) == d["lab"]) & u).sum() / u.sum())
        res[view] = dict(sil_iou=round(s, 4), sil_iou_raw=round(s_raw, 4), colour_agreement=round(agree, 4), **{k + "_iou": round(v, 3) for k, v in cols.items()})
        # tile: reference | render (shaded) | overlay (ref outline on render) | diff
        ref = d["img"].astype(np.uint8)
        ren = img.astype(np.uint8)
        diff = np.full_like(ref, 255)
        diff[d["sil"] & ~sil_m] = (220, 40, 40)   # missing in model
        diff[sil_m & ~d["sil"]] = (40, 90, 220)   # extra in model
        diff[d["sil"] & sil_m] = (200, 200, 200)
        diff[~r] = (255, 225, 225)
        ov = (0.55 * ren + 0.45 * ref).astype(np.uint8)
        tiles.append((view, [ref, ren, ov, diff]))
    # compose
    k = 3
    rows = []
    for view, ims in tiles:
        row = np.concatenate([np.pad(t, ((0, 0), (0, 6), (0, 0)), constant_values=255) for t in ims], 1)
        rows.append(row)
    W = max(r.shape[1] for r in rows)
    rows = [np.pad(r, ((0, 8), (0, W - r.shape[1]), (0, 0)), constant_values=255) for r in rows]
    canvas = Image.fromarray(np.concatenate(rows, 0)).resize((W * k, sum(r.shape[0] for r in rows) * k), Image.NEAREST)
    dr = ImageDraw.Draw(canvas)
    y = 0
    for (view, _), r in zip(tiles, rows):
        m = res[view]
        dr.text((4, y + 4), "%s  ref | model | overlay | diff(red=missing, blue=extra)   sil IoU %.3f  colour agree %.3f  gold %.2f white %.2f blue %.2f"
                % (view.upper(), m["sil_iou"], m["colour_agreement"], m["gold_iou"], m["white_iou"], m["blue_iou"]), fill=(0, 0, 0))
        y += r.shape[0] * k
    canvas.save(os.path.join(OUT, "compare_views.png"))
    return res


def rot(yaw, pitch):
    cy, sy = np.cos(np.radians(yaw)), np.sin(np.radians(yaw))
    cp, sp = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cp, sp], [0, -sp, cp]])  # +pitch = camera above
    return Rx @ Ry


def render_cam(parts, yaw, pitch, size=420, span=8.0, centre=(0, 1.9, 0.3), title=""):
    """Orthographic camera. yaw 0 = looking from the front (-Z) toward +Z.
    Positive yaw orbits toward the mech's +X side."""
    V, F, C, K = gather(parts)
    R = rot(yaw, pitch)
    Vc = (V - np.array(centre)) @ R.T
    # camera space: x right(-X at yaw0), y up, depth +z
    px = size / 2 - Vc[:, 0] * size / span
    py = size / 2 - Vc[:, 1] * size / span
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    Lw = R.T @ np.array([-0.35, 0.6, -0.72])  # light fixed to the camera
    Lw /= np.linalg.norm(Lw)
    col = np.clip(C * (0.5 + 0.5 * np.clip(n @ Lw, 0, 1))[:, None], 0, 255)
    img, lab, mask = raster(np.stack([px, py], 1), Vc[:, 2], F, size, size, col, K)
    img[~mask] = (246, 246, 250)
    im = Image.fromarray(img.astype(np.uint8))
    dr = ImageDraw.Draw(im)
    dr.text((6, 6), title, fill=(0, 0, 0))
    return im


def depth_check(parts):
    views = [("3/4 FRONT (mech left)", -40, 12), ("3/4 FRONT (mech right)", 40, 12), ("3/4 BACK", 140, 15),
             ("TOP (front down)", 0, 89.9), ("SIDE (raw)", 90, 0), ("LOW 3/4 FRONT", -30, -18)]
    ims = [render_cam(parts, y, p, title=t) for t, y, p in views]
    W, H = ims[0].size
    canvas = Image.new("RGB", (W * 3, H * 2), (255, 255, 255))
    for i, im in enumerate(ims):
        canvas.paste(im, ((i % 3) * W, (i // 3) * H))
    canvas.save(os.path.join(OUT, "depth_check.png"))


def ortho_renders(parts):
    """Model-only flat-shaded ortho FRONT / SIDE / BACK at 4x sheet scale."""
    ims = []
    for view in ("front", "side", "back"):
        d, img, lab, mask = render_sheet(view, parts, scale=4)
        img[~mask] = (246, 246, 250)
        ims.append(Image.fromarray(img.astype(np.uint8)))
    W = sum(i.width for i in ims)
    H = max(i.height for i in ims)
    canvas = Image.new("RGB", (W, H), (255, 255, 255))
    x = 0
    for i in ims:
        canvas.paste(i, (x, 0))
        x += i.width
    canvas.save(os.path.join(OUT, "ortho_views.png"))


if __name__ == "__main__":
    parts = geom.all_parts()
    r = compare(parts)
    for k, v in r.items():
        print(k, v)
    depth_check(parts)
    ortho_renders(parts)
