--!strict
-- Builds the mech's HEAD: a knight-like helmet on a round, stepped gorget
-- collar. Standalone piece from the owner's head sheet (FRONT / SIDE / BACK
-- views); not attached to the legs or any mech yet.
--
-- Same method and units as BootBuilder / LegBuilder: GRID CELLS read off the
-- sheet (one grid square = one cell = BootBuilder.CELL design units x
-- `scale`), so it fits the body built from the same sheets. Head space:
-- origin at the NECK BASE (bottom of the collar, centred), +Y up, the face
-- toward -Z. h = height above the neck base, z = front(-)/back(+), x across.
--
-- Sheet measurements (cells, h above the neck base):   sheet      built
--   spike tip                                           6.45       6.45
--   helmet top (flat part width)                        5.15 (2.2) same
--   helmet full width / where the top chamfer ends      3.1 / 4.35 same
--   helmet depth (side)                                 4.15       4.15
--   ear pods: width across / h range                    3.55 / 2.25..3.75 same
--   visor chevron (sides / centre), top                 3.15 / 2.75
--                                        bottom         2.5 / 2.1
--   chin point                                          0.7        0.7
--   collar width / top at the back                      5.3 / 2.6  same
--   gorget base width                                   ~6         6.0
--
-- Rig: "Collar" bone at the neck base (PrimaryPart, WorldPivot) and a
-- "Head" bone at the neck joint, joined by a Motor6D "Neck", so the helmet
-- can turn inside the collar later.
--
-- The helmet shell is lofted: the front-view outline (a hexagon with
-- chamfered top corners) is swept front to back and scaled to the side-view
-- dome height at each slice, so both views match. The gorget is a ring of
-- segments, high at the back and dropping low at the front so the face
-- shows above it (as the front view draws it).

local BootBuilder = require(script.Parent.BootBuilder)

local HeadBuilder = {}

local G = BootBuilder.Geometry

type Pt = { number }

-- ===== Proportions (grid cells) ==========================================

-- helmet cross-section (front view), bottom edge at HELMET_BOTTOM
local HELMET_BOTTOM = 2.75
-- narrowed after the full-body sheet review (helmet +-1.5 at h 34, +-1.2 at h 35.5 incl. ear pods)
local HELMET_SECTION: { Pt } = { { -1.32, 2.75 }, { -1.32, 4.4 }, { -1.08, 5.15 }, { 1.08, 5.15 }, { 1.32, 4.4 }, { 1.32, 2.75 } } -- { x, h } (head BACK ref: short chamfer, wide flat top)
local HELMET_TOP = 5.15 -- section top that the side profile scales
-- side profile: { z, dome top h } front to back
local HELMET_PROFILE: { Pt } = {
	{ -2.1, 4.0 },
	{ -1.85, 4.45 },
	{ -1.6, 4.75 },
	{ -0.85, 5.0 }, -- dome top lowered ~0.25 (full-body SIDE sheet: dome top ~h 36.0 assembled)
	{ 0.15, 5.1 },
	{ 1.05, 4.98 },
	{ 1.65, 4.85 },
	{ 1.95, 4.3 },
	{ 2.05, 3.6 },
	{ 2.1, 3.15 }, -- back rounds down to the rim (owner: rounded back of the head)
	{ 2.12, 2.85 },
}
local BROW_CAP_H = 3.45 -- front cap of the shell starts above the brow
local SLICES = 18 -- profile resampled (Catmull-Rom) into this many slices: small, even facets
local SHELL_T = 0.14 -- shell thickness

-- crest spike: a four-sided pyramid rising from the forehead. Side view: a
-- triangle front-base / tip / back-base; front view: a diamond, widest at
-- the side points.
local SPIKE = {
	tip = { 0, 6.15, -1.95 }, -- { x, h, z } (full-body SIDE sheet: tip ~h 36.6 / 37.4 assembled, z -3.4)
	front = { 0, 3.55, -2.12 }, -- on the brow
	back = { 0, 5.12, -0.55 }, -- emerges from the dome top so it shows from behind
	side = { 0.4, 5.15, -1.0 }, -- mirrored to -x
}

-- face (front view polygons { x, h }), stacked in front of the helmet
local FACEPLATE: { Pt } = { { -1.1, 3.2 }, { 1.1, 3.2 }, { 1.35, 2.0 }, { 0.95, 1.0 }, { 0.5, 0.75 }, { 0, 0.7 }, { -0.5, 0.75 }, { -0.95, 1.0 }, { -1.35, 2.0 } }
local FACEPLATE_Z = { -1.12, -0.6 } -- hidden core behind the angled face skins below
-- angled face (head SIDE ref): brow juts forward over a recessed visor slit,
-- the faceplate slopes back down to the chin, sides swept back. Rows of
-- { h, z } at columns x = 0, 0.55, 1.1, 1.32 (mirrored), top to bottom.
local FACE_X = { 0, 0.55, 1.0, 1.16 } -- outer column inside the helmet side walls (inner face x 1.18): nothing pokes through
local FACE_ROWS = {
	browTop = { { 3.5, -2.15 }, { 3.6, -2.05 }, { 3.7, -1.8 }, { 3.65, -1.55 } },
	browLip = { { 2.85, -2.25 }, { 2.95, -2.15 }, { 3.25, -1.9 }, { 3.2, -1.65 } },
	visorTop = { { 2.85, -1.75 }, { 2.95, -1.68 }, { 3.25, -1.5 }, { 3.2, -1.32 } }, -- slit set well back so it reads dark
	visorBot = { { 2.1, -1.72 }, { 2.3, -1.65 }, { 2.5, -1.45 }, { 2.45, -1.3 } },
	faceTop = { { 2.1, -2.1 }, { 2.3, -2.0 }, { 2.5, -1.75 }, { 2.45, -1.5 } },
	faceMid = { { 1.5, -1.85 }, { 1.55, -1.75 }, { 1.65, -1.55 }, { 1.75, -1.38 } },
	chin = { { 0.7, -1.5 }, { 0.75, -1.42 }, { 0.95, -1.3 }, { 1.2, -1.22 } },
}
-- dark band across the lower back of the helmet, lighter rim below it (head BACK ref)
local BACK_BAND = { h0 = 3.0, h1 = 3.35, halfW = 1.42 }
local VISOR: { Pt } = { { -1.1, 3.15 }, { 0, 2.75 }, { 1.1, 3.15 }, { 1.1, 2.5 }, { 0, 2.1 }, { -1.1, 2.5 } }
local VISOR_Z = { -2.3, -2.12 }
local CHEEK: { Pt } = { { 1.3, 2.3 }, { 1.0, 2.45 }, { 0.65, 1.0 }, { 0.91, 0.85 } } -- right side; mirrored
local CHEEK_Z = { -2.3, -1.0 }

-- ear pods: discs on the helmet sides
local EAR = { z = 0.2, h = 3.25, r = 0.72, inner = 0.42, x0 = 1.34, x1 = 1.57 }
-- side recess: a dark arch on each helmet side framed by a raised band (side view { z, h })
local EAR_ARCH: { Pt } = { { -1.25, 2.8 }, { -1.2, 3.6 }, { -0.7, 4.12 }, { 0.2, 4.28 }, { 1.1, 4.12 }, { 1.6, 3.6 }, { 1.7, 2.8 } }
local EAR_BAND = 0.28 -- band width round the arch
local EAR_X = { recess = { 1.3, 1.51 }, band = { 1.27, 1.45 } } -- the dark arch face sits just outside the band face (both clear of the shell's outer face at 1.39)

-- gorget: base ring + segmented collar (back high, front low) + rim
local COLLAR_Z = 1.0 -- collar centre, well behind the helmet centre (full-body SIDE: collar -3.2 .. +2.2)
local GORGET_BASE = { d = 6.0, h0 = 0, h1 = 0.55 }
local COLLAR = { r = 2.65, t = 0.45, h0 = 0.4, backTop = 2.3, frontTop = 0.6, dip = math.rad(75), segments = 24 }
local NECK = { d = 2.4, h0 = 0.3, h1 = 3.0 } -- dark neck column inside
local NECK_JOINT_H = 2.2 -- Head bone (Neck motor) height

-- ===== Helpers ============================================================

type Ctx = { u: number, color: { [string]: Color3 } }

-- front-view frame: poly { x, h } -> world (x, h), extruded along Z;
-- a prism from z0 to z1 uses xc = -(z0 + z1) / 2
local FRONT = CFrame.fromMatrix(Vector3.zero, -Vector3.zAxis, Vector3.yAxis)

local function frontSlab(ctx: Ctx, parent: Instance, name: string, poly: { Pt }, z: { number }, color: Color3?, back: boolean?)
	local z0, z1 = z[1], z[2]
	G.prism(ctx, parent, name, FRONT, poly, -(z0 + z1) / 2, z1 - z0, color or ctx.color.main)
	G.outline(ctx, parent, name .. "Line", FRONT, poly, -z0, 1)
	if back then
		G.outline(ctx, parent, name .. "Line", FRONT, poly, -z1, -1)
	end
end

local function profileTop(z: number): number
	local P = HELMET_PROFILE
	if z <= P[1][1] then
		return P[1][2]
	end
	for i = 1, #P - 1 do
		local a, b = P[i], P[i + 1]
		if z <= b[1] then
			local t = (z - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return P[#P][2]
end

-- the helmet section at slice z (world studs points)
local function section(ctx: Ctx, z: number, top: number): { Vector3 }
	local u = ctx.u
	local k = (top - HELMET_BOTTOM) / (HELMET_TOP - HELMET_BOTTOM)
	local pts = {}
	for _, p in HELMET_SECTION do
		table.insert(pts, Vector3.new(p[1], HELMET_BOTTOM + (p[2] - HELMET_BOTTOM) * k, z) * u)
	end
	return pts
end

-- ===== Build ==============================================================

export type BuildOptions = {
	colors: { [string]: Color3 }?,
}

function HeadBuilder.build(scale: number?, opts: BuildOptions?): Model
	local sc = scale or BootBuilder.DefaultScale
	local u = BootBuilder.CELL * sc
	local o = opts or {}
	local colors = table.clone(BootBuilder.Colors)
	colors.visor = Color3.fromRGB(52, 62, 72)
	if o.colors then
		for k, v in o.colors do
			colors[k] = v
		end
	end
	local ctx: Ctx = { u = u, color = colors }

	local model = Instance.new("Model")
	model.Name = "MechHead"
	model:SetAttribute("Scale", sc)

	local collarBone = G.bone("Collar", CFrame.identity, u, model)
	local headBone = G.bone("Head", CFrame.new(0, NECK_JOINT_H * u, 0), u, model)
	model.PrimaryPart = collarBone
	local collarArmor = Instance.new("Folder")
	collarArmor.Name = "CollarArmor"
	collarArmor.Parent = model
	local helmet = Instance.new("Folder")
	helmet.Name = "HelmetArmor"
	helmet.Parent = model

	-- --- helmet shell (lofted) ---
	-- every facet plate lies INSIDE the surface (outer faces meet exactly at
	-- the folds), so there are no V-gaps and no filler rods
	local centre = Vector3.new(0, HELMET_BOTTOM + 0.6, 0.1) * u
	local function skin(name: string, color: Color3, a: Vector3, b: Vector3, c: Vector3, t: number, out: Vector3?)
		local nrm = (b - a):Cross(c - a)
		if nrm.Magnitude < 1e-6 then
			return
		end
		nrm = nrm.Unit
		local ref = out or ((a + b + c) / 3 - centre)
		if nrm:Dot(ref) < 0 then
			nrm = -nrm
		end
		local k = -nrm * t * u / 2
		G.wedgeTri(helmet, name, color, a + k, b + k, c + k, t * u)
	end
	local P = HELMET_PROFILE
	local function profileAt(t: number): (number, number)
		-- Catmull-Rom through the profile points, t in [1, #P]
		local i = math.clamp(math.floor(t), 1, #P - 1)
		local f = t - i
		local p0, p1, p2, p3 = P[math.max(i - 1, 1)], P[i], P[i + 1], P[math.min(i + 2, #P)]
		local function cr(k: number): number
			return 0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * f + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * f * f + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * f * f * f)
		end
		return cr(1), math.max(cr(2), HELMET_BOTTOM + 0.05)
	end
	local slices = {}
	local zFirst, zLast = P[1][1], P[#P][1]
	for i = 0, SLICES - 1 do
		local z, top = profileAt(1 + (#P - 1) * i / (SLICES - 1))
		table.insert(slices, section(ctx, z, top))
	end
	local n = #HELMET_SECTION
	for i = 1, #slices - 1 do
		local A, B = slices[i], slices[i + 1]
		for j = 1, n - 1 do -- edges 1..n-1 go round the top; edge n (bottom) stays open
			skin("HelmetShell", colors.main, A[j], A[j + 1], B[j + 1], SHELL_T)
			skin("HelmetShell", colors.main, A[j], B[j + 1], B[j], SHELL_T)
		end
	end
	-- back cap (small), and the front one only ABOVE the brow (the face skins
	-- close the front below it; a full cap would hide the visor slit)
	do
		local S = {}
		for _, p in slices[#slices] do
			table.insert(S, p - Vector3.new(0, 0, 0.04 * u))
		end
		for j = 2, n - 1 do
			skin("HelmetCap", colors.main, S[1], S[j], S[j + 1], SHELL_T, Vector3.zAxis)
		end
		-- set 0.04 behind the first slice so its face isn't coplanar with the shell's edge faces
		local F = {}
		for _, p in slices[1] do
			table.insert(F, p + Vector3.new(0, 0, 0.04 * u))
		end
		local cut = BROW_CAP_H * u
		local poly = {}
		for j = 1, n do
			local p, q = F[j], F[j % n + 1]
			if p.Y >= cut then
				table.insert(poly, p)
			end
			if (p.Y - cut) * (q.Y - cut) < 0 then
				local t = (cut - p.Y) / (q.Y - p.Y)
				table.insert(poly, p + (q - p) * t)
			end
		end
		for j = 2, #poly - 1 do
			skin("HelmetCap", colors.main, poly[1], poly[j], poly[j + 1], SHELL_T, -Vector3.zAxis)
		end
	end
	-- underside (dark) so the open bottom doesn't show sky
	local under = G.newPart("Part", "HelmetUnder", colors.joint, helmet)
	under.Size = Vector3.new(2.55, 0.1, zLast - zFirst - 0.1) * u
	under.CFrame = CFrame.new(0, (HELMET_BOTTOM + 0.22) * u, (zFirst + zLast) / 2 * u)
	-- lighter rim along the bottom edge, dark band across the lower back
	local rim = G.newPart("Part", "HelmetRim", colors.jointFace, helmet)
	rim.Size = Vector3.new(2.84, 0.26, zLast - zFirst + 0.1) * u
	rim.CFrame = CFrame.new(0, (HELMET_BOTTOM + 0.02) * u, (zFirst + zLast) / 2 * u)
	do
		local bb = BACK_BAND
		local hb = (bb.h0 + bb.h1) / 2
		-- the back of the dome is near-vertical at band height (z ~2.05 .. 2.12)
		local zb = 2.21
		local band = G.newPart("Part", "HelmetBackBand", colors.joint, helmet)
		band.Size = Vector3.new(bb.halfW * 2, bb.h1 - bb.h0, 0.24) * u
		band.CFrame = CFrame.new(0, hb * u, zb * u)
	end

	-- --- crest spike (solid four-sided pyramid) ---
	do
		local function p(t: { number }, sx: number?): Vector3
			return Vector3.new(t[1] * (sx or 1), t[2], t[3]) * u
		end
		local T, F, B = p(SPIKE.tip), p(SPIKE.front), p(SPIKE.back)
		local R, L = p(SPIKE.side), p(SPIKE.side, -1)
		local mid = (F + B + R + L) / 4
		for _, f in { { F, R }, { R, B }, { B, L }, { L, F } } do
			local nrm = (f[1] - T):Cross(f[2] - T).Unit
			if nrm:Dot((T + f[1] + f[2]) / 3 - mid) < 0 then
				nrm = -nrm
			end
			local k = -nrm * 0.05 * u
			G.wedgeTri(helmet, "Spike", colors.main, T + k, f[1] + k, f[2] + k, 0.1 * u)
		end
	end

	-- --- face: hidden core, then angled skins (brow, recessed visor slit, faceplate) ---
	frontSlab(ctx, helmet, "FaceCore", FACEPLATE, FACEPLATE_Z)
	do
		local function row(r: { { number } }): { Vector3 }
			local pts = {}
			for i = #FACE_X, 2, -1 do
				table.insert(pts, Vector3.new(-FACE_X[i], r[i][1], r[i][2]) * u)
			end
			for i = 1, #FACE_X do
				table.insert(pts, Vector3.new(FACE_X[i], r[i][1], r[i][2]) * u)
			end
			return pts
		end
		local function bandRows(name: string, color: Color3, top: { Vector3 }, bot: { Vector3 }, t: number)
			for i = 1, #top - 1 do
				skin(name, color, top[i], top[i + 1], bot[i + 1], t, -Vector3.zAxis)
				skin(name, color, top[i], bot[i + 1], bot[i], t, -Vector3.zAxis)
			end
		end
		local R = FACE_ROWS
		bandRows("Brow", colors.main, row(R.browTop), row(R.browLip), 0.3)
		bandRows("BrowLip", colors.main, row(R.browLip), row(R.visorTop), 0.2)
		bandRows("Visor", colors.line, row(R.visorTop), row(R.visorBot), 0.2)
		bandRows("VisorLip", colors.main, row(R.visorBot), row(R.faceTop), 0.2)
		bandRows("Faceplate", colors.main, row(R.faceTop), row(R.faceMid), 0.3)
		bandRows("Faceplate", colors.main, row(R.faceMid), row(R.chin), 0.3)
		-- close the sides of the brow / face back to the helmet
		local order = { R.browTop, R.browLip, R.visorTop, R.visorBot, R.faceTop, R.faceMid, R.chin }
		for _, sd in { 1, -1 } do
			local x = sd * FACE_X[#FACE_X]
			for i = 1, #order - 1 do
				local a, b = order[i][#FACE_X], order[i + 1][#FACE_X]
				local A, B = Vector3.new(x, a[1], a[2]) * u, Vector3.new(x, b[1], b[2]) * u
				local A2, B2 = Vector3.new(x, a[1], -1.15) * u, Vector3.new(x, b[1], -1.15) * u
				skin("FaceSide", colors.main, A, B, B2, 0.15, Vector3.new(sd, 0, 0))
				skin("FaceSide", colors.main, A, B2, A2, 0.15, Vector3.new(sd, 0, 0))
			end
		end
	end
	-- cheek guards, swept back toward the ears (outer edge further back)
	for _, sd in { 1, -1 } do
		local function V(pt: { number }): Vector3
			local x = pt[1]
			return Vector3.new(sd * x, pt[2], -1.95 + (x - 0.65) * 1.05) * u
		end
		local c = CHEEK
		skin("CheekGuard", colors.main, V(c[1]), V(c[2]), V(c[3]), 0.3, Vector3.new(sd * 0.5, 0, -1))
		skin("CheekGuard", colors.main, V(c[1]), V(c[3]), V(c[4]), 0.3, Vector3.new(sd * 0.5, 0, -1))
	end

	-- --- ear pods ---
	for _, s in { 1, -1 } do
		local band = G.offset(EAR_ARCH, EAR_BAND)
		for _, p in band do
			p[2] = math.max(p[2], 2.8) -- band bottom just above the shell's bottom edge (no coplanar faces)
		end
		local bx, rx = EAR_X.band, EAR_X.recess
		G.plate(ctx, helmet, "EarBand", CFrame.identity, band, s * (bx[1] + bx[2]) / 2, bx[2] - bx[1])
		G.plate(ctx, helmet, "EarRecess", CFrame.identity, EAR_ARCH, s * (rx[1] + rx[2]) / 2, rx[2] - rx[1], colors.visor)
		local cx = s * (EAR.x0 + EAR.x1) / 2
		local cf = CFrame.new(cx * u, EAR.h * u, EAR.z * u)
		G.cylinder(ctx, helmet, "EarPod", cf, EAR.x1 - EAR.x0, EAR.r * 2, colors.jointFace)
		G.cylinder(ctx, helmet, "EarPodHub", cf * CFrame.new(s * 0.06 * u, 0, 0), EAR.x1 - EAR.x0, EAR.inner * 2, colors.joint)
		G.cylinder(ctx, helmet, "EarPodLine", cf * CFrame.new(-s * 0.05 * u, 0, 0), 0.04, EAR.r * 2 + 0.2, colors.line)
		G.cylinder(ctx, helmet, "EarPodLine", cf * CFrame.new(s * 0.02 * u, 0, 0), 0.04, EAR.inner * 2 + 0.2, colors.line)
	end

	-- --- gorget collar ---
	local yAxis = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
	local base = G.cylinder(ctx, collarArmor, "GorgetBase", CFrame.new(0, (GORGET_BASE.h0 + GORGET_BASE.h1) / 2 * u, COLLAR_Z * u) * yAxis, GORGET_BASE.h1 - GORGET_BASE.h0, GORGET_BASE.d, colors.main)
	base.CastShadow = true
	G.cylinder(ctx, collarArmor, "GorgetLine", CFrame.new(0, (GORGET_BASE.h1 - 0.02) * u, COLLAR_Z * u) * yAxis, 0.04, COLLAR.r * 2 + 0.2, colors.line)
	G.cylinder(ctx, collarArmor, "Neck", CFrame.new(0, (NECK.h0 + NECK.h1) / 2 * u, COLLAR_Z * u) * yAxis, NECK.h1 - NECK.h0, NECK.d, colors.joint)
	G.cylinder(ctx, collarArmor, "CollarFloor", CFrame.new(0, (GORGET_BASE.h1 + 0.03) * u, COLLAR_Z * u) * yAxis, 0.06, COLLAR.r * 2 - 0.2, colors.recess)
	local segs = COLLAR.segments
	local segW = 2 * math.pi * COLLAR.r / segs + 0.12
	-- top height round the ring: full height except a dip at the front (under the chin)
	local function topAt(th: number): number
		local a = math.abs(((th + math.pi) % (2 * math.pi)) - math.pi) -- 0 at the front .. pi at the back
		local k = math.clamp(a / COLLAR.dip, 0, 1)
		return COLLAR.frontTop + (COLLAR.backTop - COLLAR.frontTop) * (1 - (1 - k) ^ 2)
	end
	for i = 0, segs - 1 do
		local th0, th1 = i / segs * 2 * math.pi, (i + 1) / segs * 2 * math.pi -- 0 = front (-Z)
		local th = (th0 + th1) / 2
		local t0, t1 = topAt(th0), topAt(th1)
		local low, high = math.min(t0, t1), math.max(t0, t1)
		local h = low - COLLAR.h0
		local dir = Vector3.new(math.sin(th), 0, -math.cos(th))
		local c = Vector3.new(0, 0, COLLAR_Z) + dir * (COLLAR.r - COLLAR.t / 2)
		local mid = Vector3.new(c.X, COLLAR.h0 + h / 2, c.Z) * u
		local cf = CFrame.lookAt(mid, mid + dir) -- +X = toward th1
		local seg = G.newPart("Part", "CollarSegment", colors.main, collarArmor)
		seg.Size = Vector3.new(segW, h, COLLAR.t) * u
		seg.CFrame = cf
		local dh = high - low
		if dh > 0.02 then
			-- sloped top: a wedge rising toward the higher edge
			local w = G.newPart("WedgePart", "CollarSegment", colors.main, collarArmor)
			w.Size = Vector3.new(COLLAR.t, dh, segW) * u
			w.CFrame = cf * CFrame.new(0, (h / 2 + dh / 2) * u, 0) * CFrame.Angles(0, if t1 > t0 then math.pi / 2 else -math.pi / 2, 0)
			-- edge line along the slope, on the outer face
			local a = cf * Vector3.new(-segW / 2 * u, (h / 2 + t0 - low) * u, -(COLLAR.t / 2 + 0.02) * u)
			local b = cf * Vector3.new(segW / 2 * u, (h / 2 + t1 - low) * u, -(COLLAR.t / 2 + 0.02) * u)
			local line = G.newPart("Part", "CollarLine", colors.line, collarArmor)
			line.Size = Vector3.new(0.08 * u, 0.08 * u, (b - a).Magnitude)
			line.CFrame = CFrame.lookAt((a + b) / 2, b)
			line.CastShadow = false
		else
			local rimPart = G.newPart("Part", "CollarRim", colors.jointFace, collarArmor)
			rimPart.Size = Vector3.new(segW + 0.03, 0.14, COLLAR.t + 0.1) * u
			rimPart.CFrame = cf * CFrame.new(0, (h / 2 + 0.05) * u, 0) -- sits proud of the segment top (no coplanar faces)
			local line = G.newPart("Part", "CollarLine", colors.line, collarArmor)
			line.Size = Vector3.new(segW, 0.06, COLLAR.t + 0.12) * u
			line.CFrame = cf * CFrame.new(0, (h / 2 - 0.17) * u, 0)
			line.CastShadow = false
		end
	end

	G.weldAll(collarArmor, collarBone)
	-- the helmet is curved all over: plain (TitanPattern skips PatternPlain parts)
	for _, d in helmet:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("PatternPlain", true)
		end
	end
	G.weldAll(helmet, headBone)
	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = collarBone
	neck.Part1 = headBone
	neck.C0 = collarBone.CFrame:ToObjectSpace(headBone.CFrame)
	neck.Parent = collarBone

	G.stripLines(model)
	model.WorldPivot = collarBone.CFrame
	return model
end

return HeadBuilder
