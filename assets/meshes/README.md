# BRZ-01 Titan curved-armour meshes

These are the Titan's curved surfaces as single meshes with UVs, so the crosshatch can run across them in one
piece. The wedge build draws each surface from hundreds of thin WedgePart triangles, and a Texture can't flow across those.

The geometry is the exact current build. It was extracted in Studio from `TitanBuilder.buildRig`: each pair of
wedges was turned back into its source triangle, and the outer face was kept. Then the vertices were welded, the
shell was given its real thickness (inner surface plus rims), and normals were smoothed with hard edges at
creases over 40 degrees. The meshes were checked in Studio as EditableMesh MeshParts. They sit exactly on the
wedge surfaces (`Titan_StudioCheck_front.png`, `Titan_StudioCheck_side.png`).

## Files

| file | replaces (wedge parts) | bone (weld Part0) | offset in bone frame (studs) | size (studs) | tris | role |
|---|---|---|---|---|---|---|
| Titan_ShoulderPad_R.obj | RightPadArmor/PadShell | Chest | (5.3285, 6.5076, 0.6936) | 4.488 x 6.324 x 4.488 | 228 | main |
| Titan_ShoulderPad_L.obj | LeftPadArmor/PadShell | Chest | (-5.3285, 6.5076, 0.6936) | 4.488 x 6.324 x 4.488 | 228 | main |
| Titan_ChestDome.obj | TorsoArmor/ChestPlate, ChestLower, ChestSide | Hatch | (0, 2.5224, -0.8768) | 6.4954 x 4.9368 x 1.9584 | 204 | main |
| Titan_ChestCrescent.obj | TorsoArmor/ChestCrescent | Hatch | (0, 2.1756, -1.0007) | 6.4464 x 1.8768 x 1.7107 | 80 | hi (brass) |
| Titan_Helmet.obj | HelmetArmor/HelmetShell | Head | (0, 1.4059, 0.0082) | 2.1542 x 1.9145 x 3.4435 | 420 | main |
| Titan_HelmetCap.obj | HelmetArmor/HelmetCap (front + back end caps) | Head | (0, 0.9588, 0.0082) | 2.1542 x 1.02 x 3.3782 | 40 | hi (brass) |

- Units are studs at MechConfig.Scale 1.7, with +Y up and the front facing -Z.
- Every OBJ's vertices are centred on its bounding box, so it doesn't matter whether the importer recentres the
  mesh. Place it at `bone.CFrame * CFrame.new(offset)`. Each file header repeats its offset.
- **The importer turned every mesh 180 degrees about Y** (x -> -x, z -> -z). I checked this vertex by vertex
  against the files via EditableMesh. The size stays the same. `TitanMeshes.ImportRotation` turns each template
  back, so the full placement is `bone.CFrame * CFrame.new(offset) * CFrame.Angles(0, math.pi, 0)`.
- The chest dome is split into two meshes because one MeshPart has only one colour. The plate, lower plate and
  sides use the palette's main colour. The crescent band uses hi (brass). Both share one UV layout, so the
  lattice still lines up across the colour change.
- The dome meshes are welded to the "Hatch" bone, not to Chest. TitanBuilder re-welds the chest front to Hatch,
  which swings open. In the build pose, Hatch sits at Chest + (0, 0.8028, -1.7752).
- The bone positions in model space (build pose, all axis-aligned) are Chest (0, 19.0944, -1.224),
  Hatch (0, 19.8972, -2.9992), and Head (0, 27.2544, -1.224).
- All six meshes add up to 1,200 triangles, so each is far under the 10k limit.

## UVs

- 1 texture repeat = 4 studs. This matches MechPattern's Crosshatch `largeTile`, so the lattice on the meshes is
  the same size as on the flat panels.
- Islands are flattened with LSCM and then ARAP, so they are near-isometric (stretch 0.84 to 1.14, no flipped
  triangles). Each island is rotated and offset onto the Roblox box-mapping frame of its main facing direction:
  for a front face, u = -x and v = -y, the same as a flat part's Front Texture. Neighbouring islands keep the
  same lattice direction and phase.
- Seams fall only at the real hard creases:
  - Pads: the outer corner lines where the front and back panels meet the outer wall. This gives front, back,
    outer arc and inner wall islands.
  - Helmet: the two chamfer-to-flat-top creases. This gives a top strip and two side islands.
  - Chest bulge: a single island. ChestLower is a separate island because it is a separate plate.
- A single island per pad would have needed 0.15x to 1.6x stretch, because the pad is cup-shaped. That would
  warp the lattice badly, so the pad uses four islands instead.
- Previews: `<name>_preview.png` shows the crosshatch on Bronze in the top row, a UV checker in the bottom row
  (red = 4-stud tile edge) and the UV islands. `Titan_AllMeshes_preview.png` shows all of them in place.

## Crosshatch texture: SurfaceAppearance, not TextureID

The flat panels draw the lattice as a Texture tinted with the part colour at Transparency 0.5. That works out to
`colour * (0.5 + 0.5 * lattice)`.

- `Titan_Crosshatch_Overlay.png` (1024 px = one 4-stud tile) is black RGB with alpha = 0.5 * (1 - lattice).
  Overlaid on the part colour, it gives exactly the same result. The lattice was redrawn from Studio
  measurements of `rbxassetid://133133290921309`: 4x4 cells of alternating `\` and `/` bars, grey 185 with a
  169 rim.
- Use it as the **ColorMap of a SurfaceAppearance with AlphaMode = Overlay**. A Studio test confirmed that
  MeshPart.Color then shows through and the lattice darkens it. Recolouring per variant then just means setting
  MeshPart.Color, which TitanBuilder.applySlot already does.
- **Do not use MeshPart.TextureID.** In the Studio test it ignored the alpha: the whole mesh turned
  black or white instead of showing MeshPart.Color.
- SurfaceAppearance.ColorMap can only be set in Studio (PluginSecurity), so it has to live on the templates.
  `TitanMeshes` clones it onto each skin while the mech has a pattern and removes it when the pattern is off.
- `Titan_Crosshatch_Lattice.png` is the plain greyscale lattice, for reference only.

## Import steps (owner)

1. In Studio, open the robotgame place, which is Rojo-synced.
2. Go to **Avatar** tab > **Import 3D**, or **File > Import 3D...**. Select `Titan_ShoulderPad_R.obj` from this
   folder. You can import all six .obj files one after another.
3. In the importer's **File General** settings, check that **Scale Unit = Stud** (or that the preview size
   matches the table above), that **World Forward = Front** and **World Up = Top** (the defaults), and that
   **Import only as a model** is unchecked. Then click **Import**. The mesh is uploaded and a MeshPart is placed
   in Workspace, either on its own or inside a Model.
4. Repeat for all 6 .obj files.
5. In the Explorer, create a **Folder** named `TitanMeshes` under **ReplicatedStorage**, not under Shared,
   because Rojo owns Shared. Move the 6 MeshParts into it. Each must be a MeshPart named exactly
   `Titan_ShoulderPad_R`, `Titan_ShoulderPad_L`, `Titan_ChestDome`, `Titan_ChestCrescent`, `Titan_Helmet` and
   `Titan_HelmetCap`. If the importer wrapped them in Models, take the MeshPart out and rename it.
6. Upload the texture. Go to **View > Asset Manager > Images**, right-click > **Bulk Import** (or use the
   Import button), and select `Titan_Crosshatch_Overlay.png`. Then right-click the image > **Copy Asset ID**.
7. Right-click the `TitanMeshes` folder > **Insert Object > SurfaceAppearance** and name it `Crosshatch`. In
   Properties, set **AlphaMode = Overlay** and **ColorMap = the image id**. That one SurfaceAppearance is shared
   by all six meshes. You can also put a SurfaceAppearance on an individual template to override it.
8. Save the place. Every Titan built from then on uses the meshes. Without the folder, nothing changes.

Each mesh is optional. A missing template means that group keeps its wedges.

**Send back:** "imported into ReplicatedStorage.TitanMeshes" and the crosshatch image id. You don't need the
mesh asset ids. If you'd rather not touch the SurfaceAppearance, send the image id and the lead can set it up
through the bridge.

## Regenerating

`source/` holds the pipeline. Rerun it after the shape modules change:

1. Run `extract.luau` through `python tools/rbx.py luau` and save the result as `raw.json`.
2. Run `python build.py` to write the OBJs and `meta.json`.
3. Run `python render.py` to write the PNGs.

It needs Python 3 with numpy and Pillow. If any offset or size changes, update `TitanMeshes.Meshes` in
`src/shared/TitanMeshes.luau` to match.

## Head and collar (modelled, `head/`)

The head and neck in `head/` are new models, not exports of the wedge build. They were modelled from the owner's
FRONT, SIDE and BACK head views (`head/source/refs/235-237.png`, which are zooms of `refs/full_body_sheet.png`).
Each colour role is its own MeshPart. Every piece is a closed shell with flat, hard-edged facets.

| file | bone | offset in bone frame (studs) | size (studs) | tris | role | replaces |
|---|---|---|---|---|---|---|
| Titan_HeadMain.obj | Head | (0, 1.0037, -0.2596) | 2.5786 x 3.8842 x 3.4628 | 688 | main | set "Head": every part in MechHead/HelmetArmor |
| Titan_HeadTrim.obj | Head | (0, 0.3754, -0.5467) | 2.9539 x 2.8397 x 2.8723 | 324 | hi | (set "Head") |
| Titan_HeadCrest.obj | Head | (0, 2.5051, -1.6565) | 0.6202 x 2.8886 x 0.7834 | 48 | trim | (set "Head") |
| Titan_HeadVisor.obj | Head | (0, 0.9833, -1.3138) | 1.8115 x 0.661 x 0.7181 | 20 | glow | (set "Head") |
| Titan_HeadRecess.obj | Head | (0, 1.3872, -0.083) | 2.5214 x 1.4688 x 3.1469 | 192 | recess | (set "Head") |
| Titan_Gorget.obj | Collar | (0, 0.8609, 0.6528) | 4.4717 x 2.9458 x 4.2432 | 384 | main | set "Collar": every part in MechHead/CollarArmor |
| Titan_GorgetRecess.obj | Collar | (0, 1.2648, 0.6528) | 3.8189 x 3.0192 x 3.5904 | 252 | recess | (set "Collar") |
| Titan_ThroatFold.obj | Chest | (0, 6.3811, -1.7952) | 2.1542 x 1.2403 x 1.1424 | 20 | main | (set "Collar") MechChest/TorsoArmor ThroatPlate (both) + CollarRing (the chest's duplicate brass ring) |

What each piece contains:

- **HeadMain**: the helmet dome, the faceted forehead, the brow, the jaw side plates, the raised band around each
  ear arch, the rim below the back band, and a hidden face core.
- **HeadTrim** (brass): the prow faceplate with its centre crease, ending below the cheek bars in a pointed chin (two angled plates meeting at the crease), the two cheek bars and the ear pods.
- **HeadCrest**: the crest spike and the raised ridge down the forehead, which runs on over the brow and tapers to a point just above the visor's peak.
- **HeadVisor**: the chevron slit, filling the whole opening edge to edge (glow, so it dims with the other lights).
- **HeadRecess**: the visor surround, the ear-arch recesses and the dark band across the back.
- **Gorget**: the collar ring, which is high at the back and low at the front, with a top that slopes inward. It
  also holds the lighter inner ledge around the neck.
- **GorgetRecess**: the dark liner inside the ring and the neck column.
- **ThroatFold**: the angular plate under the chin.

How the sets work:

- A **set** is applied only when **all** of its templates exist. For example, if `Titan_HeadVisor` is missing, the
  whole primitive head stays. While set "Head" is complete, the older `Titan_Helmet` / `Titan_HelmetCap` skins are
  skipped (`supersededBy`). Each set is independent. The throat fold belongs to set "Collar".
- The bones are the same ones the primitive build uses. Head is the Neck motor's Part1, so the head turns with the
  Neck. Collar is the head model's root and stays fixed on the chest. Chest is the torso bone.
- Placement, the import rotation, recolouring by role and the crosshatch SurfaceAppearance work exactly like the
  meshes above.

UVs and normals:

- 1 repeat = 4 studs. UV islands are grown over edges under 30 degrees while each face stays within 33 degrees of
  the island normal. Each island is projected onto its own plane, oriented like the Roblox box mapping of its
  dominant direction.
- Maximum stretch is 1.19, and there are no flips.
- Normals are smooth across edges under 30 degrees and hard at sharper creases.

Owner review changes:

- The helmet is mounted **0.5 cell (0.408 studs) higher** than on the sheet, through the Head-bone offsets
  above (`HEAD_RAISE` in `build.py`). The face is **lengthened** by a pointed chin, which ends 0.35 cell below the
  sheet's chin. Together these keep the whole face clear of the gorget, the throat fold and the chest yoke in
  perspective. The neck column reaches up into the raised helmet.
- The OBJ headers give the helmet pieces' offsets at the sheet height, so pieces whose geometry didn't change stay
  byte-identical. The table above and `TitanMeshes.Meshes` hold the mounted values.

Fit against the references:

- Silhouette IoU against the thresholded drawings: the torso and the shoulder pad are masked out because they are
  other parts. In the side view, the pad hides the lower head.
  - With the helmet at the sheet's height: **front 0.973, side 0.962, back 0.962**.
  - As mounted (raised and lengthened, a deliberate deviation): front 0.904, side 0.793, back 0.851.
- The comparison images are `head/Titan_Head_compare_{front,side,back,all}.png`. Each one shows the reference, the
  render at the same scale (as mounted) and the diff. `head/Titan_Head_preview.png` shows 3/4 views.

**Import (owner):**

1. File > Import 3D. Import each of the 8 `head/*.obj` files, with **Scale Unit = Stud** (the preview size should
   match the table) and World Forward = Front, World Up = Top.
2. Each mesh lands in Asset Manager (and a MeshPart in Workspace). Paste back the list of mesh asset ids. The lead
   puts them into `ReplicatedStorage.TitanMeshes` with the exact names above (InsertService / bridge). The shared
   `Crosshatch` SurfaceAppearance already in that folder covers them.

**Regenerating:**

1. Run `cd head/source && python build.py`. It needs numpy and Pillow, and it writes the OBJs, `meta.json`, the
   comparisons and the preview.
2. The shapes are in `model.py`. Every number has a comment saying which crop pixel it was read from.
   `refs.py` holds the pixel-to-cell mapping and the masks, and `render.py` holds the rasterizer and the IoU.
3. If an offset or size changes, update `TitanMeshes.Meshes`.
