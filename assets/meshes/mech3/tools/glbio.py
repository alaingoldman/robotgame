"""GLB read/write helpers (from crimson/tools/build.py)."""
import json, struct, numpy as np
from pygltflib import GLTF2


def load_raw(fn):
    gl = GLTF2().load(fn)
    blob = gl.binary_blob()

    def acc(i):
        a = gl.accessors[i]; bv = gl.bufferViews[a.bufferView]
        ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a.componentType]
        off = (bv.byteOffset or 0) + (a.byteOffset or 0)
        arr = np.frombuffer(blob, dt, a.count * ncomp, off)
        return arr.reshape(a.count, ncomp) if ncomp > 1 else arr
    pr = gl.meshes[0].primitives[0]
    pos = acc(pr.attributes.POSITION).astype(float)
    uv = acc(pr.attributes.TEXCOORD_0).astype(float)
    nrm = acc(pr.attributes.NORMAL).astype(float)
    idx = acc(pr.indices).astype(np.int64).reshape(-1, 3)
    img = gl.images[0]; bv = gl.bufferViews[img.bufferView]
    jpg = blob[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength]
    return pos, uv, nrm, idx, jpg, img.mimeType


def write_glb(fn, parts, jpg, mime):
    """parts: list of (name, pos Nx3, nrm Nx3, uv Nx2, idx Mx3)."""
    blob = bytearray()
    bviews, accs, meshes, nodes = [], [], [], []

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
    img_bv = add_view(bytes(jpg))
    while len(blob) % 4: blob.append(0)
    gj = {
        'asset': {'version': '2.0', 'generator': 'mech3 build.py'},
        'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes, 'meshes': meshes,
        'materials': [{'name': 'Mech3Mat', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 0.8}}],
        'textures': [{'sampler': 0, 'source': 0}], 'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
        'images': [{'bufferView': img_bv, 'mimeType': mime}],
        'accessors': accs, 'bufferViews': bviews, 'buffers': [{'byteLength': len(blob)}],
    }
    js = json.dumps(gj, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(fn, 'wb').write(out)


def dark_uv(jpg):
    from PIL import Image
    import io
    from scipy.ndimage import uniform_filter
    im = np.asarray(Image.open(io.BytesIO(bytes(jpg))).convert('RGB')).astype(float)
    lum = im.mean(2)
    mean = uniform_filter(lum, 9); sq = uniform_filter(lum ** 2, 9)
    std = np.sqrt(np.maximum(sq - mean ** 2, 0))
    sat = im.max(2) - im.min(2)
    score = np.where((mean > 35) & (mean < 70) & (uniform_filter(sat, 9) < 18), std, 1e9)
    yy, xx = np.unravel_index(np.argmin(score), score.shape)
    H, W = lum.shape
    return np.array([(xx + 0.5) / W, (yy + 0.5) / H]), im[yy, xx]   # glTF uv origin top-left


