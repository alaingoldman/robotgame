"""Armour-block builder for the mech2 legs (numpy only, uses meshlib.py).

block(): a faceted "visual-hull" block. It is defined by
  - a SIDE outline  [(z, y)]  (as seen in the sheet's SIDE view; -z = forward)
  - a FRONT outline [(x, y)]  (as seen in the FRONT view; +x = mech right)
Both outlines must be y-monotone (every horizontal line crosses them once).
At every vertex height of either outline the block's cross-section is the
rectangle  x-interval(front) x z-interval(side); between those heights both
intervals change linearly, so lofting the rectangles reproduces the exact
intersection of the two extruded outlines, i.e. its FRONT/BACK and SIDE
silhouettes are exactly the drawn outlines. The rectangle corners are then
chamfered (and optionally given a shallow front/back "prow" ridge): that adds
the crisp armour facets without changing either silhouette.
"""
import math

import numpy as np

from meshlib import Mesh, loft, weld, orient_outward, cap


def interval(poly, y):
    """Horizontal extent of a y-monotone polygon [(a, y)] at height y -> (lo, hi) or None."""
    xs = []
    n = len(poly)
    for i in range(n):
        a0, y0 = poly[i]
        a1, y1 = poly[(i + 1) % n]
        if (y0 - y) * (y1 - y) <= 0 and y0 != y1:
            t = (y - y0) / (y1 - y0)
            xs.append(a0 + (a1 - a0) * t)
        elif y0 == y1 == y:
            xs += [a0, a1]
    for a0, y0 in poly:
        if abs(y0 - y) < 1e-9:
            xs.append(a0)
    if not xs:
        return None
    return min(xs), max(xs)


def yrange(poly):
    ys = [p[1] for p in poly]
    return min(ys), max(ys)


def ring(x0, x1, z0, z1, y, cf, cb, pf, pb, ridge):
    """Octagon-ish cross-section (12 points, fixed count) of the box [x0,x1]x[z0,z1] at height y.
    cf/cb: chamfer of the front/back vertical edges; pf/pb: depth of the front/back centre
    ridge (corners pulled back, centre stays on the silhouette); ridge = x of the ridge as a
    fraction of the width (0..1)."""
    # never let a section collapse to a line/point (pointed ends of the outlines): keep it a tiny
    # rectangle so the loft stays a clean closed 2-manifold (invisible at this scale)
    MIN = 0.05
    if x1 - x0 < MIN:
        c = (x0 + x1) / 2
        x0, x1 = c - MIN / 2, c + MIN / 2
    if z1 - z0 < MIN:
        c = (z0 + z1) / 2
        z0, z1 = c - MIN / 2, c + MIN / 2
    w, d = x1 - x0, z1 - z0
    cf = min(cf, 0.42 * w, 0.42 * d)
    cb = min(cb, 0.42 * w, 0.42 * d)
    pf = min(pf, 0.25 * d)
    pb = min(pb, 0.25 * d)
    xm = x0 + w * ridge
    # the ridge pulls each corner back in proportion to its distance from the ridge line, and a
    # corner that sits ON the ridge (ridge = 0 or 1: a plate split in two halves) gets no chamfer,
    # so the two halves meet flush along the ridge
    far = max(xm - x0, x1 - xm, 1e-9)
    kl, kr = (xm - x0) / far, (x1 - xm) / far
    pfl, pfr, pbl, pbr = pf * kl, pf * kr, pb * kl, pb * kr
    cfl, cfr = cf * min(1.0, 4 * kl), cf * min(1.0, 4 * kr)
    cbl, cbr = cb * min(1.0, 4 * kl), cb * min(1.0, 4 * kr)
    pts = [
        (xm, z0),
        (x1 - cfr, z0 + pfr), (x1, z0 + pfr + cfr),
        (x1, z1 - pbr - cbr), (x1 - cbr, z1 - pbr),
        (xm, z1),
        (x0 + cbl, z1 - pbl), (x0, z1 - pbl - cbl),
        (x0, z0 + pfl + cfl), (x0 + cfl, z0 + pfl),
    ]
    return [(p[0], y, p[1]) for p in pts]


def block(side, front, cf=0.12, cb=0.12, pf=0.0, pb=0.0, ridge=0.5, extra_y=()):
    """See module doc. Units: cells, leg frame (hip centre = origin)."""
    ylo = max(yrange(side)[0], yrange(front)[0])
    yhi = min(yrange(side)[1], yrange(front)[1])
    ys = sorted(set([round(p[1], 6) for p in side + front if ylo - 1e-9 <= p[1] <= yhi + 1e-9] + [ylo, yhi] +
                    [y for y in extra_y if ylo < y < yhi]))
    rings = []
    for y in ys:
        xi = interval(front, y)
        zi = interval(side, y)
        if xi is None or zi is None:
            continue
        rings.append(ring(xi[0], xi[1], zi[0], zi[1], y, cf, cb, pf, pb, ridge))
    m = loft(rings[::-1])
    return m


def cylinder_x(c, r, x0, x1, n=12, bevel=0.06):
    """Faceted disc / axle along X centred at (y, z) = c, from x0 to x1, with bevelled rims."""
    y, z = c
    rings = []
    b = min(bevel, (x1 - x0) * 0.3)
    for x, rr in ((x0, r - b), (x0 + b, r), (x1 - b, r), (x1, r - b)):
        rings.append([(x, y + rr * math.cos(2 * math.pi * (k + 0.5) / n), z + rr * math.sin(2 * math.pi * (k + 0.5) / n))
                      for k in range(n)])
    return loft(rings)


def sphere(c, r, nu=14, nv=9):
    cx, cy, cz = c
    rings = []
    for j in range(1, nv):
        th = math.pi * j / nv
        rings.append([(cx + r * math.sin(th) * math.cos(2 * math.pi * k / nu), cy + r * math.cos(th),
                       cz + r * math.sin(th) * math.sin(2 * math.pi * k / nu)) for k in range(nu)])
    return loft(rings, apex0=(cx, cy + r, cz), apex1=(cx, cy - r, cz))
