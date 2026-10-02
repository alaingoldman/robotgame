--!strict
-- Builds the VK-01 "Valkyrie" (type id "Knight") out of primitive parts: a
-- tall, slim knight-like humanoid with white main armor, gold trim, blue
-- insets and a grey frame. Helmet with a gold faceplate and two tall horn
-- fins; big layered swept-up pauldrons with rising fins; a gold V collar
-- over a pointed white chest plate; narrow waist and a pointed crotch
-- tasset; long legs with bulky thighs, big diamond knee armor, flared shins
-- and blue calf strips; two tall wing binders flanking a hex-cored spine.
--
-- Same conventions as MechBuilder / Type99Builder: design units x
-- MechConfig.Scale, model space with the origin on the ground between the
-- feet, facing -Z; invisible bone parts joined by Motor6Ds; armor welded to
-- the bones in the Armor_Helmet / Armor_Chest / Armor_Legs slot folders:
--   Helmet -> head, horns, faceplate
--   Chest  -> torso, cockpit + hatch, pauldrons, arms, hands, wings, backpack
--   Legs   -> pelvis, tasset, legs, feet
-- The pilot seat is built with the chest but lives directly under the model.
--
-- The rig uses the HWM-04B's bone and motor names (so humanoid animation code
-- can drive it later), laid out Type99-style as rest CFrames in model space
-- (position + pitch / roll); each motor's C0 is the parent's rest frame to
-- the child's, so an identity Transform is the standing pose:
--   Waist <- Root (HumanoidRootPart)        Torso <- Waist (Waist)
--   Head <- Neck (Torso)                    Hatch <- HatchHinge (Torso)
--   Wing[Left|Right] <- Wing[Left|Right]Mount (Torso)
--   [L|R]UpperArm <- [L|R]Shoulder (Torso)  [L|R]LowerArm <- [L|R]Elbow
--   [L|R]Hand <- [L|R]Wrist                 [L|R]UpperLeg <- [L|R]Hip (Waist)
--   [L|R]LowerLeg <- [L|R]Knee              [L|R]Foot <- [L|R]Ankle
--
-- Cockpit: in the chest, level with the torso. Its lower third is a narrow
-- footwell (the pilot's shins and feet), so the chest tapers to a slim
-- waist; the step beside it forms the side consoles. The white chest plate
-- is the hatch: hinged along its bottom inner edge (the cockpit floor's
-- front), it folds down and forward like a drawbridge and its inner face
-- becomes the deck. In the powered-down kneel its lip hangs ~5 studs up.
--
-- Proportions, measured on the reference sheet's front / side / back views
-- (1 sheet px = 0.0258 design units; total 705 px = 18.2 du = 30.9 studs):
--   measurement                          sheet (du)   built (du)
--   total height (horn tips)                18.2        18.25
--   pauldron span                           11.0        see report
--   chest width                              4.65        4.6
--   waist width                              2.5         2.6 (cockpit footwell)
--   hip width (thigh outer edges)            5.7         5.8
--   thigh width (mid)                        1.63        1.83 (bulk kept)
--   knee armor width                         2.35        2.45
--   shin width (mid / flared bottom)         1.68 / 2.0  1.7 / 2.1
--   foot width                               1.73        1.7
--   leg gap (mid thigh / knees)              1.94 / 1.55 2.1 / 1.39
--   stance (leg center to center)            4.26        3.9
--   heights: helmet top 17.66, chin 15.2, chest V point 11.4, hip joint
--   10.56, tasset tip 8.5, knee joint 6.95, knee armor 7.33..3.98, ankle 1.39
--   (built: 17.8, 15.2, 11.4, 10.55, 8.5, 7.0, 7.4..4.2, 1.4)
--   side: thigh depth 2.27, knee plate forward of the knee 2.07, calf depth
--   2.0, foot length ~4 (built: 2.2, 2.0, 2.05, 3.9)
-- The chest is taller and deeper than drawn (the cockpit must hold a seated
-- avatar); the legs are straight (the sheet's shins splay slightly out).

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)

local KnightBuilder = {}

KnightBuilder.TypeId = "Knight"
KnightBuilder.DisplayName = "VK-01"

type Palette = MechConfig.Palette
-- "glow": accent Neon, always lit; "light": palette light Neon, dimmed while
-- off; "screen": gold Neon screen, dimmed while off
type ColorKey = "main" | "panel" | "dark" | "accent" | "light" | "glow" | "screen"

local SCALE = MechConfig.Scale
KnightBuilder.Scale = SCALE
local SCREEN_COLOR = Color3.fromRGB(255, 196, 70)

-- Root collision box; its bottom is the Humanoid's HipHeight.
local ROOT_POS = Vector3.new(0, 11.0, 0.1)
local ROOT_SIZE = Vector3.new(4.4, 3.8, 3.2)
KnightBuilder.RootHeight = ROOT_POS.Y * SCALE
KnightBuilder.HipHeight = (ROOT_POS.Y - ROOT_SIZE.Y / 2) * SCALE

local PELVIS_POS = Vector3.new(0, 10.4, 0)
local TORSO_POS = Vector3.new(0, 10.6, 0) -- waist pivot; the torso / cockpit frame origin
local NECK_POS = Vector3.new(0, 15.45, 0.15)
local SHOULDER = Vector3.new(3.44, 13.9, 0.1) -- right side (x mirrored)
local UPPER_ARM, FOREARM = 1.9, 3.1 -- the forearm guard is the long part
local ARM_ROLL = 0.1 -- arms hang slightly out (A-stance)
local WING_MOUNT = Vector3.new(1.0, 4.0, 2.45) -- torso frame (x mirrored)

-- Legs: long, nearly straight; short thigh, long shin under the big knee armor.
local LEG_X = 1.95
local HIP_Y = 10.55
local THIGH_LEN, SHIN_LEN = 3.6, 5.55
local HIP_REST = 0.03 -- thigh pitch (lower end forward)
local SHIN_REST = -0.03 -- shin pitch (lower end back): a hint of knee bend
local function rotX(v: Vector3, a: number): Vector3
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end
local THIGH_D = Vector3.new(0, -THIGH_LEN, 0)
local SHIN_D = Vector3.new(0, -SHIN_LEN, 0)
local HIP_POS = Vector3.new(0, HIP_Y, 0)
local KNEE_POS = HIP_POS + rotX(THIGH_D, HIP_REST)
local ANKLE_POS = KNEE_POS + rotX(SHIN_D, SHIN_REST) -- y ~1.4: the sole is at -ANKLE_H in the foot frame
local ANKLE_H = ANKLE_POS.Y
KnightBuilder.LegLength = (THIGH_LEN + SHIN_LEN) * SCALE

KnightBuilder.Legs = {
	thigh = THIGH_LEN * SCALE,
	shin = SHIN_LEN * SCALE,
	hipRest = HIP_REST,
	shinRest = SHIN_REST,
	ankle = (ANKLE_POS - HIP_POS) * SCALE, -- hip -> ankle standing (studs)
	hipX = LEG_X * SCALE,
}

-- Cockpit, torso frame (design units). Clear interior 2.9 wide (2.2 in the
-- footwell, up to 1.1 above the floor) x 4.32 tall x 3.2 deep = 4.93 (3.74)
-- x 7.34 x 5.44 studs; a seated avatar with long hair measures
-- 4.2 x 6.75 x 4.54 (its shins / feet ~2.2 wide).
local INNER_HALF = 1.45
local POD_HALF = 1.65
local FOOT_HALF = 1.1 -- footwell interior
local WAIST_HALF = 1.32 -- footwell outer (the waist)
local FLOOR_BOTTOM = 0
local FLOOR_TOP = 0.25
local STEP_Y = FLOOR_TOP + 1.1 -- console ledges; the seat top is ~0.22 higher
local ROOF_BOTTOM = FLOOR_TOP + 4.32
local ROOF_TOP = ROOF_BOTTOM + 0.2
local INNER_BACK = 1.45
local BACK_OUTER = 1.65
local INNER_FRONT = -1.75 -- hatch inner face (closed) = hinge line
local HATCH_T = 0.3
local HATCH_OUTER = INNER_FRONT - HATCH_T
local HATCH_LEN = ROOF_BOTTOM - FLOOR_TOP
local HINGE = Vector3.new(0, FLOOR_TOP, INNER_FRONT)
local SEAT_SIZE = Vector3.new(1.6, 0.25, 1.3)
local SEAT_POS = Vector3.new(0, FLOOR_TOP + 1.318 - SEAT_SIZE.Y / 2, INNER_BACK - 1.22)
KnightBuilder.Cockpit = {
	min = Vector3.new(-INNER_HALF, FLOOR_TOP, INNER_FRONT), -- clear box, torso frame
	max = Vector3.new(INNER_HALF, ROOF_BOTTOM, INNER_BACK),
	footHalf = FOOT_HALF, -- narrower below stepY
	stepY = STEP_Y,
	seatTop = SEAT_POS + Vector3.new(0, SEAT_SIZE.Y / 2, 0),
	hinge = HINGE,
	hatchLength = HATCH_LEN,
}

-- Powered-down kneel ("taking a knee" before its liege): right knee on the
-- ground (on the knee armor's point) with the shin sloping back up to the
-- tucked toe, left foot planted forward and turned out with its shin
-- upright, torso nearly upright, head bowed, left hand on the raised knee,
-- wings folded, hatch down. Pitches: 0 = segment straight down, positive =
-- lower end forward (-Z).
local KNEEL_THIGH = 0.95 -- right thigh reaches forward to the knee
local KNEEL_FOOT = -1.3 -- right foot on its toes
local KNEE_GROUND = 0.08 -- knee armor / toe sink this far into the floor
local LEFT_YAW = 0.4 -- left leg turned out (knee clear of the hatch)
local LEFT_ANKLE_Z = -0.4 -- left ankle ends up here (model z)
local KNEEL_WAIST = -0.08 -- torso leans forward a touch
local KNEEL_NECK = -0.4
local HATCH_LIP = 5.0 -- open hatch lip above the ground (studs)

-- lowest points of the knee armor (shin frame) and the foot (foot frame), (y, z)
local PAD_PTS = { Vector2.new(-1.1, -2.0), Vector2.new(0.4, -0.3), Vector2.new(-2.8, -0.3), Vector2.new(-2.7, -1.0), Vector2.new(-5.3, -1.0), Vector2.new(0, -0.55) }
local FOOT_PTS = { Vector2.new(-ANKLE_H, -2.6), Vector2.new(-ANKLE_H, 1.3), Vector2.new(0.3 - ANKLE_H, -2.6), Vector2.new(0.8 - ANKLE_H, -1.9) }
local function lowest(pts: { Vector2 }, a: number): number
	local low = math.huge
	for _, p in pts do
		low = math.min(low, rotX(Vector3.new(0, p.X, p.Y), a).Y)
	end
	return low
end
-- the shin's rise behind the knee: steep enough that the toe reaches the floor
local kneelShin, kneeY = 0, 0
do
	local lo, hi = 0, 1.2
	for _ = 1, 30 do
		local beta = (lo + hi) / 2
		local shin = -math.pi / 2 - beta
		local ky = KNEE_GROUND - lowest(PAD_PTS, shin)
		local toe = ky + rotX(SHIN_D, shin).Y + lowest(FOOT_PTS, KNEEL_FOOT)
		if toe < KNEE_GROUND then
			lo = beta
		else
			hi = beta
		end
		kneelShin, kneeY = shin, ky
	end
end
local kneelHipY = kneeY - rotX(THIGH_D, KNEEL_THIGH).Y
-- left leg: shin upright, knee straight above the planted ankle
local leftKneeY = ANKLE_H + SHIN_LEN
local leftReach = math.sqrt(math.max(0, THIGH_LEN * THIGH_LEN - (leftKneeY - kneelHipY) ^ 2))
local kneelHipZ = LEFT_ANKLE_Z + leftReach * math.cos(LEFT_YAW)
local KNEEL_DROP = Vector3.new(0, kneelHipY - HIP_Y, kneelHipZ - HIP_POS.Z)
local function rotY(v: Vector3, a: number): Vector3
	return (CFrame.Angles(0, a, 0) * v) :: Vector3
end
local LEFT_ANKLE_REL = rotY(Vector3.new(0, ANKLE_H - kneelHipY, -leftReach), LEFT_YAW) -- from the left hip (left side yaw)

-- hatch open angle (about its hinge) that puts the lip HATCH_LIP above the ground
local hatchAngle: number
do
	local hinge = TORSO_POS + KNEEL_DROP + rotX(HINGE, KNEEL_WAIST)
	local below = math.asin(math.clamp((hinge.Y - HATCH_LIP / SCALE) / HATCH_LEN, -1, 1))
	hatchAngle = -(math.pi / 2 + below) - KNEEL_WAIST
end

KnightBuilder.Kneel = {
	drop = KNEEL_DROP * SCALE, -- Root transform offset (studs)
	thigh = KNEEL_THIGH, -- right leg bone pitches
	shin = kneelShin,
	foot = KNEEL_FOOT,
	rightAnkle = (rotX(THIGH_D, KNEEL_THIGH) + rotX(SHIN_D, kneelShin)) * SCALE, -- from the right hip
	leftAnkle = LEFT_ANKLE_REL * SCALE, -- from the left hip
	leftYaw = LEFT_YAW,
	leftKnee = (LEFT_ANKLE_REL + Vector3.new(0, SHIN_LEN, 0)) * SCALE, -- from the left hip
	waist = KNEEL_WAIST,
	neck = KNEEL_NECK,
	hatchAngle = hatchAngle,
}

type BoneDef = { name: string, parent: string, pos: Vector3, pitch: number?, roll: number?, joint: string }

local BONES: { BoneDef } = {
	{ name = "Waist", parent = "HumanoidRootPart", pos = PELVIS_POS, joint = "Root" },
	{ name = "Torso", parent = "Waist", pos = TORSO_POS, joint = "Waist" },
	{ name = "Head", parent = "Torso", pos = NECK_POS, joint = "Neck" },
	{ name = "Hatch", parent = "Torso", pos = TORSO_POS + HINGE, joint = "HatchHinge" },
}
for _, sd in { { "Right", 1 }, { "Left", -1 } } do
	local n, s = sd[1] :: string, sd[2] :: number
	local legX = Vector3.new(s * LEG_X, 0, 0)
	local roll = s * ARM_ROLL
	local down = Vector3.new(s * math.sin(ARM_ROLL), -math.cos(ARM_ROLL), 0) -- along the arm
	local shoulder = Vector3.new(s * SHOULDER.X, SHOULDER.Y, SHOULDER.Z)
	local elbow = shoulder + down * UPPER_ARM
	table.insert(BONES, { name = "Wing" .. n, parent = "Torso", pos = TORSO_POS + Vector3.new(s * WING_MOUNT.X, WING_MOUNT.Y, WING_MOUNT.Z), joint = "Wing" .. n .. "Mount" })
	table.insert(BONES, { name = n .. "UpperArm", parent = "Torso", pos = shoulder, roll = roll, joint = n .. "Shoulder" })
	table.insert(BONES, { name = n .. "LowerArm", parent = n .. "UpperArm", pos = elbow, roll = roll, joint = n .. "Elbow" })
	table.insert(BONES, { name = n .. "Hand", parent = n .. "LowerArm", pos = elbow + down * FOREARM, roll = roll, joint = n .. "Wrist" })
	table.insert(BONES, { name = n .. "UpperLeg", parent = "Waist", pos = HIP_POS + legX, pitch = HIP_REST, joint = n .. "Hip" })
	table.insert(BONES, { name = n .. "LowerLeg", parent = n .. "UpperLeg", pos = KNEE_POS + legX, pitch = SHIN_REST, joint = n .. "Knee" })
	table.insert(BONES, { name = n .. "Foot", parent = n .. "LowerLeg", pos = ANKLE_POS + legX, joint = n .. "Ankle" })
end
KnightBuilder.Bones = BONES -- design units; multiply positions by Scale for studs

local REST: { [string]: CFrame } = { HumanoidRootPart = CFrame.new(ROOT_POS * SCALE) }
for _, def in BONES do
	REST[def.name] = CFrame.new(def.pos * SCALE) * CFrame.Angles(def.pitch or 0, 0, 0) * CFrame.Angles(0, 0, def.roll or 0)
end
-- rest frame of a bone in model space (studs)
function KnightBuilder.restFrame(name: string): CFrame
	return REST[name]
end

-- Key points of the powered-down kneel in world space, for a mech whose
-- root is at `rootCF`.
export type OffPoints = {
	torso: CFrame, -- the torso (cockpit) frame, studs
	seat: CFrame, -- top center of the seat
	hinge: Vector3, -- hatch hinge (front edge of the cockpit floor)
	lip: Vector3, -- top edge of the open hatch, ~5 studs above the ground
	prompt: Vector3, -- on the ground in front of the lip
	exit: Vector3, -- on the ground where an unseated pilot is put down
	ground: number,
	forward: Vector3,
}
function KnightBuilder.offPoints(rootCF: CFrame): OffPoints
	local K = KnightBuilder.Kneel
	local torso = rootCF * CFrame.new((TORSO_POS - ROOT_POS) * SCALE + K.drop) * CFrame.Angles(K.waist, 0, 0)
	local hingeCF = torso * CFrame.new(HINGE * SCALE) * CFrame.Angles(K.hatchAngle, 0, 0)
	local lip = (hingeCF * CFrame.new(0, HATCH_LEN * SCALE, 0)).Position
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local ground = rootCF.Y - KnightBuilder.RootHeight
	local foot = Vector3.new(lip.X, ground, lip.Z)
	return {
		torso = torso,
		seat = torso * CFrame.new(KnightBuilder.Cockpit.seatTop * SCALE),
		hinge = hingeCF.Position,
		lip = lip,
		prompt = foot + forward * 2.5,
		exit = foot + forward * 5,
		ground = ground,
		forward = forward,
	}
end

local ROT_Y_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
-- Wedges turned so their right-triangle profile faces front (thickness along
-- Z); the key names the right-angle corner as seen from the front.
local CORNER: { [string]: CFrame } = {
	BR = CFrame.Angles(0, math.pi / 2, 0),
	BL = CFrame.Angles(0, -math.pi / 2, 0),
	TL = CFrame.Angles(0, 0, math.pi) * CFrame.Angles(0, math.pi / 2, 0),
	TR = CFrame.Angles(0, 0, math.pi) * CFrame.Angles(0, -math.pi / 2, 0),
}
local MIRROR = { BR = "BL", BL = "BR", TL = "TR", TR = "TL" }

local SHAPES = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

-- Adds one armor piece welded to a bone; `pos` / `rot` in the bone's rest frame.
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

-- A right-triangle plate facing front: `size` = (width, height, thickness),
-- `at` its bounding box frame (bone frame), `corner` the right angle.
local function tri(add: Add, bone: string, size: Vector3, at: CFrame, color: ColorKey, corner: string): BasePart
	return add(bone, "Wedge", Vector3.new(size.Z, size.Y, size.X), at.Position, color, at.Rotation * CORNER[corner])
end

-- Mirrored for side s (-1 = left): corner flipped left / right.
local function side(corner: string, s: number): string
	return if s > 0 then corner else MIRROR[corner]
end

-- Hexagonal prism facing back (+Z), from three rectangles 60 degrees apart
-- (depths staggered so no two faces share a plane). f = flat-to-flat width.
local function hex(add: Add, bone: string, center: Vector3, f: number, depth: number, color: ColorKey)
	local r = f / math.sqrt(3)
	for i = 0, 2 do
		add(bone, "Block", Vector3.new(r, f, depth + i * 0.14), center, color, CFrame.Angles(0, 0, i * math.pi / 3))
	end
end


local FLIP = CFrame.Angles(0, 0, math.pi) -- wedge sloped underneath, thick end at the back

local function buildHelmet(add: Add)
	local H = "Head" -- origin at the neck joint
	add(H, "Cylinder", Vector3.new(0.7, 1.0, 1.0), Vector3.new(0, 0.35, 0), "dark", ROT_Y_AXIS) -- neck
	add(H, "Block", Vector3.new(1.8, 1.8, 2.0), Vector3.new(0, 1.2, 0.15), "main") -- helmet
	add(H, "Block", Vector3.new(1.3, 0.9, 0.2), Vector3.new(0, 0.85, -0.95), "dark") -- face
	-- eyes: narrow slits angled up at the outer ends
	add(H, "Block", Vector3.new(0.42, 0.12, 0.08), Vector3.new(0.36, 1.02, -1.09), "light", CFrame.Angles(0, 0, 0.25))
	add(H, "Block", Vector3.new(0.42, 0.12, 0.08), Vector3.new(-0.36, 1.02, -1.09), "light", CFrame.Angles(0, 0, -0.25))
	-- white chin guard coming to a point, blue stripe
	tri(add, H, Vector3.new(0.7, 0.8, 0.45), CFrame.new(-0.35, 0.25, -1.0), "main", "TR")
	tri(add, H, Vector3.new(0.7, 0.8, 0.45), CFrame.new(0.35, 0.25, -1.0), "main", "TL")
	add(H, "Block", Vector3.new(0.5, 0.1, 0.06), Vector3.new(0, 0.55, -1.26), "accent")
	-- gold faceplate: brow sloping up and back, nose point down between the eyes
	add(H, "Wedge", Vector3.new(2.0, 0.9, 1.3), Vector3.new(0, 1.75, -0.55), "panel")
	tri(add, H, Vector3.new(0.55, 0.5, 0.25), CFrame.new(-0.275, 1.2, -1.1), "panel", "TR")
	tri(add, H, Vector3.new(0.55, 0.5, 0.25), CFrame.new(0.275, 1.2, -1.1), "panel", "TL")
	add(H, "Block", Vector3.new(1.5, 0.3, 1.2), Vector3.new(0, 2.2, 0.45), "main") -- crown
	for _, s in { 1, -1 } do
		add(H, "Block", Vector3.new(0.12, 0.65, 1.0), Vector3.new(s * 1.0, 1.7, 0.1), "accent") -- blue side panels
		add(H, "Block", Vector3.new(0.22, 0.9, 1.3), Vector3.new(s * 1.02, 0.75, -0.05), "main") -- cheek guards
		-- horn fins: tall, raked back a touch, tips out
		local horn = CFrame.new(s * 0.8, 1.85, -0.2) * CFrame.Angles(0.1, 0, -s * 0.12)
		add(H, "Wedge", Vector3.new(0.14, 1.8, 0.6), horn.Position, "panel", horn.Rotation)
		local fin = CFrame.new(s * 1.02, 1.95, 0.1) * CFrame.Angles(0.15, 0, -s * 0.2)
		add(H, "Wedge", Vector3.new(0.1, 1.2, 0.45), fin.Position, "main", fin.Rotation)
	end
end

local function buildChest(add: Add)
	local T = "Torso" -- origin at the waist pivot; the cockpit frame
	local shellDepth = BACK_OUTER - HATCH_OUTER
	local shellZ = (BACK_OUTER + HATCH_OUTER) / 2
	-- interior fittings the pilot walks past: never solid
	local function ghost(part: BasePart): BasePart
		part.CanCollide = false
		return part
	end

	-- cockpit shell: narrow footwell below the console ledges, full width above
	add(T, "Block", Vector3.new(FOOT_HALF * 2, FLOOR_TOP - FLOOR_BOTTOM, shellDepth), Vector3.new(0, (FLOOR_TOP + FLOOR_BOTTOM) / 2, shellZ), "dark").Name = "CockpitFloor"
	add(T, "Block", Vector3.new(INNER_HALF * 2, ROOF_TOP - ROOF_BOTTOM, shellDepth), Vector3.new(0, (ROOF_TOP + ROOF_BOTTOM) / 2, shellZ), "main")
	add(T, "Block", Vector3.new(FOOT_HALF * 2, STEP_Y - FLOOR_TOP, BACK_OUTER - INNER_BACK), Vector3.new(0, (STEP_Y + FLOOR_TOP) / 2, (INNER_BACK + BACK_OUTER) / 2), "dark")
	add(T, "Block", Vector3.new(INNER_HALF * 2, ROOF_BOTTOM - STEP_Y, BACK_OUTER - INNER_BACK), Vector3.new(0, (ROOF_BOTTOM + STEP_Y) / 2, (INNER_BACK + BACK_OUTER) / 2), "dark")
	add(T, "Block", Vector3.new(1.7, 0.3, 3.7), Vector3.new(0, FLOOR_BOTTOM - 0.15, -0.2), "dark") -- belly
	for _, s in { 1, -1 } do
		add(T, "Block", Vector3.new(WAIST_HALF - FOOT_HALF, STEP_Y - 0.2 - FLOOR_BOTTOM, shellDepth), Vector3.new(s * (WAIST_HALF + FOOT_HALF) / 2, (STEP_Y - 0.2 + FLOOR_BOTTOM) / 2, shellZ), "dark") -- waist walls
		add(T, "Block", Vector3.new(POD_HALF - FOOT_HALF, 0.2, INNER_BACK - INNER_FRONT), Vector3.new(s * (POD_HALF + FOOT_HALF) / 2, STEP_Y - 0.1, (INNER_BACK + INNER_FRONT) / 2), "dark") -- console ledge
		add(T, "Block", Vector3.new(POD_HALF - INNER_HALF, ROOF_TOP - STEP_Y, shellDepth), Vector3.new(s * (POD_HALF + INNER_HALF) / 2, (ROOF_TOP + STEP_Y) / 2, shellZ), "main")
		-- flank armor: full width at the top, tapering to the waist
		add(T, "Block", Vector3.new(0.65, 2.0, 3.3), Vector3.new(s * 1.975, 3.6, -0.05), "main")
		tri(add, T, Vector3.new(1.0, 1.45, 3.2), CFrame.new(s * 1.8, 1.875, -0.05), "main", side("TL", s))
		add(T, "Block", Vector3.new(0.1, 0.6, 2.0), Vector3.new(s * 2.35, 2.95, -0.1), "panel")
		add(T, "Block", Vector3.new(0.06, 0.45, 0.14), Vector3.new(s * 2.43, 2.95, -0.7), "accent")
		add(T, "Block", Vector3.new(0.6, 1.1, 1.2), Vector3.new(s * 2.6, 3.95, 0), "dark") -- shoulder yoke
		-- interior: screens on the console ledges, strips on the back wall
		add(T, "Block", Vector3.new(0.3, 0.07, 0.7), Vector3.new(s * 1.3, STEP_Y + 0.035, -0.9), "glow")
		add(T, "Block", Vector3.new(0.3, 0.07, 0.5), Vector3.new(s * 1.3, STEP_Y + 0.035, 0.0), "screen")
		add(T, "Block", Vector3.new(0.08, 2.4, 0.08), Vector3.new(s * 1.0, 2.9, INNER_BACK - 0.04), "glow")
	end
	add(T, "Block", Vector3.new(1.0, 0.08, 0.3), Vector3.new(0, ROOF_BOTTOM - 0.04, -0.2), "glow") -- dome light
	-- HUD bar hanging from the roof's front edge, screens facing the pilot
	ghost(add(T, "Block", Vector3.new(2.2, 0.4, 0.3), Vector3.new(0, ROOF_BOTTOM - 0.2, INNER_FRONT + 0.2), "dark"))
	add(T, "Block", Vector3.new(0.9, 0.2, 0.07), Vector3.new(-0.5, ROOF_BOTTOM - 0.2, INNER_FRONT + 0.385), "glow")
	add(T, "Block", Vector3.new(0.7, 0.2, 0.07), Vector3.new(0.6, ROOF_BOTTOM - 0.2, INNER_FRONT + 0.385), "screen")

	-- seat
	add(T, "Seat", SEAT_SIZE, SEAT_POS, "dark") -- "PilotSeat", kept outside the armor folder
	local seatBottom = SEAT_POS.Y - SEAT_SIZE.Y / 2
	ghost(add(T, "Block", Vector3.new(1.0, seatBottom - FLOOR_TOP, 1.0), Vector3.new(0, (seatBottom + FLOOR_TOP) / 2, SEAT_POS.Z + 0.1), "dark")) -- pedestal
	ghost(add(T, "Block", Vector3.new(1.6, 2.0, 0.2), Vector3.new(0, SEAT_POS.Y + 1.1, SEAT_POS.Z + 0.75), "dark")) -- seat back
	ghost(add(T, "Block", Vector3.new(1.0, 0.5, 0.2), Vector3.new(0, SEAT_POS.Y + 2.4, SEAT_POS.Z + 0.8), "accent")) -- headrest

	-- hatch: the white chest plate, hinged at the cockpit floor's front edge
	local function hatch(kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
		return add("Hatch", kind, size, pos - HINGE, color, rot)
	end
	local function htri(size: Vector3, pos: Vector3, color: ColorKey, corner: string): BasePart
		return tri(add, "Hatch", size, CFrame.new(pos - HINGE), color, corner)
	end
	local hcz = INNER_FRONT - HATCH_T / 2
	hatch("Block", Vector3.new(FOOT_HALF * 2 - 0.12, STEP_Y - FLOOR_TOP, HATCH_T), Vector3.new(0, (FLOOR_TOP + STEP_Y) / 2, hcz), "main").Name = "CockpitHatch"
	hatch("Block", Vector3.new(INNER_HALF * 2 - 0.12, ROOF_BOTTOM - STEP_Y, HATCH_T), Vector3.new(0, (STEP_Y + ROOF_BOTTOM) / 2, hcz), "main")
	local hz = HATCH_OUTER - 0.1 -- outer plate center
	hatch("Block", Vector3.new(3.1, 2.3, 0.2), Vector3.new(0, 3.0, hz), "main")
	htri(Vector3.new(1.55, 1.3, 0.2), Vector3.new(-0.775, 1.2, hz), "main", "TR") -- V point at the bottom
	htri(Vector3.new(1.55, 1.3, 0.2), Vector3.new(0.775, 1.2, hz), "main", "TL")
	-- gold V bib (continues the collar), white center inside it
	htri(Vector3.new(1.6, 1.3, 0.12), Vector3.new(-0.8, 4.0, HATCH_OUTER - 0.26), "panel", "TR")
	htri(Vector3.new(1.6, 1.3, 0.12), Vector3.new(0.8, 4.0, HATCH_OUTER - 0.26), "panel", "TL")
	htri(Vector3.new(0.8, 0.65, 0.1), Vector3.new(-0.4, 4.25, HATCH_OUTER - 0.37), "main", "TR")
	htri(Vector3.new(0.8, 0.65, 0.1), Vector3.new(0.4, 4.25, HATCH_OUTER - 0.37), "main", "TL")
	for _, s in { 1, -1 } do
		-- blue insets along the V
		hatch("Block", Vector3.new(1.2, 0.14, 0.06), Vector3.new(s * 0.8, 1.55, HATCH_OUTER - 0.23), "accent", CFrame.Angles(0, 0, s * 0.698))
	end
	hatch("Block", Vector3.new(0.25, 1.9, 0.25), Vector3.new(0, 2.9, HATCH_OUTER - 0.2), "main", CFrame.Angles(0, math.pi / 4, 0)) -- center keel
	for i = 0, 3 do
		-- deck strips on the inner face (the walkway when open)
		hatch("Block", Vector3.new(1.8, 0.12, 0.08), Vector3.new(0, FLOOR_TOP + 0.5 + i * 0.95, INNER_FRONT + 0.04), "glow")
	end

	-- gold collar / gorget above the hatch, rising to the neck
	add(T, "Wedge", Vector3.new(3.3, 0.35, 1.5), Vector3.new(0, ROOF_TOP + 0.175, -1.2), "panel")
	add(T, "Block", Vector3.new(3.3, 0.4, 2.1), Vector3.new(0, ROOF_TOP + 0.2, 0.6), "main") -- upper back
	for _, s in { 1, -1 } do
		local wing = CFrame.new(s * 1.35, ROOF_TOP + 0.45, -0.6) * CFrame.Angles(0, 0, s * 0.35)
		add(T, "Block", Vector3.new(1.3, 0.35, 1.6), wing.Position, "panel", wing.Rotation)
	end

	-- backpack: grey spine with a hex core, bridge across the shoulders
	add(T, "Block", Vector3.new(2.0, 4.4, 1.25), Vector3.new(0, 2.5, BACK_OUTER + 0.625), "dark")
	add(T, "Block", Vector3.new(3.0, 1.1, 1.0), Vector3.new(0, 4.35, BACK_OUTER + 0.58), "dark")
	add(T, "Block", Vector3.new(2.6, 0.2, 0.8), Vector3.new(0, 4.95, BACK_OUTER + 0.55), "panel")
	local hz0 = BACK_OUTER + 1.3 -- hex cells centered here (spine back face at BACK_OUTER + 1.25)
	for _, y in { 1.0, 1.66, 2.32 } do
		hex(add, T, Vector3.new(0, y, hz0), 0.6, 0.3, "accent")
	end
	for _, c in { Vector2.new(0.57, 1.33), Vector2.new(-0.57, 1.33), Vector2.new(0.57, 1.99), Vector2.new(-0.57, 1.99) } do
		hex(add, T, Vector3.new(c.X, c.Y, hz0), 0.6, 0.3, "panel")
	end
	for _, s in { 1, -1 } do
		add(T, "Cylinder", Vector3.new(0.5, 0.7, 0.7), Vector3.new(s * WING_MOUNT.X, WING_MOUNT.Y, WING_MOUNT.Z), "dark") -- wing pivots
	end

	-- wing binders: tall white plates flanking the spine, tops out and back
	for _, sd in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local W = "Wing" .. n
		local lean = CFrame.Angles(0.2, 0, -s * 0.15)
		local function at(p: Vector3): CFrame
			return lean * CFrame.new(p)
		end
		local plate = at(Vector3.new(s * 1.0, -0.9, 0.35))
		add(W, "Block", Vector3.new(1.9, 5.4, 0.3), plate.Position, "main", plate.Rotation)
		tri(add, W, Vector3.new(1.9, 1.3, 0.18), at(Vector3.new(s * 1.0, 2.45, 0.35)), "main", side("BR", s))
		local rim = at(Vector3.new(s * 0.05, -0.7, 0.35))
		add(W, "Block", Vector3.new(0.2, 4.8, 0.45), rim.Position, "dark", rim.Rotation)
		local stripe = at(Vector3.new(s * 1.4, -0.7, 0.53))
		add(W, "Block", Vector3.new(0.12, 3.5, 0.06), stripe.Position, "accent", stripe.Rotation)
		tri(add, W, Vector3.new(1.9, 0.8, 0.42), at(Vector3.new(s * 1.0, -4.0, 0.35)), "panel", side("TR", s)) -- gold lower tip
	end

	-- arms (bone frames lean out with the arm; -Y runs down the arm)
	for _, sd in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local UA, LA, HD = n .. "UpperArm", n .. "LowerArm", n .. "Hand"

		-- pauldron: layered plates swept up at the outer ends, tall fins rising at the collar
		add(UA, "Ball", Vector3.new(1.2, 1.2, 1.2), Vector3.new(-s * 0.3, 0, 0), "dark")
		add(UA, "Block", Vector3.new(2.0, 1.6, 2.3), Vector3.new(s * 0.2, 0.35, 0), "main")
		local l1 = CFrame.new(s * 0.3, 1.3, 0) * CFrame.Angles(0, 0, s * 0.3)
		add(UA, "Block", Vector3.new(2.0, 0.4, 2.62), l1.Position, "main", l1.Rotation)
		tri(add, UA, Vector3.new(0.9, 0.9, 2.76), l1 * CFrame.new(s * 1.45, 0.25, 0), "main", side("BR", s))
		local l2 = CFrame.new(s * 0.6, 0.55, 0) * CFrame.Angles(0, 0, s * 0.45)
		add(UA, "Block", Vector3.new(1.8, 0.35, 2.44), l2.Position, "panel", l2.Rotation)
		tri(add, UA, Vector3.new(0.7, 0.7, 2.44), l2 * CFrame.new(s * 1.25, 0.175, 0), "panel", side("BR", s))
		local l3 = CFrame.new(s * 0.6, -0.25, 0) * CFrame.Angles(0, 0, s * 0.2)
		add(UA, "Block", Vector3.new(1.8, 0.3, 2.1), l3.Position, "main", l3.Rotation)
		tri(add, UA, Vector3.new(0.7, 2.2, 0.3), CFrame.new(-s * 1.05, 2.1, 0.1) * CFrame.Angles(0, 0, s * 0.2), "main", side("BR", s))
		tri(add, UA, Vector3.new(0.5, 1.6, 0.3), CFrame.new(-s * 0.45, 1.8, 0.45) * CFrame.Angles(0, 0, s * 0.25), "panel", side("BR", s))
		-- upper arm
		add(UA, "Cylinder", Vector3.new(1.2, 1.0, 1.0), Vector3.new(0, -0.9, 0), "dark", ROT_Y_AXIS)
		add(UA, "Block", Vector3.new(1.6, 1.0, 1.4), Vector3.new(0, -1.2, 0), "main")
		add(UA, "Block", Vector3.new(1.0, 0.12, 0.06), Vector3.new(0, -1.2, -0.73), "accent")

		-- forearm guard: white, gold plate and flare on the outer side
		add(LA, "Ball", Vector3.new(1.1, 1.1, 1.1), Vector3.zero, "dark")
		add(LA, "Block", Vector3.new(1.4, 2.6, 1.5), Vector3.new(0, -1.55, 0), "main")
		add(LA, "Block", Vector3.new(0.3, 2.3, 1.2), Vector3.new(s * 0.85, -1.5, 0), "panel")
		tri(add, LA, Vector3.new(0.7, 0.9, 1.0), CFrame.new(s * 1.3, -0.6, 0), "panel", side("BL", s))
		add(LA, "Block", Vector3.new(1.0, 1.8, 0.12), Vector3.new(0, -1.6, -0.81), "main")
		add(LA, "Block", Vector3.new(0.6, 0.1, 0.06), Vector3.new(0, -0.9, -0.9), "accent")
		add(LA, "Block", Vector3.new(1.1, 0.4, 1.2), Vector3.new(0, -2.95, 0), "dark") -- cuff

		-- clawed hand, palm facing in
		add(HD, "Block", Vector3.new(0.85, 0.8, 0.95), Vector3.new(0, -0.45, 0), "dark")
		for _, z in { -0.28, 0, 0.28 } do
			local f = CFrame.new(-s * 0.05, -1.15, z) * CFrame.Angles(0, 0, -s * 0.25)
			add(HD, "Block", Vector3.new(0.22, 0.75, 0.22), f.Position, "dark", f.Rotation)
		end
		local thumb = CFrame.new(-s * 0.36, -0.6, -0.45) * CFrame.Angles(-0.3, 0, -s * 0.3)
		add(HD, "Block", Vector3.new(0.22, 0.55, 0.22), thumb.Position, "dark", thumb.Rotation)
	end
end

local function buildLegs(add: Add)
	local W = "Waist" -- pelvis, origin at PELVIS_POS
	add(W, "Block", Vector3.new(2.0, 0.8, 1.8), Vector3.new(0, -0.1, 0.1), "dark")
	for _, s in { 1, -1 } do
		add(W, "Cylinder", Vector3.new(0.8, 1.1, 1.1), Vector3.new(s * 1.3, 0.15, 0), "dark") -- hip joints
		add(W, "Ball", Vector3.new(1.4, 1.4, 1.4), Vector3.new(s * 1.35, -0.4, 0.75), "dark") -- rear hip bulk
	end
	-- pointed tasset: gold outline, white center
	add(W, "Block", Vector3.new(1.9, 0.7, 0.3), Vector3.new(0, 0.05, -1.0), "panel")
	tri(add, W, Vector3.new(0.95, 1.6, 0.3), CFrame.new(-0.475, -1.1, -1.0), "panel", "TR")
	tri(add, W, Vector3.new(0.95, 1.6, 0.3), CFrame.new(0.475, -1.1, -1.0), "panel", "TL")
	add(W, "Block", Vector3.new(1.2, 0.5, 0.15), Vector3.new(0, 0.05, -1.23), "main")
	tri(add, W, Vector3.new(0.6, 1.3, 0.15), CFrame.new(-0.3, -0.85, -1.23), "main", "TR")
	tri(add, W, Vector3.new(0.6, 1.3, 0.15), CFrame.new(0.3, -0.85, -1.23), "main", "TL")
	add(W, "Block", Vector3.new(0.6, 0.1, 0.05), Vector3.new(0, 0.1, -1.33), "accent")
	-- rear: grey skirt bar and a pointed tail
	add(W, "Block", Vector3.new(2.8, 0.5, 0.8), Vector3.new(0, 0.35, 1.35), "dark")
	add(W, "Block", Vector3.new(1.0, 1.0, 0.4), Vector3.new(0, -0.4, 1.52), "dark")
	tri(add, W, Vector3.new(0.5, 0.8, 0.3), CFrame.new(-0.25, -1.3, 1.4), "panel", "TR")
	tri(add, W, Vector3.new(0.5, 0.8, 0.3), CFrame.new(0.25, -1.3, 1.4), "panel", "TL")

	for _, sd in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local UL, LL, F = n .. "UpperLeg", n .. "LowerLeg", n .. "Foot"

		-- thigh: grey frame and hip block, white plates front / outside / inside, hamstring bulk
		add(UL, "Ball", Vector3.new(1.2, 1.2, 1.2), Vector3.zero, "dark")
		add(UL, "Block", Vector3.new(1.3, 3.0, 1.4), Vector3.new(-s * 0.05, -1.8, 0.05), "dark")
		add(UL, "Block", Vector3.new(0.46, 1.2, 1.1), Vector3.new(-s * 1.02, -0.8, 0), "dark")
		add(UL, "Block", Vector3.new(1.46, 2.2, 0.35), Vector3.new(-s * 0.05, -1.7, -0.83), "main")
		add(UL, "Block", Vector3.new(0.25, 2.6, 1.44), Vector3.new(s * 0.745, -1.8, -0.05), "main")
		add(UL, "Block", Vector3.new(0.2, 1.9, 1.36), Vector3.new(-s * 0.82, -2.0, -0.05), "main")
		add(UL, "Block", Vector3.new(0.12, 1.2, 0.06), Vector3.new(s * 0.45, -1.7, -1.035), "accent")
		add(UL, "Block", Vector3.new(1.1, 1.8, 0.5), Vector3.new(-s * 0.05, -1.4, 0.95), "main")

		-- knee: big diamond-profile armor pointing forward, grey side plate
		add(LL, "Cylinder", Vector3.new(1.56, 1.1, 1.1), Vector3.new(0, 0, 0.05), "dark")
		add(LL, "Wedge", Vector3.new(2.45, 1.5, 1.7), Vector3.new(-s * 0.03, -0.35, -1.15), "main")
		add(LL, "Wedge", Vector3.new(2.45, 1.7, 1.7), Vector3.new(-s * 0.03, -1.95, -1.15), "main", FLIP)
		add(LL, "Block", Vector3.new(0.3, 2.4, 1.2), Vector3.new(s * 1.25, -1.6, -0.5), "dark")
		-- pointed top of the knee shield (a V seen from the front)
		tri(add, LL, Vector3.new(1.2, 0.7, 0.3), CFrame.new(-s * 0.03 - 0.6, 0.75, -1.2), "main", "BR")
		tri(add, LL, Vector3.new(1.2, 0.7, 0.3), CFrame.new(-s * 0.03 + 0.6, 0.75, -1.2), "main", "BL")
		-- shin: flared at the bottom, blue insets front, grey calf with a blue strip
		add(LL, "Block", Vector3.new(1.6, 4.3, 1.1), Vector3.new(0, -3.2, -0.25), "main")
		add(LL, "Block", Vector3.new(1.4, 2.6, 0.2), Vector3.new(0, -4.0, -0.9), "main")
		for _, f in { 1, -1 } do
			tri(add, LL, Vector3.new(0.2, 1.5, 0.9), CFrame.new(f * 0.9, -4.55, -0.25), "main", if f > 0 then "BL" else "BR")
			add(LL, "Block", Vector3.new(0.45, 0.55, 0.06), Vector3.new(f * 0.4, -4.85, -1.03), "accent")
			add(LL, "Block", Vector3.new(0.3, 2.2, 1.0), Vector3.new(f * 1.02, -2.7, 0.45), "dark")
		end
		add(LL, "Block", Vector3.new(0.86, 3.2, 0.7), Vector3.new(0, -2.9, 0.6), "dark")
		add(LL, "Block", Vector3.new(0.7, 2.4, 0.1), Vector3.new(0, -2.9, 1.0), "accent")

		-- blocky foot with a toe cap
		add(F, "Ball", Vector3.new(1.0, 1.0, 1.0), Vector3.zero, "dark")
		add(F, "Block", Vector3.new(1.2, 0.7, 1.2), Vector3.new(0, -0.55, 0.1), "dark")
		add(F, "Block", Vector3.new(1.56, 0.55, 2.4), Vector3.new(0, -0.85, -0.7), "main")
		add(F, "Block", Vector3.new(1.7, 0.3, 3.9), Vector3.new(0, 0.15 - ANKLE_H, -0.65), "dark") -- sole
		add(F, "Wedge", Vector3.new(1.56, 0.5, 0.7), Vector3.new(0, 0.55 - ANKLE_H, -2.25), "main") -- toe cap
		add(F, "Block", Vector3.new(1.4, 0.5, 0.7), Vector3.new(0, -0.85, 0.95), "dark") -- heel
		add(F, "Block", Vector3.new(0.6, 0.08, 0.3), Vector3.new(0, -0.535, -1.2), "accent")
	end
end

local SLOT_BUILDERS = {
	Helmet = buildHelmet,
	Chest = buildChest,
	Legs = buildLegs,
}

-- Builds the bare rig: root, bones, motors, humanoid. No armor.
function KnightBuilder.buildRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", KnightBuilder.TypeId) -- see MechTypes

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
	humanoid.HipHeight = KnightBuilder.HipHeight
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

-- Replaces the armor in one slot with the given color variant. Parts are
-- placed from the bones' rest frames, so the rig must be in its rest pose
-- (or the welds settle them on the next physics step).
function KnightBuilder.applySlot(model: Model, slot: string, variantId: string)
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
function KnightBuilder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = KnightBuilder.buildRig(name)
	for _, slot in MechConfig.Slots do
		KnightBuilder.applySlot(model, slot, loadout[slot])
	end
	return model
end

return KnightBuilder
