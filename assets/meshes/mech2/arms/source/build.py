"""mech2 ARMS + HANDS -> OBJ meshes (one mesh per colour per rigid segment), meta.json.

Re-runnable:  python build.py      (numpy only; meshlib.py is a copy of ../../legs/source/meshlib.py)

Frame (per arm, RIGHT arm built, LEFT = mirror x -> -x):
  origin = SHOULDER ball centre, +Y up, -Z forward (front), +Z back, +X = outward for the RIGHT arm
  (Roblox: a model facing -Z has its right side at +X). Units = studs, 1 grid cell = 0.816 studs.
  Rest pose = arm hanging straight down (shoulder roll 0). The reference sheet draws the arm in an A-pose;
  render.py poses the segments with the pivots below to compare against it.

Every number below is from refs/261.png (full-body BACK view, the primary reference) unless marked:
  261.png grid: 28.45 px per cell horizontally, 28.8 px vertically -> rescaled to square pixels,
  34.87 px per stud. Measured on the arm straightened about its own axis (see measure.py):
  upper arm straightened about the shoulder (25.6 deg roll in the drawing), forearm about the elbow (16.3 deg).
  [A] = assumption (hidden in all views / depth, which a back view cannot show): see README.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from meshlib import Mesh, combine, loft, open_edges, write_obj  # noqa: E402

CELL = 0.816  # studs per grid cell (same as the other mech2 parts)

COLOURS = {  # colour roles (brief): one mesh per colour
	"White": (242, 242, 242),
	"Gold": (212, 169, 58),
	"Blue": (47, 111, 191),  # not used on the arm (no blue in the arm in 259/260/261)
	"Grey": (138, 138, 138),
	"DarkGrey": (90, 90, 90),
}

# ------------------------------------------------------------------ measurements (studs)
SHOULDER_R = 0.65  # [A] ball is mostly under the pauldron; visible grey 0.77 wide just above the upper block
UB_TOP, UB_BOT = -0.55, -2.70  # upper white block: top 19 px, bottom 94 px below the shoulder centre
UB_CX, UB_HW = 0.10, 0.86  # centre 5 px outward, width 60 px = 1.72 studs (2.1 cells)
UB_HD = 0.72  # [A] depth 1.45 studs: upper arm in side view 260.png is ~1.75 cells deep
CORE_R = 0.42  # [A] grey upper-arm core (hidden inside the block; ties ball, block and elbow together)
ELBOW_Y = -3.13  # elbow ball centre 109 px below the shoulder
ELBOW_R = 0.72  # elbow ball 50 px across = 1.43 studs

# forearm, ye = y relative to the elbow centre
CUFF_TOP, CUFF_BOT = -0.55, -2.00  # white cuff: 19 px .. 70 px below the elbow
CUFF_HW = 0.79  # 55 px = 1.58 studs wide
CUFF_HD = 0.78  # [A] square-ish cuff (side view 260 shows a deep forearm piece)
FORE_TOP, FORE_BOT = -2.00, -3.64  # grey forearm block: to 127 px below the elbow
FORE_HW0, FORE_HW1 = 0.65, 0.60  # 45 px = 1.29 studs at the top, slightly tapered
FORE_HD0, FORE_HD1 = 0.58, 0.52  # [A]
FORE_CX = 0.05  # centre 2-3 px outward
BAND_TOP, BAND_BOT = -3.64, -3.83  # dark wrist band 20 px tall
BAND_HW, BAND_HD, BAND_CX = 0.50, 0.45, 0.21  # 35 px wide, centred 7 px outward
WRIST = np.array([0.30, ELBOW_Y - 3.80, 0.0])  # wrist pivot: hand top centre (hand is 0.33 outward)

# hand (ye relative to the elbow; the hand is seen edge-on in the back view)
HAND_X0, HAND_X1 = 0.05, 0.62  # white hand 230..290 px (straightened png /3) -> 0.57 thick (X)
HAND_HZ = 0.62  # [A] 1.25 studs wide (Z) ~ 1.5 cells (owner's arm description: hand ~1.5 cells wide)
PALM_TOP, PALM_BOT = -3.83, -4.74  # palm from the wrist band to the knuckles (knuckle at 700 px)
KNUCKLE = np.array([0.36, ELBOW_Y + PALM_BOT, 0.0])
FINGER_Z = (-0.48, -0.16, 0.16, 0.48)  # [A] index (front) .. pinky (back)
FINGER_W, FINGER_H = 0.26, 0.30  # H: finger 25-30 px thick in the back view; W [A]
FINGER_L = (0.57, 0.52, 0.40)  # proximal 700->760 px, middle ->800 (diag), distal ->830 (diag)
FINGER_CURL = (  # joint angles toward the palm (deg); measured chain: 0 / 45 / 50 cumulative
	(4, 36, 12),
	(5, 37, 13),
	(6, 39, 14),
	(8, 41, 15),
)
THUMB_BASE = np.array([0.08, ELBOW_Y - 4.15, -0.46])  # grey knob 200..245 px at 605..670 px (inner side)
THUMB_DIR = (-0.40, -0.85, -0.30)  # tip at -0.45 out, 5.08 below the elbow (back view); fwd [A]
THUMB_L = (0.40, 0.34, 0.30)
THUMB_CURL = (6, 12, 14)
THUMB_W, THUMB_H = 0.28, 0.32

# forearm guard: a curved shell around an axis parallel to the forearm, outside it.
#   x = GX + r cos(th), z = GZ + r sin(th)   (th from +X toward +Z = back)
#   back view (261): outer edge 1.60 out (th = 0), lower inner edge 0.72 out, notch 0.24 out at ye -2.4,
#   tip 1.24 out at ye +0.13, bottom 4.40 (inner) / 4.03 (outer corner) below the elbow.
#   Arc radius / centre [A] chosen so the side view spans ~1.9 studs (owner's side crops: guard 1.4 cells
#   wide on a 4.5-cell length -> 0.31 x the 5.5-cell length measured here).
GX, GZ, GR, GT = 0.50, 0.20, 1.05, 0.20  # axis x, axis z, outer radius, thickness [GT A: chunky, not a sheet]
G_RIDGE, G_RIDGE_A = 0.07, 0.42  # [A] raised keel line on the outer face (fraction across front->back edge)
G_TIP = (0.25, 46.0)  # (ye, th deg)
G_BACK = [(-4.40, 78.0), (-3.00, 78.0), (-2.40, 104.0), G_TIP]  # inner edge in the back view, notch
G_FRONT = [(-3.65, -45.0), (-1.80, -50.0), (-0.45, -8.0), G_TIP]  # [A] hidden front edge
GOLD_YE = (-1.25, -3.26)  # gold inlay top / bottom (335 px / 545 px)
GOLD_TH = (28.0, 74.0)  # its centre angle at top / bottom (x 1.50 -> 0.85 in the back view)
GOLD_DTH = 30.0  # 0.5 cell wide = 0.41 studs of arc on r = 1.1


# ------------------------------------------------------------------ primitives

def rect_oct(x0, x1, z0, z1, ch):
	"""chamfered rectangle (x, z) loop, CCW seen from +Y"""
	ch = min(ch, (x1 - x0) * 0.45, (z1 - z0) * 0.45)
	return [(x1, z0 + ch), (x1, z1 - ch), (x1 - ch, z1), (x0 + ch, z1), (x0, z1 - ch), (x0, z0 + ch), (x0 + ch, z0),
		(x1 - ch, z0)]


def ybox(x0, x1, y0, y1, z0, z1, ch=0.08, sections=None):
	"""Chamfered box lofted along Y (bevelled top/bottom, chamfered vertical edges).
	sections: optional list of (y, x0, x1, z0, z1) replacing the straight sides (tapers)."""
	if sections is None:
		sections = [(y1, x0, x1, z0, z1), (y0, x0, x1, z0, z1)]
	sections = sorted(sections, key=lambda s: -s[0])
	rings = []
	top, bot = sections[0], sections[-1]

	def ring(y, a, b, c, d, inset=0.0):
		return [(x, y, z) for x, z in rect_oct(a + inset, b - inset, c + inset, d - inset, ch)]

	rings.append(ring(top[0], *top[1:], inset=ch))
	for k, s in enumerate(sections):
		y = s[0] - (ch if k == 0 else 0) + (ch if k == len(sections) - 1 else 0)
		rings.append(ring(y, *s[1:]))
	rings.append(ring(bot[0], *bot[1:], inset=ch))
	return loft(rings)


def frame_loft(origin, ax_l, ax_w, ax_h, sections, apex_end=None):
	"""sections: [(l, [(w, h) ...])] in a local frame (l along ax_l)."""
	o = np.asarray(origin, float)
	rings = [[tuple(o + l * ax_l + w * ax_w + h * ax_h) for w, h in pts] for l, pts in sections]
	return loft(rings, apex1=None if apex_end is None else tuple(o + apex_end[0] * ax_l + apex_end[1] * ax_w
		+ apex_end[2] * ax_h))


def cylinder(c0, c1, r, n=16, bevel=0.0):
	c0, c1 = np.asarray(c0, float), np.asarray(c1, float)
	ax = c1 - c0
	L = np.linalg.norm(ax)
	ax /= L
	u = np.cross(ax, [0, 1, 0] if abs(ax[1]) < 0.9 else [1, 0, 0])
	u /= np.linalg.norm(u)
	v = np.cross(ax, u)

	def ring(t, rr):
		return [tuple(c0 + ax * t + rr * (math.cos(2 * math.pi * i / n) * u + math.sin(2 * math.pi * i / n) * v))
			for i in range(n)]

	if bevel > 0:
		return loft([ring(0, r - bevel), ring(bevel, r), ring(L - bevel, r), ring(L, r - bevel)])
	return loft([ring(0, r), ring(L, r)])


def sphere(c, r, nu=24, nv=14):
	c = np.asarray(c, float)
	rings = []
	for j in range(1, nv):
		phi = -math.pi / 2 + math.pi * j / nv
		rings.append([tuple(c + r * np.array([math.cos(phi) * math.cos(2 * math.pi * i / nu), math.sin(phi),
			math.cos(phi) * math.sin(2 * math.pi * i / nu)])) for i in range(nu)])
	return loft(rings, apex0=tuple(c + [0, -r, 0]), apex1=tuple(c + [0, r, 0]))


def rot(axis, deg):
	a = np.asarray(axis, float)
	a = a / np.linalg.norm(a)
	t = math.radians(deg)
	K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
	return np.eye(3) + math.sin(t) * K + (1 - math.cos(t)) * K @ K


# ------------------------------------------------------------------ guard (curved shell)

def interp_edge(poly, b):
	"""poly: [(ye, th)] bottom -> tip; b in [0,1] runs along it by ye-arc (piecewise)"""
	pts = np.array(poly, float)
	seg = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 1]) / 40.0)  # 40 deg ~ 1 stud of arc
	cum = np.concatenate([[0], np.cumsum(seg)])
	s = b * cum[-1]
	k = min(int(np.searchsorted(cum, s, side="right")) - 1, len(seg) - 1)
	t = (s - cum[k]) / max(seg[k], 1e-9)
	return pts[k] + (pts[k + 1] - pts[k]) * t


def ridge(a):
	"""outer-face keel: tent profile peaking at G_RIDGE_A (a = 0 front edge .. 1 back edge)"""
	t = a / G_RIDGE_A if a <= G_RIDGE_A else (1 - a) / (1 - G_RIDGE_A)
	return G_RIDGE * max(0.0, min(1.0, t))


def gpoint(ye, th_deg, d):
	r = GR - d
	t = math.radians(th_deg)
	return (GX + r * math.cos(t), ELBOW_Y + ye, GZ + r * math.sin(t))


def guard_shell():
	NA = 12  # facets across the shell (angular, mech look)
	bev = 0.045
	rings = []
	bs = [0.0, 0.012] + list(np.linspace(0.03, 0.955, 26))
	for kb, b in enumerate(bs):
		L = interp_edge(G_FRONT, b)
		R = interp_edge(G_BACK, b)
		width = abs(R[1] - L[1]) / 180 * math.pi * GR + 1e-6
		ab = min(bev / width, 0.2)
		end = kb == 0  # bevelled bottom: thinner + inset ring
		d0, d1 = (0.035, GT - 0.035) if end else (0.0, GT)
		a0 = ab * (2.0 if end else 1.0)
		ring = []

		def P(a, d):
			ye = L[0] + (R[0] - L[0]) * a
			th = L[1] + (R[1] - L[1]) * a
			return gpoint(ye, th, d)

		ring.append(P(a0 * 0.5 if end else 0.0, GT / 2))
		for a in sorted(set(np.round(np.concatenate([np.linspace(a0, 1 - a0, NA), [G_RIDGE_A]]), 6))):
			ring.append(P(a, d0 - ridge(a) * (0.5 if end else 1.0)))
		ring.append(P(1 - (a0 * 0.5 if end else 0.0), GT / 2))
		for a in np.linspace(1 - a0, a0, NA + 1):
			ring.append(P(a, d1))
		rings.append(ring)
	tip = gpoint(G_TIP[0], G_TIP[1], GT / 2)
	return loft(rings, apex1=tip)


_AB = None


def patch_a(ye, th):
	"""patch coordinate a (front edge 0 .. back edge 1) of the guard point (ye, th): brute-force inverse"""
	global _AB
	if _AB is None:
		A, B = np.meshgrid(np.linspace(0, 1, 241), np.linspace(0, 1, 241))
		Ls = np.array([interp_edge(G_FRONT, b) for b in B[:, 0]])
		Rs = np.array([interp_edge(G_BACK, b) for b in B[:, 0]])
		YE = Ls[:, 0, None] + (Rs[:, 0, None] - Ls[:, 0, None]) * A
		TH = Ls[:, 1, None] + (Rs[:, 1, None] - Ls[:, 1, None]) * A
		_AB = (A, YE, TH)
	A, YE, TH = _AB
	k = np.argmin((YE - ye) ** 2 + ((TH - th) / 40.0) ** 2)
	return float(A.flat[k])


def guard_gold():
	rings = []
	shear = 0.0
	for ye in np.linspace(GOLD_YE[0], GOLD_YE[1], 14):
		f = (ye - GOLD_YE[0]) / (GOLD_YE[1] - GOLD_YE[0])
		thc = GOLD_TH[0] + (GOLD_TH[1] - GOLD_TH[0]) * f
		ring = []
		ths = np.linspace(thc - GOLD_DTH / 2, thc + GOLD_DTH / 2, 5)
		rd = [ridge(patch_a(ye, th)) for th in ths]  # follow the keel of the white face
		for th, h in zip(ths, rd):  # proud of the white by 0.035, sunk 0.03 into it
			ring.append(gpoint(ye + shear, th, -0.035 - h))
		for th, h in zip(ths[::-1], rd[::-1]):
			ring.append(gpoint(ye + shear, th, 0.03 - h))
		rings.append(ring)
	return loft(rings)


# ------------------------------------------------------------------ fingers

def phalanx(p0, d, bk, L, W, H, tip=False):
	"""white angular finger segment from joint p0 along d; back plate peaked toward bk."""
	s = np.cross(d, bk)
	s /= np.linalg.norm(s)

	def sec(scale, ridge=0.04):
		w, h = W / 2 * scale, H / 2 * scale
		return [(w, -h * 0.55), (w * 0.8, -h), (-w * 0.8, -h), (-w, -h * 0.55), (-w, h * 0.45), (-w * 0.45, h + ridge),
			(w * 0.45, h + ridge), (w, h * 0.45)]

	if tip:
		secs = [(-0.04, sec(0.72)), (0.05, sec(1.0)), (L * 0.55, sec(0.95)), (L * 0.85, sec(0.7, 0.02))]
		apex = (L, 0.0, -H * 0.25)  # claw tip, bent toward the palm
		return frame_loft(p0, d, s, bk, secs, apex_end=apex)
	secs = [(-0.04, sec(0.72)), (0.05, sec(1.0)), (L - 0.07, sec(0.96)), (L + 0.0, sec(0.7))]
	return frame_loft(p0, d, s, bk, secs)


def chain(base, d0, bk0, axis, lengths, curls, W, H, pin_len):
	"""-> list of segments: dict(pivot, axis, white, grey(pin at the next joint or None))"""
	segs = []
	p = np.asarray(base, float)
	d, bk = np.asarray(d0, float), np.asarray(bk0, float)
	acc = 0.0
	for k, (L, c) in enumerate(zip(lengths, curls)):
		acc += c
		R = rot(axis, acc)
		dk, bkk = R @ d, R @ bk
		last = k == len(lengths) - 1
		white = phalanx(p, dk, bkk, L, W, H, tip=last)
		q = p + dk * L
		grey = None
		if not last:
			ax = np.asarray(axis, float) / np.linalg.norm(axis)
			grey = cylinder(q - ax * pin_len / 2, q + ax * pin_len / 2, 0.085, n=10, bevel=0.02)
		segs.append(dict(pivot=p.copy(), axis=ax_list(axis), angle=c, white=white, grey=grey))
		p = q
	return segs


def ax_list(a):
	a = np.asarray(a, float)
	return [round(float(x), 5) for x in a / np.linalg.norm(a)]


# ------------------------------------------------------------------ build the right arm

def build_right():
	seg = {}
	# UPPER (shoulder -> elbow): pivot = shoulder ball centre
	up_grey = combine(
		sphere((0, 0, 0), SHOULDER_R, 24, 14),
		cylinder((0, -0.2, 0), (0, ELBOW_Y + 0.2, 0), CORE_R, n=12),
		sphere((0, ELBOW_Y, 0), ELBOW_R, 24, 14),
	)
	up_white = ybox(UB_CX - UB_HW, UB_CX + UB_HW, UB_BOT, UB_TOP, -UB_HD, UB_HD, ch=0.11, sections=[
		(UB_TOP, UB_CX - UB_HW, UB_CX + UB_HW, -UB_HD, UB_HD),
		(UB_TOP - 0.55, UB_CX - UB_HW - 0.02, UB_CX + UB_HW + 0.02, -UB_HD - 0.03, UB_HD + 0.03),  # slight belly
		(UB_BOT + 0.5, UB_CX - UB_HW - 0.02, UB_CX + UB_HW + 0.02, -UB_HD - 0.03, UB_HD + 0.03),
		(UB_BOT, UB_CX - UB_HW + 0.04, UB_CX + UB_HW - 0.04, -UB_HD + 0.04, UB_HD - 0.04),
	])
	seg["Upper"] = dict(parent=None, pivot=[0.0, 0.0, 0.0], joint="ball", meshes={"Grey": up_grey, "White": up_white})

	# LOWER (elbow -> wrist, incl. the guard): pivot = elbow ball centre
	E = ELBOW_Y
	cuff = ybox(-CUFF_HW, CUFF_HW, E + CUFF_BOT, E + CUFF_TOP, -CUFF_HD, CUFF_HD, ch=0.12, sections=[
		(E + CUFF_TOP, -CUFF_HW, CUFF_HW, -CUFF_HD, CUFF_HD),
		(E + CUFF_TOP - 0.45, -CUFF_HW - 0.03, CUFF_HW + 0.03, -CUFF_HD - 0.05, CUFF_HD + 0.03),
		(E + CUFF_BOT, -CUFF_HW + 0.06, CUFF_HW - 0.06, -CUFF_HD + 0.02, CUFF_HD - 0.04),
	])
	fore = ybox(0, 0, E + FORE_BOT, E + FORE_TOP + 0.1, 0, 0, ch=0.1, sections=[
		(E + FORE_TOP + 0.1, FORE_CX - FORE_HW0, FORE_CX + FORE_HW0, -FORE_HD0, FORE_HD0),
		(E + FORE_BOT, FORE_CX - FORE_HW1, FORE_CX + FORE_HW1, -FORE_HD1, FORE_HD1),
	])
	band = ybox(0, 0, E + BAND_BOT, E + BAND_TOP + 0.04, 0, 0, ch=0.07, sections=[
		(E + BAND_TOP + 0.04, BAND_CX - BAND_HW, BAND_CX + BAND_HW, -BAND_HD, BAND_HD),
		(E + BAND_BOT, BAND_CX - BAND_HW + 0.03, BAND_CX + BAND_HW - 0.03, -BAND_HD + 0.03, BAND_HD - 0.03),
	])
	# grey elbow socket ring (forearm side, sits in the ball) + guard brackets (forearm -> shell)
	socket = cylinder((0, E - 0.35, 0), (0, E - 0.62, 0), 0.58, n=16, bevel=0.04)
	brackets = []
	for ye in (-1.05, -3.25):
		thb = 8.0
		inner = np.array(gpoint(ye, thb, GT - 0.06))
		brackets.append(ybox(0.45, inner[0], E + ye - 0.16, E + ye + 0.16, inner[2] - 0.13, inner[2] + 0.13, ch=0.04))
	# gold panel on the front of the cuff (side view 260.png: gold panel on the white forearm piece) [A] size
	gp = []
	for y, hw in ((E - 0.80, 0.50), (E - 1.75, 0.36)):
		gp.append([(x, y, z) for x, z in ((hw, -CUFF_HD - 0.075), (-hw, -CUFF_HD - 0.075), (-hw + 0.03, -CUFF_HD + 0.02),
			(hw - 0.03, -CUFF_HD + 0.02))])
	cuff_gold = loft(gp)
	seg["Lower"] = dict(parent="Upper", pivot=[0.0, ELBOW_Y, 0.0], joint="ball (elbow; hinge axis +X = flex forward)",
		meshes={"White": combine(cuff, guard_shell()), "Gold": combine(guard_gold(), cuff_gold),
			"Grey": combine(fore, socket, *brackets), "DarkGrey": band})

	# HAND (wrist -> knuckles): pivot = wrist
	hx0, hx1 = HAND_X0, HAND_X1
	PT, PB = E + PALM_TOP, E + PALM_BOT
	palm = ybox(0, 0, PB, PT - 0.02, 0, 0, ch=0.09, sections=[
		(PT - 0.02, hx0 + 0.04, hx1 - 0.05, -HAND_HZ + 0.12, HAND_HZ - 0.12),
		(PT - 0.25, hx0, hx1, -HAND_HZ, HAND_HZ),
		(PB + 0.12, hx0 - 0.02, hx1 + 0.02, -HAND_HZ - 0.02, HAND_HZ + 0.02),
		(PB, hx0 + 0.03, hx1 - 0.03, -HAND_HZ + 0.03, HAND_HZ - 0.03),
	])
	# peaked back-of-hand armour plate (outer face, +X) for depth
	plate_secs = []
	for y, s in ((PT - 0.12, 0.85), (PT - 0.25, 1.0), (PB + 0.18, 1.0), (PB + 0.08, 0.85)):
		hz = (HAND_HZ - 0.06) * s
		plate_secs.append([(hx1 - 0.06, y, -hz), (hx1 + 0.08, y, -hz * 0.85), (hx1 + 0.14, y, -hz * 0.3),
			(hx1 + 0.14, y, hz * 0.3), (hx1 + 0.08, y, hz * 0.85), (hx1 - 0.06, y, hz)])
	plate = loft(plate_secs)
	pad = ybox(0, 0, PB + 0.12, PT - 0.2, 0, 0, ch=0.05, sections=[
		(PT - 0.2, hx0 - 0.06, hx0 + 0.1, -HAND_HZ + 0.15, HAND_HZ - 0.15),
		(PB + 0.12, hx0 - 0.06, hx0 + 0.1, -HAND_HZ + 0.12, HAND_HZ - 0.12),
	])
	neck = cylinder((WRIST[0], E - 3.70, 0), (WRIST[0], PT - 0.15, 0), 0.30, n=14, bevel=0.03)
	knuck_pin = cylinder(KNUCKLE + [0, 0, -HAND_HZ - 0.02], KNUCKLE + [0, 0, HAND_HZ + 0.02], 0.095, n=12, bevel=0.02)
	thumb_knob = sphere(THUMB_BASE, 0.2, 14, 8)
	hand_white = combine(palm, plate)
	hand_grey = combine(neck, knuck_pin, thumb_knob)
	seg["Hand"] = dict(parent="Lower", pivot=[float(v) for v in WRIST], joint="ball (wrist)",
		meshes={"White": hand_white, "Grey": hand_grey, "DarkGrey": pad})

	# FINGERS: curl axis -Z (rotating "down" toward -X = the palm), back of finger = +X
	names = ["Index", "Middle", "Ring", "Pinky"]
	for fi, z in enumerate(FINGER_Z):
		base = KNUCKLE + [0, 0, z]
		segs = chain(base, (0, -1, 0), (1, 0, 0), (0, 0, -1), FINGER_L, FINGER_CURL[fi], FINGER_W, FINGER_H,
			FINGER_W + 0.04)
		parent = "Hand"
		for k, s in enumerate(segs):
			nm = "%s%d" % (names[fi], k + 1)
			meshes = {"White": s["white"]}
			if s["grey"] is not None:
				meshes["Grey"] = s["grey"]
			seg[nm] = dict(parent=parent, pivot=[float(v) for v in s["pivot"]], joint="hinge", axis=s["axis"],
				rest_curl_deg=s["angle"], meshes=meshes)
			parent = nm
	# THUMB: from the inner-front corner of the palm, curls toward the fingers (+Z) under the palm
	d0 = np.array(THUMB_DIR, float)
	d0 /= np.linalg.norm(d0)
	axis = np.cross(d0, [0, 0, 1.0])
	axis /= np.linalg.norm(axis)
	bk0 = np.array([0.3, 0.0, -1.0])
	bk0 -= d0 * np.dot(bk0, d0)
	bk0 /= np.linalg.norm(bk0)
	segs = chain(THUMB_BASE, d0, bk0, axis, THUMB_L, THUMB_CURL, THUMB_W, THUMB_H, THUMB_W + 0.04)
	parent = "Hand"
	for k, s in enumerate(segs):
		nm = "Thumb%d" % (k + 1)
		meshes = {"White": s["white"]}
		if s["grey"] is not None:
			meshes["Grey"] = s["grey"]
		seg[nm] = dict(parent=parent, pivot=[float(v) for v in s["pivot"]], joint="hinge", axis=s["axis"],
			rest_curl_deg=s["angle"], meshes=meshes)
		parent = nm
	return seg


def mirror_seg(seg):
	out = {}
	for nm, s in seg.items():
		t = dict(s)
		t["pivot"] = [-s["pivot"][0], s["pivot"][1], s["pivot"][2]]
		if "axis" in s:  # rotation axis is a pseudovector: mirror x then negate
			a = s["axis"]
			t["axis"] = [round(a[0], 5), round(-a[1], 5), round(-a[2], 5)]
		t["meshes"] = {c: m.mirrored_x() for c, m in s["meshes"].items()}
		out[nm] = t
	return out


def main():
	right = build_right()
	arms = {"R": right, "L": mirror_seg(right)}
	meta = {
		"name": "mech2_arms",
		"units": "studs",
		"cell_studs": CELL,
		"frame": "per arm: origin = shoulder ball centre, +Y up, -Z forward, R arm outward = +X, L arm outward = -X",
		"rest_pose": "arm hanging straight down; reference A-pose (261.png back view): shoulder roll ~19-22 deg outward, elbow ~-3..-6 deg (renders/iou.json); the arm silhouette puts the R shoulder ball centre ~(3.5, 9.2, -) studs from the hip-line centre",
		"uv": "planar per facet group, 1 repeat = 4 studs, Roblox box-mapping orientation (meshlib.py)",
		"colours": {k: {"rgb": list(v), "hex": "#%02X%02X%02X" % v} for k, v in COLOURS.items()},
		"arms": {},
	}
	total = 0
	for side, seg in arms.items():
		d = os.path.join(OUT, side)
		os.makedirs(d, exist_ok=True)
		for f in os.listdir(d):
			if f.endswith(".obj"):
				os.remove(os.path.join(d, f))
		sm = {}
		merged = {}
		for nm, s in seg.items():
			files = []
			for col, m in s["meshes"].items():
				fn = "Mech2Arm_%s_%s_%s.obj" % (side, nm, col)
				V, _ = m.arrays()
				lo, hi = V.min(0), V.max(0)
				hdr = ("mech2 arm %s, segment %s, colour %s %s\n" % (side, nm, col, "#%02X%02X%02X" % COLOURS[col])
					+ "arm space (origin = shoulder centre, studs); segment pivot %s\n" % s["pivot"]
					+ "bbox centre %s (Roblox recentres on import: place at armCF * CFrame.new(centre))" % (
						[round(float(v), 4) for v in (lo + hi) / 2]))
				ntri, stretch, isl = write_obj(os.path.join(d, fn), m, hdr)
				oe = open_edges(m)
				total += ntri
				files.append(dict(file="%s/%s" % (side, fn), colour=col, tris=ntri, open_edges=oe,
					uv_max_stretch=round(stretch, 3), uv_islands=isl,
					bbox_min=[round(float(v), 4) for v in lo], bbox_max=[round(float(v), 4) for v in hi],
					bbox_centre=[round(float(v), 4) for v in (lo + hi) / 2],
					size=[round(float(v), 4) for v in hi - lo]))
				if nm == "Hand" or nm[:-1] in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
					merged.setdefault(col, []).append(m)
			e = {k: v for k, v in s.items() if k != "meshes"}
			e["files"] = files
			sm[nm] = e
		# convenience: whole hand (fingers in the rest curl) as one mesh per colour
		mf = []
		for col, ms in merged.items():
			m = combine(*ms)
			fn = "Mech2Arm_%s_HandMerged_%s.obj" % (side, col)
			V, _ = m.arrays()
			lo, hi = V.min(0), V.max(0)
			ntri, stretch, isl = write_obj(os.path.join(d, fn), m, "mech2 arm %s: whole hand incl. fingers (rest curl), "
				"colour %s; parent = Hand segment (pivot wrist)" % (side, col))
			mf.append(dict(file="%s/%s" % (side, fn), colour=col, tris=ntri, open_edges=open_edges(m),
				uv_max_stretch=round(stretch, 3), bbox_centre=[round(float(v), 4) for v in (lo + hi) / 2],
				size=[round(float(v), 4) for v in hi - lo]))
		meta["arms"][side] = {"segments": sm, "hand_merged_alternative": mf}
	meta["total_tris_segment_files"] = total
	with open(os.path.join(OUT, "meta.json"), "w", newline="\n") as fh:
		json.dump(meta, fh, indent=1)
	# summary
	for side in arms:
		for nm, e in meta["arms"][side]["segments"].items():
			for f in e["files"]:
				print("%-34s %5d tris  open=%d  stretch=%.3f size=%s" % (f["file"], f["tris"], f["open_edges"],
					f["uv_max_stretch"], f["size"]))
		break
	print("total tris (segment files, both arms):", total)


if __name__ == "__main__":
	main()
