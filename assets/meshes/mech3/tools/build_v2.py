"""Mech3_v2.glb: the SAME 19 parts as Mech3.glb (same vertices, UVs and triangles) with
  * the cleaned metal base colour (retexture.py) + glTF PBR: metallicRoughnessTexture and normalTexture
  * two small geometry fixes so nothing floats:
      - ShoulderPad_L/R: the pad's lower outer flap (|x| > 2.9, y < 16.35) is pulled in onto the upper
        arm (it hung 0.25 studs outside it, sky showed through the slit)
      - Wing_L/R: slid 0.2 studs in toward the body so the panel's inner edge sits on the shoulder pad
        (min gap was 0.19); Mech3Builder adds a hinge bracket from the backpack to the wing root
Writes ../Mech3_v2.glb and meta_v2.json (pivots updated for the wing shift)."""
import json, struct, numpy as np
from pygltflib import GLTF2

D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\meshes\mech3'
WING_IN = 0.2
PAD_IN = 0.22


def load_parts(fn):
    gl = GLTF2().load(fn)
    blob = gl.binary_blob()

    def acc(i):
        a = gl.accessors[i]; bv = gl.bufferViews[a.bufferView]
        ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a.componentType]
        off = (bv.byteOffset or 0) + (a.byteOffset or 0)
        arr = np.frombuffer(blob, dt, a.count * ncomp, off)
        return (arr.reshape(a.count, ncomp) if ncomp > 1 else arr).copy()
    out = []
    for node in gl.nodes:
        pr = gl.meshes[node.mesh].primitives[0]
        out.append((node.name, acc(pr.attributes.POSITION).astype(float), acc(pr.attributes.NORMAL).astype(float),
                    acc(pr.attributes.TEXCOORD_0).astype(float), acc(pr.indices).astype(np.int64).reshape(-1, 3)))
    return out


def write_glb(fn, parts, images):
    """images: list of (png bytes) -> [basecolor, metalRough, normal]."""
    blob = bytearray(); bviews, accs, meshes, nodes = [], [], [], []

    def add_view(data, target=None):
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(data)
        bv = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
        if target: bv['target'] = target
        bviews.append(bv); return len(bviews) - 1

    for name, p, n, t, ix in parts:
        p = p.astype(np.float32); n = n.astype(np.float32); t = t.astype(np.float32); ix = ix.astype(np.uint32)
        a0 = len(accs)
        accs.append({'bufferView': add_view(p.tobytes(), 34962), 'componentType': 5126, 'count': len(p), 'type': 'VEC3',
                     'min': p.min(0).tolist(), 'max': p.max(0).tolist()})
        accs.append({'bufferView': add_view(n.tobytes(), 34962), 'componentType': 5126, 'count': len(n), 'type': 'VEC3'})
        accs.append({'bufferView': add_view(t.tobytes(), 34962), 'componentType': 5126, 'count': len(t), 'type': 'VEC2'})
        accs.append({'bufferView': add_view(ix.tobytes(), 34963), 'componentType': 5125, 'count': ix.size, 'type': 'SCALAR'})
        meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': a0, 'NORMAL': a0 + 1, 'TEXCOORD_0': a0 + 2},
                                                     'indices': a0 + 3, 'material': 0}]})
        nodes.append({'name': name, 'mesh': len(meshes) - 1})
    imgs = [{'bufferView': add_view(b), 'mimeType': 'image/png'} for b in images]
    while len(blob) % 4: blob.append(0)
    gj = {
        'asset': {'version': '2.0', 'generator': 'mech3 build_v2.py'},
        'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes, 'meshes': meshes,
        'materials': [{'name': 'Mech3Metal',
                       'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicRoughnessTexture': {'index': 1},
                                                'metallicFactor': 1.0, 'roughnessFactor': 1.0},
                       'normalTexture': {'index': 2, 'scale': 1.0}}],
        'textures': [{'sampler': 0, 'source': i} for i in range(len(imgs))],
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
        'images': imgs, 'accessors': accs, 'bufferViews': bviews, 'buffers': [{'byteLength': len(blob)}],
    }
    js = json.dumps(gj, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(fn, 'wb').write(out)


def smooth(x):
    x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)


parts = load_parts(D + r'\Mech3.glb')
out = []
for name, p, n, t, ix in parts:
    p = p.copy()
    sg = 1.0 if name.endswith('_R') else -1.0
    if name.startswith('ShoulderPad'):
        ax = np.abs(p[:, 0])
        k = smooth((ax - 2.9) / 0.35) * smooth((16.35 - p[:, 1]) / 0.35)
        p[:, 0] -= sg * PAD_IN * k
    if name.startswith('Wing'):
        p[:, 0] -= sg * WING_IN
    out.append((name, p, n, t, ix))
imgs = [open(D + rf'\v2\{f}.png', 'rb').read() for f in ('basecolor', 'metal_rough', 'normal')]
write_glb(D + r'\Mech3_v2.glb', out, imgs)

meta = json.load(open(D + r'\meta.json'))
for sd, sg in (('R', 1), ('L', -1)):
    w = meta['pivots']['WingRoot_' + sd]
    meta['pivots']['WingRoot_' + sd] = [round(w[0] - sg * WING_IN, 3), w[1], w[2]]
for name, p, *_ in out:
    meta['parts'][name]['bbox_min'] = np.round(p.min(0), 3).tolist()
    meta['parts'][name]['bbox_max'] = np.round(p.max(0), 3).tolist()
meta['v2'] = {'file': 'Mech3_v2.glb', 'wing_shift_in': WING_IN, 'pad_flap_in': PAD_IN,
              'material': 'PBR: baseColor (cleaned, no ink / dots) + metallicRoughness (G rough, B metal) + normal (panel-seam grooves)'}
json.dump(meta, open(D + r'\meta_v2.json', 'w'), indent=2)
print('wrote', D + r'\Mech3_v2.glb', 'wing roots', meta['pivots']['WingRoot_R'], meta['pivots']['WingRoot_L'])
