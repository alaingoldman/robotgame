"""Tiny numpy z-buffer rasteriser. render(parts, view, size) -> PIL image.
parts: list of (vertices Nx3, faces Mx3, rgb tuple or per-face colours Mx3 uint8)
"""
import numpy as np
from PIL import Image, ImageDraw


def view_matrix(view):
    # returns rotation R such that camera coords = R @ p ; camera looks along -z_cam (we keep larger z = closer)
    def rotY(a):
        c, s = np.cos(a), np.sin(a)
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])

    def rotX(a):
        c, s = np.cos(a), np.sin(a)
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    # Model front faces -Z. Camera for 'front' sits at -Z looking +Z. Screen x right = mech's right (+X) appears on viewer's left.
    if view == 'front':
        return rotY(np.pi)          # -Z becomes +Z (towards camera)
    if view == 'side':               # from mech's right side (+X)
        return rotY(-np.pi / 2)
    if view == 'back':
        return np.eye(3)
    if view == 'threequarter':
        return rotX(np.radians(15)) @ rotY(np.pi - np.radians(35))
    if view == 'top':
        return rotX(np.radians(90)) @ rotY(np.pi)
    raise ValueError(view)


def render(parts, view, size=800, light=(0.4, 0.6, 1.0), bg=(245, 245, 245), title=None):
    R = view_matrix(view)
    allv = np.concatenate([p[0] for p in parts]) @ R.T
    mn, mx = allv.min(0), allv.max(0)
    span = max(mx[0] - mn[0], mx[1] - mn[1]) * 1.08
    c = (mn + mx) / 2
    scale = size / span
    zbuf = np.full((size, size), -np.inf)
    img = np.zeros((size, size, 3)) + np.array(bg)
    L = np.array(light, float); L /= np.linalg.norm(L)
    for v, f, col in parts:
        cv = v @ R.T
        sx = (cv[:, 0] - c[0]) * scale + size / 2
        sy = size / 2 - (cv[:, 1] - c[1]) * scale
        sz = cv[:, 2]
        tri = cv[f]
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        nl = np.linalg.norm(n, axis=1) + 1e-12
        n /= nl[:, None]
        shade = np.abs(n @ L) * 0.75 + 0.25
        col = np.asarray(col, float)
        if col.ndim == 1:
            col = np.tile(col, (len(f), 1))
        X = sx[f]; Y = sy[f]; Z = sz[f]
        for i in range(len(f)):
            x0, x1, x2 = X[i]; y0, y1, y2 = Y[i]
            xmin = max(int(np.floor(min(x0, x1, x2))), 0); xmax = min(int(np.ceil(max(x0, x1, x2))), size - 1)
            ymin = max(int(np.floor(min(y0, y1, y2))), 0); ymax = min(int(np.ceil(max(y0, y1, y2))), size - 1)
            if xmax < xmin or ymax < ymin:
                continue
            d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(d) < 1e-9:
                continue
            xs, ys = np.meshgrid(np.arange(xmin, xmax + 1) + 0.5, np.arange(ymin, ymax + 1) + 0.5)
            a = ((y1 - y2) * (xs - x2) + (x2 - x1) * (ys - y2)) / d
            b = ((y2 - y0) * (xs - x2) + (x0 - x2) * (ys - y2)) / d
            g = 1 - a - b
            m = (a >= -1e-4) & (b >= -1e-4) & (g >= -1e-4)
            if not m.any():
                continue
            z = a * Z[i, 0] + b * Z[i, 1] + g * Z[i, 2]
            sub = zbuf[ymin:ymax + 1, xmin:xmax + 1]
            upd = m & (z > sub)
            sub[upd] = z[upd]
            img[ymin:ymax + 1, xmin:xmax + 1][upd] = col[i] * shade[i]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    if title:
        ImageDraw.Draw(im).text((8, 8), title, fill=(0, 0, 0))
    return im
