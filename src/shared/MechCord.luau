--!strict
-- The mech's power socket, floor outlet and power cord geometry.
--
--   * buildSocket(model): a plain, dark round socket recess with a green
--     charging ring, centered on the dark rear skirt just below the
--     backpack's exhaust caps (the stowed rifle sits off to the left),
--     welded to the Torso bone. It lives in its own "PowerSocket"
--     folder (not an Armor_* folder), so armor swaps keep it.
--     Its "PlugPoint" attachment sits on the socket face, X axis pointing out.
--   * buildOutlet(home, parent): the charging box the cord runs to, just off
--     the back edge of the mech's pad.
--   * layout(...): the cord's centerline while plugged in: out of the socket,
--     sagging down to the floor, then snaking along it to the outlet. The
--     snake is solved so the cord always keeps its length, so it pulls taut
--     as the mech stands up.
--   * buildCord / place: the ribbed hose itself, a chain of short cylinders
--     (the first one is the plug). CordController (client) adds the joints
--     and physics; the edit-mode preview just places it.

local MechConfig = require(script.Parent.MechConfig)

local MechCord = {}

local S = MechConfig.Scale
local C = MechConfig.Cord
local D = C.Diameter
local SEG = C.SegmentLength

MechCord.Group = "MechCord" -- collides with the world (Default) only
MechCord.Diameter = D
MechCord.SegmentLength = SEG

local HAZARD_YELLOW = Color3.fromRGB(255, 196, 0)
local HAZARD_BLACK = Color3.fromRGB(24, 24, 26)
local HOUSING = Color3.fromRGB(46, 48, 54)
local HOLE = Color3.fromRGB(10, 10, 12)
local RUBBER = Color3.fromRGB(30, 31, 35)
local RIB = Color3.fromRGB(46, 47, 53)
MechCord.GlowOff = Color3.fromRGB(28, 44, 34)
MechCord.GlowOn = Color3.fromRGB(70, 255, 120)

-- Cylinders run along their X axis; this turns X onto a CFrame's look vector.
local ALONG_LOOK = CFrame.Angles(0, math.pi / 2, 0)
-- ... and this turns X onto +Z (the mech's back, in bone space).
local ALONG_BACK = CFrame.Angles(0, -math.pi / 2, 0)

-- Socket, Torso bone space studs: on the rear skirt under the backpack
-- (MechBuilder buildChest: 3.4 x 1.4 at y -0.3, face z 3.3), below the
-- exhaust caps (x +-0.8, bottom y 0.55), centered, clear of the rifle (x -1.2).
local SOCKET_BONE = "Torso"
local SOCKET_ARMOR = "Armor_Chest"
local SOCKET_X = 0 -- centered on the back, between the exhaust caps
local SOCKET_Y = -0.3 * S
local RING_R = 0.55 * S -- the plug's hazard collar (~0.94)
local HOUSING_R = RING_R + 0.18 -- socket housing, inside the skirt (~1.12)
local GLOW_OUT = RING_R + 0.1 -- green charging ring, peeking out round the collar
local HOLE_R = RING_R * 0.6 -- plug hole (~0.56)
local GLOW_R = HOLE_R + 0.12 -- inner edge of the collar's hazard tiles
local RING_SEGMENTS = 14

local function newPart(shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	return p
end

-- Rear-most armor face (bone space z, studs) under the socket's footprint.
local function rearFace(model: Model, bone: BasePart): number
	local back = 3.3 * S -- the rear skirt, if nothing is found
	local found = false
	local folder = model:FindFirstChild(SOCKET_ARMOR)
	if not folder then
		return back
	end
	for _, d in folder:GetDescendants() do
		if not d:IsA("Weld") or d.Part0 ~= bone or not d.Part1 then
			continue
		end
		local cf = d.C0 * d.C1:Inverse()
		local half = (d.Part1 :: BasePart).Size / 2
		local r = cf.Rotation
		-- axis-aligned extents of the (possibly rotated) box in bone space
		local ext = Vector3.new(
			math.abs(r.XVector.X) * half.X + math.abs(r.YVector.X) * half.Y + math.abs(r.ZVector.X) * half.Z,
			math.abs(r.XVector.Y) * half.X + math.abs(r.YVector.Y) * half.Y + math.abs(r.ZVector.Y) * half.Z,
			math.abs(r.XVector.Z) * half.X + math.abs(r.YVector.Z) * half.Y + math.abs(r.ZVector.Z) * half.Z
		)
		local p = cf.Position
		local overlapsX = p.X - ext.X < SOCKET_X + HOUSING_R and p.X + ext.X > SOCKET_X - HOUSING_R
		local overlapsY = p.Y - ext.Y < SOCKET_Y + HOUSING_R and p.Y + ext.Y > SOCKET_Y - HOUSING_R
		if overlapsX and overlapsY then
			local z = p.Z + ext.Z
			if not found or z > back then
				back, found = z, true
			end
		end
	end
	return back
end

-- Builds (or rebuilds) the rear power socket. Returns the PowerSocket folder.
function MechCord.buildSocket(model: Model): Folder
	local old = model:FindFirstChild("PowerSocket")
	if old then
		old:Destroy()
	end
	local bone = model:FindFirstChild(SOCKET_BONE) :: BasePart
	local folder = Instance.new("Folder")
	folder.Name = "PowerSocket"

	local z0 = rearFace(model, bone)
	local function add(name: string, part: BasePart, offset: CFrame)
		part.Name = name
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CollisionGroup = "MechArmor"
		part.CFrame = bone.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0 = bone
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part
		part.Parent = folder
	end
	local function at(z: number, x: number?, y: number?): CFrame
		return CFrame.new(SOCKET_X + (x or 0), SOCKET_Y + (y or 0), z0 + z)
	end

	-- plain dark housing sunk into the skirt (face 0.25 proud of it), a neon
	-- ring 0.05 proud of that (green while charging, its light spilling onto
	-- the mech and floor) and the black hole 0.06 proud of the ring. The
	-- yellow / black hazard collar is on the plug.
	add("Housing", newPart(Enum.PartType.Cylinder, Vector3.new(0.4, HOUSING_R * 2, HOUSING_R * 2), HOUSING, Enum.Material.Metal), at(0.05) * ALONG_BACK)
	local glow = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, GLOW_OUT * 2, GLOW_OUT * 2), MechCord.GlowOff, Enum.Material.Neon)
	add("Glow", glow, at(0.25) * ALONG_BACK)
	local light = Instance.new("PointLight")
	light.Color = MechCord.GlowOn
	light.Range = 6
	light.Brightness = 0
	light.Shadows = false
	light.Parent = glow
	local hole = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, HOLE_R * 2, HOLE_R * 2), HOLE, Enum.Material.SmoothPlastic)
	add("Hole", hole, at(0.3) * ALONG_BACK)
	local plugPoint = Instance.new("Attachment")
	plugPoint.Name = "PlugPoint"
	plugPoint.Position = Vector3.new(0.06, 0, 0) -- hole face; X points out of the socket
	plugPoint.Parent = hole

	folder.Parent = model
	return folder
end

-- The socket's plug attachment, if the mech has a socket.
function MechCord.plugPoint(model: Model): Attachment?
	local folder = model:FindFirstChild("PowerSocket")
	local hole = folder and folder:FindFirstChild("Hole")
	return hole and hole:FindFirstChild("PlugPoint") :: Attachment?
end

-- Outlet box CFrame for a mech parked at `home` (ground level, facing the mech's way).
-- The box faces the mech (its -Z toward the pad center).
function MechCord.outletCFrame(home: CFrame): CFrame
	local pos = (home * CFrame.new(C.OutletSide, 0, C.OutletDistance)).Position
	return CFrame.lookAt(pos, Vector3.new(home.Position.X, pos.Y, home.Position.Z))
end

local OUTLET_SIZE = Vector3.new(3.2, 2.4, 2.2)
local PORT_Y = 0.9

-- Where the cord enters the outlet (world).
function MechCord.outletPort(home: CFrame): Vector3
	return (MechCord.outletCFrame(home) * CFrame.new(0, PORT_Y, -OUTLET_SIZE.Z / 2 - 0.35)).Position
end

-- The charging box behind a pad: dark metal with a hazard-striped lid, a
-- status light and a port collar facing the mech.
function MechCord.buildOutlet(home: CFrame, parent: Instance): Model
	local cf = MechCord.outletCFrame(home)
	local model = Instance.new("Model")
	model.Name = "PowerOutlet"
	local function add(name: string, part: BasePart, offset: CFrame, collide: boolean)
		part.Name = name
		part.Anchored = true
		part.CanCollide = collide
		part.CFrame = cf * offset
		part.Parent = model
	end
	local h = OUTLET_SIZE.Y
	add("Box", newPart(Enum.PartType.Block, OUTLET_SIZE, HOUSING, Enum.Material.DiamondPlate), CFrame.new(0, h / 2, 0), true)
	add("Base", newPart(Enum.PartType.Block, OUTLET_SIZE + Vector3.new(0.5, -h + 0.3, 0.5), HAZARD_BLACK, Enum.Material.Metal), CFrame.new(0, 0.15, 0), true)
	-- hazard stripes across the lid
	local n = 6
	for i = 1, n do
		local w = OUTLET_SIZE.X / n
		local stripe = newPart(Enum.PartType.Block, Vector3.new(w, 0.12, OUTLET_SIZE.Z + 0.1), if i % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK, Enum.Material.SmoothPlastic)
		add("Stripe", stripe, CFrame.new(-OUTLET_SIZE.X / 2 + w * (i - 0.5), h + 0.06, 0), false)
	end
	-- port collar where the cord goes in, and a green "live" lamp above it
	local front = -OUTLET_SIZE.Z / 2
	add("Collar", newPart(Enum.PartType.Cylinder, Vector3.new(0.5, D * 1.6, D * 1.6), HAZARD_BLACK, Enum.Material.Metal), CFrame.new(0, PORT_Y, front - 0.2) * ALONG_BACK, false)
	add("CollarRing", newPart(Enum.PartType.Cylinder, Vector3.new(0.3, D * 1.9, D * 1.9), HAZARD_YELLOW, Enum.Material.SmoothPlastic), CFrame.new(0, PORT_Y, front - 0.1) * ALONG_BACK, false)
	local lamp = newPart(Enum.PartType.Block, Vector3.new(0.9, 0.35, 0.1), MechCord.GlowOn, Enum.Material.Neon)
	add("Lamp", lamp, CFrame.new(0, h - 0.5, front - 0.06), false)
	model.PrimaryPart = model:FindFirstChild("Box") :: BasePart
	model.Parent = parent
	return model
end

-- Number of segments a cord has (fixed; the layout keeps the length).
function MechCord.segmentCount(): number
	local dist = math.sqrt(C.OutletDistance ^ 2 + C.OutletSide ^ 2)
	return math.ceil((dist + C.HangLength) / SEG)
end

-- Farthest the socket (PlugPoint) can be from the outlet port before the
-- taut cord rips the plug out.
function MechCord.reach(): number
	return MechCord.segmentCount() * SEG - C.Slack
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function polyLength(pts: { Vector3 }): number
	local len = 0
	for i = 2, #pts do
		len += (pts[i] - pts[i - 1]).Magnitude
	end
	return len
end

-- Resamples a polyline into count + 1 evenly spaced points.
local function resample(pts: { Vector3 }, count: number): { Vector3 }
	local total = polyLength(pts)
	local step = total / count
	local out = { pts[1] }
	local seg, segStart = 2, 0
	for k = 1, count - 1 do
		local target = step * k
		while seg <= #pts do
			local l = (pts[seg] - pts[seg - 1]).Magnitude
			if segStart + l >= target or seg == #pts then
				local t = if l > 1e-6 then math.clamp((target - segStart) / l, 0, 1) else 0
				table.insert(out, pts[seg - 1]:Lerp(pts[seg], t))
				break
			end
			segStart += l
			seg += 1
		end
	end
	table.insert(out, pts[#pts])
	return out
end

-- Centerline (count + 1 points) of a cord plugged in at `plug` (the socket's
-- PlugPoint: position on the socket face, X out of it) running to `port`.
-- floorAt(p) gives the ground height under a point.
function MechCord.layout(plug: CFrame, port: Vector3, count: number, floorAt: (Vector3) -> number): { Vector3 }
	local r = D / 2
	local out = plug.XVector
	local s = plug.Position - out * 0.3 -- the plug's tip sits inside the socket
	local flat = Vector3.new(port.X - s.X, 0, port.Z - s.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(out.X, 0, out.Z).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)

	-- hanging part: out of the socket, then down to a touchdown point
	local h = s.Y - (floorAt(s) + r)
	local reach = math.clamp(h * 0.75, 1.2, 7)
	local t0 = s + dir * reach
	local touch = Vector3.new(t0.X, floorAt(t0) + r, t0.Z)
	-- the plug runs straight out along the socket's axis (so it seats flush and
	-- concentric), then the cord arcs away, clear of the back
	local q = s + out * (SEG + 0.6)
	local p1 = q + out * 1.8
	local p2 = touch - dir * math.clamp(h * 0.45, 0.4, 2.5)
	local hang: { Vector3 } = { s }
	for i = 0, 12 do
		table.insert(hang, bezier(q, p1, p2, touch, i / 12))
	end

	-- floor part: an S-bend whose amplitude takes up the spare length
	local n = 18
	local bases: { Vector3 } = {}
	for i = 1, n do
		local u = i / n
		local b = touch:Lerp(port, u)
		local y = floorAt(b) + r
		y += (port.Y - y) * smooth((u - 0.82) / 0.18)
		table.insert(bases, Vector3.new(b.X, y, b.Z))
	end
	local function build(amp: number): { Vector3 }
		local pts = table.clone(hang)
		for i, b in bases do
			local u = i / n
			table.insert(pts, b + side * (amp * math.sin(u * math.pi * 2) * math.sin(u * math.pi)))
		end
		return pts
	end
	local want = count * SEG
	local lo, hi = 0, 7
	local pts = build(0)
	if polyLength(pts) < want then
		if polyLength(build(hi)) < want then
			pts = build(hi)
		else
			for _ = 1, 14 do
				local m = (lo + hi) / 2
				if polyLength(build(m)) < want then
					lo = m
				else
					hi = m
				end
			end
			pts = build((lo + hi) / 2)
		end
	end
	return resample(pts, count)
end

-- The cord lying on the floor between `from` (where the plug ends up) and the port.
function MechCord.restLayout(from: Vector3, port: Vector3, count: number, floorAt: (Vector3) -> number): { Vector3 }
	local flat = Vector3.new(port.X - from.X, 0, port.Z - from.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
	local plug = CFrame.fromMatrix(Vector3.new(from.X, floorAt(from) + D / 2, from.Z) + dir * 0.3, dir, Vector3.yAxis)
	return MechCord.layout(plug, port, count, floorAt)
end

export type Rib = { part: BasePart, weld: Weld, frac: number }
export type Cord = {
	folder: Folder,
	segments: { BasePart }, -- [1] is the plug
	lengths: { number }, -- nominal lengths
	ribs: { { Rib } }, -- per segment
}

-- Builds the hose parts (unplaced): anchored segments with welded ribs.
function MechCord.buildCord(name: string, count: number, parent: Instance): Cord
	local folder = Instance.new("Folder")
	folder.Name = name
	local segments, lengths, ribs = {}, {}, {}
	local function rib(seg: BasePart, list: { Rib }, frac: number, dia: number, len: number, color: Color3, material: Enum.Material)
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(len, dia, dia), color, material)
		p.Name = "Rib"
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		local weld = Instance.new("Weld")
		weld.Part0 = seg
		weld.Part1 = p
		weld.C0 = CFrame.new(frac * seg.Size.X, 0, 0)
		weld.Parent = p
		p.CFrame = seg.CFrame * weld.C0
		p.Parent = seg
		table.insert(list, { part = p, weld = weld, frac = frac })
	end
	for i = 1, count do
		local plug = i == 1
		local dia = if plug then D * 1.1 else D
		local seg = newPart(Enum.PartType.Cylinder, Vector3.new(SEG, dia, dia), if plug then HOUSING else RUBBER, if plug then Enum.Material.Metal else Enum.Material.Rubber)
		seg.Name = if plug then "Plug" else "Segment"
		seg.Anchored = true
		seg.CanCollide = false
		local list: { Rib } = {}
		if plug then
			-- the tip (start, -X) goes 0.3 into the socket: brass pins; then the
			-- yellow / black hazard collar that sits against the socket face
			-- (0.05 off it), a black band and a strain relief
			for _, z in { -0.22, 0.22 } do
				local pin = newPart(Enum.PartType.Block, Vector3.new(0.4, 0.14, 0.26), Color3.fromRGB(214, 176, 70), Enum.Material.Metal)
				pin.Name = "Pin"
				pin.Anchored = false
				pin.Massless = true
				pin.CanCollide = false
				pin.CanQuery = false
				local weld = Instance.new("Weld")
				weld.Part0 = seg
				weld.Part1 = pin
				weld.C0 = CFrame.new(-SEG / 2 - 0.12, 0, z)
				weld.Parent = pin
				pin.Parent = seg
			end
			local collarX = -SEG / 2 + 0.3 + 0.05 + 0.1
			local function fixed(name: string, part: BasePart, c0: CFrame, collide: boolean)
				part.Name = name
				part.Anchored = false
				part.Massless = true
				part.CanCollide = collide
				part.CanQuery = false
				local weld = Instance.new("Weld")
				weld.Part0 = seg
				weld.Part1 = part
				weld.C0 = c0
				weld.Parent = part
				part.Parent = seg
			end
			fixed("Collar", newPart(Enum.PartType.Cylinder, Vector3.new(0.2, RING_R * 2, RING_R * 2), HAZARD_BLACK, Enum.Material.Metal), CFrame.new(collarX, 0, 0), true)
			local mid = (GLOW_R + RING_R) / 2
			local tileW = 2 * math.pi * mid / RING_SEGMENTS * 1.02
			for k = 1, RING_SEGMENTS do
				local a = (k - 0.5) / RING_SEGMENTS * math.pi * 2
				local color = if k % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK
				local tile = newPart(Enum.PartType.Block, Vector3.new(0.08, RING_R - GLOW_R, tileW), color, Enum.Material.SmoothPlastic)
				-- on the collar's outer face, 0.01 proud of it
				fixed("Hazard", tile, CFrame.new(collarX + 0.15, math.cos(a) * mid, math.sin(a) * mid) * CFrame.Angles(a, 0, 0), false)
			end
			rib(seg, list, 0.3, D * 1.3, 0.2, HAZARD_BLACK, Enum.Material.SmoothPlastic)
			rib(seg, list, 0.5, D * 1.05, 0.3, RUBBER, Enum.Material.Rubber)
		else
			rib(seg, list, -0.5, D * 1.24, 0.2, RIB, Enum.Material.SmoothPlastic)
			rib(seg, list, 0, D * 1.18, 0.16, RIB, Enum.Material.SmoothPlastic)
		end
		seg.Parent = folder
		segments[i] = seg
		lengths[i] = SEG
		ribs[i] = list
	end
	folder.Parent = parent
	return { folder = folder, segments = segments, lengths = lengths, ribs = ribs }
end

-- Segment CFrames and lengths for a centerline: segment i runs between
-- points i and i + 1. With `stretch`, segments take the exact spacing (a
-- taut or slack cord; the plug always keeps its length, starting at the
-- socket); otherwise each keeps its own length, centered on its span.
function MechCord.frames(cord: Cord, pts: { Vector3 }, stretch: boolean): ({ CFrame }, { number })
	local cfs, lens = {}, {}
	for i, seg in cord.segments do
		local a, b = pts[i], pts[i + 1]
		local len = if a and b then (b - a).Magnitude else 0
		if len < 1e-3 then
			cfs[i], lens[i] = seg.CFrame, seg.Size.X
			continue
		end
		local want = if stretch and i > 1 then len else cord.lengths[i]
		local mid = if i == 1 then a + (b - a).Unit * (want / 2) else (a + b) / 2
		cfs[i] = CFrame.lookAt(mid, b) * ALONG_LOOK
		lens[i] = want
	end
	return cfs, lens
end

-- Sets segment i's length (its ribs keep their places along it).
function MechCord.setLength(cord: Cord, i: number, len: number)
	local seg = cord.segments[i]
	if math.abs(seg.Size.X - len) > 0.005 then
		seg.Size = Vector3.new(len, seg.Size.Y, seg.Size.Z)
		for _, rib in cord.ribs[i] do
			rib.weld.C0 = CFrame.new(rib.frac * len, 0, 0)
		end
	end
end

-- Moves the (anchored) segments onto a centerline; see frames().
function MechCord.place(cord: Cord, pts: { Vector3 }, stretch: boolean)
	local cfs, lens = MechCord.frames(cord, pts, stretch)
	for i in cord.segments do
		MechCord.setLength(cord, i, lens[i])
	end
	workspace:BulkMoveTo(cord.segments, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Restores every segment's own length (before handing the cord to physics).
function MechCord.resetLengths(cord: Cord)
	for i in cord.segments do
		MechCord.setLength(cord, i, cord.lengths[i])
	end
end


return MechCord
