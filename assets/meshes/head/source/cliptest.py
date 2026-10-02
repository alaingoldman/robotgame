"""Clipping check between face pieces: samples the outward-facing surface of
piece A (pushed 0.004 cells outward) and reports how much of it lies INSIDE
the closed solid of piece B - i.e. where B pokes through A's visible skin.

    python cliptest.py
"""
import numpy as np

import model


def inside(points, m):
    """ray parity along a skewed direction (avoids hitting edges exactly)."""
    V, F = m.arrays()
    A, B, C = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    d = np.array([1.0, 0.0123, 0.0071])
    d /= np.linalg.norm(d)
    e1, e2 = B - A, C - A
    pv = np.cross(d, e2)
    det = (e1 * pv).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1), 0)
    res = []
    for p in points:
        t = p - A
        u = (t * pv).sum(1) * inv
        q = np.cross(t, e1)
        v = (q * d).sum(1) * inv
        s = (q * e2).sum(1) * inv
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (s > 0)
        res.append(hit.sum() % 2 == 1)
    return np.array(res)


def surface_samples(m, n_per=6, front_only=False, hmax=None, rng=np.random.default_rng(1)):
    V, F = m.arrays()
    pts = []
    for a, b, c in F:
        A, B, C = V[a], V[b], V[c]
        nrm = np.cross(B - A, C - A)
        ln = np.linalg.norm(nrm)
        if ln < 1e-9:
            continue
        nrm /= ln
        if front_only and nrm[2] > -0.15:
            continue
        for _ in range(n_per):
            r1, r2 = rng.random(2)
            if r1 + r2 > 1:
                r1, r2 = 1 - r1, 1 - r2
            p = A + r1 * (B - A) + r2 * (C - A) + nrm * 0.004
            if hmax is None or p[1] <= hmax:
                pts.append(p)
    return np.array(pts)


def report(name_a, a, name_b, b, **kw):
    pts = surface_samples(a, **kw)
    ins = inside(pts, b)
    print("%-28s inside %-16s %4d / %4d samples%s" % (name_a + " visible skin", name_b, ins.sum(), len(pts),
                                                     ("  e.g. " + str(np.round(pts[ins][:3], 2).tolist())) if ins.any() else ""))
    return int(ins.sum())


if __name__ == "__main__":
    band, recess, pod = model.ear_side()
    crest = model.crest()
    brow = model.brow()
    shell = model.helmet_shell()
    report("crest", crest, "brow", brow, front_only=True, hmax=4.4)
    report("crest", crest, "helmet shell", shell, front_only=True, hmax=4.4)
    report("visor", model.visor_slit(), "visor frame", model.visor_frame(), front_only=True)
    report("visor", model.visor_slit(), "brow", brow, front_only=True)
    report("visor", model.visor_slit(), "faceplate", model.faceplate(), front_only=True)
    report("faceplate", model.faceplate(), "cheek bars", model.cheek_bars(), front_only=True)
    report("faceplate", model.faceplate(), "jaw plates", model.jaw_plates(), front_only=True)
    report("cheek bars", model.cheek_bars(), "jaw plates", model.jaw_plates(), front_only=True)
    report("faceplate", model.faceplate(), "face core", model.face_core(), front_only=True)
    report("brow", brow, "crest", crest, front_only=True)
