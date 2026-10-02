# mech2 HEAD (white / gold / blue)

Offline-modelled from the owner's orthographic sheets (front 256.png, side 257.png, back 258.png,
copied to `source/refs/`). Standalone part. Attach it to the torso at its origin.

## Pieces (one mesh per colour, studs)

| file | colour | RGB | tris | shells | size X x Y x Z (studs) |
|---|---|---|---|---|---|
| Head_Gold.obj  | gold helmet: faceted beak crown + V-plan brow/visor band | 212,169,58 (#D4A93A) | 158 | 2 | 2.45 x 2.20 x 2.29 |
| Head_White.obj | skull shell, 2 chin chevron plates, 3 swept wing blades + 1 cheek blade per side | 236,236,236 | 508 | 11 | 3.55 x 3.92 x 3.71 |
| Head_Blue.obj  | upper side fins (between gold and wings), cheek fins behind the cheek blades | 47,111,191 (#2F6FBF) | 156 | 4 | 2.68 x 2.60 x 1.82 |
| Head_Neck.obj  | octagonal grey neck plug | 120,122,128 | 28 | 1 | 1.24 x 1.55 x 1.12 |

Whole head: 3.55 x 3.96 x 4.54 studs. bbox min (-1.78, -0.49, -2.06), max (1.78, 3.47, 2.48).
**No visor mesh:** the art shows no eyes. The face is the gold V brow plate over two white chin chevrons.

All shells are closed (0 open edges, outward winding). Overlapping shells of the same colour are intended.
UVs: planar per facet group, oriented like Roblox box mapping, 1 repeat = 4 studs, max stretch 1.14.

## Pivot / attachment

- Origin (0,0,0) = **neck base**, the attachment point on top of the torso collar. +Y up, **-Z forward** (face), X symmetric.
- The neck plug runs 0.49 studs below the origin into the torso socket (Y -0.49 to 1.06).
- The chin hangs to Y -0.45, in front of the torso collar, as in the side sheet.
- Scale: 1 grid cell = 0.816 studs, the same as the legs. The origin sits 2.75 cells below the grid line that the crown
  peak overlaps by 0.2 cells in all three sheets (see `source/refs.py`).

## Depth (the main goal)

The volume comes from all three sheets: front width x side depth x back width. No piece is an extruded silhouette.
- Brow/visor prow at z = -2.06 studs. The band wraps back to the temples at z = +0.15, so the face projects
  **2.2 studs** in front of the cheek planes. The side sheet's pointed beak profile is followed exactly.
- Crown: a faceted beak. The ridge steps from z -2.0 (prow) to -1.14 (Y 1.9) to -0.23 (peak). There are two facet
  slopes per side, and the back plane is at z -0.20. The skull continues behind it to z +1.52.
- The brow band's edge stands 0.1 to 0.25 studs proud of the crown. It overhangs the upper chin plate by 0.10 studs, and
  the lower chin plate steps back another 0.08 studs.
- Wings: every blade is a separate tapered, diamond-section slab, 0.24 to 0.34 studs thick, offset in X from the next.
  - B1: root z 0.90 to tip z 2.48, swept at 51 degrees, tip 0.96 studs behind the skull back.
  - B2: root z 0.61 to tip z 2.01, 32 degrees, tip 0.49 studs behind the skull back.
  - B3: root z 0.41 to tip z 1.72, 31 degrees, tip 0.20 studs behind the skull back.
  - All roots start behind the face (z > 0.4 studs).
- `depth_check.png` shows a 3/4 front from each side, a 3/4 back, the top view, the raw side and a low 3/4.

## Verification (`python source/build.py`)

Silhouette IoU against the sheets, measured inside a head ROI that excludes the shoulder pads and torso
(`refs.roi`):

| view | IoU raw | IoU vs outline-centred ref (1 px eroded) | colour agreement | gold / white / blue IoU |
|---|---|---|---|---|
| front | 0.922 | 0.927 | 0.842 | 0.93 / 0.73 / 0.51 |
| side  | 0.929 | 0.925 | 0.881 | 0.93 / 0.82 / 0.77 |
| back  | 0.932 | 0.913 | 0.854 | 0.35* / 0.85 / 0.41 |

\*The back view's gold is only the tiny crown cap, about 40 px, so its IoU is noisy.
The blue scores are low because the blue regions are thin slivers of 2 to 6 px.

Images:
- `compare_views.png`: reference, model, overlay and diff for each view (red = missing, blue = extra).
- `ortho_views.png`: model FRONT / SIDE / BACK at 4x sheet scale.
- `depth_check.png`: the depth renders listed above.
- `ref_labels.png`: the reference segmentation used for the IoU (pink = outside the ROI).

## Source

- `source/build.py`: the generator. It scales to studs, checks the shells, writes the OBJs and meta.json, then runs verify.
  Use `--no-verify` to skip that step.
- `source/geom.py`: all geometry, in cells. Each number is commented with the sheet row or column it was measured from.
- `source/refs.py`: grid measurement, reference silhouettes, colour labels and the ROI. `python refs.py` writes ref_labels.png.
- `source/verify.py`: numpy z-buffer orthographic renderer, IoU and the images.
- `source/rowdiff.py`: per-row reference vs model diff, used for tuning.
- `source/meshlib.py`: a copy of the legs helper's toolkit, so the UV and OBJ conventions match.

## Roblox import notes

Use File > Import 3D, set Scale Unit = **Stud**, and import each OBJ as its own MeshPart. Do not move the pivots: all
four share the same origin. Colour each MeshPart with the RGB above. SmoothPlastic or Metal suits the gold.
Place the head so that its origin sits on the torso's neck attachment, with -Z as the facing direction.

## Ambiguities and how they were resolved

- **Image scale:** the screenshots measure 28.5 px per cell horizontally and 29.4 px vertically, so each axis has its own scale.
- **Beak depth:** the side sheet shows the gold brow as a long forward wedge, 2.7 cells from prow to temple, so the brow
  is V-shaped in plan. This is much deeper than the 0.3-0.6 cells suggested in the brief, but it matches the drawing.
- **Blue fin vs blue strip:** the blue strip in the side sheet and the blue fins in the front and back sheets are the same
  part, a wedge fin beside the head (X 1.05 to 1.64 cells).
- **Cheek blue:** the front sheet shows blue on both sides of the white cheek blade, but the side sheet shows only a blue
  sliver. It was modelled as a blue fin behind the cheek blade that is wider in X, so it shows mostly from the front.
- **Lower back panels:** the chamfered lower back panels in the back sheet are modelled as narrowing in X. The side sheet
  shows a vertical back face down to Y 0.57.
- **Torso parts:** the grey and blue at the bottom of the front sheet, and the white block in the side sheet, are torso
  parts and are excluded via the ROI.
- **Blade tip X:** the front and back sheets disagree by about 0.06 cells on blade tip X. A compromise value was used.
