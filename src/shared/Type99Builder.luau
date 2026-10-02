--!strict
-- Builds the WTK-99 ("Type99") walking battle tank out of primitive parts:
-- a two-legged walker with no arms, a wedge-shaped armored hull with the
-- cockpit inside under a top-hinged canopy, a railgun on the right side, a
-- 2x3 missile pod on the left, twin chin guns under the nose and
-- reverse-jointed ("chicken") legs on splayed three-toed feet.
--
-- Same conventions as MechBuilder (HWM-04B): design units x MechConfig.Scale,
-- model space with the origin on the ground between the feet, facing -Z,
-- invisible bone parts joined by Motor6Ds, armor welded to the bones in the
-- Armor_Helmet / Armor_Chest / Armor_Legs slot folders:
--   Helmet -> canopy, nose, top armor, antennas
--   Chest  -> hull body, cockpit interior, railgun, missile pod, chin guns
--   Legs   -> pelvis, thighs, shins, feet
-- The pilot seat is built with the chest but lives directly under the model
-- (like the HWM-04B), so swapping the Chest never drops a seated pilot.
--
-- Unlike MechBuilder, bones are laid out as rest CFrames in model space
-- (position + pitch); each motor's C0 is the parent's rest frame to the
-- child's, so an animation Transform of identity is the standing pose.
-- Leg bones point down their segment (-Y), so a pitch Transform swings the
-- segment's lower end forward (positive) or back (negative).
--
-- Rig (bone <- motor, parent):
--   Pelvis      <- Root          (HumanoidRootPart)
--   Hull        <- HullTilt      (Pelvis)   cockpit frame, origin on the floor
--   Canopy      <- CanopyHinge   (Hull)     hinge at the rear top edge
--   Railgun     <- RailgunMount  (Hull)
--   MissilePod  <- MissileMount  (Hull)
--   ChinGun     <- ChinMount     (Hull)
--   [Left|Right]Thigh <- [Left|Right]Hip      (Pelvis)  upper thigh, forward-down
--   [Left|Right]Shank <- [Left|Right]MidJoint (Thigh)   middle segment, back-down
--   [Left|Right]Shin  <- [Left|Right]Knee     (Shank)   long lower leg, forward-down
--   [Left|Right]Foot  <- [Left|Right]Ankle    (Shin)    level at rest

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)

local Type99Builder = {}

Type99Builder.TypeId = "Type99"
Type99Builder.DisplayName = "WTK-99"

type Palette = MechConfig.Palette
-- "glow": Neon accent that stays lit; "light": palette light, dimmed while
-- off; "screen": green cockpit screens, dimmed while off; "steel": piston rods
-- "stencil": palette accent, not lit (markings)
type ColorKey = "main" | "panel" | "dark" | "accent" | "light" | "glow" | "screen" | "steel" | "stencil"

local SCALE = MechConfig.Scale
Type99Builder.Scale = SCALE
local SCREEN_COLOR = Color3.fromRGB(70, 235, 120)
local STEEL_COLOR = Color3.fromRGB(176, 180, 186)

-- Root collision box around the hull; its bottom is the Humanoid's HipHeight.
local ROOT_POS = Vector3.new(0, 11.6, 0.3)
local ROOT_SIZE = Vector3.new(5, 3.8, 4.8)
Type99Builder.RootHeight = ROOT_POS.Y * SCALE
Type99Builder.HipHeight = (ROOT_POS.Y - ROOT_SIZE.Y / 2) * SCALE

local PELVIS_POS = Vector3.new(0, 9.3, 0.3) -- hip axle
local HULL_POS = Vector3.new(0, 10.0, 0) -- cockpit floor center, the hull's tilt pivot

-- Legs (model space, design units): a three-segment zig-zag like a bird's
-- leg. From the hip the upper thigh runs forward-down to the middle joint,
-- the middle segment back-down to the big rear knee, and the long lower leg
-- (pistons) forward-down to the ankle. Segment pitches: 0 = straight down,
-- positive = lower end forward (-Z).
local LEG_X = 3.1
local LEG_LEN = { 3.2, 3.4, 5.05 } -- upper thigh, middle segment, lower leg
local LEG_REST = { math.rad(47), math.rad(-70), math.rad(28) } -- standing
local LEG_FOLD = { math.rad(55), math.rad(-108), math.rad(74) } -- sat down (Off pose)
local HIP_POS = Vector3.new(0, PELVIS_POS.Y, PELVIS_POS.Z)
-- hip -> ankle for segment pitches (design units)
local function legReach(pitches: { number }): Vector3
	local v = Vector3.zero
	for i, p in pitches do
		v += Vector3.new(0, -math.cos(p), -math.sin(p)) * LEG_LEN[i]
	end
	return v
end
local MID_POS = HIP_POS + Vector3.new(0, -math.cos(LEG_REST[1]), -math.sin(LEG_REST[1])) * LEG_LEN[1]
local KNEE_POS = MID_POS + Vector3.new(0, -math.cos(LEG_REST[2]), -math.sin(LEG_REST[2])) * LEG_LEN[2]
local ANKLE_POS = HIP_POS + legReach(LEG_REST) -- ~(0, 1.5, -1.22)

-- Cockpit, in hull-frame design units (origin = HULL_POS, on the floor).
-- Clear interior: 3.0 wide x 4.3 tall x 3.2 deep (floor to canopy roof, back
-- wall to sill) = 5.1 x 7.3 x 5.4 studs; a seated avatar with long hair
-- measures 4.2 x 6.75 x 4.55; seated here it clears the walls by >= 0.36
-- studs (sides 0.45, roof 0.5, front 0.55, back 0.36; feet on the floor).
local INNER_HALF = 1.5
local POD_HALF = 1.7 -- outer face of the cockpit side walls
local FLOOR_TOP = 0
local FLOOR_BOTTOM = -0.25
local ROOF_BOTTOM = 4.3
local ROOF_TOP = 4.5
local INNER_BACK = 1.0
local BACK_OUTER = 1.2
local INNER_FRONT = -2.2 -- sill inner face
local SILL_OUTER = -2.45 -- sill / side wall front; the canopy's front plate starts here
local SILL_TOP = 0.7 -- the opening runs from here up over the roof
local NOSE_FRONT = -6.0 -- the windscreen's lower edge (on the nose top)
-- Hull body around the cockpit (hull frame, design units): a long low wedge,
-- 13.3 long from the pointed nose to the tail (6.0 behind the cockpit floor
-- center, 5.7 behind the hip axle), flat on top.
local NOSE_TIP = -7.3 -- pointed nose tip (z) ...
local TIP_Y = 0.2 -- ... and its height
local NOSE_HALF = 1.8 -- nose block half width, between the cheeks
local HULL_BOTTOM = -0.65 -- belly / nose underside
local HULL_REAR = 6.0 -- tail face
local SKIN_IN, SKIN_OUT = 1.8, 2.3 -- outer side skins (x), cheeks forward of the sill
local SKIN_BOTTOM = 0.5 -- skin lower edge: clear above the hip joints (top ~0.45)
local SKIN_TOP = 4.4
local BODY_TOP = 4.25 -- rear body top, under the top armor
local REAR_TOP = 4.6 -- top armor over the rear body, a step above the canopy roof
local HINGE = Vector3.new(0, ROOF_TOP, BACK_OUTER)
local SEAT_SIZE = Vector3.new(1.6, 0.25, 1.3)
local SEAT_POS = Vector3.new(0, FLOOR_TOP + 1.318 - SEAT_SIZE.Y / 2, INNER_BACK - 1.204)
-- grab handles on the nose tip's upper slope, just in front of the closed
-- windscreen's lower edge: the pilot grabs them to climb onto the nose
local TIP_SLOPE = math.atan2(NOSE_FRONT - NOSE_TIP, SILL_TOP - TIP_Y) -- tilt back from vertical
local TIP_NORMAL = Vector3.new(0, math.sin(TIP_SLOPE), -math.cos(TIP_SLOPE))
local HANDLE_X, HANDLE_Z, HANDLE_OUT = 0.7, -6.4, 0.22
local HANDLE_BASE = Vector3.new(0, SILL_TOP - (SILL_TOP - TIP_Y) * (NOSE_FRONT - HANDLE_Z) / (NOSE_FRONT - NOSE_TIP), HANDLE_Z)
Type99Builder.Cockpit = {
	-- clear box (hull frame, design units), for fit checks and a boarding animation
	min = Vector3.new(-INNER_HALF, FLOOR_TOP, INNER_FRONT),
	max = Vector3.new(INNER_HALF, ROOF_BOTTOM, INNER_BACK),
	sillTop = SILL_TOP,
	sillFront = SILL_OUTER,
	seatTop = SEAT_POS + Vector3.new(0, SEAT_SIZE.Y / 2, 0),
	hinge = HINGE,
	-- the way in over the nose (hull frame, design units; see Climb)
	tip = Vector3.new(0, TIP_Y, NOSE_TIP), -- pointed nose tip
	grip = HANDLE_BASE + TIP_NORMAL * (HANDLE_OUT + 0.2), -- hand on the handle bar (x = +-gripX)
	gripX = HANDLE_X,
	deckFront = Vector3.new(0, SILL_TOP, NOSE_FRONT + 0.35), -- on the nose deck, past the tip
	sill = Vector3.new(0, SILL_TOP, SILL_OUTER), -- top of the sill, where the deck meets the cockpit
	dashTop = 1.2, -- the dashboard on the sill (stepped over)
	floorStand = Vector3.new(0, FLOOR_TOP, -1.75), -- standing in front of the seat, clear of it
}

-- Canopy open angle about its hinge (positive lifts the front up and back).
Type99Builder.CanopyOpenAngle = math.rad(105)

-- Powered-down pose: the hips drop (studs, Root transform offset) and the
-- hull tips nose-down (HullTilt pitch) so the open cockpit is low. The legs
-- fold into LEG_FOLD with the feet planted (see Type99Pose), which sets the
-- drop: down ~5.6 and back ~2.7 (a zig-zag leg folds out forward, so the
-- body sits back over its feet like a roosting bird).
local OFF_DROP = legReach(LEG_REST) - legReach(LEG_FOLD)
Type99Builder.OffDrop = OFF_DROP * SCALE
Type99Builder.OffTilt = -0.45
-- the railgun pitches up against the nose-down tilt so its barrel stays
-- clear of the ground and of the nose climb (RailgunMount, blended by the fold)
Type99Builder.OffRailPitch = 0.62

-- Leg data for Type99Pose's IK (studs; pelvis frame).
Type99Builder.Legs = {
	lengths = { LEG_LEN[1] * SCALE, LEG_LEN[2] * SCALE, LEG_LEN[3] * SCALE },
	rest = table.clone(LEG_REST), -- segment pitches standing (level pelvis)
	fold = table.clone(LEG_FOLD), -- segment pitches sat down
	footRest = 0,
	ankle = (ANKLE_POS - HIP_POS) * SCALE, -- hip -> ankle at rest
}

type BoneDef = { name: string, parent: string, pos: Vector3, pitch: number?, joint: string }

local MOUNTS = {
	Railgun = Vector3.new(2.3, 2.9, -2.0), -- on the right skin, ahead of the side module
	MissilePod = Vector3.new(-2.3, 2.8, -1.9),
	ChinGun = Vector3.new(0, -0.85, -3.7), -- under the nose (further forward it digs in when Off)
}

-- Rest frames in model space (design units): position + pitch.
local BONES: { BoneDef } = {
	{ name = "Pelvis", parent = "HumanoidRootPart", pos = PELVIS_POS, joint = "Root" },
	{ name = "Hull", parent = "Pelvis", pos = HULL_POS, joint = "HullTilt" },
	{ name = "Canopy", parent = "Hull", pos = HULL_POS + HINGE, joint = "CanopyHinge" },
	{ name = "Railgun", parent = "Hull", pos = HULL_POS + MOUNTS.Railgun, joint = "RailgunMount" },
	{ name = "MissilePod", parent = "Hull", pos = HULL_POS + MOUNTS.MissilePod, joint = "MissileMount" },
	{ name = "ChinGun", parent = "Hull", pos = HULL_POS + MOUNTS.ChinGun, joint = "ChinMount" },
}
for _, side in { { "Right", 1 }, { "Left", -1 } } do
	local n, s = side[1] :: string, side[2] :: number
	local x = Vector3.new(s * LEG_X, 0, 0)
	table.insert(BONES, { name = n .. "Thigh", parent = "Pelvis", pos = HIP_POS + x, pitch = LEG_REST[1], joint = n .. "Hip" })
	table.insert(BONES, { name = n .. "Shank", parent = n .. "Thigh", pos = MID_POS + x, pitch = LEG_REST[2], joint = n .. "MidJoint" })
	table.insert(BONES, { name = n .. "Shin", parent = n .. "Shank", pos = KNEE_POS + x, pitch = LEG_REST[3], joint = n .. "Knee" })
	table.insert(BONES, { name = n .. "Foot", parent = n .. "Shin", pos = ANKLE_POS + x, joint = n .. "Ankle" })
end
Type99Builder.Bones = BONES -- design units; multiply positions by Scale for studs

local function restCF(def: BoneDef): CFrame
	return CFrame.new(def.pos * SCALE) * CFrame.Angles(def.pitch or 0, 0, 0)
end
local REST: { [string]: CFrame } = { HumanoidRootPart = CFrame.new(ROOT_POS * SCALE) }
for _, def in BONES do
	REST[def.name] = restCF(def)
end
-- rest frame of a bone in model space (studs), for animators
function Type99Builder.restFrame(name: string): CFrame
	return REST[name]
end

-- Key points of the powered-down pose in world space for a mech whose root
-- is at `rootCF`: the hull frame and seat top (tilted nose-down), the ground
-- spot in front of the nose tip where the pilot starts climbing, and the
-- entry prompt.
export type OffPoints = {
	hull: CFrame, -- the tilted hull frame (studs); Cockpit points x SCALE live in it
	seat: CFrame,
	climb: Vector3, -- on the ground, in front of the nose tip
	prompt: Vector3, -- on the ground
	ground: number,
	forward: Vector3,
}
function Type99Builder.offPoints(rootCF: CFrame): OffPoints
	local pelvis = rootCF * REST.HumanoidRootPart:ToObjectSpace(REST.Pelvis) * CFrame.new(Type99Builder.OffDrop)
	local hull = pelvis * REST.Pelvis:ToObjectSpace(REST.Hull) * CFrame.Angles(Type99Builder.OffTilt, 0, 0)
	local seat = hull * CFrame.new(Type99Builder.Cockpit.seatTop * SCALE)
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local ground = rootCF.Y - Type99Builder.RootHeight
	local tip = hull * (Type99Builder.Cockpit.tip * SCALE)
	local climb = Vector3.new(tip.X, ground, tip.Z) + forward * 1.1
	return {
		hull = hull,
		seat = seat,
		climb = climb,
		prompt = climb + forward * 1.5,
		ground = ground,
		forward = forward,
	}
end

local ROT_Y_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
local ROT_Z_AXIS = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z
local FLIP = CFrame.Angles(0, 0, math.pi) -- wedge sloped underneath, thick end at the back
local TURN = CFrame.Angles(0, math.pi, 0) -- wedge thick end at the front, slope facing up-back
local TAIL = CFrame.Angles(math.pi, 0, 0) -- wedge flat on top, vertical face in front, slope facing down-back

local SHAPES = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

-- Adds one armor piece welded to a bone; `pos` / `rot` in the bone's frame.
local function piece(model: Model, folder: Folder, palette: Palette, boneName: string, kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
	local bone = model:FindFirstChild(boneName) :: BasePart
	if kind == "Seat" then
		-- the seat survives armor swaps (a pilot may be welded to it): recolor only
		local existing = model:FindFirstChild("PilotSeat")
		if existing and existing:IsA("Seat") then
			existing.Color = palette.dark
			return existing
		end
	end
	local part: BasePart
	if kind == "Wedge" then
		part = Instance.new("WedgePart")
	elseif kind == "Seat" then
		part = Instance.new("Seat")
	else
		local p = Instance.new("Part")
		p.Shape = SHAPES[kind]
		part = p
	end
	part.Name = boneName .. "_" .. kind
	part.Size = size * SCALE
	if color == "glow" then
		part.Color = palette.accent
		part.Material = Enum.Material.Neon
	elseif color == "light" or color == "screen" then
		part.Color = if color == "screen" then SCREEN_COLOR else palette.light
		part.Material = Enum.Material.Neon
		part:SetAttribute("MechLight", true) -- dimmed while powered down
	elseif color == "dark" then
		part.Color = palette.dark
		part.Material = Enum.Material.Metal
	elseif color == "stencil" then
		part.Color = palette.accent
		part.Material = Enum.Material.SmoothPlastic
	elseif color == "steel" then
		part.Color = STEEL_COLOR
		part.Material = Enum.Material.Metal
	else
		part.Color = palette[color]
		part.Material = Enum.Material.SmoothPlastic
	end
	part.Anchored = false
	part.CanTouch = false
	part.Massless = true
	-- big plates are solid to on-foot players (see MechBuilder.ArmorGroup); small details aren't
	local a, b, c = size.X, size.Y, size.Z
	local mid = math.max(math.min(a, b), math.min(math.max(a, b), c))
	part.CanCollide = mid >= 0.9 and math.min(a, b, c) >= 0.1 and (color == "main" or color == "panel" or color == "dark") and kind ~= "Seat"
	part.CollisionGroup = MechBuilder.ArmorGroup
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local offset = CFrame.new(pos * SCALE) * (rot or CFrame.identity)
	part.CFrame = bone.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = bone
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	if kind == "Seat" then
		part.Name = "PilotSeat"
		part.Parent = model
	else
		part.Parent = folder
	end
	return part
end

type Add = (string, string, Vector3, Vector3, ColorKey, CFrame?) -> BasePart
type At = (string, Vector3, Vector3, ColorKey, CFrame?) -> BasePart

-- Adder for a bone whose rest frame is the hull frame shifted to `origin`
-- (the canopy and the weapon mounts): takes hull-frame positions.
local function hullAt(add: Add, bone: string, origin: Vector3): At
	return function(kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
		return add(bone, kind, size, pos - origin, color, rot)
	end
end

-- A block lying on a sloped face: `base` on the face, tilted back by `angle`,
-- pushed `out` along the face normal (0, cos, -sin) rotated.
local function onSlope(base: Vector3, angle: number, out: number): (Vector3, CFrame)
	local n = Vector3.new(0, math.sin(angle), -math.cos(angle))
	return base + n * out, CFrame.Angles(angle, 0, 0)
end

local function buildHelmet(add: Add)
	local hull = hullAt(add, "Hull", Vector3.zero)
	local can = hullAt(add, "Canopy", HINGE)

	-- canopy: one hatch of a flat roof and a long sloped armored windscreen
	-- running from the roof's front edge down to the nose, closed at the sides
	-- by triangular flanges (just inside the plate, so no shared faces)
	local roofDepth = BACK_OUTER - SILL_OUTER
	local roofZ = (BACK_OUTER + SILL_OUTER) / 2
	can("Block", Vector3.new(POD_HALF * 2, ROOF_TOP - ROOF_BOTTOM, roofDepth), Vector3.new(0, (ROOF_TOP + ROOF_BOTTOM) / 2, roofZ), "main").Name = "CanopyRoof"
	local slopeDepth = SILL_OUTER - NOSE_FRONT
	local slopeH = ROOF_TOP - SILL_TOP
	local slope = math.atan2(slopeDepth, slopeH) -- tilt back from vertical
	local function slopePoint(y: number): Vector3
		return Vector3.new(0, y, NOSE_FRONT + (y - SILL_TOP) / slopeH * slopeDepth)
	end
	local slopeLen = math.sqrt(slopeDepth * slopeDepth + slopeH * slopeH)
	local p, r = onSlope(slopePoint((ROOF_TOP + SILL_TOP) / 2), slope, -0.125)
	can("Block", Vector3.new(POD_HALF * 2 + 0.1, slopeLen, 0.25), p, "main", r).Name = "CanopyWindscreen" -- 0.05 proud of the sides
	local flankDepth = slopeDepth - 0.1
	for _, s in { 1, -1 } do
		can("Wedge", Vector3.new(0.2, ROOF_BOTTOM - SILL_TOP, flankDepth), Vector3.new(s * 1.55, (ROOF_BOTTOM + SILL_TOP) / 2, SILL_OUTER - flankDepth / 2), "main")
	end
	-- grey armored glass, vision slit and a green stripe on the windscreen
	p, r = onSlope(slopePoint(2.5), slope, 0.05)
	can("Block", Vector3.new(2.6, 3.2, 0.1), p, "dark", r)
	p, r = onSlope(slopePoint(4.0), slope, 0.05)
	can("Block", Vector3.new(2.0, 0.3, 0.1), p, "screen", r) -- vision slit
	p, r = onSlope(slopePoint(1.1), slope, 0.1)
	can("Block", Vector3.new(2.2, 0.16, 0.1), p, "panel", r)
	-- roof: raised grey panel, a green stripe and a warning lamp
	can("Block", Vector3.new(2.4, 0.1, 2.4), Vector3.new(0, ROOF_TOP + 0.05, roofZ - 0.2), "dark")
	can("Block", Vector3.new(0.5, 0.08, 2.0), Vector3.new(1.45, ROOF_TOP + 0.04, roofZ - 0.2), "panel")
	can("Block", Vector3.new(0.5, 0.08, 2.0), Vector3.new(-1.45, ROOF_TOP + 0.04, roofZ - 0.2), "panel")
	can("Block", Vector3.new(0.4, 0.2, 0.4), Vector3.new(-0.7, ROOF_TOP + 0.1, 0.7), "light")
	-- canopy grab handle on the front, and the hinge knuckle on the hatch
	p, r = onSlope(slopePoint(0.85), slope, 0.06)
	can("Block", Vector3.new(0.9, 0.12, 0.12), p, "dark", r)
	can("Cylinder", Vector3.new(1.2, 0.36, 0.36), HINGE, "dark")

	-- hull-side hinge knuckles either side of the hatch's
	for _, s in { 1, -1 } do
		hull("Cylinder", Vector3.new(0.7, 0.34, 0.34), HINGE + Vector3.new(s * 1.05, 0, 0), "dark")
	end

	-- nose: a block under the windscreen and a pointed tip (two wedges meeting
	-- at TIP_Y), between the hull's cheeks
	local noseDepth = SILL_OUTER - NOSE_FRONT
	local noseZ = (SILL_OUTER + NOSE_FRONT) / 2
	local tipLen = NOSE_FRONT - NOSE_TIP
	local tipZ = NOSE_FRONT - tipLen / 2
	hull("Block", Vector3.new(NOSE_HALF * 2, SILL_TOP - HULL_BOTTOM, noseDepth), Vector3.new(0, (SILL_TOP + HULL_BOTTOM) / 2, noseZ), "main")
	hull("Wedge", Vector3.new(NOSE_HALF * 2, SILL_TOP - TIP_Y, tipLen), Vector3.new(0, (SILL_TOP + TIP_Y) / 2, tipZ), "main")
	hull("Wedge", Vector3.new(NOSE_HALF * 2, TIP_Y - HULL_BOTTOM, tipLen), Vector3.new(0, (TIP_Y + HULL_BOTTOM) / 2, tipZ), "main", FLIP)
	local tipSlope = math.atan2(tipLen, SILL_TOP - TIP_Y)
	for _, s in { 1, -1 } do
		p, r = onSlope(Vector3.new(s * 1.2, (SILL_TOP + TIP_Y) / 2, tipZ), tipSlope, 0.04)
		hull("Block", Vector3.new(0.5, 0.3, 0.08), p, "light", r) -- running lights
	end
	p, r = onSlope(Vector3.new(0, (SILL_TOP + TIP_Y) / 2, tipZ), tipSlope, 0.03)
	hull("Block", Vector3.new(1.2, 0.12, 0.06), p, "dark", r) -- panel line
	-- boarding grab handles: a bar on two posts each side of the panel line
	for _, s in { 1, -1 } do
		local base = HANDLE_BASE + Vector3.new(s * HANDLE_X, 0, 0)
		p, r = onSlope(base, TIP_SLOPE, HANDLE_OUT)
		hull("Block", Vector3.new(0.55, 0.12, 0.12), p, "steel", r).Name = "GrabHandle"
		for _, dx in { 0.23, -0.23 } do
			p, r = onSlope(base + Vector3.new(dx, 0, 0), TIP_SLOPE, HANDLE_OUT / 2)
			hull("Block", Vector3.new(0.08, 0.1, HANDLE_OUT - 0.06), p, "dark", r)
		end
	end

	-- top armor over the rear body, a step above the canopy roof
	local topZ0, topZ1 = BACK_OUTER + 0.25, HULL_REAR - 0.1
	hull("Block", Vector3.new(4.4, REAR_TOP - BODY_TOP, topZ1 - topZ0), Vector3.new(0, (REAR_TOP + BODY_TOP) / 2, (topZ0 + topZ1) / 2), "main").Name = "TopArmor"
	hull("Block", Vector3.new(2.4, 0.08, 2.6), Vector3.new(0.3, REAR_TOP + 0.04, 3.2), "dark")
	for _, z in { 1.7, 4.9 } do
		hull("Block", Vector3.new(3.8, 0.1, 0.12), Vector3.new(0, REAR_TOP + 0.03, z), "dark") -- panel lines
	end

	-- sensor mast and antennas on the rear corners
	local mastY = REAR_TOP + 0.2
	hull("Block", Vector3.new(0.45, 0.4, 0.45), Vector3.new(-1.8, mastY, 5.3), "dark")
	hull("Cylinder", Vector3.new(1.5, 0.12, 0.12), Vector3.new(-1.8, mastY + 0.94, 5.3 + 0.13), "dark", CFrame.Angles(0.18, 0, 0) * ROT_Y_AXIS)
	hull("Cylinder", Vector3.new(1.3, 0.09, 0.09), Vector3.new(-1.45, REAR_TOP + 0.6, 5.5), "dark", CFrame.Angles(0.35, 0, 0) * ROT_Y_AXIS)
	hull("Block", Vector3.new(0.45, 0.4, 0.45), Vector3.new(1.8, mastY, 5.3), "dark")
	hull("Block", Vector3.new(0.7, 0.55, 0.7), Vector3.new(1.8, mastY + 0.47, 5.3), "panel") -- sensor head
	hull("Block", Vector3.new(0.4, 0.2, 0.1), Vector3.new(1.8, mastY + 0.5, 4.9), "light") -- sensor eye
end

-- A thin cylinder from `a` to `b` (hull frame), for hoses.
local function hose(at: At, a: Vector3, b: Vector3, dia: number, color: ColorKey)
	local mid = (a + b) / 2
	at("Cylinder", Vector3.new((b - a).Magnitude, dia, dia), mid, color, CFrame.lookAt(mid, b).Rotation * ROT_Z_AXIS)
end

local function buildChest(add: Add)
	local hull = hullAt(add, "Hull", Vector3.zero)
	-- interior fittings: never solid, so they can't shove a seated pilot
	local function ghost(part: BasePart): BasePart
		part.CanCollide = false
		return part
	end

	-- cockpit tub: floor, side walls, back wall, the low front sill
	local tubDepth = BACK_OUTER - INNER_FRONT
	hull("Block", Vector3.new(INNER_HALF * 2, FLOOR_TOP - FLOOR_BOTTOM, tubDepth), Vector3.new(0, (FLOOR_TOP + FLOOR_BOTTOM) / 2, (BACK_OUTER + INNER_FRONT) / 2), "dark").Name = "CockpitFloor"
	for _, s in { 1, -1 } do
		hull("Block", Vector3.new(POD_HALF - INNER_HALF, ROOF_BOTTOM - FLOOR_BOTTOM, BACK_OUTER - SILL_OUTER), Vector3.new(s * (POD_HALF + INNER_HALF) / 2, (ROOF_BOTTOM + FLOOR_BOTTOM) / 2, (BACK_OUTER + SILL_OUTER) / 2), "dark")
	end
	hull("Block", Vector3.new(INNER_HALF * 2, ROOF_BOTTOM - FLOOR_TOP, BACK_OUTER - INNER_BACK), Vector3.new(0, (ROOF_BOTTOM + FLOOR_TOP) / 2, (INNER_BACK + BACK_OUTER) / 2), "dark")
	hull("Block", Vector3.new(INNER_HALF * 2, SILL_TOP - FLOOR_BOTTOM, INNER_FRONT - SILL_OUTER), Vector3.new(0, (SILL_TOP + FLOOR_BOTTOM) / 2, (INNER_FRONT + SILL_OUTER) / 2), "dark")

	-- seat, backrest and consoles
	hull("Seat", SEAT_SIZE, SEAT_POS, "dark") -- "PilotSeat", kept outside the armor folder
	local seatBottom = SEAT_POS.Y - SEAT_SIZE.Y / 2
	ghost(hull("Block", Vector3.new(1.0, seatBottom - FLOOR_TOP, 1.0), Vector3.new(0, (seatBottom + FLOOR_TOP) / 2, SEAT_POS.Z + 0.1), "dark")) -- pedestal
	ghost(hull("Block", Vector3.new(1.6, 2.0, 0.2), Vector3.new(0, SEAT_POS.Y + 1.1, SEAT_POS.Z + 0.75), "main")) -- backrest
	ghost(hull("Block", Vector3.new(1.0, 0.5, 0.2), Vector3.new(0, SEAT_POS.Y + 2.4, SEAT_POS.Z + 0.8), "dark")) -- headrest
	for _, s in { 1, -1 } do
		ghost(hull("Block", Vector3.new(0.2, 0.9, 1.2), Vector3.new(s * 1.4, 1.0, -1.5), "dark")) -- side console
		hull("Block", Vector3.new(0.14, 0.05, 0.9), Vector3.new(s * 1.4, 1.475, -1.5), "screen")
		hull("Block", Vector3.new(0.05, 0.6, 0.8), Vector3.new(s * 1.475, 2.7, -1.75), "screen") -- wall screen
		local strip = hull("Block", Vector3.new(0.05, 0.12, 2.0), Vector3.new(s * 1.475, 3.7, -0.4), "glow") -- light strip
		local lamp = Instance.new("PointLight")
		lamp.Brightness = 0.8
		lamp.Range = 3.2 * SCALE
		lamp.Color = Color3.fromRGB(255, 244, 225)
		lamp.Shadows = false
		lamp.Parent = strip
	end
	-- dashboard on the sill, screens facing the pilot
	local dashZ0, dashZ1 = SILL_OUTER, SILL_OUTER + 0.3
	ghost(hull("Block", Vector3.new(2.6, 0.5, dashZ1 - dashZ0), Vector3.new(0, SILL_TOP + 0.25, (dashZ0 + dashZ1) / 2), "dark"))
	for i = -1, 1 do
		hull("Block", Vector3.new(0.7, 0.34, 0.05), Vector3.new(i * 0.82, SILL_TOP + 0.26, dashZ1 + 0.025), "screen")
	end

	-- Hull body: a long low wedge. Outer skins (SKIN_IN..SKIN_OUT) run from
	-- the cockpit sill to the tail with their lower edge at SKIN_BOTTOM, clear
	-- above the hip joints; the sloped cheeks carry the deck line down to the
	-- nose. The belly and machinery bay between the hips stay narrower than
	-- the inner hip caps (|x| < 1.85).
	local skinW = SKIN_OUT - SKIN_IN
	local skinX = (SKIN_OUT + SKIN_IN) / 2
	local cheekZ0 = NOSE_TIP -- the cheeks come to a point level with the nose tip
	local lowZ0, lowZ1 = cheekZ0 + 0.9, SILL_OUTER - 0.75
	for _, s in { 1, -1 } do
		local x = s * skinX
		hull("Block", Vector3.new(skinW, SKIN_TOP - SKIN_BOTTOM, HULL_REAR - SILL_OUTER), Vector3.new(x, (SKIN_TOP + SKIN_BOTTOM) / 2, (HULL_REAR + SILL_OUTER) / 2), "main").Name = "HullSkin"
		hull("Wedge", Vector3.new(skinW, SKIN_TOP - SKIN_BOTTOM, SILL_OUTER - cheekZ0), Vector3.new(x, (SKIN_TOP + SKIN_BOTTOM) / 2, (SILL_OUTER + cheekZ0) / 2), "main").Name = "HullCheek"
		-- lower cheek: pointed chin at the front, bevel up to the skin at the back
		hull("Block", Vector3.new(skinW, SKIN_BOTTOM - HULL_BOTTOM + 0.05, lowZ1 - lowZ0), Vector3.new(x, (SKIN_BOTTOM + HULL_BOTTOM - 0.05) / 2, (lowZ0 + lowZ1) / 2), "main")
		hull("Wedge", Vector3.new(skinW, SKIN_BOTTOM - HULL_BOTTOM + 0.05, lowZ0 - cheekZ0), Vector3.new(x, (SKIN_BOTTOM + HULL_BOTTOM - 0.05) / 2, (lowZ0 + cheekZ0) / 2), "main", FLIP)
		hull("Wedge", Vector3.new(skinW, SKIN_BOTTOM - HULL_BOTTOM + 0.05, SILL_OUTER - lowZ1), Vector3.new(x, (SKIN_BOTTOM + HULL_BOTTOM - 0.05) / 2, (SILL_OUTER + lowZ1) / 2), "main", TAIL)
		-- skin details: vent slot, panel line along the lower edge, tail light
		local sx = s * (SKIN_OUT + 0.03)
		hull("Block", Vector3.new(0.1, 0.35, 1.3), Vector3.new(sx, 1.15, -1.3), "dark")
		hull("Block", Vector3.new(0.1, 0.12, 8.0), Vector3.new(sx, SKIN_BOTTOM + 0.3, 1.9), "dark")
		hull("Block", Vector3.new(0.1, 0.12, 3.4), Vector3.new(sx, 0.2, -4.6), "dark")
		hull("Block", Vector3.new(0.3, 0.2, 0.08), Vector3.new(s * 2.0, 3.9, HULL_REAR + 0.04), "light")

		-- olive armor module on the rear half of each side, with a proud lid,
		-- latches and stencils
		local mx0, mx1 = SKIN_OUT - 0.05, SKIN_OUT + 0.65
		local my0, my1 = 1.3, 4.15
		local mz0, mz1 = 0.6, 5.4
		hull("Block", Vector3.new(mx1 - mx0, my1 - my0, mz1 - mz0), Vector3.new(s * (mx0 + mx1) / 2, (my0 + my1) / 2, (mz0 + mz1) / 2), "panel").Name = "SideModule"
		hull("Block", Vector3.new(0.05, 2.25, 4.0), Vector3.new(s * (mx1 + 0.025), 2.75, 3.0), "panel") -- lid
		hull("Block", Vector3.new(0.8, 0.15, 4.9), Vector3.new(s * (mx0 + mx1) / 2, my0 - 0.02, 3.0), "dark") -- bottom rail
		for _, z in { 1.2, 4.8 } do
			hull("Block", Vector3.new(0.12, 0.3, 0.2), Vector3.new(s * (mx1 + 0.08), 3.9, z), "dark") -- latch
		end
		local lx = s * (mx1 + 0.07)
		for i, len in { 1.4, 1.0, 1.2 } do
			hull("Block", Vector3.new(0.04, if i == 1 then 0.14 else 0.1, len), Vector3.new(lx, 2.35 - i * 0.22, 1.3 + len / 2), "stencil")
		end
		hull("Block", Vector3.new(0.04, 0.12, 0.6), Vector3.new(lx, 3.45, 4.2), "stencil")
		hull("Block", Vector3.new(0.04, 0.12, 0.35), Vector3.new(lx, 3.45, 3.6), "stencil")
	end

	-- center of the body: rear body behind the cockpit up to the top armor,
	-- the belly under the cockpit, a lower bay and a bevel under the tail
	local bodyHalf = SKIN_IN - 0.05
	local bayZ1 = HULL_REAR - 1.4
	hull("Block", Vector3.new(bodyHalf * 2, BODY_TOP - SKIN_BOTTOM, HULL_REAR - BACK_OUTER - 0.05), Vector3.new(0, (BODY_TOP + SKIN_BOTTOM) / 2, (HULL_REAR + BACK_OUTER + 0.05) / 2), "main").Name = "RearBody"
	local bellyBottom, bellyZ0 = HULL_BOTTOM - 0.05, SILL_OUTER - 0.15 -- tucked into the nose block
	hull("Block", Vector3.new(3.3, FLOOR_BOTTOM + 0.05 - bellyBottom, bayZ1 - bellyZ0), Vector3.new(0, (FLOOR_BOTTOM + 0.05 + bellyBottom) / 2, (bayZ1 + bellyZ0) / 2), "dark").Name = "Belly"
	hull("Block", Vector3.new(3.4, SKIN_BOTTOM - FLOOR_BOTTOM - 0.05, bayZ1 - BACK_OUTER - 0.05), Vector3.new(0, (SKIN_BOTTOM + FLOOR_BOTTOM + 0.05) / 2, (bayZ1 + BACK_OUTER + 0.05) / 2), "dark")
	hull("Wedge", Vector3.new(bodyHalf * 2, SKIN_BOTTOM - HULL_BOTTOM + 0.05, HULL_REAR - bayZ1), Vector3.new(0, (SKIN_BOTTOM + HULL_BOTTOM - 0.05) / 2, (HULL_REAR + bayZ1) / 2), "main", TAIL)

	-- underside machinery between the hull and the hips: a turbine drum with
	-- bands and end caps, a vented box, and hoses down to the hip axle
	local drumY, drumZ = -1.05, 2.4
	hull("Cylinder", Vector3.new(2.6, 1.3, 1.3), Vector3.new(0, drumY, drumZ), "dark").Name = "Turbine"
	for _, s in { 1, -1 } do
		hull("Cylinder", Vector3.new(0.15, 1.4, 1.4), Vector3.new(s * 0.8, drumY, drumZ), "main")
		hull("Cylinder", Vector3.new(0.1, 0.8, 0.8), Vector3.new(s * 1.35, drumY, drumZ), "steel")
	end
	hull("Block", Vector3.new(2.6, 0.5, 1.3), Vector3.new(0, HULL_BOTTOM - 0.25, 3.85), "dark")
	for i = 0, 2 do
		hull("Block", Vector3.new(2.0, 0.1, 0.1), Vector3.new(0, HULL_BOTTOM - 0.52, 3.4 + i * 0.35), "main") -- vent slats
	end
	for _, s in { 1, -1 } do
		local a = Vector3.new(s * 1.05, -1.35, 2.0)
		local b = Vector3.new(s * 1.55, -1.55, 1.35)
		local c = Vector3.new(s * 1.45, -0.85, 0.55)
		hose(hull, a, b, 0.28, "dark")
		hose(hull, b, c, 0.28, "dark")
		hull("Ball", Vector3.new(0.34, 0.34, 0.34), b, "dark")
	end

	-- tail: rear hatch, vents and the charger's cable port. The port faces
	-- backward (+Z, the mech faces -Z): a chunky block with a raised rim
	-- around a recessed socket, two contact pins and a status light. Its
	-- "CablePoint" attachment sits on the socket face, X pointing out.
	local rearZ = HULL_REAR
	hull("Cylinder", Vector3.new(0.12, 1.3, 1.3), Vector3.new(0.95, 2.6, rearZ + 0.06), "dark", ROT_Z_AXIS) -- rear hatch
	hull("Cylinder", Vector3.new(0.1, 0.8, 0.8), Vector3.new(0.95, 2.6, rearZ + 0.15), "main", ROT_Z_AXIS)
	for _, x in { -0.8, 0.95 } do
		for i = 0, 2 do
			hull("Block", Vector3.new(0.9, 0.14, 0.12), Vector3.new(x, 0.75 + i * 0.25, rearZ + 0.04), "dark") -- vents
		end
	end
	local port = Vector3.new(-0.8, 2.3, rearZ + 0.25)
	local cablePort = hull("Block", Vector3.new(1.3, 1.3, 0.6), port, "dark")
	cablePort.Name = "CablePort"
	cablePort.CanCollide = false
	local point = Instance.new("Attachment")
	point.Name = "CablePoint"
	point.CFrame = CFrame.fromMatrix(Vector3.new(0, 0, 0.3 * SCALE), Vector3.zAxis, Vector3.yAxis)
	point.Parent = cablePort
	local face = port.Z + 0.3
	for _, dx in { 0.6, -0.6 } do
		hull("Block", Vector3.new(0.22, 1.44, 0.25), Vector3.new(port.X + dx, port.Y, face + 0.12), "dark") -- rim
	end
	for _, dy in { 0.6, -0.6 } do
		hull("Block", Vector3.new(0.98, 0.22, 0.2), Vector3.new(port.X, port.Y + dy, face + 0.1), "dark")
	end
	hull("Block", Vector3.new(0.8, 0.8, 0.1), Vector3.new(port.X, port.Y, face), "main") -- socket insert
	for _, dx in { 0.2, -0.2 } do
		hull("Cylinder", Vector3.new(0.12, 0.12, 0.12), Vector3.new(port.X + dx, port.Y, face + 0.11), "steel", ROT_Z_AXIS) -- pins
	end
	hull("Block", Vector3.new(0.18, 0.12, 0.08), Vector3.new(port.X + 0.25, port.Y + 0.6, face + 0.24), "glow") -- status light

	-- railgun (right side): receiver on a bracket, twin rails with a glowing core
	local RM = MOUNTS.Railgun
	local rail = hullAt(add, "Railgun", RM)
	local function rp(x: number, y: number, z: number): Vector3
		return RM + Vector3.new(x, y, z)
	end
	rail("Block", Vector3.new(0.62, 0.8, 1.2), rp(0.19, 0, 0), "dark") -- bracket, sunk into the hull skin
	rail("Block", Vector3.new(1.1, 1.2, 3.6), rp(1.05, 0, 0.2), "panel") -- receiver
	rail("Block", Vector3.new(0.6, 0.2, 3.0), rp(1.05, 0.7, 0.2), "dark") -- top rail
	rail("Block", Vector3.new(0.4, 0.4, 0.8), rp(1.05, 1.0, 0.8), "dark") -- sight
	rail("Block", Vector3.new(0.3, 0.2, 0.1), rp(1.05, 1.05, 0.35), "light")
	rail("Block", Vector3.new(0.9, 1.0, 0.8), rp(1.05, -0.15, 2.15), "dark") -- capacitor pack
	rail("Block", Vector3.new(0.1, 0.5, 1.8), rp(1.65, 0, 0), "main") -- stripe
	rail("Block", Vector3.new(0.8, 0.9, 1.6), rp(1.05, 0, -2.4), "dark") -- shroud
	for _, dy in { 0.28, -0.28 } do
		rail("Block", Vector3.new(0.22, 0.22, 4.4), rp(1.05, dy, -5.4), "dark")
	end
	rail("Block", Vector3.new(0.1, 0.1, 4.2), rp(1.05, 0, -5.3), "glow")
	for _, z in { -4.6, -6.2 } do
		rail("Block", Vector3.new(0.7, 0.95, 0.25), rp(1.05, 0, z), "panel") -- clamps
	end
	rail("Block", Vector3.new(0.6, 0.95, 0.4), rp(1.05, 0, -7.7), "dark") -- muzzle

	-- missile pod (left side): 2 x 3 tubes
	local MM = MOUNTS.MissilePod
	local pod = hullAt(add, "MissilePod", MM)
	local function pp(x: number, y: number, z: number): Vector3
		return MM + Vector3.new(x, y, z)
	end
	pod("Block", Vector3.new(0.62, 0.8, 1.2), pp(-0.19, 0, 0), "dark") -- bracket
	pod("Block", Vector3.new(1.9, 2.1, 2.8), pp(-1.45, 0.2, -0.1), "panel")
	pod("Block", Vector3.new(1.7, 1.9, 0.1), pp(-1.45, 0.2, -1.55), "dark") -- launch face
	for col = -1, 1, 2 do
		for row = -1, 1 do
			local pos = pp(-1.45 + col * 0.42, 0.2 + row * 0.6, -1.7)
			pod("Cylinder", Vector3.new(0.3, 0.5, 0.5), pos, "dark", ROT_Z_AXIS)
			pod("Cylinder", Vector3.new(0.1, 0.3, 0.3), pos + Vector3.new(0, 0, -0.18), "main", ROT_Z_AXIS) -- warhead
		end
	end
	pod("Block", Vector3.new(2.0, 2.2, 0.3), pp(-1.45, 0.2, 0.7), "dark") -- strap
	pod("Block", Vector3.new(0.1, 1.0, 1.2), pp(-2.45, 0.5, -0.5), "main") -- side marking
	pod("Block", Vector3.new(0.1, 0.25, 0.25), pp(-2.45, -0.3, -0.8), "light")

	-- twin chin guns under the nose
	local CM = MOUNTS.ChinGun
	local chin = hullAt(add, "ChinGun", CM)
	local function cp(x: number, y: number, z: number): Vector3
		return CM + Vector3.new(x, y, z)
	end
	chin("Block", Vector3.new(0.6, 0.6, 0.6), cp(0, 0.25, 0), "dark") -- stem into the nose
	chin("Block", Vector3.new(1.2, 0.5, 1.2), cp(0, -0.25, 0), "dark") -- turret
	chin("Block", Vector3.new(0.9, 0.45, 0.8), cp(0, -0.45, -0.7), "panel") -- gun housing
	for _, s in { 1, -1 } do
		chin("Cylinder", Vector3.new(2.0, 0.2, 0.2), cp(s * 0.22, -0.45, -2.1), "dark", ROT_Z_AXIS)
		chin("Cylinder", Vector3.new(0.3, 0.3, 0.3), cp(s * 0.22, -0.45, -3.05), "dark", ROT_Z_AXIS)
	end
end

-- Crotch armor (Legs slot, on the Pelvis bone, so it stays level while the
-- hull tilts): a block hung under the hip axle between the hips, well inside
-- the inner hip caps (|x| <= 1.1 vs 1.85, so the swinging thighs never reach
-- it), a front plate with a U-shaped grab bar, and two short pistons below.
local function buildCrotch(add: Add)
	local function at(kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
		return add("Pelvis", kind, size, pos, color, rot)
	end
	at("Block", Vector3.new(2.0, 1.4, 1.5), Vector3.new(0, -1.15, -0.05), "dark").Name = "Crotch"
	at("Block", Vector3.new(1.7, 1.1, 0.1), Vector3.new(0, -1.1, -0.85), "main") -- front plate
	for _, s in { 1, -1 } do
		at("Block", Vector3.new(0.1, 1.0, 1.2), Vector3.new(s * 1.05, -1.15, -0.05), "main") -- side plates
	end
	-- grab bar: top bar and two uprights on standoffs
	at("Block", Vector3.new(1.5, 0.18, 0.18), Vector3.new(0, -0.62, -1.12), "steel")
	for _, s in { 1, -1 } do
		at("Block", Vector3.new(0.12, 0.9, 0.08), Vector3.new(s * 0.6, -1.1, -1.12), "steel")
		for _, y in { -0.8, -1.45 } do
			at("Block", Vector3.new(0.08, 0.1, 0.22), Vector3.new(s * 0.6, y, -0.97), "dark")
		end
	end
	-- pistons under the block
	for _, s in { 1, -1 } do
		at("Cylinder", Vector3.new(0.7, 0.34, 0.34), Vector3.new(s * 0.45, -2.2, 0), "dark", ROT_Y_AXIS)
		at("Cylinder", Vector3.new(0.6, 0.16, 0.16), Vector3.new(s * 0.45, -2.75, 0), "steel", ROT_Y_AXIS)
		at("Block", Vector3.new(0.34, 0.12, 0.34), Vector3.new(s * 0.45, -3.1, 0), "dark")
	end
end

local function buildLegs(add: Add)
	-- pelvis: axle and block under the hull
	add("Pelvis", "Cylinder", Vector3.new(4.8, 0.8, 0.8), Vector3.zero, "dark")
	add("Pelvis", "Block", Vector3.new(2.6, 0.6, 1.2), Vector3.new(0, -0.1, 0), "dark")

	-- round joint: dark barrel, a colored cap on each end (outer face at
	-- +-capX), a bolt head and its slot line on the outside. Each joint's
	-- caps sit in their own X band (knee outermost, then hip, mid, ankle;
	-- bands 0.22 deep, 0.04 apart), so caps from different segments never
	-- share a plane however the leg folds.
	local function joint(bone: string, s: number, capX: number, dia: number, cap: ColorKey)
		add(bone, "Cylinder", Vector3.new(2 * (capX - 0.1), dia, dia), Vector3.zero, "dark")
		for _, f in { s, -s } do
			add(bone, "Cylinder", Vector3.new(0.1, dia * 0.72, dia * 0.72), Vector3.new(f * (capX - 0.05), 0, 0), cap)
		end
		add(bone, "Cylinder", Vector3.new(0.06, dia * 0.4, dia * 0.4), Vector3.new(s * (capX + 0.03), 0, 0), "dark")
		add(bone, "Block", Vector3.new(0.06, dia * 0.36, 0.1), Vector3.new(s * (capX + 0.09), 0, 0), cap, CFrame.Angles(0.6, 0, 0))
	end

	for _, side in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = side[1] :: string, side[2] :: number
		local TH, SK, SH, F = n .. "Thigh", n .. "Shank", n .. "Shin", n .. "Foot"
		local L1, L2, L3 = LEG_LEN[1], LEG_LEN[2], LEG_LEN[3]

		-- hip: big round joint
		joint(TH, s, 1.14, 2.3, "main")
		-- upper thigh (forward-down): frame inside a chunky armored shell
		add(TH, "Block", Vector3.new(0.96, L1, 1.0), Vector3.new(0, -L1 / 2, 0), "dark")
		add(TH, "Block", Vector3.new(1.5, L1 - 1.0, 1.9), Vector3.new(0, -L1 / 2 - 0.1, -0.15), "main")
		add(TH, "Wedge", Vector3.new(1.5, 0.6, 1.9), Vector3.new(0, -0.3, -0.15), "main")
		add(TH, "Block", Vector3.new(0.1, 1.4, 1.2), Vector3.new(s * 0.8, -L1 / 2, -0.2), "panel")
		add(TH, "Block", Vector3.new(0.9, 0.9, 0.1), Vector3.new(0, -L1 / 2, -1.12), "dark") -- panel line plate
		add(TH, "Block", Vector3.new(0.2, 0.2, 0.1), Vector3.new(-s * 0.4, -L1 / 2 - 0.7, -1.12), "light")

		-- middle joint (front) with an olive guard plate, then the middle segment
		-- (back-down): a fork of two dark side plates the lower leg folds into,
		-- a top cover and an exposed strut
		joint(SK, s, 0.88, 1.8, "panel")
		add(SK, "Block", Vector3.new(1.3, 1.5, 0.3), Vector3.new(0, 0.1, -1.05), "panel", CFrame.Angles(0.35, 0, 0))
		for _, f in { 1, -1 } do
			add(SK, "Block", Vector3.new(0.3, L2 - 0.8, 1.2), Vector3.new(f * 0.95, -(L2 + 1.1) / 2, 0), "dark")
		end
		add(SK, "Block", Vector3.new(1.6, L2 - 1.4, 0.3), Vector3.new(0, -L2 / 2, 0.5), "main")
		add(SK, "Cylinder", Vector3.new(L2 - 0.8, 0.34, 0.34), Vector3.new(0, -L2 / 2, -0.4), "steel", ROT_Y_AXIS)
		add(SK, "Cylinder", Vector3.new(1.2, 0.5, 0.5), Vector3.new(0, -0.9, -0.4), "dark", ROT_Y_AXIS)

		-- knee (rear, the big one): olive caps, a guard hooked over the back
		joint(SH, s, 1.4, 2.1, "panel")
		add(SH, "Wedge", Vector3.new(1.3, 1.0, 0.6), Vector3.new(0, 0.9, 0.7), "panel", CFrame.Angles(0.5, 0, 0))
		-- lower leg (forward-down): twin struts, olive armor on the front face,
		-- exposed pistons behind
		for _, f in { 1, -1 } do
			add(SH, "Block", Vector3.new(0.3, L3 - 0.6, 0.45), Vector3.new(f * 0.42, -L3 / 2, 0.05), "dark")
		end
		add(SH, "Block", Vector3.new(1.24, 2.8, 0.5), Vector3.new(0, -2.0, -0.45), "panel")
		add(SH, "Wedge", Vector3.new(1.24, 0.6, 0.5), Vector3.new(0, -0.3, -0.45), "panel")
		add(SH, "Block", Vector3.new(1.2, 1.5, 0.45), Vector3.new(0, -4.1, -0.43), "panel")
		add(SH, "Block", Vector3.new(0.8, 0.12, 0.1), Vector3.new(0, -2.5, -0.73), "dark") -- panel line
		add(SH, "Block", Vector3.new(0.2, 0.2, 0.1), Vector3.new(s * 0.4, -1.2, -0.73), "light")
		for _, f in { 1, -1 } do
			add(SH, "Cylinder", Vector3.new(2.4, 0.42, 0.42), Vector3.new(f * 0.28, -1.9, 0.5), "dark", ROT_Y_AXIS) -- cylinder
			add(SH, "Cylinder", Vector3.new(2.6, 0.2, 0.2), Vector3.new(f * 0.28, -4.0, 0.5), "steel", ROT_Y_AXIS) -- rod
		end
		add(SH, "Block", Vector3.new(0.84, 0.3, 0.5), Vector3.new(0, -L3 + 0.25, 0.45), "dark") -- rod anchor

		-- foot: ankle joint, block, three splayed toes and a heel spur. Soles
		-- sit at the ground (foot frame y -ANKLE_POS.Y).
		local g = -ANKLE_POS.Y
		joint(F, s, 0.62, 1.2, "panel")
		add(F, "Block", Vector3.new(0.9, 0.85, 0.9), Vector3.new(0, -0.525, 0), "dark")
		add(F, "Block", Vector3.new(1.6, 0.4, 1.8), Vector3.new(0, g + 0.3, -0.1), "dark") -- base
		add(F, "Block", Vector3.new(1.3, 0.3, 1.2), Vector3.new(0, g + 0.65, -0.5), "main") -- top cover
		add(F, "Block", Vector3.new(0.55, 0.45, 1.6), Vector3.new(0, g + 0.225, -1.5), "main") -- middle toe
		add(F, "Wedge", Vector3.new(0.55, 0.45, 0.6), Vector3.new(0, g + 0.225, -2.6), "main")
		for _, t in { 1, -1 } do
			-- outer toes pivot at the base's front corners and splay out
			local toe = CFrame.new(t * 0.6, g + 0.225, -0.7) * CFrame.Angles(0, -t * 0.45, 0)
			local body = toe * CFrame.new(0, 0, -0.75)
			local tip = toe * CFrame.new(0, 0, -1.8)
			add(F, "Block", Vector3.new(0.5, 0.45, 1.5), body.Position, "main", body.Rotation)
			add(F, "Wedge", Vector3.new(0.5, 0.45, 0.6), tip.Position, "main", tip.Rotation)
		end
		add(F, "Wedge", Vector3.new(0.5, 0.5, 1.2), Vector3.new(0, g + 0.25, 1.3), "main", TURN) -- heel spur
	end
end

local SLOT_BUILDERS = {
	Helmet = buildHelmet,
	Chest = buildChest,
	Legs = function(add: Add)
		buildLegs(add)
		buildCrotch(add)
	end,
}

-- Builds the bare rig: root, bones, motors, humanoid. No armor.
function Type99Builder.buildRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", Type99Builder.TypeId)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE * SCALE
	root.CFrame = REST.HumanoidRootPart
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = MechBuilder.RootGroup
	root.RootPriority = 100 -- stays the assembly root with a pilot welded in
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	local bones: { [string]: BasePart } = { HumanoidRootPart = root }
	for _, def in BONES do
		local parent = bones[def.parent]
		local c0 = REST[def.parent]:ToObjectSpace(REST[def.name])

		local bone = Instance.new("Part")
		bone.Name = def.name
		bone.Size = Vector3.new(0.4, 0.4, 0.4)
		bone.CFrame = REST[def.name]
		bone.Transparency = 1
		bone.CanCollide = false
		bone.CanTouch = false
		bone.CanQuery = false
		bone.Massless = true
		bone.Parent = model
		bones[def.name] = bone

		local motor = Instance.new("Motor6D")
		motor.Name = def.joint
		motor.Part0 = parent
		motor.Part1 = bone
		motor.C0 = c0
		motor.C1 = CFrame.identity
		motor.Parent = bone
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = Type99Builder.HipHeight
	humanoid.WalkSpeed = MechConfig.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.CameraOffset = Vector3.new(0, 4 * SCALE, 0)
	humanoid.Parent = model

	for _, slot in MechConfig.Slots do
		local folder = Instance.new("Folder")
		folder.Name = "Armor_" .. slot
		folder.Parent = model
	end

	return model
end

-- Replaces the armor in one slot with the given color variant.
function Type99Builder.applySlot(model: Model, slot: string, variantId: string)
	local folder = model:FindFirstChild("Armor_" .. slot) :: Folder
	folder:ClearAllChildren()
	local palette = MechConfig.getVariant(variantId).palette
	local function add(boneName: string, kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
		return piece(model, folder, palette, boneName, kind, size, pos, color, rot)
	end
	SLOT_BUILDERS[slot](add)
	model:SetAttribute(slot, variantId)
end

-- Builds a complete mech. `loadout` maps slot -> variant id.
function Type99Builder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = Type99Builder.buildRig(name)
	for _, slot in MechConfig.Slots do
		Type99Builder.applySlot(model, slot, loadout[slot])
	end
	return model
end

return Type99Builder
