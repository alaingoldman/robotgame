"""Tiny closed-shell mesh toolkit (numpy only): lofts, slabs, prisms,
hard-edge normals, per-facet-group planar UVs (1 repeat = 4 studs, Roblox
box-mapping orientation), OBJ writer."""
import math

import numpy as np


class Mesh:
    def __init__(self):
        self.v = []  # [x, y, z]
        self.f = []  # (a, b, c)

    def add_v(self, p):
        self.v.append([float(p[0]), float(p[1]), float(p[2])])
        return len(self.v) - 1

    def tri(self, a, b, c):
        if a != b and b != c and a != c:
            self.f.append((a, b, c))

    def quad(self, a, b, c, d):
        # split along the shorter diagonal
        V = self.v
        d1 = np.linalg.norm(np.subtract(V[a], V[c]))
        d2 = np.linalg.norm(np.subtract(V[b], V[d]))
        if d1 <= d2:
            self.tri(a, b, c)
            self.tri(a, c, d)
        else:
            self.tri(a, b, d)
            self.tri(b, c, d)

    def extend(self, other):
        o = len(self.v)
        self.v += [list(p) for p in other.v]
        self.f += [(a + o, b + o, c + o) for a, b, c in other.f]
        return self

    def arrays(self):
        return np.array(self.v, float).reshape(-1, 3), np.array(self.f, int).reshape(-1, 3)

    def transformed(self, fn):
        m = Mesh()
        m.v = [list(fn(np.array(p))) for p in self.v]
        m.f = list(self.f)
        return m

    def mirrored_x(self):
        m = Mesh()
        m.v = [[-p[0], p[1], p[2]] for p in self.v]
        m.f = [(a, c, b) for a, b, c in self.f]
        return m


def combine(*meshes):
    out = Mesh()
    for m in meshes:
        out.extend(m)
    return out


def sym(m):
    """m plus its mirror across x = 0 (two shells)."""
    return combine(m, m.mirrored_x())


# ---------- polygon helpers ----------

def poly_area2(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a / 2


def ear_clip(pts):
    """Triangulate a simple 2D polygon -> index triples (CCW)."""
    n = len(pts)
    idx = list(range(n))
    if poly_area2(pts) < 0:
        idx.reverse()
    tris = []

    def sgn(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    def inside(p, a, b, c):
        return sgn(p, a, b) >= -1e-12 and sgn(p, b, c) >= -1e-12 and sgn(p, c, a) >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 100000:
        guard += 1
        m = len(idx)
        best = None
        for i in range(m):
            ia, ib, ic = idx[i - 1], idx[i], idx[(i + 1) % m]
            a, b, c = pts[ia], pts[ib], pts[ic]
            cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if cross <= 1e-12:
                continue
            ok = True
            for j in idx:
                if j in (ia, ib, ic):
                    continue
                pj = pts[j]
                if (abs(pj[0] - a[0]) + abs(pj[1] - a[1]) < 1e-12 or abs(pj[0] - b[0]) + abs(pj[1] - b[1]) < 1e-12
                        or abs(pj[0] - c[0]) + abs(pj[1] - c[1]) < 1e-12):
                    continue
                if inside(pj, a, b, c):
                    ok = False
                    break
            if ok:
                la = math.hypot(c[0] - a[0], c[1] - a[1])
                q = cross / (la * la + 1e-12)
                if best is None or q > best[0]:
                    best = (q, i)
        if best is None:
            for i in range(1, len(idx) - 1):
                tris.append((idx[0], idx[i], idx[i + 1]))
            return tris
        i = best[1]
        m = len(idx)
        tris.append((idx[i - 1], idx[i], idx[(i + 1) % m]))
        idx.pop(i)
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def plane_basis(pts3):
    P = np.array(pts3, float)
    c = P.mean(0)
    n = np.zeros(3)
    for i in range(len(P)):  # Newell normal
        a, b = P[i], P[(i + 1) % len(P)]
        n += np.array([(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])])
    n /= np.linalg.norm(n) + 1e-12
    t = np.cross(n, [0, 1, 0] if abs(n[1]) < 0.9 else [1, 0, 0])
    t /= np.linalg.norm(t)
    s = np.cross(n, t)
    return c, n, t, s


def cap(mesh, ids):
    """Fill a closed loop of vertex ids (planar-ish)."""
    pts3 = [mesh.v[i] for i in ids]
    c, n, t, s = plane_basis(pts3)
    p2 = [(float(np.dot(np.subtract(p, c), t)), float(np.dot(np.subtract(p, c), s))) for p in pts3]
    for a, b, cc in ear_clip(p2):
        mesh.tri(ids[a], ids[b], ids[cc])


# ---------- solids ----------

def loft(rings, apex0=None, apex1=None, closed_rings=True):
    """rings: list of closed loops of 3D points (same count each), lofted with
    quads; ends capped flat, or closed to a point apex. Winding fixed after."""
    m = Mesh()
    ids = [[m.add_v(p) for p in r] for r in rings]
    n = len(rings[0])
    for k in range(len(rings) - 1):
        A, B = ids[k], ids[k + 1]
        for i in range(n):
            j = (i + 1) % n
            m.quad(A[i], A[j], B[j], B[i])
    if apex0 is not None:
        a = m.add_v(apex0)
        for i in range(n):
            m.tri(a, ids[0][(i + 1) % n], ids[0][i])
    else:
        cap(m, ids[0])
    if apex1 is not None:
        a = m.add_v(apex1)
        for i in range(n):
            m.tri(a, ids[-1][i], ids[-1][(i + 1) % n])
    else:
        cap(m, ids[-1])
    m = weld(m)
    orient_outward(m)
    return m


def torus_loft(rings):
    """rings: closed loops swept round a closed path (last joins first): a ring solid."""
    m = Mesh()
    ids = [[m.add_v(p) for p in r] for r in rings]
    n = len(rings[0])
    K = len(rings)
    for k in range(K):
        A, B = ids[k], ids[(k + 1) % K]
        for i in range(n):
            j = (i + 1) % n
            m.quad(A[i], A[j], B[j], B[i])
    m = weld(m)
    orient_outward(m)
    return m


def split_line(poly, axis, c):
    """Split a polygon by the line (x if axis == 0 else h) = c into its two
    sides (each cut must be a single chord)."""
    pts = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        pts.append(tuple(a))
        da, db = a[axis] - c, b[axis] - c
        if (da < -1e-9 and db > 1e-9) or (da > 1e-9 and db < -1e-9):
            t = da / (da - db)
            p = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
            p[axis] = c
            pts.append(tuple(p))
    out = []
    for keep in (lambda v: v <= c + 1e-9, lambda v: v >= c - 1e-9):
        q = []
        for p in pts:
            if keep(p[axis]) and (not q or abs(q[-1][0] - p[0]) + abs(q[-1][1] - p[1]) > 1e-9):
                q.append(p)
        if len(q) > 1 and abs(q[0][0] - q[-1][0]) + abs(q[0][1] - q[-1][1]) < 1e-9:
            q.pop()
        if len(q) >= 3 and abs(poly_area2(q)) > 1e-9:
            out.append(q)
    return out


def split_x(poly):
    return split_line(poly, 0, 0.0)


def slab(poly, zfront, thick, fold_x=True, cuts_h=(), cuts_x=()):
    """Front-view polygon [(x, h)] lifted onto a front surface z = zfront(x, h),
    given depth `thick` (number or fn(x, h)) toward +Z. fold_x splits it at
    x = 0 so a V-shaped (prow) front keeps a crisp centre crease; cuts_h adds
    horizontal folds (where zfront has a kink in h). One closed shell."""
    pieces = [list(map(tuple, poly))]
    if fold_x:
        pieces = [q for p in pieces for q in split_line(p, 0, 0.0)]
    for c in cuts_h:
        pieces = [q for p in pieces for q in split_line(p, 1, c)]
    for c in cuts_x:
        pieces = [q for p in pieces for q in split_line(p, 0, c)]
    m = Mesh()
    th = thick if callable(thick) else (lambda x, h: thick)
    key = {}

    def vid(x, h, back):
        k = (round(x, 7), round(h, 7), back)
        if k not in key:
            z = zfront(x, h)
            key[k] = m.add_v((x, h, z + (th(x, h) if back else 0.0)))
        return key[k]

    edge_count = {}
    for pc in pieces:
        for a, b, c in ear_clip(pc):
            A, B, C = pc[a], pc[b], pc[c]
            m.tri(vid(*A, False), vid(*B, False), vid(*C, False))
            m.tri(vid(*A, True), vid(*C, True), vid(*B, True))
        n = len(pc)
        for i in range(n):
            e = (tuple(round(v, 7) for v in pc[i]), tuple(round(v, 7) for v in pc[(i + 1) % n]))
            edge_count[e] = edge_count.get(e, 0) + 1
    for (p, q), k in edge_count.items():
        if (q, p) in edge_count:
            continue  # interior chord shared by two pieces
        m.quad(vid(*p, False), vid(*q, False), vid(*q, True), vid(*p, True))
    m = weld(m)
    orient_outward(m)
    return m


def prism(poly, axis, d0, d1):
    """2D polygon extruded along an axis. 'x': poly (z, h), x from d0 to d1;
    'z': poly (x, h); 'y': poly (x, z)."""
    def P(p, d):
        if axis == "x":
            return (d, p[1], p[0])
        if axis == "z":
            return (p[0], p[1], d)
        return (p[0], d, p[1])
    return loft([[P(p, d0) for p in poly], [P(p, d1) for p in poly]])


def weld(m, eps=1e-6):
    key = {}
    remap = []
    nv = []
    for p in m.v:
        k = (round(p[0] / eps), round(p[1] / eps), round(p[2] / eps))
        if k not in key:
            key[k] = len(nv)
            nv.append(p)
        remap.append(key[k])
    out = Mesh()
    out.v = nv
    seen = set()
    for a, b, c in m.f:
        t = (remap[a], remap[b], remap[c])
        if len(set(t)) == 3:
            k = frozenset(t)
            if k in seen:
                continue
            seen.add(k)
            out.f.append(t)
    return out


def orient_outward(m):
    """Consistent winding over shared edges, then outward (positive volume)
    per connected shell."""
    F = [list(f) for f in m.f]
    edge_faces = {}
    for i, (a, b, c) in enumerate(F):
        for e in ((a, b), (b, c), (c, a)):
            edge_faces.setdefault(frozenset(e), []).append(i)
    V = np.array(m.v)
    seen = [False] * len(F)
    for s in range(len(F)):
        if seen[s]:
            continue
        comp = [s]
        seen[s] = True
        q = [s]
        while q:
            i = q.pop()
            a, b, c = F[i]
            for (u, v) in ((a, b), (b, c), (c, a)):
                for j in edge_faces[frozenset((u, v))]:
                    if seen[j]:
                        continue
                    x, y, z = F[j]
                    if (x, y) == (u, v) or (y, z) == (u, v) or (z, x) == (u, v):
                        F[j] = [x, z, y]
                    seen[j] = True
                    comp.append(j)
                    q.append(j)
        vol = 0.0
        for i in comp:
            a, b, c = F[i]
            vol += np.dot(V[a], np.cross(V[b], V[c]))
        if vol < 0:
            for i in comp:
                a, b, c = F[i]
                F[i] = [a, c, b]
    m.f = [tuple(f) for f in F]


def open_edges(m):
    cnt = {}
    for a, b, c in m.f:
        for e in ((a, b), (b, c), (c, a)):
            cnt[e] = cnt.get(e, 0) + 1
    return sum(1 for (a, b), k in cnt.items() if cnt.get((b, a), 0) != k)


# ---------- normals / UVs / OBJ ----------

def face_normals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    area = np.linalg.norm(n, axis=1)
    return n / (area[:, None] + 1e-12), area / 2


# Roblox box-mapping frame per dominant face direction: (u axis, v axis)
BOX = {
    ("z", -1): (np.array([-1, 0, 0.]), np.array([0, -1, 0.])),  # front (-Z): u = -x, v = -y
    ("z", 1): (np.array([1, 0, 0.]), np.array([0, -1, 0.])),  # back
    ("x", 1): (np.array([0, 0, -1.]), np.array([0, -1, 0.])),  # right
    ("x", -1): (np.array([0, 0, 1.]), np.array([0, -1, 0.])),  # left
    ("y", 1): (np.array([-1, 0, 0.]), np.array([0, 0, 1.])),  # top
    ("y", -1): (np.array([-1, 0, 0.]), np.array([0, 0, -1.])),  # bottom
}


def dom_key(n):
    ax = int(np.argmax(np.abs(n)))
    return "xyz"[ax], (1 if n[ax] > 0 else -1)


def build_render_data(m, crease_deg=30.0, group_deg=33.0, tile=4.0):
    """-> V, F, corner normals, corner uvs, island id per face, max stretch.
    Normals are smooth across edges under crease_deg, hard above. UV islands
    grow over edges under crease_deg while each face stays within group_deg
    of the island normal (planar projection stretch <= 1/cos(33) = 1.19);
    each island is projected on its own plane, oriented like Roblox's box
    mapping of its dominant direction, so the lattice keeps its direction
    and phase across neighbouring islands."""
    V, F = m.arrays()
    N, A = face_normals(V, F)
    cos_c = math.cos(math.radians(crease_deg))
    cos_g = math.cos(math.radians(group_deg))
    edge_faces = {}
    for i, (a, b, c) in enumerate(F):
        for e in ((a, b), (b, c), (c, a)):
            edge_faces.setdefault(frozenset(e), []).append(i)
    vert_faces = [[] for _ in range(len(V))]
    for i, f in enumerate(F):
        for k in range(3):
            vert_faces[f[k]].append(i)
    CN = np.zeros((len(F), 3, 3))
    for i, f in enumerate(F):
        for k in range(3):
            acc = np.zeros(3)
            for j in vert_faces[f[k]]:
                if np.dot(N[i], N[j]) >= cos_c:
                    acc += N[j] * A[j]
            CN[i, k] = acc / (np.linalg.norm(acc) + 1e-12)
    island = -np.ones(len(F), int)
    islands = []
    for s in np.argsort(-A):
        if island[s] >= 0:
            continue
        gid = len(islands)
        seedn = N[s]
        island[s] = gid
        members = [s]
        q = [s]
        while q:
            i = q.pop()
            a, b, c = F[i]
            for e in ((a, b), (b, c), (c, a)):
                for j in edge_faces[frozenset(e)]:
                    if island[j] >= 0:
                        continue
                    if np.dot(N[i], N[j]) >= cos_c and np.dot(seedn, N[j]) >= cos_g:
                        island[j] = gid
                        members.append(j)
                        q.append(j)
        nsum = (N[members] * A[members, None]).sum(0)
        nrm = nsum / (np.linalg.norm(nsum) + 1e-12)
        if np.min(N[members] @ nrm) < cos_g:
            nrm = seedn
        U, Vv = BOX[dom_key(nrm)]
        U = U - np.dot(U, nrm) * nrm
        U /= np.linalg.norm(U)
        Vv = Vv - np.dot(Vv, nrm) * nrm - np.dot(Vv, U) * U
        Vv /= np.linalg.norm(Vv)
        islands.append((members, nrm, U, Vv))
    CUV = np.zeros((len(F), 3, 2))
    worst = 1.0
    for members, nrm, U, Vv in islands:
        for i in members:
            for k in range(3):
                p = V[F[i][k]]
                CUV[i, k] = (np.dot(p, U) / tile, np.dot(p, Vv) / tile)
            worst = max(worst, 1.0 / max(float(np.dot(N[i], nrm)), 1e-6))
    return V, F, CN, CUV, island, worst


def write_obj(path, m, header=""):
    V, F, CN, CUV, island, stretch = build_render_data(m)
    vt_index, vts = {}, []
    vn_index, vns = {}, []
    lines = ["# " + h for h in header.splitlines()]
    lines.append("o " + path.replace("\\", "/").split("/")[-1].rsplit(".", 1)[0])
    for p in V:
        lines.append("v %.5f %.5f %.5f" % tuple(p))
    fl = []
    for i, f in enumerate(F):
        tok = []
        for k in range(3):
            uvk = (round(float(CUV[i, k, 0]), 5), round(float(CUV[i, k, 1]), 5))
            if uvk not in vt_index:
                vt_index[uvk] = len(vts) + 1
                vts.append(uvk)
            nk = tuple(round(float(c), 4) for c in CN[i, k])
            if nk not in vn_index:
                vn_index[nk] = len(vns) + 1
                vns.append(nk)
            tok.append("%d/%d/%d" % (f[k] + 1, vt_index[uvk], vn_index[nk]))
        fl.append("f " + " ".join(tok))
    lines += ["vt %.5f %.5f" % t for t in vts]
    lines += ["vn %.4f %.4f %.4f" % n for n in vns]
    lines.append("s off")
    lines += fl
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(F), stretch, int(island.max() + 1)
