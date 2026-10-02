"""Build Mech3.glb (19 named part nodes, one shared texture) and meta.json from source/mech_raw.glb.
Adapted from crimson/tools/build.py: same refine-then-label split, overlap band and inset caps.
Differences: wings are found as separate connected shells (they float behind the shoulders),
and the depth (Z) is boosted by ZS after splitting (owner rule: never flat; the raw Meshy torso was ~15% shallower than the sheet's side view)."""
import json, numpy as np, trimesh
from scipy.spatial import ConvexHull, cKDTree
from trimesh.remesh import subdivide
from glbio import load_raw, write_glb, dark_uv
import seg

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
ZS = 1.12            # depth boost applied after the split
WING_BACK = 0.6      # studs: slide the floating wing shells back so they rise from behind the shoulders (sheet), not beside them

pos, uv, nrm, idx, jpg, mime = load_raw(D + r'\source\mech_raw.glb')
FLIP = np.array([-1.0, 1.0, -1.0])          # raw faces +Z -> rotate 180 about Y so front = -Z
p = pos * FLIP; n = nrm * FLIP
S = 20.0 / (p[:, 1].max() - p[:, 1].min())
p = p * S; p[:, 1] -= p[:, 1].min()
cxz = (p.max(0) + p.min(0)) / 2; p[:, 0] -= cxz[0]; p[:, 2] -= cxz[2]
print('mech scale', S, 'bounds', p.min(0), p.max(0), 'tris', len(idx))

# ---- wings = the two big disconnected shells that sit in the wing zone
tm = trimesh.Trimesh(p, idx, process=False)
tm.merge_vertices(merge_tex=True, merge_norm=True)
comps = trimesh.graph.connected_components(tm.face_adjacency, nodes=np.arange(len(tm.faces)))
wingf = np.zeros(len(idx), bool)
for comp in comps:
    if len(comp) < 500:
        continue
    v = tm.vertices[np.unique(tm.faces[comp])]
    if v[:, 1].min() > 13.5 and np.abs(v[:, 0]).min() > 2.0:
        wingf[comp] = True
        print('wing shell', len(comp), v.min(0).round(2), v.max(0).round(2))
assert wingf.sum() > 2000


def vert_labels(pts, faces, fwing):
    vw = np.zeros(len(pts), bool); vw[faces[fwing].ravel()] = True
    return seg.label_points(pts, vw)


# ---- refine straddling triangles so the triangle-level split follows the cut planes
for it in range(2):
    vl = vert_labels(p, idx, wingf)
    fl = vl[idx]
    strad = np.where(((fl[:, 0] != fl[:, 1]) | (fl[:, 1] != fl[:, 2])) & ~wingf)[0]
    mask = np.zeros(len(idx), bool); mask[strad] = True
    p, idx, attr = subdivide(p, idx, face_index=strad, vertex_attributes={'uv': uv, 'n': n})
    uv, n = attr['uv'], attr['n']
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    wingf = np.concatenate([wingf[~mask], np.zeros(len(idx) - (~mask).sum(), bool)])
    print('refine', it, 'straddling', len(strad), 'tris now', len(idx))
vlab = vert_labels(p, idx, wingf)
clab = seg.label_points(p[idx].mean(1))
clab[wingf] = np.where(p[idx[wingf]].mean(1)[:, 0] >= 0, 'Wing_R', 'Wing_L')
cap_uv, cap_rgb = dark_uv(jpg)
print('cap texel', cap_uv, cap_rgb)

P = seg.P
CAPS = {   # part -> list of (y, side): side -1 cap faces down (cut below part), +1 faces up
    'Torso': [(P['waist_y'], -1)],
    'Pelvis': [(P['waist_y'], +1)],
    'UpperArm': [(P['elbow_y'], -1)],
    'Forearm': [(P['elbow_y'], +1), (P['wrist_y'], -1)],
    'Hand': [(P['wrist_y'], +1)],
    'Thigh': [(P['hip_y'], +1), (P['knee_y'], -1)],
    'Shin': [(P['knee_y'], +1), (P['ankle_y'], -1)],
    'Foot': [(P['ankle_y'], +1)],
}

parts_out, stats = [], {}
for name in seg.PARTS:
    core = clab == name
    dup = (vlab[idx] == name).any(1) & ~core     # overlap band: straddling triangles also kept
    fsel = np.where(core | dup)[0]
    F = idx[fsel]
    used, inv = np.unique(F.ravel(), return_inverse=True)
    pp, nn, tt = p[used], n[used], uv[used]
    FF = inv.reshape(-1, 3)
    ncap = 0
    for (cy, sd) in CAPS.get(name.split('_')[0], []):
        band = np.abs(pp[:, 1] - cy) < 0.3
        if band.sum() < 6:
            continue
        xz = pp[band][:, [0, 2]]
        try:
            hull = ConvexHull(xz)
        except Exception:
            continue
        ring = xz[hull.vertices]
        ctr = ring.mean(0)
        ring = ctr + (ring - ctr) * 0.93
        yc = cy + sd * -0.04               # sit just inside the part
        base = len(pp)
        cv = np.vstack([[ctr[0], yc, ctr[1]], np.column_stack([ring[:, 0], np.full(len(ring), yc), ring[:, 1]])])
        k = len(ring)
        tri = np.array([[0, 1 + i, 1 + (i + 1) % k] for i in range(k)])
        a, b, c = cv[tri[0]]
        if np.sign(np.cross(b - a, c - a)[1]) != sd:
            tri = tri[:, [0, 2, 1]]
        pp = np.vstack([pp, cv]); nn = np.vstack([nn, np.tile([0, sd, 0], (len(cv), 1))])
        tt = np.vstack([tt, np.tile(cap_uv, (len(cv), 1))])
        FF = np.vstack([FF, tri + base]); ncap += len(tri)
    if name.startswith('Wing'):
        pp = pp + [0, 0, WING_BACK]
    # depth boost (normals use the inverse-transpose scale)
    pp = pp * [1, 1, ZS]
    nn = nn / [1, 1, ZS]; nn = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    stats[name] = {'tris': int(len(FF)), 'core_tris': int(core.sum()), 'overlap_tris': int(dup.sum()), 'cap_tris': ncap,
                   'bbox_min': np.round(pp.min(0), 3).tolist(), 'bbox_max': np.round(pp.max(0), 3).tolist()}
    assert len(FF) < 20000, (name, len(FF))
    parts_out.append((name, pp, nn, tt, FF))

write_glb(D + r'\Mech3.glb', parts_out, jpg, mime)


# ---------------------------------------------------------------- pivots (computed in boosted space)
PV = {nm: pp for nm, pp, *_ in parts_out}


def band_centre(name, y0, y1, xlim=None):
    q = PV[name]
    m = (q[:, 1] >= y0) & (q[:, 1] <= y1)
    if xlim is not None:
        m &= (np.abs(q[:, 0]) >= xlim[0]) & (np.abs(q[:, 0]) <= xlim[1])
    q = q[m]
    return (q.min(0) + q.max(0)) / 2


def r3(a): return [round(float(x), 3) for x in a]


piv = {}
hc = band_centre('Head', P['neck_block_y'], P['neck_y']); piv['Neck'] = r3([0, P['neck_y'], hc[2]])
tc = band_centre('Torso', P['waist_y'], P['waist_y'] + 0.5); piv['Waist'] = r3([0, P['waist_y'], tc[2]])
body = np.vstack([PV[k] for k in ('Torso', 'ShoulderPad_L', 'ShoulderPad_R')])
for sd, sg in (('R', 1), ('L', -1)):
    w = PV['Wing_' + sd]
    yc = (w[:, 1].min() + w[:, 1].max()) / 2           # wing root = inner edge of the panel at mid-height, mid-depth
    m = np.abs(w[:, 1] - yc) < 0.4
    piv['WingRoot_' + sd] = [float(np.abs(w[m, 0]).min()) * sg, float(yc), float((w[m, 2].min() + w[m, 2].max()) / 2)]
    ua = band_centre('UpperArm_' + sd, 15.0, 16.1)
    piv['Shoulder_' + sd] = r3([ua[0], 15.6, ua[2]])
    pad = band_centre('ShoulderPad_' + sd, 16.15, 17.6)
    piv['ShoulderPad_' + sd] = r3([sg * P['pad_x'], 16.9, pad[2]])        # inner hinge where pad meets the collar
    e = band_centre('UpperArm_' + sd, P['elbow_y'] - 0.1, P['elbow_y'] + 0.4); piv['Elbow_' + sd] = r3([e[0], P['elbow_y'], e[2]])
    wr = band_centre('Forearm_' + sd, P['wrist_y'], P['wrist_y'] + 0.5); piv['Wrist_' + sd] = r3([wr[0], P['wrist_y'], wr[2]])
    th = band_centre('Thigh_' + sd, 10.4, 11.5, (0.6, 2.0)); piv['Hip_' + sd] = r3([th[0], 11.0, th[2]])
    k = band_centre('Shin_' + sd, P['knee_y'] - 0.6, P['knee_y']); piv['Knee_' + sd] = r3([k[0], P['knee_y'], k[2]])
    a = band_centre('Shin_' + sd, P['ankle_y'], P['ankle_y'] + 0.4); piv['Ankle_' + sd] = r3([a[0], P['ankle_y'], a[2]])

for j in ('WingRoot',):                               # mirror-average L/R so the pair flaps symmetrically
    a, b = np.array(piv[j + '_R']), np.array(piv[j + '_L'])
    avg = (np.abs(a) + np.abs(b)) / 2
    piv[j + '_R'] = r3([avg[0], avg[1], (a[2] + b[2]) / 2]); piv[j + '_L'] = r3([-avg[0], avg[1], (a[2] + b[2]) / 2])

meta = {
    'units': 'studs (1 glTF unit = 1 stud)', 'up': '+Y', 'front': '-Z', 'mech_right': '+X',
    'height': 20.0, 'source_scale': S, 'depth_boost_z': ZS, 'wing_shift_back': WING_BACK,
    'parts': stats, 'pivots': piv,
    'hierarchy': {
        'Pelvis': None, 'Torso': 'Pelvis', 'Head': 'Torso', 'Wing_L': 'Torso', 'Wing_R': 'Torso',
        'ShoulderPad_L': 'Torso', 'ShoulderPad_R': 'Torso', 'UpperArm_L': 'Torso', 'UpperArm_R': 'Torso',
        'Forearm_L': 'UpperArm_L', 'Forearm_R': 'UpperArm_R', 'Hand_L': 'Forearm_L', 'Hand_R': 'Forearm_R',
        'Thigh_L': 'Pelvis', 'Thigh_R': 'Pelvis', 'Shin_L': 'Thigh_L', 'Shin_R': 'Thigh_R', 'Foot_L': 'Shin_L', 'Foot_R': 'Shin_R'},
    'joint_of_part': {
        'Torso': 'Waist', 'Head': 'Neck', 'Wing_L': 'WingRoot_L', 'Wing_R': 'WingRoot_R',
        'ShoulderPad_L': 'ShoulderPad_L', 'ShoulderPad_R': 'ShoulderPad_R', 'UpperArm_L': 'Shoulder_L', 'UpperArm_R': 'Shoulder_R',
        'Forearm_L': 'Elbow_L', 'Forearm_R': 'Elbow_R', 'Hand_L': 'Wrist_L', 'Hand_R': 'Wrist_R',
        'Thigh_L': 'Hip_L', 'Thigh_R': 'Hip_R', 'Shin_L': 'Knee_L', 'Shin_R': 'Knee_R', 'Foot_L': 'Ankle_L', 'Foot_R': 'Ankle_R'},
    'wing_axes': {'flap': 'about +Z through WingRoot (positive = tip swings up/out on the R wing; mirror for L)',
                  'fold': 'about +Y through WingRoot (swings the panel back along the body)'},
}
json.dump(meta, open(D + r'\meta.json', 'w'), indent=2)
print(json.dumps(piv, indent=0))
for k2, s2 in stats.items(): print(k2, s2['tris'], s2['core_tris'], s2['overlap_tris'], s2['cap_tris'])
print('total', sum(s['tris'] for s in stats.values()))
