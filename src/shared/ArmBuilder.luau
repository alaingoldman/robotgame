--!strict
-- Builds the mech's ARMS (shoulder joint down to the fingertips) as a
-- standalone piece, in the same style and units as BootBuilder / LegBuilder:
-- flat blue-grey plates (#6A7D8E) and darker joints (#4B5964). No outline
-- strips (the sheet's black lines are drawing aids only).
--
-- Units: GRID CELLS (BootBuilder.CELL = 0.48 design units per cell, times
-- `scale`; at MechConfig.Scale 1.7 one cell = 0.816 studs).
--
-- Arm space (cells): origin = the SHOULDER JOINT centre, +Y up (the arm hangs
-- toward -Y), -Z = the mech's forward, +X = OUTWARD for the right arm (the left
-- arm is mirrored: everything built with x -> -x). Side-profile polygons are
-- { z, y } pairs extruded across x; front-view polygons are { x, y } pairs
-- extruded along z.
--
-- MEASURED from the owner's full-body FRONT / SIDE / BACK sheet
-- (refs/full_body_sheet.png, 20 px = 1 cell, ground at y = 847.5 px) and the
-- arm close-ups; h = height above the ground in the assembled mech
-- (arm-space y ~ (h - 30) / cos 15deg):
--   shoulder joint (side view dark disc)   h 30.0, ox 5.8, z -0.65  -> ArmBuilder.Shoulder*
--   arm splay (front view, shoulder->hand)  ~15 deg outward          -> default splay 15
--   elbow disc                              h ~26.3                   y -4.0
--   cuff ring (thick collar band)           h 25.4 .. 22.9 (centre), ~4.5 wide x 4.4 deep
--   lower gauntlet                          h 22.9 .. 19.8, ~3.2 x 3.9 (side)
--   crest on the cuff's outer top edge     tip h ~29.2: pointed shield with edge spikes + disc
--   latch + ring loop (outer side)          h ~22.8
--   bolt pins (2, inner half, front + back) h 22.0 / 20.5
--   hand back plate (side view, 4 ribs)     h 19.9 .. 16.1, ~4.1 deep
--   knuckle rings (4, side view)            h 16.9, d 0.9, 0.95 apart
--   fingertips (curled inward)              h ~14.0 (crotch plate point 15.5)
--   hand width in the front view            ~3.8 (outer slab + splayed thumb: open claw)
--
-- Rig (invisible bone parts, Motor6Ds named like MechBuilder's):
--   <Side>ArmRoot (PrimaryPart, at the shoulder joint; WorldPivot)
--   <Side>UpperArm  <- <Side>Shoulder   (axis: any, rest = splay about Z)
--   <Side>LowerArm  <- <Side>Elbow      (hinge = local X; +angle bends forward)
--   <Side>Hand      <- <Side>Wrist
--   <Side>Finger<i>A/B/C <- <Side>Finger<i>Knuckle / Mid / Tip  (curl = local Z)
--   <Side>ThumbA/B  <- <Side>ThumbBase / ThumbTip
-- Side = "Right" / "Left". The armour of each segment is welded to its bone.

local MechConfig = require(script.Parent.MechConfig)

local ArmBuilder = {}

ArmBuilder.CELL = 0.48
ArmBuilder.DefaultScale = MechConfig.Scale

-- The shoulder joint in leg space (cells: ground = 0, centreline x = 0, the
-- mech faces -Z). ChestBuilder puts its shoulder sockets here, so this is the
-- one source of truth for where the arms hang.
ArmBuilder.ShoulderHeight = 30.0
ArmBuilder.ShoulderOut = 5.8
ArmBuilder.ShoulderZ = -0.65

type Pt = { number }

ArmBuilder.Colors = {
	main = Color3.fromRGB(106, 125, 142), -- #6A7D8E plates
	joint = Color3.fromRGB(75, 89, 100), -- #4B5964 joints / upper arm
	jointFace = Color3.fromRGB(88, 104, 117),
	recess = Color3.fromRGB(58, 69, 79), -- palm
	line = Color3.fromRGB(30, 36, 42), -- #1E242A (unused: no outlines)
}

-- ===== Proportions (cells, arm space) =====================================

local SHOULDER = { r = 1.3, w = 2.3, hubR = 0.75, hubW = 2.5 }

-- upper arm: dark, slim, mostly under the pad; a ladder channel front + back
local UPPER: { Pt } = { { -0.95, -0.4 }, { 0.95, -0.4 }, { 1.0, -0.85 }, { 1.0, -3.95 }, { -1.0, -3.95 }, { -1.0, -0.85 } }
local UPPER_W = 2.3
local UPPER_RUNGS = { { -0.95, -2.0 }, { -2.25, -3.7 } } -- lighter panels in the channel (y ranges)

local ELBOW_Y = -4.0
local ELBOW = { r = 0.95, w = 2.2, hubR = 0.55, hubW = 2.4 }

-- cuff ring: thick collar band at the top of the forearm
local CUFF: { Pt } = { { -1.95, -4.95 }, { 1.65, -4.95 }, { 2.05, -5.35 }, { 2.05, -7.2 }, { 1.8, -7.55 }, { -2.1, -7.55 }, { -2.35, -7.2 }, { -2.35, -5.35 } }
local CUFF_XC = 0.7 -- outer side reaches x 2.8 (review: gauntlet 0.5-0.8 short on the outer side)
local CUFF_W = 4.8
local CUFF_BAND_Y = -6.3 -- dark band round the cuff

-- lower gauntlet
local GAUNT: { Pt } = { { -2.0, -7.35 }, { 1.65, -7.35 }, { 1.8, -7.6 }, { 1.8, -10.1 }, { 1.55, -10.5 }, { -1.8, -10.5 }, { -2.1, -10.1 }, { -2.1, -7.6 } }
local GAUNT_XC = 0.95 -- shifted outward (full-body FRONT sheet: gauntlet reaches ~0.5 further out, wrist ~0.7 less in)
local GAUNT_W = 3.2
local GAUNT_STRIP = { x0 = -1.0, x1 = 0.15, top = -7.7, bottom = -10.2 } -- dark strip (front + back faces)
local PINS = { -8.4, -9.85 } -- bolt pins across the strip (y)
local LATCH = { y = -8.05, h = 0.6, z0 = -1.55, z1 = 0.85 }
local ROD = { z = -0.45, top = -7.3, d = 0.42 } -- short rod on the outer side, latch -> cuff
local DROP: { Pt } = { { -0.85, -8.4 }, { -0.05, -8.4 }, { -0.45, -10.1 } } -- downward spike under the latch (z, y)
local LOOP = { z = 0.35, r = 0.45, tube = 0.2 }

-- crest (replaces the separate fin / leaf / star): on the cuff's outer top
-- edge, tip at h ~29.2 (front view spike), shield with edge spikes and a disc
-- (side view); all of it rests on CrestMount, which is set into the cuff
local CREST = { x = 3.32, y = -3.55, z = -0.45, t = 0.42, discR = 0.62, mountTop = -4.7, mountBottom = -5.5 }
local SHIELD: { Pt } = {
	{ 0, 1.85 }, { 0.58, 1.38 }, { 1.11, 1.39 }, { 0.87, 0.92 }, { 1.45, 0 }, { 0.87, -0.8 }, { 1.09, -1.27 }, { 0.58, -1.2 }, { 0, -2.15 },
	{ -0.58, -1.2 }, { -1.09, -1.27 }, { -0.87, -0.8 }, { -1.45, 0 }, { -0.87, 0.92 }, { -1.11, 1.39 }, { -0.58, 1.38 },
}
local SHIELD_CORE: { Pt } = { { 0, 1.55 }, { 0.75, 0 }, { 0, -1.4 }, { -0.75, 0 } }
local SIDE_BLADES = { { base = { 2.4, -5.15, -1.5 }, tip = { 2.75, -3.7, -2.35 } }, { base = { 2.4, -5.15, 0.6 }, tip = { 2.75, -3.7, 1.45 } } }

local WRIST_Y = -10.7
local WRIST = { w = 2.0, h = 0.5, d = 2.6 }

-- hand (hand-local: HAND_XC / HAND_ZC added)
local HAND_XC = 0.85
local HAND_TILT = math.rad(10) -- hand swings its fingertips in toward the thigh (full-body FRONT sheet)
local HAND_ZC = -0.4
local PALM: { Pt } = { { -1.85, -10.8 }, { 1.55, -10.8 }, { 1.95, -11.3 }, { 1.95, -13.9 }, { 1.6, -14.45 }, { -1.9, -14.45 }, { -2.2, -13.9 }, { -2.2, -11.3 } }
local PALM_X = { -0.8, 0.9 }
local BACK_PLATE: { Pt } = { { -2.0, -10.7 }, { 1.65, -10.7 }, { 2.1, -11.2 }, { 2.1, -14.0 }, { 1.7, -14.6 }, { -2.0, -14.6 }, { -2.35, -14.0 }, { -2.35, -11.2 } }
local BACK_PLATE_X = { 0.85, 1.25 }
local FINGER_Z = { -1.6, -0.65, 0.3, 1.25 }
local RIB = { top = -11.05, bottom = -13.15, w = 0.3, proud = 0.13 }
local KNUCKLE_Y = -13.6
local FINGER_Y = -14.35
local FINGER_X = 0.2
local FINGER_SEG = { 1.1, 0.95, 0.85 } -- proximal, middle, tip
local FINGER_W = 0.82 -- across (z)
local FINGER_T = 1.2 -- thickness (x)
local FINGER_CURL = { math.rad(8), math.rad(20), math.rad(30) } -- open claw
local THUMB = { x = -1.05, y = -11.5, z = -1.75, seg = { 1.5, 1.55 }, w = 1.05, t = 1.0, spread = math.rad(62), curl = math.rad(45) } -- splayed clear of the palm

-- ===== Geometry helpers ===================================================

type Ctx = { u: number, color: { [string]: Color3 } }

local function newPart(class: string, name: string, color: Color3, parent: Instance): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function wedgeTri(parent: Instance, name: string, color: Color3, a: Vector3, b: Vector3, c: Vector3, thick: number)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ab.Magnitude < 1e-4 or ac.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
		return
	end
	local right = ac:Cross(ab)
	if right.Magnitude < 1e-6 then
		return
	end
	right = right.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local w1 = newPart("WedgePart", name, color, parent)
	w1.Size = Vector3.new(thick, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local w2 = newPart("WedgePart", name, color, parent)
	w2.Size = Vector3.new(thick, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function signedArea(poly: { Pt }): number
	local s = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		s += p[1] * q[2] - q[1] * p[2]
	end
	return s / 2
end

local function ccw(poly: { Pt }): { Pt }
	if signedArea(poly) >= 0 then
		return poly
	end
	local r = {}
	for i = #poly, 1, -1 do
		table.insert(r, poly[i])
	end
	return r
end

local function cross2(o: Pt, a: Pt, b: Pt): number
	return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end

local function inTri(p: Pt, a: Pt, b: Pt, c: Pt): boolean
	return cross2(a, b, p) >= -1e-9 and cross2(b, c, p) >= -1e-9 and cross2(c, a, p) >= -1e-9
end

local function triangulate(polyIn: { Pt }): { { Pt } }
	local poly = ccw(polyIn)
	local idx = {}
	for i = 1, #poly do
		idx[i] = i
	end
	local tris = {}
	local guard = 0
	while #idx > 3 and guard < 1000 do
		guard += 1
		local n = #idx
		local clipped = false
		for i = 1, n do
			local ia, ib, ic = idx[(i - 2) % n + 1], idx[i], idx[i % n + 1]
			local a, b, c = poly[ia], poly[ib], poly[ic]
			if cross2(a, b, c) > 1e-9 then
				local ok = true
				for _, j in idx do
					if j ~= ia and j ~= ib and j ~= ic and inTri(poly[j], a, b, c) then
						ok = false
						break
					end
				end
				if ok then
					table.insert(tris, { a, b, c })
					table.remove(idx, i)
					clipped = true
					break
				end
			end
		end
		if not clipped then
			break
		end
	end
	if #idx == 3 then
		table.insert(tris, { poly[idx[1]], poly[idx[2]], poly[idx[3]] })
	end
	return tris
end

-- { z, y } polygon in frame xf, extruded across x in [xc - w/2, xc + w/2].
local function prism(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, xc: number, w: number, color: Color3?)
	local u = ctx.u
	for _, t in triangulate(poly) do
		local a = xf * Vector3.new(xc * u, t[1][2] * u, t[1][1] * u)
		local b = xf * Vector3.new(xc * u, t[2][2] * u, t[2][1] * u)
		local c = xf * Vector3.new(xc * u, t[3][2] * u, t[3][1] * u)
		wedgeTri(parent, name, color or ctx.color.main, a, b, c, w * u)
	end
end

-- Front-view frame: a { x, y } polygon -> (x, y), extruded along Z from z0 to z1.
local FRONT = CFrame.fromMatrix(Vector3.zero, -Vector3.zAxis, Vector3.yAxis)

local function frontPrism(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, z0: number, z1: number, color: Color3?)
	prism(ctx, parent, name, xf * FRONT, poly, -(z0 + z1) / 2, z1 - z0, color)
end

local function mirror(poly: { Pt }, s: number): { Pt }
	local r = {}
	for _, p in poly do
		table.insert(r, { s * p[1], p[2] })
	end
	return r
end

-- Cylinder with its axis along the frame's X (cf), len / d in cells.
local function cylinder(ctx: Ctx, parent: Instance, name: string, cf: CFrame, len: number, d: number, color: Color3): BasePart
	local p = newPart("Part", name, color, parent) :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len * ctx.u, d * ctx.u, d * ctx.u)
	p.CFrame = cf
	return p
end

-- Cylinder between two world points (studs), d in cells.
local function rod(ctx: Ctx, parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3): BasePart
	local p = newPart("Part", name, color, parent) :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new((b - a).Magnitude, d * ctx.u, d * ctx.u)
	p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return p
end

local function box(ctx: Ctx, parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3): BasePart
	local p = newPart("Part", name, color, parent)
	p.Size = size * ctx.u
	p.CFrame = cf
	return p
end

-- Joint disc stack (rim + proud hub) with its axis along cf's X.
local function jointDiscs(ctx: Ctx, parent: Instance, name: string, cf: CFrame, r: number, w: number, hubR: number, hubW: number)
	cylinder(ctx, parent, name .. "Rim", cf, w, r * 2, ctx.color.joint)
	cylinder(ctx, parent, name .. "Hub", cf, hubW, hubR * 2, ctx.color.jointFace)
end

local function bone(name: string, cf: CFrame, u: number, parent: Instance): BasePart
	local b = Instance.new("Part")
	b.Name = name
	b.Size = Vector3.new(0.5, 0.5, 0.5) * u
	b.CFrame = cf
	b.Transparency = 1
	b.CanCollide = false
	b.CanTouch = false
	b.CanQuery = false
	b.Massless = true
	b.Anchored = false
	b.Parent = parent
	return b
end

local function weldAll(folder: Instance, b: BasePart)
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") then
			local w = Instance.new("Weld")
			w.Part0 = b
			w.Part1 = d
			w.C0 = b.CFrame:ToObjectSpace(d.CFrame)
			w.Parent = d
		end
	end
end

local function motor(name: string, p0: BasePart, p1: BasePart)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
	m.C1 = CFrame.identity
	m.Parent = p0
end

-- Four-sided spike: diamond base (centre c, half axes ax / az, studs) to a tip.
local function spike(parent: Instance, name: string, color: Color3, c: Vector3, ax: Vector3, az: Vector3, tip: Vector3, thick: number)
	local pts = { c + ax, c + az, c - ax, c - az }
	for i = 1, 4 do
		wedgeTri(parent, name, color, tip, pts[i], pts[i % 4 + 1], thick)
	end
	wedgeTri(parent, name, color, pts[1], pts[2], pts[3], thick)
	wedgeTri(parent, name, color, pts[1], pts[3], pts[4], thick)
end

-- ===== Build ==============================================================

export type BuildOptions = {
	colors: { [string]: Color3 }?,
	elbowBend: number?, -- degrees, forearm swung forward at rest (default 3)
	splay: number?, -- degrees, whole arm tilted outward at the shoulder (default 15, sheet)
	fingerCurl: number?, -- multiplier on the rest finger curl (default 1)
	thumbSpread: number?, -- degrees the thumb swings in from the palm (default 62)
	loop: boolean?, -- ring loop on the latch (default true)
}

-- One arm. side "L" or "R" (default "R"). Built with the shoulder joint at
-- the origin, hanging down, facing -Z. WorldPivot = the shoulder joint.
function ArmBuilder.build(scale: number?, side: string?, opts: BuildOptions?): Model
	local u = ArmBuilder.CELL * (scale or ArmBuilder.DefaultScale)
	local o = opts or {}
	local colors = table.clone(ArmBuilder.Colors)
	if o.colors then
		for k, v in o.colors do
			colors[k] = v
		end
	end
	local ctx: Ctx = { u = u, color = colors }
	local s = if side == "L" then -1 else 1
	local n = if s > 0 then "Right" else "Left"

	local model = Instance.new("Model")
	model.Name = n .. "Arm"
	model:SetAttribute("Side", if s > 0 then "R" else "L")
	model:SetAttribute("Scale", scale or ArmBuilder.DefaultScale)

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		return f
	end

	-- frames: design coordinates (absolute arm space, cells) -> world, per segment
	local splay = math.rad(o.splay or 15)
	local bend = math.rad(o.elbowBend or 3)
	local upperXf = CFrame.Angles(0, 0, s * splay)
	local function pivotAbout(xf: CFrame, y: number, rot: CFrame): CFrame
		local p = CFrame.new(0, y * u, 0)
		return xf * p * rot * p:Inverse()
	end
	local foreXf = pivotAbout(upperXf, ELBOW_Y, CFrame.Angles(bend, 0, 0))
	local handXf = pivotAbout(foreXf, WRIST_Y, CFrame.Angles(math.rad(-2), 0, -s * HAND_TILT))
	local function at(xf: CFrame, x: number, y: number, z: number): CFrame
		return xf * CFrame.new(s * x * u, y * u, z * u)
	end

	local root = bone(n .. "ArmRoot", CFrame.identity, u, model)
	local upperBone = bone(n .. "UpperArm", upperXf, u, model)
	local foreBone = bone(n .. "LowerArm", foreXf * CFrame.new(0, ELBOW_Y * u, 0), u, model)
	local handBone = bone(n .. "Hand", handXf * CFrame.new(0, WRIST_Y * u, 0), u, model)
	model.PrimaryPart = root

	-- --- shoulder + upper arm ---
	local upper = folder("UpperArmArmor")
	jointDiscs(ctx, upper, "Shoulder", upperXf, SHOULDER.r, SHOULDER.w, SHOULDER.hubR, SHOULDER.hubW)
	prism(ctx, upper, "UpperArm", upperXf, UPPER, 0, UPPER_W, colors.joint)
	for _, r in UPPER_RUNGS do
		-- ladder channel: lighter panels standing a little proud of the front / back faces
		local panel: { Pt } = { { -0.55, r[1] }, { 0.55, r[1] }, { 0.55, r[2] }, { -0.55, r[2] } }
		frontPrism(ctx, upper, "UpperPanel", upperXf, mirror(panel, s), -1.08, -0.95, colors.jointFace)
		frontPrism(ctx, upper, "UpperPanel", upperXf, mirror(panel, s), 0.95, 1.08, colors.jointFace)
	end
	-- elbow: discs across the arm
	jointDiscs(ctx, upper, "Elbow", foreXf * CFrame.new(0, ELBOW_Y * u, 0), ELBOW.r, ELBOW.w, ELBOW.hubR, ELBOW.hubW)
	weldAll(upper, upperBone)

	-- --- forearm: cuff ring, gauntlet, outer column, fin ---
	local fore = folder("ForearmArmor")
	prism(ctx, fore, "Cuff", foreXf, CUFF, s * CUFF_XC, CUFF_W)
	do
		local g: { Pt } = { { -2.42, CUFF_BAND_Y + 0.12 }, { 2.12, CUFF_BAND_Y + 0.12 }, { 2.12, CUFF_BAND_Y - 0.12 }, { -2.42, CUFF_BAND_Y - 0.12 } }
		prism(ctx, fore, "CuffBand", foreXf, g, s * CUFF_XC, CUFF_W + 0.12, colors.jointFace)
	end
	prism(ctx, fore, "Gauntlet", foreXf, GAUNT, s * GAUNT_XC, GAUNT_W)
	local gIn = GAUNT_XC - GAUNT_W / 2 -- inner face x
	local gOut = GAUNT_XC + GAUNT_W / 2 -- outer face x
	for _, f in { -1, 1 } do
		-- dark strip on the inner half of the front / back faces
		local zFace = if f < 0 then -2.1 else 1.8
		local st = GAUNT_STRIP
		local strip: { Pt } = { { st.x0, st.top }, { st.x1, st.top }, { st.x1, st.bottom }, { st.x0, st.bottom } }
		frontPrism(ctx, fore, "GauntletStrip", foreXf, mirror(strip, s), zFace - 0.06, zFace + 0.06, colors.joint)
		-- bolt pins: a rod lying across the strip and sticking out past the
		-- inner face, with a round head at its outer end
		for _, y in PINS do
			local zp = zFace + f * 0.21
			local a = foreXf * Vector3.new(s * (gIn - 0.45) * u, y * u, zp * u)
			local b = foreXf * Vector3.new(s * (st.x1 + 0.1) * u, y * u, zp * u)
			rod(ctx, fore, "BoltPin", a, b, 0.3, colors.joint)
			local head = at(foreXf, st.x1 + 0.15, y, zFace + f * 0.3) * CFrame.Angles(0, math.pi / 2, 0)
			cylinder(ctx, fore, "BoltHead", head, 0.36, 0.72, colors.main)
			if f < 0 then
				-- strap band round the gauntlet at each pin
				local band: { Pt } = { { -2.2, y + 0.3 }, { 1.9, y + 0.3 }, { 1.9, y - 0.3 }, { -2.2, y - 0.3 } }
				prism(ctx, fore, "GauntletBand", foreXf, band, s * GAUNT_XC, GAUNT_W + 0.12, colors.jointFace)
			end
		end
	end
	do
		-- outer column: latch bar with a ring loop, rod up to the fin, drop spike
		local xo = gOut
		local latch: { Pt } = { { LATCH.z0, LATCH.y + LATCH.h / 2 }, { LATCH.z1, LATCH.y + LATCH.h / 2 }, { LATCH.z1, LATCH.y - LATCH.h / 2 }, { LATCH.z0, LATCH.y - LATCH.h / 2 } }
		prism(ctx, fore, "Latch", foreXf, latch, s * (xo + 0.13), 0.32, colors.jointFace)
		for _, z in { LATCH.z0 + 0.3, LATCH.z1 - 0.3 } do
			cylinder(ctx, fore, "LatchRivet", at(foreXf, xo + 0.33, LATCH.y, z), 0.1, 0.3, colors.joint)
		end
		prism(ctx, fore, "DropSpike", foreXf, DROP, s * (xo + 0.1), 0.22, colors.main)
		local centre = Vector3.new(s * (xo + 0.3 + LOOP.r), LATCH.y, LOOP.z)
		local segs = if o.loop == false then 0 else 8 -- the sheet has the ring loop on the LEFT arm only
		for i = 0, segs - 1 do
			local a = (i + 0.5) / segs * math.pi * 2
			local p = centre + Vector3.new(math.cos(a) * LOOP.r, math.sin(a) * LOOP.r, 0)
			box(ctx, fore, "Loop", foreXf * CFrame.new(p * u) * CFrame.Angles(0, 0, a), Vector3.new(LOOP.tube, 2 * math.pi * LOOP.r / segs + 0.04, LOOP.tube), colors.joint)
		end
		-- short rod from the latch up into the cuff (no air gap)
		local rx = gOut + 0.3
		local ra = foreXf * Vector3.new(s * rx * u, (LATCH.y + LATCH.h / 2) * u, ROD.z * u)
		local rb = foreXf * Vector3.new(s * rx * u, ROD.top * u, ROD.z * u)
		rod(ctx, fore, "LatchRod", ra, rb, ROD.d, colors.joint)
	end
	do
		-- crest on the cuff's outer top edge: a mount block set into the cuff,
		-- a pointed shield / diamond with small spikes round its edge, a raised
		-- centre and a round disc (sheet SIDE view; owner's circled emblem)
		local c = CREST
		local mount: { Pt } = { { c.z - 0.95, c.mountTop }, { c.z + 0.85, c.mountTop }, { c.z + 0.85, c.mountBottom }, { c.z - 0.95, c.mountBottom } }
		prism(ctx, fore, "CrestMount", foreXf, mount, s * (c.x - 0.15), 0.8, colors.joint)
		local shield: { Pt } = {}
		for _, p in SHIELD do
			table.insert(shield, { c.z + p[1], c.y + p[2] })
		end
		prism(ctx, fore, "CrestShield", foreXf, shield, s * c.x, c.t, colors.main)
		local core: { Pt } = {}
		for _, p in SHIELD_CORE do
			table.insert(core, { c.z + p[1], c.y + p[2] })
		end
		prism(ctx, fore, "CrestRidge", foreXf, core, s * c.x, c.t + 0.36, colors.main)
		local dcf = at(foreXf, c.x + (c.t + 0.36) / 2 + 0.08, c.y, c.z)
		cylinder(ctx, fore, "CrestDisc", dcf, 0.16, c.discR * 2, colors.jointFace)
		cylinder(ctx, fore, "CrestHub", dcf * CFrame.new(s * 0.05 * u, 0, 0), 0.16, c.discR * 1.1, colors.joint)
		for _, b in SIDE_BLADES do
			local bc = foreXf * Vector3.new(s * b.base[1] * u, b.base[2] * u, b.base[3] * u)
			local bt = foreXf * Vector3.new(s * b.tip[1] * u, b.tip[2] * u, b.tip[3] * u)
			spike(fore, "CrestBlade", colors.main, bc, foreXf:VectorToWorldSpace(Vector3.new(0.3 * u, 0, 0)), foreXf:VectorToWorldSpace(Vector3.new(0, 0, 0.32 * u)), bt, 0.05 * u)
		end
	end
	box(ctx, fore, "Wrist", at(foreXf, GAUNT_XC * 0.6, WRIST_Y + 0.05, -0.2), Vector3.new(WRIST.w, WRIST.h, WRIST.d), colors.joint)
	weldAll(fore, foreBone)

	-- --- hand: palm block, back plate with 4 ribs + 4 knuckle rings ---
	local hxf = handXf * CFrame.new(s * HAND_XC * u, 0, HAND_ZC * u)
	local hand = folder("HandArmor")
	prism(ctx, hand, "Palm", hxf, PALM, s * (PALM_X[1] + PALM_X[2]) / 2, PALM_X[2] - PALM_X[1], colors.main)
	do
		local bx = BACK_PLATE_X
		prism(ctx, hand, "BackPlate", hxf, BACK_PLATE, s * (bx[1] + bx[2]) / 2, bx[2] - bx[1], colors.main)
		local xo = bx[2]
		for _, z in FINGER_Z do
			local rib: { Pt } = { { z - RIB.w, RIB.top - 0.4 }, { z, RIB.top }, { z + RIB.w, RIB.top - 0.4 }, { z + RIB.w, RIB.bottom }, { z - RIB.w, RIB.bottom } }
			prism(ctx, hand, "Rib", hxf, rib, s * (xo + RIB.proud / 2 - 0.02), RIB.proud + 0.04, colors.jointFace)
			local kcf = at(hxf, xo + 0.06, KNUCKLE_Y, z)
			cylinder(ctx, hand, "KnuckleRing", kcf, 0.2, 0.9, colors.main)
			cylinder(ctx, hand, "KnuckleHole", kcf * CFrame.new(s * 0.04 * u, 0, 0), 0.2, 0.52, colors.joint)
		end
		local palmFace: { Pt } = { { -1.6, -11.2 }, { 1.4, -11.2 }, { 1.5, -14.0 }, { -1.7, -14.0 } }
		prism(ctx, hand, "PalmFace", hxf, palmFace, s * (PALM_X[1] - 0.02), 0.06, colors.recess)
		box(ctx, hand, "KnuckleBar", at(hxf, FINGER_X, FINGER_Y + 0.1, (FINGER_Z[1] + FINGER_Z[4]) / 2), Vector3.new(FINGER_T * 0.78, 0.5, FINGER_Z[4] - FINGER_Z[1] + FINGER_W * 0.93), colors.joint)
	end
	weldAll(hand, handBone)

	-- fingers: chunky angular blocks curling toward the palm (rotation about
	-- Z). Each segment is a front-view polygon (x outward, y down the finger)
	-- extruded across the finger's width.
	local curlMul = o.fingerCurl or 1
	local function segShape(t: number, l: number, isTip: boolean): { Pt }
		local h = t / 2
		if isTip then
			return { { -h, -0.05 }, { h, -0.05 }, { h, -l * 0.5 }, { h * 0.2, -l }, { -h * 0.55, -l * 0.95 }, { -h, -l * 0.7 } }
		end
		return { { -h, -0.05 }, { h - 0.15, -0.05 }, { h, -0.25 }, { h, -l + 0.1 }, { h - 0.1, -l + 0.02 }, { -h, -l + 0.02 } }
	end
	local function digit(prefix: string, jointNames: { string }, startCF: CFrame, segLens: { number }, curls: { number }, w: number, t: number)
		local parentBone = handBone
		local cf = startCF
		local letters = { "A", "B", "C" }
		for i, len in segLens do
			cf = cf * CFrame.Angles(0, 0, -s * curls[i] * curlMul)
			local b = bone(prefix .. letters[i], cf, u, model)
			local f = Instance.new("Folder")
			f.Name = prefix .. letters[i] .. "Armor"
			f.Parent = model
			local isTip = i == #segLens
			frontPrism(ctx, f, "Segment", cf, mirror(segShape(t, len, isTip), s), -w / 2, w / 2, colors.main)
			-- raised plate on the outer (back) face of the segment
			local pl: { Pt } = { { -w / 2 + 0.1, -0.2 }, { w / 2 - 0.1, -0.2 }, { w / 2 - 0.1, -len * 0.62 }, { -w / 2 + 0.1, -len * 0.62 } }
			prism(ctx, f, "SegmentPlate", cf, pl, s * (t / 2 + 0.04), 0.12, colors.jointFace)
			-- dark joint block at the knuckle (shows in the gap between segments)
			box(ctx, f, "SegmentJoint", cf * CFrame.new(0, 0.02 * u, 0), Vector3.new(t * 0.7, 0.3, w * 0.8), colors.joint)
			weldAll(f, b)
			motor(jointNames[i], parentBone, b)
			parentBone = b
			cf = cf * CFrame.new(0, -len * u, 0)
		end
	end
	for i, z in FINGER_Z do
		local start = at(hxf, FINGER_X, FINGER_Y, z)
		digit(n .. "Finger" .. i, { n .. "Finger" .. i .. "Knuckle", n .. "Finger" .. i .. "Mid", n .. "Finger" .. i .. "Tip" }, start, FINGER_SEG, FINGER_CURL, FINGER_W, FINGER_T)
	end
	do
		-- thumb: a thick angular block hooking inward from the palm's front
		-- corner, then down, its tip turned back toward the palm
		local start = at(hxf, THUMB.x, THUMB.y, THUMB.z) * CFrame.Angles(math.rad(10), 0, 0)
		local f = Instance.new("Folder")
		f.Name = n .. "ThumbMount"
		f.Parent = model
		box(ctx, f, "ThumbBase", start * CFrame.new(s * 0.35 * u, 0.25 * u, 0), Vector3.new(1.4, 1.1, 1.15), colors.joint)
		weldAll(f, handBone)
		digit(n .. "Thumb", { n .. "ThumbBase", n .. "ThumbTip" }, start, THUMB.seg, { if o.thumbSpread then math.rad(o.thumbSpread) else THUMB.spread, -THUMB.curl }, THUMB.w, THUMB.t)
	end

	motor(n .. "Shoulder", root, upperBone)
	motor(n .. "Elbow", upperBone, foreBone)
	motor(n .. "Wrist", foreBone, handBone)

	model.WorldPivot = root.CFrame
	return model
end

-- Both arms, mirrored, shoulder joints ShoulderOut cells either side of the
-- centreline at ShoulderHeight cells above y = 0 (z = ShoulderZ). WorldPivot =
-- the ground point between them (same convention as BootBuilder.buildPair).
-- optsL (optional) gives the left arm its own pose; otherwise both use opts.
function ArmBuilder.buildPair(scale: number?, opts: BuildOptions?, optsL: BuildOptions?): Model
	local u = ArmBuilder.CELL * (scale or ArmBuilder.DefaultScale)
	local pair = Instance.new("Model")
	pair.Name = "MechArms"
	for _, side in { "R", "L" } do
		local arm = ArmBuilder.build(scale, side, if side == "L" and optsL then optsL else opts)
		local x = (if side == "R" then 1 else -1) * ArmBuilder.ShoulderOut * u
		arm:PivotTo(CFrame.new(x, ArmBuilder.ShoulderHeight * u, ArmBuilder.ShoulderZ * u))
		arm.Parent = pair
	end
	pair.WorldPivot = CFrame.identity
	return pair
end

return ArmBuilder
