"""Close-up of the shoulder pad vs upper arm / torso (part colours) from several angles."""
import sys, numpy as np, trimesh
from PIL import Image
from raster import render, view_matrix
import raster
fn = sys.argv[1]; out = sys.argv[2]
sc = trimesh.load(fn, process=False)
COL = {'Torso': (200, 60, 60), 'ShoulderPad_R': (255, 150, 0), 'UpperArm_R': (60, 130, 230), 'Forearm_R': (60, 200, 200), 'Wing_R': (60, 60, 60), 'Head': (230, 210, 40)}
parts = []
for node in sc.graph.nodes_geometry:
    T, g = sc.graph[node]
    if node in COL:
        m = sc.geometry[g]
        v = np.asarray(m.vertices); f = np.asarray(m.faces)
        keep = (v[f][:, :, 1].min(1) > 12.5) & (v[f][:, :, 0].min(1) > -1.5)
        parts.append((v, f[keep], COL[node]))
def rotY(a):
    c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def rotX(a):
    c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
views = {'front': rotY(np.pi), 'tq_front_R': rotX(np.radians(10)) @ rotY(np.pi + np.radians(40)), 'side_R': rotY(-np.pi / 2),
         'tq_back_R': rotX(np.radians(10)) @ rotY(-np.radians(40)), 'top': rotX(np.radians(90)) @ rotY(np.pi)}
ims = []
orig = raster.view_matrix
for k, R in views.items():
    raster.view_matrix = lambda v, R=R: R
    ims.append(render(parts, k, 500, title=k))
raster.view_matrix = orig
im = Image.new('RGB', (500 * len(ims), 500), 'white')
for i, x in enumerate(ims): im.paste(x, (500 * i, 0))
im.save(out)
