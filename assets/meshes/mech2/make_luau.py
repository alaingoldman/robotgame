"""Prints the Mech2Meshes.Meshes table (src/shared/Mech2Meshes.luau) from the
OBJs in _import/ (the exact files uploaded, see asset_ids.json).

Each entry: bone the MeshPart is welded to, the mesh bounding-box centre in
that bone's frame (bone frames are the source folders' own frames: torso
segment pivots, head origin, arm frames incl. their rest roll, leg segment
pivots), size, palette role and asset ids. Run: python make_luau.py"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ids = json.load(open(os.path.join(HERE, "asset_ids.json")))
legs = json.load(open(os.path.join(HERE, "legs", "meta.json")))
torso = json.load(open(os.path.join(HERE, "torso", "meta.json")))
sock = torso["sockets"]

def obj_path(name):
    # _import2 holds the re-exported torso files (tasset split): newer than _import
    p2 = os.path.join(HERE, "_import2", name + ".obj")
    return p2 if os.path.exists(p2) else os.path.join(HERE, "_import", name + ".obj")


def bbox(name):
    vs = [list(map(float, l.split()[1:4])) for l in open(obj_path(name)) if l.startswith("v ")]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return [(lo[i] + hi[i]) / 2 for i in range(3)], [hi[i] - lo[i] for i in range(3)]

ROLE = {"white": "main", "gold": "hi", "blue": "accent", "joint": "joint", "grey": "joint", "darkgrey": "dark", "neck": "joint"}

def sub(a, b):
    return [a[i] - b[i] for i in range(3)]

rows = []
for name in sorted(ids):
    centre, size = bbox(name)
    colour = name.split("_")[-1].lower()
    role = ROLE[colour]
    if name.startswith("Head_"):
        bone, pivot = "Head", [0, 0, 0]
        if name == "Head_Gold":
            bone, pivot = "Canopy", [0, 2.3, 0.15]  # crown hinge (Mech2Builder.CanopyHinge)
    elif name.startswith("Leg_"):
        side, seg = name.split("_")[1], name.split("_")[2]
        piv = legs["legs"]["Leg_" + side]["pivots"][{"Thigh": "Hip", "Shin": "Knee", "Foot": "Ankle"}[seg]]
        n = "Right" if side == "R" else "Left"
        bone, pivot = n + seg, piv
    elif name.startswith("Mech2Arm_"):
        side, seg = name.split("_")[1], name.split("_")[2]
        n = "Right" if side == "R" else "Left"
        sx = 1 if side == "R" else -1
        if seg == "Upper":
            bone, pivot = n + "UpperArm", [0, 0, 0]
        elif seg == "Lower":
            bone, pivot = n + "LowerArm", [0, -3.13, 0]
        else:
            bone, pivot = n + "Hand", [0.30 * sx, -6.93, 0]
    else:
        seg = name.split("_")[0]
        if seg == "tasset":
            side = name.split("_")[1]
            bone = ("Right" if side == "R" else "Left") + "Tasset"
            pivot = sock["RightTasset" if side == "R" else "LeftTasset"]
        elif seg == "pauldron":
            side = name.split("_")[1]
            bone = ("Right" if side == "R" else "Left") + "Pauldron"
            pivot = sock["RightShoulder" if side == "R" else "LeftShoulder"]
        else:
            bone = {"pelvis": "Pelvis", "abdomen": "Abdomen", "chest": "Chest"}[seg]
            pivot = torso["segments"][seg]["pivot"]
    off = sub(centre, pivot)
    rows.append((name, bone, off, size, role, ids[name]["model"], ids[name]["mesh"]))

def v(a):
    return "Vector3.new(%s)" % ", ".join("%.4f" % x for x in a)

for name, bone, off, size, role, model, mesh in rows:
    print('\t%s = { bone = "%s", role = "%s", offset = %s, size = %s, model = %d, mesh = %d },' % (name, bone, role, v(off), v(size), model, mesh))
