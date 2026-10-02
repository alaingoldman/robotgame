--!strict
-- The SCRAPYARD: the core loop's play area, built from primitive parts (no
-- assets), south of the spawn (+Z) and clear of the mech lineups (-Z), the
-- EXO showcase (z ~ 20) and the assembled-mech preview (x ~ 160).
--
-- Workspace.Scrapyard is built once in Studio edit mode and saved with the
-- place (Rojo leaves unmanaged Workspace children alone), like ExoShowcase;
-- ensure() rebuilds it at runtime only if the folder is missing. Run in edit
-- mode (plugin context, fresh copy so the require cache can't serve an old
-- version):
--   require(game.ServerScriptService.Server.CoreLoop.Scrapyard:Clone()).build()
--
-- Layout (top view, +Z = away from the spawn; yard floor x -120..120, z 70..250):
--   north edge   jersey barriers with wide gaps + the GATE arch (x 0) and its
--                SCRAPYARD sign; the four BASE PLOTS sit just north of it
--                (z ~ 50, x -84 / -28 / 28 / 84, see CoreLoopConfig.Bases)
--   centre       THE MOUND: raised 8-stud plateau with ramps N + S, a crane
--                tower landmark (blinking red light) on top
--   west         PIPE RUN: three big pipes, one on supports (walkable), valves
--   north-west   FALLEN HULK: a giant broken mech lying on its side (climbable)
--   east         CONTAINER STACKS (1-3 high) + catwalks; a bridge from the
--                stacks to the mound
--   south-west   RUINED FACTORY: broken walls, pillars, a collapsed roof slab
--                (ramp), the SMOKESTACK landmark
--   south-east   THE TRENCH: a raised terrace cut by a canyon, ramps in / out
--   everywhere   scrap piles (decor), lamp posts, floor patches
-- Spawn markers (invisible): Scrapyard.JunkSpawns / Scrapyard.CrateSpawns,
-- found by raycasts + clearance checks after the geometry is placed.
-- Bases: Scrapyard.Bases.Plot<i> with Pad, Sign (SurfaceGui "Owner" label),
-- EquipStation, Locker, Charger (+ "ChargeLight" neon) and a DropZone; the
-- server (CoreLoop/Bases) adds the prompts / owner names at runtime.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scrapyard = {}

local function cfg(): any
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CoreLoopConfig"))
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local C = {
	concrete = rgb(148, 146, 138),
	concreteDark = rgb(112, 110, 104),
	asphalt = rgb(60, 60, 62),
	dirt = rgb(112, 98, 80),
	dirtDark = rgb(88, 78, 64),
	rust = rgb(140, 78, 48),
	rustDark = rgb(98, 56, 38),
	steel = rgb(110, 114, 120),
	gunmetal = rgb(62, 65, 70),
	dark = rgb(34, 35, 38),
	yellow = rgb(236, 205, 40),
	black = rgb(24, 24, 26),
	green = rgb(70, 255, 120),
	red = rgb(255, 60, 50),
	containers = { rgb(150, 60, 45), rgb(50, 90, 140), rgb(60, 120, 110), rgb(200, 120, 40), rgb(98, 106, 62), rgb(170, 170, 160) },
}

local M = Enum.Material
local rng = Random.new(20261002)

local folder: Folder
local count = 0

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	count += 1
	return p
end

-- WedgePart whose slope rises from `low` (ground-edge centre) to `high` (top-edge centre).
local function ramp(parent: Instance, name: string, width: number, low: Vector3, high: Vector3, color: Color3, mat: Enum.Material?): WedgePart
	local h = high.Y - low.Y
	local flat = Vector3.new(high.X - low.X, 0, high.Z - low.Z)
	local len = flat.Magnitude
	local mid = Vector3.new((low.X + high.X) / 2, low.Y + h / 2, (low.Z + high.Z) / 2)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = Vector3.new(width, h, len)
	-- a wedge's tall face is its back (+Z): face -Z toward the low end
	w.CFrame = CFrame.lookAt(mid, mid - flat.Unit)
	w.Color = color
	w.Material = mat or M.Concrete
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	count += 1
	return w
end

local function group(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function at(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

local function neon(p: BasePart, color: Color3)
	p.Material = M.Neon
	p.Color = color
	p.CastShadow = false
end

local function lightOn(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

------------------------------------------------------------------ pieces

local function container(parent: Instance, cf: CFrame, color: Color3, doors: boolean?)
	local m = group(parent, "Container")
	local size = Vector3.new(8, 8.5, 20)
	part(m, "Body", size, cf * CFrame.new(0, size.Y / 2, 0), color, M.CorrodedMetal)
	-- corrugation ribs along both long sides + the rails along the top
	for _, sx in { -1, 1 } do
		part(m, "Rib", Vector3.new(0.3, 7.6, 18.6), cf * CFrame.new(sx * 4.05, size.Y / 2, 0), color:Lerp(Color3.new(0, 0, 0), 0.25), M.CorrodedMetal)
	end
	part(m, "Rail", Vector3.new(8.2, 0.4, 20.2), cf * CFrame.new(0, size.Y - 0.2, 0), color:Lerp(Color3.new(0, 0, 0), 0.35), M.Metal)
	if doors then
		part(m, "Doors", Vector3.new(7.4, 7.8, 0.3), cf * CFrame.new(0, size.Y / 2, -10.1), color:Lerp(Color3.new(1, 1, 1), 0.08), M.Metal)
		for _, dx in { -1.6, 1.6 } do
			part(m, "Bar", Vector3.new(0.2, 7.6, 0.2), cf * CFrame.new(dx, size.Y / 2, -10.3), C.steel, M.Metal)
		end
	end
end

local function scrapPile(parent: Instance, center: Vector3, radius: number, pieces: number)
	local m = group(parent, "ScrapPile")
	for i = 1, pieces do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, radius) * (1 - i / pieces * 0.5)
		local s = Vector3.new(rng:NextNumber(1.5, 5), rng:NextNumber(0.6, 3), rng:NextNumber(1.5, 6)) * (1.2 - i / pieces * 0.5)
		local y = (1 - r / radius) * radius * 0.45 + s.Y * 0.3
		local cf = CFrame.new(center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r))
			* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6))
		local roll = rng:NextNumber()
		local color = if roll < 0.4 then C.rust elseif roll < 0.6 then C.rustDark elseif roll < 0.8 then C.steel else C.containers[rng:NextInteger(1, #C.containers)]
		if roll > 0.9 then
			-- a tyre
			local t = part(m, "Tyre", Vector3.new(1.4, 4, 4), cf, C.black, M.Rubber, Enum.PartType.Cylinder)
			t.CanCollide = true
		elseif roll > 0.75 then
			local w = Instance.new("WedgePart")
			w.Name = "Plate"
			w.Anchored = true
			w.Size = s
			w.CFrame = cf
			w.Color = color
			w.Material = M.CorrodedMetal
			w.Parent = m
			count += 1
		else
			part(m, "Chunk", s, cf, color, if roll < 0.6 then M.CorrodedMetal else M.Metal)
		end
	end
end

local function lamp(parent: Instance, pos: Vector3, yaw: number)
	local m = group(parent, "Lamp")
	local base = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	part(m, "Post", Vector3.new(0.7, 16, 0.7), base * CFrame.new(0, 8, 0), C.gunmetal, M.Metal)
	part(m, "Arm", Vector3.new(0.5, 0.5, 4), base * CFrame.new(0, 15.8, -1.8), C.gunmetal, M.Metal)
	local head = part(m, "Head", Vector3.new(1.6, 0.6, 1.2), base * CFrame.new(0, 15.5, -3.6), C.dark, M.Metal)
	local bulb = part(m, "Bulb", Vector3.new(1.2, 0.2, 0.8), base * CFrame.new(0, 15.15, -3.6), rgb(255, 214, 150))
	neon(bulb, rgb(255, 214, 150))
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 100
	spot.Range = 34
	spot.Brightness = 2.2
	spot.Color = rgb(255, 205, 140)
	spot.Parent = head
end

local function barrier(parent: Instance, cf: CFrame, len: number)
	-- jersey barrier: base + tapered top (two wedges)
	local m = group(parent, "Barrier")
	part(m, "Base", Vector3.new(2.6, 1.2, len), cf * CFrame.new(0, 0.6, 0), C.concrete, M.Concrete)
	part(m, "Top", Vector3.new(1.2, 2, len), cf * CFrame.new(0, 2.2, 0), C.concrete, M.Concrete)
	local s = part(m, "Stripe", Vector3.new(2.62, 0.4, len * 0.98), cf * CFrame.new(0, 1.0, 0), C.yellow, M.SmoothPlastic)
	s.CastShadow = false
end

local function fence(parent: Instance, a: Vector3, b: Vector3, height: number)
	-- corrugated panels on posts, ~24 studs per panel
	local m = group(parent, "Fence")
	local d = b - a
	local n = math.max(1, math.ceil(d.Magnitude / 24))
	for i = 0, n - 1 do
		local p0 = a + d * (i / n)
		local p1 = a + d * ((i + 1) / n)
		local mid = (p0 + p1) / 2
		local cf = CFrame.lookAt(mid, p1) * CFrame.Angles(0, math.pi / 2, 0)
		local panelColor = if i % 3 == 0 then C.rust elseif i % 3 == 1 then C.steel else C.rustDark
		part(m, "Panel", Vector3.new((p1 - p0).Magnitude, height, 0.4), cf * CFrame.new(0, height / 2, 0), panelColor, M.CorrodedMetal)
		part(m, "Post", Vector3.new(0.8, height + 1, 0.8), CFrame.new(p0) * CFrame.new(0, (height + 1) / 2, 0), C.gunmetal, M.Metal)
	end
	part(m, "Post", Vector3.new(0.8, height + 1, 0.8), CFrame.new(b) * CFrame.new(0, (height + 1) / 2, 0), C.gunmetal, M.Metal)
end

local function railing(parent: Instance, a: Vector3, b: Vector3)
	local d = b - a
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b)
	part(parent, "Rail", Vector3.new(0.25, 0.25, d.Magnitude), cf * CFrame.new(0, 3, 0), C.yellow, M.Metal).CastShadow = false
	local n = math.max(1, math.floor(d.Magnitude / 6))
	for i = 0, n do
		local p = a + d * (i / n)
		part(parent, "RailPost", Vector3.new(0.25, 3, 0.25), CFrame.new(p + Vector3.new(0, 1.5, 0)), C.gunmetal, M.Metal)
	end
end

-- Flat walkway deck from a to b (centre line, deck top height = a.Y), on posts.
local function catwalk(parent: Instance, a: Vector3, b: Vector3, width: number, rails: boolean)
	local m = group(parent, "Catwalk")
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + d)
	part(m, "Deck", Vector3.new(width, 0.6, d.Magnitude), cf * CFrame.new(0, -0.3, 0), C.gunmetal, M.DiamondPlate)
	local n = math.max(1, math.floor(d.Magnitude / 14))
	for i = 1, n - 1 do
		local p = a + d * (i / n)
		for _, sx in { -1, 1 } do
			local q = p + cf.RightVector * sx * (width / 2 - 0.4)
			part(m, "Leg", Vector3.new(0.6, a.Y, 0.6), CFrame.new(q.X, a.Y / 2 - 0.3, q.Z), C.steel, M.Metal)
		end
	end
	if rails then
		for _, sx in { -1, 1 } do
			local off = cf.RightVector * sx * (width / 2 - 0.15)
			railing(m, a + off, b + off)
		end
	end
end

------------------------------------------------------------------ zones

local function buildFloor(parent: Instance)
	local m = group(parent, "Floor")
	local Y = cfg().Yard
	local c, s = Y.Center, Y.Size
	-- big dirt base + varied patches (tops at y 0.05 .. 0.15)
	part(m, "Dirt", Vector3.new(s.X, 1, s.Y), CFrame.new(c.X, -0.45, c.Z), C.dirt, M.Ground)
	for i = 1, 14 do
		local w, l = rng:NextNumber(20, 46), rng:NextNumber(20, 46)
		local px = rng:NextNumber(-s.X / 2 + w / 2, s.X / 2 - w / 2)
		local pz = rng:NextNumber(-s.Y / 2 + l / 2, s.Y / 2 - l / 2)
		local mat = if i % 3 == 0 then M.Asphalt elseif i % 3 == 1 then M.Slate else M.Ground
		local col = if mat == M.Asphalt then C.asphalt elseif mat == M.Slate then C.concreteDark else C.dirtDark
		part(m, "Patch", Vector3.new(w, 1, l), CFrame.new(c.X + px, -0.45 + 0.04 + i * 0.004, c.Z + pz) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), col, mat)
	end
	-- the main road: gate -> mound
	part(m, "Road", Vector3.new(16, 1, 60), CFrame.new(0, -0.38, 100), C.asphalt, M.Asphalt)
	for i = 0, 5 do
		local dash = part(m, "RoadLine", Vector3.new(0.5, 0.1, 5), CFrame.new(0, 0.13, 74 + i * 10), C.yellow)
		dash.CastShadow = false
	end
end

local function buildEdge(parent: Instance)
	local m = group(parent, "Perimeter")
	local Y = cfg().Yard
	local x0, x1 = Y.Center.X - Y.Size.X / 2, Y.Center.X + Y.Size.X / 2
	local z0, z1 = Y.Center.Z - Y.Size.Y / 2, Y.Center.Z + Y.Size.Y / 2
	fence(m, Vector3.new(x0, 0, z0 + 8), Vector3.new(x0, 0, z1), 10)
	fence(m, Vector3.new(x1, 0, z0 + 8), Vector3.new(x1, 0, z1), 10)
	fence(m, Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1), 10)
	-- north edge: barriers with gaps in front of every base plot and the gate
	for _, seg in { { -118, -100 }, { -68, -44 }, { -12 - 0, -16 }, { 16, 12 }, { 44, 68 }, { 100, 118 } } do
		local a, b = seg[1], seg[2]
		if math.abs(b - a) > 6 then
			barrier(m, CFrame.new((a + b) / 2, 0, z0), math.abs(b - a))
		end
	end
	-- gate arch at x 0
	local gate = group(m, "Gate")
	for _, sx in { -1, 1 } do
		part(gate, "Pillar", Vector3.new(3, 18, 3), CFrame.new(sx * 11, 9, z0), C.gunmetal, M.DiamondPlate)
		local stripe = part(gate, "PillarStripe", Vector3.new(3.1, 1.2, 3.1), CFrame.new(sx * 11, 3, z0), C.yellow)
		stripe.CastShadow = false
	end
	part(gate, "Beam", Vector3.new(26, 2.4, 2.4), CFrame.new(0, 17.4, z0), C.gunmetal, M.Metal)
	local sign = part(gate, "Sign", Vector3.new(20, 4, 0.6), CFrame.new(0, 21, z0), C.dark, M.Metal)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.PixelsPerStud = 24
		g.LightInfluence = 0
		g.Parent = sign
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.Text = "SCRAPYARD"
		t.TextColor3 = C.yellow
		t.Parent = g
	end
	local trim = part(gate, "SignGlow", Vector3.new(20.4, 0.25, 0.7), CFrame.new(0, 18.9, z0), C.green)
	neon(trim, C.green)
	CollectionService:AddTag(trim, "ExoLight")
end

local function buildMound(parent: Instance)
	local m = group(parent, "Mound")
	local cx, cz, H, S = 0, 165, 8, 44
	-- plateau: a core block + rough stacked edges
	part(m, "Core", Vector3.new(S, H, S), CFrame.new(cx, H / 2, cz), C.dirtDark, M.Ground)
	part(m, "Top", Vector3.new(S - 2, 0.4, S - 2), CFrame.new(cx, H + 0.2, cz), C.concreteDark, M.Concrete)
	for i = 1, 10 do
		-- rough boulders round the west / north / south edges, clear of the
		-- ramps (x -14 .. 7) and the east bridge
		local side = rng:NextInteger(1, 3)
		local along = rng:NextNumber(-S / 2 + 6, S / 2 - 6)
		local off = S / 2 + rng:NextNumber(0.5, 2.5)
		local p = if side == 1 then Vector3.new(cx - off, 0, cz + along) elseif side == 2 then Vector3.new(cx + along, 0, cz + off) else Vector3.new(cx + along, 0, cz - off)
		if side == 1 or p.X - cx > 12 or p.X - cx < -18 then
			local h = rng:NextNumber(3, H + 1.5)
			part(m, "Boulder", Vector3.new(rng:NextNumber(4, 8), h, rng:NextNumber(4, 8)), CFrame.new(p.X, h / 2, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), C.concrete, M.Concrete)
		end
	end
	-- ramps north (toward the gate) and south
	ramp(m, "RampN", 14, Vector3.new(cx, 0, cz - S / 2 - 18), Vector3.new(cx, H + 0.4, cz - S / 2), C.concrete)
	ramp(m, "RampS", 12, Vector3.new(cx - 8, 0, cz + S / 2 + 18), Vector3.new(cx - 8, H + 0.4, cz + S / 2), C.concrete)
	-- hazard edges on the ramp tops
	for _, z in { cz - S / 2 + 0.3, cz + S / 2 - 0.3 } do
		local s = part(m, "EdgeStripe", Vector3.new(S - 2, 0.12, 0.6), CFrame.new(cx, H + 0.46, z), C.yellow)
		s.CastShadow = false
	end

	-- CRANE tower landmark (lattice) with a jib and a hook + magnet
	local crane = group(m, "Crane")
	local base = Vector3.new(cx + 12, H + 0.4, cz + 10)
	local TH = 46
	for _, o in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
		part(crane, "Leg", Vector3.new(0.8, TH, 0.8), CFrame.new(base + o + Vector3.new(0, TH / 2, 0)), C.yellow, M.Metal)
	end
	for y = 4, TH - 2, 7 do
		for _, f in { { Vector3.new(0, 0, -2), 0 }, { Vector3.new(0, 0, 2), 0 }, { Vector3.new(-2, 0, 0), 90 }, { Vector3.new(2, 0, 0), 90 } } do
			local o, yaw = f[1] :: Vector3, f[2] :: number
			part(crane, "Brace", Vector3.new(5.6, 0.4, 0.4), CFrame.new(base + o + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(yaw), math.rad(38)), C.yellow, M.Metal)
		end
	end
	part(crane, "Cab", Vector3.new(6, 4, 6), CFrame.new(base + Vector3.new(0, TH + 2, 0)), C.yellow, M.Metal)
	local window = part(crane, "Window", Vector3.new(5, 1.6, 0.2), CFrame.new(base + Vector3.new(0, TH + 2.6, -3.05)), rgb(40, 60, 70), M.Glass)
	window.Transparency = 0.2
	local jibLen = 40
	part(crane, "Jib", Vector3.new(2.4, 2.4, jibLen), CFrame.new(base + Vector3.new(0, TH + 5, -jibLen / 2 + 6)), C.yellow, M.Metal)
	part(crane, "Counter", Vector3.new(4, 4, 6), CFrame.new(base + Vector3.new(0, TH + 3.6, 9)), C.concreteDark, M.Concrete)
	local tip = base + Vector3.new(0, TH + 5, -jibLen + 8)
	part(crane, "Cable", Vector3.new(0.2, 20, 0.2), CFrame.new(tip - Vector3.new(0, 10, 0)), C.black, M.Metal)
	part(crane, "Magnet", Vector3.new(6, 1.6, 6), CFrame.new(tip - Vector3.new(0, 20.8, 0)), C.dark, M.Metal, Enum.PartType.Cylinder).CFrame =
		CFrame.new(tip - Vector3.new(0, 20.8, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local beacon = part(crane, "Beacon", Vector3.new(1, 1, 1), CFrame.new(base + Vector3.new(0, TH + 6.8, 0)), C.red, M.Neon, Enum.PartType.Ball)
	lightOn(beacon, C.red, 18, 2)
	beacon:SetAttribute("Blink", true)
	CollectionService:AddTag(beacon, "ScrapyardBlink")
	-- a dangling car body under the magnet (decor)
	local car = group(crane, "HangingCar")
	local carCF = CFrame.new(tip - Vector3.new(0, 24.2, 0)) * CFrame.Angles(0.15, 0.6, 0.08)
	part(car, "Body", Vector3.new(6, 2.4, 12), carCF, C.containers[2], M.CorrodedMetal)
	part(car, "Roof", Vector3.new(5, 1.6, 6), carCF * CFrame.new(0, 2, 0.5), C.containers[2]:Lerp(C.black, 0.2), M.CorrodedMetal)
end

local function buildContainers(parent: Instance)
	local m = group(parent, "ContainerStacks")
	-- three clusters; { x, z, yaw, level, doors }
	local list = {
		-- cluster A (north-east): two-high wall + stair stack
		{ 70, 95, 0, 0 },
		{ 79, 95, 0, 0 },
		{ 70, 95, 0, 1 },
		{ 92, 102, 90, 0, true },
		-- cluster B (east middle): the bridge stack (top at 8.5 = mound height)
		{ 64, 150, 0, 0, true },
		{ 73, 150, 0, 0 },
		{ 64, 172, 0, 0 },
		{ 73, 172, 0, 0 },
		{ 73, 150, 0, 1 },
		{ 73, 172, 0, 1 },
		{ 73, 161, 0, 2 },
		-- cluster C (east, near the fence): tall tower
		{ 104, 140, 0, 0 },
		{ 104, 162, 0, 0 },
		{ 104, 140, 0, 1 },
		{ 104, 162, 0, 1 },
		{ 104, 151, 90, 2 },
		{ 96, 190, 90, 0, true },
		{ 96, 190, 90, 1 },
	}
	for i, c in list do
		local x, z, yaw, level = c[1] :: number, c[2] :: number, c[3] :: number, c[4] :: number
		local color = C.containers[(i * 7) % #C.containers + 1]
		container(m, at(x, level * 8.5, z, yaw + (if level > 0 then rng:NextNumber(-3, 3) else 0)), color, c[5] == true)
	end
	-- stairs up cluster A (ramp onto the lower box, then up the stack)
	ramp(m, "StairA", 7, Vector3.new(79, 0, 120), Vector3.new(79, 8.5, 105.2), C.gunmetal, M.DiamondPlate)
	-- ramp onto cluster B from the south
	ramp(m, "StairB", 8, Vector3.new(64, 0, 200), Vector3.new(64, 8.5, 182.2), C.gunmetal, M.DiamondPlate)
	-- bridge cluster B top (8.5) -> the mound top (8.4)
	catwalk(m, Vector3.new(59.8, 8.5, 160), Vector3.new(22, 8.5, 160), 6, true)
	-- catwalk from cluster B second level to tower C second level (y 17)
	catwalk(m, Vector3.new(77.2, 17, 155), Vector3.new(99.8, 17, 155), 5, true)
	-- ramp from the B lower deck up to its second level
	ramp(m, "StairB2", 5, Vector3.new(66.5, 8.5, 175), Vector3.new(66.5, 17, 160.5), C.gunmetal, M.DiamondPlate)
end

local function buildPipes(parent: Instance)
	local m = group(parent, "PipeRun")
	local function pipe(a: Vector3, b: Vector3, dia: number, color: Color3)
		local d = b - a
		local p = part(m, "Pipe", Vector3.new(d.Magnitude, dia, dia), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, M.Metal, Enum.PartType.Cylinder)
		-- flanges
		local n = math.floor(d.Magnitude / 18)
		for i = 1, n do
			local q = a + d * (i / (n + 1))
			part(m, "Flange", Vector3.new(0.8, dia + 0.6, dia + 0.6), CFrame.lookAt(q, b) * CFrame.Angles(0, math.pi / 2, 0), C.gunmetal, M.Metal, Enum.PartType.Cylinder)
		end
		return p
	end
	-- ground pipes (half sunk)
	pipe(Vector3.new(-104, 1.6, 88), Vector3.new(-104, 1.6, 232), 5, rgb(120, 92, 64))
	pipe(Vector3.new(-92, 1.2, 96), Vector3.new(-92, 1.2, 190), 4, C.steel)
	-- elevated pipe on supports (walkable along its top), y 10
	local y = 10
	pipe(Vector3.new(-78, y, 92), Vector3.new(-78, y, 196), 4.5, rgb(70, 120, 110))
	for z = 98, 190, 16 do
		part(m, "Support", Vector3.new(1, y - 2, 1), CFrame.new(-80.5, (y - 2) / 2, z), C.gunmetal, M.Metal)
		part(m, "Support", Vector3.new(1, y - 2, 1), CFrame.new(-75.5, (y - 2) / 2, z), C.gunmetal, M.Metal)
		part(m, "Saddle", Vector3.new(6, 1, 1.4), CFrame.new(-78, y - 2.1, z), C.gunmetal, M.Metal)
	end
	-- a walk plank on top of the elevated pipe + ramp up to it
	part(m, "Plank", Vector3.new(2.6, 0.4, 100), CFrame.new(-78, y + 2.45, 144), C.gunmetal, M.DiamondPlate)
	ramp(m, "PipeRamp", 4, Vector3.new(-78, 0, 210), Vector3.new(-78, y + 2.65, 194), C.gunmetal, M.DiamondPlate)
	-- valve wheels
	for _, z in { 120, 168 } do
		part(m, "ValveStem", Vector3.new(0.6, 3, 0.6), CFrame.new(-104, 5.2, z), C.gunmetal, M.Metal)
		part(m, "Valve", Vector3.new(0.4, 3, 3), CFrame.new(-104, 6.8, z) * CFrame.Angles(0, 0, math.pi / 2), C.red, M.Metal, Enum.PartType.Cylinder)
	end
	-- a broken pipe end jutting up (landmark-ish)
	part(m, "BrokenPipe", Vector3.new(14, 4, 4), CFrame.new(-90, 6, 214) * CFrame.Angles(0, 0.4, math.rad(62)), C.rust, M.CorrodedMetal, Enum.PartType.Cylinder)
end

local function buildHulk(parent: Instance)
	-- a giant broken mech lying on its side (climbable landmark)
	local m = group(parent, "FallenHulk")
	local base = CFrame.new(-40, 0, 118) * CFrame.Angles(0, math.rad(-25), 0)
	local hull = rgb(98, 106, 62)
	local hullDark = rgb(78, 85, 48)
	part(m, "Torso", Vector3.new(16, 9, 12), base * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(8)), hull, M.CorrodedMetal)
	part(m, "ChestPlate", Vector3.new(12, 7, 1.4), base * CFrame.new(0, 5, -6.4) * CFrame.Angles(0, 0, math.rad(8)), hullDark, M.CorrodedMetal)
	part(m, "Head", Vector3.new(6, 5, 6), base * CFrame.new(-11, 3, 1) * CFrame.Angles(0.2, 0.3, math.rad(-20)), hull, M.CorrodedMetal)
	local eye = part(m, "Visor", Vector3.new(4, 0.8, 0.3), base * CFrame.new(-11.2, 3.6, -2.1) * CFrame.Angles(0.2, 0.3, math.rad(-20)), rgb(255, 80, 60))
	neon(eye, rgb(140, 40, 30))
	-- one arm reaching out along the ground, one sticking up
	part(m, "ArmUpper", Vector3.new(14, 4, 4), base * CFrame.new(3, 2, -12) * CFrame.Angles(0, 0.5, 0), hull, M.CorrodedMetal)
	part(m, "ArmLower", Vector3.new(12, 3.6, 3.6), base * CFrame.new(12, 1.8, -19) * CFrame.Angles(0, 0.9, 0), hullDark, M.CorrodedMetal)
	part(m, "Fist", Vector3.new(4.5, 4, 4.5), base * CFrame.new(17, 2, -24), hull, M.CorrodedMetal)
	part(m, "ArmUp", Vector3.new(4, 16, 4), base * CFrame.new(4, 12, 4) * CFrame.Angles(0.3, 0, -0.25), hullDark, M.CorrodedMetal)
	-- legs off to the side
	part(m, "Thigh", Vector3.new(14, 5.5, 5.5), base * CFrame.new(14, 2.75, 3) * CFrame.Angles(0, -0.2, 0), hull, M.CorrodedMetal)
	part(m, "Shin", Vector3.new(12, 5, 5), base * CFrame.new(25, 2.5, 7) * CFrame.Angles(0, -0.5, 0), hullDark, M.CorrodedMetal)
	part(m, "Foot", Vector3.new(5, 4, 8), base * CFrame.new(31, 2, 12) * CFrame.Angles(0, -0.5, 0.1), hull, M.CorrodedMetal)
	-- a ramp of debris onto its torso
	ramp(m, "DebrisRamp", 6, (base * CFrame.new(0, 0, 18)).Position, (base * CFrame.new(0, 8.6, 5.5)).Position, C.rustDark, M.CorrodedMetal)
	-- hazard stripes on the shoulder + a sparking hole
	part(m, "Hazard", Vector3.new(4, 0.3, 4), base * CFrame.new(-5, 9.6, 0) * CFrame.Angles(0, 0, math.rad(8)), C.yellow).CastShadow = false
end

local function buildFactory(parent: Instance)
	local m = group(parent, "RuinedFactory")
	local x0, x1, z0, z1 = -112, -36, 200, 244
	local wallC = rgb(160, 140, 120)
	local wallD = rgb(126, 108, 92)
	-- broken perimeter walls: segments with varying heights + gaps
	local function wallRun(a: Vector3, b: Vector3)
		local d = b - a
		local n = math.floor(d.Magnitude / 6)
		for i = 0, n - 1 do
			if rng:NextNumber() > 0.18 then
				local p = a + d * ((i + 0.5) / n)
				local h = if rng:NextNumber() < 0.3 then rng:NextNumber(2, 5) else rng:NextNumber(7, 14)
				part(m, "Wall", Vector3.new(d.Magnitude / n + 0.05, h, 1.6), CFrame.lookAt(p, p + d) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, h / 2, 0), if i % 2 == 0 then wallC else wallD, M.Brick)
			end
		end
	end
	wallRun(Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0))
	wallRun(Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	wallRun(Vector3.new(x1, 0, z0 + 12), Vector3.new(x1, 0, z1))
	-- pillars (some snapped)
	for x = x0 + 14, x1 - 10, 16 do
		for _, z in { z0 + 14, z1 - 12 } do
			local h = if rng:NextNumber() < 0.4 then rng:NextNumber(4, 8) else 16
			part(m, "Pillar", Vector3.new(2.4, h, 2.4), CFrame.new(x, h / 2, z), C.concrete, M.Concrete)
		end
	end
	-- collapsed roof slab: a tilted ramp from the floor up onto the pillars
	local slab = part(m, "RoofSlab", Vector3.new(16, 1, 30), CFrame.new(-60, 7.2, 222) * CFrame.Angles(math.rad(-27), 0, 0), C.concreteDark, M.Concrete)
	slab.Name = "CollapsedRoof"
	part(m, "RoofIntact", Vector3.new(22, 1, 18), CFrame.new(-60, 16.5, 236), C.concreteDark, M.Concrete)
	part(m, "RoofBeam", Vector3.new(30, 1.2, 1.2), CFrame.new(-90, 15.5, 214) * CFrame.Angles(0, 0, math.rad(-12)), C.rust, M.CorrodedMetal)
	-- SMOKESTACK landmark
	local sx, sz = -98, 232
	part(m, "StackBase", Vector3.new(10, 4, 10), CFrame.new(sx, 2, sz), wallD, M.Brick)
	part(m, "Stack", Vector3.new(58, 7, 7), CFrame.new(sx, 31, sz) * CFrame.Angles(0, 0, math.pi / 2), wallC, M.Brick, Enum.PartType.Cylinder)
	for _, y in { 20, 40, 56 } do
		part(m, "StackBand", Vector3.new(1.2, 7.6, 7.6), CFrame.new(sx, y, sz) * CFrame.Angles(0, 0, math.pi / 2), C.dark, M.Metal, Enum.PartType.Cylinder)
	end
	local top = part(m, "StackTop", Vector3.new(0.6, 6, 6), CFrame.new(sx, 60.2, sz) * CFrame.Angles(0, 0, math.pi / 2), C.black, M.Metal, Enum.PartType.Cylinder)
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(70, 70, 70)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 6
	smoke.Size = 6
	smoke.Parent = top
	local stackLight = part(m, "StackBeacon", Vector3.new(0.8, 0.8, 0.8), CFrame.new(sx, 61, sz + 3.6), C.red, M.Neon, Enum.PartType.Ball)
	lightOn(stackLight, C.red, 14, 1.5)
	CollectionService:AddTag(stackLight, "ScrapyardBlink")
	-- rubble
	scrapPile(m, Vector3.new(-80, 0, 228), 6, 10)
end

local function buildTrench(parent: Instance)
	local m = group(parent, "Trench")
	-- raised terrace (height 7) south-east, cut east-west by a 14-wide canyon
	local H = 7
	local xa, xb = 34, 118
	local function terrace(z0: number, z1: number)
		local w = xb - xa
		part(m, "Terrace", Vector3.new(w, H, z1 - z0), CFrame.new((xa + xb) / 2, H / 2, (z0 + z1) / 2), C.dirtDark, M.Ground)
		part(m, "TerraceTop", Vector3.new(w - 1, 0.3, z1 - z0 - 1), CFrame.new((xa + xb) / 2, H + 0.15, (z0 + z1) / 2), C.dirt, M.Ground)
	end
	terrace(204, 220)
	terrace(234, 249)
	-- canyon floor (darker) + rock walls along the cut
	part(m, "CanyonFloor", Vector3.new(xb - xa, 0.3, 14), CFrame.new((xa + xb) / 2, 0.08, 227), C.rustDark, M.Slate)
	for x = xa + 4, xb - 4, 9 do
		for _, z in { 220.6, 233.4 } do
			local h = rng:NextNumber(H - 1, H + 2.5)
			part(m, "Rock", Vector3.new(rng:NextNumber(5, 9), h, rng:NextNumber(1.5, 2.5)), CFrame.new(x, h / 2, z) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), C.concreteDark, M.Slate)
		end
	end
	-- ramps up onto the terraces from the yard (north + west) and into the canyon
	ramp(m, "TerraceRampN", 10, Vector3.new(60, 0, 190), Vector3.new(60, H + 0.3, 204), C.dirt, M.Ground)
	ramp(m, "TerraceRampW", 10, Vector3.new(20, 0, 241), Vector3.new(34, H + 0.3, 241), C.dirt, M.Ground)
	-- a plank bridge over the canyon
	part(m, "Bridge", Vector3.new(6, 0.6, 16), CFrame.new(86, H + 0.1, 227), rgb(110, 84, 58), M.WoodPlanks)
	for _, sx in { -1, 1 } do
		part(m, "BridgeRope", Vector3.new(0.2, 0.2, 16), CFrame.new(86 + sx * 3, H + 2.4, 227), rgb(70, 60, 50), M.Fabric)
	end
	-- wrecked car in the canyon
	local car = group(m, "Wreck")
	local cf = CFrame.new(70, 1.4, 227) * CFrame.Angles(0, 0.3, 0.25)
	part(car, "Body", Vector3.new(6, 2.4, 11), cf, C.containers[1], M.CorrodedMetal)
	part(car, "Roof", Vector3.new(5, 1.6, 5), cf * CFrame.new(0, 1.9, 0.5), C.containers[1]:Lerp(C.black, 0.3), M.CorrodedMetal)
end

local function buildDecor(parent: Instance)
	local m = group(parent, "Decor")
	local piles = {
		Vector3.new(-20, 0, 92),
		Vector3.new(30, 0, 108),
		Vector3.new(-60, 0, 160),
		Vector3.new(36, 0, 140),
		Vector3.new(-30, 0, 196),
		Vector3.new(20, 0, 200),
		Vector3.new(-110, 0, 180),
		Vector3.new(50, 0, 240),
		Vector3.new(110, 0, 80),
		Vector3.new(-56, 0, 86),
	}
	for _, p in piles do
		scrapPile(m, p, rng:NextNumber(4, 7), rng:NextInteger(9, 15))
	end
	-- lamp posts along the road and the yard
	for _, l in { { -10, 78, 90 }, { 10, 78, -90 }, { -10, 128, 90 }, { 10, 128, -90 }, { -60, 100, 0 }, { 56, 128, 0 }, { -40, 180, 180 }, { 40, 196, 0 }, { -100, 150, 90 }, { 100, 116, -90 } } do
		lamp(m, Vector3.new(l[1], 0, l[2]), l[3])
	end
	-- tyre stacks
	for _, p in { Vector3.new(-112, 0, 96), Vector3.new(112, 0, 230), Vector3.new(-20, 0, 236) } do
		for i = 0, 3 do
			part(m, "Tyre", Vector3.new(1.4, 4, 4), CFrame.new(p + Vector3.new(rng:NextNumber(-0.3, 0.3), 0.7 + i * 1.4, rng:NextNumber(-0.3, 0.3))) * CFrame.Angles(0, 0, math.pi / 2), C.black, M.Rubber, Enum.PartType.Cylinder)
		end
	end
	-- oil drums
	for i = 1, 14 do
		local p = Vector3.new(rng:NextNumber(-110, 110), 0, rng:NextNumber(80, 245))
		local col = if i % 3 == 0 then rgb(40, 80, 140) elseif i % 3 == 1 then rgb(170, 50, 40) else rgb(60, 110, 60)
		part(m, "Drum", Vector3.new(3, 2.2, 2.2), CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), col, M.Metal, Enum.PartType.Cylinder)
	end
end

------------------------------------------------------------------ bases

local function sign(parent: Instance, cf: CFrame, size: Vector3, text: string, name: string): Part
	local s = part(parent, name, size, cf, C.dark, M.Metal)
	local g = Instance.new("SurfaceGui")
	g.Name = "Gui"
	g.Face = Enum.NormalId.Front
	g.PixelsPerStud = 30
	g.LightInfluence = 0
	g.Parent = s
	local t = Instance.new("TextLabel")
	t.Name = "Owner"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = C.yellow
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = t
	return s
end

local function buildPlot(parent: Instance, index: number, x: number, z: number, size: number)
	local m = group(parent, "Plot" .. index)
	m:SetAttribute("PlotIndex", index)
	-- the plot faces +Z (the yard); the garage wall is on its north (-Z) edge
	local base = CFrame.new(x, 0, z)
	local half = size / 2
	local pad = part(m, "Pad", Vector3.new(size, 0.4, size), base * CFrame.new(0, 0.2, 0), rgb(92, 94, 98), M.Concrete)
	pad:SetAttribute("BasePad", true)
	-- yellow / black hazard edge
	for i, e in { { 0, -half }, { 0, half }, { -half, 0 }, { half, 0 } } do
		local alongX = i <= 2
		local s = part(m, "Edge", if alongX then Vector3.new(size, 0.1, 0.8) else Vector3.new(0.8, 0.1, size), base * CFrame.new(e[1], 0.45, e[2]), C.yellow)
		s.CastShadow = false
	end
	-- drop zone: glowing square in the middle
	local dz = part(m, "DropZone", Vector3.new(8, 0.08, 8), base * CFrame.new(0, 0.44, 2), C.green)
	neon(dz, rgb(30, 110, 60))
	dz.Transparency = 0.35
	dz.CanCollide = false
	local inner = part(m, "DropZoneInner", Vector3.new(7, 0.1, 7), base * CFrame.new(0, 0.45, 2), rgb(70, 72, 76), M.DiamondPlate)
	inner.CanCollide = false
	-- garage frame: back wall + two pillars + roof beam + half roof
	part(m, "BackWall", Vector3.new(size, 12, 1), base * CFrame.new(0, 6.4, -half + 0.5), rgb(78, 80, 84), M.CorrodedMetal)
	for _, sx in { -1, 1 } do
		part(m, "Pillar", Vector3.new(1.4, 12.5, 1.4), base * CFrame.new(sx * (half - 0.7), 6.6, -half + 8), C.yellow, M.Metal)
		part(m, "SideWall", Vector3.new(0.8, 12, 7), base * CFrame.new(sx * (half - 0.4), 6.4, -half + 4.2), rgb(78, 80, 84), M.CorrodedMetal)
	end
	part(m, "RoofBeam", Vector3.new(size, 1.2, 1.4), base * CFrame.new(0, 12.6, -half + 8), C.yellow, M.Metal)
	part(m, "Roof", Vector3.new(size + 1, 0.6, 9), base * CFrame.new(0, 13.1, -half + 4), rgb(62, 65, 70), M.CorrodedMetal)
	local roofLight = part(m, "RoofLight", Vector3.new(size - 4, 0.15, 0.5), base * CFrame.new(0, 12.75, -half + 6), C.green)
	neon(roofLight, C.green)
	lightOn(roofLight, rgb(200, 255, 210), 22, 1.2)
	-- owner sign above the back wall, facing the yard
	sign(m, base * CFrame.new(0, 15.6, -half + 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(16, 3.2, 0.4), "FREE PLOT", "Sign")

	-- EQUIP STATION (west side): a gantry with a clamp arm over a floor ring
	local eq = group(m, "EquipStation")
	local ex = base * CFrame.new(-half + 5.5, 0, -half + 6)
	part(eq, "Floor", Vector3.new(6, 0.3, 6), ex * CFrame.new(0, 0.55, 0), C.gunmetal, M.DiamondPlate)
	local ring = part(eq, "Ring", Vector3.new(0.2, 5.4, 5.4), ex * CFrame.new(0, 0.72, 0) * CFrame.Angles(0, 0, math.pi / 2), C.green, M.Neon, Enum.PartType.Cylinder)
	ring.CastShadow = false
	part(eq, "RingCover", Vector3.new(0.22, 4.8, 4.8), ex * CFrame.new(0, 0.73, 0) * CFrame.Angles(0, 0, math.pi / 2), C.gunmetal, M.DiamondPlate, Enum.PartType.Cylinder)
	for _, sx in { -1, 1 } do
		part(eq, "Post", Vector3.new(0.8, 10, 0.8), ex * CFrame.new(sx * 3, 5.5, -2.4), C.gunmetal, M.Metal)
	end
	part(eq, "Bar", Vector3.new(7, 0.8, 0.8), ex * CFrame.new(0, 10.2, -2.4), C.gunmetal, M.Metal)
	part(eq, "Arm", Vector3.new(0.6, 0.6, 3), ex * CFrame.new(0, 9.6, -1), C.steel, M.Metal)
	local clamp = part(eq, "Clamp", Vector3.new(2.4, 0.8, 1.4), ex * CFrame.new(0, 9.2, 0.4), C.yellow, M.Metal)
	clamp:SetAttribute("Clamp", true)
	local eqSign = sign(eq, ex * CFrame.new(0, 8, -2.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(5.6, 1.2, 0.2), "EQUIP", "Label")
	eqSign.CanCollide = false
	local eqPrompt = part(eq, "PromptAnchor", Vector3.new(1, 1, 1), ex * CFrame.new(0, 3, 0), C.dark)
	eqPrompt.Transparency = 1
	eqPrompt.CanCollide = false
	eqPrompt.CanQuery = false

	-- PART LOCKER (back wall, centre-left): a cabinet with shelves
	local lk = group(m, "Locker")
	local lx = base * CFrame.new(-3, 0, -half + 2)
	part(lk, "Cabinet", Vector3.new(8, 8, 2.4), lx * CFrame.new(0, 4.4, 0), rgb(50, 90, 140), M.Metal)
	for i = 0, 2 do
		part(lk, "Door", Vector3.new(2.4, 7.4, 0.2), lx * CFrame.new(-2.7 + i * 2.7, 4.4, 1.25), rgb(40, 74, 118), M.Metal)
		part(lk, "Vent", Vector3.new(1.6, 0.6, 0.1), lx * CFrame.new(-2.7 + i * 2.7, 7.2, 1.38), C.dark, M.Metal)
		local h = part(lk, "Handle", Vector3.new(0.2, 1, 0.2), lx * CFrame.new(-1.8 + i * 2.7, 4.4, 1.4), C.steel, M.Metal)
		h.CastShadow = false
	end
	local lkSign = sign(lk, lx * CFrame.new(0, 9.1, 1.21), Vector3.new(6, 1.2, 0.2), "PART LOCKER", "Label")
	lkSign.CanCollide = false
	local lkPrompt = part(lk, "PromptAnchor", Vector3.new(1, 1, 1), lx * CFrame.new(0, 3, 2.5), C.dark)
	lkPrompt.Transparency = 1
	lkPrompt.CanCollide = false
	lkPrompt.CanQuery = false

	-- CHARGER (east side): a pylon with a glowing coil and a cable to the pad
	local ch = group(m, "Charger")
	local cx = base * CFrame.new(half - 4.5, 0, -half + 5)
	part(ch, "Base", Vector3.new(4, 1, 4), cx * CFrame.new(0, 0.9, 0), C.gunmetal, M.DiamondPlate)
	part(ch, "Column", Vector3.new(2.2, 8, 2.2), cx * CFrame.new(0, 5.4, 0), C.dark, M.Metal)
	for i = 0, 3 do
		local coil = part(ch, "Coil", Vector3.new(0.5, 3, 3), cx * CFrame.new(0, 3.2 + i * 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), C.green, M.Neon, Enum.PartType.Cylinder)
		coil.CastShadow = false
		coil:SetAttribute("Phase", i * 0.12)
		CollectionService:AddTag(coil, "ExoLight")
	end
	local cap = part(ch, "Cap", Vector3.new(3, 1, 3), cx * CFrame.new(0, 9.9, 0), C.yellow, M.Metal)
	local chargeLight = part(ch, "ChargeLight", Vector3.new(1.2, 1.2, 1.2), cx * CFrame.new(0, 10.9, 0), C.green, M.Neon, Enum.PartType.Ball)
	lightOn(chargeLight, C.green, 14, 1.5)
	cap.CastShadow = true
	local chSign = sign(ch, cx * CFrame.new(0, 7.4, 1.15), Vector3.new(4.4, 1, 0.2), "CHARGER", "Label")
	chSign.CanCollide = false
	local chPrompt = part(ch, "PromptAnchor", Vector3.new(1, 1, 1), cx * CFrame.new(0, 3, 2.4), C.dark)
	chPrompt.Transparency = 1
	chPrompt.CanCollide = false
	chPrompt.CanQuery = false

	-- spawn point marker (invisible), facing the yard
	local sp = part(m, "SpawnPoint", Vector3.new(1, 1, 1), base * CFrame.new(0, 3.5, -2) * CFrame.Angles(0, math.pi, 0), C.dark)
	sp.Transparency = 1
	sp.CanCollide = false
	sp.CanQuery = false
	sp.CanTouch = false
end

------------------------------------------------------------------ spawns

local function marker(parent: Instance, name: string, pos: Vector3)
	local p = part(parent, name, Vector3.new(1, 1, 1), CFrame.new(pos), C.dark)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	count -= 1 -- not geometry
end

local function findSpawns(yard: Folder)
	local Y = cfg().Yard
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { yard }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { yard }
	local junk = Instance.new("Folder")
	junk.Name = "JunkSpawns"
	local crates = Instance.new("Folder")
	crates.Name = "CrateSpawns"

	local function clear(top: Vector3, w: number, h: number): boolean
		local found = workspace:GetPartBoundsInBox(CFrame.new(top + Vector3.new(0, h / 2 + 0.6, 0)), Vector3.new(w, h, w), overlap)
		return #found == 0
	end

	local junkPts: { Vector3 } = {}
	local cratePts: { Vector3 } = {}
	local x0, z0 = Y.Center.X - Y.Size.X / 2 + 6, Y.Center.Z - Y.Size.Y / 2 + 8
	for gx = x0, x0 + Y.Size.X - 12, 10 do
		for gz = z0, z0 + Y.Size.Y - 14, 10 do
			local p = Vector3.new(gx + rng:NextNumber(-3, 3), 80, gz + rng:NextNumber(-3, 3))
			local hit = workspace:Raycast(p, Vector3.new(0, -100, 0), params)
			if hit and hit.Normal.Y > 0.97 and hit.Position.Y < 20 then
				local top = hit.Position
				if clear(top, 7, 6) then
					local ok = true
					for _, q in junkPts do
						if (q - top).Magnitude < 9 then
							ok = false
							break
						end
					end
					if ok then
						table.insert(junkPts, top)
					end
				end
				if top.Y < 1 and clear(top, 15, 10) then
					local ok = true
					for _, q in cratePts do
						if (q - top).Magnitude < 34 then
							ok = false
							break
						end
					end
					if ok then
						table.insert(cratePts, top)
					end
				end
			end
		end
	end
	for _, p in junkPts do
		marker(junk, "JunkSpawn", p)
	end
	for _, p in cratePts do
		marker(crates, "CrateSpawn", p)
	end
	junk.Parent = yard
	crates.Parent = yard
	return #junkPts, #cratePts
end

------------------------------------------------------------------ build

function Scrapyard.build(): Folder
	local Y = cfg().Yard
	local old = workspace:FindFirstChild(Y.FolderName)
	if old then
		old:Destroy()
	end
	count = 0
	rng = Random.new(20261002)
	folder = Instance.new("Folder")
	folder.Name = Y.FolderName
	folder.Parent = workspace
	buildFloor(folder)
	buildEdge(folder)
	buildMound(folder)
	buildContainers(folder)
	buildPipes(folder)
	buildHulk(folder)
	buildFactory(folder)
	buildTrench(folder)
	buildDecor(folder)
	local nj, nc = findSpawns(folder)
	-- bases are built after the spawn search (their pads are outside the yard anyway)
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	bases.Parent = folder
	local B = cfg().Bases
	for i, x in B.X do
		buildPlot(bases, i, x, B.Z, B.PadSize)
	end
	folder:SetAttribute("PartCount", count)
	folder:SetAttribute("JunkSpawns", nj)
	folder:SetAttribute("CrateSpawns", nc)
	return folder
end

-- Runtime: keep the saved yard; build it only if the place has none.
function Scrapyard.ensure(): Folder
	local Y = cfg().Yard
	local f = workspace:FindFirstChild(Y.FolderName)
	if f and f:IsA("Folder") then
		return f
	end
	return Scrapyard.build()
end

return Scrapyard
