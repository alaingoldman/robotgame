"""Verification renders for the mech2 torso (numpy + Pillow software rasteriser).

  python verify.py   ->  ../renders/compare_front.png, compare_back.png, compare_side.png,
                          ../renders/depth_check.png, ../renders/iou.json

Orthographic, flat shaded, rendered at the reference sheet scale (28.4 px per cell
horizontally, 29.3 px per cell vertically).  Silhouette IoU is computed only inside
the "care" region of each sheet: head, arms (below the pauldrons / shoulder balls)
and legs (below the hip-ball tops) are masked out because they are other helpers' parts.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, ".."))
REN = os.path.join(OUT, "renders")
REFS = os.path.join(HERE, "refs")
S = 0.816
SX, SY = 28.4, 29.3

COL = {"white": (242, 242, 242), "gold": (212, 169, 58), "blue": (47, 111, 191), "grey": (138, 138, 138),
       "darkgrey": (90, 90, 90)}


def load_objs():
    tris, cols = [], []
    for f in sorted(os.listdir(OUT)):
        if not f.endswith(".obj"):
            continue
        col = f[:-4].split("_")[-1]
        V, F = [], []
        for line in open(os.path.join(OUT, f)):
            if line.startswith("v "):
                V.append([float(t) for t in line.split()[1:4]])
            elif line.startswith("f "):
                F.append([int(t.split("/")[0]) - 1 for t in line.split()[1:4]])
        V = np.array(V) / S  # back to cells
        T = V[np.array(F)]
        tris.append(T)
        cols += [col] * len(T)
    return np.concatenate(tris), cols


def load_per_file():
    out = {}
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".obj"):
            V = [[float(t) for t in l.split()[1:4]] for l in open(os.path.join(OUT, f)) if l.startswith("v ")]
            out[f[:-4]] = np.array(V) / S
    return out


def render(T, cols, cam_dir, W, H, cx, cy, up=(0, 1, 0), bg=(40, 40, 46), sx=SX, sy=SY):
    """cam_dir: unit vector from the model toward the camera.  Returns (rgb, mask)."""
    c = np.array(cam_dir, float)
    c /= np.linalg.norm(c)
    upv = np.array(up, float)
    f = -c
    r = np.cross(f, upv)
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    P = T.reshape(-1, 3)
    px = cx + (P @ r) * sx
    py = cy - (P @ u) * sy
    dz = P @ c  # bigger = closer
    px, py, dz = px.reshape(-1, 3), py.reshape(-1, 3), dz.reshape(-1, 3)
    N = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    L = 0.55 * c + 0.45 * u - 0.35 * r
    L /= np.linalg.norm(L)
    shade = 0.42 + 0.58 * np.clip(np.abs(N @ L), 0, 1)
    img = np.zeros((H, W, 3), float)
    img[:] = bg
    zb = np.full((H, W), -1e9)
    for i in range(len(T)):
        x0, x1 = int(max(0, math.floor(px[i].min()))), int(min(W - 1, math.ceil(px[i].max())))
        y0, y1 = int(max(0, math.floor(py[i].min()))), int(min(H - 1, math.ceil(py[i].max())))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (xa, xb, xc), (ya, yb, yc) = px[i], py[i]
        den = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
        if abs(den) < 1e-9:
            continue
        w0 = ((yb - yc) * (gx - xc) + (xc - xb) * (gy - yc)) / den
        w1 = ((yc - ya) * (gx - xc) + (xa - xc) * (gy - yc)) / den
        w2 = 1 - w0 - w1
        ins = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not ins.any():
            continue
        z = w0 * dz[i, 0] + w1 * dz[i, 1] + w2 * dz[i, 2]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        upd = ins & (z > sub)
        sub[upd] = z[upd]
        img[y0:y1 + 1, x0:x1 + 1][upd] = np.array(COL[cols[i]]) * shade[i]
    mask = zb > -1e8
    return img.clip(0, 255).astype(np.uint8), mask


def ref_mask(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    g = a.mean(2)
    sat = a.max(2) - a.min(2)
    bgc = (sat < 18) & (g > 180) & (g < 237)
    im = Image.fromarray((bgc * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
    Hh, Ww = a.shape[:2]
    for seed in [(0, 0), (Ww - 1, 0), (0, Hh - 1), (Ww - 1, Hh - 1), (Ww // 2, 0)]:
        if im.getpixel(seed) == 255:
            ImageDraw.floodfill(im, seed, 128)
    # enclosed background pockets (e.g. between arm and waist) -> background too
    arr = np.asarray(im).copy()
    ys, xs = np.nonzero(arr == 255)
    im2 = Image.fromarray(arr).copy()
    done = np.zeros_like(arr, bool)
    for y, x in zip(ys, xs):
        if done[y, x] or im2.getpixel((int(x), int(y))) != 255:
            continue
        ImageDraw.floodfill(im2, (int(x), int(y)), 77)
        reg = np.asarray(im2) == 77
        done |= reg
        # white armour (~233) vs paper (~227 incl. darker grid lines): decide by mean brightness
        val = 128 if (reg.sum() > 150 and g[reg].mean() < 230.0) else 200
        b = np.asarray(im2).copy()
        b[reg] = val
        im2 = Image.fromarray(b).copy()
    m = np.asarray(im2) != 128
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
    return a.astype(np.uint8), m


def poly_mask(W, H, polys):
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    for p in polys:
        d.polygon([tuple(map(float, q)) for q in p], fill=255)
    return np.asarray(im) > 0


def mirror(poly, c):
    return [(2 * c - x, y) for x, y in poly]


def dontcare_front(W, H):
    c = 285.5
    head = [(220, 0), (351, 0), (351, 92), (337, 100), (330, 160), (305, 170), (266, 170), (241, 160), (234, 100),
            (220, 92)]
    arm = [(0, 232), (120, 232), (170, 225), (192, 218), (192, 345), (0, 345)]
    ball = [(170, 172), (198, 172), (198, 236), (170, 236)]
    ps = [head, arm, mirror(arm, c), ball, mirror(ball, c)]
    return poly_mask(W, H, ps)


def dontcare_back(W, H):
    c = 296.0
    head = [(230, 0), (362, 0), (362, 85), (345, 138), (250, 138), (230, 85)]
    arm = [(0, 228), (125, 230), (185, 214), (200, 214), (200, 342), (180, 342), (180, H), (0, H)]
    ball = [(182, 170), (203, 170), (203, 230), (182, 230)]
    legs = [(0, 503), (W, 503), (W, H), (0, H)]
    ps = [head, arm, mirror(arm, c), ball, mirror(ball, c), legs]
    return poly_mask(W, H, ps)


def dontcare_side(W, H):
    head = [(85, 20), (250, 0), (262, 60), (240, 150), (215, 165), (150, 160), (95, 170), (85, 100)]
    arm = [(160, 140), (250, 140), (262, 300), (250, H), (130, H), (150, 300)]
    low = [(0, 330), (W, 330), (W, H), (0, H)]
    return poly_mask(W, H, [head, arm, low])


def iou(a, b, care):
    i = (a & b & care).sum()
    u = ((a | b) & care).sum()
    return float(i) / max(u, 1)


def overlay(ref, mask_r, mask_m, care):
    o = (ref.astype(float) * 0.35 + 140).astype(np.uint8)
    o = o.copy()
    o[mask_r & ~mask_m & care] = (230, 60, 60)    # reference only (missing)
    o[mask_m & ~mask_r & care] = (60, 120, 240)   # model only (extra)
    o[mask_m & mask_r & care] = (90, 200, 110)    # both
    return o


def label(img, text):
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 8 * len(text) + 8, 16], fill=(0, 0, 0))
    d.text((4, 2), text, fill=(255, 255, 255))
    return np.asarray(im)


def side_by_side(*imgs):
    Hh = max(i.shape[0] for i in imgs)
    out = np.full((Hh, sum(i.shape[1] for i in imgs) + 6 * (len(imgs) - 1), 3), 255, np.uint8)
    x = 0
    for i in imgs:
        out[:i.shape[0], x:x + i.shape[1]] = i
        x += i.shape[1] + 6
    return out


def main():
    os.makedirs(REN, exist_ok=True)
    T, cols = load_objs()
    res = {}
    # FRONT (camera at -Z)
    ref, mr = ref_mask(os.path.join(REFS, "259.png"))
    Hh, Ww = mr.shape
    img, mm = render(T, cols, (0, 0, -1), Ww, Hh, 285.5, 525.0)
    care = ~dontcare_front(Ww, Hh)
    res["front_iou"] = iou(mr, mm, care)
    Image.fromarray(side_by_side(label(ref, "ref 259"), label(img, "model front"),
                                 label(overlay(ref, mr, mm, care), "IoU %.3f" % res["front_iou"]))).save(
        os.path.join(REN, "compare_front.png"))
    # BACK (camera at +Z)
    ref, mr = ref_mask(os.path.join(REFS, "261.png"))
    Hh, Ww = mr.shape
    img, mm = render(T, cols, (0, 0, 1), Ww, Hh, 296.0, 525.0)
    care = ~dontcare_back(Ww, Hh)
    res["back_iou"] = iou(mr, mm, care)
    crop = (0, 640)
    Image.fromarray(side_by_side(label(ref[:crop[1]], "ref 261"), label(img[:crop[1]], "model back"),
                                 label(overlay(ref, mr, mm, care)[:crop[1]], "IoU %.3f" % res["back_iou"]))).save(
        os.path.join(REN, "compare_back.png"))
    # SIDE: 260 is a 3/4 view; fit the camera azimuth + placement by IoU over the visible torso
    ref, mr = ref_mask(os.path.join(REFS, "260.png"))
    Hh, Ww = mr.shape
    care = ~dontcare_side(Ww, Hh)
    best = None
    # coarse search on silhouettes only (fast path: render masks)
    T2 = T
    cand = []
    for az in range(45, 91, 5):
        a = math.radians(az)
        cam = (-math.sin(a), 0.0, -math.cos(a))
        _, m0 = render(T2, cols, cam, Ww * 2, Hh * 2, Ww, Hh * 1.5)
        cand.append((az, cam, m0))
    for az, cam, m0 in cand:
        # place by sliding the rendered mask (pure translation search)
        for dx in range(-120, 121, 6):
            for dy in range(-200, 201, 6):
                x0, y0 = Ww // 2 - dx, int(Hh * 0.5) - dy
                if x0 < 0 or y0 < 0 or x0 + Ww > m0.shape[1] or y0 + Hh > m0.shape[0]:
                    continue
                mm = m0[y0:y0 + Hh, x0:x0 + Ww]
                v = iou(mr, mm, care)
                if best is None or v > best[0]:
                    best = (v, az, cam, x0, y0)
    v, az, cam, x0, y0 = best
    img2, m2 = render(T, cols, cam, Ww * 2, Hh * 2, Ww, Hh * 1.5)
    img, mm = img2[y0:y0 + Hh, x0:x0 + Ww], m2[y0:y0 + Hh, x0:x0 + Ww]
    res["side34_iou"] = v
    res["side34_fitted_azimuth_deg"] = az
    Image.fromarray(side_by_side(label(ref, "ref 260 (3/4)"), label(img, "model az %d" % az),
                                 label(overlay(ref, mr, mm, care), "IoU %.3f" % v))).save(
        os.path.join(REN, "compare_side.png"))
    # DEPTH CHECK
    W2, H2 = 420, 520
    views = []
    for name, cam in [("3/4 front-left", (-0.7, 0.25, -0.7)), ("3/4 front-right", (0.7, 0.25, -0.7)),
                      ("3/4 back", (0.6, 0.3, 0.75)), ("side (right)", (1, 0, 0))]:
        im, _ = render(T, cols, cam, W2, H2, W2 / 2, 470, sx=26, sy=26)
        views.append(label(im, name))
    top, _ = render(T, cols, (0, 1, 0), W2, H2, W2 / 2, H2 / 2, up=(0, 0, -1), sx=26, sy=26)
    # annotate top view: front is up
    views.append(label(top, "top (front up)"))
    # measured depth numbers (cells)
    per = load_per_file()
    chest = np.concatenate([v for k, v in per.items() if k.startswith("chest_")])
    wb = per["chest_white"]
    dep = {
        "chest_prow_Z": float(chest[:, 2].min()),
        "core_front_Z": float(per["chest_darkgrey"][:, 2].min()),
        "blue_side_block_front_Z": float(per["chest_blue"][np.abs(per["chest_blue"][:, 0]) > 2.65][:, 2].min()),
        "back_plate_Z": float(wb[(np.abs(wb[:, 0]) < 1.05) & (wb[:, 1] > 9.5)][:, 2].max()),
        "fin_top_back_Z": float(per["chest_gold"][:, 2].max()),
        "pauldron_Z_extent": [float(per["pauldron_R_white"][:, 2].min()), float(per["pauldron_R_white"][:, 2].max())],
        "pauldron_outer_tip_X": float(per["pauldron_R_gold"][:, 0].max()),
        "torso_side_X": float(per["chest_blue"][:, 0].max()),
    }
    dep["chest_projection_vs_core"] = dep["core_front_Z"] - dep["chest_prow_Z"]
    dep["chest_projection_vs_blue_side"] = dep["blue_side_block_front_Z"] - dep["chest_prow_Z"]
    dep["prow_to_back_plate"] = dep["back_plate_Z"] - dep["chest_prow_Z"]
    dep["pauldron_standoff_past_torso_side"] = dep["pauldron_outer_tip_X"] - dep["torso_side_X"]
    res["depth_cells"] = {k: (round(v, 3) if isinstance(v, float) else [round(x, 3) for x in v]) for k, v in dep.items()}
    side_im, _ = render(T, cols, (1, 0, 0), W2, H2, W2 / 2, 470, sx=26, sy=26)
    sim = Image.fromarray(side_im)
    d = ImageDraw.Draw(sim)
    # side view: camera at +X; screen right = -Z?  r = cross(f, up) with f = (-1,0,0) -> (0,0,-1): right = forward
    marks = [(dep["chest_prow_Z"], "chest prow Z %.2f" % dep["chest_prow_Z"], (255, 120, 120)),
             (dep["core_front_Z"], "core front %.2f" % dep["core_front_Z"], (180, 180, 255)),
             (dep["back_plate_Z"], "back plate %.2f" % dep["back_plate_Z"], (120, 255, 120))]
    for k, (z, txt, colr) in enumerate(marks):
        X = W2 / 2 + (-z) * 26
        d.line([(X, 20), (X, H2 - 20)], fill=colr)
        d.text((min(X + 2, W2 - 120), 22 + 14 * k), txt, fill=colr)
    d.text((6, H2 - 34), "chest pops %.2f cells (%.2f studs) in front of the core" % (
        dep["chest_projection_vs_core"], dep["chest_projection_vs_core"] * S), fill=(255, 255, 255))
    views.append(label(np.asarray(sim), "side + depth marks (front ->)"))
    row1 = side_by_side(*views[:3])
    row2 = side_by_side(*views[3:])
    Image.fromarray(np.concatenate([row1, np.full((6, row1.shape[1], 3), 255, np.uint8), row2])).save(
        os.path.join(REN, "depth_check.png"))
    print(json.dumps(res, indent=2))
    with open(os.path.join(REN, "iou.json"), "w") as fh:
        json.dump(res, fh, indent=2)


if __name__ == "__main__":
    main()
