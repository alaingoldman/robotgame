"""mech2 TORSO builder (offline; numpy only).  python build.py  ->  ../*.obj + ../meta.json

Design units are GRID CELLS of the reference sheets (1 cell = 0.816 studs);
everything is converted to studs on export.  Frame: +Y up, -Z forward,
+X = the robot's RIGHT (Roblox convention: character faces -Z, right arm at +X).
Origin: centre of the hip-joint line (the hip-ball centres in the BACK view).

Reference pixel -> cell conversions (measured with grid.py / zoom crops):
  grid pitch: 28.4 px / cell horizontally, 29.3 px / cell vertically (all 3 sheets)
  FRONT 259.png : body centre x = 285.5 px     -> |X| = (285.5 - px) / 28.4
  BACK  261.png : body centre x = 296 px       -> |X| = (296 - px) / 28.4
  both          : hip-ball centre line y = 525 px (261) -> H = (525 - py) / 29.3
                  (259 shares the vertical registration: pauldron blade tip y 217 vs 215,
                   tall-plate tops y 92 vs 88)
  SIDE  260.png : 3/4 view used for DEPTH (see DEPTH notes below).

DEPTH (Z) choices, from the side view 260 (px / 28.4):
  front-most chest point (white/gold chest prow) x~100-110 vs the blue/grey core
  behind it x~150-165  ->  ~1.9 cells of forward projection   => prow Z -3.0, core front Z -1.1
  the gold vertical shoulder-blade plates sweep up and BACK to x~345 (top) ->
  fins reach Z +3.2 at their top, back plate Z +2.6.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import meshlib as ml  # noqa: E402  (copy of legs/source/meshlib.py - same UV/OBJ conventions)

OUT = os.path.normpath(os.path.join(HERE, ".."))
S = 0.816  # studs per cell

COLORS = {
    "white": "#F2F2F2",
    "gold": "#D4A93A",
    "blue": "#2F6FBF",
    "grey": "#8A8A8A",
    "darkgrey": "#5A5A5A",
}


def FX(px):  # front sheet 259, image-left half (robot right) -> |X| cells
    return (285.5 - px) / 28.4


def BX(px):  # back sheet 261, image-left half -> |X| cells
    return (296.0 - px) / 28.4


def HY(py):  # both sheets -> height above the hip line, cells
    return (525.0 - py) / 29.3


# ------------------------------------------------------------------ primitives

def _inset(poly, d):
    """Offset a CCW polygon inward by per-edge distances d[i] (edge i = i -> i+1)."""
    n = len(poly)
    P = np.array(poly, float)
    out = []
    for i in range(n):
        a0, a1 = P[i - 1], P[i]          # edge i-1
        b0, b1 = P[i], P[(i + 1) % n]    # edge i
        ta = (a1 - a0) / (np.linalg.norm(a1 - a0) + 1e-12)
        tb = (b1 - b0) / (np.linalg.norm(b1 - b0) + 1e-12)
        na = np.array([-ta[1], ta[0]])  # inward normal for CCW
        nb = np.array([-tb[1], tb[0]])
        pa = a0 + na * d[i - 1]
        pb = b0 + nb * d[i]
        M = np.array([ta, -tb]).T
        if abs(np.linalg.det(M)) < 1e-6:
            out.append(P[i] + nb * d[i])
            continue
        s = np.linalg.solve(M, pb - pa)
        q = pa + ta * s[0]
        # clamp runaway miters on very sharp corners
        if np.linalg.norm(q - P[i]) > 3.0 * max(d[i - 1], d[i], 1e-9):
            q = P[i] + (na + nb) / (np.linalg.norm(na + nb) + 1e-9) * max(d[i - 1], d[i])
        out.append(q)
    return [tuple(p) for p in out]


def plate(poly, wfun, thick, ch=0.14, chb=0.06, sharp=lambda p, q: False, frame=None, inward=1.0):
    """Chamfered armour plate.  poly: 2D outline (u, v); outer face lies on
    w = wfun(u, v) (keep it planar), the body extends `thick` toward
    w * inward.  ch / chb: chamfer on the outer / inner rim; edges for which
    sharp(p, q) is True get no chamfer (fold lines shared with a sibling plate).
    frame(u, v, w) -> world xyz (default u=X, v=H, w=Z)."""
    poly = [tuple(map(float, p)) for p in poly]
    if ml.poly_area2(poly) < 0:
        poly = poly[::-1]
    n = len(poly)
    shp = [sharp(poly[i], poly[(i + 1) % n]) for i in range(n)]
    d0 = [0.0 if s else ch for s in shp]
    d3 = [0.0 if s else chb for s in shp]
    P0 = _inset(poly, d0)
    P3 = _inset(poly, d3)
    if frame is None:
        frame = lambda u, v, w: (u, v, w)  # noqa: E731
    k = inward

    def ring(P, off):
        return [frame(u, v, wfun(u, v) + k * off) for (u, v) in P]

    rings = [ring(P0, 0.0), ring(poly, ch), ring(poly, thick - chb), ring(P3, thick)]
    return ml.loft(rings)


def fold_x(p, q):
    return abs(p[0]) < 1e-7 and abs(q[0]) < 1e-7


def fold_h(*hs):
    def f(p, q):
        if abs(p[0]) < 1e-7 and abs(q[0]) < 1e-7:
            return True
        return any(abs(p[1] - h) < 1e-7 and abs(q[1] - h) < 1e-7 for h in hs)
    return f


def box(x0, x1, y0, y1, z0, z1, ch=0.12):
    return plate([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], lambda u, v: z0, z1 - z0, ch, ch)


def oct_ring(cx, h, wx, zf, zb, c):
    """Octagonal section (chamfered rectangle) at height h: x in [cx-wx, cx+wx], z in [zf, zb]."""
    return [(cx - wx + c, h, zf), (cx + wx - c, h, zf), (cx + wx, h, zf + c), (cx + wx, h, zb - c),
            (cx + wx - c, h, zb), (cx - wx + c, h, zb), (cx - wx, h, zb - c), (cx - wx, h, zf + c)]


def band(h0, h1, w0, w1, zf, zb, c=0.42, bev=0.12):
    """Chamfered octagonal tyre between heights h0..h1 (half widths w0 -> w1)."""
    rings = [oct_ring(0, h0, w0 - bev, zf + bev, zb - bev, c), oct_ring(0, h0 + bev, w0, zf, zb, c + 0.04),
             oct_ring(0, h1 - bev, w1, zf, zb, c + 0.04), oct_ring(0, h1, w1 - bev, zf + bev, zb - bev, c)]
    return ml.loft(rings)


def sym(m):
    return ml.sym(m)


def lean_frame(x0, h0, ang, side=1.0):
    """For fins built in the (Z, H) plane with w = local x: shift to x0 and lean the
    top outward by `ang` degrees about the Z axis through (x0, h0)."""
    a = math.radians(ang)

    def f(u, v, w):  # u = Z, v = H, w = local x
        lx = w
        dh = v - h0
        x = x0 + lx * math.cos(a) + dh * math.sin(a)
        y = h0 - lx * math.sin(a) + dh * math.cos(a)
        return (side * x, y, u)
    return f


# ------------------------------------------------------------------ parts

parts = {}  # (segment, colour) -> [Mesh]


def add(seg, col, m):
    parts.setdefault((seg, col), []).append(m)


def build_chest():
    seg = "chest"
    # --- dark core (hidden mostly): |X|<=2.95, H 8.7..12.45 (back sheet: grey frame x 210..382, y 140..262)
    add(seg, "darkgrey", box(-2.95, 2.95, 8.65, 12.45, -1.1, 1.5, 0.2))
    # --- grey neck collar ring around the neck socket (259: grey neck x 262..309, y 150..170)
    rings = [oct_ring(0, 12.2, 0.95, -0.75, 0.95, 0.35), oct_ring(0, 12.75, 0.95, -0.75, 0.95, 0.35),
             oct_ring(0, 12.95, 0.8, -0.6, 0.8, 0.3)]
    add(seg, "grey", ml.loft(rings))
    # --- grey back frame (261: top bar x 249..344 -> |X| 1.68, y 140..162 -> H 13.14..12.39;
    #     frame sides visible x 245..350 down to y 262 -> H 8.98)
    frame_poly = [(0, 13.14), (1.68, 13.14), (1.85, 12.39), (2.45, 12.2), (2.45, 8.75), (0, 8.75)]
    add(seg, "grey", sym(plate(frame_poly, lambda u, v: 2.15, 1.25, 0.14, 0.05, fold_x, inward=-1.0)))
    # --- white central back plate (261: x 268..325 -> |X| 0.99..1.02, y 163..237 -> H 12.36..9.83)
    #     prow toward the back: centre crease Z +2.65, edges +2.45
    bp = [(0, 12.36), (1.0, 12.36), (1.0, 9.83), (0, 9.83)]
    add(seg, "white", sym(plate(bp, lambda u, v: 2.65 - 0.2 * u, 0.55, 0.12, 0.04, fold_x, inward=-1.0)))
    # --- tall gold shoulder-blade fins (261: top x 205..227 -> |X| 3.2..2.43 at y 88..92 -> H 14.9;
    #     bottom x 240..268 -> |X| 1.97..0.99 at y 255 -> H 9.2; 259: x 194..217 at top, same).
    #     Built in the side (Z,H) plane, 1.2 cells thick, leaning out ~10 deg; sweeps back (260).
    fin_prof = [(-0.55, 9.0), (2.45, 8.7), (2.9, 10.2), (3.6, 13.3), (4.3, 14.55), (3.75, 15.0),
                (2.6, 14.95), (0.7, 13.2), (-0.55, 12.4)]
    for side in (1.0, -1.0):
        f = lean_frame(1.35, 9.2, 9.0, side)
        add(seg, "gold", plate(fin_prof, lambda u, v: 0.0, 1.1, 0.14, 0.14, frame=f))
        # white inset on the fin's back face (261: tilted rect x 215..262, y 165..250 -> H 12.3..9.4)
        ins = [(1.15, 9.45), (2.55, 9.45), (2.75, 12.3), (1.45, 12.3)]
        # it lies in the XH plane on the back of the fin; lean like the fin
        ins_l = [(u + (v - 9.2) * math.tan(math.radians(9.0)), v) for u, v in ins]  # same lean as the fin
        add(seg, "white", plate(ins_l, lambda u, v: 2.9 + 0.24 * (v - 9.45), 0.6, 0.1, 0.04,  # follows the fin's back edge
                                frame=(lambda s: (lambda u, v, w: (s * u, v, w)))(side), inward=-1.0))
    # --- blue side blocks (261: x 200..225 -> |X| 3.38..2.5, y 160..235 -> H 12.46..9.9;
    #     259: blue x 190..205 -> |X| 3.36..2.83, y 210..245 -> H 10.75..9.56)
    for s in (1, -1):
        add(seg, "blue", plate([(s * 2.5, 9.45), (s * 3.42, 9.45), (s * 3.42, 12.25), (s * 2.5, 12.45)],
                               lambda u, v: -1.25, 3.55, 0.16, 0.16))
    # --- grey shoulder socket cups on the torso sides: the arm's ball (r ~0.85 cells, centre |X| 4.29)
    #     seats into these so no gap shows between the ball and the blue side block (|X| 3.42)
    sx_, sh_, sz_ = SOCKETS["RightShoulder"]
    for s in (1, -1):
        r8 = [(0.78 * math.cos(math.radians(22.5 + 45 * k)), 0.78 * math.sin(math.radians(22.5 + 45 * k)))
              for k in range(8)]
        rings = [[(s * x, sh_ + a_, sz_ + b_) for a_, b_ in r8] for x in (3.2, 3.62)]
        rings.insert(1, [(s * 3.55, sh_ + a_ * 1.06, sz_ + b_ * 1.06) for a_, b_ in r8])
        add(seg, "grey", ml.loft(rings))
    # --- gold lower back side panels (261: x 200..245 -> |X| 3.38..1.8, y 235..275 -> H 9.9..8.53)
    glp = [(1.8, 9.95), (3.4, 9.95), (3.4, 9.0), (2.75, 8.5), (1.8, 8.5)]
    add(seg, "gold", sym(plate(glp, lambda u, v: 2.55 - 0.08 * (u - 1.8), 2.2, 0.13, 0.08, inward=-1.0)))
    # --- blue lower back wedges (261: x 225..262 -> |X| 2.5..1.2, y 265..295 -> H 8.87..7.85)
    blw = [(1.2, 8.9), (2.6, 8.9), (2.3, 7.9), (1.5, 7.85)]
    add(seg, "blue", sym(plate(blw, lambda u, v: 2.2, 1.2, 0.12, 0.05, inward=-1.0)))
    # ---------------- FRONT (the chest that POPS OUT) ----------------
    # blue collar V band under the head (259: x 240..335 -> |X| 1.6..1.75, y 168..188 -> H 12.18..11.5,
    # V tip at the centre y 188)
    collar = [(0, 11.5), (1.8, 11.95), (1.8, 12.4), (0.55, 12.3), (0, 12.05)]
    add(seg, "blue", sym(plate(collar, lambda u, v: -2.05 + 0.22 * u, 1.5, 0.1, 0.05, fold_x)))
    # gold yoke blocks either side of the collar (259: x 190..252 -> |X| 3.36..1.18, y 165..202 -> H 12.3..11.0)
    yoke = [(1.17, 11.0), (3.4, 11.0), (3.4, 12.0), (2.55, 12.45), (1.4, 12.25)]
    add(seg, "gold", sym(plate(yoke, lambda u, v: -2.55 + 0.3 * (u - 1.17) + 0.45 * (v - 11.0), 2.6, 0.17, 0.08)))
    # yoke top ridge rising above the shoulder line (front view gold shoulders over the collar)
    ridge = [(1.6, 12.2), (3.3, 11.95), (3.3, 12.55), (2.5, 12.95), (1.75, 12.7)]
    add(seg, "gold", sym(plate(ridge, lambda u, v: -1.8 + 0.25 * (u - 1.6), 2.6, 0.14, 0.08)))
    # white central chest plate, faceted prow (259: top x 205..365 -> |X| 2.82, y 202 (sides) / 214 (centre)
    #   -> H 11.02 / 10.61; sides to y 248 -> H 9.45; centre to y 268 -> H 8.77)
    #   prow crease Z -3.0 at H 9.8; upper facet leans back to -2.45 at the top, lower tucks to -2.6
    up = [(0, 9.8), (2.82, 9.8), (2.82, 11.02), (0, 10.61)]
    lo = [(0, 8.75), (1.05, 9.0), (2.82, 9.45), (2.82, 9.8), (0, 9.8)]
    z_up = lambda u, v: -3.4 + 0.42 * u + 0.5 * (v - 9.8)  # noqa: E731
    z_lo = lambda u, v: -3.4 + 0.42 * u + 0.42 * (9.8 - v)  # noqa: E731
    add(seg, "white", sym(plate(up, z_up, 2.1, 0.13, 0.05, fold_h(9.8))))
    add(seg, "white", sym(plate(lo, z_lo, 2.1, 0.13, 0.05, fold_h(9.8))))
    # gold lower pectoral chevrons, stacked 0.3 in front of the white plate
    #   (259: (190,232) (252,240) (255,267) (235,270) (210,280) (195,275))
    pec = [(FX(190), HY(232)), (FX(252), HY(240)), (FX(255), HY(267)), (FX(235), HY(270)),
           (FX(210), HY(280)), (FX(195), HY(275))]
    z_pec = lambda u, v: -3.55 + 0.42 * u + 0.36 * (9.8 - v) + 0.1 * (u - 1.1)  # noqa: E731
    add(seg, "gold", sym(plate(pec, z_pec, 1.9, 0.16, 0.06)))
    # gold outer pec side wrap (259: gold x 190..205 at y 240..280)
    wrap = [(-0.6, 8.35), (0.6, 8.6), (0.5, 10.0), (-0.9, 10.0)]
    for s in (1, -1):
        add(seg, "gold", plate(wrap, lambda u, v: 3.15, 0.55, 0.1, 0.05,
                               frame=(lambda s: (lambda u, v, w: (s * w, v, -1.75 + u)))(s)))
    # lower white chevron under the chest (259: (230,268) .. V tip (285,295) .. (340,268) -> H 8.77..7.85)
    chev = [(0, 7.85), (1.95, 8.6), (1.95, 8.95), (0, 8.4)]
    add(seg, "white", sym(plate(chev, lambda u, v: -2.8 + 0.25 * u + 0.25 * (v - 7.85), 1.5, 0.1, 0.04, fold_x)))
    # blue under-chest accents (259: x 215..240 -> |X| 2.48..1.6, y 270..300 -> H 8.7..7.68)
    buc = [(1.55, 8.55), (2.55, 8.85), (2.6, 8.4), (2.0, 7.7)]
    add(seg, "blue", sym(plate(buc, lambda u, v: -2.3 + 0.2 * u, 1.3, 0.1, 0.04)))


def build_abdomen():
    seg = "abdomen"
    # 261 grey waist: y 262 half 46 px (1.62), y 300 half 48 (1.69, narrowest), y 335 half 56 (1.97);
    # segment lines at y 265 / 285 / 302 -> H 8.87 / 8.19 / 7.61.  259: x 240..335 at y 300.
    add(seg, "darkgrey", ml.loft([oct_ring(0, 6.3, 1.55, -1.0, 1.0, 0.4), oct_ring(0, 9.2, 1.45, -0.95, 0.95, 0.4)]))
    add(seg, "grey", band(6.45, 7.55, 2.0, 1.72, -1.3, 1.3))
    add(seg, "grey", band(7.65, 8.15, 1.7, 1.7, -1.22, 1.22))
    add(seg, "grey", band(8.25, 8.95, 1.72, 1.85, -1.22, 1.25))
    # grey front ab plates, wider than the back waist (259: x 235..337 at y 285, x 222..349 at y 345)
    ab = [(0, 6.4), (2.1, 6.4), (2.1, 6.9), (1.75, 8.35), (0.8, 8.25), (0, 7.35)]
    add(seg, "grey", sym(plate(ab, lambda u, v: -1.62 + 0.12 * u, 0.7, 0.1, 0.04, fold_x)))


def build_pelvis():
    seg = "pelvis"
    # dark core block + grey hip housings (hip balls at 261 x 225 / 365 -> |X| 2.46, y 525 -> H 0)
    add(seg, "darkgrey", box(-2.3, 2.3, 2.7, 6.55, -1.35, 1.35, 0.25))
    for s in (1, -1):
        hx = SOCKETS["RightHip"][0]  # grey hip housing centred over the hip ball
        add(seg, "grey", box(s * hx - 0.85, s * hx + 0.85, 0.75, 3.3, -0.95, 0.95, 0.2))
    for zs in (1.0, -1.0):  # back (+Z) and front (-Z) copies of the crotch armour
        inward = -zs
        # white centre plate (261: x 268..325 -> |X| 1.0, y 335..395 -> H 6.48..4.44, V cut)
        cp = [(0, 6.48), (1.0, 6.48), (1.0, 5.12), (0.5, 4.44), (0, 4.44)]
        add(seg, "white", sym(plate(cp, lambda u, v, zs=zs: zs * (1.85 - 0.25 * u), 0.7, 0.11, 0.04, fold_x,
                                    inward=inward)))
        # blue V (261: y 375..425 -> H 5.12..3.41, x 268..322)
        bv = [(0, 4.44), (0.5, 4.44), (1.0, 5.12), (1.0, 3.95), (0.8, 3.41), (0, 3.41)]
        add(seg, "blue", sym(plate(bv, lambda u, v, zs=zs: zs * (1.75 - 0.25 * u - 0.05 * (4.4 - v)), 0.7, 0.1,
                                   0.04, fold_x, inward=inward)))
        # white crotch tip (261: x 275..318 -> |X| 0.75, tip (296,452) -> H 2.49)
        ct = [(0, 3.41), (0.78, 3.41), (0.78, 2.95), (0, 2.49)]
        add(seg, "white", sym(plate(ct, lambda u, v, zs=zs: zs * (1.65 - 0.2 * u - 0.15 * (3.41 - v)), 0.8, 0.1,
                                    0.04, fold_x, inward=inward)))
        # side top white plates (261: (268,335) (225,333) (220,355) (258,378) -> |X| 1.0..2.7, H 6.55..5.0)
        st = [(1.05, 6.5), (2.55, 6.6), (2.75, 5.9), (2.35, 5.3), (1.05, 5.12)]
        add(seg, "white", sym(plate(st, lambda u, v, zs=zs: zs * (1.75 - 0.12 * (u - 1.0)), 0.65, 0.11, 0.04,
                                    inward=inward)))
        # grey diagonal straps (261: (220,355) -> (275,420), ~20 px wide)
        gs = [(2.95, 5.75), (2.7, 6.1), (0.9, 3.95), (1.05, 3.35)]
        add(seg, "grey", sym(plate(gs, lambda u, v, zs=zs: zs * 1.6, 0.6, 0.08, 0.04, inward=inward)))
        # rear / front skirt plate (261: inner edge (275,440)->(0.74,2.9), (270,420)->(0.92,3.58),
        #   top joins the strap at (200,350)->(3.38,5.97); bottom (200,515)->(3.38,0.34), (262,505)->(1.2,0.68))
        bot = 0.4 if zs > 0 else 1.3  # front skirts shorter for leg-raise clearance (assumption)
        sk = [(0.75, 2.9), (0.95, 3.6), (2.85, 5.55), (3.45, 5.75), (3.5, bot + 0.1), (3.3, bot),
              (1.2, bot + 0.3), (0.75, 2.0)]
        zsk = lambda u, v, zs=zs: zs * (1.9 + 0.12 * (5.5 - v) - 0.05 * (u - 0.75))  # flares out at the bottom
        add(seg, "white", sym(plate(sk, zsk, 0.55, 0.14, 0.05, inward=inward)))
        # layered lower plate with the curved top (261: x 210..265 -> |X| 3.0..1.1, y 448..505 -> H 2.6..0.68)
        lp = [(1.05, bot + 0.35), (3.1, bot + 0.2), (3.15, 2.55), (2.6, 2.75), (2.0, 2.82), (1.4, 2.75),
              (1.05, 2.55)]
        zlp = lambda u, v, zs=zs: zs * (2.55 + 0.12 * (2.6 - v) - 0.05 * (u - 1.0))  # noqa: E731
        add(seg, "white", sym(plate(lp, zlp, 0.5, 0.1, 0.04, inward=inward)))
    # outer side skirt plates in the (Z,H) plane (261 outer edge: (200,350) (186,390) (183,480) (200,515)
    #   -> |X| 3.38 @H5.97, 3.87 @4.6, 3.98 @1.55, 3.38 @0.34): flare out ~7 deg toward the bottom
    #   built as two facets folded along a vertical ridge (u = 0 -> Z +0.15) so the side is not a flat board
    side_f = [(-1.75, 5.6), (0.0, 5.6), (0.0, 0.35), (-1.45, 0.9), (-2.0, 1.8)]
    side_b = [(0.0, 5.6), (1.8, 5.6), (2.1, 1.2), (1.6, 0.35), (0.0, 0.35)]
    for s in (1.0, -1.0):
        def fr(u, v, w, s=s):
            x = 3.35 + (5.6 - v) * 0.11 + w  # outer face, flaring out toward the bottom
            return (s * x, v, u + 0.15)
        zf = lambda u, v: 0.7 - 0.2 * abs(u)  # noqa: E731  ridge stands 0.2..0.55 proud of the rim
        for pr in (side_f, side_b):
            add(seg, "white", plate(pr, zf, 0.75, 0.13, 0.06, fold_x, frame=fr, inward=-1.0))
        # blue insert near the back on the outer face (261: x 185..205 -> |X| 3.9..3.2, y 458..490 -> H 2.3..1.2)
        bi = [(0.5, 1.25), (1.45, 1.05), (1.5, 2.35), (0.55, 2.45)]
        add(seg, "blue", plate(bi, lambda u, v: 0.72 - 0.2 * u, 0.35, 0.06, 0.03, frame=fr, inward=-1.0))


def build_pauldrons():
    # 259 front, image-left (robot right, +X):
    #  white top slab  (70,177) (120,134) (190,135) (180,187)
    #  gold blade      (41,217) (70,195) (115,200) (145,182) (175,185) (182,202) (170,220) (120,227)
    #  261 back agrees within ~5 px; blade tip |X| 8.6.
    white = [(FX(70), HY(177)), (FX(120), HY(136)), (FX(190), HY(137)), (FX(182), HY(190)), (FX(145), HY(186)),
             (FX(115), HY(199)), (FX(68), HY(196))]
    gold = [(FX(41), HY(217)), (FX(70), HY(195)), (FX(115), HY(200)), (FX(145), HY(182)), (FX(175), HY(185)),
            (FX(182), HY(202)), (FX(170), HY(223)), (FX(120), HY(230))]
    # depth: white slab Z -1.65..+1.65 at the shoulder tapering to -1.15..+1.15 at the outer tip; heavy chamfers
    for s, seg in ((1.0, "pauldron_R"), (-1.0, "pauldron_L")):
        fr = (lambda s: (lambda u, v, w: (s * u, v, w)))(s)
        zw = lambda u, v: -1.65 + 0.12 * (u - 3.4)  # noqa: E731
        add(seg, "white", _tapered(white, zw, lambda u, v: 1.65 - 0.12 * (u - 3.4), 0.5, fr))
        # top cap ridge on the slab (raised white strip along the upper edge)
        cap = [(FX(118), HY(140)), (FX(188), HY(140)), (FX(189), HY(152)), (FX(125), HY(155)), (FX(80), HY(178)),
               (FX(74), HY(174))]
        add(seg, "white", _tapered(cap, lambda u, v: -1.25 + 0.1 * (u - 3.4), lambda u, v: 1.25 - 0.1 * (u - 3.4),
                                   0.25, fr))
        zg = lambda u, v: -1.35 + 0.1 * (u - 3.6)  # noqa: E731
        add(seg, "gold", _tapered(gold, zg, lambda u, v: 1.35 - 0.1 * (u - 3.6), 0.35, fr))
        # grey hinge block between pauldron and the shoulder ball
        # sits on top of the shoulder ball (ball centre |X| 4.29, H 11.27) under the white slab
        add(seg, "grey", plate([(3.35, 11.75), (5.2, 11.75), (5.2, 12.45), (3.35, 12.45)], lambda u, v: -0.85, 1.7,
                               0.15, 0.15, frame=fr))


def _tapered(poly, zfront, zback, ch, frame, raise_=0.0):
    """Plate with independent front (-Z) and back (+Z) planar faces, both chamfered by ch.
    raise_: lifts the whole outline by that much in H (used for the cap ridge)."""
    poly = [(float(u), float(v) + raise_) for u, v in poly]
    if ml.poly_area2(poly) < 0:
        poly = poly[::-1]
    P0 = _inset(poly, [ch] * len(poly))

    def ring(P, fn, off):
        return [frame(u, v, fn(u, v) + off) for (u, v) in P]
    rings = [ring(P0, zfront, 0.0), ring(poly, zfront, ch), ring(poly, zback, -ch), ring(P0, zback, 0.0)]
    return ml.loft(rings)


# ------------------------------------------------------------------ sockets / export

SOCKETS = {  # cells
    # neck: top of the grey collar ring (259 grey neck under the head y ~150 -> H 12.8)
    "Neck": (0.0, 12.95, 0.1),
    # shoulder balls, re-measured: only the lower-inner quadrant of the ball shows under the pauldron blade.
    #   261: right extreme x 198, bottom y 226 (at x ~185), arc reaches x 160 at y ~218 -> circle r ~28-32 px,
    #        centre ~(166..170, 194..198) -> |X| 4.44..4.58 cells, H 11.16..11.30
    #   259: right extreme x 188, bottom y 229 -> centre ~(160, 201) -> |X| 4.42, H 11.06
    #   arms helper (fit of their arm silhouette on 261): (3.5, 9.2) studs = (4.289, 11.275) cells.
    #   Settled on the arms helper's value (inside the sheet's measurement band) so both parts agree exactly.
    "RightShoulder": (3.5 / 0.816, 9.2 / 0.816, 0.2),
    "LeftShoulder": (-3.5 / 0.816, 9.2 / 0.816, 0.2),
    # hip balls (261: centres x 225 / 365 -> |X| 2.46, y 525 -> H 0); snapped to the legs helper's
    # hip_offsets_from_mech_centre = +-1.9511 studs = 2.391 cells so the parts assemble exactly
    "RightHip": (1.9511 / 0.816, 0.0, 0.0),
    "LeftHip": (-1.9511 / 0.816, 0.0, 0.0),
    # internal joints between torso segments
    "Waist": (0.0, 6.45, 0.0),   # pelvis <-> abdomen (bottom of the waist bands, 261 y 336)
    "Spine": (0.0, 8.95, 0.1),   # abdomen <-> chest (261 y 262)
}
PIVOTS = {
    "pelvis": (0.0, 0.0, 0.0),
    "abdomen": SOCKETS["Waist"],
    "chest": SOCKETS["Spine"],
    "pauldron_R": SOCKETS["RightShoulder"],
    "pauldron_L": SOCKETS["LeftShoulder"],
}
PARENT = {"pelvis": None, "abdomen": "pelvis", "chest": "abdomen", "pauldron_R": "chest", "pauldron_L": "chest"}


def main():
    parts.clear()
    build_chest()
    build_abdomen()
    build_pelvis()
    build_pauldrons()
    meshes = {}
    for (seg, col), ms in sorted(parts.items()):
        m = ml.combine(*ms).transformed(lambda p: p * S)
        meshes[(seg, col)] = m
    files = []
    for f in os.listdir(OUT):
        if f.endswith(".obj"):
            os.remove(os.path.join(OUT, f))
    for (seg, col), m in sorted(meshes.items()):
        name = "%s_%s.obj" % (seg, col)
        path = os.path.join(OUT, name)
        hdr = "mech2 torso - segment %s, colour %s %s\nunits: studs, +Y up, -Z forward, origin = hip-joint line centre" % (
            seg, col, COLORS[col])
        ntri, stretch, nisl = ml.write_obj(path, m, hdr)
        V, F = m.arrays()
        files.append({"file": name, "segment": seg, "colour": col, "hex": COLORS[col], "tris": int(ntri),
                      "open_edges": int(ml.open_edges(m)), "max_uv_stretch": round(float(stretch), 3),
                      "bbox_min": [round(float(c), 4) for c in V.min(0)],
                      "bbox_max": [round(float(c), 4) for c in V.max(0)],
                      "bbox_centre": [round(float(c), 4) for c in (V.min(0) + V.max(0)) / 2]})
        print("%-28s %5d tris  open=%d  stretch=%.3f" % (name, ntri, files[-1]["open_edges"], stretch))
    st = lambda p: [round(c * S, 4) for c in p]  # noqa: E731
    meta = {
        "part": "mech2 torso",
        "units": "studs",
        "cell_studs": S,
        "axes": "+Y up, -Z forward (Roblox), +X = robot's right",
        "origin": "centre of the hip-joint line (hip-ball centres, back sheet y=525px)",
        "vertex_space": "model space (all OBJs already in assembled position relative to the origin); "
                        "pivots/sockets below are in the same space",
        "uv": "planar per facet group, Roblox box-mapping orientation, 1 UV repeat = 4 studs, stretch <= 1.2",
        "colours": COLORS,
        "segments": {k: {"pivot": st(v), "parent": PARENT[k],
                         "files": [f["file"] for f in files if f["segment"] == k]} for k, v in PIVOTS.items()},
        "sockets": {k: st(v) for k, v in SOCKETS.items()},
        "sockets_cells": {k: list(v) for k, v in SOCKETS.items()},
        "files": files,
        "total_tris": int(sum(f["tris"] for f in files)),
    }
    with open(os.path.join(OUT, "meta.json"), "w", newline="\n") as fh:
        json.dump(meta, fh, indent=2)
    print("total tris", meta["total_tris"])
    return meshes


if __name__ == "__main__":
    main()
