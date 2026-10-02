"""Old vs new texture close-ups: per-pixel textured z-buffer render (UV interpolated per pixel, simple
lambert + a fake specular for the v2 metal) of the chest, legs and shoulder, from the front and 3/4.
usage: python tex_closeup.py out.png"""
import io, sys, numpy as np, trimesh
from PIL import Image, ImageDraw
from pygltflib import GLTF2

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'


def load(fn):
    sc = trimesh.load(fn, process=False)
    gl = GLTF2().load(fn); blob = gl.binary_blob()
    texs = []
    for im in gl.images:
        bv = gl.bufferViews[im.bufferView]
        texs.append(np.asarray(Image.open(io.BytesIO(blob[bv.byteOffset or 0:(bv.byteOffset or 0) + bv.byteLength])).convert('RGB')).astype(np.float32))
    parts = []
    for node in sc.graph.nodes_geometry:
        g = sc.geometry[sc.graph[node][1]]
        parts.append((np.asarray(g.vertices), np.asarray(g.faces), np.asarray(g.visual.uv)))
    return parts, texs


def rot(yaw, pitch):
    cy, sy = np.cos(yaw), np.sin(yaw); cp, sp = np.cos(pitch), np.sin(pitch)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]); Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    return Rx @ Ry


def render(parts, texs, R, centre, half, size=520, metal=False):
    tex = texs[0]; mr = texs[1] if metal and len(texs) > 1 else None
    TH, TW = tex.shape[:2]
    zb = np.full((size, size), -np.inf); img = np.full((size, size, 3), 235.0)
    L = np.array([0.35, 0.6, 0.72]); L /= np.linalg.norm(L)
    c = R @ centre
    for v, f, uv in parts:
        cv = v @ R.T
        sx = (cv[:, 0] - c[0]) / half * size / 2 + size / 2
        sy = size / 2 - (cv[:, 1] - c[1]) / half * size / 2
        X, Y, Z = sx[f], sy[f], cv[f][:, :, 2]
        inb = (X.max(1) >= 0) & (X.min(1) < size) & (Y.max(1) >= 0) & (Y.min(1) < size)
        nrm = np.cross(cv[f][:, 1] - cv[f][:, 0], cv[f][:, 2] - cv[f][:, 0])
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
        for i in np.where(inb)[0]:
            x0, x1, x2 = X[i]; y0, y1, y2 = Y[i]
            xa, xb = max(int(min(x0, x1, x2)), 0), min(int(max(x0, x1, x2)) + 1, size - 1)
            ya, yb = max(int(min(y0, y1, y2)), 0), min(int(max(y0, y1, y2)) + 1, size - 1)
            if xb < xa or yb < ya:
                continue
            d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(d) < 1e-9:
                continue
            xs, ys = np.meshgrid(np.arange(xa, xb + 1) + 0.5, np.arange(ya, yb + 1) + 0.5)
            a = ((y1 - y2) * (xs - x2) + (x2 - x1) * (ys - y2)) / d
            b = ((y2 - y0) * (xs - x2) + (x0 - x2) * (ys - y2)) / d
            gg = 1 - a - b
            m = (a >= -1e-4) & (b >= -1e-4) & (gg >= -1e-4)
            if not m.any():
                continue
            z = a * Z[i, 0] + b * Z[i, 1] + gg * Z[i, 2]
            sub = zb[ya:yb + 1, xa:xb + 1]; upd = m & (z > sub)
            if not upd.any():
                continue
            sub[upd] = z[upd]
            t = uv[f[i]]
            u = a[upd] * t[0, 0] + b[upd] * t[1, 0] + gg[upd] * t[2, 0]
            vv = a[upd] * t[0, 1] + b[upd] * t[1, 1] + gg[upd] * t[2, 1]
            px = np.clip((u % 1) * TW, 0, TW - 1).astype(int); py = np.clip((1 - vv % 1) * TH, 0, TH - 1).astype(int)
            col = tex[py, px]
            n = nrm[i] * (1 if nrm[i][2] >= 0 else -1)
            lam = 0.35 + 0.65 * max(0.0, float(n @ L))
            out = col * lam
            if mr is not None:
                rough = mr[py, px, 1] / 255; met = mr[py, px, 2] / 255
                h = L + np.array([0, 0, 1.0]); h /= np.linalg.norm(h)
                spec = max(0.0, float(n @ h)) ** 24
                out = out + (spec * met * (1 - rough) * 160)[:, None]
            img[ya:yb + 1, xa:xb + 1][upd] = out
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


if __name__ == '__main__':
    old, ot = load(D + r'\Mech3.glb')
    new, nt = load(D + r'\Mech3_v2.glb')
    shots = [('chest front', rot(np.pi, 0.1), np.array([0, 15.2, 0]), 2.6),
             ('chest 3/4', rot(np.pi + 0.7, 0.15), np.array([0.8, 15.5, 0]), 2.8),
             ('legs 3/4', rot(np.pi + 0.6, 0.1), np.array([1.5, 5.5, 0]), 4.0),
             ('R shoulder 3/4', rot(np.pi + 0.75, 0.2), np.array([2.8, 16.2, 0.3]), 2.2)]
    S = 520
    sheet = Image.new('RGB', (S * len(shots), S * 2 + 30), 'white')
    for k, (name, R, c, h) in enumerate(shots):
        a = render(old, ot, R, c, h, S); b = render(new, nt, R, c, h, S, metal=True)
        ImageDraw.Draw(a).text((6, 6), 'OLD ' + name, fill=(0, 0, 0)); ImageDraw.Draw(b).text((6, 6), 'v2 ' + name, fill=(0, 0, 0))
        sheet.paste(a, (S * k, 0)); sheet.paste(b, (S * k, S + 30))
    sheet.save(sys.argv[1])
