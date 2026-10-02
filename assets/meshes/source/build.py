import json, os, numpy as np
from collections import Counter, defaultdict
from geom import raw, U, cf, extract, weld

D = os.path.dirname(os.path.abspath(__file__))
OUT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes'
TILE = 4.0  # studs per texture repeat (MechPattern Crosshatch largeTile)
CREASE = np.cos(np.radians(40))


def tri_normals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    a = np.linalg.norm(n, axis=1)
    return n / a[:, None], a / 2


def components(F, nv):
    par = list(range(nv))

    def f(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for t in F:
        for i in range(3):
            a, b = f(t[i]), f(t[(i + 1) % 3])
            par[a] = b
    return np.array([f(t[0]) for t in F])


def local2d(P):
    e1 = P[1] - P[0]
    L = np.linalg.norm(e1)
    e1 = e1 / L
    n = np.cross(P[1] - P[0], P[2] - P[0])
    n /= np.linalg.norm(n)
    e2 = np.cross(n, e1)
    return np.array([[0, 0], [L, 0], [np.dot(P[2] - P[0], e1), np.dot(P[2] - P[0], e2)]])


def lscm(V, F):
    nv = len(V)
    rows = []
    for t in F:
        q = local2d(V[t])
        z = q[:, 0] + 1j * q[:, 1]
        A2 = abs((q[1, 0] - q[0, 0]) * (q[2, 1] - q[0, 1]) - (q[1, 1] - q[0, 1]) * (q[2, 0] - q[0, 0]))
        W = [z[2] - z[1], z[0] - z[2], z[1] - z[0]]
        r = np.zeros(nv, complex)
        for j in range(3):
            r[t[j]] = W[j] / np.sqrt(A2)
        rows.append(r)
    M = np.array(rows)
    used = np.unique(F)
    P = V[used]
    d = np.linalg.norm(P[:, None] - P[None], axis=2)
    i, j = np.unravel_index(np.argmax(d), d.shape)
    pin = {int(used[i]): 0 + 0j, int(used[j]): d[i, j] + 0j}
    free = [k for k in range(nv) if k not in pin]
    Mf = M[:, free]
    b = -sum(M[:, k] * v for k, v in pin.items())
    A = np.block([[Mf.real, -Mf.imag], [Mf.imag, Mf.real]])
    bb = np.concatenate([b.real, b.imag])
    x = np.linalg.lstsq(A, bb, rcond=None)[0]
    uv = np.zeros((nv, 2))
    n = len(free)
    uv[free, 0] = x[:n]
    uv[free, 1] = x[n:]
    for k, v in pin.items():
        uv[k] = [v.real, v.imag]
    return uv


def signed_areas(uv, F):
    a = uv[F[:, 1]] - uv[F[:, 0]]
    b = uv[F[:, 2]] - uv[F[:, 0]]
    return (a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0]) / 2


def arap(V, F, uv, iters=300):
    nv = len(V)
    used = np.unique(F)
    loc = [local2d(V[t]) for t in F]
    W = np.zeros((nv, nv))
    C = []
    for t, q in zip(F, loc):
        c = np.zeros(3)
        for k in range(3):
            i, j = t[(k + 1) % 3], t[(k + 2) % 3]
            qi, qj, qo = q[(k + 1) % 3], q[(k + 2) % 3], q[k]
            a, b = qi - qo, qj - qo
            cot = np.dot(a, b) / abs(a[0] * b[1] - a[1] * b[0])
            c[k] = cot
            W[i, j] += cot / 2
            W[j, i] += cot / 2
        C.append(c)
    L = np.diag(W.sum(1)) - W
    fix = used[0]
    Lr = L.copy()
    Lr[fix] = 0
    Lr[fix, fix] = 1
    unused = np.setdiff1d(np.arange(nv), used)
    for k in unused:
        Lr[k] = 0
        Lr[k, k] = 1
    Linv = np.linalg.inv(Lr)
    for _ in range(iters):
        Rs = []
        for t, q, c in zip(F, loc, C):
            S = np.zeros((2, 2))
            for k in range(3):
                i, j = (k + 1) % 3, (k + 2) % 3
                S += c[k] * np.outer(uv[t[i]] - uv[t[j]], q[i] - q[j])
            Uu, s, Vt = np.linalg.svd(S)
            R = Uu @ Vt
            if np.linalg.det(R) < 0:
                Uu[:, 1] *= -1
                R = Uu @ Vt
            Rs.append(R)
        b = np.zeros((nv, 2))
        for t, q, c, R in zip(F, loc, C, Rs):
            for k in range(3):
                i, j = (k + 1) % 3, (k + 2) % 3
                d = c[k] / 2 * (R @ (q[i] - q[j]))
                b[t[i]] += d
                b[t[j]] -= d
        b[fix] = uv[fix]
        for k in unused:
            b[k] = uv[k]
        uv = Linv @ b
    return uv


def stretch(V, F, uv):
    out = []
    for t in F:
        q = local2d(V[t])
        u = uv[t]
        Q = np.array([q[1] - q[0], q[2] - q[0]]).T
        Uu = np.array([u[1] - u[0], u[2] - u[0]]).T
        J = Uu @ np.linalg.inv(Q)
        out.append(np.linalg.svd(J, compute_uv=False))
    return np.array(out)


SEAM = np.cos(np.radians(60))  # creases sharper than this split UV islands

# Roblox box-mapping frames (TitanPattern FACE table): axis -> (u axis, v axis) as signed unit vectors
BOX = {
    (2, -1): (np.array([-1, 0, 0]), np.array([0, -1, 0])),  # Front (-Z)
    (2, 1): (np.array([1, 0, 0]), np.array([0, -1, 0])),    # Back (+Z)
    (0, 1): (np.array([0, 0, -1]), np.array([0, -1, 0])),   # Right (+X)
    (0, -1): (np.array([0, 0, 1]), np.array([0, -1, 0])),   # Left (-X)
    (1, 1): (np.array([-1, 0, 0]), np.array([0, 0, -1])),   # Top (+Y)
    (1, -1): (np.array([0, 0, -1]), np.array([-1, 0, 0])),  # Bottom (-Y)
}


def islands(F, n, V=None, seam_fn=None):
    emap = defaultdict(list)
    for fi, t in enumerate(F):
        for k in range(3):
            emap[tuple(sorted((t[k], t[(k + 1) % 3])))].append(fi)
    lab = -np.ones(len(F), int)
    cur = 0
    for s in range(len(F)):
        if lab[s] >= 0:
            continue
        stack = [s]
        lab[s] = cur
        while stack:
            f = stack.pop()
            t = F[f]
            for k in range(3):
                fs = emap[tuple(sorted((t[k], t[(k + 1) % 3])))]
                if len(fs) != 2:
                    continue
                g = fs[0] if fs[1] == f else fs[1]
                ea, eb = t[k], t[(k + 1) % 3]
                if seam_fn is not None and seam_fn(V[ea], V[eb]):
                    continue
                if lab[g] < 0 and np.dot(n[f], n[g]) >= SEAM:
                    lab[g] = cur
                    stack.append(g)
        cur += 1
    return lab


def unwrap(V, F, seam_fn=None):
    """Seams at creases > 60 deg; each island: LSCM -> ARAP (near-isometric, studs),
    then rotated + translated onto the Roblox box-mapping projection of its dominant
    axis (same frame a flat part's Texture would use). Returns per-corner UVs."""
    F = np.array(F)
    n, a = tri_normals(V, F)
    lab = islands(F, n, V, seam_fn)
    cuv = np.zeros((len(F), 3, 2))
    report = []
    for l in np.unique(lab):
        idx = np.where(lab == l)[0]
        Fi = F[idx]
        vi = np.unique(Fi)
        remap = {int(v): k for k, v in enumerate(vi)}
        Vl = V[vi]
        Fl = np.array([[remap[int(x)] for x in t] for t in Fi])
        if len(Fl) == 1:
            u1 = local2d(Vl[Fl[0]])
            u1 = u1[np.argsort(Fl[0])] if False else u1
            tmp = np.zeros((len(Vl), 2))
            for k in range(3):
                tmp[Fl[0][k]] = u1[k]
            u1 = tmp
        else:
            u0 = lscm(Vl, Fl)
            if signed_areas(u0, Fl).sum() < 0:
                u0[:, 0] *= -1
            u0 *= np.sqrt(tri_normals(Vl, Fl)[1].sum() / abs(signed_areas(u0, Fl).sum()))
            u1 = arap(Vl, Fl, u0)
        if signed_areas(u1, Fl).sum() < 0:
            u1[:, 0] *= -1
        st = stretch(Vl, Fl, u1)
        nm = (n[idx] * a[idx, None]).sum(0)
        ax = int(np.argmax(np.abs(nm)))
        ua, va = BOX[(ax, int(np.sign(nm[ax])))]
        tgt = np.stack([Vl @ ua, Vl @ va], 1)
        w = np.zeros(len(Vl))
        for t, ar in zip(Fl, a[idx]):
            w[t] += ar
        w /= w.sum()

        def fit(u):
            mu, mt = (u * w[:, None]).sum(0), (tgt * w[:, None]).sum(0)
            H = ((u - mu) * w[:, None]).T @ (tgt - mt)
            Uu, s, Vt = np.linalg.svd(H)
            return mu, mt, (Uu @ Vt).T
        mu, mt, Rm = fit(u1)
        if np.linalg.det(Rm) < 0:
            u1[:, 0] *= -1
            mu, mt, Rm = fit(u1)
        ul = (u1 - mu) @ Rm.T + mt
        for j, fi in enumerate(idx):
            cuv[fi] = ul[Fl[j]]
        sa = signed_areas(ul, Fl)
        report.append(dict(tris=int(len(Fl)), axis='XYZ'[ax] + ('+' if nm[ax] > 0 else '-'),
                           stretch_min=round(float(st.min()), 3), stretch_max=round(float(st.max()), 3),
                           flipped=int((sa * np.sign(sa.sum()) <= 0).sum())))
    return cuv, lab, report


def front_ref(V, F, n, a):
    """front view: u = -x (viewer's right looking at the -Z face), v = -y (texture v runs down)"""
    tg = [np.stack([-V[t][:, 0], -V[t][:, 1]], 1) for t in F]
    w = a * np.clip(-n[:, 2], 0, None) ** 2
    if w.sum() < 1e-6:
        tg = [np.stack([V[t][:, 0], -V[t][:, 1]], 1) for t in F]  # back faces
        w = a * np.clip(n[:, 2], 0, None) ** 2
    return tg, w


def top_ref(V, F, n, a):
    tg = [np.stack([-V[t][:, 0], V[t][:, 2]], 1) for t in F]
    w = a * np.clip(n[:, 1], 0, None) ** 2
    return tg, w


# ---------------- shell (thickness, rims, normals) ----------------

def build_shell(V, F, thick, uv, roles):
    F = np.array(F)
    n, a = tri_normals(V, F)
    nv = len(V)
    inc = defaultdict(list)
    for fi, t in enumerate(F):
        for k in t:
            inc[k].append(fi)
    inner = V.copy()
    for v in range(nv):
        fs = inc[v]
        if not fs:
            continue
        N = n[fs]
        T = thick[fs]
        avg = (N * a[fs, None]).sum(0)
        avg /= np.linalg.norm(avg)
        tm = float(np.mean(T))
        A = np.vstack([N, 0.05 * np.eye(3)])
        b = np.concatenate([T, 0.05 * avg * tm])
        d = np.linalg.lstsq(A, b, rcond=None)[0]
        if np.linalg.norm(d) > 3 * tm or np.dot(d, avg) <= 0:
            d = avg * tm
        inner[v] = V[v] - d
    ec = Counter()
    for t in F:
        for k in range(3):
            ec[tuple(sorted((t[k], t[(k + 1) % 3])))] += 1
    bnd = []
    for fi, t in enumerate(F):
        for k in range(3):
            i, j = t[k], t[(k + 1) % 3]
            if ec[tuple(sorted((i, j)))] == 1:
                bnd.append((int(i), int(j), fi))
    P = list(V) + list(inner)
    # uv: per-corner (F x 3 x 2), lab: island per face; one vt per (island, vertex)
    uv, lab = uv
    UVs, ukey = [], {}

    def uvi(fi, k):
        key = (int(lab[fi]), int(F[fi][k]))
        if key not in ukey:
            ukey[key] = len(UVs)
            UVs.append(uv[fi][k])
        return ukey[key]
    faces = []
    for fi, t in enumerate(F):
        t = [int(x) for x in t]
        u = [uvi(fi, k) for k in range(3)]
        faces.append(([t[0], t[1], t[2]], u, roles[fi], 'outer'))
        faces.append(([t[0] + nv, t[2] + nv, t[1] + nv], [u[0], u[2], u[1]], roles[fi], 'inner'))
    for i, j, fi in bnd:
        ki, kj = list(F[fi]).index(i), list(F[fi]).index(j)
        ui, uj = uv[fi][ki], uv[fi][kj]
        uo = uv[fi][3 - ki - kj]
        e = uj - ui
        L = np.linalg.norm(e)
        perp = np.array([e[1], -e[0]]) / max(L, 1e-9)
        if np.dot(uo - ui, perp) > 0:
            perp = -perp
        tt = thick[fi] / TILE
        base = len(UVs)
        UVs += [ui, uj, uj + perp * tt, ui + perp * tt]
        # outer edge i->j is CCW in its face; the rim faces outward across the edge
        faces.append(([i, j + nv, j], [base, base + 2, base + 1], roles[fi], 'rim'))
        faces.append(([i, i + nv, j + nv], [base, base + 3, base + 2], roles[fi], 'rim'))
    return np.array(P), np.array(UVs), faces


def corner_normals(P, faces):
    Fi = np.array([f[0] for f in faces])
    n, a = tri_normals(P, Fi)
    inc = defaultdict(list)
    for k, t in enumerate(Fi):
        for v in t:
            inc[v].append(k)
    cn = []
    for k, t in enumerate(Fi):
        row = []
        for v in t:
            fs = [f for f in inc[v] if np.dot(n[f], n[k]) >= CREASE and faces[f][3] == faces[k][3]]
            s = (n[fs] * a[fs, None]).sum(0)
            row.append(s / np.linalg.norm(s))
        cn.append(row)
    return np.array(cn)


def write_obj(path, name, P, UVs, faces, cn, roles, header):
    sel = [k for k, f in enumerate(faces) if f[2] in roles]
    vmap, tmap, nlist, nmap = {}, {}, [], {}
    lines_f = []
    for k in sel:
        vs, ts, _, _ = faces[k]
        idx = []
        for c in range(3):
            v, t = vs[c], ts[c]
            if v not in vmap:
                vmap[v] = len(vmap) + 1
            if t not in tmap:
                tmap[t] = len(tmap) + 1
            nk = tuple(np.round(cn[k][c], 5))
            if nk not in nmap:
                nmap[nk] = len(nmap) + 1
                nlist.append(nk)
            idx.append(f'{vmap[v]}/{tmap[t]}/{nmap[nk]}')
        lines_f.append('f ' + ' '.join(idx))
    vs = sorted(vmap, key=vmap.get)
    ts = sorted(tmap, key=tmap.get)
    Pv = P[vs]
    ctr = (Pv.min(0) + Pv.max(0)) / 2
    with open(path, 'w', newline='\n') as fh:
        fh.write(header)
        fh.write('# vertices centred on their bounding box: place the MeshPart at bone.CFrame * CFrame.new(%.4f, %.4f, %.4f)\n' % tuple(ctr))
        fh.write(f'o {name}\n')
        for v in vs:
            fh.write('v {:.5f} {:.5f} {:.5f}\n'.format(*(P[v] - ctr)))
        for t in ts:
            fh.write('vt {:.5f} {:.5f}\n'.format(UVs[t][0], 1 - UVs[t][1]))  # OBJ v runs up, ours runs down
        for nn in nlist:
            fh.write('vn {:.5f} {:.5f} {:.5f}\n'.format(*nn))
        fh.write('s off\n')
        fh.write('\n'.join(lines_f) + '\n')
    Pv = P[vs]
    lo, hi = Pv.min(0), Pv.max(0)
    return dict(file=os.path.basename(path), tris=len(sel), verts=len(vs), bbox_min=lo.tolist(), bbox_max=hi.tolist(),
                centre=((lo + hi) / 2).tolist(), size=(hi - lo).tolist())


def process(group, names, centre, ref, outputs, label):
    tris, un, bones, _ = extract(group, names, centre)
    V, Fl = weld(tris)
    keep = [k for k, f in enumerate(Fl) if f]
    F = [Fl[k] for k in keep]
    T = [tris[k] for k in keep]
    cuv, lab, rep = unwrap(V, F, ref)  # ref = seam predicate
    uvT = (cuv / TILE, lab)
    thick = np.array([t['t'] for t in T])
    roles = [t['role'] for t in T]
    P, UVs, faces = build_shell(V, F, thick, uvT, roles)
    cn = corner_normals(P, faces)
    bone = list(bones)[0]
    res = {}
    for fname, oname, rs in outputs:
        hdr = (f'# {oname}: BRZ-01 Titan {label}, exported from the wedge build (MechConfig.Scale {raw["scale"]})\n'
               f'# units: studs, in the "{bone}" bone frame (+Y up, front = -Z); UV: 1 repeat = {TILE} studs (crosshatch largeTile)\n')
        info = write_obj(os.path.join(OUT, fname), oname, P, UVs, faces, cn, rs, hdr)
        info['bone'] = bone
        info['islands'] = rep
        res[oname] = info
    mesh = dict(P=P.tolist(), UV=UVs.tolist(), islands=rep, faces=[(f[0], f[1], f[2], f[3]) for f in faces], cn=cn.tolist(), bone=bone)
    return res, mesh


PAD_ROWS = [(27.5, 4.62, 6.45, 2.75), (28.3, 4.51, 6.75, 2.75), (29.2, 4.39, 7.4, 2.75), (30.2, 4.25, 8.4, 2.75),
            (31.2, 4.11, 9.28, 2.75), (31.9, 4.02, 9.0, 2.71), (32.4, 3.95, 8.75, 2.59), (32.9, 3.91, 8.72, 2.37),
            (33.3, 3.88, 8.7, 2.1), (33.55, 3.86, 8.68, 1.88), (33.85, 3.84, 8.3, 1.53), (34.1, 3.82, 7.98, 1.11),
            (34.35, 3.8, 7.66, 0.6), (34.55, 3.78, 7.4, 0.6), (35.25, 6.6, 6.6, 0.6)]  # ChestBuilder PAD_ROWS


def pad_seam(s):
    """seam along the pad's outer corner lines (front/back panel meets the outer wall):
    the box-like pad unfolds into four near-isometric islands (front, back, outer arc, inner wall)"""
    pts = []
    for h, inner, outer, hd in PAD_ROWS:
        for f in (-1, 1):
            pts.append(np.array([s * outer, h - 23.4, -0.65 + f * hd + 1.5]) * U)
    pts = np.array(pts)

    def on(p):
        d = np.linalg.norm(pts - p, axis=1)
        k = int(np.argmin(d))
        return (pts[k][2] > -0.65 * U + 1.5 * U) if d[k] < 0.03 else None
    def fn(a, b):
        sa, sb = on(a), on(b)
        return sa is not None and sa == sb
    return fn


def helmet_seam(a, b):
    """seam along the chamfer / flat-top creases (section points x = +-1.08 cells)"""
    xa, xb = 1.08 * U, 1.08 * U
    return abs(abs(a[0]) - xa) < 0.01 and abs(abs(b[0]) - xb) < 0.01 and a[0] * b[0] > 0


if __name__ == '__main__':
    hc = np.array([0, (2.75 + 0.6 - 2.2) * U, 0.1 * U])
    dparts = [q for q in raw['groups']['Dome']]
    dc = np.mean([cf(q['cf'])[0] for q in dparts], axis=0) + np.array([0, 0, 3.0])
    jobs = [
        ('PadR', {'PadShell'}, None, pad_seam(1), [('Titan_ShoulderPad_R.obj', 'Titan_ShoulderPad_R', {'main'})], 'right shoulder pad (PadShell)'),
        ('PadL', {'PadShell'}, None, pad_seam(-1), [('Titan_ShoulderPad_L.obj', 'Titan_ShoulderPad_L', {'main'})], 'left shoulder pad (PadShell)'),
        ('Dome', {'ChestPlate', 'ChestCrescent', 'ChestLower', 'ChestSide'}, dc, None,
         [('Titan_ChestDome.obj', 'Titan_ChestDome', {'main'}), ('Titan_ChestCrescent.obj', 'Titan_ChestCrescent', {'hi'})],
         'chest bulge (ChestPlate/ChestLower/ChestSide = main, ChestCrescent = hi)'),
        ('Helmet', {'HelmetShell'}, hc, helmet_seam, [('Titan_Helmet.obj', 'Titan_Helmet', {'main'})], 'helmet shell (HelmetShell)'),
        ('Helmet', {'HelmetCap'}, hc, None, [('Titan_HelmetCap.obj', 'Titan_HelmetCap', {'hi'})], 'helmet end caps (HelmetCap)'),
    ]
    allres = {}
    meshes = {}
    for g, names, c, ref, outs, label in jobs:
        res, mesh = process(g, names, c, ref, outs, label)
        allres.update(res)
        meshes[outs[0][1]] = mesh
        for k, v in res.items():
            print(k, v['tris'], 'tris', v['verts'], 'v', 'centre', np.round(v['centre'], 4).tolist(), 'size', np.round(v['size'], 4).tolist())
        print('   islands', v['islands'])
    allres['_bones'] = raw['bones']
    json.dump(allres, open(os.path.join(D, 'meta.json'), 'w'), indent=1)
    json.dump(meshes, open(os.path.join(D, 'meshes.json'), 'w'))
