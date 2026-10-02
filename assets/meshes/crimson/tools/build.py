"""Build Crimson_Mech.glb (17 named part nodes, shared texture), Crimson_Blade.glb and meta.json."""
import json, struct, numpy as np, trimesh
from scipy.spatial import ConvexHull
from pygltflib import GLTF2
import seg

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\crimson'


def load_raw(fn):
    gl = GLTF2().load(fn)
    blob = gl.binary_blob()

    def acc(i):
        a = gl.accessors[i]; bv = gl.bufferViews[a.bufferView]
        ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a.componentType]
        off = (bv.byteOffset or 0) + (a.byteOffset or 0)
        arr = np.frombuffer(blob, dt, a.count * ncomp, off)
        return arr.reshape(a.count, ncomp) if ncomp > 1 else arr
    pr = gl.meshes[0].primitives[0]
    pos = acc(pr.attributes.POSITION).astype(float)
    uv = acc(pr.attributes.TEXCOORD_0).astype(float)
    nrm = acc(pr.attributes.NORMAL).astype(float)
    idx = acc(pr.indices).astype(np.int64).reshape(-1, 3)
    img = gl.images[0]; bv = gl.bufferViews[img.bufferView]
    jpg = blob[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength]
    return pos, uv, nrm, idx, jpg, img.mimeType


def write_glb(fn, parts, jpg, mime):
    """parts: list of (name, pos Nx3, nrm Nx3, uv Nx2, idx Mx3)."""
    blob = bytearray()
    bviews, accs, meshes, nodes = [], [], [], []

    def add_view(data, target=None):
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(data)
        bv = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
        if target: bv['target'] = target
        bviews.append(bv); return len(bviews) - 1

    for name, p, n, t, ix in parts:
        p = p.astype(np.float32); n = n.astype(np.float32); t = t.astype(np.float32); ix = ix.astype(np.uint32)
        a0 = len(accs)
        accs.append({'bufferView': add_view(p.tobytes(), 34962), 'componentType': 5126, 'count': len(p), 'type': 'VEC3',
                     'min': p.min(0).tolist(), 'max': p.max(0).tolist()})
        accs.append({'bufferView': add_view(n.tobytes(), 34962), 'componentType': 5126, 'count': len(n), 'type': 'VEC3'})
        accs.append({'bufferView': add_view(t.tobytes(), 34962), 'componentType': 5126, 'count': len(t), 'type': 'VEC2'})
        accs.append({'bufferView': add_view(ix.tobytes(), 34963), 'componentType': 5125, 'count': ix.size, 'type': 'SCALAR'})
        meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': a0, 'NORMAL': a0 + 1, 'TEXCOORD_0': a0 + 2},
                                                     'indices': a0 + 3, 'material': 0}]})
        nodes.append({'name': name, 'mesh': len(meshes) - 1})
    img_bv = add_view(bytes(jpg))
    while len(blob) % 4: blob.append(0)
    gj = {
        'asset': {'version': '2.0', 'generator': 'crimson build.py'},
        'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes, 'meshes': meshes,
        'materials': [{'name': 'CrimsonMat', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 0.8}}],
        'textures': [{'sampler': 0, 'source': 0}], 'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
        'images': [{'bufferView': img_bv, 'mimeType': mime}],
        'accessors': accs, 'bufferViews': bviews, 'buffers': [{'byteLength': len(blob)}],
    }
    js = json.dumps(gj, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(fn, 'wb').write(out)


def dark_uv(jpg):
    from PIL import Image
    import io
    from scipy.ndimage import uniform_filter
    im = np.asarray(Image.open(io.BytesIO(bytes(jpg))).convert('RGB')).astype(float)
    lum = im.mean(2)
    mean = uniform_filter(lum, 9); sq = uniform_filter(lum ** 2, 9)
    std = np.sqrt(np.maximum(sq - mean ** 2, 0))
    sat = im.max(2) - im.min(2)
    score = np.where((mean > 35) & (mean < 70) & (uniform_filter(sat, 9) < 18), std, 1e9)
    yy, xx = np.unravel_index(np.argmin(score), score.shape)
    H, W = lum.shape
    return np.array([(xx + 0.5) / W, (yy + 0.5) / H]), im[yy, xx]   # glTF uv origin top-left


# ---------------------------------------------------------------- mech
pos, uv, nrm, idx, jpg, mime = load_raw(D + r'\source\mech_raw.glb')
FLIP = np.array([-1.0, 1.0, -1.0])          # raw faces +Z -> rotate 180 about Y so front = -Z
p = pos * FLIP; n = nrm * FLIP
S = 20.0 / (p[:, 1].max() - p[:, 1].min())
p = p * S; p[:, 1] -= p[:, 1].min()
cxz = (p.max(0) + p.min(0)) / 2; p[:, 0] -= cxz[0]; p[:, 2] -= cxz[2]
print('mech scale', S, 'bounds', p.min(0), p.max(0), 'tris', len(idx))

# refine triangles that straddle a part boundary so the triangle-level split follows the cut lines closely
from trimesh.remesh import subdivide
for it in range(2):
    vl = seg.label_points(p)
    fl = vl[idx]
    strad = np.where((fl[:, 0] != fl[:, 1]) | (fl[:, 1] != fl[:, 2]))[0]
    p, idx, attr = subdivide(p, idx, face_index=strad, vertex_attributes={'uv': uv, 'n': n})
    uv, n = attr['uv'], attr['n']
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    print('refine', it, 'straddling', len(strad), 'tris now', len(idx))
clab = seg.label_points(p[idx].mean(1))
vlab = seg.label_points(p)
cap_uv, cap_rgb = dark_uv(jpg)
print('cap texel', cap_uv, cap_rgb)

P = seg.P
# horizontal cut planes to cap: part -> list of (y, side) side=-1 cap faces down (cut below part), +1 faces up
CAPS = {
    'Head': [(P['neck_y'], -1)],
    'Torso': [(P['waist_y'], -1)],
    'Pelvis': [(P['waist_y'], +1)],
    'UpperArm': [(P['elbow_y'], -1)],
    'Forearm': [(P['elbow_y'], +1), (P['wrist_y'], -1)],
    'Hand': [(P['wrist_y'], +1)],
    'Thigh': [(P['hipband_y'], +1), (P['knee_y'], -1)],
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
        band = np.abs(pp[:, 1] - cy) < 0.45
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
        # orient: normal should point +Y if sd=+1 else -Y
        a, b, c = cv[tri[0]]
        if np.sign(np.cross(b - a, c - a)[1]) != sd:
            tri = tri[:, [0, 2, 1]]
        pp = np.vstack([pp, cv]); nn = np.vstack([nn, np.tile([0, sd, 0], (len(cv), 1))])
        tt = np.vstack([tt, np.tile(cap_uv, (len(cv), 1))])
        FF = np.vstack([FF, tri + base]); ncap += len(tri)
    side = 'R' if name.endswith('_R') else ('L' if name.endswith('_L') else '')
    stats[name] = {'tris': int(len(FF)), 'core_tris': int(core.sum()), 'overlap_tris': int(dup.sum()), 'cap_tris': ncap,
                   'bbox_min': np.round(pp.min(0), 3).tolist(), 'bbox_max': np.round(pp.max(0), 3).tolist()}
    assert len(FF) < 20000, name
    parts_out.append((name, pp, nn, tt, FF))

write_glb(D + r'\Crimson_Mech.glb', parts_out, jpg, mime)


# ---------------------------------------------------------------- pivots
def band_centre(name, y0, y1):
    q = np.vstack([pp for nm, pp, *_ in parts_out if nm == name])
    m = (q[:, 1] >= y0) & (q[:, 1] <= y1)
    q = q[m]
    return (q.min(0) + q.max(0)) / 2


def r3(a): return [round(float(x), 3) for x in a]


piv = {}
hc = band_centre('Head', P['neck_y'], P['neck_y'] + 0.6); piv['Neck'] = r3([0, P['neck_y'], hc[2]])
tc = band_centre('Torso', P['waist_y'], P['waist_y'] + 0.6); piv['Waist'] = r3([0, P['waist_y'], tc[2]])
for sd, sg in (('R', 1), ('L', -1)):
    ua = band_centre('UpperArm_' + sd, 15.5, 17.6)
    piv['Shoulder_' + sd] = r3([sg * 4.45, 16.8, ua[2]])          # centre of the shoulder gear disc
    pad = band_centre('ShoulderPad_' + sd, 17.4, 20)
    piv['ShoulderPad_' + sd] = r3([sg * 2.0, 18.1, pad[2]])        # inner hinge where pad meets the collar
    e = band_centre('Forearm_' + sd, P['elbow_y'] - 0.6, P['elbow_y']); piv['Elbow_' + sd] = r3([e[0], P['elbow_y'], e[2]])
    w = band_centre('Forearm_' + sd, P['wrist_y'], P['wrist_y'] + 0.6); piv['Wrist_' + sd] = r3([w[0], P['wrist_y'], w[2]])
    th = band_centre('Thigh_' + sd, 11.0, 12.6); piv['Hip_' + sd] = r3([th[0], 12.2, th[2]])
    k = band_centre('Thigh_' + sd, P['knee_y'], P['knee_y'] + 1.0); piv['Knee_' + sd] = r3([k[0], 8.0, k[2]])
    a = band_centre('Shin_' + sd, P['ankle_y'], P['ankle_y'] + 0.6); piv['Ankle_' + sd] = r3([a[0], P['ankle_y'] + 0.1, a[2]])

# ---------------------------------------------------------------- blade
bpos, buv, bnrm, bidx, bjpg, bmime = load_raw(D + r'\source\blade_raw.glb')
hm = (bpos[:, 0] > 0.50) & (bpos[:, 0] < 0.84)                 # handle span (raw: blade along -X, handle +X)
grip = np.array([0.67, (bpos[hm, 1].min() + bpos[hm, 1].max()) / 2, (bpos[hm, 2].min() + bpos[hm, 2].max()) / 2])
BS = 10.0 / (bpos[:, 0].max() - bpos[:, 0].min())
q = (bpos - grip) * BS
R = lambda a: np.stack([a[:, 1], -a[:, 0], a[:, 2]], 1)          # rotZ(-90): raw -X -> +Y
bp, bn = R(q), R(bnrm)
write_glb(D + r'\Crimson_Blade.glb', [('Crimson_Blade', bp, bn, buv, bidx)], bjpg, bmime)
print('blade', bp.min(0), bp.max(0), len(bidx))

# suggested hand-grip location on the mech: centre of the right hand's fist
hr = band_centre('Hand_R', 7.3, 9.9)
meta = {
    'units': 'studs (1 glTF unit = 1 stud)', 'up': '+Y', 'front': '-Z', 'mech_right': '+X',
    'height': 20.0, 'source_scale': S,
    'parts': stats, 'pivots': piv,
    'blade': {'file': 'Crimson_Blade.glb', 'length': round(float(bp[:, 1].max() - bp[:, 1].min()), 3),
              'grip_origin': [0, 0, 0], 'blade_axis': '+Y', 'spine_side': '+X', 'edge_side': '-X',
              'bbox_min': r3(bp.min(0)), 'bbox_max': r3(bp.max(0)), 'tris': int(len(bidx)),
              'suggested_grip_in_mech_space_R': r3(hr), 'suggested_grip_in_mech_space_L': r3(hr * [-1, 1, 1])},
}
json.dump(meta, open(D + r'\meta.json', 'w'), indent=2)
print(json.dumps(piv, indent=0))
for k2, s2 in stats.items(): print(k2, s2['tris'], s2['core_tris'], s2['overlap_tris'], s2['cap_tris'])
