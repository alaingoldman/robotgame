"""Writes the head / collar OBJs (studs, bounding-box centred, +Y up, face
-Z), meta.json (bone, offset, size, tris, role), the FRONT / SIDE / BACK
comparison PNGs with silhouette IoU, and a 3/4 preview.

    python build.py
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

import model
import refs
import render
from meshlib import open_edges, write_obj

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)
STUDS = 0.816  # studs per cell at MechConfig.Scale 1.7 (BootBuilder.CELL 0.48 x 1.7)

# bone origin in head space (cells): HeadBuilder Head bone (NECK_JOINT_H 2.2),
# Collar bone = head origin, ChestBuilder Chest bone = leg (0, 23.4, -1.5) =
# head (0, -7.8, 0)
BONES = {"Head": (0, 2.2, 0), "Collar": (0, 0, 0), "Chest": (0, -7.8, 0)}

PIECES = {
    # name: (bone, sub-model, folder, role, replaces)
    "Titan_HeadMain": ("Head", "MechHead", "HelmetArmor", "main"),
    "Titan_HeadTrim": ("Head", "MechHead", "HelmetArmor", "hi"),
    "Titan_HeadCrest": ("Head", "MechHead", "HelmetArmor", "trim"),
    "Titan_HeadVisor": ("Head", "MechHead", "HelmetArmor", "glow"),
    "Titan_HeadRecess": ("Head", "MechHead", "HelmetArmor", "recess"),
    "Titan_Gorget": ("Collar", "MechHead", "CollarArmor", "main"),
    "Titan_GorgetRecess": ("Collar", "MechHead", "CollarArmor", "recess"),
    "Titan_ThroatFold": ("Chest", "MechChest", "TorsoArmor", "main"),
}


def iso_view(yaw_deg, pitch_deg, cx0, cy0, s):
    yaw, pit = math.radians(yaw_deg), math.radians(pitch_deg)

    def fn(x, h, z):
        # turn the model, then look along +Z from the front
        x1 = x * math.cos(yaw) + z * math.sin(yaw)
        z1 = -x * math.sin(yaw) + z * math.cos(yaw)
        h2 = h * math.cos(pit) - z1 * math.sin(pit)
        z2 = h * math.sin(pit) + z1 * math.cos(pit)
        return cx0 - x1 * s, cy0 - h2 * s, z2
    return fn


def main():
    P = model.pieces()
    meta = {}
    items = []
    for name, m in P.items():
        bone, sub, folder, role = PIECES[name]
        V, F = m.arrays()
        lo, hi = V.min(0), V.max(0)
        c = (lo + hi) / 2
        off = (c - np.array(BONES[bone], float)) * STUDS
        size = (hi - lo) * STUDS
        ms = m.transformed(lambda p: (p - c) * STUDS)
        hdr = ("%s - BRZ-01 Titan head/collar mesh (assets/meshes/head/source/build.py)\n"
               "units: studs (Scale 1.7), +Y up, face toward -Z, centred on the bounding box\n"
               "weld to bone '%s' (%s) at bone.CFrame * CFrame.new(%.4f, %.4f, %.4f) * ImportRotation\n"
               "size %.4f x %.4f x %.4f, role %s" % (name, bone, sub, off[0], off[1], off[2], size[0], size[1], size[2], role))
        tris, stretch, islands = write_obj(os.path.join(OUT, name + ".obj"), ms, hdr)
        meta[name] = {"bone": bone, "model": sub, "folder": folder, "role": role,
                      "offset": [round(float(v), 4) for v in off], "size": [round(float(v), 4) for v in size],
                      "tris": tris, "open_edges": open_edges(m), "uv_islands": islands,
                      "max_uv_stretch": round(float(stretch), 3)}
        print("%-20s %-6s %-6s tris %4d  stretch %.3f  islands %3d  open %d  off (%.4f, %.4f, %.4f)  size (%.4f, %.4f, %.4f)" % (
            name, bone, role, tris, stretch, islands, meta[name]["open_edges"], *off, *size))
        items.append((m, role))
    ious = {}
    imgs = []
    for view in ("front", "side", "back"):
        v, im = render.compare_image(view, items, os.path.join(OUT, "Titan_Head_compare_%s.png" % view))
        ious[view] = round(float(v), 4)
        imgs.append(im)
        print("IoU %-5s %.4f" % (view, v))
    # 3/4 previews
    panels = []
    for yaw, pit in ((-35, -22), (40, -22), (150, -22)):
        refs.VIEWS["_iso"] = ("235.png", iso_view(yaw, pit, 200, 250, 46))
        img, _ = render.raster(items, "_iso", (360, 400), ss=3)
        panels.append(Image.fromarray(np.clip(img, 0, 255).astype("uint8")))
    del refs.VIEWS["_iso"]
    pv = Image.new("RGB", (400 * 3 + 20, 386), "white")
    for i, p in enumerate(panels):
        pv.paste(p, (i * 410, 26))
    ImageDraw.Draw(pv).text((4, 6), "BRZ-01 Titan head + collar meshes (main / hi brass / trim crest / glow visor / recess), 3/4 views", fill=(0, 0, 0))
    pv.save(os.path.join(OUT, "Titan_Head_preview.png"))
    # all comparisons in one sheet
    W = max(i.width for i in imgs)
    sheet = Image.new("RGB", (W, sum(i.height for i in imgs) + 20), "white")
    y = 0
    for i in imgs:
        sheet.paste(i, (0, y))
        y += i.height + 10
    sheet.save(os.path.join(OUT, "Titan_Head_compare_all.png"))
    with open(os.path.join(HERE, "meta.json"), "w") as fh:
        json.dump({"pieces": meta, "iou": ious, "studs_per_cell": STUDS}, fh, indent=2)


if __name__ == "__main__":
    main()
