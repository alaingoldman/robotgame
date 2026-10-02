import json, numpy as np, trimesh
from PIL import Image, ImageDraw
from raster import render
import seg

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
OUT = D + r'\renders'
sc = trimesh.load(D + r'\Mech3.glb', process=False)
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


views = ['front', 'side', 'threequarter', 'top', 'back']
coded = [(v, f, code_col(n)) for n, (v, f, _) in parts.items()]
textured = [(v, f, c) for n, (v, f, c) in parts.items()]
sheet([(coded, vw, 'parts: ' + vw) for vw in views], OUT + r'\Mech3_parts_views.png')
sheet([(textured, vw, 'textured: ' + vw) for vw in views], OUT + r'\Mech3_textured_views.png')

# legend + tri counts
lg = Image.new('RGB', (520, 24 * len(seg.PARTS) + 40), 'white'); d = ImageDraw.Draw(lg)
d.text((8, 8), 'part (tris in GLB, < 20000 each)', fill=(0, 0, 0))
for i, n in enumerate(seg.PARTS):
    y = 32 + 24 * i
    d.rectangle([8, y, 28, y + 16], fill=tuple(int(c) for c in code_col(n)))
    d.text((36, y + 2), f"{n}: {meta['parts'][n]['tris']}", fill=(0, 0, 0))
lg.save(OUT + r'\Mech3_parts_legend.png')


# ---- posed test
def rot(axis, deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    x, y, z = axis
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])

# chain: (part, parent joint list). Each joint: (pivot name, axis, degrees). +X axis rotation = swing limb forward (-Z).
pose = {   # spec: elbows and knees 40 deg, wings swung 30 deg; plus a little shoulder/hip so the bends read
    'R': {'Shoulder': ((1, 0, 0), 20), 'Elbow': ((1, 0, 0), 40), 'Wrist': ((1, 0, 0), 0),
          'Hip': ((1, 0, 0), 30), 'Knee': ((1, 0, 0), -40), 'Ankle': ((1, 0, 0), 10)},
    'L': {'Shoulder': ((0, 0, 1), -25), 'Elbow': ((1, 0, 0), 40), 'Wrist': ((1, 0, 0), 0),
          'Hip': ((1, 0, 0), -10), 'Knee': ((1, 0, 0), -40), 'Ankle': ((1, 0, 0), 0)},
}
WING = {'R': ((0, 0, 1), 30), 'L': ((0, 0, 1), -30)}     # flap: tips swing up/out
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
        if base == 'Wing':
            axis, deg = WING[sd]; pv = np.array(piv['WingRoot_' + sd])
            vv = (vv - pv) @ rot(axis, deg).T + pv
        out.append((vv, f, colfn(n, c)))
    return out


pc = posed(lambda n, c: code_col(n))
pt = posed(lambda n, c: c)
sheet([(pc, 'front', 'posed parts: front'), (pc, 'side', 'posed parts: side'), (pt, 'threequarter', 'posed textured: 3/4'),
       (pt, 'side', 'posed textured: side')], OUT + r'\Mech3_posed_test.png')

# close-ups of elbow and knee bends (right side), selected by part
def pick(lst, names):
    return [it for (n, _), it in zip(parts.items(), lst) if n in names]

el = pick(pt, {'UpperArm_R', 'Forearm_R', 'Hand_R'})
kn = pick(pt, {'Thigh_R', 'Shin_R', 'Foot_R'})
wg = pick(pt, {'Wing_R', 'Wing_L', 'Torso', 'ShoulderPad_R', 'ShoulderPad_L', 'Head'})
sheet([(el, 'side', 'R elbow 40 (shoulder 20)'), (el, 'threequarter', 'R elbow 3/4'),
       (kn, 'side', 'R knee 40 (hip 30)'), (kn, 'threequarter', 'R knee 3/4'),
       (wg, 'back', 'wings flapped 30: back'), (wg, 'top', 'wings flapped 30: top')], OUT + r'\Mech3_joint_closeups.png')

# sheet vs model, same order as the owner's turnaround (front, side from mech right, back)
from PIL import Image as _I
src = D + r'\source'
row1 = [_I.open(src + '/view_' + k + '.png').convert('RGB').resize((600, 600)) for k in ('front', 'side', 'back')]
row2 = [render(textured, vw, 600, title='model ' + vw) for vw in ('front', 'side', 'back')]
cmp_ = _I.new('RGB', (1800, 1200), 'white')
for i2, x in enumerate(row1): cmp_.paste(x, (600 * i2, 0))
for i2, x in enumerate(row2): cmp_.paste(x, (600 * i2, 600))
cmp_.save(OUT + r'\Mech3_vs_sheet.png')
print('done')
