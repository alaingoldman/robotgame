--!strict
-- The WTK-99's wall charger and its twin power hoses (geometry only).
--
--   * buildCharger(home, parent): a heavy armored charger box standing on the
--     back edge of the pad behind the walker (MechConfig.Type99Charger.Offset),
--     facing the mech: beveled slate body, a recessed square socket panel with an
--     olive housing and two hose glands, a status screen (SurfaceGui), green
--     light strips, a connector cradle, hazard band, vents, a winch drum and
--     an amber beacon on top. Anchored and solid to players.
--   * portCFrame(model): the hull's "CablePort" face (X out of the hull),
--     read from the part at runtime wherever the builder puts it.
--   * buildConnector / placeConnector: the chunky square connector at the
--     mech end (latch lever, hazard band, status LED, two strain-relief boots).
--   * buildHose / placeHose / hose(...): a smooth thick hose (cylinders with
--     ball joints) laid along a sagging Bezier whose sag is solved so the
--     hose has a given length; it flattens onto the floor when slack.
-- Type99CableController (client) animates them; MechService.buildPreview
-- places them statically; MechBattery uses portCFrame / glandCenter / reach.

local PhysicsService = game:GetService("PhysicsService")

local MechConfig = require(script.Parent.MechConfig)
local MechTypes = require(script.Parent.MechTypes)

local Type99Charger = {}

local CFG = MechConfig.Type99Charger
local D = CFG.Diameter
local R = D / 2

Type99Charger.TypeId = "Type99"
Type99Charger.Group = "MechCord" -- collides with the world only (see MechService)
-- invisible block round the charger that only walker roots collide with, so a
-- walker can't back up over / through its charger (MechService registers it)
Type99Charger.BlockGroup = "ChargerBlock"
local BLOCK_REACH = 4.6 -- reaches out toward the walker past the box (before the charger's ScaleTo CS)
local BLOCK_MARGIN = 1.2
local BLOCK_HEIGHT = 20 -- x CS: above the walker's root box
Type99Charger.Diameter = D

local SLATE = Color3.fromRGB(92, 99, 102)
local SLATE_DARK = Color3.fromRGB(70, 76, 80)
local OLIVE = Color3.fromRGB(98, 106, 62)
local OLIVE_DARK = Color3.fromRGB(74, 80, 46)
local DARK = Color3.fromRGB(40, 42, 46)
local HOLE = Color3.fromRGB(12, 12, 14)
local STEEL = Color3.fromRGB(170, 174, 178)
local HAZARD_YELLOW = Color3.fromRGB(255, 196, 0)
local HAZARD_BLACK = Color3.fromRGB(24, 24, 26)
local HOSE = Color3.fromRGB(33, 34, 37)
local SCREEN_GLASS = Color3.fromRGB(14, 22, 18)
Type99Charger.GlowOn = Color3.fromRGB(70, 255, 120)
Type99Charger.GlowStandby = Color3.fromRGB(255, 150, 30)
Type99Charger.GlowOff = Color3.fromRGB(34, 40, 36)
Type99Charger.BeaconOn = Color3.fromRGB(255, 160, 20)
Type99Charger.BeaconOff = Color3.fromRGB(90, 60, 20)

local ALONG_LOOK = CFrame.Angles(0, math.pi / 2, 0) -- cylinder X onto a CFrame's look vector
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- cylinder X onto Z
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2) -- cylinder X onto Y

-- Charger box, charger frame (origin on the ground at its center, -Z faces the mech).
local W, D_BOX = 5.4, 3.6
local PLINTH_H = 0.5
local BODY_TOP = 8.0
local BEVEL = 0.45
local FRONT = -D_BOX / 2
local PANEL_Y = 5.0
local GLAND_X = 0.48
local GLAND_FRONT = FRONT - 0.55
local PARK_Y = 2.8
-- the box is built in the units above, then scaled up by this (Model:ScaleTo)
local CS = 1.3
local CONN_HALF_H = 0.66 -- connector body half height (unscaled, it matches the port)

-- Whether a mech (or type id) uses this charger.
function Type99Charger.applies(modelOrId: Instance | string): boolean
	local id = if typeof(modelOrId) == "string" then modelOrId else MechTypes.idOf(modelOrId :: Instance)
	return id == Type99Charger.TypeId
end

-- Charger CFrame (ground level, facing the mech) for a mech parked at `home`.
function Type99Charger.chargerCFrame(home: CFrame): CFrame
	local pos = (home * CFrame.new(CFG.Offset)).Position
	local at = Vector3.new(home.Position.X, pos.Y, home.Position.Z)
	return if (at - pos).Magnitude > 1e-3 then CFrame.lookAt(pos, at) else home
end

-- Where hose i (1, 2) leaves its gland, and the gland's outward direction.
function Type99Charger.glandEnd(chargerCF: CFrame, i: number): (Vector3, Vector3)
	local x = if i == 1 then -GLAND_X else GLAND_X
	return (chargerCF * CFrame.new(x * CS, PANEL_Y * CS, GLAND_FRONT * CS)).Position, chargerCF.LookVector
end

-- Middle of the socket panel's glands (world), for reach checks.
function Type99Charger.glandCenter(home: CFrame): Vector3
	return (Type99Charger.chargerCFrame(home) * CFrame.new(0, PANEL_Y * CS, GLAND_FRONT * CS)).Position
end

-- The connector parked in the charger's cradle (X out toward the mech).
function Type99Charger.parkCFrame(home: CFrame): CFrame
	local cf = Type99Charger.chargerCFrame(home)
	local pos = (cf * CFrame.new(0, (PARK_Y - 0.69) * CS + CONN_HALF_H + 0.02, FRONT * CS - 0.05)).Position
	return CFrame.fromMatrix(pos, cf.LookVector, cf.UpVector)
end

-- Keeps a flying connector (a ball of radius r at `pos`) out of the charger
-- box: pushes it out through the nearest face and bounces its velocity.
function Type99Charger.collide(chargerCF: CFrame, pos: Vector3, vel: Vector3, r: number): (Vector3, Vector3, boolean)
	local lp = chargerCF:PointToObjectSpace(pos)
	local hx, hz = (W / 2 + 0.4) * CS + r, (D_BOX / 2 + 0.4) * CS + r
	local top = (BODY_TOP + BEVEL + 1.5) * CS + r
	if math.abs(lp.X) >= hx or math.abs(lp.Z) >= hz or lp.Y >= top then
		return pos, vel, false
	end
	local lv = chargerCF:VectorToObjectSpace(vel)
	local dx, dz, dy = hx - math.abs(lp.X), hz - math.abs(lp.Z), top - lp.Y
	if dy <= dx and dy <= dz then
		lp = Vector3.new(lp.X, top, lp.Z)
		lv = Vector3.new(lv.X * 0.6, math.abs(lv.Y) * 0.3, lv.Z * 0.6)
	elseif dz <= dx then
		local sz = if lp.Z < 0 then -1 else 1
		lp = Vector3.new(lp.X, lp.Y, sz * hz)
		lv = Vector3.new(lv.X * 0.6, lv.Y, sz * math.abs(lv.Z) * 0.3)
	else
		local sx = if lp.X < 0 then -1 else 1
		lp = Vector3.new(sx * hx, lp.Y, lp.Z)
		lv = Vector3.new(sx * math.abs(lv.X) * 0.3, lv.Y, lv.Z * 0.6)
	end
	return chargerCF * lp, chargerCF:VectorToWorldSpace(lv), true
end

-- Port to socket distance where the connector ejects.
function Type99Charger.reach(): number
	return CFG.Reach
end

-- Hose length the winch pays out for a port to gland distance: a good sag
-- close by, pulling straighter as the mech moves off.
function Type99Charger.hoseLength(dist: number): number
	return math.min(dist * 1.18 + 2, CFG.Reach + 1)
end

-- The hull's cable port face (X pointing out of the hull), if the mech has one.
function Type99Charger.portPart(model: Model): BasePart?
	local chest = model:FindFirstChild("Armor_Chest")
	local part = chest and chest:FindFirstChild("CablePort")
	return if part and part:IsA("BasePart") then part else nil
end

-- Nothing about the port is hardcoded: an Attachment named "CablePoint" in
-- the part (X out) wins; otherwise it's the part face pointing away from the
-- Hull bone's origin (the outward face of a block on the hull's skin).
function Type99Charger.portCFrame(model: Model): CFrame?
	local part = Type99Charger.portPart(model)
	if not part then
		return nil
	end
	local point = part:FindFirstChild("CablePoint")
	if point and point:IsA("Attachment") then
		return point.WorldCFrame
	end
	local cf = part.CFrame
	local hull = model:FindFirstChild("Hull")
	local ref = if hull and hull:IsA("BasePart") then hull.Position else model:GetPivot().Position
	local rel = cf:VectorToObjectSpace(part.Position - ref)
	local ax, ay, az = math.abs(rel.X), math.abs(rel.Y), math.abs(rel.Z)
	local out: Vector3
	if ax >= ay and ax >= az then
		out = Vector3.new(math.sign(rel.X), 0, 0)
	elseif az >= ay then
		out = Vector3.new(0, 0, math.sign(rel.Z))
	else
		out = Vector3.new(0, math.sign(rel.Y), 0)
	end
	local pos = cf * (out * part.Size / 2)
	local outW = cf:VectorToWorldSpace(out)
	local up = if math.abs(out.Y) > 0.5 then cf.LookVector else cf.UpVector
	return CFrame.fromMatrix(pos, outW, up)
end

local function newPart(shape: Enum.PartType | string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = shape :: Enum.PartType
		p = part
	end
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	return p
end

local BLOCK, CYL, BALL = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball
local METAL, SMOOTH, NEON = Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Neon

-- Builds the charger unit for a pad. Named parts the client drives:
-- Screen (SurfaceGui "Display" > "Status" / "Percent"), StripL / StripR,
-- Beacon, Drum, Gland1 / Gland2, GlandLight (PointLight "Glow").
function Type99Charger.buildCharger(home: CFrame, parent: Instance): Model
	local cf = Type99Charger.chargerCFrame(home)
	local model = Instance.new("Model")
	model.Name = "Type99Charger"
	model:SetAttribute("Home", home)
	local function add(name: string, shape: Enum.PartType | string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material, collide: boolean, rot: CFrame?): BasePart
		local p = newPart(shape, size, color, material)
		p.Name = name
		p.Anchored = true
		p.CanCollide = collide
		p.CanQuery = collide
		p.CFrame = cf * CFrame.new(pos) * (rot or CFrame.identity)
		p.Parent = model
		return p
	end

	-- plinth and the beveled body: two crossed blocks + four corner wedges
	add("Plinth", BLOCK, Vector3.new(W + 0.8, PLINTH_H, D_BOX + 0.8), Vector3.new(0, PLINTH_H / 2, 0), DARK, Enum.Material.DiamondPlate, true)
	local bodyH = BODY_TOP - PLINTH_H
	local midY = PLINTH_H + bodyH / 2
	add("Body", BLOCK, Vector3.new(W, bodyH, D_BOX - BEVEL * 2), Vector3.new(0, midY, 0), SLATE, SMOOTH, true)
	add("Body", BLOCK, Vector3.new(W - BEVEL * 2, bodyH, D_BOX), Vector3.new(0, midY, 0), SLATE, SMOOTH, true)
	local r0 = CFrame.Angles(0, 0, math.pi / 2) -- wedge extruded along Y
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local rot = r0
			for _, yaw in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
				local r = CFrame.Angles(0, yaw, 0) * r0
				local inner = r:VectorToWorldSpace(Vector3.new(0, -1, 1)) -- the right-angle corner
				if math.sign(math.round(inner.X)) == -sx and math.sign(math.round(inner.Z)) == -sz then
					rot = r
					break
				end
			end
			local pos = Vector3.new(sx * (W / 2 - BEVEL / 2), midY, sz * (D_BOX / 2 - BEVEL / 2))
			add("Bevel", "Wedge", Vector3.new(bodyH, BEVEL, BEVEL), pos, SLATE, SMOOTH, true, rot)
		end
	end
	-- beveled lid
	local lidY = BODY_TOP + BEVEL / 2
	add("Lid", BLOCK, Vector3.new(W - BEVEL * 2, BEVEL, D_BOX - BEVEL * 2), Vector3.new(0, lidY, 0), SLATE, SMOOTH, true)
	add("Bevel", "Wedge", Vector3.new(W - BEVEL * 2, BEVEL, BEVEL), Vector3.new(0, lidY, FRONT + BEVEL / 2), SLATE, SMOOTH, true)
	add("Bevel", "Wedge", Vector3.new(W - BEVEL * 2, BEVEL, BEVEL), Vector3.new(0, lidY, -FRONT - BEVEL / 2), SLATE, SMOOTH, true, CFrame.Angles(0, math.pi, 0))
	for _, s in { 1, -1 } do
		add("Bevel", "Wedge", Vector3.new(D_BOX - BEVEL * 2, BEVEL, BEVEL), Vector3.new(s * (W / 2 - BEVEL / 2), lidY, 0), SLATE, SMOOTH, true, CFrame.Angles(0, -s * math.pi / 2, 0))
	end
	-- armor seams: dark bands round the body
	for _, y in { 2.2, 7.6 } do
		add("Seam", BLOCK, Vector3.new(W - BEVEL * 2 + 0.04, 0.12, D_BOX + 0.04), Vector3.new(0, y, 0), SLATE_DARK, METAL, false)
		add("Seam", BLOCK, Vector3.new(W + 0.04, 0.12, D_BOX - BEVEL * 2 + 0.04), Vector3.new(0, y, 0), SLATE_DARK, METAL, false)
	end

	-- recessed socket panel: raised dark frame, black recess, olive housing, two glands
	local fz = FRONT - 0.15
	local outer, bar = 3.4, 0.4
	for _, s in { 1, -1 } do
		add("PanelFrame", BLOCK, Vector3.new(outer, bar, 0.3), Vector3.new(0, PANEL_Y + s * (outer - bar) / 2, fz), DARK, METAL, false)
		add("PanelFrame", BLOCK, Vector3.new(bar, outer - bar * 2, 0.3), Vector3.new(s * (outer - bar) / 2, PANEL_Y, fz), DARK, METAL, false)
	end
	add("Recess", BLOCK, Vector3.new(outer - bar * 2, outer - bar * 2, 0.06), Vector3.new(0, PANEL_Y, FRONT - 0.03), HOLE, SMOOTH, false)
	add("Housing", BLOCK, Vector3.new(2.0, 1.4, 0.35), Vector3.new(0, PANEL_Y, FRONT - 0.175), OLIVE, SMOOTH, false)
	add("HousingLip", BLOCK, Vector3.new(2.1, 0.14, 0.4), Vector3.new(0, PANEL_Y + 0.72, FRONT - 0.2), OLIVE_DARK, SMOOTH, false)
	for i, x in { -GLAND_X, GLAND_X } do
		add("Gland" .. i, CYL, Vector3.new(0.3, D * 1.45, D * 1.45), Vector3.new(x, PANEL_Y, GLAND_FRONT + 0.15), DARK, METAL, false, ALONG_Z)
		add("GlandRing", CYL, Vector3.new(0.08, D * 1.6, D * 1.6), Vector3.new(x, PANEL_Y, FRONT - 0.36), HAZARD_YELLOW, SMOOTH, false, ALONG_Z)
	end
	local glandLight = add("GlandLight", BLOCK, Vector3.new(0.9, 0.08, 0.06), Vector3.new(0, PANEL_Y - 0.55, FRONT - 0.37), Type99Charger.GlowOff, NEON, false)
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Type99Charger.GlowOn
	glow.Range = 4
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = glandLight
	for _, sx in { 1, -1 } do
		for _, sy in { 1, -1 } do
			add("Bolt", CYL, Vector3.new(0.12, 0.22, 0.22), Vector3.new(sx * 1.5, PANEL_Y + sy * 1.5, FRONT - 0.33), STEEL, METAL, false, ALONG_Z)
		end
	end
	-- green light strips either side of the panel
	for name, s in { StripL = -1, StripR = 1 } do
		add(name, BLOCK, Vector3.new(0.16, 3.0, 0.08), Vector3.new(s * 2.2, PANEL_Y, FRONT - 0.04), Type99Charger.GlowOff, NEON, false)
	end

	-- status screen above the panel
	add("Bezel", BLOCK, Vector3.new(2.9, 1.15, 0.2), Vector3.new(0, 7.0, FRONT - 0.1), DARK, METAL, false)
	local screen = add("Screen", BLOCK, Vector3.new(2.6, 0.85, 0.05), Vector3.new(0, 7.0, FRONT - 0.22), SCREEN_GLASS, SMOOTH, false)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(260, 85)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = screen
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -16, 0.5, 0)
	status.Position = UDim2.fromOffset(8, 4)
	status.Font = Enum.Font.Code
	status.TextScaled = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Type99Charger.GlowOn
	status.Text = "CHARGING"
	status.Parent = gui
	local percent = status:Clone()
	percent.Name = "Percent"
	percent.Position = UDim2.new(0, 8, 0.5, 0)
	percent.Size = UDim2.new(1, -16, 0.45, 0)
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.Text = "100%"
	percent.Parent = gui

	-- connector cradle under the panel
	local shelfTop = PARK_Y - 0.69
	add("Cradle", BLOCK, Vector3.new(2.1, 0.24, 1.6), Vector3.new(0, shelfTop - 0.12, FRONT - 0.8), DARK, METAL, true)
	for _, s in { 1, -1 } do
		add("CradleCheek", BLOCK, Vector3.new(0.18, 0.7, 1.6), Vector3.new(s * 1.0, shelfTop + 0.23, FRONT - 0.8), DARK, METAL, false)
	end
	add("CradleBrace", BLOCK, Vector3.new(1.6, 0.5, 0.9), Vector3.new(0, shelfTop - 0.49, FRONT - 0.45), SLATE_DARK, METAL, false)
	-- hazard band across the front, near the bottom
	local hy0, hy1 = 0.95, 1.65
	add("HazardBack", BLOCK, Vector3.new(W - BEVEL * 2, hy1 - hy0, 0.06), Vector3.new(0, (hy0 + hy1) / 2, FRONT - 0.03), HAZARD_BLACK, SMOOTH, false)
	local sw = 0.6
	local n = math.floor((W - BEVEL * 2 - 0.4) / sw)
	for i = 0, n - 1 do
		local x = -(n - 1) * sw / 2 + i * sw
		add("Hazard", BLOCK, Vector3.new(0.26, 0.85, 0.05), Vector3.new(x, (hy0 + hy1) / 2, FRONT - 0.07), HAZARD_YELLOW, SMOOTH, false, CFrame.Angles(0, 0, math.rad(45)))
	end
	for _, y in { hy0, hy1 } do
		add("HazardTrim", BLOCK, Vector3.new(W - BEVEL * 2, 0.16, 0.14), Vector3.new(0, y, FRONT - 0.07), SLATE_DARK, METAL, false)
	end
	-- side vents
	for _, s in { 1, -1 } do
		add("VentPlate", BLOCK, Vector3.new(0.06, 2.0, 2.2), Vector3.new(s * (W / 2 + 0.03), 5.9, 0.1), SLATE_DARK, METAL, false)
		for k = 0, 4 do
			add("Vent", BLOCK, Vector3.new(0.1, 0.12, 2.0), Vector3.new(s * (W / 2 + 0.08), 5.1 + k * 0.38, 0.1), DARK, METAL, false)
		end
	end
	-- winch drum on the lid (the hoses reel in here), brackets, amber beacon
	local drumY = BODY_TOP + BEVEL + 0.75
	add("Drum", CYL, Vector3.new(3.6, 1.5, 1.5), Vector3.new(0, drumY, 0.4), OLIVE, SMOOTH, true)
	for _, s in { 1, -1 } do
		add("DrumBracket", BLOCK, Vector3.new(0.35, 1.3, 1.3), Vector3.new(s * 2.0, drumY - 0.4, 0.4), DARK, METAL, true)
		add("DrumCap", CYL, Vector3.new(0.12, 1.1, 1.1), Vector3.new(s * 2.23, drumY, 0.4), STEEL, METAL, false)
	end
	for k = -2, 2 do
		add("DrumBand", CYL, Vector3.new(0.1, 1.54, 1.54), Vector3.new(k * 0.7, drumY, 0.4), DARK, METAL, false)
	end
	add("BeaconBase", CYL, Vector3.new(0.3, 0.55, 0.55), Vector3.new(1.9, BODY_TOP + BEVEL + 0.15, FRONT + 0.6), DARK, METAL, false, ALONG_Y)
	local beacon = add("Beacon", BALL, Vector3.new(0.5, 0.5, 0.5), Vector3.new(1.9, BODY_TOP + BEVEL + 0.4, FRONT + 0.6), Type99Charger.BeaconOff, NEON, false)
	local beaconLight = Instance.new("PointLight")
	beaconLight.Name = "Light"
	beaconLight.Color = Type99Charger.BeaconOn
	beaconLight.Range = 10
	beaconLight.Brightness = 0
	beaconLight.Shadows = false
	beaconLight.Parent = beacon
	-- feed conduit out of the back into the floor
	add("Conduit", CYL, Vector3.new(4.0, 0.8, 0.8), Vector3.new(-1.4, PLINTH_H + 2.0, D_BOX / 2 + 0.4), DARK, METAL, false, ALONG_Y)
	add("ConduitBox", BLOCK, Vector3.new(1.2, 1.0, 0.6), Vector3.new(-1.4, PLINTH_H + 4.1, D_BOX / 2 + 0.3), SLATE_DARK, METAL, false)

	-- walker block (see BlockGroup): invisible, collides with mech roots only
	local depth = D_BOX + BLOCK_MARGIN * 2 + BLOCK_REACH
	local blocker = add("WalkerBlock", BLOCK, Vector3.new(W + BLOCK_MARGIN * 2, BLOCK_HEIGHT, depth), Vector3.new(0, BLOCK_HEIGHT / 2, D_BOX / 2 + BLOCK_MARGIN - depth / 2), DARK, SMOOTH, false)
	blocker.Transparency = 1
	blocker.CastShadow = false
	blocker.CanTouch = false
	if PhysicsService:IsCollisionGroupRegistered(Type99Charger.BlockGroup) then
		blocker.CollisionGroup = Type99Charger.BlockGroup
		blocker.CanCollide = true
	end
	model.PrimaryPart = model:FindFirstChild("Body") :: BasePart
	model.WorldPivot = cf
	model:ScaleTo(CS)
	game:GetService("CollectionService"):AddTag(model, "Type99Charger")
	model.Parent = parent
	return model
end

-- Connector (mech end), connector frame: X out of the port, Z along the hull.
export type Connector = {
	folder: Folder,
	parts: { BasePart },
	offsets: { CFrame },
	latch: BasePart,
	led: BasePart,
	body: BasePart,
}

local LATCH_PIVOT = CFrame.new(0.25, 0.72, 0)
local HOSE_Z = 0.42
local BOOT_END = 1.7

-- Latch lever offset for an open angle (0 latched .. ~1 flipped up).
local function latchOffset(angle: number): CFrame
	return LATCH_PIVOT * CFrame.Angles(0, 0, angle) * CFrame.new(0.42, 0.08, 0)
end

function Type99Charger.buildConnector(name: string, parent: Instance): Connector
	local folder = Instance.new("Folder")
	folder.Name = name
	local parts, offsets = {}, {}
	local function add(pname: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
		local p = newPart(shape, size, color, material)
		p.Name = pname
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CollisionGroup = Type99Charger.Group
		p.Parent = folder
		table.insert(parts, p)
		table.insert(offsets, offset)
		return p
	end
	add("Flange", BLOCK, Vector3.new(0.14, 1.5, 1.75), CFrame.new(0.08, 0, 0), DARK, METAL)
	local body = add("Body", BLOCK, Vector3.new(1.05, 1.32, 1.55), CFrame.new(0.66, 0, 0), SLATE_DARK, METAL)
	add("Band", BLOCK, Vector3.new(0.18, 1.36, 1.59), CFrame.new(0.95, 0, 0), HAZARD_YELLOW, SMOOTH)
	add("BandDark", BLOCK, Vector3.new(0.08, 1.37, 1.6), CFrame.new(1.0, 0, 0), HAZARD_BLACK, SMOOTH)
	add("Top", BLOCK, Vector3.new(0.8, 0.1, 1.2), CFrame.new(0.55, 0.7, 0), OLIVE, SMOOTH)
	local led = add("Led", BLOCK, Vector3.new(0.35, 0.14, 0.05), CFrame.new(0.55, 0.3, 0.79), Type99Charger.GlowOff, NEON)
	for _, z in { -HOSE_Z, HOSE_Z } do
		add("Boot", CYL, Vector3.new(0.5, D * 1.45, D * 1.45), CFrame.new(1.4, 0, z) * CFrame.Angles(0, 0, 0), DARK, Enum.Material.Rubber)
		add("BootRing", CYL, Vector3.new(0.1, D * 1.6, D * 1.6), CFrame.new(1.2, 0, z), STEEL, METAL)
	end
	local latch = add("Latch", BLOCK, Vector3.new(0.9, 0.16, 0.32), latchOffset(0), HAZARD_YELLOW, SMOOTH)
	add("LatchHinge", CYL, Vector3.new(0.4, 0.2, 0.2), LATCH_PIVOT * ALONG_Z, STEEL, METAL)
	folder.Parent = parent
	return { folder = folder, parts = parts, offsets = offsets, latch = latch, led = led, body = body }
end

-- Moves the connector to `cf` with the latch lever `latch` open (0..1).
function Type99Charger.placeConnector(conn: Connector, cf: CFrame, latch: number?)
	local cfs = table.create(#conn.parts)
	for i, p in conn.parts do
		local off = if p == conn.latch then latchOffset((latch or 0) * 1.1) else conn.offsets[i]
		cfs[i] = cf * off
	end
	workspace:BulkMoveTo(conn.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Where hose i leaves the connector (world) and its direction.
function Type99Charger.connectorEnd(cf: CFrame, i: number): (Vector3, Vector3)
	local z = if i == 1 then -HOSE_Z else HOSE_Z
	return (cf * CFrame.new(BOOT_END, 0, z)).Position, cf.XVector
end

-- Hose i pairs with the gland on the same side: connector Z runs along the
-- hull (toward the back); pick the gland nearer to each end.
function Type99Charger.glandFor(chargerCF: CFrame, connCF: CFrame, i: number): (Vector3, Vector3)
	local a = Type99Charger.connectorEnd(connCF, i)
	local g1, dir = Type99Charger.glandEnd(chargerCF, 1)
	local g2 = Type99Charger.glandEnd(chargerCF, 2)
	local other = Type99Charger.connectorEnd(connCF, 3 - i)
	-- the pairing that doesn't cross
	local keep = (a - g1).Magnitude + (other - g2).Magnitude <= (a - g2).Magnitude + (other - g1).Magnitude
	if (i == 1) == keep then
		return g1, dir
	end
	return g2, dir
end

export type Hose = {
	folder: Folder,
	segs: { BasePart },
	balls: { BasePart },
}

function Type99Charger.buildHose(name: string, parent: Instance): Hose
	local folder = Instance.new("Folder")
	folder.Name = name
	local segs, balls = {}, {}
	local function part(shape: Enum.PartType, size: Vector3): BasePart
		local p = newPart(shape, size, HOSE, SMOOTH)
		p.Name = if shape == BALL then "Joint" else "Hose"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CollisionGroup = Type99Charger.Group
		p.Parent = folder
		return p
	end
	for i = 1, CFG.Segments do
		segs[i] = part(CYL, Vector3.new(1, D, D))
		if i > 1 then
			table.insert(balls, part(BALL, Vector3.new(D, D, D)))
		end
	end
	folder.Parent = parent
	return { folder = folder, segs = segs, balls = balls }
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- Centerline (Segments + 1 points) of a hose from `a` (leaving along `da`)
-- to `b` (leaving along `db`) that is `length` long, sagging under its
-- weight and lying on the floor (`floorY`) where it reaches it.
function Type99Charger.hose(a: Vector3, da: Vector3, b: Vector3, db: Vector3, length: number, floorY: number, sagBias: number?): { Vector3 }
	local n = CFG.Segments
	local dist = (b - a).Magnitude
	local h = math.clamp(dist * 0.3, 0.3, 1.6)
	local p1, p2 = a + da * h, b + db * h
	local bias = sagBias or 0.5
	local minY = floorY + R
	local function build(sag: number): ({ Vector3 }, number)
		local pts = table.create(n + 1)
		local len = 0
		for i = 0, n do
			local t = i / n
			-- sag peaks at `bias` along the hose (lower end droops more)
			local w = if t < bias then math.sin(t / bias * math.pi / 2) else math.cos((t - bias) / (1 - bias) * math.pi / 2)
			local p = bezier(a, p1, p2, b, t) - Vector3.new(0, sag * w, 0)
			if p.Y < minY and i > 0 and i < n then
				p = Vector3.new(p.X, minY, p.Z)
			end
			pts[i + 1] = p
			if i > 0 then
				len += (p - pts[i]).Magnitude
			end
		end
		return pts, len
	end
	local pts, len = build(0)
	if len >= length then
		return pts
	end
	local lo, hi = 0, 40
	for _ = 1, 16 do
		local m = (lo + hi) / 2
		local _, l = build(m)
		if l < length then
			lo = m
		else
			hi = m
		end
	end
	pts = build((lo + hi) / 2)
	return pts
end

local DIRTY = 0.01

-- Moves a hose onto a centerline.
function Type99Charger.placeHose(hose: Hose, pts: { Vector3 })
	local parts, cfs = {}, {}
	for i, seg in hose.segs do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		if len < 1e-3 then
			b = a + Vector3.new(0, -1e-3, 0)
			len = 1e-3
		end
		local want = len + D * 0.15 -- tiny overlap into the joint balls
		if math.abs(seg.Size.X - want) > DIRTY then
			seg.Size = Vector3.new(want, D, D)
		end
		table.insert(parts, seg)
		table.insert(cfs, CFrame.lookAt((a + b) / 2, b) * ALONG_LOOK)
	end
	for k, ball in hose.balls do
		table.insert(parts, ball)
		table.insert(cfs, CFrame.new(pts[k + 1]))
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Lays both hoses between a connector at `connCF` and the charger.
function Type99Charger.layHoses(hoses: { Hose }, chargerCF: CFrame, connCF: CFrame, length: number, floorY: number)
	for i, hose in hoses do
		local a, da = Type99Charger.connectorEnd(connCF, i)
		local b, db = Type99Charger.glandFor(chargerCF, connCF, i)
		-- the pair hangs a touch differently so they don't read as one
		local l = length * (if i == 1 then 1 else 1.04)
		Type99Charger.placeHose(hose, Type99Charger.hose(a, da, b, db, l, floorY, if i == 1 then 0.45 else 0.52))
	end
end

-- Hose length from the connector's hose ends to the glands.
function Type99Charger.spanOf(chargerCF: CFrame, connCF: CFrame): number
	local a = Type99Charger.connectorEnd(connCF, 1)
	local b = Type99Charger.glandFor(chargerCF, connCF, 1)
	return (a - b).Magnitude
end

return Type99Charger
