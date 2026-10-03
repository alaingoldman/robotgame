"""Merge work/meta_T##.json + work/meta_weapons.json into assets/gear3d/meta.json"""
import json, os, glob
ROOT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d'
meta = {
    'format': 'gear3d v1',
    'units': 'studs',
    'space': 'model space: Y up, front = -Z, +X = character RIGHT. Feet at y=0, worn by an R15 avatar ~5.5 studs tall '
             '(armour pieces are a bit oversized). Arm length 3.2 (pad top -> fingertips), leg 3.0 (hip -> sole), '
             'chest+helmet 3.4 tall (bottom y=2.85).',
    'roblox_import_notes': 'Roblox recentres every MeshPart on its own bbox centre and the importer rotates the model 180 deg '
                           'about Y. Use bbox_min/bbox_max (centre = (min+max)/2) and the pivots below to place parts: '
                           'offset of a joint inside a part = pivot - bbox centre (then apply the 180 deg Y turn, i.e. negate X and Z, '
                           'if your import was rotated).',
    'pivots_doc': {'shoulder': 'top of ArmX_Upper on the arm axis', 'elbow': 'ArmX_Upper / ArmX_Lower cut (section centre)',
                   'wrist': 'ArmX_Lower / ArmX_Hand cut', 'hip': 'top of LegX_Upper on the leg axis', 'knee': 'LegX_Upper / LegX_Lower cut',
                   'ankle': 'LegX_Lower / LegX_Foot cut', 'neck': 'Torso_Upper / Head cut', 'waist': 'Torso_Upper / Torso_Lower cut '
                   '(if a tier has no Torso_Lower: bottom of Torso_Upper)'},
    'tiers': {}, 'weapons': {},
}
for f in sorted(glob.glob(os.path.join(ROOT, 'work', 'meta_T*.json'))):
    m = json.load(open(f))
    meta['tiers'][os.path.basename(f)[5:8]] = m
wf = os.path.join(ROOT, 'work', 'meta_weapons.json')
if os.path.exists(wf):
    meta['weapons'] = {'file': 'Weapons.glb',
                       'doc': 'grip at the origin of each node. Melee: blade/head along +Y, edge/heavy side towards -Z. '
                              'Ranged: barrel along -Z (forward), up +Y. length = extent along the main axis.',
                       'nodes': json.load(open(wf))}
json.dump(meta, open(os.path.join(ROOT, 'meta.json'), 'w'), indent=1)
print('tiers', sorted(meta['tiers']), 'weapons', len(meta['weapons'].get('nodes', {})))
