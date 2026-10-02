# mech2 torso

Chest/torso of mech2 (white / gold / blue / grey), modelled offline from the reference sheets
`source/refs/259.png` (front), `260.png` (3/4 side), `261.png` (back). Rebuild with `python source/build.py`;
re-verify with `python source/verify.py`. Needs only numpy and Pillow.

## Frame and units
- Studs. 1 sheet grid cell = 0.816 studs, the same as the other mech2 parts.
- +Y up, **-Z forward**, +X = the robot's right.
- Origin (0,0,0) = centre of the hip-joint line, at the height of the hip-ball centres.
- All OBJs are in **model space**, already in their assembled positions. Pivots and sockets in `meta.json`
  use the same space, and each file's bbox centre is listed there too.

## Segments (one OBJ per colour per segment)
| segment | parent | pivot (studs) | files |
|---|---|---|---|
| pelvis | - (root) | (0, 0, 0) | pelvis_white / blue / grey / darkgrey |
| abdomen | pelvis | Waist (0, 5.263, 0) | abdomen_grey / darkgrey |
| chest | abdomen | Spine (0, 7.303, 0.082) | chest_white / gold / blue / grey / darkgrey (grey includes the shoulder socket cups) |
| pauldron_R | chest | RightShoulder (3.5, 9.2, 0.163) | pauldron_R_white / gold / grey |
| pauldron_L | chest | LeftShoulder (-3.5, 9.2, 0.163) | pauldron_L_white / gold / grey |

Sockets: Neck (0, 10.567, 0.082) is the top of the grey collar ring, where the head's origin goes.
The shoulder sockets are the arm ball centres, which is where the arms' origins go. They were re-measured: only the lower-inner
quarter of the ball shows under the pauldron blade, and fitting a circle to it puts the centre at |X| 3.6-3.7 studs and Y 9.0-9.2 studs.
The arms helper's fit is (3.5, 9.2). A sweep of the socket with the real arms pinned on, over +-0.15 studs in X and +-0.2 in Y,
scores (3.5, 9.2) best, so that is the value used. The pauldrons' shape and position did not change; only their pivot moved.
Grey octagonal cups on the torso sides (|X| 3.2-3.62 cells) take the ball (radius about 0.7 studs), so there is no gap between the ball and the torso. The hips are at
(+-1.9511, 0, 0), which matches the legs' `hip_offsets_from_mech_centre`.

Colours: white #F2F2F2, gold #D4A93A, blue #2F6FBF, grey #8A8A8A, dark grey #5A5A5A.

## Quality checks
- Every file is made of closed shells (0 open edges) and has fewer than 1,000 triangles. The whole torso is 3,364 triangles.
- UVs are planar per facet group in Roblox box-mapping orientation. 1 repeat = 4 studs, and the worst stretch is 1.14.
- Silhouette IoU, with the head, arms and legs masked out: front **0.911**, back **0.924**. The 3/4 side sheet is a perspective-ish 3/4
  view heavily blocked by the near arm. Fitting the camera azimuth gives 60 deg and IoU 0.77, so it was used for depth only.
- Depth (cells): the chest prow is at Z -3.40, the dark core front at -1.10, the blue side blocks at -1.25 and the white back plate at +2.65.
  The tops of the gold fins sweep back to +4.30. **The chest stands 2.30 cells (1.88 studs) proud of the core.** Prow to back plate is 6.05 cells.
  The pauldrons are 3.17 cells deep and reach 5.19 cells past the torso side.
- Torso and arms together (`source/fit_arms.py`): the arms helper's Upper, Lower and HandMerged pieces are pinned at the sockets with a 17 deg
  outward roll, which fits the sheets best (25 deg fits worse). Silhouette IoU with only the head and legs masked out: front 0.900, back 0.889.
  Images: `renders/fit_with_arms.png` and `renders/fit_with_arms_3q.png`.
- Renders: `renders/compare_front.png`, `compare_back.png`, `compare_side.png`, `depth_check.png`, `iou.json`.

## Assumptions
- The front of the pelvis is not shown on any sheet. The front crotch and skirt plates mirror the back ones, but the front skirts
  stop higher (H 1.3 cells instead of 0.4) to leave room for the legs to swing.
- Depth comes from the 3/4 sheet, which cannot be measured exactly. The chest projection was set slightly beyond what the
  sheet suggests (about 1.9 cells) because the owner asked for a chest that clearly pops out.
- The tall gold plates are fins about 1.1 cells thick. They lean out 9 deg and sweep up and back behind the head.
- `source/meshlib.py` is a copy of the legs helper's toolkit, kept so the UV and OBJ conventions match exactly.
