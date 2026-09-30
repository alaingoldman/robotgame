--!strict
-- Builds the HWM-04B mech out of primitive parts.
--
-- The rig is a set of invisible "bone" parts joined by Motor6Ds. Visible armor
-- is welded to the bones and grouped into three swappable slots:
--   Helmet -> Head
--   Chest  -> Torso, cockpit (doors, ramp), arms, hands, backpack, guns
-- The pilot seat is built with the chest but lives directly under the model,
-- so swapping the Chest armor never drops a seated pilot.
--   Legs   -> Waist, legs, feet
-- Coordinates below are in design units, model space, origin on the ground
-- between the feet, facing -Z. Everything is multiplied by SCALE when built,
-- so the finished mech is about 17.2 * SCALE (~29) studs tall.
--
-- Bones carry a rest angle (pitch, radians) baked into their motor, which gives
-- the hunched profile: torso leaning forward, forearms bent, shins slanting back.
-- Positive pitch swings a limb's lower end forward (-Z). Animation Transforms
-- are applied on top of this rest pose.
--
-- The cockpit fills the chest. It is built in its own "cockpit frame": the
-- torso frame tilted back by COCKPIT_TILT, which is level when the mech
-- kneels with its torso bowed forward (the powered-down pose). Its front is
-- two doors hinged at the outer edges that swing out to the sides, and
-- behind them a ramp plate hinged at the floor's front edge that folds down
-- to the ground so the pilot can walk in.

local MechConfig = require(script.Parent.MechConfig)

local MechBuilder = {}

type Palette = MechConfig.Palette
-- "glow" is a Neon accent that stays lit while the mech is powered down
type ColorKey = "main" | "panel" | "dark" | "accent" | "light" | "glow"

local SCALE = MechConfig.Scale
MechBuilder.Scale = SCALE

-- Collision groups (registered by MechService): armor is solid to on-foot
-- players only, so it never drags on the ground or snags other mechs; the
-- root is the mech's body against the world. A pilot strapped into the seat
-- collides with nothing.
MechBuilder.ArmorGroup = "MechArmor"
MechBuilder.RootGroup = "MechRoot"
MechBuilder.PlayerGroup = "Players"
MechBuilder.PilotGroup = "Pilot"

local ROOT_POS = Vector3.new(0, 10.6, 0)
local ROOT_SIZE = Vector3.new(5, 4, 3)
MechBuilder.RootHeight = ROOT_POS.Y * SCALE -- root center above the ground
MechBuilder.HipHeight = (ROOT_POS.Y - ROOT_SIZE.Y / 2) * SCALE

local TORSO_LEAN = -0.22 -- top of the torso tips forward
local HIP_REST = 0.15
local KNEE_REST = -0.38
local ELBOW_REST = 0.32
MechBuilder.HipRest = HIP_REST
MechBuilder.KneeRest = KNEE_REST

local WAIST_POS = Vector3.new(0, 9.6, 0)
local TORSO_POS = Vector3.new(0, 10.4, 0)
local LEG_X = 2.9 -- hips sit wide so the cockpit fits between the knees when kneeling

-- Cockpit, in cockpit-frame design units (origin at the torso joint).
-- Interior: +-1.42 wide, FLOOR_TOP..ROOF_BOTTOM tall, INNER_FRONT..INNER_BACK
-- deep = 4.8 x 7.3 x 5.3 studs scaled. A seated avatar with long hair
-- measures 4.2 x 6.75 x 4.55.
local COCKPIT_TILT = 0.7 -- cockpit frame relative to the torso (tilted back)
local POD_HALF = 1.6 -- outer half width (walls 0.18 thick)
local INNER_HALF = 1.42
local FLOOR_TOP = -2.0
local FLOOR_BOTTOM = -2.25
local ROOF_BOTTOM = FLOOR_TOP + 4.3
local ROOF_TOP = ROOF_BOTTOM + 0.2
local INNER_BACK = -0.9
local BACK_OUTER = INNER_BACK + 0.2
local INNER_FRONT = INNER_BACK - 3.1 -- ramp inner face (closed) = ramp hinge line
local RAMP_THICK = 0.25
local RAMP_LENGTH = 3.6
local DOOR_INNER = INNER_FRONT - RAMP_THICK - 0.05
local DOOR_OUTER = DOOR_INNER - 0.3
local RAMP_HINGE = Vector3.new(0, FLOOR_TOP, INNER_FRONT)
local SEAT_SIZE = Vector3.new(1.6, 0.25, 1.3)
local SEAT_POS = Vector3.new(0, FLOOR_TOP + 1.318 - SEAT_SIZE.Y / 2, INNER_BACK - 1.144) -- seat top 2.24 studs above the floor

-- Powered-down kneel: how far the hips (and the whole body with them) move,
-- design units; knees end up on the ground. The torso bows forward until the
-- cockpit frame is level, which puts the cockpit floor ~3.7 studs up.
local OFF_DROP = Vector3.new(0, -6.2, -0.35)
MechBuilder.OffDrop = OFF_DROP * SCALE
MechBuilder.OffTorsoBow = -COCKPIT_TILT - TORSO_LEAN -- Waist motor transform pitch

-- Ramp open angle (radians, negative = top falls forward): it swings down
-- until its inner top edge rests on the ground.
local rampHingeOff = TORSO_POS.Y + OFF_DROP.Y + FLOOR_TOP
MechBuilder.RampOpenAngle = -(math.pi / 2 + math.asin(rampHingeOff / RAMP_LENGTH))
-- Door open angle about the hinge (the left door turns positive).
MechBuilder.DoorOpenAngle = math.rad(115)

local function rotX(v: Vector3, a: number): Vector3
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end

-- One-knee kneel (the "OffPose" = "OneKnee" model attribute): "taking a
-- knee". The right knee rests on the ground with the shin sloping up behind
-- it onto the tucked toe; the left foot stays planted flat where it stood,
-- thigh about level, while the body moves back over the kneeling leg. The
-- torso bows less than in the deep kneel, so the cockpit ends up tilted a
-- little nose-up, and the ramp hangs steeply with its lip off the ground.
-- Angles are bone pitches in the (level) waist frame, design units.
local KNEEL_THIGH = -0.08 -- right thigh: knee just behind the hip
local KNEEL_FOOT = -1.45 -- right foot stands on its toes, heel up
local KNEE_GROUND = 0.1 -- knee pad and toe sink this far into the floor, like the soles
local LEFT_PLANT = 1.7 -- left ankle this far ahead of the hip
local ONE_KNEE_TILT = 0.2 -- cockpit pitch (nose up)
local ONE_KNEE_LIP = 5.4 -- ramp lip height above the ground, studs: a hang for an avatar

local THIGH_D = Vector3.new(0, -3.5, 0) -- hip -> knee, thigh bone frame
local SHIN_D = Vector3.new(0, -4.2, 0.2) -- knee -> ankle, shin bone frame
local ANKLE_STAND = rotX(THIGH_D, HIP_REST) + rotX(SHIN_D, HIP_REST + KNEE_REST) -- hip -> ankle standing
-- lowest points of the knee pad (shin frame) and the toe / heel (foot frame), (y, z)
local PAD_PTS = { Vector2.new(0.65, -1.4), Vector2.new(-0.85, -1.4) }
local FOOT_PTS = { Vector2.new(-1.4, -3.75), Vector2.new(-1.5, -3.35), Vector2.new(-1.5, -1.05), Vector2.new(-1.5, 1.9), Vector2.new(-1.275, 2.45) }
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
local oneKneeHip = Vector3.new(0, kneeY, 0) - rotX(THIGH_D, KNEEL_THIGH) -- relative to the knee
local oneKneeHipZ = ANKLE_STAND.Z + LEFT_PLANT
local ONE_KNEE_DROP = Vector3.new(0, oneKneeHip.Y - 9.0, oneKneeHipZ) -- hips start at y 9
local ONE_KNEE_WAIST = ONE_KNEE_TILT - COCKPIT_TILT - TORSO_LEAN

-- Ramp angle (about the cockpit-frame hinge) that puts the lip `lipY` above
-- the ground, for a cockpit whose torso joint moved by `drop` and pitched `tilt`.
local function rampAngle(drop: Vector3, tilt: number, lipY: number): number
	local hinge = TORSO_POS + drop + rotX(RAMP_HINGE, tilt)
	local below = math.asin(math.clamp((hinge.Y - lipY) / RAMP_LENGTH, -1, 1)) -- world angle below level
	return -(math.pi / 2 + below) - tilt
end

-- Powered-down pose styles, by "OffPose" attribute (default "Kneel"):
-- body drop (Root transform offset, studs), Waist pitch, the cockpit frame's
-- resulting pitch (0 level, positive nose up) and the ramp's open angle.
export type OffStyle = { drop: Vector3, waist: number, tilt: number, rampAngle: number }
MechBuilder.OffStyles = {
	Kneel = { drop = MechBuilder.OffDrop, waist = MechBuilder.OffTorsoBow, tilt = 0, rampAngle = MechBuilder.RampOpenAngle },
	OneKnee = {
		drop = ONE_KNEE_DROP * SCALE,
		waist = ONE_KNEE_WAIST,
		tilt = ONE_KNEE_TILT,
		rampAngle = rampAngle(ONE_KNEE_DROP, ONE_KNEE_TILT, ONE_KNEE_LIP / SCALE),
	},
} :: { [string]: OffStyle }

function MechBuilder.offStyle(name: string?): OffStyle
	return MechBuilder.OffStyles[name or "Kneel"] or MechBuilder.OffStyles.Kneel
end

-- The one-knee legs at full pose (studs, waist frame), for MechPose's IK:
-- final right leg bone pitches and ankle (relative to the dropped hip), and
-- the right foot's toe pivot (foot frame).
MechBuilder.OneKneeLegs = {
	thigh = KNEEL_THIGH,
	shin = kneelShin,
	foot = KNEEL_FOOT,
	rightAnkle = (rotX(THIGH_D, KNEEL_THIGH) + rotX(SHIN_D, kneelShin)) * SCALE,
}

-- Cockpit-frame position -> torso-frame position.
local function cockpitToTorso(p: Vector3): Vector3
	return (CFrame.Angles(COCKPIT_TILT, 0, 0) * p) :: Vector3
end

type BoneDef = { name: string, parent: string, pos: Vector3, joint: string, rest: number? }

-- name, parent, joint origin (model space, before rest angles), motor name, rest pitch
local BONES: { BoneDef } = {
	{ name = "Waist", parent = "HumanoidRootPart", pos = WAIST_POS, joint = "Root" },
	{ name = "Torso", parent = "Waist", pos = TORSO_POS, joint = "Waist", rest = TORSO_LEAN },
	{ name = "Head", parent = "Torso", pos = Vector3.new(0, 14.6, 0.35), joint = "Neck", rest = 0.14 },
	-- cockpit hinges carry the cockpit tilt so they turn about cockpit-frame axes
	-- door hinges sit on the door's outer-rear edge, which is the chest shell's front corner
	{ name = "DoorLeft", parent = "Torso", pos = TORSO_POS + cockpitToTorso(Vector3.new(-POD_HALF, 0, DOOR_INNER)), joint = "DoorLeftHinge", rest = COCKPIT_TILT },
	{ name = "DoorRight", parent = "Torso", pos = TORSO_POS + cockpitToTorso(Vector3.new(POD_HALF, 0, DOOR_INNER)), joint = "DoorRightHinge", rest = COCKPIT_TILT },
	{ name = "Ramp", parent = "Torso", pos = TORSO_POS + cockpitToTorso(RAMP_HINGE), joint = "RampHinge", rest = COCKPIT_TILT },
}
for _, side in { { "Right", 1 }, { "Left", -1 } } do
	local n, s = side[1] :: string, side[2] :: number
	table.insert(BONES, { name = n .. "UpperArm", parent = "Torso", pos = Vector3.new(s * 5.0, 13.0, -0.2), joint = n .. "Shoulder", rest = -TORSO_LEAN + 0.06 })
	table.insert(BONES, { name = n .. "LowerArm", parent = n .. "UpperArm", pos = Vector3.new(s * 5.3, 10.1, -0.2), joint = n .. "Elbow", rest = ELBOW_REST })
	table.insert(BONES, { name = n .. "Hand", parent = n .. "LowerArm", pos = Vector3.new(s * 5.3, 7.5, -0.2), joint = n .. "Wrist" })
	table.insert(BONES, { name = n .. "UpperLeg", parent = "Waist", pos = Vector3.new(s * LEG_X, 9.0, 0), joint = n .. "Hip", rest = HIP_REST })
	table.insert(BONES, { name = n .. "LowerLeg", parent = n .. "UpperLeg", pos = Vector3.new(s * LEG_X, 5.5, 0), joint = n .. "Knee", rest = KNEE_REST })
	table.insert(BONES, { name = n .. "Foot", parent = n .. "LowerLeg", pos = Vector3.new(s * LEG_X, 1.3, 0.2), joint = n .. "Ankle", rest = -(HIP_REST + KNEE_REST) })
end
MechBuilder.Bones = BONES -- design units; multiply by Scale for studs

-- Key points of the powered-down pose in world space, for a mech whose root
-- is at `rootCF`. Used by the server (seating, walk timing) and by clients.
export type OffPoints = {
	seat: CFrame, -- top center of the seat, facing the mech's forward
	stand: Vector3, -- on the floor, just in front of the seat
	hinge: Vector3, -- front edge of the floor, top of the ramp
	lip: Vector3, -- bottom edge of the ramp (on the ground, or above it in the one-knee pose)
	foot: Vector3, -- on the ground where boarding starts: the lip, or just in front of the raised one
	ground: number, -- ground height under the mech
	approach: Vector3, -- a few studs in front of the ramp
	forward: Vector3, -- the mech's facing, flat
}
MechBuilder.HangOut = 1.1 -- studs in front of a raised lip where the pilot stands to climb it
function MechBuilder.offPoints(rootCF: CFrame, style: string?): OffPoints
	-- the cockpit frame is centered on the torso joint (level in the deep kneel)
	local st = MechBuilder.offStyle(style)
	local cockpit = rootCF * CFrame.new((TORSO_POS - ROOT_POS) * SCALE + st.drop) * CFrame.Angles(st.tilt, 0, 0)
	local seat = cockpit * CFrame.new((SEAT_POS + Vector3.new(0, SEAT_SIZE.Y / 2, 0)) * SCALE)
	local hingeCF = cockpit * CFrame.new(RAMP_HINGE * SCALE)
	local lip = (hingeCF * CFrame.Angles(st.rampAngle, 0, 0) * CFrame.new(0, RAMP_LENGTH * SCALE, 0)).Position
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local ground = rootCF.Y - MechBuilder.RootHeight
	local foot = if lip.Y - ground > 1 then Vector3.new(lip.X, ground, lip.Z) + forward * MechBuilder.HangOut else lip
	return {
		seat = seat,
		stand = cockpit * (Vector3.new(0, FLOOR_TOP, SEAT_POS.Z - 0.7) * SCALE),
		hinge = hingeCF.Position,
		lip = lip,
		foot = foot,
		ground = ground,
		approach = foot + forward * 4,
		forward = forward,
	}
end

-- Walking route (world points) from `from` up the ramp to the spot in front
-- of the seat. Starting beside or behind the resting arms, it goes round
-- them first.
local ARMS_FRONT = -6.2 * SCALE -- how far forward the resting arms reach (root space)
local ARMS_OUTER = 11 * SCALE -- and how far out
local CORRIDOR = 2.5 * SCALE -- half width of the lane in front of the ramp
function MechBuilder.boardPath(rootCF: CFrame, from: Vector3, style: string?): { Vector3 }
	local p = MechBuilder.offPoints(rootCF, style)
	local rel = rootCF:PointToObjectSpace(from)
	local path = {}
	if rel.Z > ARMS_FRONT and (math.abs(rel.X) > CORRIDOR or rel.Z > 0) then
		local x = (if rel.X >= 0 then 1 else -1) * ARMS_OUTER
		local approachZ = rootCF:PointToObjectSpace(p.approach).Z
		table.insert(path, rootCF * Vector3.new(x, rel.Y, rel.Z))
		table.insert(path, rootCF * Vector3.new(x, rel.Y, approachZ))
		table.insert(path, p.approach)
	end
	if p.foot ~= p.lip then
		-- raised ramp: the walk ends under its lip (the climb is animated)
		table.insert(path, p.foot)
		return path
	end
	if rel.Z < rootCF:PointToObjectSpace(p.lip).Z + 1 or #path > 0 then
		table.insert(path, p.lip)
	end
	table.insert(path, p.hinge)
	table.insert(path, p.stand)
	return path
end

-- Flat length of a route starting at `from`.
function MechBuilder.pathLength(from: Vector3, path: { Vector3 }): number
	local len, last = 0, from
	for _, p in path do
		len += ((p - last) * Vector3.new(1, 0, 1)).Magnitude
		last = p
	end
	return len
end

local ROT_Y_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
local ROT_Z_AXIS = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z
local FLIP = CFrame.Angles(0, 0, math.pi) -- wedge sloped underneath, thick end at the back
local FLIP_FRONT = CFrame.Angles(math.pi, 0, 0) -- wedge sloped underneath, thick end at the front

local SHAPES = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

-- Tilts an axis-aligned rotation backward (top toward +Z) by `angle`.
local function tiltBack(angle: number, rot: CFrame?): CFrame
	return CFrame.Angles(angle, 0, 0) * (rot or CFrame.identity)
end

-- Center of a rod of `length` starting at `base`, tilted back by `angle`.
local function rodCenter(base: Vector3, angle: number, length: number): Vector3
	return base + Vector3.new(0, math.cos(angle), math.sin(angle)) * (length / 2)
end

-- Adds one armor piece welded to a bone.
local function piece(
	model: Model,
	folder: Folder,
	palette: Palette,
	boneName: string,
	kind: string,
	size: Vector3,
	pos: Vector3,
	color: ColorKey,
	rot: CFrame?
): BasePart
	local bone = model:FindFirstChild(boneName) :: BasePart
	local part: BasePart
	if kind == "Seat" then
		-- the seat survives armor swaps (a pilot may be welded to it): recolor only
		local existing = model:FindFirstChild("PilotSeat")
		if existing and existing:IsA("Seat") then
			existing.Color = palette.dark
			return existing
		end
	end
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
	elseif color == "light" then
		part.Color = palette.light
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
	-- big plates are solid to on-foot players (see ArmorGroup); small details aren't
	local a, b, c = size.X, size.Y, size.Z
	local mid = math.max(math.min(a, b), math.min(math.max(a, b), c))
	local solid = mid >= 0.9 and math.min(a, b, c) >= 0.1 and color ~= "glow" and color ~= "light" and kind ~= "Seat"
	part.CanCollide = solid
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

local function buildHelmet(add: Add)
	local B = "Head"
	add(B, "Cylinder", Vector3.new(0.7, 1.1, 1.1), Vector3.new(0, 0.1, 0.1), "dark", ROT_Y_AXIS) -- neck
	add(B, "Block", Vector3.new(1.9, 1.5, 1.9), Vector3.new(0, 0.85, 0), "main")
	add(B, "Block", Vector3.new(1.6, 0.25, 1.6), Vector3.new(0, 1.72, 0.05), "panel")
	add(B, "Block", Vector3.new(0.3, 0.7, 0.9), Vector3.new(1.08, 0.85, 0.1), "panel")
	add(B, "Block", Vector3.new(0.3, 0.7, 0.9), Vector3.new(-1.08, 0.85, 0.1), "panel")
	add(B, "Block", Vector3.new(1.4, 0.7, 0.35), Vector3.new(0, 0.75, -1.05), "dark") -- visor housing
	add(B, "Block", Vector3.new(1.6, 0.25, 0.5), Vector3.new(0, 1.35, -0.95), "panel") -- brow
	add(B, "Cylinder", Vector3.new(0.2, 0.45, 0.45), Vector3.new(0.3, 0.75, -1.25), "dark", ROT_Z_AXIS) -- camera
	add(B, "Block", Vector3.new(0.35, 0.16, 0.1), Vector3.new(-0.3, 0.8, -1.24), "light") -- eye slit
	add(B, "Block", Vector3.new(0.25, 0.2, 0.1), Vector3.new(0.52, 1.1, -1.24), "light")

	-- antennas, raked back
	local a1Base, a1Angle, a1Len = Vector3.new(-0.55, 1.95, 0.5), 0.5, 2.9
	add(B, "Block", Vector3.new(0.35, 0.35, 0.35), a1Base, "dark")
	add(B, "Cylinder", Vector3.new(a1Len, 0.12, 0.12), rodCenter(a1Base, a1Angle, a1Len), "dark", tiltBack(a1Angle, ROT_Y_AXIS))
	local a2Base, a2Angle, a2Len = Vector3.new(-0.2, 1.9, 0.75), 0.75, 1.9
	add(B, "Cylinder", Vector3.new(a2Len, 0.09, 0.09), rodCenter(a2Base, a2Angle, a2Len), "dark", tiltBack(a2Angle, ROT_Y_AXIS))

	-- twin sensor dish on a stalk, raked back
	local dBase, dAngle, dLen = Vector3.new(0.6, 1.85, 0.4), 0.35, 0.9
	local dTop = dBase + Vector3.new(0, math.cos(dAngle), math.sin(dAngle)) * dLen
	add(B, "Cylinder", Vector3.new(dLen, 0.15, 0.15), rodCenter(dBase, dAngle, dLen), "dark", tiltBack(dAngle, ROT_Y_AXIS))
	add(B, "Block", Vector3.new(0.9, 0.12, 0.12), dTop, "dark", tiltBack(dAngle))
	-- dishes sit just in front of the crossbar so their faces never share a plane with it
	add(B, "Block", Vector3.new(0.45, 0.4, 0.1), dTop + Vector3.new(-0.32, 0.08, -0.08), "panel", tiltBack(dAngle))
	add(B, "Block", Vector3.new(0.45, 0.4, 0.1), dTop + Vector3.new(0.32, 0.08, -0.08), "panel", tiltBack(dAngle))
end

local function buildChest(add: Add)
	local T = "Torso"
	-- torso core beside and behind the cockpit
	add(T, "Block", Vector3.new(4.4, 0.6, 2.0), Vector3.new(0, 4.1, 0.6), "main")
	add(T, "Block", Vector3.new(0.6, 3.8, 3.0), Vector3.new(1.95, 1.9, 0.1), "main")
	add(T, "Block", Vector3.new(0.6, 3.8, 3.0), Vector3.new(-1.95, 1.9, 0.1), "main")
	add(T, "Block", Vector3.new(0.3, 2.2, 2.4), Vector3.new(2.3, 2.3, 0.1), "panel")
	add(T, "Block", Vector3.new(0.3, 2.2, 2.4), Vector3.new(-2.3, 2.3, 0.1), "panel")

	-- cockpit, built in the cockpit frame (level when kneeling)
	local tilt = CFrame.Angles(COCKPIT_TILT, 0, 0)
	local function cp(kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
		return add(T, kind, size, cockpitToTorso(pos), color, tilt * (rot or CFrame.identity))
	end
	-- interior fittings the pilot walks past: never solid
	local function ghost(part: BasePart): BasePart
		part.CanCollide = false
		return part
	end
	local floorDepth = BACK_OUTER - INNER_FRONT
	local shellDepth = BACK_OUTER - DOOR_INNER
	local shellZ = (BACK_OUTER + DOOR_INNER) / 2
	cp("Block", Vector3.new(INNER_HALF * 2, FLOOR_TOP - FLOOR_BOTTOM, floorDepth), Vector3.new(0, (FLOOR_TOP + FLOOR_BOTTOM) / 2, (BACK_OUTER + INNER_FRONT) / 2), "dark").Name = "CockpitFloor"
	cp("Block", Vector3.new(INNER_HALF * 2, ROOF_TOP - ROOF_BOTTOM, shellDepth), Vector3.new(0, (ROOF_TOP + ROOF_BOTTOM) / 2, shellZ), "main")
	cp("Block", Vector3.new(INNER_HALF * 2, ROOF_BOTTOM - FLOOR_TOP, BACK_OUTER - INNER_BACK), Vector3.new(0, (ROOF_BOTTOM + FLOOR_TOP) / 2, (INNER_BACK + BACK_OUTER) / 2), "panel")
	for _, s in { 1, -1 } do
		cp("Block", Vector3.new(POD_HALF - INNER_HALF, ROOF_TOP - FLOOR_BOTTOM, shellDepth), Vector3.new(s * (POD_HALF + INNER_HALF) / 2, (ROOF_TOP + FLOOR_BOTTOM) / 2, shellZ), "main")
		cp("Block", Vector3.new(0.15, 3.8, 3.0), Vector3.new(s * (POD_HALF + 0.075), 0.1, shellZ + 0.1), "panel") -- side skin
		cp("Block", Vector3.new(0.12, 0.3, 2.6), Vector3.new(s * (POD_HALF + 0.21), -1.4, shellZ + 0.1), "accent")
		cp("Block", Vector3.new(0.05, 0.12, 2.0), Vector3.new(s * (INNER_HALF - 0.025), 0.7, shellZ + 0.1), "glow") -- interior light strip
	end
	cp("Block", Vector3.new(2.9, 0.2, floorDepth), Vector3.new(0, FLOOR_BOTTOM - 0.1, (BACK_OUTER + INNER_FRONT) / 2), "panel") -- belly
	cp("Block", Vector3.new(2.4, 0.25, 2.6), Vector3.new(0, FLOOR_BOTTOM - 0.325, (BACK_OUTER + INNER_FRONT) / 2), "dark") -- keel
	cp("Block", Vector3.new(3.0, 0.2, 3.2), Vector3.new(0, ROOF_TOP + 0.1, shellZ + 0.1), "main") -- roof armor
	cp("Block", Vector3.new(1.0, 0.04, 0.3), Vector3.new(0, ROOF_BOTTOM - 0.02, INNER_FRONT + 0.6), "glow") -- dome light

	-- seat
	cp("Seat", SEAT_SIZE, SEAT_POS, "dark") -- "PilotSeat", kept outside the armor folder
	local seatBottom = SEAT_POS.Y - SEAT_SIZE.Y / 2
	ghost(cp("Block", Vector3.new(1.0, seatBottom - FLOOR_TOP, 1.0), Vector3.new(0, (seatBottom + FLOOR_TOP) / 2, SEAT_POS.Z + 0.1), "dark")) -- pedestal
	ghost(cp("Block", Vector3.new(1.6, 2.0, 0.2), Vector3.new(0, SEAT_POS.Y + 1.1, SEAT_POS.Z + 0.75), "dark")) -- seat back
	ghost(cp("Block", Vector3.new(1.0, 0.5, 0.2), Vector3.new(0, SEAT_POS.Y + 2.4, SEAT_POS.Z + 0.8), "accent")) -- headrest

	-- ramp plate, standing up behind the doors; its inner face is the deck
	local function ramp(kind: string, size: Vector3, pos: Vector3, color: ColorKey): BasePart
		return add("Ramp", kind, size, pos - RAMP_HINGE, color)
	end
	ramp("Block", Vector3.new(2.76, RAMP_LENGTH, RAMP_THICK), Vector3.new(0, FLOOR_TOP + RAMP_LENGTH / 2, INNER_FRONT - RAMP_THICK / 2), "panel").Name = "CockpitRamp"
	for i = 0, 3 do
		ramp("Block", Vector3.new(2.4, 0.2, 0.04), Vector3.new(0, FLOOR_TOP + 0.5 + i * 0.8, INNER_FRONT + 0.02), "accent")
	end

	-- chest doors, split down the middle, hinged at the outer edges. The hinge
	-- axis is the door's outer-rear edge, shared with the shell's front corner,
	-- so the door stays against the body at every angle; hinge knuckles on the
	-- axis alternate between the body (top/bottom) and the door (between).
	for _, s in { 1, -1 } do
		local bone = if s > 0 then "DoorRight" else "DoorLeft"
		local hinge = Vector3.new(s * POD_HALF, 0, DOOR_INNER)
		local function door(kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
			return add(bone, kind, size, pos - hinge, color, rot)
		end
		local KNUCKLE_D = 0.32
		for _, k in { { -2.05, -1.0, false }, { -1.0, 0.2, true }, { 0.2, 1.2, false }, { 1.2, 2.3, true } } do
			local y0, y1, onDoor = k[1] :: number, k[2] :: number, k[3] :: boolean
			local size = Vector3.new(y1 - y0, KNUCKLE_D, KNUCKLE_D)
			local pos = Vector3.new(s * POD_HALF, (y0 + y1) / 2, DOOR_INNER)
			if onDoor then
				door("Cylinder", size, pos, "dark", ROT_Y_AXIS)
			else
				cp("Cylinder", size, pos, "dark", ROT_Y_AXIS)
			end
		end
		door("Block", Vector3.new(POD_HALF, ROOF_TOP - FLOOR_BOTTOM, DOOR_INNER - DOOR_OUTER), Vector3.new(s * POD_HALF / 2, (ROOF_TOP + FLOOR_BOTTOM) / 2, (DOOR_INNER + DOOR_OUTER) / 2), "main")
		door("Block", Vector3.new(1.3, 3.0, 0.15), Vector3.new(s * 0.8, 0.5, DOOR_OUTER - 0.075), "panel")
		door("Block", Vector3.new(1.3, 0.3, 0.1), Vector3.new(s * 0.8, -1.4, DOOR_OUTER - 0.05), "accent")
		if s > 0 then
			door("Block", Vector3.new(0.28, 0.28, 0.1), Vector3.new(0.9, 1.5, DOOR_OUTER - 0.2), "light")
			door("Block", Vector3.new(0.28, 0.28, 0.1), Vector3.new(1.0, 0.8, DOOR_OUTER - 0.2), "light")
		else
			door("Block", Vector3.new(0.9, 0.12, 0.1), Vector3.new(-0.8, 1.5, DOOR_OUTER - 0.2), "dark") -- vent slits
			door("Block", Vector3.new(0.9, 0.12, 0.1), Vector3.new(-0.8, 1.25, DOOR_OUTER - 0.2), "dark")
		end
	end

	-- backpack
	add(T, "Block", Vector3.new(3.8, 3.8, 2.0), Vector3.new(0, 2.6, 2.6), "main")
	add(T, "Block", Vector3.new(3.4, 0.3, 1.7), Vector3.new(0, 4.6, 2.6), "panel")
	add(T, "Block", Vector3.new(0.25, 2.4, 1.6), Vector3.new(2.0, 2.6, 2.6), "panel")
	add(T, "Block", Vector3.new(0.25, 2.4, 1.6), Vector3.new(-2.0, 2.6, 2.6), "panel")
	add(T, "Block", Vector3.new(1.3, 1.6, 0.1), Vector3.new(0.7, 2.8, 3.65), "panel")
	add(T, "Cylinder", Vector3.new(0.7, 0.8, 0.8), Vector3.new(0.8, 0.95, 3.7), "dark", ROT_Z_AXIS)
	add(T, "Cylinder", Vector3.new(0.7, 0.8, 0.8), Vector3.new(-0.8, 0.95, 3.7), "dark", ROT_Z_AXIS)
	-- rear skirt hanging under the backpack; overlaps the waist's spine block
	-- (see buildLegs) like a bellows so no gap opens as the torso leans or bows
	add(T, "Block", Vector3.new(3.4, 1.4, 2.8), Vector3.new(0, -0.3, 1.9), "dark")
	for _, s in { 1, -1 } do
		-- flank under the rib, closing the slot above the thigh beside the spine
		add(T, "Block", Vector3.new(0.4, 0.5, 1.9), Vector3.new(s * 1.95, -0.2, 0.75), "dark")
	end

	-- rifle stowed upside down on the backpack: stock up, barrel down
	local rx, rz = -1.2, 4.05
	add(T, "Block", Vector3.new(0.7, 0.3, 0.5), Vector3.new(rx, 3.6, rz - 0.35), "panel") -- clamps
	add(T, "Block", Vector3.new(0.7, 0.3, 0.5), Vector3.new(rx, 1.2, rz - 0.35), "panel")
	add(T, "Block", Vector3.new(0.45, 3.0, 0.9), Vector3.new(rx, 2.6, rz), "dark") -- receiver
	add(T, "Block", Vector3.new(0.4, 1.4, 0.6), Vector3.new(rx, 0.4, rz), "dark") -- handguard
	add(T, "Cylinder", Vector3.new(2.6, 0.24, 0.24), Vector3.new(rx, -1.0, rz), "dark", ROT_Y_AXIS) -- barrel
	add(T, "Block", Vector3.new(0.34, 0.45, 0.34), Vector3.new(rx, -2.4, rz), "dark") -- muzzle
	add(T, "Block", Vector3.new(0.35, 1.4, 0.5), Vector3.new(rx, 4.7, rz + 0.15), "dark") -- stock
	add(T, "Block", Vector3.new(0.45, 0.35, 1.1), Vector3.new(rx, 5.35, rz + 0.3), "dark") -- butt
	add(T, "Block", Vector3.new(0.3, 0.8, 0.35), Vector3.new(rx, 3.7, rz + 0.62), "dark") -- grip
	add(T, "Block", Vector3.new(0.35, 1.0, 0.45), Vector3.new(rx, 2.3, rz + 0.67), "dark") -- magazine

	for _, side in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = side[1] :: string, side[2] :: number
		local UA, LA, H = n .. "UpperArm", n .. "LowerArm", n .. "Hand"

		-- shoulder yoke on the torso bridging to the pod. Stops just short of the pod's
		-- inner face (torso x 4.0); the shoulder swings about X so that face never moves.
		add(T, "Block", Vector3.new(1.85, 1.9, 2.4), Vector3.new(s * 3.025, 3.25, -0.3), "main")
		add(T, "Block", Vector3.new(1.6, 0.2, 2.0), Vector3.new(s * 3.05, 4.25, -0.3), "panel")
		-- dark recess under the yoke, filling the see-through gap beside the ribs
		add(T, "Block", Vector3.new(1.45, 1.65, 1.6), Vector3.new(s * 3.025, 1.525, -0.1), "dark")
		-- side vent framing the recess: olive frame, hooded bottom lip, dark slats.
		-- Its lip clears the thighs' swing and the folded legs when kneeling (torso y 0.85).
		add(T, "Block", Vector3.new(1.85, 0.4, 0.7), Vector3.new(s * 2.925, 2.55, -1.25), "main")
		add(T, "Wedge", Vector3.new(1.8, 0.3, 0.7), Vector3.new(s * 2.95, 1.1, -1.25), "main", FLIP_FRONT)
		add(T, "Block", Vector3.new(0.25, 1.15, 0.6), Vector3.new(s * 3.675, 1.825, -1.25), "main")
		add(T, "Block", Vector3.new(0.25, 1.15, 0.6), Vector3.new(s * 2.175, 1.825, -1.25), "main")
		for i = 0, 2 do
			add(T, "Block", Vector3.new(1.35, 0.12, 0.3), Vector3.new(s * 2.95, 1.5 + i * 0.275, -1.3), "dark")
		end

		-- shoulder pod, pushed forward so it peeks out past the chest
		add(UA, "Ball", Vector3.new(1.3, 1.3, 1.3), Vector3.new(s * -1.4, 0, 0), "dark")
		add(UA, "Block", Vector3.new(2.6, 2.9, 3.3), Vector3.new(s * 0.3, 0.3, -0.3), "main")
		add(UA, "Block", Vector3.new(2.2, 0.3, 2.9), Vector3.new(s * 0.3, 1.9, -0.3), "panel")
		add(UA, "Block", Vector3.new(0.2, 1.8, 2.4), Vector3.new(s * 1.7, 0.4, -0.3), "panel")
		add(UA, "Block", Vector3.new(0.1, 0.4, 2.0), Vector3.new(s * 1.84, -0.6, -0.3), "accent")
		add(UA, "Block", Vector3.new(1.8, 0.4, 0.1), Vector3.new(s * 0.3, -0.5, 1.37), "accent")
		add(UA, "Block", Vector3.new(0.28, 0.28, 0.1), Vector3.new(s * 0.8, 1.0, -1.97), "light")
		add(UA, "Block", Vector3.new(1.2, 2.3, 1.3), Vector3.new(s * 0.3, -2.1, 0), "panel")

		-- forearm
		add(LA, "Cylinder", Vector3.new(1.5, 1.1, 1.1), Vector3.new(0, 0, 0), "dark")
		add(LA, "Block", Vector3.new(1.8, 2.6, 2.0), Vector3.new(0, -1.4, 0), "main")
		add(LA, "Block", Vector3.new(1.1, 1.0, 0.2), Vector3.new(0, -1.0, -1.05), "panel")
		add(LA, "Block", Vector3.new(1.6, 0.35, 0.1), Vector3.new(0, -2.2, -1.05), "accent")
		add(LA, "Block", Vector3.new(0.28, 0.28, 0.1), Vector3.new(s * 0.5, -0.4, -1.05), "light")
		add(LA, "Block", Vector3.new(1.5, 0.3, 1.7), Vector3.new(0, -2.8, 0), "dark")

		-- fist
		add(H, "Block", Vector3.new(1.0, 0.95, 1.1), Vector3.new(0, -0.575, 0), "dark") -- top tucked under the cuff
		add(H, "Block", Vector3.new(0.9, 0.4, 0.5), Vector3.new(0, -1.05, -0.2), "dark")
		add(H, "Block", Vector3.new(0.3, 0.5, 0.4), Vector3.new(-s * 0.55, -0.5, -0.3), "dark")
	end

	-- rotary gatling on the right forearm, barrels running down past the fist
	local LA = "RightLowerArm"
	local gx = 1.55
	add(LA, "Block", Vector3.new(1.2, 2.3, 1.6), Vector3.new(gx, -1.3, -0.1), "dark")
	add(LA, "Block", Vector3.new(0.6, 1.2, 0.6), Vector3.new(gx - 0.8, -1.1, -0.1), "dark") -- mount
	add(LA, "Cylinder", Vector3.new(1.1, 1.3, 1.3), Vector3.new(gx, -0.9, 1.05), "dark", ROT_Z_AXIS) -- ammo drum
	add(LA, "Cylinder", Vector3.new(0.9, 1.1, 1.1), Vector3.new(gx, -2.8, -0.1), "dark", ROT_Y_AXIS)
	add(LA, "Cylinder", Vector3.new(0.25, 1.25, 1.25), Vector3.new(gx, -3.5, -0.1), "dark", ROT_Y_AXIS)
	add(LA, "Cylinder", Vector3.new(0.25, 1.25, 1.25), Vector3.new(gx, -6.0, -0.1), "dark", ROT_Y_AXIS)
	for i = 0, 5 do
		local a = i * math.pi / 3
		add(LA, "Cylinder", Vector3.new(3.4, 0.26, 0.26), Vector3.new(gx + math.cos(a) * 0.36, -4.8, -0.1 + math.sin(a) * 0.36), "dark", ROT_Y_AXIS)
	end
end

local function buildLegs(add: Add)
	local W = "Waist"
	-- pelvis, kept behind the cockpit's back wall
	add(W, "Block", Vector3.new(3.2, 0.8, 1.8), Vector3.new(0, 0.4, 0.3), "dark")
	add(W, "Block", Vector3.new(2.2, 1.6, 1.45), Vector3.new(0, -0.4, 0.175), "main")
	add(W, "Block", Vector3.new(2.0, 1.0, 0.3), Vector3.new(0, -0.2, 1.1), "panel")
	add(W, "Cylinder", Vector3.new(0.9, 1.3, 1.3), Vector3.new(2.1, -0.6, 0), "dark") -- hip joints
	add(W, "Cylinder", Vector3.new(0.9, 1.3, 1.3), Vector3.new(-2.1, -0.6, 0), "dark")
	-- spine block rising behind the cockpit into the torso's rear skirt, closing
	-- the see-through gap under the backpack; inside the thighs (x < 1.95)
	add(W, "Block", Vector3.new(3.7, 1.8, 2.7), Vector3.new(0, 1.0, 1.65), "dark")
	add(W, "Block", Vector3.new(3.0, 1.2, 1.85), Vector3.new(0, -0.4, 1.975), "dark") -- seat plate under it, inside the shins
	for _, s in { 1, -1 } do
		-- hip guard behind the thigh top, blocking the slot over the thigh; the
		-- thigh never reaches above y -0.5 this far back (z > 1.25)
		add(W, "Block", Vector3.new(1.2, 1.8, 1.0), Vector3.new(s * 2.5, 0.6, 1.8), "dark")
	end
	-- crotch plate: narrow enough for the thighs (x >= 1.95) to swing past, and
	-- its front stays behind the cockpit belly when the torso bows to kneel
	-- (bottom ~0.25 off the ground when kneeling)
	add(W, "Block", Vector3.new(1.6, 1.6, 1.2), Vector3.new(0, -1.9, 0.15), "main")
	add(W, "Wedge", Vector3.new(1.4, 0.5, 1.0), Vector3.new(0, -2.9, 0.1), "main", FLIP) -- bevel under the front
	add(W, "Block", Vector3.new(1.1, 1.0, 0.1), Vector3.new(0, -1.8, -0.5), "panel")
	for _, s in { 1, -1 } do
		-- flares: wide at the top, tapering down (trapezoid from the front)
		add(W, "Wedge", Vector3.new(1.1, 1.25, 0.45), Vector3.new(s * 1.0, -1.675, 0.15), "main", CFrame.Angles(0, -s * math.pi / 2, 0) * FLIP)
		add(W, "Block", Vector3.new(0.5, 1.3, 0.9), Vector3.new(s * 1.3, -1.25, 0.15), "dark") -- hip joint block
	end

	for _, side in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = side[1] :: string, side[2] :: number
		local UL, LL, F = n .. "UpperLeg", n .. "LowerLeg", n .. "Foot"

		-- thigh
		add(UL, "Block", Vector3.new(2.2, 3.6, 2.4), Vector3.new(s * 0.15, -1.5, -0.05), "main")
		add(UL, "Block", Vector3.new(1.8, 2.6, 0.3), Vector3.new(s * 0.15, -1.4, -1.35), "panel")
		add(UL, "Block", Vector3.new(0.2, 2.4, 1.8), Vector3.new(s * 1.3, -1.4, 0), "panel")
		add(UL, "Block", Vector3.new(0.28, 0.28, 0.1), Vector3.new(s * 0.6, -0.5, -1.52), "light")

		-- knee + shin
		add(LL, "Cylinder", Vector3.new(1.7, 1.2, 1.2), Vector3.new(0, 0, 0.1), "dark")
		add(LL, "Block", Vector3.new(1.8, 1.5, 0.8), Vector3.new(0, -0.1, -1.0), "main")
		add(LL, "Block", Vector3.new(1.3, 0.9, 0.1), Vector3.new(0, -0.1, -1.41), "panel")
		add(LL, "Block", Vector3.new(2.0, 3.4, 2.0), Vector3.new(0, -2.4, 0), "main")
		add(LL, "Block", Vector3.new(1.6, 2.2, 0.3), Vector3.new(0, -2.6, -1.05), "panel")
		add(LL, "Block", Vector3.new(1.6, 0.4, 0.1), Vector3.new(0, -3.4, -1.25), "accent")
		add(LL, "Block", Vector3.new(0.28, 0.28, 0.1), Vector3.new(s * 0.5, -1.9, -1.25), "light")
		-- big calf bulge tapering toward the ankle
		add(LL, "Block", Vector3.new(1.8, 2.3, 1.4), Vector3.new(0, -1.55, 1.6), "main")
		add(LL, "Block", Vector3.new(1.4, 1.6, 0.2), Vector3.new(0, -1.55, 2.35), "panel")
		add(LL, "Wedge", Vector3.new(1.8, 1.2, 1.4), Vector3.new(0, -3.3, 1.6), "main", FLIP_FRONT)
		add(LL, "Cylinder", Vector3.new(1.4, 0.45, 0.45), Vector3.new(0, -3.5, 0.95), "dark", ROT_Y_AXIS)
		-- side plates on both flanks of the shin: panel edge, rounded olive plate on top
		for _, f in { 1, -1 } do
			add(LL, "Block", Vector3.new(0.2, 2.9, 1.7), Vector3.new(f * 1.09, -2.45, -0.05), "panel")
			add(LL, "Block", Vector3.new(0.12, 1.4, 1.3), Vector3.new(f * 1.24, -2.45, -0.05), "main")
			-- rounded ends stand 0.05 proud of the flat middle so their caps never share its plane
			add(LL, "Cylinder", Vector3.new(0.22, 1.3, 1.3), Vector3.new(f * 1.24, -1.75, -0.05), "main")
			add(LL, "Cylinder", Vector3.new(0.22, 1.3, 1.3), Vector3.new(f * 1.24, -3.15, -0.05), "main")
		end

		-- arched foot: toe and heel pads with a raised middle
		add(F, "Ball", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 0, 0), "dark")
		add(F, "Block", Vector3.new(1.3, 0.7, 1.2), Vector3.new(0, -0.55, 0), "dark") -- ankle block
		add(F, "Block", Vector3.new(2.05, 0.5, 2.0), Vector3.new(0, -0.6, -0.5), "main") -- arch
		add(F, "Block", Vector3.new(2.2, 0.8, 1.5), Vector3.new(0, -0.9, -1.9), "main") -- toe
		add(F, "Wedge", Vector3.new(2.1, 0.7, 0.9), Vector3.new(0, -0.88, -3.05), "main") -- narrower/raised vs toe block
		add(F, "Block", Vector3.new(2.3, 0.5, 2.3), Vector3.new(0, -1.25, -2.2), "dark") -- toe sole
		add(F, "Block", Vector3.new(0.45, 0.3, 0.6), Vector3.new(0.625, -1.25, -3.45), "dark") -- toe claws
		add(F, "Block", Vector3.new(0.45, 0.3, 0.6), Vector3.new(-0.625, -1.25, -3.45), "dark")
		add(F, "Block", Vector3.new(1.7, 0.8, 1.2), Vector3.new(0, -0.9, 1.1), "main") -- heel
		add(F, "Block", Vector3.new(2.2, 0.5, 1.5), Vector3.new(0, -1.25, 1.15), "dark") -- heel sole
		add(F, "Block", Vector3.new(0.6, 0.35, 0.7), Vector3.new(0, -1.1, 2.1), "dark") -- heel spur
	end
end

local SLOT_BUILDERS = {
	Helmet = buildHelmet,
	Chest = buildChest,
	Legs = buildLegs,
}

-- Builds the bare rig: root, bones, motors, humanoid. No armor.
function MechBuilder.buildRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE * SCALE
	root.CFrame = CFrame.new(ROOT_POS * SCALE)
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = MechBuilder.RootGroup
	root.RootPriority = 100 -- stays the assembly root with a pilot welded in
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	local bones: { [string]: BasePart } = { HumanoidRootPart = root }
	local origins: { [string]: Vector3 } = { HumanoidRootPart = ROOT_POS }
	for _, def in BONES do
		local parent = bones[def.parent]
		-- joint offset is measured in the parent's frame, so parent rest angles carry down the chain
		local c0 = CFrame.new((def.pos - origins[def.parent]) * SCALE) * CFrame.Angles(def.rest or 0, 0, 0)

		local bone = Instance.new("Part")
		bone.Name = def.name
		bone.Size = Vector3.new(0.4, 0.4, 0.4)
		bone.CFrame = parent.CFrame * c0
		bone.Transparency = 1
		bone.CanCollide = false
		bone.CanTouch = false
		bone.CanQuery = false
		bone.Massless = true
		bone.Parent = model
		bones[def.name] = bone
		origins[def.name] = def.pos

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
	humanoid.HipHeight = MechBuilder.HipHeight
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
function MechBuilder.applySlot(model: Model, slot: string, variantId: string)
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
function MechBuilder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = MechBuilder.buildRig(name)
	for _, slot in MechConfig.Slots do
		MechBuilder.applySlot(model, slot, loadout[slot])
	end
	return model
end

return MechBuilder
