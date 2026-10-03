"""GLB IO for the gear pipeline: read a Tripo GLB (PBR), write a multi-node GLB with one shared PBR material."""
import json, struct, io, numpy as np
from pygltflib import GLTF2
from PIL import Image


def read_glb(fn):
    gl = GLTF2().load(fn)
    blob = gl.binary_blob()

    def acc(i):
        a = gl.accessors[i]; bv = gl.bufferViews[a.bufferView]
        ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a.componentType]
        off = (bv.byteOffset or 0) + (a.byteOffset or 0)
        arr = np.frombuffer(blob, dt, a.count * ncomp, off)
        return (arr.reshape(a.count, ncomp) if ncomp > 1 else arr).copy()

    def img(ti):
        if ti is None:
            return None
        im = gl.images[gl.textures[ti.index].source]; bv = gl.bufferViews[im.bufferView]
        return Image.open(io.BytesIO(blob[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength])).convert('RGB')
    Ps, Ns, Ts, Is = [], [], [], []
    off = 0
    for node in gl.nodes:
        if node.mesh is None:
            continue
        M = np.eye(4)
        if node.matrix:
            M = np.array(node.matrix).reshape(4, 4).T
        for pr in gl.meshes[node.mesh].primitives:
            p = acc(pr.attributes.POSITION).astype(float)
            p = p @ M[:3, :3].T + M[:3, 3]
            n = acc(pr.attributes.NORMAL).astype(float) if pr.attributes.NORMAL is not None else np.zeros_like(p)
            t = acc(pr.attributes.TEXCOORD_0).astype(float)
            ix = acc(pr.indices).astype(np.int64).reshape(-1, 3)
            Ps.append(p); Ns.append(n @ M[:3, :3].T); Ts.append(t); Is.append(ix + off); off += len(p)
    mat = gl.materials[0]
    pbr = mat.pbrMetallicRoughness
    texs = {'base': img(pbr.baseColorTexture), 'mr': img(pbr.metallicRoughnessTexture), 'normal': img(mat.normalTexture),
            'factors': (pbr.metallicFactor, pbr.roughnessFactor)}
    return np.vstack(Ps), np.vstack(Ns), np.vstack(Ts), np.vstack(Is), texs


def write_glb(fn, parts, mats, size=1024, sub_size=None, gen='gear3d'):
    """parts: list of (name, pos, nrm, uv, idx, mat_index). mats: list of dicts base/mr/normal PIL images (+name).
    size: base colour texture size; sub_size: metal-rough + normal size (default = size)."""
    sub_size = sub_size or size
    blob = bytearray(); bviews, accs, meshes, nodes = [], [], [], []

    def add_view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob); blob.extend(data)
        bv = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
        if target:
            bv['target'] = target
        bviews.append(bv); return len(bviews) - 1

    for name, p, n, t, ix, mi in parts:
        p = p.astype(np.float32); n = n.astype(np.float32); t = t.astype(np.float32); ix = ix.astype(np.uint32)
        nl = np.linalg.norm(n, axis=1, keepdims=True); n = np.where(nl > 1e-8, n / np.maximum(nl, 1e-8), [0, 1, 0]).astype(np.float32)
        a0 = len(accs)
        accs.append({'bufferView': add_view(p.tobytes(), 34962), 'componentType': 5126, 'count': len(p), 'type': 'VEC3',
                     'min': p.min(0).tolist(), 'max': p.max(0).tolist()})
        accs.append({'bufferView': add_view(n.tobytes(), 34962), 'componentType': 5126, 'count': len(n), 'type': 'VEC3'})
        accs.append({'bufferView': add_view(t.tobytes(), 34962), 'componentType': 5126, 'count': len(t), 'type': 'VEC2'})
        accs.append({'bufferView': add_view(ix.tobytes(), 34963), 'componentType': 5125, 'count': ix.size, 'type': 'SCALAR'})
        meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': a0, 'NORMAL': a0 + 1, 'TEXCOORD_0': a0 + 2},
                                                     'indices': a0 + 3, 'material': int(mi)}]})
        nodes.append({'name': name, 'mesh': len(meshes) - 1})
    images, textures, materials = [], [], []

    def add_img(im, sz, png=False):
        if im.size != (sz, sz):
            im = im.resize((sz, sz), Image.LANCZOS)
        b = io.BytesIO()
        if png:
            im.save(b, 'PNG', optimize=True); mime = 'image/png'
        else:
            im.save(b, 'JPEG', quality=90); mime = 'image/jpeg'
        images.append({'bufferView': add_view(b.getvalue()), 'mimeType': mime})
        textures.append({'sampler': 0, 'source': len(images) - 1}); return len(textures) - 1
    for k, texs in enumerate(mats):
        mat = {'name': texs.get('name', 'GearMetal%d' % k), 'pbrMetallicRoughness': {'metallicFactor': 1.0, 'roughnessFactor': 1.0}}
        if texs.get('base') is not None:
            mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': add_img(texs['base'], size)}
        if texs.get('mr') is not None:
            mat['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': add_img(texs['mr'], sub_size)}
        else:
            f = texs.get('factors', (0.8, 0.5))
            mat['pbrMetallicRoughness'].update(metallicFactor=f[0], roughnessFactor=f[1])
        if texs.get('normal') is not None:
            mat['normalTexture'] = {'index': add_img(texs['normal'], sub_size, png=True), 'scale': 1.0}
        materials.append(mat)
    while len(blob) % 4:
        blob.append(0)
    gj = {'asset': {'version': '2.0', 'generator': gen}, 'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}],
          'nodes': nodes, 'meshes': meshes, 'materials': materials, 'textures': textures,
          'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
          'images': images, 'accessors': accs, 'bufferViews': bviews, 'buffers': [{'byteLength': len(blob)}]}
    if not textures:
        del gj['textures'], gj['images'], gj['samplers']
    js = json.dumps(gj, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    open(fn, 'wb').write(out)
