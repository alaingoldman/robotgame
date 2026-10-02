import json, os, numpy as np
from PIL import Image, ImageDraw

D = os.path.dirname(os.path.abspath(__file__))
OUT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes'
N = 1024  # texture px per 4-stud tile


# ---------------- textures ----------------

def crosshatch_alpha():
    """Weld lattice of MechPattern's Crosshatch largeImage (rbxassetid://133133290921309), measured
    off Studio: 4x4 cells per tile, one diagonal bar per cell alternating \\ and / in a checkerboard,
    bar from 13% to 84% of the cell, grey ~185 with a darker 169 rim on white. Returns luminance L."""
    yy, xx = np.mgrid[0:N, 0:N] + 0.5
    cell = N / 4
    s = N / 600.0
    prof_d = np.array([0, 1.41, 2.83, 4.24, 5.66, 7.07, 8.5, 99]) * s
    prof_L = np.array([187, 185, 169, 176, 217, 250, 255, 255], float)
    best = np.full((N, N), 1e9)
    for cy in range(4):
        for cx in range(4):
            x0, y0 = cx * cell, cy * cell
            a0, a1 = 0.133 * cell, 0.84 * cell
            if (cx + cy) % 2 == 0:  # "\"
                A = np.array([x0 + a0, y0 + a0]); B = np.array([x0 + a1, y0 + a1])
            else:  # "/"
                A = np.array([x0 + a1, y0 + a0]); B = np.array([x0 + a0, y0 + a1])
            AB = B - A
            t = np.clip(((xx - A[0]) * AB[0] + (yy - A[1]) * AB[1]) / AB.dot(AB), 0, 1)
            d = np.hypot(xx - (A[0] + t * AB[0]), yy - (A[1] + t * AB[1]))
            best = np.minimum(best, d)
    return np.interp(best, prof_d, prof_L)


def write_textures():
    L = crosshatch_alpha()
    # Roblox: Texture tinted by the part colour at Transparency 0.5 over the part colour
    #   = C * (0.5 + 0.5 * L/255) = C * (1 - a) with a black overlay of alpha a = 0.5 * (1 - L/255)
    a = 0.5 * (1 - L / 255.0)
    rgba = np.zeros((N, N, 4), np.uint8)
    rgba[..., 3] = np.round(a * 255).astype(np.uint8)
    Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, 'Titan_Crosshatch_Overlay.png'))
    # the plain lattice (opaque, white background) for reference / tinting setups
    g = np.round(L).astype(np.uint8)
    Image.fromarray(g, 'L').save(os.path.join(OUT, 'Titan_Crosshatch_Lattice.png'))
    return a


def checker():
    yy, xx = np.mgrid[0:N, 0:N]
    c = ((xx // (N // 4) + yy // (N // 4)) % 2).astype(float)
    img = np.stack([0.25 + 0.6 * c, 0.35 + 0.3 * (xx / N), 0.85 - 0.6 * c * (yy / N)], -1)
    img[(xx % (N // 4) < 6) | (yy % (N // 4) < 6)] = [0.1, 0.1, 0.1]
    img[(xx < 14) | (yy < 14)] = [0.9, 0.1, 0.1]  # tile seam marker (every 4 studs)
    return img


# ---------------- rasterizer ----------------

def look(eye, target):
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return np.stack([r, u, -f]), eye


def render(meshes, eye, target, W=640, H=640, fov=30, mode='hatch', alpha=None, chk=None, ss=2):
    W2, H2 = W * ss, H * ss
    R, E = look(np.array(eye, float), np.array(target, float))
    fpx = (H2 / 2) / np.tan(np.radians(fov) / 2)
    img = np.ones((H2, W2, 3)) * np.array([0.93, 0.94, 0.96])
    zb = np.full((H2, W2), np.inf)
    light = np.array([-0.45, 0.8, -0.4]); light /= np.linalg.norm(light)
    for m in meshes:
        P = np.array(m['P']) + m.get('offset', 0)
        UV = np.array(m['UV'])
        cn = np.array(m['cn'])
        base = np.array(m['color']) / 255.0
        cam = (P - E) @ R.T  # x right, y up, z back (visible: z < 0)
        for k, (vs, ts, role, kind) in enumerate(m['faces']):
            if role not in m['roles']:
                continue
            c = cam[vs]
            if (c[:, 2] > -0.05).any():
                continue
            sx = W2 / 2 + fpx * c[:, 0] / -c[:, 2]
            sy = H2 / 2 - fpx * c[:, 1] / -c[:, 2]
            area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0])
            if area >= 0:  # back face (CCW from outside -> negative in y-down screen space): culled like Roblox
                continue
            x0, x1 = int(max(np.floor(sx.min()), 0)), int(min(np.ceil(sx.max()), W2 - 1))
            y0, y1 = int(max(np.floor(sy.min()), 0)), int(min(np.ceil(sy.max()), H2 - 1))
            if x1 < x0 or y1 < y0:
                continue
            yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
            w0 = ((sx[1] - xx) * (sy[2] - yy) - (sx[2] - xx) * (sy[1] - yy)) / area
            w1 = ((sx[2] - xx) * (sy[0] - yy) - (sx[0] - xx) * (sy[2] - yy)) / area
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            iz = np.array([1 / -c[0, 2], 1 / -c[1, 2], 1 / -c[2, 2]])
            izp = w0 * iz[0] + w1 * iz[1] + w2 * iz[2]
            depth = 1 / izp
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            vis = inside & (depth < sub)
            if not vis.any():
                continue
            b0, b1, b2 = w0 * iz[0] / izp, w1 * iz[1] / izp, w2 * iz[2] / izp
            uv = UV[ts]
            u = b0 * uv[0, 0] + b1 * uv[1, 0] + b2 * uv[2, 0]
            v = b0 * uv[0, 1] + b1 * uv[1, 1] + b2 * uv[2, 1]
            nrm = b0[..., None] * cn[k][0] + b1[..., None] * cn[k][1] + b2[..., None] * cn[k][2]
            nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
            lam = np.clip(nrm @ light, 0, 1)
            shade = 0.42 + 0.58 * lam
            tu = ((u % 1) * N).astype(int) % N
            tv = ((v % 1) * N).astype(int) % N
            if mode == 'hatch':
                col = base[None, None, :] * (1 - alpha[tv, tu])[..., None]
            else:
                col = chk[tv, tu]
            col = col * shade[..., None]
            region = img[y0:y1 + 1, x0:x1 + 1]
            region[vis] = col[vis]
            sub[vis] = depth[vis]
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    return im.resize((W, H), Image.LANCZOS)


def uv_layout(m, roles, size=640):
    UV = np.array(m['UV'])
    sel = [f for f in m['faces'] if f[2] in roles and f[3] == 'outer']
    pts = np.concatenate([UV[f[1]] for f in sel])
    lo, hi = np.floor(pts.min(0)), np.ceil(pts.max(0))
    span = max(hi - lo)
    sc = (size - 40) / span
    im = Image.new('RGB', (size, size), (250, 250, 250))
    d = ImageDraw.Draw(im)
    for i in range(int(span) + 1):  # one grid line per texture repeat (4 studs)
        p = 20 + i * sc
        d.line([(p, 20), (p, size - 20)], fill=(200, 60, 60))
        d.line([(20, p), (size - 20, p)], fill=(200, 60, 60))
    for f in sel:
        q = [(20 + (UV[t][0] - lo[0]) * sc, 20 + (UV[t][1] - lo[1]) * sc) for t in f[1]]
        d.polygon(q, outline=(30, 30, 30))
    d.text((24, size - 18), 'UV islands (red grid = 1 texture repeat = 4 studs)', fill=(0, 0, 0))
    return im


if __name__ == '__main__':
    alpha = write_textures()
    chk = checker()
    meshes = json.load(open(os.path.join(D, 'meshes.json')))
    meta = json.load(open(os.path.join(D, 'meta.json')))
    bones = {k: np.array(v[:3]) for k, v in meta['_bones'].items()}
    BRONZE = dict(main=(138, 96, 46), hi=(198, 156, 82))

    def item(name, roles, color, offset=None):
        m = dict(meshes[name])
        m['roles'] = roles
        m['color'] = color
        if offset is not None:
            m['offset'] = offset
        return m

    shots = {
        'Titan_ShoulderPad_R': ([item('Titan_ShoulderPad_R', {'main'}, BRONZE['main'])], [(14, 12, -12), (5.3, 6.5, 0.7)], [(-4, 14, 13), (5.3, 6.5, 0.7)]),
        'Titan_ShoulderPad_L': ([item('Titan_ShoulderPad_L', {'main'}, BRONZE['main'])], [(-14, 12, -12), (-5.3, 6.5, 0.7)], [(4, 14, 13), (-5.3, 6.5, 0.7)]),
        'Titan_ChestDome': ([item('Titan_ChestDome', {'main'}, BRONZE['main']), item('Titan_ChestDome', {'hi'}, BRONZE['hi'])],
                            [(-8, 7, -14), (0, 2.4, -1)], [(10, 2, -12), (0, 2.4, -1)]),
        'Titan_Helmet': ([item('Titan_Helmet', {'main'}, BRONZE['main']), item('Titan_HelmetCap', {'hi'}, BRONZE['hi'])],
                         [(-5, 5.5, -6), (0, 1.4, 0)], [(6, 4, 6), (0, 1.4, 0)]),
    }
    for name, (ms, v1, v2) in shots.items():
        tiles = []
        for mode in ('hatch', 'checker'):
            for eye, tgt in (v1, v2):
                tiles.append(render(ms, eye, tgt, mode=mode, alpha=alpha, chk=chk, W=480, H=480))
        tiles.append(uv_layout(meshes[name], {'main', 'hi'}, 480))
        sheet = Image.new('RGB', (480 * 3, 480 * 2), (255, 255, 255))
        pos = [(0, 0), (480, 0), (0, 480), (480, 480), (960, 0)]
        for t, p in zip(tiles, pos):
            sheet.paste(t, p)
        d = ImageDraw.Draw(sheet)
        d.text((968, 488), name + '\ntop: crosshatch overlay on Bronze (as in Roblox)\nbottom: UV checker, red = 4-stud tile edge\nright: UV islands', fill=(0, 0, 0))
        sheet.save(os.path.join(OUT, name + '_preview.png'))
        print('wrote', name)
    # everything placed on the Chest bone frame (closed hatch, build pose)
    ch = bones['Chest']
    allm = [item('Titan_ShoulderPad_R', {'main'}, BRONZE['main']), item('Titan_ShoulderPad_L', {'main'}, BRONZE['main']),
            item('Titan_ChestDome', {'main'}, BRONZE['main'], bones['Hatch'] - ch), None,
            item('Titan_Helmet', {'main'}, BRONZE['main'], bones['Head'] - ch), None]
    allm[3] = dict(meshes['Titan_ChestDome'], roles={'hi'}, color=BRONZE['hi'], offset=bones['Hatch'] - ch)
    allm[5] = dict(meshes['Titan_HelmetCap'], roles={'hi'}, color=BRONZE['hi'], offset=bones['Head'] - ch)
    a = render(allm, (-12, 14, -30), (0, 6, 0), W=720, H=720, alpha=alpha, chk=chk)
    b = render(allm, (16, 12, 24), (0, 6, 0), W=720, H=720, alpha=alpha, chk=chk)
    sheet = Image.new('RGB', (1440, 720))
    sheet.paste(a, (0, 0)); sheet.paste(b, (720, 0))
    sheet.save(os.path.join(OUT, 'Titan_AllMeshes_preview.png'))
    print('wrote all')
