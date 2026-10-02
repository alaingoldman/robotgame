# mech2 arms + hands (white / gold / grey)

These are the mech2 arms and hands, built offline as OBJ meshes with UVs. Each rigid segment gets one mesh per
colour. There is a right arm (`R/`) and a left arm (`L/`, an exact mirror of the right). Nothing was built in
Studio.

- `source/build.py` makes every OBJ plus `meta.json`. Each measurement in it is commented with where it came from.
- `source/render.py` makes the verification renders and the silhouette IoU.
- `source/meshlib.py` is an unchanged copy of `../legs/source/meshlib.py`, so the UVs, normals and OBJ writer
  match the legs.
- To rebuild, run `python build.py` and then `python render.py`. Both need only numpy and Pillow.

## Frame and scale

- Units are studs. 1 grid cell of the sheet = 0.816 studs.
- The origin of each arm is the **SHOULDER ball centre**. +Y is up, **-Z is forward**, +Z is back.
- The R arm's outward side is +X. The L arm's outward side is -X.
- The rest pose is the arm hanging straight down. The sheet draws an A-pose, which is the rest pose plus a
  shoulder roll of about 22 degrees outward and an elbow of about -5 degrees. Those angles are fitted in
  `renders/iou.json`.
- Overall size of one arm is 2.44 (X) x 9.80 (Y) x 2.14 (Z) studs. It runs from the top of the shoulder ball at
  y = +0.65 down to the fingertips at y = -9.15.
- All vertices are in arm space, so the files are **not** recentred. Roblox recentres every mesh on import on its
  bounding box. Place each MeshPart at `armCF * CFrame.new(bbox_centre)`. The `bbox_centre` value is in
  `meta.json` and in each OBJ header.
- The earlier Titan meshes found that the importer turned meshes 180 degrees about Y. If that happens again,
  apply the same `CFrame.Angles(0, math.pi, 0)` fix used there.

## Segments and pivots (R arm; for L, negate x)

| segment | parent | pivot (studs) | joint | colour files |
|---|---|---|---|---|
| Upper | (torso socket) | (0, 0, 0) shoulder | ball | Grey (shoulder ball, core, elbow ball), White (upper block) |
| Lower | Upper | (0, -3.13, 0) elbow | ball; hinge axis +X = flex forward | White (cuff + **forearm guard**), Gold (guard inlay + cuff panel), Grey (forearm, elbow socket, guard brackets), DarkGrey (wrist band) |
| Hand | Lower | (0.30, -6.93, 0) wrist | ball | White (palm + peaked back plate), Grey (wrist neck, knuckle pin, thumb knob), DarkGrey (palm pad) |
| Index/Middle/Ring/Pinky 1-3 | Hand -> 1 -> 2 | knuckles at (0.36, -7.87, z = -0.48/-0.16/0.16/0.48) | hinge, axis (0,0,-1) (L: (0,0,1)); a positive angle curls toward the palm | White per phalanx; Grey = the pin at the next joint (phalanges 1-2) |
| Thumb 1-3 | Hand -> 1 -> 2 | base (0.08, -7.28, -0.46) | hinge, axis (-0.905, 0.426, 0) (L: (-0.905, -0.426, 0)) | same |

- Exact pivots for every phalanx, plus the built-in rest curl `rest_curl_deg`, are in `meta.json`.
- Joint balls and pins sit on the parent segment and are centred on the pivot or axis. Rotating a child never
  opens a gap.
- `R/Mech2Arm_R_HandMerged_{White,Grey,DarkGrey}.obj` is an optional one-piece hand with the fingers in their
  rest curl. It uses the Hand pivot.

## Colours

| role | RGB | hex |
|---|---|---|
| White | 242, 242, 242 | #F2F2F2 |
| Gold | 212, 169, 58 | #D4A93A |
| Grey | 138, 138, 138 | #8A8A8A |
| DarkGrey | 90, 90, 90 | #5A5A5A |

There is no Blue on the arm, because none of the references show blue on it.

## Triangle counts (per arm; L is the same)

- Upper: Grey 1292, White 92.
- Lower: White 1642, Gold 288, Grey 304, DarkGrey 60.
- Hand: White 136, Grey 396, DarkGrey 60.
- Each finger phalanx: White 60-62, pin 76. The thumb is the same.
- One arm totals 5,940 triangles, and both arms total 11,880. The largest single file is 1,642 triangles.
- All shells are closed (0 open edges).
- UVs are 1 repeat = 4 studs, with planar islands on the Roblox box-mapping frame. The maximum stretch is 1.19.

## Import

1. In Studio, use File > Import 3D with **Scale Unit = Stud**.
2. Give each part its colour from the table above.
3. Weld each segment's colour meshes together.
4. Join the segments with Motor6Ds at the pivots: torso to Upper, Upper to Lower, Lower to Hand, Hand to the
   finger segments.

## Reference and verification (`renders/`)

- The primary reference is `source/refs/261.png`, the full-body BACK view. Its grid is 28.45 px per cell, which
  gives 34.87 px per stud. The arm was measured after straightening it about its own axis (see the comments in
  `build.py`). `259.png` (front) and `260.png` (side) only show the arm partly; they were used for the depth and
  for the gold panel on the forearm cuff.
- **Silhouette IoU against the arm regions of 261.png** is **R 0.919** and **L 0.906**. It is measured below the
  pauldron, which hides the shoulder ball. Shoulder position and angles are fitted with the mesh fixed.
  `iou_back_overlay.png` shows green where both match, red for reference only and blue for model only.
  - The left arm is lower because the drawing is not symmetric (its fitted roll is 3 degrees different). The
    mesh is one exact mirror, so the two arms cannot both fit perfectly.
  - The rest of the error is outline-stroke width and the open gaps between the fingers.
- `compare_back.png` shows the reference beside the model in the fitted pose.
- `ortho_R_rest.png` shows the back, front, outer side and inner side views.
- `ortho_both_apose.png` shows the back and front in the A-pose.
- `depth_check.png` shows 3/4 front-left, 3/4 front-right, 3/4 back and top views.
- `hand_closeup.png` shows the hand.

## Assumptions (things a back view cannot show)

- **Depth (Z)**:
  - The upper block is 1.45 deep (from the side view 260, about 1.75 cells).
  - The cuff is 1.56 deep.
  - The forearm is about 1.1 deep.
  - The hand is 1.25 wide in Z, with four fingers at a 0.32 pitch.
- **Forearm guard**:
  - It is a curved, 0.20-thick shell on an arc (radius 1.05 around an axis at x 0.5, z 0.2). It wraps from the
    front-outer side (about -50 degrees) round the outer side to the back (about 80-104 degrees), with a raised
    keel line and bevelled edges.
  - Its back-view outline is measured: tip 0.25 above the elbow, outer edge 1.55, inner edge 0.72, the notch,
    and an angled bottom 3.65-4.4 below the elbow.
  - The hidden front edge and the arc are chosen so the side view spans about 1.9 studs, which is the owner's
    side-crop proportion (width about 0.31 x length).
  - Two grey brackets tie the guard to the forearm.
  - The gold inlay is a sheared band (a parallelogram) on the back-outer face. It runs from near the outer edge
    at the top to the inner edge at the bottom, as drawn in 261.
- The shoulder ball radius is 0.65, because the ball is hidden under the pauldron.
- The gold panel on the front of the cuff comes from the side view 260; its size is a guess.
- The thumb's forward angle and all of the finger curls (except the measured back-view chain) are guesses.
- **Scale conflict:**
  - The owner's arm description said the arm is 6-7 cells tall. Measured on 261's grid, it is 12 cells
    (9.8 studs), nearly as long as a leg.
  - I followed 261, which is on the same grid as the leg sheet.
