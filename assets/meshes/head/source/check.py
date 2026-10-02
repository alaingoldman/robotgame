"""Quick iteration: build the pieces, report closure / tris, render the
three comparisons into ../ (head folder)."""
import os
import sys

import model
import render
from meshlib import open_edges

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)

ROLES = {
    "Titan_HeadMain": "main",
    "Titan_HeadTrim": "hi",
    "Titan_HeadCrest": "trim",
    "Titan_HeadVisor": "glow",
    "Titan_HeadRecess": "recess",
    "Titan_Gorget": "main",
    "Titan_GorgetRecess": "recess",
    "Titan_ThroatFold": "main",
}


def main():
    P = model.pieces()
    items = []
    for name, m in P.items():
        print("%-20s tris %5d  open edges %d" % (name, len(m.f), open_edges(m)))
        items.append((m, ROLES[name]))
    res = {}
    for view in ("front", "side", "back"):
        v, _ = render.compare_image(view, items, os.path.join(OUT, "Titan_Head_compare_%s.png" % view))
        res[view] = v
        print("IoU %-5s %.4f" % (view, v))
    return res


if __name__ == "__main__":
    main()
