"""Build assets/gear3d/Gear_T##.glb from the three Tripo GLBs of a tier (arm, leg, chest+head).

Model space: studs, Y up, front = -Z, +X = character's right. Feet at y = 0.
  leg   : sole y=0 .. hip y=3.0, centred at x=+/-max(0.5, 0.45*width)
  chest : bottom y=2.85 .. helmet top y=6.25 (3.4 tall), centred x=0
  arm   : 3.2 long, top (pad) at neck height + 0.15, hanging; inner edge near the chest's side
Cuts (horizontal planes, chosen at the narrowest section inside a window of the piece height) are capped with the
real cross-section (cut.py). Left side = mirror X, flipped winding, mirrored normals.
usage: python build_tier.py <T> [--norender]"""
import sys, os, json, pickle, io
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from gio import read_glb, write_glb
from dec import decimate, vnormals
from cut import split

ROOT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d'
RAW = ROOT + r'\work\raw'
PREP = ROOT + r'\work\prep'
os.makedirs(PREP, exist_ok=True)
MAXT = 19500


def rotY(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


# Tripo multiview puts the FRONT reference image facing +X: rotate +90 deg about Y so it faces -Z.
ROT = rotY(90)


def prep(piece, target=56000):
    fn = os.path.join(PREP, piece + '.pkl')
    if os.path.exists(fn):
        return pickle.load(open(fn, 'rb'))
    p, n, t, ix, tx = read_glb(os.path.join(RAW, piece + '.glb'))
    p = p @ ROT.T; n = n @ ROT.T
    p, n, t, ix = decimate(p, n, t, ix, target)
    texs = {}
    for k in ('base', 'mr', 'normal'):
        im = tx.get(k)
        if im is not None:
            texs[k] = im.resize((1024, 1024), Image.LANCZOS)
    texs['factors'] = tx['factors']
    out = (p, n, t, ix, texs)
    pickle.dump(out, open(fn, 'wb'))
    return out


def dark_uv(base):
    """uv of a flat, dark, low-saturation texel (cut caps)."""
    from scipy.ndimage import uniform_filter
    im = np.asarray(base.convert('RGB')).astype(float)
    lum = im.mean(2); sat = im.max(2) - im.min(2)
    mean = uniform_filter(lum, 7); std = np.sqrt(np.maximum(uniform_filter(lum ** 2, 7) - mean ** 2, 0))
    score = np.where((mean > 25) & (mean < 70) & (uniform_filter(sat, 7) < 30), std + np.abs(mean - 45) * 0.2, 1e9)
    if not np.isfinite(score).any() or score.min() >= 1e9:
        score = mean
    yy, xx = np.unravel_index(np.argmin(score), score.shape)
    H, W = lum.shape
    return np.array([(xx + 0.5) / W, (yy + 0.5) / H])


def profile(p, ix, nb=120):
    """width^2-ish area per height bin (from triangle centroids)."""
    c = p[ix].mean(1)
    y0, y1 = p[:, 1].min(), p[:, 1].max()
    bins = np.linspace(y0, y1, nb + 1)
    k = np.clip(np.digitize(c[:, 1], bins) - 1, 0, nb - 1)
    area = np.zeros(nb)
    for i in range(nb):
        q = c[k == i]
        if len(q) > 3:
            lo = np.percentile(q[:, [0, 2]], 3, axis=0); hi = np.percentile(q[:, [0, 2]], 97, axis=0)
            area[i] = np.prod(hi - lo)
    return bins, area


def find_cut(p, ix, lo, hi):
    """y of the narrowest section between fractions lo..hi measured from the TOP of the piece."""
    bins, area = profile(p, ix)
    y0, y1 = bins[0], bins[-1]
    mid = (bins[:-1] + bins[1:]) / 2
    fr = (y1 - mid) / (y1 - y0)
    m = (fr >= lo) & (fr <= hi) & (area > 0)
    if not m.any():
        return y1 - (lo + hi) / 2 * (y1 - y0)
    a = np.convolve(area, np.ones(3) / 3, 'same')
    i = np.where(m)[0][np.argmin(a[m])]
    return float(mid[i])


def norm_piece(p, height):
    s = height / np.ptp(p[:, 1])
    q = p * s
    c = (q.min(0) + q.max(0)) / 2
    q[:, 0] -= c[0]; q[:, 2] -= c[2]; q[:, 1] -= q[:, 1].min()
    return q, s


def cut_chain(mesh, cuts, cap_uv):
    """cuts: descending y. returns list of meshes top->bottom and loops per cut."""
    p, n, t, ix = mesh
    out, loops = [], []
    rest = (p, n, t, ix)
    for y in cuts:
        below, above, lp = split(*rest, y, cap_uv)
        out.append(above); loops.append(lp); rest = below
    out.append(rest)
    return out, loops


def loop_center(loops, y, fallback):
    if not loops:
        return [float(fallback[0]), float(y), float(fallback[2])]
    big = max(loops, key=lambda L: len(L))
    allp = np.vstack(loops)
    c = allp.mean(0)
    return [float(c[0]), float(y), float(c[1])]


def limit(mesh, maxt=MAXT):
    p, n, t, ix = mesh
    if len(ix) > maxt:
        p, n, t, ix = decimate(p, n, t, ix, maxt - 200)
    return p, n, t, ix


def mirror(mesh):
    p, n, t, ix = mesh
    p = p * [-1, 1, 1]; n = n * [-1, 1, 1]
    return p, n, t, ix[:, [0, 2, 1]]


def r3(v):
    return [round(float(x), 4) for x in v]


def build(T, render=True):
    tag = '%d' % T
    arm, leg, chest = prep(tag + '01_arm'), prep(tag + '02_leg'), prep(tag + '03_chest')
    nodes, piv = [], {}

    # ---------- chest + head
    p, n, t, ix, tx_c = chest
    p, s = norm_piece(p, 3.4); p[:, 1] += 2.85
    cap = dark_uv(tx_c['base'])
    y_top, y_bot = p[:, 1].max(), p[:, 1].min()
    H = y_top - y_bot
    y_neck = find_cut(p, ix, 0.24, 0.42)
    y_waist = find_cut(p, ix, 0.80, 0.90)
    has_lower = (y_waist - y_bot) > 0.18
    cuts = [y_neck] + ([y_waist] if has_lower else [])
    parts, loops = cut_chain((p, n, t, ix), cuts, cap)
    names = ['Head', 'Torso_Upper'] + (['Torso_Lower'] if has_lower else [])
    for nm, m in zip(names, parts):
        nodes.append((nm, *limit(m), 2))
    piv['neck'] = loop_center(loops[0], y_neck, [0, 0, 0])
    if has_lower:
        piv['waist'] = loop_center(loops[1], y_waist, [0, 0, 0])
    else:
        piv['waist'] = [0.0, float(y_bot), 0.0]
    # chest half width at shoulder level (a bit under the neck)
    cpts = p[(p[:, 1] < y_neck - 0.1) & (p[:, 1] > y_neck - 0.9)]
    half_w = np.percentile(np.abs(cpts[:, 0]), 98) if len(cpts) else 1.0
    zc_chest = (np.percentile(cpts[:, 2], 2) + np.percentile(cpts[:, 2], 98)) / 2 if len(cpts) else 0.0

    # ---------- arm (right)
    p, n, t, ix, tx_a = arm
    p, s = norm_piece(p, 3.2)
    cap = dark_uv(tx_a['base'])
    y_elbow = find_cut(p, ix, 0.40, 0.56)
    y_wrist = find_cut(p, ix, 0.70, 0.82)
    # place: top at neck + 0.15, inner edge tucked 25% of arm width into the chest side
    w = np.ptp(p[:, 0])
    dx = half_w + w * 0.25
    dy = y_neck + 0.15 - 3.2
    p = p + [dx, dy, zc_chest]
    y_elbow += dy; y_wrist += dy
    parts, loops = cut_chain((p, n, t, ix), [y_elbow, y_wrist], cap)
    arm_axis = loop_center(loops[0], y_elbow, p.mean(0))
    piv['shoulder_R'] = [arm_axis[0], float(parts[0][0][:, 1].max()), arm_axis[2]]
    piv['elbow_R'] = arm_axis
    piv['wrist_R'] = loop_center(loops[1], y_wrist, p.mean(0))
    for nm, m in zip(['ArmR_Upper', 'ArmR_Lower', 'ArmR_Hand'], parts):
        m = limit(m)
        nodes.append((nm, *m, 0))
        nodes.append((nm.replace('ArmR', 'ArmL'), *mirror(m), 0))

    # ---------- leg (right)
    p, n, t, ix, tx_l = leg
    p, s = norm_piece(p, 3.0)
    cap = dark_uv(tx_l['base'])
    y_knee = find_cut(p, ix, 0.40, 0.58)
    y_ankle = find_cut(p, ix, 0.76, 0.90)
    w = np.ptp(p[:, 0])
    p = p + [max(0.5, 0.45 * w), 0, zc_chest]
    parts, loops = cut_chain((p, n, t, ix), [y_knee, y_ankle], cap)
    knee = loop_center(loops[0], y_knee, p.mean(0))
    piv['hip_R'] = [knee[0], float(parts[0][0][:, 1].max()), knee[2]]
    piv['knee_R'] = knee
    piv['ankle_R'] = loop_center(loops[1], y_ankle, p.mean(0))
    for nm, m in zip(['LegR_Upper', 'LegR_Lower', 'LegR_Foot'], parts):
        m = limit(m)
        nodes.append((nm, *m, 1))
        nodes.append((nm.replace('LegR', 'LegL'), *mirror(m), 1))
    for k in ('shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle'):
        v = piv[k + '_R']
        piv[k + '_L'] = [-v[0], v[1], v[2]]

    order = ['Torso_Upper', 'Torso_Lower', 'Head', 'ArmR_Upper', 'ArmR_Lower', 'ArmR_Hand', 'ArmL_Upper', 'ArmL_Lower',
             'ArmL_Hand', 'LegR_Upper', 'LegR_Lower', 'LegR_Foot', 'LegL_Upper', 'LegL_Lower', 'LegL_Foot']
    nodes.sort(key=lambda x: order.index(x[0]))
    mats = [dict(tx_a, name='T%02d_Arm' % T), dict(tx_l, name='T%02d_Leg' % T), dict(tx_c, name='T%02d_Chest' % T)]
    out = os.path.join(ROOT, 'Gear_T%02d.glb' % T)
    write_glb(out, nodes, mats, size=1024, gen='gear3d build_tier.py')
    meta = {'file': os.path.basename(out), 'nodes': {}, 'pivots': {k: r3(v) for k, v in piv.items()}}
    for nm, p, n, t, ix, mi in nodes:
        meta['nodes'][nm] = {'bbox_min': r3(p.min(0)), 'bbox_max': r3(p.max(0)), 'tris': int(len(ix)),
                             'material': mats[mi]['name']}
    json.dump(meta, open(os.path.join(ROOT, 'work', 'meta_T%02d.json' % T), 'w'), indent=1)
    print('T%02d' % T, os.path.getsize(out) // 1024, 'KB', {nm: int(len(ix)) for nm, p, n, t, ix, mi in nodes})
    if render:
        from render_tier import render_tier
        render_tier(T, nodes, mats)
    return meta


if __name__ == '__main__':
    build(int(sys.argv[1]), render='--norender' not in sys.argv)
