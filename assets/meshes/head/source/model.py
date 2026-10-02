"""BRZ-01 Titan HEAD + NECK/COLLAR, modelled from the owner's FRONT / SIDE /
BACK head crops (refs/235, 236, 237 = zooms of refs/full_body_sheet.png).

Everything here is in HEAD SPACE, grid cells (HeadBuilder's frame: origin at
the neck base = leg space (0, 31.2, -1.5), +Y up, face toward -Z, +X = mech
right; 1 cell = 0.816 studs at Scale 1.7). build.py converts to studs in each
bone's frame. Numbers are read off the crops with refs.VIEWS' mapping (see
the comments: (cx, cy) are crop pixels).

Pieces (one MeshPart = one colour role):
  HeadMain    main   helmet dome (hexagon section with chamfered top, faceted
                     forehead), brow, jaw side plates, side bands round the ear
                     arch, rim under the back band, hidden face core
  HeadTrim    hi     faceplate (prow with a centre crease), cheek bars, ear pods
  HeadCrest   trim   crest spike + the raised ridge down the forehead
  HeadVisor   glow   chevron visor slit
  HeadRecess  recess visor surround, ear arch recesses, back band
  Gorget      main   collar ring (high at the back, low at the front, top
                     sloping inward) + the inner ledge round the neck
  GorgetRecess recess dark liner inside the ring + the neck column
  ThroatFold  main   the angular plate jutting forward under the chin
"""
import math

import numpy as np

from meshlib import Mesh, combine, loft, prism, slab, sym, torus_loft


def lerp(a, b, t):
    return a + (b - a) * t


def interp(table, h):
    """piecewise-linear lookup in [(key, value), ...] sorted by key."""
    if h <= table[0][0]:
        return table[0][1]
    for (h0, v0), (h1, v1) in zip(table, table[1:]):
        if h <= h1:
            return lerp(v0, v1, (h - h0) / (h1 - h0))
    return table[-1][1]


# ======================================================================
# HELMET SHELL
# ======================================================================
# per height: X half-width (FRONT: sides x 1.51 down to the chamfer at h 4.47,
# (cx 78/204, cy 103); chamfer to the flat top +-1.07 at h 5.31 (cx 96/185,
# cy 68)); zf = front of the forehead (SIDE: (100,100) -> z -1.64 h 4.92,
# (81,130) -> -2.09 4.20, (80,150) -> -2.12 3.71; over the top (120,89) ->
# -1.16 5.19, (140,82) -> -0.68 5.34); zs = front edge of the side wall (SIDE
# band edge cx ~101 -> z -1.62); zb = back (SIDE: (205,89) 0.89 5.19, (220,97)
# 1.25 4.98, (232,110) 1.55 4.68, (240,125) 1.73 4.32, (243,142) 1.80 3.89,
# (240,170) 1.73 3.23).
HELM_ROWS = [
    # h,    X,    zf,    zs,    zb
    (2.50, 1.47, -1.22, -1.22, 1.68),
    (3.38, 1.50, -1.22, -1.22, 1.76),
    (3.74, 1.51, -2.10, -1.62, 1.79),
    (4.20, 1.51, -2.07, -1.62, 1.77),
    (4.47, 1.51, -1.97, -1.62, 1.66),
    (4.68, 1.40, -1.84, -1.56, 1.55),
    (4.92, 1.24, -1.62, -1.42, 1.32),
    (5.10, 1.08, -1.28, -1.10, 1.02),  # FRONT/BACK: top corners (96,75)/(82,93) -> +-1.07 at h ~5.1
    (5.24, 0.72, -0.95, -0.85, 0.72),  # the top arches up to the centre (cy 66 / 86)
    (5.31, 0.36, -0.62, -0.55, 0.38),
]
FOREHEAD_HALF = 1.0  # FRONT: the forehead's flat front ends at x +-1.0 (cx 97..99), angled facets out to the walls


def helmet_ring(h, X, zf, zs, zb, grow=0.0):
    xf = min(FOREHEAD_HALF, X - 0.12)
    X = X + grow
    zf, zs, zb = zf - grow, zs - grow, zb + grow
    r = min(0.62, (zb - zs) * 0.35)
    pts = [(-xf, zf), (xf, zf), (X, zs)]
    # rounded back corners
    for k in range(5):
        a = math.radians(90 * k / 4)
        pts.append((X - r + r * math.cos(a), zb - r + r * math.sin(a)))
    for k in range(5):
        a = math.radians(90 + 90 * k / 4)
        pts.append((-(X - r) + r * math.cos(a), zb - r + r * math.sin(a)))
    pts.append((-X, zs))
    return [(x, h, z) for x, z in pts]


def helmet_profile_at(h):
    """(X, zf, zs, zb) at height h (linear between the rows)."""
    rows = HELM_ROWS
    if h <= rows[0][0]:
        return rows[0][1:]
    for a, b in zip(rows, rows[1:]):
        if h <= b[0]:
            t = (h - a[0]) / (b[0] - a[0])
            return tuple(lerp(a[i], b[i], t) for i in range(1, 5))
    return rows[-1][1:]


def helmet_shell():
    rings = [helmet_ring(*r) for r in HELM_ROWS]
    return loft(rings)


def helmet_back_strip(h0, h1, grow, inset, half=1.40):
    """a strip wrapped round the back of the helmet between x -half..half,
    standing `grow` proud of the shell and `inset` deep."""
    hm = (h0 + h1) / 2
    X, zf, zs, zb = helmet_profile_at(hm)
    ring = helmet_ring(hm, X, zf, zs, zb)
    pts = [(p[0], p[2]) for p in ring]
    # walk the back part of the ring (indices 3..12 are the rounded back)
    back = pts[3:13]
    # keep only |x| <= half (+ interpolated ends)
    path = []
    for i in range(len(back) - 1):
        a, b = back[i], back[i + 1]
        if abs(a[0]) <= half:
            path.append(a)
        if (abs(a[0]) - half) * (abs(b[0]) - half) < 0:
            t = (abs(a[0]) - half) / (abs(a[0]) - abs(b[0]))
            path.append((lerp(a[0], b[0], t), lerp(a[1], b[1], t)))
    if abs(back[-1][0]) <= half:
        path.append(back[-1])
    # side walls of the strip: clip from x = +half on the side wall too
    out_path, in_path = [], []
    for i, (x, z) in enumerate(path):
        # outward normal of the path (centre of the plan ~ (0, 0.2))
        n = np.array([x, z - 0.2])
        n /= np.linalg.norm(n) + 1e-9
        out_path.append((x + n[0] * grow, z + n[1] * grow))
        in_path.append((x - n[0] * inset, z - n[1] * inset))
    poly = out_path + in_path[::-1]
    return prism([(x, z) for x, z in poly], "y", h0, h1)


# ======================================================================
# CREST SPIKE + FOREHEAD RIDGE
# ======================================================================
# FRONT: tip (140.5, 15) -> h 6.58; blade +-0.20 at cy 57 (h 5.58); ridge
# +-0.38 at cy 128 (h 3.87), pointed bottom at cy 153 (h 3.27).
# SIDE: tip (77, 34) -> z -2.19 h 6.50; front edge down to (66, 150) -> z
# -2.45 h 3.71; back edge to the dome at (100, 100) -> z -1.64 h 4.92.
SPIKE_TIP = (0.0, 6.54, -2.20)


def crest():
    rows = [
        # h, half-width, z front
        (5.58, 0.20, -2.27),
        (4.92, 0.29, -2.33),
        (4.20, 0.36, -2.40),
        (3.80, 0.38, -2.46),
        # owner review: the ridge runs on DOWN over the brow as a raised,
        # tapering ridge, its point just above the visor's peak (h 2.93)
        (3.62, 0.33, -2.50),
        (3.30, 0.20, -2.51),
    ]
    rings = []
    for h, w, zfr in rows:
        X, zf, zs, zb = helmet_profile_at(h)
        zbk = min(zf + 0.12, -1.55)  # sunk into the forehead
        if h > 5.0:
            zbk = lerp(-1.87, -1.55, (5.58 - h) / 0.66)  # SIDE: blade's own back edge above the dome
        zm = zbk - 0.08
        if h < 3.75:  # on the brow: sides sunk just into the brow's front (z -2.44 + 0.62|x|)
            zm = -2.44 + 0.62 * w + 0.02
            zbk = zm + 0.05
        rings.append([(0, h, zfr), (w, h, zm), (0, h, zbk), (-w, h, zm)])
    return loft(rings, apex0=SPIKE_TIP, apex1=(0.0, 3.00, -2.47))


# ======================================================================
# FACE: brow, visor, faceplate (prow), cheek bars, jaw plates
# ======================================================================
SWEEP = 0.76  # SIDE: visor centre z -2.07 (cx 82), its end at x 1.0 z -1.31 (cx 113) -> 0.76 per cell


def face_zc(h):
    """the faceplate's centre crease (SIDE front contour): top ledge under the
    visor (81,197) -> z -2.10 h 2.58, jutting corner (67,207) -> -2.43 h 2.34,
    sloping back to the chin (90,268) -> -1.88 h 0.88."""
    return interp([(0.42, -1.70), (0.88, -1.88), (2.34, -2.43), (2.60, -2.08)], h)  # CHIN: recedes to its point (owner: pointed chin piece)


FACE_FOLDS = (2.34, 0.88)


def face_z(x, h):
    return face_zc(h) + SWEEP * abs(x)


# FRONT (crop px -> cells): visor frame top (93,152)/(140,168)/(188,152) ->
# sides (+-1.14, 3.29), centre (0, 2.91); its bottom (97,168)/(140,185) ->
# (+-1.04, 2.93), (0, 2.50); the slit (100,157)/(140,172)/(182,157) top,
# (100,165)/(140,182) bottom -> sides 3.17 / 2.98, centre 2.81 / 2.57.
BROW_POLY = [(-1.16, 3.31), (0.0, 2.93), (1.16, 3.31), (1.12, 3.80), (-1.12, 3.80)]
FRAME_POLY = [(-1.12, 3.31), (0.0, 2.93), (1.12, 3.31), (1.08, 2.93), (0.0, 2.50), (-1.08, 2.93)]
SLIT_POLY = [(-0.99, 3.17), (0.0, 2.81), (0.99, 3.17), (0.99, 2.98), (0.0, 2.57), (-0.99, 2.98)]
# owner review: the faceplate continues below the cheek bars into a pointed
# CHIN (two angled plates meeting at the centre crease), ending at h 0.42 -
# the face is lengthened ~0.35 below the sheet's chin (0.77) and the whole
# helmet is mounted HEAD_RAISE higher (build.py) so it clears the gorget,
# throat fold and chest yoke in perspective.
# faceplate (between the cheek bars), cheek bars (cx 98..111 at cy 197 ->
# 120 at cy 248), jaw side plates out to the face's outer contour (78,187)
# -> (+-1.50, 2.45), (78,213) -> 1.80, (115,248) -> (+-0.61, 0.98), chin
# (140.5, 257) -> 0.77
FACE_POLY = [(0.0, 2.50), (1.04, 2.93), (1.02, 2.21), (0.71, 2.13), (0.49, 0.99), (0.40, 0.70), (0.0, 0.42),
             (-0.40, 0.70), (-0.49, 0.99), (-0.71, 2.13), (-1.02, 2.21), (-1.04, 2.93)]
BAR_POLY = [(1.02, 2.21), (0.71, 2.13), (0.49, 0.99), (0.66, 0.97)]  # right; mirrored
JAW_POLY = [(1.04, 2.93), (1.47, 2.47), (1.49, 1.80), (0.64, 0.95), (1.02, 2.21)]  # right; mirrored


def brow():
    def zfr(x, h):
        return -2.44 + 0.62 * abs(x)
    return slab(BROW_POLY, zfr, lambda x, h: 0.55)


def visor_frame():
    return slab(FRAME_POLY, lambda x, h: -2.07 + SWEEP * min(abs(x), 1.0) + 0.04, 0.35)


def visor_slit():
    # owner: the glow must fill the WHOLE slit opening edge to edge, i.e. the
    # visor surround's face (FRAME_POLY) between brow and faceplate, inset
    # 0.01 and set 0.02 in front of it (no z-fighting); same facets as the frame
    inset = [(x * (1 - 0.01 / 1.12), h) for x, h in FRAME_POLY]
    return slab(inset, lambda x, h: -2.07 + SWEEP * min(abs(x), 1.0) + 0.02, 0.12)


def faceplate():
    return slab(FACE_POLY, face_z, 0.4, cuts_h=FACE_FOLDS)


def cheek_bars():
    bar = slab(BAR_POLY, lambda x, h: face_z(x, h) - 0.09, 0.3, fold_x=False, cuts_h=FACE_FOLDS)
    return sym(bar)


def jaw_plates():
    jaw = slab(JAW_POLY, lambda x, h: face_z(x, h) + 0.03, lambda x, h: max(0.25, -0.55 - (face_z(x, h) + 0.03)),
               fold_x=False, cuts_h=FACE_FOLDS)
    return sym(jaw)


def face_core():
    poly = [(-1.42, 2.95), (1.42, 2.95), (1.42, 1.80), (0.52, 0.95), (0.0, 0.55), (-0.52, 0.95), (-1.42, 1.80)]
    return slab(poly, lambda x, h: face_z(x, h) + 0.3, lambda x, h: max(0.3, -0.2 - (face_z(x, h) + 0.3)), cuts_h=FACE_FOLDS)


# ======================================================================
# EARS: raised band round a dark arch recess, ear pod disc
# ======================================================================
# SIDE: dark arch from (130,190) -> z -0.92 h 2.75 up to h 4.27 (cy 127);
# pod (light) top (185,148) -> h 3.76, left (150,..) -> z -0.44.
# FRONT: pods cx 64..80 / 200..215 -> x 1.45..1.81, cy 128..187 -> h 2.45..3.87.
EAR_C = (0.35, 3.16)  # (z, h)
EAR_POD_R = 0.74
ARCH_R = 1.12
BAND_W = 0.22
ARCH_FOOT = 2.56
WALL_X = 1.505


def arch_poly(r, foot, n=12):
    zc, hc = EAR_C
    pts = [(zc + r, foot)]
    for k in range(n + 1):
        a = math.pi * k / n
        pts.append((zc + r * math.cos(a), hc + r * math.sin(a)))
    pts.append((zc - r, foot))
    return pts


def ear_side():
    band_outer = arch_poly(ARCH_R + BAND_W, ARCH_FOOT)
    band_inner = arch_poly(ARCH_R, ARCH_FOOT + 0.001)
    band = band_outer + band_inner[::-1]
    # U-shaped band (main), x 1.43..1.58
    band_m = prism(band, "x", WALL_X - 0.08, 1.58)
    recess = prism(arch_poly(ARCH_R + 0.02, ARCH_FOOT), "x", WALL_X - 0.08, 1.545)
    pod_rings = []
    for x, r in ((WALL_X - 0.05, EAR_POD_R), (1.72, EAR_POD_R), (1.81, EAR_POD_R - 0.16)):
        pod_rings.append([(x, EAR_C[1] + r * math.sin(a), EAR_C[0] + r * math.cos(a))
                          for a in np.linspace(0, 2 * math.pi, 20, endpoint=False)])
    pod = loft(pod_rings)
    return sym(band_m), sym(recess), sym(pod)


# ======================================================================
# GORGET RING + inner ledge + recess liner + neck
# ======================================================================
# FRONT: outer x +-2.69 (cx 28); ring top behind the head cy 173 -> h 2.79;
# side wall cy 212..255 -> h 1.85..0.82; the front-diagonal facets drop to
# the throat plate at x +-1.26 (cx 88/193). BACK: top h 2.79..2.86 at the
# centre, 2.48 at x 2.05, 2.19 at x 2.53 (rounded shoulders).
RING_ZC = 0.85
RING_R = 2.74
RING_RZ_BACK = 2.55
RING_FRONT_Z = -1.80
RING_T = 0.42


def ring_outline(dr=0.0):
    """closed plan outline (x, z), clockwise from the front centre round the
    right side, shrunk by dr (approx. offset)."""
    zc = RING_ZC
    R, Rb, zf = RING_R - dr, RING_RZ_BACK - dr, RING_FRONT_Z + dr
    right = [(0.0, zf), (0.6, zf), (1.26 - dr * 0.4, zf), (1.80 - dr * 0.8, zf + 0.52 + dr * 0.1),
             (2.30 - dr * 0.95, zf + 1.20 + dr * 0.15), (R - 0.02, zc - 0.55), (R, zc)]
    for k in range(1, 7):
        a = math.radians(15 * k)
        right.append((R * math.cos(a), zc + Rb * math.sin(a)))
    left = [(-x, z) for x, z in right[1:-1][::-1]]
    return right + left  # front centre .. right .. back centre .. left


def ring_heights(x, z):
    """outer top T, bottom B, ledge L at a plan point (front lower, back high)."""
    zc = RING_ZC
    if z >= zc:
        b = min(1.0, (z - zc) / RING_RZ_BACK)
        T = 2.02 + 0.84 * b
        B = 0.80 - 0.60 * b
        L = 1.20 + 0.55 * b
    else:
        f = min(1.0, (zc - z) / (zc - RING_FRONT_Z))
        T = 2.02 - 1.57 * f ** 0.8
        B = 0.80 - 1.55 * f ** 0.9
        L = 1.20 - 0.72 * f ** 0.9
    return T, B, L


def gorget_ring():
    outer = ring_outline(0.0)
    inner = ring_outline(RING_T)
    rings = []
    for (xo, zo), (xi, zi) in zip(outer, inner):
        T, B, L = ring_heights(xo, zo)
        rings.append([(xo, B, zo), (xo, T, zo), (xi, T - 0.25, zi), (xi, B, zi)])
    return torus_loft(rings)


NECK_ZC = 0.35


def neck_outline(r=1.0, n=16):
    return [(1.42 * r * math.sin(2 * math.pi * k / n), NECK_ZC - 1.30 * r * math.cos(2 * math.pi * k / n))
            for k in range(n)]


def ledge():
    """light inner step round the neck (FRONT: cy 266 / 275 at the front ->
    h 0.55 / 0.33, rising to (52, 238) -> x 2.13 h 1.23 at the sides)."""
    inner = ring_outline(RING_T + 0.04)
    rings = []
    for (xo, zo) in inner:
        T, B, L = ring_heights(xo, zo)
        # radial point toward the neck
        d = np.array([xo, zo - NECK_ZC])
        d /= np.linalg.norm(d) + 1e-9
        xn, zn = d[0] * 1.30, NECK_ZC + d[1] * 1.22
        rings.append([(xo, L - 0.35, zo), (xo, L, zo), (xn, L + 0.08, zn), (xn, L - 0.35, zn)])
    return torus_loft(rings)


def recess_liner():
    """dark inner wall of the ring, from just under its top down to the ledge."""
    a = ring_outline(RING_T - 0.02)
    b = ring_outline(RING_T + 0.06)
    rings = []
    for (xa, za), (xb, zb) in zip(a, b):
        T, B, L = ring_heights(xa, za)
        rings.append([(xa, L - 0.1, za), (xa, T - 0.30, za), (xb, T - 0.30, zb), (xb, L - 0.1, zb)])
    return torus_loft(rings)


def neck():
    pts = neck_outline()
    return prism(pts, "y", -0.3, 3.4)  # up into the helmet, which the Titan mounts HEAD_RAISE higher


# ======================================================================
# THROAT FOLD (welded to the Chest bone)
# ======================================================================
# SIDE: (90,276) -> z -1.86 h 0.70, tip (46,301) -> -2.90 0.11, front bottom
# (50,333) -> -2.81 -0.69, underside back to (88,314) -> -1.90 -0.23.
# FRONT: front face +-1.26 (cx 88..193) h 0.10..-0.73 (cy 285..320), the
# sloped top band +-1.08 (cx 95..185) up to cy 266 (h 0.55).
THROAT_PROFILE = [(-1.50, 0.78), (-1.86, 0.70), (-2.90, 0.11), (-2.84, -0.74), (-1.90, -0.25), (-1.50, -0.25)]
THROAT_HALF = [1.10, 1.10, 1.32, 1.32, 1.32, 1.32]


def throat_fold():
    L = [(-w, h, z) for (z, h), w in zip(THROAT_PROFILE, THROAT_HALF)]
    R = [(w, h, z) for (z, h), w in zip(THROAT_PROFILE, THROAT_HALF)]
    return loft([L, R])


# ======================================================================

def pieces():
    band, recess, pod = ear_side()
    return {
        "Titan_HeadMain": combine(helmet_shell(), brow(), jaw_plates(), face_core(), band,
                                  helmet_back_strip(2.96, 3.42, 0.07, 0.25)),
        "Titan_HeadTrim": combine(faceplate(), cheek_bars(), pod),
        "Titan_HeadCrest": crest(),
        "Titan_HeadVisor": visor_slit(),
        "Titan_HeadRecess": combine(visor_frame(), recess, helmet_back_strip(3.44, 3.87, 0.05, 0.25)),
        "Titan_Gorget": combine(gorget_ring(), ledge()),
        "Titan_GorgetRecess": combine(recess_liner(), neck()),
        "Titan_ThroatFold": throat_fold(),
    }
