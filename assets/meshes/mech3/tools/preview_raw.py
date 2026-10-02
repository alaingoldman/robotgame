"""Quick textured views of the raw Meshy GLB (as delivered, no flip) to check orientation/quality."""
import sys, io, numpy as np
from PIL import Image
from glbio import load_raw
from raster import render
D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
pos, uv, nrm, idx, jpg, mime = load_raw(D + r'\source\mech_raw.glb')
tex = np.asarray(Image.open(io.BytesIO(bytes(jpg))).convert('RGB'))
H, W = tex.shape[:2]
fuv = uv[idx].mean(1)
fc = tex[np.clip((fuv[:, 1] % 1) * (H - 1), 0, H - 1).astype(int), np.clip((fuv[:, 0] % 1) * (W - 1), 0, W - 1).astype(int)]
parts = [(pos, idx, fc)]
size = 500
ims = [render(parts, v, size, title=v) for v in ['front', 'side', 'back', 'threequarter']]
im = Image.new('RGB', (size * 4, size), 'white')
for i, x in enumerate(ims): im.paste(x, (size * i, 0))
im.save(sys.argv[1])
