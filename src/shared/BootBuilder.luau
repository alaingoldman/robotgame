--!strict
-- Builds a pair of mech BOOTS (lower legs + feet) from the owner's reference
-- sheet (SIDE / BACK / FRONT views on a square grid). Standalone piece: it is
-- not wired into any mech yet.
--
-- Every number below is in GRID CELLS, read straight off the sheet (one grid
-- square = one cell). Side-view profiles are { z, h } points: h = height above
-- the ground (sole bottom = 0), z = forward/back with the ANKLE CENTRE at z = 0
-- and the toe toward -Z (the mech's forward, same as MechBuilder). x = across
-- the boot (+X = the boot's right).
--
-- Size: CELL design units per cell, times `scale` (default MechConfig.Scale).
-- 0.48 du/cell puts the knee joint 11.5 cells = 5.5 du above the ground, the
-- same knee height as the HWM-04B (MechBuilder: knee bone at y 5.5); at Scale
-- 1.7 that is 0.816 studs per cell: knee ~9.4 studs up, boot ~11 studs tall,
-- foot ~6.9 studs long, ~3.1 studs wide.
--
-- Sheet measurements (cells):           sheet        built
--   knee joint centre height            11.5         11.5
--   knee disc radius (rim/face/hub)     1.7/1.33/.86 same
--   ankle centre height                 2.76         2.76
--   foot length toe tip -> heel back    8.4          8.4
--   foot width (front / back views)     3.8          3.8
--   heel block w x h x d                2.4x2.5x1.9  same
--   instep chevron top / shoulders      4.67 / 3.4   same
--   shin width low / high (front)       2.3 / 3.6    2.3 / 3.6 (calf)
--   piston: top 8.3, knuckle 5.3, heel post top 3.5
--   stance, boot centre to centre       9.2          9.2
--   knee-in lean (front view)           ~4.5 deg     4.5 deg
--
-- Rig: two invisible bone parts, "Shin" (at the knee joint) and "Foot" (at
-- the ankle), joined by a Motor6D "Ankle". Shin armour is welded to Shin,
-- foot armour to Foot. Model.PrimaryPart = Shin, WorldPivot = the knee joint,
-- so it can later be hung under a thigh. The piston's lower rod is on the
-- foot and its upper rod on the shin (it only stays joined at rest pose).
--
-- Plates are side-profile polygons extruded across the boot (triangulated
-- into WedgeParts), with thin dark strips drawn along their edges on the
-- outer faces so they read like the sheet's flat-shaded line art. The toe
-- cap is a faceted quarter-ellipsoid shell.

local MechConfig = require(script.Parent.MechConfig)

local BootBuilder = {}

BootBuilder.CELL = 0.48 -- design units per grid cell (x scale = studs)
BootBuilder.DefaultScale = MechConfig.Scale

type Pt = { number } -- { z, h } in cells

-- Colours sampled from the sheet.
BootBuilder.Colors = {
	main = Color3.fromRGB(106, 125, 142), -- #6A7D8E plates
	joint = Color3.fromRGB(75, 89, 100), -- #4B5964 knee / ankle discs
	jointFace = Color3.fromRGB(88, 104, 117),
	recess = Color3.fromRGB(80, 95, 108), -- #505F6C arch under the ankle
	rod = Color3.fromRGB(112, 128, 142),
	line = Color3.fromRGB(30, 36, 42), -- outline strips (only built when Outlines = true)
}

-- The sheets' black outlines are drawing aids, not geometry: off by default.
-- When false, `outline` builds nothing and every module's finished model is
-- passed through Geometry.stripLines (removes the remaining "...Line" strips).
BootBuilder.Outlines = false

-- ===== Proportions (grid cells) ==========================================

local KNEE: Pt = { -1.33, 11.52 } -- knee joint centre
local ANKLE: Pt = { 0, 2.76 } -- ankle joint centre
local KNEE_R = { rim = 1.69, face = 1.33, hub = 0.86 }
local ANKLE_R = { ring = 0.82, hub = 0.54 }
local KNEE_W = { rim = 2.4, face = 2.55, hub = 2.7 } -- narrowed to the full-body sheet's knee (~2.6 wide) -- disc spans across the boot
local ANKLE_W = { ring = 2.8, hub = 3.0 } -- narrowed: no flare at the ankle (full-body sheet ~2.6)
local LEAN = math.rad(7) -- shin tips in toward the other boot (front view); 7 deg (was 4.5): full-body sheet knees ~0.4 further in
local STANCE = 9.2 -- boot centre to centre (front / back views)

-- Knee guard: upper front plate under the knee, sloping forward.
local KNEE_GUARD: { Pt } = { { -3.05, 11.00 }, { -4.00, 9.90 }, { -2.10, 7.62 }, { -1.05, 8.33 }, { -1.38, 9.43 }, { -2.67, 10.48 } }
local KNEE_GUARD_W = 2.5
local KNEE_GUARD_RIDGE_W = 1.15 -- raised centre face (front view)
-- Calf housing: the big rear block under the knee.
local CALF: { Pt } = { { -1.38, 9.43 }, { -0.67, 9.71 }, { 0.29, 10.29 }, { 0.71, 11.00 }, { 1.48, 10.29 }, { 1.95, 9.52 }, { 2.05, 8.48 }, { 1.67, 7.52 }, { 1.33, 7.05 }, { 0.57, 6.67 }, { 0.29, 7.62 }, { -0.10, 8.10 }, { -0.67, 8.33 }, { -1.05, 8.33 } }
local CALF_W = 3.4 -- full-body FRONT sheet: calf ~3.3 wide
-- Front shin: long curved plate from the knee guard down to the ankle.
local SHIN: { Pt } = { { -2.10, 7.62 }, { -1.05, 8.33 }, { -0.67, 8.33 }, { -0.10, 8.10 }, { 0.29, 7.62 }, { 0.57, 6.67 }, { 0.05, 6.19 }, { -0.38, 5.48 }, { -0.52, 4.76 }, { -0.38, 3.81 }, { -0.10, 3.10 }, { -0.67, 2.76 }, { -0.95, 3.33 }, { -1.24, 4.05 }, { -1.48, 5.00 }, { -1.71, 6.19 } }
local SHIN_W = 2.3
local SHIN_RIDGE_W = 1.1 -- centre ridge strip down the front (front view)
-- Lower calf plate behind the shin.
local LOWER_CALF: { Pt } = { { 0.57, 6.67 }, { 1.33, 7.05 }, { 1.10, 5.95 }, { 1.10, 5.00 }, { 1.33, 4.05 }, { 0.86, 3.33 }, { 0.29, 2.76 }, { -0.10, 3.10 }, { -0.38, 3.81 }, { -0.52, 4.76 }, { -0.38, 5.48 }, { 0.05, 6.19 } }
local LOWER_CALF_W = 2.3 -- full-body FRONT sheet: shin ~2.1 wide

-- Instep chevron: a house-shaped plate leaning forward over the ankle.
local INSTEP_BOTTOM: Pt = { -2.85, 2.55 } -- front-bottom corner (side view)
local INSTEP_TIP: Pt = { -1.62, 4.67 } -- pointed top
local INSTEP_W = 2.6 -- narrowed: no flare over the ankle (full-body sheet)
local INSTEP_SHOULDER = 0.95 -- side edge length before the point, along the face
local INSTEP_DEPTH = 0.8
-- side flaps of the instep plate, wrapping back to the shin (side view)
local INSTEP_FLAP: { Pt } = { { -2.40, 3.43 }, { -2.80, 2.70 }, { -1.90, 2.29 }, { -1.62, 2.71 }, { -0.62, 2.71 }, { -0.90, 3.43 } }
local INSTEP_FLAP_W = 2.7

-- Foot: toe cap (quarter-ellipsoid on a sole strip), front plate, mid plate,
-- dark arch under the ankle, heel block.
local SOLE_TOP = 0.38
local TOE_BACK = -4.33 -- z where the toe cap meets the front plate
local TOE_TIP = -6.05
local TOE_TOP = 1.76
local FOOT_W = 3.8
-- front plate: an arch (front view) behind the toe cap, a rim around it
local FRONT_ARCH = { halfW = 1.92, h = 1.95, zFront = -4.33, zBack = -2.4 }
local MID_PLATE: { Pt } = { { -3.14, 2.00 }, { -2.67, 2.52 }, { -1.90, 2.29 }, { -1.62, 2.71 }, { -0.67, 2.71 }, { -0.29, 1.81 }, { -1.48, 0.2 }, { -2.43, 0.2 } } -- bottom kept above the ground
local ARCH: { Pt } = { { -1.48, 0.1 }, { -0.29, 1.81 }, { 0.38, 2.10 }, { 0.86, 2.62 }, { 1.14, 2.62 }, { 1.00, 1.43 }, { 0.43, 1.43 }, { 0.43, 0.38 } }
local ARCH_W = 3.0
local HEEL: { Pt } = { { 0.43, 0 }, { 2.33, 0 }, { 2.33, 2.52 }, { 1.05, 2.52 }, { 0.86, 1.52 }, { 0.43, 1.43 } }
local HEEL_W = 2.4
local FOOT_TENT = math.rad(22) -- the foot's sides lean in (front / back views)

-- Piston at the back: calf -> knuckle joint -> post on the heel.
local PISTON_TOP: Pt = { 1.57, 8.33 }
local PISTON_KNUCKLE: Pt = { 2.81, 5.33 }
local PISTON_POST: Pt = { 1.62, 3.48 } -- top of the heel post
local PISTON_ROD_D = 0.45
local PISTON_CLAMP = { d = 0.95, len = 0.65 } -- band round the upper rod (back view)
local PISTON_SLEEVE = { d = 0.65, len = 1.0 } -- wider sleeve where the lower rod leaves the post
local PISTON_KNUCKLE_R = 0.42
local PISTON_POST_D = 0.76

-- Thigh stub above the knee (where the thigh would continue).
local THIGH_STUB: { Pt } = { { -3.9, 13.6 }, { -2.3, 12.9 }, { -0.1, 12.95 }, { 0.5, 13.6 } }
local THIGH_STUB_W = 2.6

local LINE_W = 0.1 -- outline strip width (cells)
local LINE_T = 0.04 -- outline strip thickness

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

-- Two WedgeParts filling triangle a b c (studs, world), `thick` studs thick
-- centred on the triangle's plane.
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

-- Ear-clipping triangulation of a simple polygon.
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
			break -- degenerate leftovers
		end
	end
	if #idx == 3 then
		table.insert(tris, { poly[idx[1]], poly[idx[2]], poly[idx[3]] })
	end
	return tris
end

-- Polygon grown outward by d cells (shrunk if d < 0).
local function offset(polyIn: { Pt }, d: number): { Pt }
	local poly = ccw(polyIn)
	local n = #poly
	local out = {}
	for i = 1, n do
		local p, v, q = poly[(i - 2) % n + 1], poly[i], poly[i % n + 1]
		local e1 = Vector2.new(v[1] - p[1], v[2] - p[2]).Unit
		local e2 = Vector2.new(q[1] - v[1], q[2] - v[2]).Unit
		-- outward normals of a CCW polygon point right of each edge
		local n1 = Vector2.new(e1.Y, -e1.X)
		local n2 = Vector2.new(e2.Y, -e2.X)
		local bis = n1 + n2
		if bis.Magnitude < 1e-6 then
			bis = n1
		end
		bis = bis.Unit
		local k = d / math.max(bis:Dot(n1), 0.35)
		table.insert(out, { v[1] + bis.X * k, v[2] + bis.Y * k })
	end
	return out
end

-- Side-profile polygon (cells, frame's z/h plane) extruded across x in
-- [xc - w/2, xc + w/2] (cells) of frame `xf` (studs).
local function prism(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, xc: number, w: number, color: Color3)
	local u = ctx.u
	for _, t in triangulate(poly) do
		local a = xf * Vector3.new(xc * u, t[1][2] * u, t[1][1] * u)
		local b = xf * Vector3.new(xc * u, t[2][2] * u, t[2][1] * u)
		local c = xf * Vector3.new(xc * u, t[3][2] * u, t[3][1] * u)
		wedgeTri(parent, name, color, a, b, c, w * u)
	end
end

-- Dark strips along every edge of `poly`, lying on the face at x = xFace
-- (cells) and standing proud of it on the `outward` side (+1 / -1).
local function outline(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, xFace: number, outward: number)
	if not BootBuilder.Outlines then
		return
	end
	local u = ctx.u
	local x = (xFace + outward * LINE_T / 2) * u
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		local a = Vector3.new(x, p[2] * u, p[1] * u)
		local b = Vector3.new(x, q[2] * u, q[1] * u)
		local len = (b - a).Magnitude
		if len > 1e-3 then
			local dir = (b - a).Unit
			local xAxis = Vector3.xAxis
			local cf = xf * CFrame.fromMatrix((a + b) / 2, xAxis, dir:Cross(xAxis))
			local s = newPart("Part", name, ctx.color.line, parent)
			s.Size = Vector3.new(LINE_T * u, LINE_W * u, len + LINE_W * u)
			s.CFrame = cf
			s.CastShadow = false
		end
	end
end

-- A plate: prism plus outlines on both outer faces.
local function plate(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, xc: number, w: number, color: Color3?)
	prism(ctx, parent, name, xf, poly, xc, w, color or ctx.color.main)
	outline(ctx, parent, name .. "Line", xf, poly, xc + w / 2, 1)
	outline(ctx, parent, name .. "Line", xf, poly, xc - w / 2, -1)
end

local function cylinder(ctx: Ctx, parent: Instance, name: string, cf: CFrame, len: number, d: number, color: Color3): BasePart
	local p = newPart("Part", name, color, parent) :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len * ctx.u, d * ctx.u, d * ctx.u)
	p.CFrame = cf
	return p
end

-- Cylinder (axis along the rod) between two world points, d in cells.
local function rod(ctx: Ctx, parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3): BasePart
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	local p = newPart("Part", name, color, parent) :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new((b - a).Magnitude, d * ctx.u, d * ctx.u)
	p.CFrame = cf
	return p
end

local function v3(ctx: Ctx, x: number, p: Pt): Vector3
	return Vector3.new(x * ctx.u, p[2] * ctx.u, p[1] * ctx.u)
end

-- ===== Pieces =============================================================

-- Faceted upper-front quarter of an ellipsoid: the toe cap.
local TOE_SEG_AROUND = 8
local TOE_SEG_FWD = 3
local function toeCap(ctx: Ctx, parent: Instance, xf: CFrame)
	local u = ctx.u
	local a, b, c = FOOT_W / 2 - 0.05, TOE_TOP - SOLE_TOP, TOE_BACK - TOE_TIP
	local centre = Vector3.new(0, SOLE_TOP, TOE_BACK)
	local function pt(i: number, j: number): Vector3
		local phi = math.pi * i / TOE_SEG_AROUND
		local th = (math.pi / 2) * j / TOE_SEG_FWD
		-- forward reach falls off faster with height (full-body side view: shorter upper toe)
		local p = centre + Vector3.new(a * math.cos(phi) * math.cos(th), b * math.sin(phi) * math.cos(th), -c * math.sin(th) * (1 - 0.5 * math.sin(phi) ^ 2))
		return xf * (p * u)
	end
	local thick = 0.12 * u
	for j = 0, TOE_SEG_FWD - 1 do
		for i = 0, TOE_SEG_AROUND - 1 do
			local p00, p10, p01, p11 = pt(i, j), pt(i + 1, j), pt(i, j + 1), pt(i + 1, j + 1)
			if j == TOE_SEG_FWD - 1 then
				wedgeTri(parent, "ToeCap", ctx.color.main, p00, p10, p01, thick)
			else
				wedgeTri(parent, "ToeCap", ctx.color.main, p00, p10, p11, thick)
				wedgeTri(parent, "ToeCap", ctx.color.main, p00, p11, p01, thick)
			end
		end
	end
	-- sole strip under the toe: half-ellipse footprint a little proud of the cap
	local foot: { Pt } = {}
	local n = 10
	for i = 0, n do
		local phi = math.pi * i / n
		table.insert(foot, { (a + 0.08) * math.cos(phi), TOE_BACK - (c + 0.1) * math.sin(phi) })
	end
	table.insert(foot, { -(a + 0.08), TOE_BACK + 0.3 })
	table.insert(foot, { a + 0.08, TOE_BACK + 0.3 })
	-- frame: X = up (extrusion), Y = +Z, so poly { x, z } lies flat
	local soleXf = xf * CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis)
	prism(ctx, parent, "ToeSole", soleXf, foot, SOLE_TOP / 2, SOLE_TOP, ctx.color.main)
	outline(ctx, parent, "ToeSoleLine", soleXf, foot, SOLE_TOP, 1)
end

-- One leaning side slab of a foot plate, outlined on its outer face.
local function plateSide(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, xc: number, w: number, s: number)
	prism(ctx, parent, name, xf, poly, xc, w, ctx.color.main)
	outline(ctx, parent, name .. "Line", xf, poly, xc + s * w / 2, s)
end

-- Foot plate with leaning ("tent") sides: a narrow full-height centre and two
-- side slabs rolled inward from the sole edge.
local function tentPlate(ctx: Ctx, parent: Instance, name: string, xf: CFrame, poly: { Pt }, w: number, centreW: number)
	local u = ctx.u
	prism(ctx, parent, name, xf, poly, 0, centreW, ctx.color.main)
	local slab = 0.55
	for _, s in { 1, -1 } do
		local hinge = xf * CFrame.new(s * (w / 2) * u, 0, 0) * CFrame.Angles(0, 0, s * FOOT_TENT)
		local sideXf = hinge * CFrame.new(-s * (w / 2) * u, 0, 0)
		plateSide(ctx, parent, name, sideXf, poly, s * (w / 2 - slab / 2), slab, s)
	end
end


-- ===== Build ==============================================================

local function weldAll(folder: Instance, bone: BasePart)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local w = Instance.new("Weld")
			w.Part0 = bone
			w.Part1 = d
			w.C0 = bone.CFrame:ToObjectSpace(d.CFrame)
			w.Parent = d
		end
	end
end

local function bone(name: string, cf: CFrame, u: number, parent: Instance): BasePart
	local b = Instance.new("Part")
	b.Name = name
	b.Size = Vector3.new(0.6, 0.6, 0.6) * u
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

-- Remove the outline / seam strips (BaseParts named "...Line") from a built
-- model unless BootBuilder.Outlines is on.
local function stripLines(model: Instance)
	if BootBuilder.Outlines then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, -4) == "Line" then
			d:Destroy()
		end
	end
end

-- Shared geometry helpers (used by LegBuilder). ctx = { u = studs per cell,
-- color = { main, joint, jointFace, recess, rod, line } }; polygons are
-- { a, b } cell pairs in a frame's (local Z, local Y) plane, extruded along
-- local X.
BootBuilder.Geometry = {
	newPart = newPart,
	wedgeTri = wedgeTri,
	prism = prism,
	outline = outline,
	plate = plate,
	cylinder = cylinder,
	rod = rod,
	offset = offset,
	weldAll = weldAll,
	bone = bone,
	stripLines = stripLines,
}

export type BuildOptions = {
	thighStub: boolean?, -- default true
	colors: { [string]: Color3 }?,
}

-- One boot. side "L" or "R" (default "R"). Built standing on y = 0 with the
-- ankle above the origin, facing -Z; WorldPivot = the knee joint.
function BootBuilder.build(scale: number?, side: string?, opts: BuildOptions?): Model
	local u = BootBuilder.CELL * (scale or BootBuilder.DefaultScale)
	local o = opts or {}
	local colors = table.clone(BootBuilder.Colors)
	if o.colors then
		for k, v in o.colors do
			colors[k] = v
		end
	end
	local ctx: Ctx = { u = u, color = colors }
	local s = if side == "L" then -1 else 1 -- +1 = right boot (sits at +X)

	local model = Instance.new("Model")
	model.Name = if s > 0 then "BootR" else "BootL"
	model:SetAttribute("Side", if s > 0 then "R" else "L")
	model:SetAttribute("Scale", scale or BootBuilder.DefaultScale)

	local ankle = v3(ctx, 0, ANKLE)
	-- shin frame: boot space rotated about the ankle so the knee tips inward
	local shinXf = CFrame.new(ankle) * CFrame.Angles(0, 0, s * LEAN) * CFrame.new(-ankle)
	local footXf = CFrame.identity

	local shinBone = bone("Shin", shinXf * CFrame.new(v3(ctx, 0, KNEE)), u, model)
	local footBone = bone("Foot", CFrame.new(ankle), u, model)
	model.PrimaryPart = shinBone

	local shinArmor = Instance.new("Folder")
	shinArmor.Name = "ShinArmor"
	shinArmor.Parent = model
	local footArmor = Instance.new("Folder")
	footArmor.Name = "FootArmor"
	footArmor.Parent = model

	-- --- shin ---
	-- knee joint: hub, face and rim discs, axis across the boot
	local kneeCF = shinXf * CFrame.new(v3(ctx, 0, KNEE))
	cylinder(ctx, shinArmor, "KneeRim", kneeCF, KNEE_W.rim, KNEE_R.rim * 2, colors.joint)
	cylinder(ctx, shinArmor, "KneeFace", kneeCF, KNEE_W.face, KNEE_R.face * 2, colors.jointFace)
	cylinder(ctx, shinArmor, "KneeHub", kneeCF, KNEE_W.hub, KNEE_R.hub * 2, colors.joint)
	for _, f in { 1, -1 } do
		-- ring lines between rim / face / hub
		cylinder(ctx, shinArmor, "KneeLine", kneeCF * CFrame.new(f * (KNEE_W.rim / 2 - 0.1) * u, 0, 0), 0.04, KNEE_R.rim * 2 + LINE_W * 2, colors.line)
		-- a thin dark disc between two steps, a bit wider than the inner step: shows as a ring
		cylinder(ctx, shinArmor, "KneeLine", kneeCF * CFrame.new(f * (KNEE_W.rim + KNEE_W.face) / 4 * u, 0, 0), 0.04, KNEE_R.face * 2 + LINE_W * 2, colors.line)
		cylinder(ctx, shinArmor, "KneeLine", kneeCF * CFrame.new(f * (KNEE_W.face + KNEE_W.hub) / 4 * u, 0, 0), 0.04, KNEE_R.hub * 2 + LINE_W * 2, colors.line)
	end
	if o.thighStub ~= false then
		plate(ctx, shinArmor, "ThighStub", shinXf, THIGH_STUB, 0, THIGH_STUB_W)
	end
	plate(ctx, shinArmor, "CalfHousing", shinXf, CALF, 0, CALF_W)
	plate(ctx, shinArmor, "KneeGuard", shinXf, KNEE_GUARD, 0, KNEE_GUARD_W)
	plate(ctx, shinArmor, "KneeGuardRidge", shinXf, offset(KNEE_GUARD, 0.12), 0, KNEE_GUARD_RIDGE_W)
	plate(ctx, shinArmor, "ShinPlate", shinXf, SHIN, 0, SHIN_W)
	plate(ctx, shinArmor, "ShinRidge", shinXf, offset(SHIN, 0.12), 0, SHIN_RIDGE_W)
	plate(ctx, shinArmor, "LowerCalf", shinXf, LOWER_CALF, 0, LOWER_CALF_W)

	-- piston upper half
	local top = shinXf * v3(ctx, 0, PISTON_TOP)
	local knuckle = shinXf * v3(ctx, 0, PISTON_KNUCKLE)
	rod(ctx, shinArmor, "PistonRod", top, knuckle, PISTON_ROD_D, colors.rod)
	local clampAt = top:Lerp(knuckle, 0.55)
	local along = (knuckle - top).Unit * PISTON_CLAMP.len / 2 * u
	rod(ctx, shinArmor, "PistonClamp", clampAt - along, clampAt + along, PISTON_CLAMP.d, colors.main)
	cylinder(ctx, shinArmor, "PistonKnuckle", CFrame.new(knuckle) * shinXf.Rotation, 0.6, PISTON_KNUCKLE_R * 2, colors.main)
	cylinder(ctx, shinArmor, "PistonKnucklePin", CFrame.new(knuckle) * shinXf.Rotation, 0.7, PISTON_KNUCKLE_R * 1.2, colors.joint)

	-- --- foot ---
	toeCap(ctx, footArmor, footXf)
	for _, d in footArmor:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "ToeCap" or d.Name == "ToeSole") then
			d:SetAttribute("PatternPlain", true) -- curved: plain
		end
	end
	do
		-- frame: X = +Z (extrusion), Y = up, so poly { -x, h } is the front view
		local archXf = footXf * CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.yAxis)
		local arch: { Pt } = {}
		local n = 10
		for i = 0, n do
			local phi = math.pi * i / n
			table.insert(arch, { FRONT_ARCH.halfW * math.cos(phi), FRONT_ARCH.h * math.sin(phi) })
		end
		local len = FRONT_ARCH.zBack - FRONT_ARCH.zFront
		prism(ctx, footArmor, "FrontPlate", archXf, arch, (FRONT_ARCH.zFront + FRONT_ARCH.zBack) / 2, len, colors.main)
		outline(ctx, footArmor, "FrontPlateLine", archXf, arch, FRONT_ARCH.zFront, -1)
	end
	tentPlate(ctx, footArmor, "MidPlate", footXf, MID_PLATE, FOOT_W - 0.1, 2.0)
	prism(ctx, footArmor, "Arch", footXf, ARCH, 0, ARCH_W, colors.recess)
	plate(ctx, footArmor, "HeelBlock", footXf, HEEL, 0, HEEL_W)

	-- instep chevron (house-shaped plate leaning forward)
	do
		local bottom = v3(ctx, 0, INSTEP_BOTTOM)
		local tip = v3(ctx, 0, INSTEP_TIP)
		local up = (tip - bottom).Unit
		local len = (tip - bottom).Magnitude / u
		local fwd = Vector3.new(0, -up.Z, up.Y) -- perpendicular to `up`, toward -Z
		if fwd.Z > 0 then
			fwd = -fwd
		end
		-- frame: X = out of the face (forward), Y = up the face, Z = across
		local xf = CFrame.fromMatrix(bottom, fwd, up)
		local hw = INSTEP_W / 2
		local house: { Pt } = { { -hw, 0 }, { hw, 0 }, { hw, INSTEP_SHOULDER }, { 0, len }, { -hw, INSTEP_SHOULDER } }
		plate(ctx, footArmor, "Instep", xf, house, -INSTEP_DEPTH / 2, INSTEP_DEPTH)
		plate(ctx, footArmor, "InstepFace", xf, offset(house, -0.22), 0.04, 0.08)
		for _, f in { 1, -1 } do
			plate(ctx, footArmor, "InstepFlap", footXf, INSTEP_FLAP, f * (INSTEP_FLAP_W / 2 - 0.15), 0.3)
		end
	end

	-- ankle discs (both sides)
	local ankleCF = CFrame.new(ankle)
	cylinder(ctx, footArmor, "AnkleRing", ankleCF, ANKLE_W.ring, ANKLE_R.ring * 2, colors.main)
	cylinder(ctx, footArmor, "AnkleHub", ankleCF, ANKLE_W.hub, ANKLE_R.hub * 2, colors.joint)
	for _, f in { 1, -1 } do
		cylinder(ctx, footArmor, "AnkleLine", ankleCF * CFrame.new(f * (ANKLE_W.ring / 2 - 0.1) * u, 0, 0), 0.04, ANKLE_R.ring * 2 + LINE_W * 2, colors.line)
		cylinder(ctx, footArmor, "AnkleLine", ankleCF * CFrame.new(f * (ANKLE_W.ring + ANKLE_W.hub) / 4 * u, 0, 0), 0.04, ANKLE_R.hub * 2 + LINE_W * 2, colors.line)
	end

	-- piston lower half: post on the heel, rod up to the knuckle
	local postTop = v3(ctx, 0, PISTON_POST)
	local postBottom = v3(ctx, 0, { PISTON_POST[1], HEEL[3][2] - 0.1 })
	rod(ctx, footArmor, "PistonPost", postBottom, postTop, PISTON_POST_D, colors.main)
	local cap = newPart("Part", "PistonPostCap", colors.main, footArmor) :: Part
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.one * PISTON_POST_D * u
	cap.CFrame = CFrame.new(postTop)
	rod(ctx, footArmor, "PistonRod", postTop, knuckle, PISTON_ROD_D, colors.rod)
	rod(ctx, footArmor, "PistonSleeve", postTop - (knuckle - postTop).Unit * 0.04 * u, postTop + (knuckle - postTop).Unit * PISTON_SLEEVE.len * u, PISTON_SLEEVE.d, colors.main)

	weldAll(shinArmor, shinBone)
	weldAll(footArmor, footBone)
	local motor = Instance.new("Motor6D")
	motor.Name = "Ankle"
	motor.Part0 = shinBone
	motor.Part1 = footBone
	motor.C0 = shinBone.CFrame:ToObjectSpace(footBone.CFrame)
	motor.C1 = CFrame.identity
	motor.Parent = shinBone

	stripLines(model)
	model.WorldPivot = shinBone.CFrame
	return model
end

-- Both boots, mirrored, STANCE cells apart (centre to centre), standing on
-- y = 0 around the origin. WorldPivot = ground point between them.
function BootBuilder.buildPair(scale: number?, opts: BuildOptions?): Model
	local u = BootBuilder.CELL * (scale or BootBuilder.DefaultScale)
	local pair = Instance.new("Model")
	pair.Name = "MechBoots"
	for _, side in { "R", "L" } do
		local boot = BootBuilder.build(scale, side, opts)
		local x = (if side == "R" then 1 else -1) * STANCE / 2 * u
		boot:PivotTo(CFrame.new(x, 0, 0) * boot:GetPivot())
		boot.Parent = pair
	end
	pair.WorldPivot = CFrame.identity
	return pair
end

return BootBuilder
