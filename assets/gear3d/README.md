# gear3d: steampunk mech gear, game-ready GLBs

Made from the 80 concept sheets in `../gear_concepts/` (20 tiers × arm / leg / chest+head, plus 10 melee and 10 ranged weapons).

## Files to import

| file | contents |
|---|---|
| `Gear_T01.glb` … `Gear_T20.glb` | One armour set per tier, with 15 mesh nodes (14 if the tier has no `Torso_Lower`). Each file is about 11 MB. |
| `Weapons.glb` | 20 weapon nodes: `W_M01`…`W_M10` (melee) and `W_R01`…`W_R10` (ranged). |
| `meta.json` | Bounding boxes, joint pivots, weapon grip and length. |
| `renders/` | `T##_turnaround.png` per tier, `contact_1-10.png`, `contact_11-20.png` and `Weapons_lineup.png`. |
| `tools/` | The pipeline scripts (see below). |

## Node naming (per tier GLB)

```
Torso_Upper   chest, collar, back plate
Torso_Lower   abdomen / belt (only when the chest piece reaches below the waist cut)
Head          helmet
ArmR_Upper    shoulder pad + upper arm      ArmL_Upper   (mirror)
ArmR_Lower    forearm                       ArmL_Lower
ArmR_Hand     hand                          ArmL_Hand
LegR_Upper    thigh (+ hip plate)           LegL_Upper
LegR_Lower    shin (+ knee guard)           LegL_Lower
LegR_Foot     boot                          LegL_Foot
```

Every node is under 20k triangles; most are about 19.3k.

There is one PBR material per source piece: `T##_Arm`, `T##_Leg` and `T##_Chest`. Each has a base colour texture (JPEG, 1024), a metallicRoughness texture (JPEG 1024, glTF convention: G = roughness, B = metal) and a normal map (PNG 1024). Arm nodes share `T##_Arm`, leg nodes share `T##_Leg`, and Torso and Head share `T##_Chest`.

Weapon materials are `W_xxx_Mat`: base colour at 1024, metal-rough and normal at 512.

## Space

- Units are studs. Y is up, the front is −Z, and **+X is the character's RIGHT**. The feet are at y = 0.
- Each set is built as if worn by an R15 avatar about 5.5 studs tall. The armour is a bit bulkier than the body.
- Leg (hip to sole): 3.0. Arm (top of the pad to the fingertips): 3.2, hanging straight down. Chest+helmet: 3.4 tall, from y = 2.85 to 6.25.
- The pieces are closed shells, so the player's limb hidden inside is fully covered. The game is expected to scale each node to the body part's bounding box with a margin.
- The left side is the right side mirrored in X. Winding is flipped and normals are mirrored, so the mirrored nodes are not inside-out.
- Cuts are horizontal planes at the narrowest section near the elbow, wrist, knee, ankle, neck and waist. Each opening is capped with its real cross-section, using the same approach as mech3 v2's "clean caps", with a dark texel.

## meta.json

```
tiers.T##.nodes.<Node>  = {bbox_min, bbox_max, tris, material}
tiers.T##.pivots        = {neck, waist, shoulder_R, elbow_R, wrist_R, hip_R, knee_R, ankle_R, shoulder_L, ... ankle_L}
weapons.nodes.W_xxx     = {bbox_min, bbox_max, grip:[0,0,0], length, reach_from_grip, type, source}
```

Pivot definitions:

- **shoulder** and **hip**: the top of the Upper node, on the limb axis.
- **elbow**, **wrist**, **knee**, **ankle** and **neck**: the centre of the cut section.
- **waist**: the Torso_Upper/Torso_Lower cut. When a tier has no Torso_Lower, it is the bottom of Torso_Upper.

All values are in model space.

### Roblox import notes (important)

- Roblox **recentres each MeshPart on its own bounding-box centre**. A node's centre in model space is `(bbox_min + bbox_max) / 2`. A joint's offset inside its part is `pivot − centre`.
- The Roblox importer **rotates the model 180° about Y**. After import, negate the X and Z of any offset taken from meta.json. Equivalently, the imported "front" faces +Z in Roblox space until it is rotated back.

## Weapons

- The **grip is at the origin** of every weapon node.
- **Melee:** the blade or head points along +Y and the edge or heavy side faces −Z. Length is 5.0 studs.
- **Ranged:** the barrel points along −Z (forward), up is +Y, and the grip is where the hand holds the handle under the barrel. Lengths are 3–5 studs (pistol 3.0, railgun 5.0).

## How it was made

1. `tools/crop_views.py` cuts each 1344×752 sheet into single 1024² views. Armour gets front, side and back. Weapons get a side view plus a 3/4 view, and only the side view was used.
2. The crops were uploaded to Higgsfield (presigned PUT, then `media_confirm`). Job and media ids are in `work/ledger.json`.
3. Bake-off on the T6 arm: `sam_3_3d` produced blurry, low-poly geometry, while **`tripo_h3_1_multiview_to_3d`** produced crisp geometry with PBR. Tripo multiview was therefore used for all 60 armour pieces, with the front, side and back crops. The weapons used `tripo_h3_1_image_to_3d` on the side view.
4. `tools/build_tier.py <T>` does the following for each tier:
   - Rotates Tripo's front (+X) to −Z.
   - Decimates from about 1.4M to 56k triangles per piece with `dec.py`. It welds by position, so UV seams cannot crack open, and it re-assigns UVs per chart.
   - Scales and places the pieces, cuts and caps them with `cut.py`, mirrors the left side, and writes the GLB with `gio.py`.
   - Renders with `render_tier.py`.
5. `tools/build_ready.py` builds every tier that is ready. `tools/build_weapons.py` builds `Weapons.glb`. `tools/make_meta.py` writes `meta.json`. `tools/contact.py` makes the contact sheets.

The raw Tripo GLBs (about 46 MB each) are not committed. Re-download them with `tools/fetch.py`, which uses the result URLs in `work/ledger.json`.
