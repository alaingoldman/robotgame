"""v2 texture: turn Meshy's baked copy of the cel-shaded sheet (ink outlines, speckle dots, flat paper
fills) into painted metal, plus glTF PBR maps. Writes v2/basecolor.png, v2/metal_rough.png, v2/normal.png
and debug images. Run before build_v2.py.

Steps (all in texture space, per UV island so nothing bleeds across atlas seams):
  1. rasterise the UV triangles -> coverage + island id per texel
  2. classify texels into the palette: plate (navy), panel (steel blue), joint (grey), recess (near black),
     glow (bright cyan); thin near-black strokes are INK, not recess
  3. majority filter the class map (kills the dot noise), refill ink / dot texels from the nearest
     neighbouring class in the same island
  4. every connected class region gets one flat colour (its robust median), then subtle metal:
     low-frequency tonal drift, fine brushed grain, soft lighter wear along panel edges
  5. maps: metallic/roughness per class (+grain), a normal map with soft grooves along the panel
     boundaries (height field -> tangent-space normals, glTF +Y-up convention)
  6. pad every island outward so mip-maps don't pull in the background
"""
import io, sys, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
import trimesh
from glbio import load_raw

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
OUT = D + r'\v2'
rng = np.random.default_rng(3)

pos, uv, nrm, idx, jpg, mime = load_raw(D + r'\source\mech_raw.glb')
src = np.asarray(Image.open(io.BytesIO(bytes(jpg))).convert('RGB')).astype(np.float32)
H, W = src.shape[:2]

# ---- 1. coverage + island ids (islands = UV-connected triangle groups)
cc = trimesh.graph.connected_components(trimesh.Trimesh(np.c_[uv, np.zeros(len(uv))], idx, process=False).face_adjacency,
                                        nodes=np.arange(len(idx)), min_len=1)
fisland = np.zeros(len(idx), np.int32)
for i, comp in enumerate(cc):
    fisland[comp] = i + 1
isl_img = Image.new('I', (W, H), 0)
dr = ImageDraw.Draw(isl_img)
P = uv[idx] * [W, H]
for f in range(len(idx)):
    dr.polygon([tuple(p) for p in P[f]], fill=int(fisland[f]), outline=int(fisland[f]))
island = np.asarray(isl_img, np.int32)
cover = island > 0
print('islands', len(cc), 'coverage %.2f' % cover.mean())

# ---- 2. classify
lum = src.mean(2)
r, g, b = src[..., 0], src[..., 1], src[..., 2]
sat = src.max(2) - src.min(2)
PLATE, PANEL, JOINT, RECESS, GLOW, INK = 1, 2, 3, 4, 5, 9
cls = np.full((H, W), PLATE, np.uint8)
cls[(lum >= 80) & (lum < 118) & (b - r < 9)] = JOINT
cls[lum >= 112] = PANEL
cls[(lum >= 112) & (b - r >= 9) & (lum < 125)] = PANEL
cls[(b > 200) & (g > 170) & (sat > 70)] = GLOW
dark = lum < 33
thick = ndi.binary_opening(dark, structure=np.ones((7, 7)))       # wide dark blobs = real recesses
thick = ndi.binary_dilation(thick, iterations=2) & dark
cls[thick] = RECESS
ink = (dark & ~thick)
# antialiased fringe of the ink strokes and darker-than-surroundings thin lines
med = ndi.median_filter(lum, size=7)
ink |= (lum < med - 22) & (lum < 60)
ink = ndi.binary_dilation(ink, iterations=1) & ~thick
cls[ink] = INK
cls[~cover] = 0
print('ink share %.3f' % (ink & cover).mean())

# ---- 3. majority filter + refill ink from the nearest real class in the same island
def mode_filter(c, size):
    best = np.zeros(c.shape, np.float32); out = c.copy()
    for k in (PLATE, PANEL, JOINT, RECESS, GLOW):
        cnt = ndi.uniform_filter((c == k).astype(np.float32), size)
        m = cnt > best
        best[m] = cnt[m]; out[m] = k
    return out

real = (cls != INK) & cover
_, (iy, ix) = ndi.distance_transform_edt(~real, return_indices=True)
filled = cls[iy, ix]
same = island[iy, ix] == island
filled[~same & cover] = PLATE
filled[~cover] = 0
lab = mode_filter(filled, 5)
lab = mode_filter(lab, 7)
lab[~cover] = 0
# glow keeps its exact small shapes (eyes / slits), unfiltered
lab[(filled == GLOW) & ndi.binary_opening(filled == GLOW, iterations=1)] = GLOW

# ---- 4. paint: ink texels refilled from the nearest clean texel of the same island, the dot noise
# median-filtered out (gradients and the drawing's real shapes - frames, stripes, rims - stay), then
# each class pulled toward one paint colour so the cel-shade bands merge
CLEAN = (~ink) & cover
_, (cy_, cx_) = ndi.distance_transform_edt(~CLEAN, return_indices=True)
okfill = island[cy_, cx_] == island
fillsrc = src[cy_, cx_]
fillsrc[~okfill] = src[~okfill]
base = np.stack([ndi.median_filter(ndi.median_filter(fillsrc[..., ch], size=3), size=5) for ch in range(3)], -1)
PAL = {PLATE: (58, 60, 74), PANEL: (132, 160, 182), JOINT: (88, 90, 95), RECESS: (32, 33, 38), GLOW: (110, 205, 255)}
for k, c in PAL.items():
    m = lab == k
    base[m] = base[m] * 0.7 + np.array(c, np.float32) * 0.3


def field(sigma, amp):
    f = ndi.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), sigma)
    return f / (f.std() + 1e-6) * amp


tone = field(28, 0.035) + field(7, 0.015)                     # low-frequency drift
grain = ndi.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), (0.6, 5.0))
grain = grain / grain.std() * 0.012                           # fine brushed grain
# panel edges (class boundaries inside one island): soft lighter wear
edge = np.zeros((H, W), bool)
for dy, dx in ((0, 1), (1, 0)):
    a = lab[: H - dy, : W - dx]; bb = lab[dy:, dx:]
    ia = island[: H - dy, : W - dx]; ib = island[dy:, dx:]
    e = (a != bb) & (a > 0) & (bb > 0) & (ia == ib)
    edge[: H - dy, : W - dx] |= e; edge[dy:, dx:] |= e
# the drawing's ink strokes were the panel seams: long ones (not the speckle) become seams too
inkl, nink = ndi.label(ink & cover)
sizes = ndi.sum(np.ones_like(lum), inkl, index=np.arange(1, nink + 1))
seam = np.isin(inkl, np.where(sizes >= 30)[0] + 1)
seam = ndi.binary_erosion(seam, iterations=1) | (seam & ~ndi.binary_dilation(~seam, iterations=1))
dist_edge = ndi.distance_transform_edt(~edge)
dist = ndi.distance_transform_edt(~(edge | seam))
wear = np.exp(-(dist_edge / 2.2) ** 2) * (0.6 + 0.4 * field(3, 1.0).clip(-1, 1))
wear_k = np.where(lab == PLATE, 0.16, np.where(lab == PANEL, 0.08, np.where(lab == JOINT, 0.06, 0.0)))
shade = 1 + tone + grain
col = base * shade[..., None]
steel = np.array((150, 156, 166), np.float32)
w = (wear * wear_k)[..., None]
col = col * (1 - w) + steel * w
col[lab == GLOW] = base[lab == GLOW]

# ---- 5. PBR maps
metal = np.select([lab == PLATE, lab == PANEL, lab == JOINT, lab == RECESS, lab == GLOW], [0.72, 0.65, 0.35, 0.5, 0.0], 0.6)
rough = np.select([lab == PLATE, lab == PANEL, lab == JOINT, lab == RECESS, lab == GLOW], [0.42, 0.38, 0.55, 0.6, 0.3], 0.45)
rough = rough + field(10, 0.04) + grain * 1.5 - wear * 0.1
metal = metal + wear * 0.15 * (lab != GLOW)
height = -np.exp(-(dist / 1.4) ** 2) * 1.0 + field(2, 0.02)
height = ndi.gaussian_filter(height, 0.7)
gy, gx = np.gradient(height)
strength = 2.2
nx, ny, nz = -gx * strength, gy * strength, np.ones_like(gx)     # glTF: +X right, +Y up (image rows go down)
nl = np.sqrt(nx * nx + ny * ny + nz * nz)
normal = np.stack([nx / nl, ny / nl, nz / nl], -1)

# ---- 6. pad islands outward (nearest covered texel)
_, (py, px) = ndi.distance_transform_edt(~cover, return_indices=True)


def pad(a):
    return a[py, px]


col, metal, rough, normal = pad(col), pad(metal), pad(rough), pad(normal)
mr = np.zeros((H, W, 3), np.float32)
mr[..., 1] = np.clip(rough, 0.05, 1) * 255                       # glTF: G = roughness, B = metallic
mr[..., 2] = np.clip(metal, 0, 1) * 255
Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save(OUT + r'\basecolor.png', optimize=True)
Image.fromarray(mr.astype(np.uint8)).save(OUT + r'\metal_rough.png', optimize=True)
Image.fromarray(((normal * 0.5 + 0.5) * 255).astype(np.uint8)).save(OUT + r'\normal.png', optimize=True)
# debug: class map
dbg = np.zeros((H, W, 3), np.uint8)
for k, c in {PLATE: (60, 60, 160), PANEL: (120, 200, 255), JOINT: (160, 160, 160), RECESS: (20, 20, 20), GLOW: (0, 255, 255)}.items():
    dbg[lab == k] = c
Image.fromarray(dbg).save(OUT + r'\debug_classes.png')
print('done', {k: float((lab == k).mean()) for k in (PLATE, PANEL, JOINT, RECESS, GLOW)})
