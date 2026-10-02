# Crimson mech (Meshy image-to-3D, split for animation)

| file | what |
|---|---|
| `Crimson_Mech.glb` | The mech as **17 separately named mesh nodes** that share one material and one 2048² baked colour texture. It's about 8 MB. |
| `Crimson_Blade.glb` | The cleaver/blade as one textured mesh (`Crimson_Blade`). It is 10 studs long and about 3.7 MB. |
| `meta.json` | Joint pivots, per-part triangle counts and bounding boxes, and the blade grip info. |
| `renders/` | Check renders: part colour-coding, textured views, a posed test and joint close-ups. |
| `source/` | Concept art (`ref_original.png`), the clean A-pose (`mech_front.png`), the blade image and the raw Meshy GLBs. |
| `tools/` | The scripts that produced everything. Run `python build.py` and then `python renders.py` from `tools/`. |

## Conventions

- 1 glTF unit = 1 stud. The mech is 20 studs tall and its feet are on y = 0.
- +Y is up. The front faces **-Z**. +X is the mech's **right**.
- All part vertices are in **model space**. Parts are not re-centred, so they import already assembled. Each node has an identity transform.

## Parts

| part | tris |
|---|---|
| Head | 4112 |
| Torso (chest + abdomen + shoulder gear sockets) | 15209 |
| Pelvis (waist ring + crotch plate) | 7297 |
| ShoulderPad_L / _R | 3167 / 3022 |
| UpperArm_L / _R | 3285 / 3129 |
| Forearm_L / _R | 3280 / 3234 |
| Hand_L / _R | 2607 / 2626 |
| Thigh_L / _R | 5225 / 4909 |
| Shin_L / _R | 4320 / 4431 |
| Foot_L / _R | 3595 / 3635 |

That is 77k triangles in total. Every part is under Roblox's 20k MeshPart limit.

### How it was split (`tools/seg.py`)

Meshy returns one triangle soup of 41k tris. I flipped it 180° about Y so the front is -Z, then scaled it to 20 studs. Each triangle was assigned to a part by its centroid, using the cut regions below (all in studs):

- **Neck**: y = 17.9 for |x| < 1.75. The head is the inset turret block between the pads, including its back hump.
- **Shoulder pads**: y ≥ 17.45 and |x| ≥ 1.75, excluding the arm.
- **Arms**: |x| > 4.0 below y = 16.1, and |x| > 4.85 for y 16.1–18.25. This keeps the round shoulder-gear discs on the torso as sockets. The arm's dome top runs up under the pad to about y = 18.2.
- **Elbow**: y = 13.85. **Wrist**: y = 9.95. Hands are |x| > 5.3.
- **Waist**: y = 13.9. The pelvis keeps the centre (|x| < 0.95) down to the crotch plate. The thighs start at y = 12.9.
- **Knee**: y = 7.7 (the knee gear stays on the thigh). **Ankle**: y = 1.85.

Triangles that straddle a boundary were subdivided twice before labelling, so the cut edges follow the planes closely. Every triangle that touches a part is also copied into it. This gives each joint a thin overlap band, so bent joints don't open a gap.

The horizontal cuts at the neck, waist, hip, elbow, wrist, knee and ankle are **capped**. Each cap is an inset convex fill that uses a dark gun-metal texel from the texture, so the parts don't look hollow when rotated. The stepped shoulder cut (arm/torso) and the pad underside are not capped. They are hidden in normal poses.

## Pivots (studs, model space; from `meta.json`)

| joint | R | L |
|---|---|---|
| Neck | (0, 17.9, 0.54) | |
| Waist | (0, 13.9, -0.10) | |
| Shoulder (arm, centre of gear disc) | (4.45, 16.8, 0.35) | (-4.45, 16.8, 0.35) |
| Shoulder pad hinge (inner edge) | (2.0, 18.1, 0.62) | (-2.0, 18.1, 0.63) |
| Elbow | (6.07, 13.85, 0.37) | (-6.03, 13.85, 0.34) |
| Wrist | (6.90, 9.95, 0.05) | (-6.89, 9.95, 0.06) |
| Hip | (2.33, 12.2, 0.07) | (-2.31, 12.2, 0.11) |
| Knee | (2.58, 8.0, 0.10) | (-2.52, 8.0, 0.12) |
| Ankle | (3.60, 1.95, 0.31) | (-3.62, 1.95, 0.31) |

Hierarchy suggestion:

- Pelvis (root) → Torso (Waist) → Head (Neck).
- Torso → ShoulderPad (pad hinge, or weld it to the Torso or UpperArm).
- Torso → UpperArm (Shoulder) → Forearm (Elbow) → Hand (Wrist).
- Pelvis → Thigh (Hip) → Shin (Knee) → Foot (Ankle).

Rotation about +X with a positive angle swings a limb forward (toward -Z). The knee bends with a negative angle.

## Blade

The grip centre is at the origin and the blade runs along **+Y**:

- Length: 10 studs.
- Bounding box: x -1.26..0.67, y -1.47..8.53, z ±0.29.
- The pommel sits at y ≈ -1.47.
- The spine (with the notch) is toward +X and the cutting edge is toward -X.

The suggested hand position in mech space is the fist centre at `Hand_R` ≈ (6.56, 8.62, -0.23). To mount the blade, weld it to `Hand_R` with C0 = hand-local fist offset and C1 = identity. Then rotate it about X so the blade points forward or down as the pose needs.

## Importing into Roblox

1. In Studio, go to **File → Import 3D** and choose `Crimson_Mech.glb`. Keep the default "Import as Model". Set the scale unit to studs (scale 1). Leave "Merge Meshes" **off**.
2. You get one Model containing 17 MeshParts named as above, already in place, each with the texture applied. Anchor the Pelvis, unanchor the rest, and add Motor6Ds at the pivots in `meta.json`. The pivots are in model space, so subtract the model's import offset if Studio moved it.
3. Import `Crimson_Blade.glb` the same way to get one MeshPart.

## Known issues

- Meshy's bake is fairly low-poly and faceted, with smeared texture on some side and back faces. The red paint and gun-metal joints read well. The "CRIMSON CORP." logo and the decals did not survive.
- The head is not a separate shape in the generated mesh: it is fused into the collar between the pads. The Head part is that whole centre-top block down to y = 17.9, including the back hump.
- Some torso machinery sits under the upper arms. It becomes visible as a few thin slivers when an arm is raised far out (see `renders/Crimson_posed_test.png`).
- The shoulder-gear discs belong to the Torso, not the arm.
