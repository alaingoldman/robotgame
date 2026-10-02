# mech2 legs (working name)

These are the new mech's two legs as Wavefront OBJ meshes with UVs and normals. They were modelled offline in
Python (numpy and Pillow; Blender is not installed) from the owner's reference sheet. The sheet shows FRONT, SIDE
and BACK views and lives at `source/refs/255.png`, with a side detail in `source/refs/254.png`. Nothing was
built in Studio.

The legs are a standalone part. Each leg attaches at its **hip-joint centre**, which is the origin of every file.

## Frame, scale, placement

- **Units are studs.** One grid cell of the sheet is 0.816 studs, the same convention as the other mech
  (Scale 1.7, cell 0.48). The grid pitch measured from the sheet is 28.44 px horizontally and 29.08 px
  vertically. The screenshot is slightly anisotropic, so each axis uses its own pitch.
- **Each leg's frame** has its origin at its hip-joint centre. +Y is up and -Z is forward, so the front faces
  -Z. +X is the mech's right.
  - `Leg_R_*` is the mech's right leg. Its outer side is +X.
  - `Leg_L_*` is the exact mirror of `Leg_R_*` (x -> -x, winding flipped).
- **Pair spacing** (also in `meta.json`):
  - Hip centres sit at **x = +1.9511 (R)** and **x = -1.9511 (L)** from the mech centre, so the spacing is
    3.9021 studs. This was measured from the front-view hip balls at x 111.5 and 247.5 px, a gap of 4.78 cells.
  - The hip centre is **8.4603 studs above the soles** (10.368 cells). The soles are flat at y = -8.4603 in the
    leg frame.
- **Pivots in the leg frame** (Leg_R; Leg_L has x negated):

| joint | position (studs) | drives segment |
|---|---|---|
| Hip | (0, 0, 0) | Thigh |
| Knee | (0.2856, -4.4064, 0.1632) | Shin |
| Ankle | (0.5059, -7.5480, 0.1632) | Foot |

The legs splay slightly: on the sheet the lower leg's centre sits about 0.6 cells outboard of the hip, and that
is why the knee and ankle have x != 0.

## Files

There is one OBJ per colour, because a MeshPart has one colour. They come in two sets:

1. **Whole leg**: `Leg_<R|L>_<Colour>.obj`. These are for a static leg.
2. **Rigid segments for animation**: `Leg_<R|L>_<Thigh|Shin|Foot>_<Colour>.obj`. Thigh runs hip to knee, Shin
   runs knee to ankle, and Foot runs ankle to toe. Weld each segment's parts to a bone at the segment's pivot.

All files are in the **same leg frame** (hip = origin), so they assemble without any offsets. Each file's header
and `meta.json` record:
- its bounding-box centre and size
- its segment pivot
- `bbox_centre_minus_pivot`, which is the offset to use if the importer recentres the mesh

| file (Leg_R; Leg_L identical counts) | tris | pieces | bbox size (studs) |
|---|---|---|---|
| Leg_R_White.obj | 1152 | thigh plate (2 halves), knee block, shin plate + 2 flanks, achilles spur, toe plate | 2.79 x 8.15 x 4.65 |
| Leg_R_Gold.obj | 1712 | notch collar, outer/inner hip guards, outer/inner lower plates, rear plate, knee-back frame (4), toe tip, heel | 2.83 x 8.51 x 3.67 |
| Leg_R_Blue.obj | 504 | thigh under-suit core, knee-back inset, calf, ankle front | 1.98 x 6.90 x 2.51 |
| Leg_R_Joint.obj | 484 | hip ball, knee axle (hidden), ankle disc, ankle cover | 1.96 x 8.71 x 1.75 |
| Leg_R_Thigh_White.obj | 292 | thigh plate halves, knee block | 2.70 x 4.26 x 2.84 |
| Leg_R_Thigh_Gold.obj | 1500 | collar, guards, lower plates, rear plate, knee-back frame | 2.83 x 4.99 x 3.57 |
| Leg_R_Thigh_Blue.obj | 232 | thigh core, knee-back inset | 1.49 x 4.49 x 1.96 |
| Leg_R_Thigh_Joint.obj | 224 | hip ball (r 0.70) | 1.38 x 1.40 x 1.35 |
| Leg_R_Shin_White.obj | 744 | shin plate, flanks, achilles spur | 2.27 x 3.51 x 2.98 |
| Leg_R_Shin_Blue.obj | 272 | calf, ankle front | 1.66 x 2.49 x 2.24 |
| Leg_R_Shin_Joint.obj | 260 | knee axle, ankle disc, ankle cover | 1.63 x 3.91 x 1.37 |
| Leg_R_Foot_White.obj | 116 | toe plate | 1.66 x 1.32 x 2.68 |
| Leg_R_Foot_Gold.obj | 212 | toe tip, heel | 1.70 x 1.44 x 3.39 |

- There are 26 OBJs: 13 for each leg. No foot piece is blue or grey, so those files don't exist.
- One complete leg is 3,852 triangles. Every file has **0 open edges**: each piece is its own closed,
  outward-wound shell, and an independent re-parse of the OBJs confirmed it.
- **UVs**: 1 repeat = 4 studs. Each facet group gets its own planar projection, oriented like Roblox box
  mapping, so a crosshatch can flow across the surface later. Max stretch is 1.19.
- **Normals**: hard edges at creases over 30 degrees, so the blocks look flat-shaded and the ball and discs
  look round.

### Colours (exact RGB used for the renders; set these as the MeshPart Color)

| role | RGB | hex |
|---|---|---|
| White armour | 236, 236, 232 | #ECECE8 |
| Gold armour | 212, 169, 58 | #D4A93A |
| Blue under-suit / recesses | 47, 111, 191 | #2F6FBF |
| Joint grey | 128, 128, 128 | #808080 |

## Verification

The two legs were rendered orthographically, flat-shaded in the 4 colours, directly into the sheet's pixel
frame. The renders were compared with 255.png.

The reference silhouette comes from flood-filling the background from the image border. The ink outlines stop
the fill; this matters because the white plates (value 233) are almost the same as the paper (228). The
reference colour classes come from hue.

| view | silhouette IoU | colour IoU W / G / B / grey | pixel colour agreement |
|---|---|---|---|
| FRONT | **0.963** | 0.82 / 0.66 / 0.62 / 0.25 | 0.89 |
| SIDE | **0.949** | 0.89 / 0.91 / 0.58 / 0.61 | 0.96 |
| BACK | **0.954** | 0.50 / 0.75 / 0.72 / 0.46 | 0.88 |

The low grey and white scores come from small areas: the hip balls are cut off at the top of the sheet, and the
back view's white is thin fins. The per-colour agreement on shared pixels is the meaningful number.

Images:
- `Legs_compare_front.png`, `Legs_compare_side.png` and `Legs_compare_back.png` each show four panels: the
  reference, its colour classes, the mesh render, and the silhouette diff. `Legs_compare_all.png` stacks all three.
- `Legs_hero.png` shows 3/4 front and 3/4 back views.
- `Legs_segments.png` shows the right leg exploded into thigh, shin and foot, with the pivots marked.

## How the shapes are built (source/)

`python source/build.py` regenerates everything: the OBJs, `meta.json` and the PNGs. The sources are:
- `refs.py`: grid calibration and sheet segmentation.
- `measure.py`: writes the 5x gridded zooms `refs/zoom_*.png` and the silhouette-extents table that every
  coordinate was read from.
- `model.py`: every piece. Each coordinate is commented with the sheet or zoom pixel it came from.
- `blocks.py`: the armour-block builder.
- `render.py`: the rasterizer, IoU and comparison panels.
- `meshlib.py`: welding, orientation, UVs and the OBJ writer. It is a copy of the head helper's library.

Each armour piece is a **visual-hull block**:
- It is defined by its SIDE outline (z, y) and its FRONT outline (x, y).
- At every outline vertex height, its cross-section is the rectangle of the two intervals, and the block is a
  loft of those rectangles. Its front/back and side silhouettes are therefore exactly the drawn outlines.
- The rectangle corners are then chamfered, and some pieces get a shallow centre ridge (the chevron plates and
  the toe). This adds crisp armour facets without moving either silhouette.
- The hip ball is a faceted sphere. The knee and ankle are bevelled discs along X.

## Import later (Studio)

1. Use File > Import 3D with **Scale Unit = Stud**. Import each OBJ (or the set) and set each MeshPart's Color
   from the table above.
2. Studio recentres a mesh on its bounding box. Place each part at
   `legBone.CFrame * CFrame.new(bbox_centre)`, using `bbox_centre` from `meta.json` (leg frame).
3. For segments, weld them to bones at the pivots:
   - Thigh bone at Hip.
   - Shin bone at Knee.
   - Foot bone at Ankle.
   - Within a segment, the part offset from its bone is `bbox_centre_minus_pivot`.
4. Put the leg roots on the pelvis at `hip_offsets_from_mech_centre`: (+/-1.9511, 0, 0) from the mech centre at
   hip height.
5. On the other mech, the importer turned meshes 180 degrees about Y (x -> -x, z -> -z); see
   `../../README.md`. If that happens here too, add `CFrame.Angles(0, math.pi, 0)` to the placement or swap the
   L/R files. Check one part against the hero render.

## Ambiguities in the drawing and how they were resolved

- **The views are not one consistent solid.** The side view's white thigh plate is a tilted square leaning
  forward; the front view shows it as a chevron plate. Each piece is the intersection of the two outlines, so
  both views match. The thigh plate therefore became a chunky forward-leaning wedge.
- **The sheet's pixels are not square** (28.44 vs 29.08 px per cell). Each axis uses its own pitch.
- **The hip balls are cut off at the top of 255.png.** The side ball's centre and radius come from 254.png,
  which has 7 more rows (template-matched: 254(x, y) = 255(x + 560, y - 7)). The rows above the cut are
  excluded from the IoU.
- **There is a small white spike above the side-view thigh** at z -1.9..-0.8 and y > +0.3. It is not in the
  front or back views and looks like a pelvis/skirt piece, so it was left out and masked from the IoU.
- **The gold notch collar:** the front shows gold filling the V notch of the thigh plate, and the side shows a
  gold spike ahead of the plate's top corner. Both are one gold wedge whose lower edges coincide with the notch
  edges.
- **The legs splay:** in both front and back, the lower leg sits about 0.6 cells outboard of the hip. This is
  kept, so the knee and ankle pivots have x offsets.
- **No knee disc is visible** in any view, but the brief lists one. A grey knee axle (r 0.33 studs) sits hidden
  inside the knee, at the knee pivot.
- The grey cover above the ankle disc shows in the side view. From behind it peeks out beside the Achilles plate
  as a thin grey strip, where the sheet shows blue. The side view was favoured.
- **Back-view white fins beside the calf** are read as the shin plate's side flanks, which the front view
  also shows.
- **The back view's white "box" above the heel** is the same piece as the side view's white Achilles spur.
