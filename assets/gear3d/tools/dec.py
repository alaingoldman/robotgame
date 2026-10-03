"""Crack-free decimation that keeps UVs.
The mesh is welded by POSITION (so UV seams cannot open into cracks), simplified with fast_simplification, then
each output face corner gets a UV from the original vertex that survived, picking the variant that belongs to the
same UV chart as the original surface under the face (chart = connected component of the UV-split mesh)."""
import numpy as np
import fast_simplification
import trimesh
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree


def compact(p, n, t, ix):
    used, inv = np.unique(ix.ravel(), return_inverse=True)
    return p[used], n[used], t[used], inv.reshape(-1, 3)


def _weld_key(a, q):
    key = np.round(a / q).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return first, inv.ravel()


def weld(p, n, t, ix):
    first, inv = _weld_key(np.hstack([p / 1e-5, t / 1e-5]), 1.0)
    ix2 = inv[ix]
    ok = (ix2[:, 0] != ix2[:, 1]) & (ix2[:, 1] != ix2[:, 2]) & (ix2[:, 0] != ix2[:, 2])
    return p[first], n[first], t[first], ix2[ok]


def vnormals(p, f):
    return np.asarray(trimesh.Trimesh(p, f, process=False).vertex_normals)


def decimate(p, n, t, ix, target):
    if len(ix) <= target:
        return p, n, t, ix
    p, n, t, ix = weld(p, n, t, ix)                       # split mesh (pos+uv unique)
    nv = len(p)
    # charts
    e = np.vstack([ix[:, [0, 1]], ix[:, [1, 2]], ix[:, [2, 0]]])
    g = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(nv, nv))
    _, chart = connected_components(g, directed=False)
    # position weld
    first, wid = _weld_key(p, 1e-6)
    P = p[first]; F = wid[ix]
    ok = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    F = F[ok]; ixs = ix[ok]
    red = 1 - target / len(F)
    P32 = P.astype(np.float32); F32 = F.astype(np.int32)
    p2, f2, coll = fast_simplification.simplify(P32, F32, red, return_collapses=True)
    _, _, mapping = fast_simplification.replay_simplification(P32, F32, coll)
    p2 = np.asarray(p2, float); f2 = np.asarray(f2, np.int64)
    m2 = len(p2)
    # every old welded vertex -> new vertex; candidates for new vertex = all split vertices whose welded id maps to it
    newv_of_split = mapping[wid]                           # split vertex -> new vertex id
    # chart of each output face = chart of the nearest original face
    cen = P[F].mean(1)
    tree = cKDTree(cen)
    _, fi = tree.query(p2[f2].mean(1))
    fchart = chart[ixs[fi, 0]]
    # lookup (new vertex, chart) -> split vertex  (prefer the vertex that itself survived)
    valid = (newv_of_split >= 0) & (newv_of_split < m2)
    sv = np.where(valid)[0]
    key = newv_of_split[sv] * (chart.max() + 1) + chart[sv]
    # prefer split vertices closest to the new vertex position
    d = np.linalg.norm(p[sv] - p2[newv_of_split[sv]], axis=1)
    order = np.lexsort((d, key))
    k_sorted = key[order]; sv_sorted = sv[order]
    uk, start = np.unique(k_sorted, return_index=True)
    lut = dict(zip(uk.tolist(), sv_sorted[start].tolist()))
    # fallback: nearest split vertex of that chart near the corner position
    ptree = cKDTree(p)
    corners = f2.ravel()
    cch = np.repeat(fchart, 3)
    C = chart.max() + 1
    chosen = np.empty(len(corners), np.int64)
    ck = corners * C + cch
    miss = []
    for i, kk in enumerate(ck.tolist()):
        s = lut.get(kk)
        if s is None:
            miss.append(i); chosen[i] = -1
        else:
            chosen[i] = s
    if miss:
        miss = np.array(miss)
        _, nn = ptree.query(p2[corners[miss]], k=min(32, len(p)))
        for j, i in enumerate(miss):
            cand = nn[j]
            hit = cand[chart[cand] == cch[i]]
            chosen[i] = hit[0] if len(hit) else cand[0]
    # output vertices = unique (new vertex, chosen split vertex)
    pair = corners * (nv + 1) + chosen
    up, inv = np.unique(pair, return_inverse=True)
    vv = up // (nv + 1); ss = up % (nv + 1)
    nrm = vnormals(p2, f2)
    P_, N_, T_, I_ = p2[vv], nrm[vv], t[ss], inv.reshape(-1, 3)
    # faces whose UVs got stretched across a seam (uv/3d area ratio >> typical): give them a flat texel taken from
    # the original surface right under the face (no smear, colour still correct).
    def ratio(pp, tt, ff):
        a3 = np.linalg.norm(np.cross(pp[ff[:, 1]] - pp[ff[:, 0]], pp[ff[:, 2]] - pp[ff[:, 0]]), axis=1)
        d1 = tt[ff[:, 1]] - tt[ff[:, 0]]; d2 = tt[ff[:, 2]] - tt[ff[:, 0]]
        return np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / np.maximum(a3, 1e-12)
    r0 = np.median(ratio(p, t, ixs))
    bad = np.where(ratio(P_, T_, I_) > 4 * r0)[0]
    if len(bad):
        uvc = t[ixs[fi[bad]]].mean(1)
        b0 = len(P_)
        cor = I_[bad].ravel()
        P_ = np.vstack([P_, P_[cor]]); N_ = np.vstack([N_, N_[cor]]); T_ = np.vstack([T_, np.repeat(uvc, 3, axis=0)])
        I_[bad] = (b0 + np.arange(len(cor))).reshape(-1, 3)
        P_, N_, T_, I_ = compact(P_, N_, T_, I_)
    return P_, N_, T_, I_
