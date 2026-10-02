# Mech3 (winged navy mech, Meshy multi-view to 3D, split for animation)

This mech is built from the owner's turnaround sheet (`source/sheet.png`): a slim navy/steel-blue mech with a pointed helmet, a chevron chest, blade wings and a backpack.

| file | what |
|---|---|
| `Mech3.glb` | The mech as **19 separately named mesh nodes** that share one material and one baked colour texture (JPEG). About 8.1 MB. |
| `meta.json` | Joint pivots, the suggested hierarchy, wing axes, and per-part triangle counts and bounding boxes. |
| `renders/` | Check renders: textured and part-coloured views, a posed test, joint close-ups and the sheet side by side with the model. |
| `source/` | The sheet, the three cropped views sent to Meshy (`view_front/side/back.png`) and the raw Meshy GLB (`mech_raw.glb`). |
| `tools/` | The scripts that made everything. Run `python build.py` and then `python renders.py` from `tools/`. |

## Pipeline

1. `crop_views.py` cuts FRONT, SIDE and BACK out of the sheet. It masks out the grey grid and guide line, then pads each view to a white 1024 px square. All three use the same scale and the same feet line.
2. Higgsfield `multi_image_to_3d` (Meshy) took the three views with `should_texture`, `symmetry_mode: on`, `target_polycount: 60000` and a texture prompt. This was one job, `ba7610ce-…`, and it produced 61k triangles. The result read well on the first try, so it was not resubmitted.
3. `build.py` reuses the Crimson split:
   - flip 180° about Y so the front faces -Z;
   - scale to 20 studs with the feet at y = 0;
   - subdivide the triangles that straddle a cut twice, then label each triangle by its centroid;
   - add an overlap band at each joint and inset caps on the horizontal cuts.

   It also does three things the Crimson build did not:
   - **Wings**: Meshy made the two blade wings as separate floating shells, so they are picked out as connected components, not by position.
   - **Depth boost**: Z is scaled by **1.12** after the split. At chest height the raw torso was about 15% shallower than the sheet's side view (3.9 vs 4.6 studs). The owner's rule is that models are never flat. After the boost the chest chevron and the helmet beak both project to z ≈ -2.1.
   - **Wing shift**: the wing shells are moved **0.6 studs back** (before the boost), so they rise from behind the shoulders as on the sheet instead of floating beside them.
4. `grid_views.py` and `slices.py` are the measuring tools used to choose the cut planes. The first makes gridded close-up renders and the second plots horizontal cross-sections.

## Conventions

- 1 glTF unit = 1 stud. The mech is 20 studs tall, its feet are at y = 0 and +Y is up.
- The front faces **-Z** and +X is the mech's **right**.
- Vertices are in **model space** and every node has an identity transform, so the parts import already assembled.
- Studio's importer turns the model 180° about Y, so after import the `_L` parts sit at +X.

## Parts (triangles; every part is under 20k)

| part | tris | | part | tris |
|---|---|---|---|---|
| Head (helmet, ear fins, neck block) | 6130 | | Torso (chest, collar, abdomen bands, backpack) | 17440 |
| Pelvis (belt plates and crotch) | 5916 | | Wing_L / _R | 1738 / 1458 |
| ShoulderPad_L / _R | 2454 / 2278 | | UpperArm_L / _R | 4002 / 3619 |
| Forearm_L / _R (with elbow ball) | 4107 / 3969 | | Hand_L / _R | 2754 / 2744 |
| Thigh_L / _R (with hip balls) | 6125 / 5940 | | Shin_L / _R (with knee ball) | 8326 / 8149 |
| Foot_L / _R (with ankle ball) | 4164 / 4034 | | **total** | **95347** |

## Cut planes (`tools/seg.py`, studs, before the Z boost)

- **Neck**: y = 17.45. The helmet is whatever sits inside the collar ring. The neck block below it, down to y = 17.05, also goes with the Head. The collar ring stays on the Torso.
- **Shoulder pad**: the dark armour at y ≥ 16.15 and |x| ≥ 1.85, plus its lower outer tip.
- **Arm**: |x| > 1.9, below the pad.
- **Elbow**: y = 13.85, through the elbow ball.
- **Wrist**: y = 10.85.
- **Waist**: y = 12.4, below the last abdomen band.
- **Hip**: y = 11.6, with |x| > 0.6 (the crotch plate stays on the Pelvis).
- **Knee**: y = 7.2.
- **Ankle**: y = 1.55.
- **Wings**: these are separate shells, so there is no cut.

## Pivots (studs, model space; from `meta.json`)

| joint | R | L |
|---|---|---|
| Neck | (0, 17.45, -0.16) | |
| Waist | (0, 12.4, -0.06) | |
| WingRoot (inner edge, mid-height) | (3.02, 16.80, 1.02) | (-3.02, 16.80, 1.02) |
| ShoulderPad hinge | (1.85, 16.9, 0.09) | (-1.85, 16.9, 0.09) |
| Shoulder | (2.61, 15.6, 0.09) | (-2.62, 15.6, 0.09) |
| Elbow | (3.39, 13.85, 0.41) | (-3.38, 13.85, 0.41) |
| Wrist | (4.38, 10.85, -0.60) | (-4.40, 10.85, -0.59) |
| Hip | (1.29, 11.0, -0.01) | (-1.30, 11.0, -0.01) |
| Knee | (1.52, 7.2, -0.06) | (-1.52, 7.2, -0.12) |
| Ankle | (1.85, 1.55, 0.41) | (-1.85, 1.55, 0.41) |

Suggested hierarchy:

- Pelvis (root) → Torso (Waist) → Head (Neck).
- Torso → Wing (WingRoot).
- Torso → ShoulderPad (hinge, or weld it).
- Torso → UpperArm (Shoulder) → Forearm (Elbow) → Hand (Wrist).
- Pelvis → Thigh (Hip) → Shin (Knee) → Foot (Ankle).

How the joints rotate:

- Rotating about +X by a positive angle swings a limb forward (toward -Z). The knee bends with a negative angle.
- **Wing flap**: rotate about +Z through WingRoot, +30° on R and -30° on L, so the tips swing up and out. **Wing fold**: rotate about +Y.

## Known issues

- Meshy's texture is a fair match for the sheet's palette: navy plates, steel-blue panels and grey ball joints. The glowing blue **eyes and chest slits are only faint**, so add a Neon/emissive detail in-game if you want the glow.
- The wings float free of the body, as they do on the sheet. They are also deeper than the sheet (about 2.7 studs front to back), which makes them read as thick blade slabs. From the side they cover the shoulder pad.
- Some shin and calf stripes on the back are smeared in the bake (see the back view in `renders/Mech3_vs_sheet.png`).
- The arm/torso and pad cuts are vertical and are not capped, as on the Crimson. They are hidden in normal poses. A thin light-blue sliver of the upper-arm cut shows at a deep elbow bend.
- The helmet has a pointed beak, but it is shorter than the sheet's long side-view spike.

## In game: SRF-03 "Seraph" (type id `Mech3`)

The owner imported the GLB as asset **110252059423481**. The game code lives in:

- `src/shared/Mech3Meshes.luau`, `Mech3Config.luau`, `Mech3Builder.luau`, `Mech3Pose.luau` and `Mech3Dock.luau`;
- `src/client/Mech3Animator.luau` and `Mech3Pilot.luau`.

It is registered in `MechTypes` and its lineup spot is at (-218, -150), next to the CRM-01, with its charging post behind it on the right.
