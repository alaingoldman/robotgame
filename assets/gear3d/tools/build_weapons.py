"""Build assets/gear3d/Weapons.glb from the 20 Tripo image-to-3D weapon GLBs (made from the SIDE view crop).

Each node has its GRIP at the origin:
  melee  W_M01..W_M10 : blade/head along +Y, the heavier side of the head (edge/blade) towards -Z, flat side along X
  ranged W_R01..W_R10 : barrel along -Z (forward), up = +Y, grip below the barrel
Grip detection: melee = PCA long axis in the image plane; the thinner end is the handle, grip 14% of the length in
from that end (pommel side). Ranged = the handle is the part hanging below the barrel; grip = top of the handle.
Writes Weapons.glb, work/meta_weapons.json, renders/Weapons_lineup.png"""
import os, sys, json
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from gio import read_glb, write_glb
from dec import decimate

ROOT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d'
RAW = ROOT + r'\work\raw'
JOBS = json.load(open(r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear_concepts\jobs.json'))['jobs']
MELEE_LEN = 5.0
RANGED_LEN = {'pistol': 3.0, 'blunderbuss': 3.8, 'crossbow': 3.8, 'harpoon': 4.6, 'mortar': 3.6, 'gatling': 4.2,
              'flamethrower': 4.4, 'tesla': 4.6, 'aether': 3.6, 'railgun': 5.0}


def image_plane(p):
    """returns (h, d): unit vectors of the image-horizontal axis and the thin depth axis (both horizontal)."""
    ex, ez = np.ptp(p[:, 0]), np.ptp(p[:, 2])
    if ex >= ez:
        return np.array([1., 0, 0]), np.array([0, 0, 1.])
    return np.array([0, 0, 1.]), np.array([1., 0, 0])


def frame_rot(a, b, c):
    """rotation matrix taking world vectors a->X, b->Y, c->Z (rows)."""
    return np.vstack([a, b, c])


FLIP = {'1007_melee'}   # sabre: the narrow blade tip fooled the 'thinner end = handle' rule


def melee(p, flip=False):
    h, d = image_plane(p)
    q = np.column_stack([p @ h, p[:, 1]])           # 2D image coords (horizontal, up)
    c = q.mean(0)
    u, s, vt = np.linalg.svd(q - c, full_matrices=False)
    ax = vt[0]
    t = (q - c) @ ax
    perp = (q - c) @ np.array([-ax[1], ax[0]])
    lo, hi = t.min(), t.max(); L = hi - lo

    def width(a, b):
        m = (t >= a) & (t <= b)
        return np.ptp(perp[m]) if m.sum() > 10 else 1e9
    w_lo = width(lo, lo + 0.25 * L); w_hi = width(hi - 0.25 * L, hi)
    if (w_hi < w_lo) != flip:                         # handle at the high end -> flip axis
        ax = -ax; t = -t; perp = -perp; lo, hi = -hi, -lo
    grip_t = lo + 0.14 * L
    m = (t > grip_t - 0.05 * L) & (t < grip_t + 0.05 * L)
    grip_perp = np.median(perp[m]) if m.any() else 0.0
    side = np.array([-ax[1], ax[0]])
    grip2 = c + ax * grip_t + side * grip_perp
    # 3D axes: length dir, perpendicular in image plane, depth
    L3 = ax[0] * h + ax[1] * np.array([0, 1., 0])
    P3 = side[0] * h + side[1] * np.array([0, 1., 0])
    gp = grip2[0] * h + np.array([0, grip2[1], 0]) + d * np.median(p @ d)
    # heavier side of the head (top 35% of the length) goes to -Z
    head = t > lo + 0.65 * L
    sgn = 1.0 if np.mean(perp[head] - grip_perp) > 0 else -1.0
    R = frame_rot(np.cross(L3, -sgn * P3), L3, -sgn * P3)       # X = cross, Y = length, Z = -heavy side
    if np.linalg.det(R) < 0:
        R[0] = -R[0]
    out = (p - gp) @ R.T
    return out, R, MELEE_LEN / L


def ranged(p, length):
    h, d = image_plane(p)
    x = p @ h; y = p[:, 1]
    H = np.ptp(y); y0 = y.min()
    low = y < y0 + 0.3 * H                           # handle / grip hanging down
    xg = np.median(x[low]) if low.sum() > 20 else x.mean()
    # muzzle = the end farther from the handle
    muzzle_dir = 1.0 if (x.max() - xg) > (xg - x.min()) else -1.0
    band = (np.abs(x - xg) < 0.08 * np.ptp(x))
    yg = np.percentile(y[band], 60) if band.sum() > 20 else y0 + 0.45 * H
    gp = xg * h + np.array([0, yg, 0]) + d * np.median(p @ d)
    fwd = muzzle_dir * h
    R = frame_rot(np.cross(np.array([0, 1., 0]), -fwd), np.array([0, 1., 0]), -fwd)
    if np.linalg.det(R) < 0:
        R[0] = -R[0]
    out = (p - gp) @ R.T
    return out, R, length / np.ptp(x)


def build():
    nodes, mats, meta = [], [], {}
    keys = [k for k in JOBS if JOBS[k]['slot'] == 'melee'] + [k for k in JOBS if JOBS[k]['slot'] == 'ranged']
    for k in keys:
        j = JOBS[k]
        i = int(k[:4]) % 1000
        nm = ('W_M%02d' if j['slot'] == 'melee' else 'W_R%02d') % i
        fn = os.path.join(RAW, k + '.glb')
        if not os.path.exists(fn):
            print('missing', k); continue
        p, n, t, ix, tx = read_glb(fn)
        if j['slot'] == 'melee':
            q, R, s = melee(p, k in FLIP)
        else:
            key = next((w for w in RANGED_LEN if w in j['file']), None)
            q, R, s = ranged(p, RANGED_LEN.get(key, 4.0))
        q = q * s
        nn = n @ R.T
        q, nn, t, ix = decimate(q, nn, t, ix, 16000)
        mats.append({'name': nm + '_Mat', 'base': tx['base'], 'mr': tx['mr'], 'normal': tx['normal'], 'factors': tx['factors']})
        nodes.append((nm, q, nn, t, ix, len(mats) - 1))
        length = float(q[:, 1].max()) if j['slot'] == 'melee' else float(-q[:, 2].min())
        meta[nm] = {'source': j['file'], 'type': j['slot'], 'bbox_min': [round(float(v), 4) for v in q.min(0)],
                    'bbox_max': [round(float(v), 4) for v in q.max(0)], 'grip': [0.0, 0.0, 0.0],
                    'length': round(float(np.ptp(q[:, 1]) if j['slot'] == 'melee' else np.ptp(q[:, 2])), 3),
                    'reach_from_grip': round(length, 3), 'tris': int(len(ix))}
        print(nm, k, meta[nm]['length'], len(ix), flush=True)
    write_glb(os.path.join(ROOT, 'Weapons.glb'), nodes, mats, size=1024, sub_size=512, gen='gear3d build_weapons.py')
    json.dump(meta, open(os.path.join(ROOT, 'work', 'meta_weapons.json'), 'w'), indent=1)
    print('Weapons.glb', os.path.getsize(os.path.join(ROOT, 'Weapons.glb')) // 1024, 'KB')
    render(nodes, mats)


def render(nodes, mats):
    from rend import render as R_, strip
    from PIL import ImageDraw
    ims = []
    for nm, q, n, t, ix, mi in nodes:
        pp, nn, tt, ff = decimate(q, n, t, ix, 4000)
        tex = np.asarray(mats[mi]['base'].convert('RGB').resize((512, 512)))
        import trimesh
        bx = trimesh.creation.box(extents=(0.3, 0.3, 0.3))
        part = [(pp, ff, tt, tex), (np.asarray(bx.vertices), np.asarray(bx.faces), None, (255, 0, 0))]   # red = grip
        a = R_(part, 'side', 260, title=nm + ' side')
        b = R_(part, 'threeq', 260, title='3/4')
        # grip marker: draw small cross at origin in side view
        ims.append(strip([a, b]))
    cols = 5
    W = ims[0].width; H = ims[0].height
    sheet = Image.new('RGB', (W * cols, H * ((len(ims) + cols - 1) // cols)), 'white')
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % cols) * W, (i // cols) * H))
    sheet.save(os.path.join(ROOT, 'renders', 'Weapons_lineup.png'))


if __name__ == '__main__':
    build()
