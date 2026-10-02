"""Mech3_v2.glb: the SAME 19 parts as Mech3.glb (same vertices, UVs and triangles) with
  * the cleaned metal base colour (retexture.py) + glTF PBR: metallicRoughnessTexture and normalTexture
  * two small geometry fixes so nothing floats:
      - ShoulderPad_L/R: the pad's lower outer flap (|x| > 2.9, y < 16.35) is pulled in onto the upper
        arm (it hung 0.25 studs outside it, sky showed through the slit)
      - Wing_L/R: slid 0.2 studs in toward the body so the panel's inner edge sits on the shoulder pad
        (min gap was 0.19); Mech3Builder adds a hinge bracket from the backpack to the wing root
Writes ../Mech3_v2.glb and meta_v2.json (pivots updated for the wing shift)."""
import json, struct, numpy as np
from pygltflib import GLTF2

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
WING_IN = 0.2
PAD_IN = 0.22


def load_parts(fn):
    gl = GLTF2().load(fn)
    blob = gl.binary_blob()

    def acc(i):
        a = gl.accessors[i]; bv = gl.bufferViews[a.bufferView]
        ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a.componentType]
        off = (bv.byteOffset or 0) + (a.byteOffset or 0)
        arr = np.frombuffer(blob, dt, a.count * ncomp, off)
        return (arr.reshape(a.count, ncomp) if ncomp > 1 else arr).copy()
    out = []
    for node in gl.nodes:
        pr = gl.meshes[node.mesh].primitives[0]
        out.append((node.name, acc(pr.attributes.POSITION).astype(float), acc(pr.attributes.NORMAL).astype(float),
                    acc(pr.attributes.TEXCOORD_0).astype(float), acc(pr.indices).astype(np.int64).reshape(-1, 3)))
    return out


def write_glb(fn, parts, images):
    """images: list of (png bytes) -> [basecolor, metalRough, normal]."""
    blob = bytearray(); bviews, accs, meshes, nodes = [], [], [], []

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
    imgs = [{'bufferView': add_view(b), 'mimeType': 'image/png'} for b in images]
    while len(blob) % 4: blob.append(0)
    gj = {
        'asset': {'version': '2.0', 'generator': 'mech3 build_v2.py'},
        'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes, 'meshes': meshes,
        'materials': [{'name': 'Mech3Metal',
                       'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicRoughnessTexture': {'index': 1},
                                                'metallicFactor': 1.0, 'roughnessFactor': 1.0},
                       'normalTexture': {'index': 2, 'scale': 1.0}}],
        'textures': [{'sampler': 0, 'source': i} for i in range(len(imgs))],
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
        'images': imgs, 'accessors': accs, 'bufferViews': bviews, 'buffers': [{'byteLength': len(blob)}],
    }
    js = json.dumps(gj, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(fn, 'wb').write(out)


# ---------------------------------------------------------------- cut caps
# v1's caps were inset convex hulls of the whole band of the part near the cut. Where the part's outline
# is concave (elbow ball + forearm guard flaps, knee) the hull stuck out of the surface as a thin flat
# plate - seen edge-on it was a dark line / spike at the joint. v2 drops them and caps each cut with the
# part's real cross-section at the cut plane: the mesh is sliced, the segments chained into closed loops,
# each loop ear-clipped. A cap then fills exactly the opening and never pokes outside.
CAP_UV = np.array([0.407959, 0.592529])
CUTS = {'Torso': [(12.4, -1)], 'Pelvis': [(12.4, 1)], 'UpperArm': [(13.85, -1)], 'Forearm': [(13.85, 1), (10.85, -1)],
        'Hand': [(10.85, 1)], 'Thigh': [(11.6, 1), (7.2, -1)], 'Shin': [(7.2, 1), (1.55, -1)], 'Foot': [(1.55, 1)]}


def strip_old_caps(p, n, t, ix):
    capv = (np.abs(np.abs(n[:, 1]) - 1) < 1e-6) & (np.abs(t - CAP_UV).max(1) < 1e-5)
    keep = ~capv[ix].all(1)
    ix = ix[keep]
    used, inv = np.unique(ix.ravel(), return_inverse=True)
    return p[used], n[used], t[used], inv.reshape(-1, 3), int((~keep).sum())


def section_loops(p, ix, y):
    """Closed loops (lists of xz points) where the plane y cuts the triangles."""
    T = p[ix]
    s = T[:, :, 1] - y
    segs = []
    for tri, sv in zip(T, s):
        pts = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            if (sv[a] > 0) != (sv[b] > 0):
                u = sv[a] / (sv[a] - sv[b])
                q = tri[a] + u * (tri[b] - tri[a])
                pts.append((q[0], q[2]))
        if len(pts) == 2:
            segs.append(pts)
    key = lambda q: (round(q[0], 4), round(q[1], 4))
    adj = {}
    for a, b in segs:
        ka, kb = key(a), key(b)
        if ka == kb:
            continue
        adj.setdefault(ka, []).append(kb); adj.setdefault(kb, []).append(ka)
    used = set(); loops = []
    for start in list(adj):
        if start in used or len(adj[start]) != 2:
            continue
        loop = [start]; used.add(start); prev, cur = None, start
        ok = False
        while True:
            nxt = [k for k in adj[cur] if k != prev]
            if not nxt or len(adj[cur]) != 2:
                break
            prev, cur = cur, nxt[0]
            if cur == start:
                ok = True; break
            if cur in used:
                break
            used.add(cur); loop.append(cur)
        if ok and len(loop) >= 3:
            loops.append(np.array(loop, float))
    return loops


def area2(P):
    x, z = P[:, 0], P[:, 1]
    return float(np.sum(x * np.roll(z, -1) - np.roll(x, -1) * z))


def ear_clip(P):
    """Triangulate a simple polygon (Nx2). Returns index triples (CCW) or None."""
    n = len(P)
    idx = list(range(n)) if area2(P) > 0 else list(range(n))[::-1]
    tris = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    guard = 0
    while len(idx) > 3 and guard < 20000:
        guard += 1
        m = len(idx); found = False
        for i in range(m):
            ia, ib, ic = idx[i - 1], idx[i], idx[(i + 1) % m]
            a, b, c = P[ia], P[ib], P[ic]
            if cross(a, b, c) <= 1e-12:
                continue
            inside = False
            for j in idx:
                if j in (ia, ib, ic):
                    continue
                q = P[j]
                if cross(a, b, q) >= 0 and cross(b, c, q) >= 0 and cross(c, a, q) >= 0:
                    inside = True; break
            if inside:
                continue
            tris.append((ia, ib, ic)); idx.pop(i); found = True
            break
        if not found:
            return None
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def point_tri_dist(q, T):
    """Distance from point q to each triangle in T (Mx3x3)."""
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    ab, ac, ap = b - a, c - a, q - a
    d1 = (ab * ap).sum(1); d2 = (ac * ap).sum(1)
    bp = q - b; d3 = (ab * bp).sum(1); d4 = (ac * bp).sum(1)
    cp = q - c; d5 = (ab * cp).sum(1); d6 = (ac * cp).sum(1)
    va = d3 * d6 - d5 * d4; vb = d5 * d2 - d1 * d6; vc = d1 * d4 - d3 * d2
    denom = np.where(np.abs(va + vb + vc) < 1e-12, 1e-12, va + vb + vc)
    v = vb / denom; w = vc / denom
    res = a + ab * v[:, None] + ac * w[:, None]
    # regions outside the face: fall back to the closest point on the three edges
    def seg(p0, p1):
        d = p1 - p0; tt = np.clip(((q - p0) * d).sum(1) / np.maximum((d * d).sum(1), 1e-12), 0, 1)
        return p0 + d * tt[:, None]
    inside = (va >= 0) & (vb >= 0) & (vc >= 0)
    cands = np.stack([seg(a, b), seg(b, c), seg(c, a)], 1)
    de = np.linalg.norm(cands - q, axis=2).min(1)
    di = np.linalg.norm(res - q, axis=1)
    return np.where(inside, di, de)


def drop_specks(p, n, t, ix, min_faces=12, gap=0.03):
    """Remove crumbs: tiny shells (< min_faces) that do not touch the rest of the part (every vertex
    further than `gap` from the other triangles). Tiny shells that touch are kept - the split's
    refinement leaves T-junctions, so many legit surface pieces are separate shells."""
    import trimesh
    m = trimesh.Trimesh(p, ix, process=False)
    m.merge_vertices(merge_tex=True, merge_norm=True)
    comps = trimesh.graph.connected_components(m.face_adjacency, nodes=np.arange(len(ix)), min_len=1)
    small = [c for c in comps if len(c) < min_faces]
    keep = np.ones(len(ix), bool)
    if small:
        smallmask = np.zeros(len(ix), bool)
        for c in small:
            smallmask[c] = True
        from scipy.spatial import cKDTree
        BT = p[ix[~smallmask]]
        cen = BT.mean(1)
        rad = np.linalg.norm(BT - cen[:, None], axis=2).max(1)
        tree = cKDTree(cen)
        for c in small:
            v = p[np.unique(ix[c])]
            dmin = np.inf
            for q in v:
                cand = tree.query_ball_point(q, rad.max() + gap)
                if cand:
                    dmin = min(dmin, point_tri_dist(q, BT[cand]).min())
            if dmin > gap:
                keep[c] = False
    ix = ix[keep]
    used, inv = np.unique(ix.ravel(), return_inverse=True)
    return p[used], n[used], t[used], inv.reshape(-1, 3), int((~keep).sum())


def drop_flap_strips(p, n, t, ix):
    """The upper arm carried a copy (overlap band) of the pad flap's bottom edge: thin flat strips at
    y 15.75, |x| > 2.9. With the flap pulled in, they would float outside as a dark speck - drop them."""
    import trimesh
    m = trimesh.Trimesh(p, ix, process=False)
    m.merge_vertices(merge_tex=True, merge_norm=True)
    comps = trimesh.graph.connected_components(m.face_adjacency, nodes=np.arange(len(ix)), min_len=1)
    keep = np.ones(len(ix), bool)
    for c in comps:
        v = p[ix[c]].reshape(-1, 3)
        if len(c) < 400 and np.ptp(v[:, 1]) < 0.08 and 15.68 < v[:, 1].mean() < 15.82 and np.abs(v[:, 0]).min() > 2.9:
            keep[c] = False
    ix = ix[keep]
    used, inv = np.unique(ix.ravel(), return_inverse=True)
    return p[used], n[used], t[used], inv.reshape(-1, 3), int((~keep).sum())


def dark_cap_uv():
    """A flat charcoal texel in the v2 base colour for the cut caps (v1's cap texel became navy plate)."""
    from PIL import Image
    from scipy import ndimage as ndi
    b = np.asarray(Image.open(D + '/v2/basecolor.png').convert('RGB')).astype(float)
    lum = b.mean(2)
    mean = ndi.uniform_filter(lum, 9); sq = ndi.uniform_filter(lum ** 2, 9)
    std = np.sqrt(np.maximum(sq - mean ** 2, 0))
    score = np.where((mean > 34) & (mean < 46), std, 1e9)
    yy, xx = np.unravel_index(np.argmin(score), score.shape)
    H, W = lum.shape
    print('cap texel', b[yy, xx])
    return np.array([(xx + 0.5) / W, (yy + 0.5) / H])


NEW_CAP_UV = None


def add_caps(name, p, n, t, ix):
    base = name.split('_')[0]
    added = 0
    for cy, sd in CUTS.get(base, []):
        yc = cy - sd * 0.03                      # just inside the part
        for loop in section_loops(p, ix, yc):
            # drop near-duplicate points
            keep = np.r_[True, np.linalg.norm(np.diff(loop, axis=0), axis=1) > 1e-3]
            loop = loop[keep]
            if len(loop) < 3 or abs(area2(loop)) / 2 < 0.004:
                continue
            tris = ear_clip(loop)
            if not tris:
                continue
            b0 = len(p)
            v3 = np.column_stack([loop[:, 0], np.full(len(loop), yc), loop[:, 1]])
            F = np.array(tris) + b0
            # orient: normal +Y if sd = +1 (cap faces up out of a part below the cut), else -Y
            a, b, c = v3[tris[0][0]], v3[tris[0][1]], v3[tris[0][2]]
            if np.sign(np.cross(b - a, c - a)[1]) != sd:
                F = F[:, [0, 2, 1]]
            p = np.vstack([p, v3]); n = np.vstack([n, np.tile([0, sd, 0], (len(v3), 1))])
            t = np.vstack([t, np.tile(NEW_CAP_UV, (len(v3), 1))]); ix = np.vstack([ix, F]); added += len(F)
    return p, n, t, ix, added


def smooth(x):
    x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)


parts = load_parts(D + r'\Mech3.glb')
out = []
NEW_CAP_UV = dark_cap_uv()
for name, p, n, t, ix in parts:
    p, n, t, ix, dropped = strip_old_caps(p, n, t, ix)
    p, n, t, ix, specks = drop_specks(p, n, t, ix)
    if specks:
        print(f'{name}: dropped {specks} speck tris')
    p, n, t, ix, added = add_caps(name, p, n, t, ix)
    if dropped or added:
        print(f'{name}: old cap tris {dropped} -> new {added}')
    if name.startswith('UpperArm'):
        p, n, t, ix, strips = drop_flap_strips(p, n, t, ix)
        print(f'{name}: dropped {strips} flap-overlap strip tris')
    p = p.copy()
    sg = 1.0 if name.endswith('_R') else -1.0
    if name.startswith('ShoulderPad'):
        ax = np.abs(p[:, 0])
        k = smooth((ax - 2.9) / 0.35) * smooth((16.35 - p[:, 1]) / 0.35)
        p[:, 0] -= sg * PAD_IN * k
    if name.startswith('Wing'):
        p[:, 0] -= sg * WING_IN
    out.append((name, p, n, t, ix))
imgs = [open(D + rf'\v2\{f}.png', 'rb').read() for f in ('basecolor', 'metal_rough', 'normal')]
write_glb(D + r'\Mech3_v2.glb', out, imgs)

meta = json.load(open(D + r'\meta.json'))
for sd, sg in (('R', 1), ('L', -1)):
    w = meta['pivots']['WingRoot_' + sd]
    meta['pivots']['WingRoot_' + sd] = [round(w[0] - sg * WING_IN, 3), w[1], w[2]]
for name, p, _n, _t, _ix in out:
    meta['parts'][name]['bbox_min'] = np.round(p.min(0), 3).tolist()
    meta['parts'][name]['bbox_max'] = np.round(p.max(0), 3).tolist()
    meta['parts'][name]['tris'] = int(len(_ix))
meta['v2'] = {'file': 'Mech3_v2.glb', 'wing_shift_in': WING_IN, 'pad_flap_in': PAD_IN,
              'material': 'PBR: baseColor (cleaned, no ink / dots) + metallicRoughness (G rough, B metal) + normal (panel-seam grooves)'}
json.dump(meta, open(D + r'\meta_v2.json', 'w'), indent=2)
print('wrote', D + r'\Mech3_v2.glb', 'wing roots', meta['pivots']['WingRoot_R'], meta['pivots']['WingRoot_L'])
