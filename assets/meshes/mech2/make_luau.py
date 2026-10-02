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
# the chest cockpit meshes (_import3) are used once their uploads are in asset_ids.json
USE_IMPORT3 = "hatch_white" in ids
# IRON MAN chest doors (_import4): door_R/L + the chevron-only hatch_white; hatch_gold retired
USE_IMPORT4 = "door_R_white" in ids
SKIP = {"hatch_gold"} if USE_IMPORT4 else set()

def obj_path(name):
    # re-exported torso files, newest first: _import3 (chest cockpit / hatch split),
    # _import2 (tasset split), then the original upload. A newer file only counts
    # once asset_ids.json has its new upload (USE_IMPORT3).
    dirs = (["_import4"] if USE_IMPORT4 else []) + (["_import3"] if USE_IMPORT3 else []) + ["_import2", "_import"]
    for d in dirs:
        p = os.path.join(HERE, d, name + ".obj")
        if os.path.exists(p):
            return p
    raise FileNotFoundError(name)


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
    if name in SKIP:
        continue
    centre, size = bbox(name)
    colour = name.split("_")[-1].lower()
    role = ROLE[colour]
    if name.startswith("Head_"):
        bone, pivot = "Head", [0, 0, 0]
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
        if seg == "door":
            side = name.split("_")[1]
            bone = ("Right" if side == "R" else "Left") + "Door"
            pivot = sock["RightDoorHinge" if side == "R" else "LeftDoorHinge"]
        elif seg == "hatch":
            bone, pivot = "Hatch", sock["HatchHinge"]  # chest cockpit hatch (bottom hinge)
        elif seg == "tasset":
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
