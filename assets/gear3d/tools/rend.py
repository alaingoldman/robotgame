"""Small numpy z-buffer rasteriser with per-pixel texture sampling.
part = (V Nx3, F Mx3, UV Nx2 or None, tex HxWx3 uint8 or rgb tuple)."""
import numpy as np
from PIL import Image, ImageDraw


def rotY(a):
    c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotX(a):
    c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def view_matrix(view):
    # model: front = -Z, +X = character right. 'front' camera at -Z looking +Z.
    if view == 'front': return rotY(np.pi)
    if view == 'side': return rotY(-np.pi / 2)        # from character's right (+X)
    if view == 'lside': return rotY(np.pi / 2)
    if view == 'back': return np.eye(3)
    if view == 'threeq': return rotX(np.radians(12)) @ rotY(np.pi - np.radians(35))
    if view == 'threeq_l': return rotX(np.radians(12)) @ rotY(np.pi + np.radians(35))
    if view == 'top': return rotX(np.radians(90)) @ rotY(np.pi)
    raise ValueError(view)


def render(parts, view, size=600, bg=(235, 235, 235), title=None, frame=None):
    R = view_matrix(view) if isinstance(view, str) else view
    allv = np.concatenate([p[0] for p in parts]) @ R.T
    mn, mx = allv.min(0), allv.max(0)
    if frame is not None: mn, mx = frame
    span = max(mx[0] - mn[0], mx[1] - mn[1]) * 1.08
    c = (mn + mx) / 2; scale = size / span
    zbuf = np.full((size, size), -np.inf)
    img = np.zeros((size, size, 3)) + np.array(bg)
    L = np.array([0.35, 0.55, 1.0]); L /= np.linalg.norm(L)
    for V, F, UV, tex in parts:
        cv = V @ R.T
        sx = (cv[:, 0] - c[0]) * scale + size / 2
        sy = size / 2 - (cv[:, 1] - c[1]) * scale
        sz = cv[:, 2]
        tri = cv[F]
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= (np.linalg.norm(n, axis=1) + 1e-12)[:, None]
        facing = n[:, 2]                              # >0 facing camera (if winding CCW outward)
        shade = np.clip(np.abs(n @ L), 0, 1) * 0.7 + 0.3
        istex = isinstance(tex, np.ndarray) and tex.ndim == 3 and UV is not None
        if istex:
            TH, TW = tex.shape[:2]
        X = sx[F]; Y = sy[F]; Z = sz[F]
        for i in range(len(F)):
            x0, x1, x2 = X[i]; y0, y1, y2 = Y[i]
            xmin = max(int(min(x0, x1, x2)), 0); xmax = min(int(max(x0, x1, x2)) + 1, size - 1)
            ymin = max(int(min(y0, y1, y2)), 0); ymax = min(int(max(y0, y1, y2)) + 1, size - 1)
            if xmax < xmin or ymax < ymin: continue
            d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(d) < 1e-9: continue
            xs, ys = np.meshgrid(np.arange(xmin, xmax + 1) + 0.5, np.arange(ymin, ymax + 1) + 0.5)
            a = ((y1 - y2) * (xs - x2) + (x2 - x1) * (ys - y2)) / d
            b = ((y2 - y0) * (xs - x2) + (x0 - x2) * (ys - y2)) / d
            g = 1 - a - b
            m = (a >= -1e-3) & (b >= -1e-3) & (g >= -1e-3)
            if not m.any(): continue
            z = a * Z[i, 0] + b * Z[i, 1] + g * Z[i, 2]
            sub = zbuf[ymin:ymax + 1, xmin:xmax + 1]
            upd = m & (z > sub)
            if not upd.any(): continue
            sub[upd] = z[upd]
            if istex:
                uv = a[upd, None] * UV[F[i, 0]] + b[upd, None] * UV[F[i, 1]] + g[upd, None] * UV[F[i, 2]]
                tx = np.clip((uv[:, 0] % 1) * TW, 0, TW - 1).astype(int); ty = np.clip((uv[:, 1] % 1) * TH, 0, TH - 1).astype(int)
                col = tex[ty, tx].astype(float)
            else:
                col = np.array(tex, float)
            k = shade[i] if facing[i] >= 0 else shade[i] * 0.35   # back faces darkened -> holes show up
            if not istex and facing[i] < 0: col = np.array([255, 0, 255], float)
            img[ymin:ymax + 1, xmin:xmax + 1][upd] = col * k
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    if title: ImageDraw.Draw(im).text((6, 6), title, fill=(0, 0, 0))
    return im


def strip(ims, fn=None):
    W = sum(i.width for i in ims); H = max(i.height for i in ims)
    out = Image.new('RGB', (W, H), 'white'); x = 0
    for i in ims: out.paste(i, (x, 0)); x += i.width
    if fn: out.save(fn)
    return out


def load_glb_parts(fn):
    """All geometry in a glb, baked to world, with uv + base colour texture (glTF uv origin top-left)."""
    import trimesh
    sc = trimesh.load(fn, process=False)
    out = []
    for node in sc.graph.nodes_geometry:
        T, gname = sc.graph[node]
        g = sc.geometry[gname]
        V = trimesh.transform_points(np.asarray(g.vertices), T)
        uv = getattr(g.visual, 'uv', None)
        tex = None
        mat = getattr(g.visual, 'material', None)
        if mat is not None:
            im = getattr(mat, 'baseColorTexture', None) or getattr(mat, 'image', None)
            if im is not None: tex = np.asarray(im.convert('RGB'))
        if uv is not None: uv = np.column_stack([uv[:, 0], 1 - uv[:, 1]])   # trimesh flips v
        out.append((node, V, np.asarray(g.faces), uv, tex if tex is not None else (180, 180, 180)))
    return out
