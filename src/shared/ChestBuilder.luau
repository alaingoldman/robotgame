--!strict
-- Builds the mech's CHEST (torso) and both SHOULDER PADS as one separate
-- piece. It sits on the LegBuilder legs (pivot = top of the waist band) and
-- carries the HeadBuilder head (NeckSocket attachment) and the ArmBuilder arms
-- (shoulder socket attachments). MechAssembly puts them together.
--
-- Same method and units as BootBuilder / LegBuilder: every number is in GRID
-- CELLS (BootBuilder.CELL design units per cell, times `scale`; 0.816 studs per
-- cell at MechConfig.Scale 1.7). Coordinates are LEG SPACE: origin on the
-- ground midway between the feet, +Y up, the mech faces -Z. ox = across
-- (+ = the mech's right / +X), h = height above the ground, z = front(-)/back(+).
-- No outline strips: the sheet's black lines are drawing aids only.
--
-- MEASURED from the owner's full-body FRONT / SIDE / BACK sheet
-- (refs/full_body_sheet.png: 20 px = 1 cell, ground at y 847.5 px, front
-- centreline x 279, back centreline x 999, side view z = (x - 660) / 20 with
-- the ankle at z 0 as in BootBuilder):
--   torso shoulder line (top) h 32.5, half-width 3.95; widest 4.2 at h ~28.5
--   head's gorget ring sits IN the torso top: neck base h 31.2 (spike tip
--     37.65 - HeadBuilder's 6.45), head origin z -1.7 (side view)
--   squared plate under the collar ox +-1.3, h 30.5 .. 31.3
--   chest is a forward PROW (side view): top edge z -4.1 at h 30.5, crest
--     z -6.1 at h 28.6 (the front view's upper arc), back to z -4.75 at the
--     lower arc h 26.2 (built 1 cell deeper after the owner's side review), lower plate down to h 24.45 between the discs
--   big discs (ox +-2.6, h 25.05, r 0.85); small oval discs (+-1.85, 23.75)
--   dark flanks behind the big discs out to ox 4.45, h 24.4 .. 26.1
--   abdomen: dark bands h ~22 .. 24.6, half-width ~2
--   back: plate h 25.1 .. 32.6, half-width 4.0 (4.3 low); raised spine panel
--     ox +-1.2 (the "T" seams); exhaust tubes from (1.7, 27.3) out / down /
--     back to (3.2, 25.1), z 1.8 -> 4.0, d 1.3
--   shoulder PAD (front view): inner edge ox 3.78 (h 34.55) .. 4.62 (h 27.5),
--     peak ox 6.78 h 35.25, outer corner 8.95 h 33.55, outermost 9.28 h 31.2,
--     concave lower-outer arc down to the bottom ox 6.45 .. 4.62 at h 27.5
--   pad (side view): dome z -3.4 .. 2.1 (centre -0.65), top h 34.3, legs down
--     to h 27.5 with the middle cut away (horseshoe) showing the shoulder
--     joint; a strap z -1.05 .. 0.15 over the crest to h 35.4, dark below
--     h 32.4; a dark lobe under the arc in the front view
--   shoulder joint: ArmBuilder.ShoulderHeight / ShoulderOut / ShoulderZ
--     (h 30.0, ox 5.8, z -0.65) - the sockets below use those values.
-- INFERRED: depths that only one view shows (side walls, core, yoke).
--
-- Rig: one invisible bone "Chest" (PrimaryPart, = WorldPivot, at the top of
-- the waist band, z = LegBuilder's pelvis z) with all armour welded to it.
-- Attachments on the bone: NeckSocket (head origin), RightShoulderSocket and
-- LeftShoulderSocket (arm roots). To mount on LegBuilder legs:
--   chest:PivotTo(legs.Pelvis.CFrame * ChestBuilder.pelvisOffset(scale))

local ArmBuilder = require(script.Parent.ArmBuilder)
local BootBuilder = require(script.Parent.BootBuilder)

local ChestBuilder = {}

local G = BootBuilder.Geometry

type Pt = { number }
type Ctx = { u: number, color: { [string]: Color3 } }

-- ===== Proportions (grid cells, leg space) ================================

local WAIST_TOP = 23.4 -- LegBuilder WAIST.top
local PELVIS_H = 19.0 -- LegBuilder Pelvis bone height
local PIVOT_Z = -1.5 -- LegBuilder PELVIS_Z

-- where the head's origin (HeadBuilder neck base) goes
ChestBuilder.NeckSocket = Vector3.new(0, 31.2, -1.5) -- full-body SIDE: helmet front ~-3.5

-- abdomen: dark stacked bands from inside the waist band up under the chest
local ABDOMEN = { count = 3, bottom = 22.0, step = 0.85, h = 0.78, halfW = 2.02, grow = 0.08, zFront = -3.05, zBack = 1.45 }

-- torso core (dark, mostly hidden)
local CORE = { halfW = 3.65, bottom = 26.4, top = 31.15, zFront = -3.85, zBack = 2.3 }
local CORE_LOW = { halfW = 3.2, bottom = 24.4, top = 26.5, zFront = -3.7, zBack = 2.25 } -- lower chest tapers into the waist

-- dark flank bulges behind the big discs (front-view polygon, right side)
local FLANK: { Pt } = { { 1.95, 24.3 }, { 3.45, 24.35 }, { 4.0, 24.95 }, { 3.85, 25.6 }, { 3.5, 26.3 }, { 1.95, 26.4 } }
local FLANK_Z = { -3.95, 1.4 }
local DISC_BIG = { ox = 2.6, h = 25.05, r = 0.85, rIn = 0.62, z = -3.7 }
local DISC_SMALL = { ox = 1.85, h = 23.75, r = 0.45, rIn = 0.28, z = -2.85 }

-- chest prow: rows of { ox, h, z } (right half, from the centre out)
-- chest bulge: rows across the front (right half, centre out). Each row is
-- { h at each x }, x stations, centre depth zc and edge depth zEdge; depth
-- follows z = zc + (zEdge - zc) * (x / xmax)^2 so the plate wraps round.
-- Side view (full-body sheet): -4.5 at h 30, -5.2 at 29.5, -5.8 at 28..28.5,
-- -5.2 at 27..27.5, -4.8 at 26.5, -4.0 at 25, -3.8 at 24.5.
type Row = { x: { number }, h: { number }, zc: number, zEdge: number }
local BULGE: { Row } = {
	{ x = { 0, 1.35, 2.4, 3.3, 3.98 }, h = { 30.5, 30.5, 30.15, 29.75, 28.75 }, zc = -4.45, zEdge = -3.75 },
	{ x = { 0, 1.2, 2.4, 3.3, 3.98 }, h = { 29.6, 29.55, 29.35, 28.95, 28.3 }, zc = -5.2, zEdge = -3.95 },
	{ x = { 0, 1.2, 2.4, 3.3, 3.95 }, h = { 28.2, 28.15, 28.0, 27.8, 27.6 }, zc = -5.95, zEdge = -4.1 },
	{ x = { 0, 1.2, 2.4, 3.2, 3.8 }, h = { 27.2, 27.15, 27.0, 26.8, 26.5 }, zc = -5.55, zEdge = -4.1 },
	{ x = { 0, 1.2, 2.2, 2.9, 3.5 }, h = { 26.25, 26.2, 26.1, 26.0, 25.9 }, zc = -4.8, zEdge = -4.0 },
}
local LOWER: { Row } = {
	{ x = { 0, 1.2, 2.45 }, h = { 26.25, 26.2, 26.1 }, zc = -4.8, zEdge = -4.45 },
	{ x = { 0, 1.2, 2.45 }, h = { 24.45, 24.45, 24.5 }, zc = -4.0, zEdge = -3.8 },
}
local PLATE_T = 0.23 -- < 0.2 studs: the panels' edges get no pattern Texture

-- yoke: the upper torso front between the prow and the shoulder line, with a
-- notch the head's gorget sits in (front-view polygon, full width)
local YOKE: { Pt } = {
	{ -1.35, 31.3 }, { 1.35, 31.3 }, { 2.75, 31.65 }, { 3.85, 31.65 }, { 4.0, 29.5 }, { 4.0, 28.75 }, { 3.3, 29.75 }, { 1.35, 30.5 },
	{ -1.35, 30.5 }, { -3.3, 29.75 }, { -4.0, 28.75 }, { -4.0, 29.5 }, { -3.85, 31.65 }, { -2.75, 31.65 },
}
local YOKE_Z = { -4.1, -3.0 }
local SQUARE_PLATE: { Pt } = { { -1.3, 31.24 }, { 1.3, 31.24 }, { 1.3, 30.55 }, { -1.3, 30.55 } }
local SQUARE_PLATE_Z = { -4.3, -3.9 }
-- throat fold (full-body SIDE sheet / owner): two stepped angular plates under
-- the chin, each angled down-forward, jutting in front of the neck line.
-- Side profiles { z, h } extruded across x (half-width).
local THROAT_UPPER = { halfW = 1.0, profile = { { -3.25, 31.95 }, { -4.05, 31.35 }, { -3.6, 31.22 }, { -2.95, 31.85 } } }
local THROAT_LOWER = { halfW = 1.36, profile = { { -3.7, 31.32 }, { -4.55, 30.55 }, { -4.1, 30.4 }, { -3.5, 30.45 } } }
local COLLAR_RING = { rx = 3.5, rz = 2.6, zc = -0.7, t = 0.45, h = 0.65, frontTop = 31.5, sideTop = 32.6, segments = 20 }
-- shoulder blocks either side of the gorget, back block behind it
local SHOULDER_BLOCK = { x0 = 2.75, x1 = 3.72, bottom = 28.9, top = 32.15, zFront = -3.05, zBack = 2.35 }
local BACK_BLOCK = { halfW = 2.8, bottom = 28.9, top = 32.15, zFront = 1.2, zBack = 2.4 }

-- side walls (side-view polygon { z, h }, extruded across x)
local SIDE_WALL: { Pt } = { { -3.05, 32.2 }, { -3.9, 31.6 }, { -4.15, 30.0 }, { -4.2, 27.6 }, { -3.8, 26.5 }, { 2.75, 26.5 }, { 2.95, 28.0 }, { 2.75, 32.0 }, { 2.45, 32.2 } }
local SIDE_WALL_X = { 3.76, 4.02 } -- torso +-4.0 at h 27 .. 28 (full-body sheet)

-- back plate (front-view polygon), raised spine panel, seams as shallow steps
local BACK_PLATE: { Pt } = { { -3.9, 32.15 }, { 3.9, 32.15 }, { 4.02, 28.5 }, { 3.8, 26.0 }, { 1.2, 25.6 }, { 1.2, 25.1 }, { -1.2, 25.1 }, { -1.2, 25.6 }, { -3.8, 26.0 }, { -4.02, 28.5 } }
local BACK_PLATE_Z = { 2.4, 2.7 } -- recessed base: the panels below stand proud of it, leaving grooves (the T seams)
local BACK_PANEL: { Pt } = { { 1.38, 31.72 }, { 3.85, 31.72 }, { 3.95, 28.5 }, { 3.72, 26.1 }, { 1.38, 25.78 } } -- right; mirrored
local BACK_PANEL_Z = { 2.6, 2.98 }
local SPINE: { Pt } = { { -1.18, 32.4 }, { 1.18, 32.4 }, { 1.18, 25.15 }, { -1.18, 25.15 } }
local SPINE_Z = { 2.6, 3.15 }
local BACK_BAND: { Pt } = { { 1.38, 32.1 }, { 3.85, 32.1 }, { 3.85, 31.9 }, { 1.38, 31.9 } } -- band above each side panel (right; mirrored)
local BACK_BAND_Z = { 2.6, 2.95 }
local EXHAUST = {
	from = { ox = 1.7, h = 27.3, z = 2.0 },
	to = { ox = 3.2, h = 25.3, z = 3.45 },
	d = 1.3, rimD = 1.45, rimLen = 0.35, boreD = 0.85,
	-- owner's hand edit in Studio (2026-10-02, saved here): the tubes slid DOWN /
	-- OUT along their own axis so their inner ends clear the cockpit; the two
	-- sides were moved 1.53 / 1.71 studs, averaged to one symmetric 1.62 studs
	-- (= 1.987 cells). The rim and bore stay where they were (the rim now reads
	-- as a band round the tube).
	slide = 1.987,
}
ChestBuilder.ExhaustSlide = EXHAUST.slide -- cells; TitanBuilder places the back battery from the un-slid tubes

-- shoulder pads: rows of { h, inner ox, outer ox, half-depth } (bottom up)
local PAD_ROWS: { { number } } = {
	{ 27.5, 4.62, 6.45, 2.75 },
	{ 28.3, 4.51, 6.75, 2.75 },
	{ 29.2, 4.39, 7.4, 2.75 },
	{ 30.2, 4.25, 8.4, 2.75 },
	{ 31.2, 4.11, 9.28, 2.75 },
	{ 31.9, 4.02, 9.0, 2.71 }, -- upper outer edge pulled in ~0.25 (review: pads too wide at the top)
	{ 32.4, 3.95, 8.75, 2.59 },
	{ 32.9, 3.91, 8.72, 2.37 },
	{ 33.3, 3.88, 8.7, 2.1 },
	{ 33.55, 3.86, 8.68, 1.88 },
	{ 33.85, 3.84, 8.3, 1.53 },
	{ 34.1, 3.82, 7.98, 1.11 },
	{ 34.35, 3.8, 7.66, 0.6 },
	{ 34.55, 3.78, 7.4, 0.6 },
	{ 35.25, 6.6, 6.6, 0.6 },
}
local PAD_OPEN_BELOW = 31.2 -- the outer wall is cut away below this (horseshoe)
local PAD_LEG_T = 1.0 -- front / back panel thickness below PAD_OPEN_BELOW
local PAD_T = 0.25
local PAD_LOBE: { Pt } = { { 6.55, 28.3 }, { 6.95, 28.85 }, { 7.6, 28.8 }, { 8.2, 30.3 }, { 8.0, 30.45 }, { 7.0, 29.55 } } -- dark, under the arc
local STRAP = { w = 1.2, dz = 0.2, t = 0.16, darkBelow = 32.4 }
local SOCKET = { r = 1.0, hubR = 0.6 } -- torso-side shoulder socket disc

-- ===== Helpers ============================================================

-- Front-view frame (poly { ox, h }, extruded along world Z; local x = -z).
local FRONT = CFrame.fromMatrix(Vector3.zero, -Vector3.zAxis, Vector3.yAxis)

local function mirror(poly: { Pt }, s: number): { Pt }
	local r = {}
	for _, p in poly do
		table.insert(r, { s * p[1], p[2] })
	end
	return r
end

-- Front-view slab from z0 (front) to z1 (back).
local function slab(ctx: Ctx, parent: Instance, name: string, poly: { Pt }, z0: number, z1: number, color: Color3?)
	G.prism(ctx, parent, name, FRONT, poly, -(z0 + z1) / 2, z1 - z0, color or ctx.color.main)
end

local function box(ctx: Ctx, parent: Instance, name: string, x0: number, x1: number, b: { [string]: number }, color: Color3): BasePart
	local u = ctx.u
	local p = G.newPart("Part", name, color, parent)
	p.Size = Vector3.new(x1 - x0, b.top - b.bottom, b.zBack - b.zFront) * u
	p.CFrame = CFrame.new((x0 + x1) / 2 * u, (b.top + b.bottom) / 2 * u, (b.zFront + b.zBack) / 2 * u)
	return p
end

-- Triangle a b c (cells) as a plate `t` cells thick lying INSIDE the surface:
-- its outer face is the triangle, on the side `out` points to.
local function skinTri(ctx: Ctx, parent: Instance, name: string, color: Color3, a: Vector3, b: Vector3, c: Vector3, t: number, out: Vector3)
	local nrm = (b - a):Cross(c - a)
	if nrm.Magnitude < 1e-6 then
		return
	end
	nrm = nrm.Unit
	if nrm:Dot(out) < 0 then
		nrm = -nrm
	end
	local k = -nrm * t / 2
	local u = ctx.u
	G.wedgeTri(parent, name, color, (a + k) * u, (b + k) * u, (c + k) * u, t * u)
end

local function skinQuad(ctx: Ctx, parent: Instance, name: string, color: Color3, a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: number, out: Vector3)
	skinTri(ctx, parent, name, color, a, b, c, t, out)
	skinTri(ctx, parent, name, color, a, c, d, t, out)
end

-- Full-width row from a right-half row (first point on the centreline).
local function fullRow(half: { { number } }): { Vector3 }
	local r = {}
	for i = #half, 2, -1 do
		local p = half[i]
		table.insert(r, Vector3.new(-p[1], p[2], p[3]))
	end
	for _, p in half do
		table.insert(r, Vector3.new(p[1], p[2], p[3]))
	end
	return r
end

-- Skin between two rows of equal length (front-facing surface).
-- Skin between two rows of equal length (front-facing surface): exact
-- inward-offset triangles (closed seams). Curved, so tagged PatternPlain.
local function band(ctx: Ctx, parent: Instance, name: string, color: Color3, top: { Vector3 }, bot: { Vector3 }, t: number)
	for i = 1, #top - 1 do
		skinQuad(ctx, parent, name, color, top[i], top[i + 1], bot[i + 1], bot[i], t, -Vector3.zAxis)
	end
end
local CURVED = { ChestPlate = true, ChestCrescent = true, ChestLower = true, ChestSide = true }

-- Round disc on a front face: outer ring + proud inner face (axis along Z).
local function frontDisc(ctx: Ctx, parent: Instance, name: string, ox: number, h: number, z: number, r: number, rIn: number)
	local u = ctx.u
	local cf = CFrame.new(ox * u, h * u, z * u) * CFrame.Angles(0, math.pi / 2, 0) -- local +X = forward (-Z)
	G.cylinder(ctx, parent, name .. "Ring", cf * CFrame.new(-0.2 * u, 0, 0), 1.2, r * 2, ctx.color.main)
	G.cylinder(ctx, parent, name .. "Face", cf, 1.0, rIn * 2, ctx.color.joint)
end

-- ===== Shoulder pad =======================================================

local function shoulderPad(ctx: Ctx, parent: Instance, s: number)
	local main = ctx.color.main
	local zc = ArmBuilder.ShoulderZ
	local function P(x: number, h: number, z: number): Vector3
		return Vector3.new(s * x, h, z)
	end
	for i = 1, #PAD_ROWS - 1 do
		local r0, r1 = PAD_ROWS[i], PAD_ROWS[i + 1]
		local h0, h1 = r0[1], r1[1]
		local lower = h0 < PAD_OPEN_BELOW - 1e-3
		local t = if lower then PAD_LEG_T else PAD_T
		-- front and back panels
		for _, f in { -1, 1 } do
			local a, b = P(r0[2], h0, zc + f * r0[4]), P(r0[3], h0, zc + f * r0[4])
			local c, d = P(r1[3], h1, zc + f * r1[4]), P(r1[2], h1, zc + f * r1[4])
			skinQuad(ctx, parent, "PadShell", main, a, b, c, d, t, Vector3.new(0, 0, f))
		end
		-- inner wall (toward the neck)
		do
			local a, b = P(r0[2], h0, zc - r0[4]), P(r0[2], h0, zc + r0[4])
			local c, d = P(r1[2], h1, zc + r1[4]), P(r1[2], h1, zc - r1[4])
			skinQuad(ctx, parent, "PadShell", main, a, b, c, d, PAD_T, Vector3.new(-s, 0.2, 0))
		end
		-- outer wall, only above the horseshoe cut
		if not lower then
			local a, b = P(r0[3], h0, zc - r0[4]), P(r0[3], h0, zc + r0[4])
			local c, d = P(r1[3], h1, zc + r1[4]), P(r1[3], h1, zc - r1[4])
			skinQuad(ctx, parent, "PadShell", main, a, b, c, d, PAD_T, Vector3.new(s, 0.3, 0))
			-- strap over the outer wall: light on the crest, dark low down
			local u = ctx.u
			local pa, pb = Vector3.new(s * r0[3], h0, 0), Vector3.new(s * r1[3], h1, 0)
			local along = pb - pa
			if along.Magnitude > 1e-3 then
				local nrm = Vector3.new(along.Y * s, -along.X * s, 0).Unit -- outward in the x-h plane
				if nrm.X * s < 0 then
					nrm = -nrm
				end
				local mid = (pa + pb) / 2 + nrm * (STRAP.t / 2 - 0.03)
				local dark = (h0 + h1) / 2 < STRAP.darkBelow
				local p = G.newPart("Part", "PadStrap", if dark then ctx.color.joint else main, parent)
				p.Size = Vector3.new(if dark then STRAP.t - 0.05 else STRAP.t, along.Magnitude + 0.12, if dark then STRAP.w - 0.06 else STRAP.w) * u
				p.CFrame = CFrame.fromMatrix(Vector3.new(mid.X, mid.Y, zc + STRAP.dz) * u, nrm, along.Unit)
			end
		end
	end
	-- dark lobe under the arc (front-view plate at the pad's mid depth)
	slab(ctx, parent, "PadLobe", mirror(PAD_LOBE, s), zc - 0.15, zc + 0.15, ctx.color.joint)
end

-- ===== Build ==============================================================

export type BuildOptions = {
	colors: { [string]: Color3 }?,
	pads: boolean?, -- default true
}

-- Pivot of the chest relative to LegBuilder's Pelvis bone.
function ChestBuilder.pelvisOffset(scale: number?): CFrame
	local u = BootBuilder.CELL * (scale or BootBuilder.DefaultScale)
	return CFrame.new(0, (WAIST_TOP - PELVIS_H) * u, 0)
end

-- Torso + both shoulder pads in leg space (as if standing on the legs),
-- facing -Z. WorldPivot = the Chest bone at the top of the waist band.
function ChestBuilder.build(scale: number?, opts: BuildOptions?): Model
	local sc = scale or BootBuilder.DefaultScale
	local u = BootBuilder.CELL * sc
	local o = opts or {}
	local colors = table.clone(BootBuilder.Colors)
	if o.colors then
		for k, v in o.colors do
			colors[k] = v
		end
	end
	local ctx: Ctx = { u = u, color = colors }

	local model = Instance.new("Model")
	model.Name = "MechChest"
	model:SetAttribute("Scale", sc)

	local bone = G.bone("Chest", CFrame.new(0, WAIST_TOP * u, PIVOT_Z * u), u, model)
	model.PrimaryPart = bone
	local function attach(name: string, p: Vector3)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = bone.CFrame:PointToObjectSpace(p * u)
		a.Parent = bone
	end
	local sh = Vector3.new(ArmBuilder.ShoulderOut, ArmBuilder.ShoulderHeight, ArmBuilder.ShoulderZ)
	attach("NeckSocket", ChestBuilder.NeckSocket)
	attach("RightShoulderSocket", sh)
	attach("LeftShoulderSocket", sh * Vector3.new(-1, 1, 1))

	local torso = Instance.new("Folder")
	torso.Name = "TorsoArmor"
	torso.Parent = model

	-- --- core, abdomen, flanks, discs ---
	box(ctx, torso, "TorsoCore", -CORE.halfW, CORE.halfW, CORE, colors.joint)
	box(ctx, torso, "TorsoCoreLow", -CORE_LOW.halfW, CORE_LOW.halfW, CORE_LOW, colors.joint)
	local ab = ABDOMEN
	for i = 0, ab.count - 1 do
		local w = ab.halfW + ab.grow * i
		box(ctx, torso, "AbBand", -w, w, {
			bottom = ab.bottom + ab.step * i,
			top = ab.bottom + ab.step * i + ab.h,
			zFront = ab.zFront - ab.grow * i,
			zBack = ab.zBack + ab.grow * i,
		}, colors.joint)
	end
	for _, s in { 1, -1 } do
		slab(ctx, torso, "Flank", mirror(FLANK, s), FLANK_Z[1], FLANK_Z[2], colors.joint)
		frontDisc(ctx, torso, "DiscBig", s * DISC_BIG.ox, DISC_BIG.h, DISC_BIG.z, DISC_BIG.r, DISC_BIG.rIn)
		frontDisc(ctx, torso, "DiscSmall", s * DISC_SMALL.ox, DISC_SMALL.h, DISC_SMALL.z, DISC_SMALL.r, DISC_SMALL.rIn)
		-- side wall
		local x0, x1 = SIDE_WALL_X[1], SIDE_WALL_X[2]
		G.prism(ctx, torso, "SideWall", CFrame.identity, SIDE_WALL, s * (x0 + x1) / 2, x1 - x0, colors.main)
		-- shoulder socket disc on the torso side (the arm's joint discs sit outboard)
		local sock = CFrame.new(s * (x1 + 0.2) * u, ArmBuilder.ShoulderHeight * u, ArmBuilder.ShoulderZ * u)
		G.cylinder(ctx, torso, "ArmSocket", sock, 0.5, SOCKET.r * 2, colors.joint)
		G.cylinder(ctx, torso, "ArmSocketHub", sock, 0.62, SOCKET.hubR * 2, colors.jointFace)
		-- shoulder block beside the gorget
		local b = SHOULDER_BLOCK
		box(ctx, torso, "ShoulderBlock", if s > 0 then b.x0 else -b.x1, if s > 0 then b.x1 else -b.x0, b, colors.main)
	end
	box(ctx, torso, "BackBlock", -BACK_BLOCK.halfW, BACK_BLOCK.halfW, BACK_BLOCK, colors.main)

	-- --- chest front: yoke, squared plate, prow, lower plate ---
	slab(ctx, torso, "Yoke", YOKE, YOKE_Z[1], YOKE_Z[2])
	slab(ctx, torso, "SquarePlate", SQUARE_PLATE, SQUARE_PLATE_Z[1], SQUARE_PLATE_Z[2])
	for _, t in { THROAT_UPPER, THROAT_LOWER } do
		G.prism(ctx, torso, "ThroatPlate", CFrame.identity, t.profile, 0, t.halfW * 2, colors.main)
	end
	-- collar ring round the head's gorget (full-body FRONT sheet: +-3.5 at h
	-- 32.5, standing above the shoulder line): low at the front, high at the sides / back
	do
		local c = COLLAR_RING
		local n = c.segments
		for i = 0, n - 1 do
			local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2 -- 0 = front
			local am = (a0 + a1) / 2
			local p0 = Vector3.new(c.rx * math.sin(a0), 0, c.zc - c.rz * math.cos(a0))
			local p1 = Vector3.new(c.rx * math.sin(a1), 0, c.zc - c.rz * math.cos(a1))
			local fromFront = math.abs(((am + math.pi) % (2 * math.pi)) - math.pi)
			local top = c.frontTop + (c.sideTop - c.frontTop) * math.min(1, fromFront / (math.pi / 2)) ^ 0.7
			local mid = (p0 + p1) / 2
			local along = p1 - p0
			local outward = Vector3.new(along.Z, 0, -along.X).Unit
			if outward:Dot(Vector3.new(mid.X, 0, mid.Z - c.zc)) < 0 then
				outward = -outward
			end
			local part = G.newPart("Part", "CollarRing", colors.main, torso)
			part.Size = Vector3.new(along.Magnitude + 0.15, c.h, c.t) * u
			local centre = Vector3.new(mid.X, top - c.h / 2, mid.Z) - outward * c.t / 2
			part.CFrame = CFrame.fromMatrix(centre * u, along.Unit, Vector3.yAxis)
		end
	end
	-- resample each row at evenly spaced x stations (fine columns keep the
	-- wrap-round smooth instead of a few big lit facets)
	local STATIONS = 5 -- fewer, larger facets: no fine diagonal striation
	local function rowPts(r: Row): { { number } }
		local pts = {}
		local xm = r.x[#r.x]
		for k = 0, STATIONS - 1 do
			local x = xm * k / (STATIONS - 1)
			local h = r.h[#r.h]
			for i = 1, #r.x - 1 do
				if x <= r.x[i + 1] + 1e-6 then
					local t = (x - r.x[i]) / (r.x[i + 1] - r.x[i])
					h = r.h[i] + (r.h[i + 1] - r.h[i]) * t
					break
				end
			end
			table.insert(pts, { x, h, r.zc + (r.zEdge - r.zc) * (x / xm) ^ 2 })
		end
		return pts
	end
	for i = 1, #BULGE - 1 do
		band(ctx, torso, if i <= 2 then "ChestPlate" else "ChestCrescent", colors.main, fullRow(rowPts(BULGE[i])), fullRow(rowPts(BULGE[i + 1])), PLATE_T)
	end
	band(ctx, torso, "ChestLower", colors.main, fullRow(rowPts(LOWER[1])), fullRow(rowPts(LOWER[2])), PLATE_T)
	-- close the bulge's open sides: fan from its outer edge back to the torso side
	for _, sd in { 1, -1 } do
		local edge = {}
		for _, r in BULGE do
			local xm = r.x[#r.x]
			table.insert(edge, Vector3.new(sd * xm, r.h[#r.h], r.zEdge))
		end
		for k = 1, #edge - 1 do
			local a, b = edge[k], edge[k + 1]
			local a2 = Vector3.new(a.X, a.Y, -3.55)
			local b2 = Vector3.new(b.X, b.Y, -3.55)
			skinQuad(ctx, torso, "ChestSide", colors.main, a, b, b2, a2, PLATE_T, Vector3.new(sd, 0, 0))
		end
	end

	-- --- back ---
	slab(ctx, torso, "BackPlate", BACK_PLATE, BACK_PLATE_Z[1], BACK_PLATE_Z[2])
	slab(ctx, torso, "BackSpine", SPINE, SPINE_Z[1], SPINE_Z[2])
	for _, s in { 1, -1 } do
		slab(ctx, torso, "BackBand", mirror(BACK_BAND, s), BACK_BAND_Z[1], BACK_BAND_Z[2])
		slab(ctx, torso, "BackPanel", mirror(BACK_PANEL, s), BACK_PANEL_Z[1], BACK_PANEL_Z[2])
		local e = EXHAUST
		local a = Vector3.new(s * e.from.ox, e.from.h, e.from.z) * u
		local b = Vector3.new(s * e.to.ox, e.to.h, e.to.z) * u
		local dir = (b - a).Unit
		local slide = dir * e.slide * u
		G.rod(ctx, torso, "Exhaust", a - dir * 0.6 * u + slide, b + slide, e.d, colors.main)
		G.rod(ctx, torso, "ExhaustRim", b - dir * e.rimLen * u, b + dir * 0.06 * u, e.rimD, colors.joint)
		G.rod(ctx, torso, "ExhaustBore", b - dir * 0.2 * u, b + dir * 0.1 * u, e.boreD, colors.line)
	end

	-- --- shoulder pads ---
	if o.pads ~= false then
		for _, s in { 1, -1 } do
			local f = Instance.new("Folder")
			f.Name = if s > 0 then "RightPadArmor" else "LeftPadArmor"
			f.Parent = model
			shoulderPad(ctx, f, s)
			-- curved: the owner wants the pads plain (TitanPattern skips PatternPlain parts)
			for _, d in f:GetDescendants() do
				if d:IsA("BasePart") then
					d:SetAttribute("PatternPlain", true)
				end
			end
			G.weldAll(f, bone)
		end
	end

	for _, d in torso:GetChildren() do
		if d:IsA("BasePart") and CURVED[d.Name] then
			d:SetAttribute("PatternPlain", true) -- curved bulge: plain (TitanPattern)
		end
	end
	G.weldAll(torso, bone)
	G.stripLines(model)
	model.WorldPivot = bone.CFrame
	return model
end

return ChestBuilder
