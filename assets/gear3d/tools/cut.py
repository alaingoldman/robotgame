"""Split a textured mesh by a horizontal plane y = c and cap both openings with the real cross-section
(segments chained into loops by position, each loop earcut-triangulated). Same idea as mech3 v2 'clean caps'."""
import numpy as np
import mapbox_earcut as earcut


def _compact(p, n, t, ix):
    if len(ix) == 0:
        return p[:0], n[:0], t[:0], ix
    used, inv = np.unique(ix.ravel(), return_inverse=True)
    return p[used], n[used], t[used], inv.reshape(-1, 3)


def split(p, n, t, ix, c, cap_uv):
    """Returns (below, above, loops) where below/above = (p, n, t, ix) and loops = list of Nx2 xz loops."""
    s = p[:, 1] - c
    s = np.where(np.abs(s) < 1e-7, 1e-7, s)
    side = s > 0                                   # True = above
    tri_side = side[ix]
    cnt = tri_side.sum(1)
    above_ix = [ix[cnt == 3]]; below_ix = [ix[cnt == 0]]
    mixed = ix[(cnt == 1) | (cnt == 2)]
    P, N, T = [p], [n], [t]
    nv = len(p)
    edge_cache = {}
    segs = []

    def epoint(a, b):
        nonlocal nv
        k = (a, b) if a < b else (b, a)
        if k in edge_cache:
            return edge_cache[k]
        u = s[a] / (s[a] - s[b])
        P.append((p[a] + u * (p[b] - p[a]))[None]); N.append((n[a] + u * (n[b] - n[a]))[None])
        T.append((t[a] + u * (t[b] - t[a]))[None])
        edge_cache[k] = nv; nv += 1
        return nv - 1
    ab, bl = [], []
    for tri in mixed:
        sd = side[tri]
        lone = 0 if sd[0] != sd[1] and sd[0] != sd[2] else (1 if sd[1] != sd[0] and sd[1] != sd[2] else 2)
        L, M, Nn = tri[lone], tri[(lone + 1) % 3], tri[(lone + 2) % 3]
        Pp = epoint(L, M); Q = epoint(L, Nn)
        lone_list, other_list = (ab, bl) if side[L] else (bl, ab)
        lone_list.append((L, Pp, Q))
        other_list.append((Pp, M, Nn)); other_list.append((Pp, Nn, Q))
        segs.append((Pp, Q))
    p2 = np.vstack(P); n2 = np.vstack(N); t2 = np.vstack(T)
    A = np.vstack(above_ix + ([np.array(ab, np.int64)] if ab else []))
    B = np.vstack(below_ix + ([np.array(bl, np.int64)] if bl else []))
    loops = chain_loops(p2, segs)
    above = list(_compact(p2, n2, t2, A)); below = list(_compact(p2, n2, t2, B))
    for loop in loops:
        tris = earcut.triangulate_float64(loop, np.array([len(loop)], np.uint32)).reshape(-1, 3).astype(np.int64)
        if len(tris) == 0:
            continue
        v3 = np.column_stack([loop[:, 0], np.full(len(loop), c), loop[:, 1]])
        for mesh, sd in ((below, 1.0), (above, -1.0)):
            F = tris.copy()
            a, b, cc = v3[F[0, 0]], v3[F[0, 1]], v3[F[0, 2]]
            if np.sign(np.cross(b - a, cc - a)[1]) != sd:
                F = F[:, [0, 2, 1]]
            b0 = len(mesh[0])
            mesh[0] = np.vstack([mesh[0], v3]); mesh[1] = np.vstack([mesh[1], np.tile([0, sd, 0], (len(v3), 1))])
            mesh[2] = np.vstack([mesh[2], np.tile(cap_uv, (len(v3), 1))]); mesh[3] = np.vstack([mesh[3], F + b0])
    return tuple(below), tuple(above), loops


def chain_loops(p, segs, tol=1e-4):
    key = lambda i: (round(p[i, 0] / tol), round(p[i, 2] / tol))
    adj = {}
    pos = {}
    for a, b in segs:
        ka, kb = key(a), key(b)
        if ka == kb:
            continue
        adj.setdefault(ka, set()).add(kb); adj.setdefault(kb, set()).add(ka)
        pos[ka] = p[a, [0, 2]]; pos[kb] = p[b, [0, 2]]
    used = set(); loops = []
    for start in list(adj):
        if start in used:
            continue
        loop = [start]; used.add(start); prev, cur = None, start
        closed = False
        for _ in range(200000):
            nxt = [k for k in adj[cur] if k != prev and (k not in used or k == start)]
            if not nxt:
                break
            if start in nxt and len(loop) > 2:
                closed = True; break
            nxt = [k for k in nxt if k != start]
            if not nxt:
                break
            prev, cur = cur, nxt[0]; used.add(cur); loop.append(cur)
        pts = np.array([pos[k] for k in loop])
        if not closed and len(pts) > 5 and np.linalg.norm(pts[0] - pts[-1]) < 0.15 * np.ptp(pts, 0).max():
            closed = True                           # nearly closed: close it
        if closed and len(pts) >= 3:
            ar = 0.5 * abs(np.sum(pts[:, 0] * np.roll(pts[:, 1], -1) - np.roll(pts[:, 0], -1) * pts[:, 1]))
            if ar > 1e-5:
                loops.append(pts)
    return loops
