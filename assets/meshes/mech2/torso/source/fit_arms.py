"""Fit check: torso + the arms helper's arms pinned at the torso shoulder sockets.

  python fit_arms.py  ->  ../renders/fit_with_arms.png, ../renders/fit_with_arms.json

Arms are read from ../../arms/{R,L}/ (Upper + Lower + HandMerged), placed with their origin (shoulder ball
centre) on RightShoulder / LeftShoulder from ../meta.json and rolled outward by the sheet's A-pose angle
(arms meta says ~25 deg; the best silhouette fit on 259/261 is ~17 deg).  Silhouette IoU against 259 / 261 is computed over torso + arms
(only head and legs masked out).
"""
import json
import math
import os

import numpy as np
from PIL import Image

import verify as vf

HERE = os.path.dirname(os.path.abspath(__file__))
ARMS = os.path.normpath(os.path.join(HERE, "..", "..", "arms"))
ROLL = float(os.environ.get("ARM_ROLL", "17"))


def load_arm(side):
    tris, cols = [], []
    for f in sorted(os.listdir(os.path.join(ARMS, side))):
        if not f.endswith(".obj") or not any(k in f for k in ("_Upper_", "_Lower_", "_HandMerged_")):
            continue
        col = {"White": "white", "Gold": "gold", "Blue": "blue", "Grey": "grey", "DarkGrey": "darkgrey"}[
            f[:-4].split("_")[-1]]
        V, F = [], []
        for line in open(os.path.join(ARMS, side, f)):
            if line.startswith("v "):
                V.append([float(t) for t in line.split()[1:4]])
            elif line.startswith("f "):
                F.append([int(t.split("/")[0]) - 1 for t in line.split()[1:4]])
        T = np.array(V)[np.array(F)]
        tris.append(T)
        cols += [col] * len(T)
    return np.concatenate(tris), cols


def main():
    meta = json.load(open(os.path.join(vf.OUT, "meta.json")))
    T, cols = vf.load_objs()
    allT, allC = [T], list(cols)
    for side, key, sgn in (("R", "RightShoulder", 1.0), ("L", "LeftShoulder", -1.0)):
        A, ac = load_arm(side)
        a = math.radians(ROLL * sgn)
        Rz = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])
        P = A.reshape(-1, 3) @ Rz.T + np.array(meta["sockets"][key])
        allT.append((P / vf.S).reshape(-1, 3, 3))
        allC += ac
    T = np.concatenate(allT)
    res = {"sockets_studs": {k: meta["sockets"][k] for k in ("RightShoulder", "LeftShoulder")}, "roll_deg": ROLL}
    panels = []
    for name, ref, cam, cx, dc in (("front", "259.png", (0, 0, -1), 285.5, vf.dontcare_front),
                                   ("back", "261.png", (0, 0, 1), 296.0, vf.dontcare_back)):
        img_r, mr = vf.ref_mask(os.path.join(vf.REFS, ref))
        Hh, Ww = mr.shape
        img, mm = vf.render(T, allC, cam, Ww, Hh, cx, 525.0)
        dcm = dc(Ww, Hh)
        # keep head + legs masked, but un-mask the arms (they are part of this check)
        keep = vf.poly_mask(Ww, Hh, [[(0, 0), (Ww, 0), (Ww, 140), (0, 140)]]) if name == "back" else \
            vf.poly_mask(Ww, Hh, [[(0, 0), (Ww, 0), (Ww, 165), (0, 165)]])
        care = ~(dcm & keep)
        if name == "back":
            care &= ~vf.poly_mask(Ww, Hh, [[(0, 503), (Ww, 503), (Ww, Hh), (0, Hh)]])
        res[name + "_iou_torso_plus_arms"] = vf.iou(mr, mm, care)
        ov = vf.overlay(img_r, mr, mm, care)
        hcut = 560 if name == "back" else Hh
        panels.append(vf.side_by_side(vf.label(img[:hcut], name + " torso+arms"),
                                      vf.label(ov[:hcut], "IoU %.3f" % res[name + "_iou_torso_plus_arms"])))
    w = max(p.shape[1] for p in panels)
    rows = [np.pad(p, ((0, 6), (0, w - p.shape[1]), (0, 0)), constant_values=255) for p in panels]
    Image.fromarray(np.concatenate(rows)).save(os.path.join(vf.REN, "fit_with_arms.png"))
    with open(os.path.join(vf.REN, "fit_with_arms.json"), "w") as fh:
        json.dump(res, fh, indent=2)
    print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
