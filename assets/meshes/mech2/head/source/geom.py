"""mech2 HEAD geometry, in GRID CELLS (1 cell = 0.816 studs; build.py scales).

Axes: X = mech's left/right (symmetric), +Y up, -Z forward (face).
Origin = neck base = top of the torso collar (2.75 cells below grid line G,
see refs.py). Every number below is measured from the reference masks
(refs.py prints per-row extents); comments give the source as
"view y<px> -> value" (Y from rows, X from the front/back sheet, Z from the
side sheet: Z = (x_side - 115) / 28.5).

Pieces (each separate closed shell, grouped by colour):
  GOLD : crown (faceted beak dome), brow band (V-plan visor plate)
  WHITE: skull (octagonal back shell), 2 chin chevron plates, blades B1-B3,
         cheek blade B4 (x2 sides)
  BLUE : upper side fins (between gold and wings), cheek fins behind B4
  GREY : neck
"""
import numpy as np

from meshlib import Mesh, combine, loft, slab, sym, weld, orient_outward


def mirror_half(half):
    """half outline (X >= 0) from the top centre point clockwise to the
    bottom centre point -> full closed polygon."""
    right = [tuple(p) for p in half]
    left = [(-x, y) for x, y in reversed(half[1:-1])]
    return right + left


# ---------------------------------------------------------------- GOLD
# crown ridge (front-most centre line, side sheet gold front edge):
#   side y64 -> Y2.99 z-0.30 (peak) ; y84 -> Y2.31 z-1.44 ; y116 -> Y1.22 z-2.46
RIDGE = [(1.10, -2.40), (2.31, -1.40), (2.98, -0.28)]
CROWN_BACK = -0.25  # side: gold back edge x=107-108 -> z = -0.27..-0.25 for Y 1.9..2.99
A_IN, A_OUT, X_CREASE = 1.5, 3.0, 0.8  # facet slopes dz/d|X|; crease at front x=62 -> |X| 0.8


def ridge_z(Y):
    ys = [r[0] for r in RIDGE]
    zs = [r[1] for r in RIDGE]
    return float(np.interp(Y, ys, zs))


def crown():
    # front sheet gold half-widths: y60 Y3.02 0 ; y64 Y2.89 0.35 ; y68 Y2.75 0.62 ;
    # y72 Y2.61 0.75 ; y80 Y2.34 0.82 ; y84 Y2.21 0.90 ; y88 Y2.07 1.00 ; y92 Y1.93 1.07
    # bottom follows the brow band top edge (front y97 x40 -> X1.58 Y1.76 down to y117 x85 -> Y1.08)
    half = [(0.0, 2.98), (0.35, 2.89), (0.62, 2.76), (0.76, 2.60), (0.83, 2.38), (0.92, 2.20),
            (1.02, 2.06), (1.09, 1.92), (1.10, 1.62), (0.55, 1.36), (0.0, 1.12)]
    poly = mirror_half(half)

    def zf(x, h):
        ax = abs(x)
        z = ridge_z(h) + A_IN * min(ax, X_CREASE) + A_OUT * max(0.0, ax - X_CREASE)
        return min(z, CROWN_BACK - 0.06)

    def th(x, h):
        return max(0.06, CROWN_BACK - zf(x, h))

    return slab(poly, zf, th, fold_x=True, cuts_h=(2.31,), cuts_x=(-X_CREASE, X_CREASE))


def band():
    """Gold brow/visor: a V-plan plate wrapping from the prow (z -2.5) back to
    the temples (z +0.18). Rings across X: [top_out, mid_out, bot_out, bot_in, top_in]."""
    def col(x, top, mid, bot, inset_x, inset_z):
        s = 1 if x >= 0 else -1
        to = (x, top[0], top[1])
        mo = (x, mid[0], mid[1])
        bo = (x, bot[0], bot[1])
        bi = (x - s * inset_x, bot[0] + 0.10, bot[1] + inset_z)
        ti = (x - s * inset_x, top[0] + 0.02, top[1] + inset_z)
        return [to, mo, bo, bi, ti]
    # outer end: front y97..112 x40 -> X1.50..1.58, Y1.80..1.25 ; side band back x120-121 -> z0.18
    end = lambda s: col(s * 1.50, (1.80, 0.18), (1.40, 0.22), (0.98, 0.16), 0.30, 0.10)
    # X 1.05: top edge on the y97->y117 line -> Y1.53 ; front gold half-width 1.03 at y124 -> bottom Y0.82 ;
    # side bottom edge line (Y0.27 z-1.61)->(Y0.95 z-0.04) -> z-0.42 at Y0.82
    mid = lambda s: col(s * 1.05, (1.55, -0.92), (1.18, -0.70), (0.80, -0.42), 0.25, 0.32)
    # centre: side front edge y116 Y1.22 z-2.46, y120 Y1.08 z-2.49, y128 Y0.81 z-2.14,
    # y136 Y0.54 z-1.93, y144 Y0.27 z-1.61 ; front V tip y140-142 -> Y0.30
    centre = [(0.0, 1.14, -2.52), (0.0, 0.72, -2.10), (0.0, 0.28, -1.62), (0.0, 0.42, -1.12), (0.0, 1.18, -2.02)]
    rings = [end(-1), mid(-1), centre, mid(1), end(1)]
    return loft(rings)


# ---------------------------------------------------------------- WHITE
def skull():
    """Octagonal back shell. back sheet white half-widths: y72 Y2.78 0.56 ; y76 Y2.65 0.72 ;
    y80 Y2.51 0.90 ; y84 Y2.38 1.00 ; y92 Y2.10 1.12 ; y100 Y1.83 1.24 ; original lines x75/x150 -> 1.30
    for y100..135 ; bottom y145 -> Y0.30, chamfer corners x~88/137 -> 0.85.
    side: top y68-72 -> Y2.78 from z-0.21 to 0.9 ; back face x168 -> z1.86 (y100..135, Y1.76..0.57),
    so the lower back chamfer seen in the back sheet is a narrowing in X, not in Z."""
    # (Y, half width W, back z, front z)
    levels = [(0.26, 0.85, 1.45, -0.35), (0.57, 1.22, 1.86, -0.55), (1.08, 1.30, 1.86, -0.60),
              (2.00, 1.24, 1.86, -0.35), (2.38, 1.06, 1.50, -0.25), (2.62, 0.86, 1.22, -0.20),
              (2.86, 0.56, 1.05, -0.16)]
    rings = []
    for Y, W, zb, zf in levels:
        # back sheet panels: centre column x93..132 -> |X| 0.68 of 1.30 = 0.52 W
        # front corners pulled in / back so they stay inside the gold brow band
        rings.append([(0.52 * W, Y, zb), (W, Y, zb - 0.55), (0.88 * W, Y, zf + 0.55), (0.5 * W, Y, zf),
                      (-0.5 * W, Y, zf), (-0.88 * W, Y, zf + 0.55), (-W, Y, zb - 0.55), (-0.52 * W, Y, zb)])
    return loft(rings)


def chevron(half, zc, slope, thick):
    def zf(x, h):
        return zc(h) + slope * abs(x)
    return slab(mirror_half(half), zf, thick, fold_x=True)


def chin():
    # upper chevron: top = band bottom V (front y140 Y0.30 centre, y128 X0.75 Y0.71);
    # bottom V front y152 -> Y-0.11 centre ; side y132-148 front z -1.44..-1.51
    ch1 = chevron([(0.0, 0.36), (0.80, 0.64), (0.96, 0.54), (0.95, 0.20), (0.0, -0.12)],
                  lambda h: -1.50 + 0.05 * (0.36 - h), 0.75, 0.32)
    # lower chevron, stepped 0.12 back, tip leaning slightly forward (reads as a separate plate): front y164 -> Y-0.52 centre tip ; side y164 Y-0.41 z-1.40
    ch2 = chevron([(0.0, 0.05), (0.80, 0.45), (0.92, 0.30), (0.88, -0.08), (0.0, -0.55)],
                  lambda h: -1.38 + 0.10 * (h - 0.05), 0.75, 0.32)
    return combine(ch1, ch2)


def blade(Rt, Rb, T, th, ts=(0.0, 0.3, 0.6, 0.85)):
    """Tapered faceted blade: root edge Rt-Rb, tip T, hexagonal (diamond-edged)
    cross-section of thickness th tapering to the point. Closed shell."""
    Rt, Rb, T = map(lambda p: np.array(p, float), (Rt, Rb, T))
    mid0 = (Rt + Rb) / 2
    n = np.cross(T - mid0, Rt - Rb)
    n /= np.linalg.norm(n)
    rings = []
    for t in ts:
        top = Rt + (T - Rt) * t
        bot = Rb + (T - Rb) * t
        m = (top + bot) / 2
        h = th / 2 * (1 - 0.55 * t)
        rings.append([top, m + 0.45 * (top - m) + n * h, m + 0.45 * (bot - m) + n * h,
                      bot, m + 0.45 * (bot - m) - n * h, m + 0.45 * (top - m) - n * h])
    return loft(rings, apex1=T)


# blade keypoints (left side X < 0; mirrored). (X, Y, Z)
BLADES = {
    # B1 tip: front y24 x24 -> X-2.12 Y4.25 ; side y28 x200 -> Z2.98 ; back y32 -> X-2.07
    # side upper edge (z1.19 Y2.85)->(tip) ; lower edge (z1.68 Y2.27)->(tip)
    "B1": dict(Rt=(-1.62, 2.80, 1.10), Rb=(-1.68, 1.75, 1.75), T=(-2.14, 4.25, 3.04), th=0.42),
    # B2 tip: front y77 x27 -> X-2.04 Y2.44 ; side y78 x185 -> Z2.46 ; lower edge (z1.93 Y1.76)
    "B2": dict(Rt=(-1.58, 2.20, 0.75), Rb=(-1.68, 0.75, 1.00), T=(-2.06, 2.47, 2.46), th=0.36),
    # B3 tip: front y105 x32 -> X-1.86 Y1.49 ; side y108 x175 -> Z2.11 ; side edges (z0.67 Y1.08)/(z0.74 Y0.54)
    "B3": dict(Rt=(-1.45, 1.15, 0.50), Rb=(-1.36, 0.02, 0.75), T=(-1.84, 1.49, 2.11), th=0.30),
}


def wings():
    parts = [blade(**BLADES[k]) for k in ("B1", "B2", "B3")]
    return sym(combine(*parts))


def cheek_blade():
    """B4: white jaw strip. side: from chin x74 y159 (z-1.44 Y-0.39) up-back to
    x134 y120 (z0.67 Y0.94); front: x49-64 y123..161 (X-1.26..-0.74), leaning in at the bottom."""
    bl = blade(Rt=(-1.22, 1.05, 0.62), Rb=(-1.24, 0.62, 0.72), T=(-0.98, -0.42, -1.38), th=0.20,
               ts=(0.0, 0.5, 0.9))
    return sym(bl)


def white():
    return combine(skull(), chin(), wings(), cheek_blade())


# ---------------------------------------------------------------- BLUE
def upper_fin():
    """Blue fin between the gold crown and the wings. side sheet polygon (z, Y)
    from the blue rows: y68 Y2.85 0.77..1.16 ; y76 Y2.58 0.56..1.09 ; y84 Y2.31 0.18..0.98 ;
    y92 Y2.04 0.00..0.88 ; y104 Y1.63 0.21..0.91 ; y120 Y1.08 0.21..0.53.
    X: front y88 -1.65..-1.05, y64 -1.61..-1.44 (narrows to the tip) ; back -1.52..-1.17."""
    side = [(1.14, 2.97), (1.18, 2.80), (1.05, 2.46), (0.88, 2.22), (0.90, 1.30), (0.62, 1.02),
            (0.20, 1.02), (0.20, 1.66), (0.00, 1.96), (0.04, 2.22), (0.52, 2.62), (1.00, 2.95)]

    def xin(Y):
        return -1.05 - max(0.0, Y - 2.0) * 0.42

    def xout(Y):
        return -1.64 + max(0.0, Y - 2.4) * 0.12
    # loft along X (inner -> outer) of the side polygon; X depends on Y per vertex
    r_in = [(xin(Y), Y, z) for z, Y in side]
    r_out = [(xout(Y), Y, z) for z, Y in side]
    m = loft([r_in, r_out])
    return sym(m)


def cheek_fin():
    """Blue fin behind B4 (front: blue both sides of B4 at x45-52 and x55-63 -> X-1.40..-0.80 ;
    side: blue peeks out at x120-134 y130-137 -> z0.18..0.67, Y0.6..0.8)."""
    bl = blade(Rt=(-1.12, 1.02, 0.80), Rb=(-1.14, 0.80, 0.86), T=(-1.02, -0.22, -1.05), th=0.50,
               ts=(0.0, 0.5, 0.9))
    return sym(bl)


def blue():
    return combine(upper_fin(), cheek_fin())


# ---------------------------------------------------------------- GREY
def neck():
    """Octagonal neck plug. back sheet grey y144-148 -> X-0.75..+0.73 under the skull ;
    side y164 grey z-0.88..-0.60 (front of neck) ; front grey y156-164 beside the chin.
    Runs from Y-0.60 (0.49 studs into the torso socket) up into the skull (Y1.3)."""
    rx, rz = 0.82, 0.74
    ring = lambda Y: [(rx * np.cos(a), Y, rz * np.sin(a)) for a in np.arange(8) * np.pi / 4 + np.pi / 8]
    return loft([ring(-0.60), ring(1.30)])


def gold():
    return combine(crown(), band())


def all_parts():
    return {"Gold": gold(), "White": white(), "Blue": blue(), "Neck": neck()}
