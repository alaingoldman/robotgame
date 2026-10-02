import json, numpy as np, trimesh
from PIL import Image, ImageDraw
from raster import render
import seg

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\crimson'
OUT = D + r'\renders'
sc = trimesh.load(D + r'\Crimson_Mech.glb', process=False)
meta = json.load(open(D + r'\meta.json'))
piv = meta['pivots']
tex = None
parts = {}
for node in sc.graph.nodes_geometry:
    T, gname = sc.graph[node]
    g = sc.geometry[gname]
    assert np.allclose(T, np.eye(4))
    if tex is None:
        tex = np.asarray(g.visual.material.baseColorTexture.convert('RGB'))
    H, W = tex.shape[:2]
    fuv = g.visual.uv[g.faces].mean(1)
    fc = tex[np.clip((1 - fuv[:, 1] % 1) * (H - 1), 0, H - 1).astype(int), np.clip((fuv[:, 0] % 1) * (W - 1), 0, W - 1).astype(int)]
    parts[node] = (np.asarray(g.vertices), np.asarray(g.faces), fc)
print(sorted(parts), sum(len(p[1]) for p in parts.values()))
assert set(parts) == set(seg.PARTS)


def code_col(n):
    c = np.array(seg.COL[n], float)
    return c * 0.7 if n.endswith('_L') else c


def sheet(items, fn, size=600):
    ims = [render(pl, vw, size, title=t) for pl, vw, t in items]
    im = Image.new('RGB', (size * len(ims), size), 'white')
    for i, x in enumerate(ims): im.paste(x, (size * i, 0))
    im.save(fn); return fn


views = ['front', 'side', 'threequarter', 'top']
coded = [(v, f, code_col(n)) for n, (v, f, _) in parts.items()]
textured = [(v, f, c) for n, (v, f, c) in parts.items()]
sheet([(coded, vw, 'parts: ' + vw) for vw in views], OUT + r'\Crimson_parts_views.png')
sheet([(textured, vw, 'textured: ' + vw) for vw in views], OUT + r'\Crimson_textured_views.png')

# legend + tri counts
lg = Image.new('RGB', (520, 24 * len(seg.PARTS) + 40), 'white'); d = ImageDraw.Draw(lg)
d.text((8, 8), 'part (tris in GLB, < 20000 each)', fill=(0, 0, 0))
for i, n in enumerate(seg.PARTS):
    y = 32 + 24 * i
    d.rectangle([8, y, 28, y + 16], fill=tuple(int(c) for c in code_col(n)))
    d.text((36, y + 2), f"{n}: {meta['parts'][n]['tris']}", fill=(0, 0, 0))
lg.save(OUT + r'\Crimson_parts_legend.png')


# ---- posed test
def rot(axis, deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    x, y, z = axis
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])

# chain: (part, parent joint list). Each joint: (pivot name, axis, degrees). +X axis rotation = swing limb forward (-Z).
pose = {
    'R': {'Shoulder': ((1, 0, 0), 25), 'Elbow': ((1, 0, 0), 40), 'Wrist': ((1, 0, 0), 15),
          'Hip': ((1, 0, 0), 35), 'Knee': ((1, 0, 0), -45), 'Ankle': ((1, 0, 0), 15)},
    'L': {'Shoulder': ((0, 0, 1), -30), 'Elbow': ((1, 0, 0), 40), 'Wrist': ((1, 0, 0), 0),
          'Hip': ((1, 0, 0), -10), 'Knee': ((1, 0, 0), -40), 'Ankle': ((1, 0, 0), 0)},
}
chains = {'UpperArm': ['Shoulder'], 'Forearm': ['Shoulder', 'Elbow'], 'Hand': ['Shoulder', 'Elbow', 'Wrist'],
          'Thigh': ['Hip'], 'Shin': ['Hip', 'Knee'], 'Foot': ['Hip', 'Knee', 'Ankle']}


def posed(colfn):
    out = []
    for n, (v, f, c) in parts.items():
        base, _, sd = n.partition('_')
        vv = v.copy()
        if base in chains:
            # apply innermost joint first, then propagate outward joints (child-to-root order)
            for j in reversed(chains[base]):
                axis, deg = pose[sd][j]
                pv = np.array(piv[j + '_' + sd])
                # pivot of joint j itself must be transformed by its ancestors: handled because we apply
                # child joints first in rest space, then parents rotate everything (including child pivots).
                vv = (vv - pv) @ rot(axis, deg).T + pv
        out.append((vv, f, colfn(n, c)))
    return out


pc = posed(lambda n, c: code_col(n))
pt = posed(lambda n, c: c)
sheet([(pc, 'front', 'posed parts: front'), (pc, 'side', 'posed parts: side'), (pt, 'threequarter', 'posed textured: 3/4'),
       (pt, 'side', 'posed textured: side')], OUT + r'\Crimson_posed_test.png')

# close-ups of elbow and knee bends (right side, textured), from the side
def crop_parts(lst, lo, hi):
    res = []
    for v, f, c in lst:
        m = ((v[f] >= lo) & (v[f] <= hi)).all(2).all(1)
        if m.any(): res.append((v, f[m], np.asarray(c)[m] if np.ndim(c) == 2 else c))
    return res

el = crop_parts(pt, np.array([3.0, 8.0, -6]), np.array([9.0, 17.5, 6]))
kn = crop_parts(pt, np.array([0.5, 3.5, -6]), np.array([6.0, 12.5, 6]))
sheet([(el, 'side', 'R elbow 40 (shoulder 25)'), (el, 'threequarter', 'R elbow 3/4'),
       (kn, 'side', 'R knee -45 (hip 35)'), (kn, 'threequarter', 'R knee 3/4')], OUT + r'\Crimson_joint_closeups.png')
print('done')
