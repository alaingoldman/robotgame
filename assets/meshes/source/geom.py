import json, numpy as np, os
D = os.path.dirname(os.path.abspath(__file__))
raw = json.loads(json.load(open(os.path.join(D, 'raw.json'), encoding='utf-8'))['returnValue'])
U = 0.48 * raw['scale']

def cf(c):
    p = np.array(c[:3]); R = np.array(c[3:]).reshape(3, 3)
    return p, R

def wedge_faces(part):
    sx, sy, sz = part['size']; p, R = cf(part['cf'])
    loc = np.array([[0, -sy/2, -sz/2], [0, -sy/2, sz/2], [0, sy/2, sz/2]])  # bottom-front, bottom-back (right angle), top-back
    faces = []
    for s in (1, -1):
        l = loc.copy(); l[:, 0] = s * sx / 2
        faces.append((l @ R.T) + p)
    return faces, R[:, 0], p, sx

def extract(group, names, centre=None, out_fn=None):
    parts = [q for q in raw['groups'][group] if q['class'] == 'WedgePart' and q['name'] in names]
    if centre is None:
        centre = np.mean([cf(q['cf'])[0] for q in parts], axis=0)
    wedges = []
    for q in parts:
        faces, xax, p, t = wedge_faces(q)
        outdir = out_fn(q, p) if out_fn else (p - centre)
        if np.dot(xax, outdir) >= 0:
            tri, n = faces[0], xax
        else:
            tri, n = faces[1], -xax
        wedges.append(dict(tri=tri, foot=tri[1], n=n, t=t, name=q['name'], role=q['role'], bone=q['bone']))
    # pair by foot
    byfoot = {}
    for w in wedges:
        k = tuple(np.round(w['foot'], 3))
        byfoot.setdefault(k, []).append(w)
    tris = []
    unpaired = 0
    for k, ws in byfoot.items():
        if len(ws) == 2:
            a, b = ws
            pts = [a['tri'][0], a['tri'][2]]
            for v in (b['tri'][0], b['tri'][2]):
                if min(np.linalg.norm(v - x) for x in pts) > 1e-3:
                    pts.append(v)
            if len(pts) != 3:
                # one wedge degenerate: fall back to both triangles
                for w in ws:
                    tris.append(dict(v=w['tri'], n=w['n'], t=w['t'], name=w['name'], role=w['role']))
                continue
            tris.append(dict(v=np.array(pts), n=a['n'], t=a['t'], name=a['name'], role=a['role']))
        else:
            unpaired += len(ws)
            for w in ws:
                tris.append(dict(v=w['tri'], n=w['n'], t=w['t'], name=w['name'], role=w['role']))
    # orient CCW seen from outside
    for T in tris:
        v = T['v']; nn = np.cross(v[1] - v[0], v[2] - v[0])
        if np.dot(nn, T['n']) < 0:
            T['v'] = v[[0, 2, 1]]
    bones = {w['bone'] for w in wedges}
    return tris, unpaired, bones, centre

def weld(tris, tol=0.01):
    verts = []; idx = []; grid = {}
    def find(p):
        k = tuple(np.floor(p / tol).astype(int))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for i in grid.get((k[0]+dx, k[1]+dy, k[2]+dz), []):
                        if np.linalg.norm(verts[i] - p) < tol:
                            return i
        verts.append(p.copy()); grid.setdefault(k, []).append(len(verts) - 1)
        return len(verts) - 1
    F = []
    for T in tris:
        f = [find(p) for p in T['v']]
        if len(set(f)) == 3:
            F.append(f)
        else:
            F.append(None)
    return np.array(verts), F

if __name__ == '__main__':
    hc = np.array([0, (2.75 + 0.6 - 2.2) * U, 0.1 * U])
    for g, names, c in [('PadR', {'PadShell'}, None), ('PadL', {'PadShell'}, None),
                        ('Dome', {'ChestPlate', 'ChestCrescent', 'ChestLower', 'ChestSide'}, 'dome'),
                        ('Helmet', {'HelmetShell'}, hc), ('Helmet', {'HelmetCap'}, hc)]:
        if isinstance(c, str):
            parts = [q for q in raw['groups'][g] if q['name'] in names]
            c = np.mean([cf(q['cf'])[0] for q in parts], axis=0) + np.array([0, 0, 3.0])
        tris, un, bones, _ = extract(g, names, c)
        V, F = weld([t for t in tris])
        Fv = [f for f in F if f]
        from collections import Counter
        ec = Counter()
        for f in Fv:
            for i in range(3):
                ec[tuple(sorted((f[i], f[(i+1)%3])))] += 1
        print(g, names, 'tris', len(tris), 'unpaired', un, 'bones', bones, 'verts', len(V), 'deg', len(F)-len(Fv),
              'boundary', sum(1 for v in ec.values() if v == 1), 'nonmanifold', sum(1 for v in ec.values() if v > 2),
              'roles', Counter(t['role'] for t in tris), 'thick', sorted({round(t['t'],3) for t in tris}))
