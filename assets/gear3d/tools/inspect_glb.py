"""Render selected nodes of a built GLB at full resolution. usage: inspect_glb.py <glb> <out.png> <view,view> [node prefix ...]"""
import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from rend import render, strip, load_glb_parts
fn, out, views = sys.argv[1], sys.argv[2], sys.argv[3].split(',')
pref = sys.argv[4:]
P = [(V, F, uv, t) for nm, V, F, uv, t in load_glb_parts(fn) if not pref or any(nm.startswith(x) for x in pref)]
strip([render(P, v, 520, title=v) for v in views], out)
