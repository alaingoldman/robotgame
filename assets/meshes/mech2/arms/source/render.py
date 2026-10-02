"""Verification renders for the mech2 arms (numpy + Pillow, flat-shaded orthographic, painter's algorithm
with back-face culling) + silhouette IoU against the back-view reference refs/261.png.

  python render.py            -> ../renders/*.png and ../renders/iou.json
"""
import json
import math
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RND = os.path.join(ROOT, "renders")
META = json.load(open(os.path.join(ROOT, "meta.json")))
COL = {k: np.array(v["rgb"], float) for k, v in META["colours"].items()}


def load_obj(path):
	V, F = [], []
	for ln in open(path):
		if ln.startswith("v "):
			V.append([float(t) for t in ln.split()[1:4]])
		elif ln.startswith("f "):
			F.append([int(t.split("/")[0]) - 1 for t in ln.split()[1:4]])
	return np.array(V), np.array(F)


def rot(axis, deg):
	a = np.asarray(axis, float)
	a = a / np.linalg.norm(a)
	t = math.radians(deg)
	K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
	return np.eye(3) + math.sin(t) * K + (1 - math.cos(t)) * K @ K


def posed_arm(side, pose=None, origin=(0, 0, 0)):
	"""pose: {segment: (axis, deg)} rotations about the segment pivot, applied down the hierarchy.
	-> list of (V, F, colour rgb)"""
	pose = pose or {}
	segs = META["arms"][side]["segments"]
	xf = {}

	def world(nm):
		if nm in xf:
			return xf[nm]
		s = segs[nm]
		R0, t0 = (np.eye(3), np.zeros(3)) if s["parent"] is None else world(s["parent"])
		p = np.array(s["pivot"])
		Rl = rot(*pose[nm]) if nm in pose else np.eye(3)
		# local: x -> p + Rl (x - p); then parent
		R = R0 @ Rl
		t = R0 @ (p - Rl @ p) + t0
		xf[nm] = (R, t)
		return xf[nm]

	out = []
	for nm, s in segs.items():
		R, t = world(nm)
		for f in s["files"]:
			V, F = load_obj(os.path.join(ROOT, f["file"]))
			out.append(((V @ R.T) + t + np.asarray(origin, float), F, COL[f["colour"]]))
	return out


def view_basis(f, up=(0, 1, 0)):
	f = np.asarray(f, float)
	f /= np.linalg.norm(f)
	u = np.asarray(up, float)
	u = u - f * np.dot(u, f)
	u /= np.linalg.norm(u)
	r = np.cross(f, u)
	return f, u, r


def render(parts, f, up=(0, 1, 0), size=(600, 900), scale=None, centre=None, ss=2, bg=(236, 236, 236),
		silhouette=False):
	f, u, r = view_basis(f, up)
	allV = np.concatenate([p[0] for p in parts])
	sx, sy = allV @ r, allV @ u
	if centre is None:
		centre = ((sx.min() + sx.max()) / 2, (sy.min() + sy.max()) / 2)
	if scale is None:
		scale = 0.9 * min(size[0] / (sx.max() - sx.min()), size[1] / (sy.max() - sy.min()))
	W, H = size[0] * ss, size[1] * ss
	L = -f * 0.75 + u * 0.55 - r * 0.45
	L /= np.linalg.norm(L)
	if silhouette:  # fast path: union of all projected triangles
		img = Image.new("L", (W, H), 255)
		dr = ImageDraw.Draw(img)
		for V, F, c in parts:
			P = V[F]
			X = (P @ r - centre[0]) * scale * ss + W / 2
			Y = H / 2 - (P @ u - centre[1]) * scale * ss
			for i in range(len(F)):
				dr.polygon(list(zip(X[i], Y[i])), fill=0)
		return img.convert("RGB").resize(size, Image.LANCZOS), scale, centre
	# z-buffer rasterizer (per-triangle bounding box, vectorised barycentrics)
	zbuf = np.full((H, W), np.inf)
	cbuf = np.zeros((H, W, 3))
	cbuf[:] = bg
	for V, F, c in parts:
		P = V[F]
		n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
		n /= np.linalg.norm(n, axis=1)[:, None] + 1e-12
		vis = n @ f < 0
		shade = 0.30 + 0.70 * np.clip(n @ L, 0, 1)
		X = (P @ r - centre[0]) * scale * ss + W / 2
		Y = H / 2 - (P @ u - centre[1]) * scale * ss
		Z = P @ f
		for i in np.nonzero(vis)[0]:
			xs, ys, zs = X[i], Y[i], Z[i]
			x0, x1 = max(int(math.floor(xs.min())), 0), min(int(math.ceil(xs.max())), W - 1)
			y0, y1 = max(int(math.floor(ys.min())), 0), min(int(math.ceil(ys.max())), H - 1)
			if x1 < x0 or y1 < y0:
				continue
			gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
			d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
			if abs(d) < 1e-12:
				continue
			l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
			l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
			l2 = 1 - l0 - l1
			ins = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
			if not ins.any():
				continue
			z = l0 * zs[0] + l1 * zs[1] + l2 * zs[2]
			zb = zbuf[y0:y1 + 1, x0:x1 + 1]
			upd = ins & (z < zb)
			zb[upd] = z[upd]
			cb = cbuf[y0:y1 + 1, x0:x1 + 1]
			cb[upd] = (0, 0, 0) if silhouette else np.minimum(c * shade[i], 255)
	# dark outline where depth jumps (silhouettes / overlaps), like the line-art reference
	if not silhouette:
		zz = np.where(np.isinf(zbuf), 1e6, zbuf)
		edge = np.zeros((H, W), bool)
		thr = 0.08
		edge[:, 1:] |= np.abs(zz[:, 1:] - zz[:, :-1]) > thr
		edge[1:, :] |= np.abs(zz[1:, :] - zz[:-1, :]) > thr
		cbuf[edge] = cbuf[edge] * 0.25
	img = Image.fromarray(cbuf.astype(np.uint8))
	return img.resize(size, Image.LANCZOS), scale, centre


def label(img, text):
	d = ImageDraw.Draw(img)
	try:
		fnt = ImageFont.truetype("arial.ttf", 18)
	except OSError:
		fnt = ImageFont.load_default()
	d.text((8, 6), text, fill=(20, 20, 20), font=fnt)
	return img


def grid(imgs, cols):
	w, h = imgs[0].size
	rows = (len(imgs) + cols - 1) // cols
	out = Image.new("RGB", (w * cols, h * rows), (255, 255, 255))
	for i, im in enumerate(imgs):
		out.paste(im, ((i % cols) * w, (i // cols) * h))
	return out


# ------------------------------------------------------------------ reference silhouette (261.png back view)
REF = os.path.join(HERE, "refs", "261.png")
SQ = 28.45 / 28.8  # rows -> square pixels (grid 28.45 px wide, 28.8 px tall)
PX = 28.45 / 0.816  # px per stud
Y_CUT = 232  # (square px) everything above is hidden by the pauldron -> excluded from IoU


def ref_masks():
	a = np.asarray(Image.open(REF).convert("RGB").resize((574, int(round(891 * SQ))), Image.LANCZOS)).astype(int)
	H, W, _ = a.shape
	g = a.mean(2)
	neutral = np.abs(a[..., 0] - a[..., 2]) < 10
	cand = neutral & (g > 150) & (g <= 232)  # background (227) + grid lines
	bg = np.zeros((H, W), bool)
	q = deque()
	for x in range(W):
		for y in (0, H - 1):
			if cand[y, x]:
				bg[y, x] = True
				q.append((y, x))
	while q:
		y, x = q.popleft()
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			yy, xx = y + dy, x + dx
			if 0 <= yy < H and 0 <= xx < W and not bg[yy, xx] and cand[yy, xx]:
				bg[yy, xx] = True
				q.append((yy, xx))
	fg = ~bg
	fg[:Y_CUT] = False
	lab = -np.ones((H, W), int)
	comps = []
	for y0 in range(H):
		for x0 in range(W):
			if fg[y0, x0] and lab[y0, x0] < 0:
				k = len(comps)
				lab[y0, x0] = k
				q = deque([(y0, x0)])
				pts = []
				while q:
					y, x = q.popleft()
					pts.append((y, x))
					for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
						yy, xx = y + dy, x + dx
						if 0 <= yy < H and 0 <= xx < W and fg[yy, xx] and lab[yy, xx] < 0:
							lab[yy, xx] = k
							q.append((yy, xx))
				comps.append(np.array(pts))
	masks = {}
	for side, test in (("R", lambda cx: cx > 425), ("L", lambda cx: cx < 574 - 425)):
		m = np.zeros((H, W), bool)
		for pts in comps:
			cy, cx = pts.mean(0)
			if len(pts) > 25 and np.ptp(pts[:, 1]) > 6 and test(cx) and cy < 530 and pts[:, 1].min() > (380 if side == "R" else 0) \
					and pts[:, 1].max() < (574 if side == "R" else 194):
				m[pts[:, 0], pts[:, 1]] = True
		masks[side] = m
	return masks, a


def model_mask(side, pose, shoulder_px, shape):
	parts = posed_arm(side, pose)
	img, _, _ = render(parts, (0, 0, -1), size=(shape[1], shape[0]), scale=PX, ss=1,
		centre=(-shoulder_px[0] / PX + shape[1] / 2 / PX, shoulder_px[1] / PX - shape[0] / 2 / PX), silhouette=True,
		bg=(255, 255, 255))
	m = np.asarray(img.convert("L")) < 128
	# no dilation: the reference fg (flood-filled background removed) already matches the model area to <1%
	# when aligned, i.e. the outline stroke sits on the true edge
	m[:Y_CUT] = False
	return m


def iou(a, b):
	return float((a & b).sum()) / max(float((a | b).sum()), 1.0)


def ref_pose(side, sh, el, wr):
	s = 1 if side == "R" else -1
	return {"Upper": ((0, 0, 1), s * sh), "Lower": ((0, 0, 1), s * el), "Hand": ((0, 0, 1), s * wr)}


def fit(side, ref, start):
	"""coordinate descent over shoulder pixel position + shoulder roll / elbow / wrist angles (z axis)"""
	p = dict(start)
	steps = {"x": 4.0, "y": 4.0, "sh": 3.0, "el": 3.0, "wr": 4.0}

	def score(pp):
		return iou(model_mask(side, ref_pose(side, pp["sh"], pp["el"], pp["wr"]), (pp["x"], pp["y"]), ref.shape), ref)

	best = score(p)
	for _ in range(5):
		improved = False
		for k in ("x", "y", "sh", "el", "wr"):
			for sgn in (1, -1):
				q = dict(p)
				q[k] += sgn * steps[k]
				s = score(q)
				if s > best + 1e-4:
					best, p, improved = s, q, True
		if not improved:
			for k in steps:
				steps[k] /= 2
	return p, best


def main():
	os.makedirs(RND, exist_ok=True)
	# ---------------- IoU vs the back view
	masks, refimg = ref_masks()
	res = {}
	overlay = Image.fromarray(refimg.astype(np.uint8)).convert("RGB")
	ov = np.asarray(overlay).astype(float)
	for side, start in (("R", dict(x=408.0, y=200.0, sh=25.6, el=-9.0, wr=-6.0)),
			("L", dict(x=166.0, y=200.0, sh=25.6, el=-9.0, wr=-6.0))):
		p, best = None, -1
		for dsh, dx in ((0, 0), (-4, 6), (-7, 10), (3, -4)):  # multi-start: shoulder position / roll trade off
			st = dict(start)
			st["sh"] += dsh
			st["x"] += dx if side == "R" else -dx
			pp, bb = fit(side, masks[side], st)
			if bb > best:
				p, best = pp, bb
		mm = model_mask(side, ref_pose(side, p["sh"], p["el"], p["wr"]), (p["x"], p["y"]), masks[side].shape)
		res[side] = dict(iou=round(best, 4), shoulder_px=[p["x"], p["y"]], shoulder_roll_deg=p["sh"],
			elbow_deg=p["el"], wrist_deg=p["wr"])
		ref = masks[side]
		ov[ref & ~mm] = ov[ref & ~mm] * 0.3 + np.array([255, 0, 0]) * 0.7  # ref only: red
		ov[mm & ~ref] = ov[mm & ~ref] * 0.3 + np.array([0, 90, 255]) * 0.7  # model only: blue
		ov[mm & ref] = ov[mm & ref] * 0.6 + np.array([0, 200, 0]) * 0.4  # both: green
	cmp_img = Image.fromarray(ov.astype(np.uint8)).crop((20, 150, 574 - 0, 560))
	cmp_img = cmp_img.resize((cmp_img.width * 2, cmp_img.height * 2), Image.LANCZOS)
	label(cmp_img, "IoU vs 261.png back view (below pauldron): R %.3f  L %.3f   green=both red=ref only blue=model only"
		% (res["R"]["iou"], res["L"]["iou"]))
	cmp_img.save(os.path.join(RND, "iou_back_overlay.png"))
	json.dump(res, open(os.path.join(RND, "iou.json"), "w"), indent=1)
	print(json.dumps(res, indent=1))

	# side-by-side: reference vs model in the fitted pose (flat shaded), same canvas / scale as the reference
	H0, W0 = refimg.shape[:2]
	parts = []
	for side in ("L", "R"):
		p = res[side]
		# arm space -> reference canvas space (studs): put this shoulder at its fitted pixel position
		off = ((p["shoulder_px"][0] - W0 / 2) / PX, (H0 / 2 - p["shoulder_px"][1]) / PX, 0)
		parts += posed_arm(side, ref_pose(side, p["shoulder_roll_deg"], p["elbow_deg"], p["wrist_deg"]), origin=off)
	mimg, _, _ = render(parts, (0, 0, -1), size=(W0, H0), scale=PX, centre=(0, 0), ss=3, bg=(227, 227, 227))
	box = (20, 170, 574, 540)
	r1 = Image.fromarray(refimg.astype(np.uint8)).crop(box)
	m1 = mimg.crop(box)
	r1 = r1.resize((r1.width * 2, r1.height * 2), Image.LANCZOS)
	m1 = m1.resize((m1.width * 2, m1.height * 2), Image.LANCZOS)
	grid([label(r1, "reference 261.png (back view)"), label(m1, "model, back view, fitted pose")], 2).save(
		os.path.join(RND, "compare_back.png"))

	# ---------------- ortho views, rest pose (right arm) + both arms
	R = posed_arm("R")
	views = [("back (+Z cam)", (0, 0, -1)), ("front (-Z cam)", (0, 0, 1)), ("side outer (+X cam)", (-1, 0, 0)),
		("side inner (-X cam)", (1, 0, 0))]
	allV = np.concatenate([p[0] for p in R])
	sc = 0.9 * 900 / (allV[:, 1].max() - allV[:, 1].min())
	imgs = []
	for nm, f in views:
		img, _, _ = render(R, f, size=(420, 900), scale=sc,
			centre=(0, (allV[:, 1].max() + allV[:, 1].min()) / 2) if True else None)
		imgs.append(label(img, "R arm " + nm))
	grid(imgs, 4).save(os.path.join(RND, "ortho_R_rest.png"))
	# pose with reference A-pose for both arms, back + front
	both = posed_arm("R", ref_pose("R", 25, -9, -6), origin=(2.6, 0, 0)) + posed_arm("L", ref_pose("L", 25, -9, -6),
		origin=(-2.6, 0, 0))
	a, _, _ = render(both, (0, 0, -1), size=(800, 760))
	b, _, _ = render(both, (0, 0, 1), size=(800, 760))
	grid([label(a, "both arms, back view, ref A-pose (shoulders 5.2 apart, placeholder)"),
		label(b, "front view")], 2).save(os.path.join(RND, "ortho_both_apose.png"))

	# ---------------- depth check
	dv = [("3/4 front-left (cam front, outer side of L)", (0.65, -0.35, 0.75)),
		("3/4 front-right (cam front, outer side of R)", (-0.65, -0.35, 0.75)),
		("3/4 back-right", (-0.7, -0.3, -0.7)), ("top (front = up)", (0, -1, 0.0001))]
	imgs = []
	for nm, f in dv:
		up = (0, 0, -1) if nm.startswith("top") else (0, 1, 0)
		img, _, _ = render(R, f, up=up, size=(500, 760) if not nm.startswith("top") else (500, 760))
		imgs.append(label(img, "R arm " + nm))
	grid(imgs, 4).save(os.path.join(RND, "depth_check.png"))
	# hand close-ups (fingers depth)
	H = [p for p in posed_arm("R")]
	hv = [("hand 3/4 front-in", (0.6, -0.2, 0.8)), ("hand 3/4 back-out", (-0.7, -0.1, -0.7)),
		("hand from below", (0.0001, 1, 0))]
	hand = []
	ymax = META["arms"]["R"]["segments"]["Hand"]["pivot"][1] + 0.2
	sel = [(V, F, c) for V, F, c in H if V[:, 1].max() <= ymax]
	for nm, f in hv:
		up = (0, 0, -1) if "below" in nm else (0, 1, 0)
		img, _, _ = render(sel, f, up=up, size=(420, 420))
		hand.append(label(img, nm))
	grid(hand, 3).save(os.path.join(RND, "hand_closeup.png"))


if __name__ == "__main__":
	main()
