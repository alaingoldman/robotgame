--!strict
-- Builds the GR-07 "Bulwark" (type id "Gunner") out of primitive parts: a
-- heavy, monochrome gunmetal humanoid gunner. Broad boxy chest with a raised
-- central block and two framed sensor slots, a small boxy head sunk into the
-- chest top (vertical sensor slot, antenna beside it), a periscope turret on
-- the right of the chest top, big boxy shoulder blocks, long arms with
-- forearm armor and light-grey cuff bands, clawed fists, a long cannon over
-- the left shoulder (front to back), a tall narrow shield on the left
-- forearm, two thrusters on the back, a narrow waist with a central
-- crotch plate and thick legs: boxy thighs, a round knee cap, a hexagonal
-- shin plate forward of the knee, the lower shin raked back to a light-grey
-- ankle band, then a short ankle link forward-down to long clawed feet with
-- spikes at the toe and heel. The pilot rides standing in a pod in the
-- torso, entered from the back through a six-petal "flower" hatch.
--
-- Same conventions as KnightBuilder: design units x MechConfig.Scale, model
-- space with the origin on the ground between the feet, facing -Z;
-- invisible bone parts joined by Motor6Ds (identity Transform = standing);
-- armor welded to the bones in Armor_Helmet / Armor_Chest / Armor_Legs:
--   Helmet -> head, periscope
--   Chest  -> torso, pod + petals, cannon, arms, hands, shield, thrusters
--   Legs   -> pelvis, crotch plate, legs, feet
-- The pilot seat is built with the chest but lives directly under the model.
--
-- Rig (HWM-04B bone / motor names plus extras), rest frames in model space:
--   Waist <- Root (HumanoidRootPart)        Torso <- Waist (Waist)
--   Head <- Neck (Torso)                    Petal1..6 <- Petal1..6Hinge (Torso)
--   Periscope <- PeriscopeTurret (Torso)    CannonMount <- CannonPitch (Torso)
--   [L|R]UpperArm <- [L|R]Shoulder (Torso)  [L|R]LowerArm <- [L|R]Elbow
--   [L|R]Hand <- [L|R]Wrist                 Shield <- ShieldMount (LeftLowerArm)
--   [L|R]UpperLeg <- [L|R]Hip (Waist)       [L|R]LowerLeg <- [L|R]Knee
--   [L|R]Foot <- [L|R]Ankle
--
-- Colors: the look is monochrome; "main" = primary plates, "panel" =
-- secondary plates, "dark" = frame / joints, "trim" = the light-grey details
-- (a neutral grey, darker on light palettes), "light" / "glow" = sensors.
--
-- Proportions, measured on the reference sheet (grid squares; 1 square = 0.7
-- design units; ground = sheet y 650; front view centered x 256.5, side view
-- body center x 637, facing +x):
--   measurement                           sheet (sq)   design (du)  built (du)
--   total height (periscope ring)            24.9        17.4        17.67
--   head top / antenna top                22.1 / 23.2  15.5 / 16.3  15.82 / 16.83
--   shoulder block top                       21.3        14.9        15.05
--   shoulder span (outer blocks)             13.9         9.7         9.8
--   chest width (sensor slots)               7.74         5.42        5.42
--   waist width                              3.9          2.73        2.84
--   hip width (thigh outer edges)            9.5          6.65        6.64
--   thigh width top / at knee             3.06 / 2.4   2.14 / 1.68  2.12 / 1.8
--   gap between thighs (top)                 3.24         2.27        2.28
--   stance (thigh centers / feet)          6.23 / 9.2   4.36 / 6.44  4.4 / 6.2
--   hip joint height                         13.6         9.52        9.5
--   knee height (knee cap center)            8.25         5.78        5.79
--   shin width                               2.95         2.07        2.0
--   ankle band (w x h, bottom)          2.75x1.5, 2.2   1.92x1.05, 1.52  1.92x1.0, 1.4
--   foot width (claws) / block               3.94 / 2.62  2.76 / 1.83  2.5 / 1.85
--   foot length blocks / with spikes      4.7 / 8.75    3.3 / 6.1    3.4 / 6.2
--   side view, from vertical (lower end forward = +):
--     thigh  hip -> knee cap      5.35 sq long,  +3 deg   (built 3.72 du, +3.4)
--     shin   knee -> ankle band   5.7 sq long,   -4 deg   (built 3.95 du, -4.6)
--     shin plate (hex + lower)    5.1 sq tall,  -24 deg   (built: hex plate
--       forward of the knee, lower shin plates raked -14 deg)
--     ankle link ankle -> ball    2.0 sq long,  +62 deg   (built 1.43 du, +61)
--   cannon length / over the shoulder      18.5 sq      12.9        13.0
--   shield (left forearm) w x h              1.3 x 13.7   0.9 x 9.6  0.5..0.9 x 10.2
-- The legs are built straight (the sheet's shins / feet splay out ~6 deg):
-- the shin, ankle band and foot armor sit progressively further out on
-- vertical bones instead. The chest is ~0.25 du taller than drawn (chest top
-- 14.96 vs 14.73) and the pod floor sits at the waist so a standing avatar
-- fits; the back is the closed flower bud instead of the sheet's back plate.

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)

local GunnerBuilder = {}

GunnerBuilder.TypeId = "Gunner"
GunnerBuilder.DisplayName = "GR-07"
GunnerBuilder.Nickname = "BULWARK"

type Palette = MechConfig.Palette
-- "glow": accent Neon, always lit; "light": palette light Neon, dimmed while
-- off; "screen": amber Neon screen, dimmed while off; "trim": light-grey details
type ColorKey = "main" | "panel" | "dark" | "accent" | "light" | "glow" | "screen" | "trim"

local SCALE = MechConfig.Scale
GunnerBuilder.Scale = SCALE
local SCREEN_COLOR = Color3.fromRGB(255, 176, 60)

-- light-grey detail color: neutral grey, darker on light palettes
local function trimColor(p: Palette): Color3
	local m = p.main
	local lum = 0.3 * m.R + 0.59 * m.G + 0.11 * m.B
	return if lum > 0.75 then Color3.fromRGB(138, 145, 154) else Color3.fromRGB(198, 202, 207)
end

-- Root collision box; its bottom is the Humanoid's HipHeight.
local ROOT_POS = Vector3.new(0, 10.4, 0.2)
local ROOT_SIZE = Vector3.new(4.6, 3.2, 3.6)
GunnerBuilder.RootHeight = ROOT_POS.Y * SCALE
GunnerBuilder.HipHeight = (ROOT_POS.Y - ROOT_SIZE.Y / 2) * SCALE

local PELVIS_POS = Vector3.new(0, 9.5, 0)
local TORSO_POS = Vector3.new(0, 10.0, 0) -- waist pivot; the torso / cockpit frame origin
local NECK_POS = Vector3.new(0, 15.01, 0.35)
local PERISCOPE_POS = Vector3.new(1.85, 15.01, 0.45)
local CANNON_PIVOT = Vector3.new(-2.35, 15.75, 0.9)
local SHOULDER = Vector3.new(3.4, 13.75, 0.3) -- right side (x mirrored)
local UPPER_ARM, FOREARM = 2.15, 3.4
local ARM_ROLL = 0.2 -- arms hang out (A-stance)
local ELBOW_REST = 0.3 -- forearms forward a little
local SHIELD_OFFSET = Vector3.new(-2.0, -2.5, 0) -- left forearm frame

-- Legs (re-measured on the sheet, see the table above): in the front / back
-- views each leg is a straight line splayed out LEG_SPLAY from the hip (thigh
-- ~7-9 deg, shin ~7-10 deg); in the side view the thigh is plumb (knee cap
-- right under the hip), the shin runs back a touch to the ankle band, and the
-- ankle link goes forward-down to the foot's ball joint. The thigh and shin
-- bones are rolled out by LEG_SPLAY (the foot bone stays level), so walking
-- and the IK swing the legs in their splayed planes.
local LEG_X = 1.92 -- hip joint, out from the center
local HIP_Y = 9.5
local LEG_SPLAY = 0.145 -- roll, lower end out (8.3 deg)
local HIP_REST = 0 -- thigh pitch (lower end forward)
local SHIN_REST = -0.082 -- shin pitch (lower end back)
-- lengths along the rolled bones: knee cap center 5.66 du up, ankle (band
-- center) 1.69 up and 0.33 behind the knee, as on the sheet
local THIGH_LEN = (HIP_Y - 5.66) / math.cos(LEG_SPLAY)
local SHIN_LEN = (5.66 - 1.69) / math.cos(LEG_SPLAY) / math.cos(SHIN_REST)
local function rotX(v: Vector3, a: number): Vector3
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end
-- splay roll of side s (+1 right, -1 left): lower end out
local function splay(s: number): CFrame
	return CFrame.Angles(0, 0, s * LEG_SPLAY)
end
local THIGH_D = Vector3.new(0, -THIGH_LEN, 0)
local SHIN_D = Vector3.new(0, -SHIN_LEN, 0)
local HIP_POS = Vector3.new(0, HIP_Y, 0)
-- unrolled (plumb) offsets; the rolled ones are splay(s) * these
local KNEE_D = rotX(THIGH_D, HIP_REST)
local ANKLE_D = KNEE_D + rotX(SHIN_D, SHIN_REST)
local function legPoint(s: number, d: Vector3): Vector3
	return HIP_POS + Vector3.new(s * LEG_X, 0, 0) + splay(s) * d
end
local ANKLE_H = legPoint(1, ANKLE_D).Y -- 1.69: the sole is at -ANKLE_H in the foot frame
GunnerBuilder.LegLength = (THIGH_LEN + SHIN_LEN) * SCALE

GunnerBuilder.Legs = {
	thigh = THIGH_LEN * SCALE,
	shin = SHIN_LEN * SCALE,
	hipRest = HIP_REST,
	shinRest = SHIN_REST,
	splay = LEG_SPLAY,
	ankle = (legPoint(1, ANKLE_D) - legPoint(1, Vector3.zero)) * SCALE, -- right hip -> ankle standing (studs)
	hipX = LEG_X * SCALE,
}

-- Cockpit: an upright pod in the torso, entered from the BACK. The pilot
-- stands in it facing forward, chest against a padded couch on the front
-- wall; in the powered-down pose the mech lies face down, so the pilot lies
-- prone on the couch (chest down, head toward the mech's head) and the pod
-- opens upward. Torso frame (design units): clear interior 2.9 wide (2.2 in
-- the footwell, up to 1.1 above the floor) x 4.36 tall x 3.2+ deep (front
-- wall to the rim; the closed petals bulge 1.0 further) = 4.93 (3.74) x 7.41
-- x 5.44+ studs; an avatar with long hair measures 4.2 x 6.75 x 4.54 at most.
local INNER_HALF = 1.45
local POD_HALF = 1.65
local FOOT_HALF = 1.1 -- footwell interior
local WAIST_HALF = 1.42 -- footwell outer (the waist)
local FLOOR_BOTTOM = 0
local FLOOR_TOP = 0.25
local STEP_Y = FLOOR_TOP + 0.8 -- console ledges (below the pilot's hands)
local ROOF_BOTTOM = FLOOR_TOP + 4.56
local ROOF_TOP = ROOF_BOTTOM + 0.2
local BACK_OUTER = 1.6 -- the rim of the rear opening
local INNER_FRONT = -1.85 -- front wall inner face
local FRONT_T = 0.3
local FRONT_OUTER = INNER_FRONT - FRONT_T
local FLANK_X = 2.71 -- chest half width at the sensor slots
local FLANK_TOP = ROOF_TOP - 0.05
local COUCH_FACE = INNER_FRONT + 0.45 -- the padded couch's face
-- The PilotSeat is an invisible Seat used only for its weld: the server
-- re-sets the SeatWeld (GunnerBuilder.fitPilot) so the avatar stands upright,
-- facing forward, feet FEET_CLEAR above the floor whatever its leg length;
-- clients stop its sit animation (GunnerAnimator), so it stays straight in
-- the pod, chest to the couch (prone when the mech lies down).
local SEAT_SIZE = Vector3.new(1.0, 0.2, 1.0)
local FEET_CLEAR = 0.3 -- studs
local PILOT_Z = -1.04 -- avatar root center z (torso frame)
local SEAT_POS = Vector3.new(0, FLOOR_TOP + 0.6, PILOT_Z)
-- avatar root center (torso frame, design units) for a standard avatar
-- (HipHeight 2, root 2 studs tall)
local PILOT_ROOT = Vector3.new(0, FLOOR_TOP + (FEET_CLEAR + 3) / SCALE, PILOT_Z)

-- Flower hatch: six armored petals close the rear opening as a low hip-roof
-- "bud" (rim x +-RIM_X, y RIM_BOTTOM..RIM_TOP at z RIM_Z, ridge BULGE behind
-- it); each petal is hinged on its base edge on the rim and swings outward
-- and back to open. Petal1 top, 2 upper right, 3 lower right, 4 bottom,
-- 5 lower left, 6 upper left (as seen from behind: right = +X).
local RIM_X = POD_HALF
local RIM_Z = BACK_OUTER
local RIM_TOP = ROOF_TOP
local RIM_BOTTOM = 0.2
local RIM_MID = (RIM_TOP + RIM_BOTTOM) / 2
local BULGE = 1.0
local PETAL_T = 0.22
local SLANT = math.sqrt(RIM_X * RIM_X + BULGE * BULGE) -- petal depth, base to ridge
type PetalDef = { name: string, kind: string, hinge: Vector3, x: Vector3, y: Vector3, half: number, seg: number, open: number }
local PETALS: { PetalDef } = {}
do
	local inY = Vector3.new(0, -RIM_X, BULGE).Unit -- top petal, base toward the ridge
	local outX = Vector3.new(-RIM_X, 0, BULGE).Unit -- right petals
	local function add(name: string, kind: string, hinge: Vector3, x: Vector3, y: Vector3, half: number, seg: number, open: number)
		table.insert(PETALS, { name = name, kind = kind, hinge = hinge, x = x, y = y, half = half, seg = seg, open = open })
	end
	-- side petals: base from the split to the rim corner, ridge part `seg` long;
	-- the left pair's split and ridge ends sit LEFT_SHIFT off the right pair's
	-- (they overlap the end petals by that much) so no faces share a plane
	local LEFT_SHIFT = 0.06
	local function side(name: string, kind: string, s: number, y0: number, y1: number, r0: number, r1: number)
		local x = Vector3.new(0, s, 0)
		local yv = Vector3.new(s * outX.X, 0, outX.Z)
		local seg = if (kind == "upper") == (s > 0) then r1 - y0 else y1 - r0
		add(name, kind, Vector3.new(s * RIM_X, (y0 + y1) / 2, RIM_Z), x, yv, (y1 - y0) / 2, seg, 1.85)
	end
	local split, splitL = RIM_MID, RIM_MID + LEFT_SHIFT
	local r0, r1 = RIM_BOTTOM + RIM_X, RIM_TOP - RIM_X -- ridge ends
	add("Petal1", "end", Vector3.new(0, RIM_TOP, RIM_Z), Vector3.new(-1, 0, 0), inY, RIM_X, 0, 1.55)
	side("Petal2", "upper", 1, split, RIM_TOP, r0, r1)
	side("Petal3", "lower", 1, RIM_BOTTOM, split, r0, r1)
	add("Petal4", "end", Vector3.new(0, RIM_BOTTOM, RIM_Z), Vector3.new(1, 0, 0), Vector3.new(0, -inY.Y, inY.Z), RIM_X, 0, 1.45)
	side("Petal5", "upper", -1, RIM_BOTTOM, splitL, r0 - LEFT_SHIFT, r1 + LEFT_SHIFT)
	side("Petal6", "lower", -1, splitL, RIM_TOP, r0 - LEFT_SHIFT, r1 + LEFT_SHIFT)
end
GunnerBuilder.Petals = PETALS -- open = full opening angle (radians) about each petal's hinge (local X)

GunnerBuilder.Cockpit = {
	min = Vector3.new(-INNER_HALF, FLOOR_TOP, COUCH_FACE), -- clear box, torso frame (to the rim)
	max = Vector3.new(INNER_HALF, ROOF_BOTTOM, RIM_Z),
	footHalf = FOOT_HALF, -- narrower below stepY
	stepY = STEP_Y,
	pilotRoot = PILOT_ROOT, -- avatar root center
	seatTop = SEAT_POS + Vector3.new(0, SEAT_SIZE.Y / 2, 0),
	feetClear = FEET_CLEAR,
	rim = Vector3.new(0, RIM_MID, RIM_Z), -- center of the rear opening
	rimHalf = Vector2.new(RIM_X, (RIM_TOP - RIM_BOTTOM) / 2),
}

-- Powered-down pose, reached in two stages (GunnerPose.offPose):
--   Crouch (k = 0.5): hips drop and sit back with the feet planted, knees
--   out, the body pitches forward, hands reach down ahead, cannon held level.
--   Prone (k = 1): the mech lies face down on its chest and knee plates,
--   legs straight back with the feet pointed, forearms flat on the ground
--   ahead (sphinx), head up, cannon laid forward along the ground, shield
--   flat; the flower on its back opens upward ~7 studs off the ground.
-- Pelvis offsets are from the rest pelvis (design units, model space);
-- pitches are radians (negative = top / front tips forward and down).
GunnerBuilder.Crouch = {
	pelvis = Vector3.new(0, -3.4, 0.9),
	pitch = -0.3,
	waist = -0.45,
	neck = 0.35,
	kneeOut = 0.18,
	cannon = 0.75,
}
GunnerBuilder.Prone = {
	pelvis = Vector3.new(0, 2.81 - PELVIS_POS.Y, -1.2),
	pitch = -math.pi / 2,
	waist = 0,
	neck = 0.5,
	legs = Vector3.new(1.05, -7.48, 0.3), -- hip -> ankle, pelvis frame (X out: x side)
	foot = -math.pi / 2 + 1.15, -- toes dug in, down and back
	cannon = math.pi / 2 - 0.12, -- barrel forward along the ground
}

-- Torso frame of the full prone pose, relative to the root (studs).
local function proneTorso(): CFrame
	local P = GunnerBuilder.Prone
	return CFrame.new((PELVIS_POS - ROOT_POS + P.pelvis) * SCALE) * CFrame.Angles(P.pitch, 0, 0) * CFrame.new((TORSO_POS - PELVIS_POS) * SCALE) * CFrame.Angles(P.waist, 0, 0)
end

type BoneDef = { name: string, parent: string, cf: CFrame, joint: string }

-- rest frames in design units
local REST_DU: { [string]: CFrame } = { HumanoidRootPart = CFrame.new(ROOT_POS) }
local BONES: { BoneDef } = {}
local function bone(name: string, parent: string, cf: CFrame, joint: string)
	REST_DU[name] = cf
	table.insert(BONES, { name = name, parent = parent, cf = cf, joint = joint })
end
bone("Waist", "HumanoidRootPart", CFrame.new(PELVIS_POS), "Root")
bone("Torso", "Waist", CFrame.new(TORSO_POS), "Waist")
bone("Head", "Torso", CFrame.new(NECK_POS), "Neck")
bone("Periscope", "Torso", CFrame.new(PERISCOPE_POS), "PeriscopeTurret")
bone("CannonMount", "Torso", CFrame.new(CANNON_PIVOT), "CannonPitch")
for _, p in PETALS do
	-- petal frame: X along the hinge, Y from the base toward the ridge, Z out
	bone(p.name, "Torso", CFrame.fromMatrix(TORSO_POS + p.hinge, p.x, p.y), p.name .. "Hinge")
end
for _, sd in { { "Right", 1 }, { "Left", -1 } } do
	local n, s = sd[1] :: string, sd[2] :: number
	local upper = CFrame.new(s * SHOULDER.X, SHOULDER.Y, SHOULDER.Z) * CFrame.Angles(0, 0, s * ARM_ROLL)
	local lower = CFrame.new(upper * Vector3.new(0, -UPPER_ARM, 0)) * CFrame.Angles(ELBOW_REST, 0, 0) * CFrame.Angles(0, 0, s * ARM_ROLL)
	local hand = CFrame.new(lower * Vector3.new(0, -FOREARM, 0)) * CFrame.Angles(ELBOW_REST, 0, 0) * CFrame.Angles(0, 0, s * ARM_ROLL)
	bone(n .. "UpperArm", "Torso", upper, n .. "Shoulder")
	bone(n .. "LowerArm", n .. "UpperArm", lower, n .. "Elbow")
	bone(n .. "Hand", n .. "LowerArm", hand, n .. "Wrist")
	bone(n .. "UpperLeg", "Waist", CFrame.new(legPoint(s, Vector3.zero)) * splay(s) * CFrame.Angles(HIP_REST, 0, 0), n .. "Hip")
	bone(n .. "LowerLeg", n .. "UpperLeg", CFrame.new(legPoint(s, KNEE_D)) * splay(s) * CFrame.Angles(SHIN_REST, 0, 0), n .. "Knee")
	bone(n .. "Foot", n .. "LowerLeg", CFrame.new(legPoint(s, ANKLE_D)), n .. "Ankle") -- level
end
bone("Shield", "LeftLowerArm", REST_DU.LeftLowerArm * CFrame.new(SHIELD_OFFSET) * CFrame.Angles(-ELBOW_REST, 0, 0), "ShieldMount") -- hangs plumb
GunnerBuilder.Bones = BONES -- design units; multiply positions by Scale for studs

local REST: { [string]: CFrame } = {}
for name, cf in REST_DU do
	REST[name] = CFrame.new(cf.Position * SCALE) * cf.Rotation
end
-- rest frame of a bone in model space (studs)
function GunnerBuilder.restFrame(name: string): CFrame
	return REST[name]
end

-- Key points of the powered-down (prone) pose in world space, for a mech
-- whose root is at `rootCF`.
export type OffPoints = {
	torso: CFrame, -- the torso (pod) frame, studs
	seat: CFrame, -- top center of the seat
	pilot: CFrame, -- where the avatar's root ends up (lying prone)
	rim: Vector3, -- center of the open flower on the back
	prompt: Vector3, -- on the ground beside the open flower
	exit: Vector3, -- on the ground where an unseated pilot is put down
	ground: number,
	forward: Vector3,
}
function GunnerBuilder.offPoints(rootCF: CFrame): OffPoints
	local torso = rootCF * proneTorso()
	local rim = torso * (GunnerBuilder.Cockpit.rim * SCALE)
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local ground = rootCF.Y - GunnerBuilder.RootHeight
	local side = Vector3.new(rim.X, ground, rim.Z) + right * (FLANK_X + 2.2) * SCALE
	return {
		torso = torso,
		seat = torso * CFrame.new(GunnerBuilder.Cockpit.seatTop * SCALE),
		pilot = torso * CFrame.new(PILOT_ROOT * SCALE),
		rim = rim,
		prompt = side,
		exit = side + right * 2 - forward * 2,
		ground = ground,
		forward = forward,
	}
end

-- Re-sets the pilot seat's weld so the seated avatar stands upright in the
-- pod with its feet FEET_CLEAR above the floor (server, right after Sit).
function GunnerBuilder.fitPilot(model: Model, hum: Humanoid)
	local seat = model:FindFirstChild("PilotSeat")
	local weld = seat and seat:FindFirstChild("SeatWeld")
	local hrp = hum.RootPart
	if not (weld and weld:IsA("Weld") and hrp) then
		return
	end
	local rootY = FLOOR_TOP * SCALE + FEET_CLEAR + hum.HipHeight + hrp.Size.Y / 2 -- torso frame, studs
	local seatTop = (SEAT_POS.Y + SEAT_SIZE.Y / 2) * SCALE
	weld.C0 = CFrame.new(0, SEAT_SIZE.Y / 2 * SCALE, 0)
	weld.C1 = CFrame.new(0, -(rootY - seatTop), 0)
end

local ROT_Y_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
local ROT_Z_AXIS = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z
local FLIP = CFrame.Angles(0, 0, math.pi) -- wedge sloped underneath, thick end at the back
local TURN = CFrame.Angles(0, math.pi, 0) -- wedge thin end at the back
-- wedge running along Z, its slope facing up and toward side s (+1 = +X)
local function slopeSide(s: number): CFrame
	return CFrame.Angles(0, -s * math.pi / 2, 0)
end
-- wedge running along Z, its slope facing down and toward side s
local function underSide(s: number): CFrame
	return CFrame.Angles(0, s * math.pi / 2, 0) * FLIP
end

local SHAPES = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

-- Adds one armor piece welded to a bone; `pos` / `rot` in the bone's rest frame.
local function piece(model: Model, folder: Folder, palette: Palette, boneName: string, kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?): BasePart
	local b = model:FindFirstChild(boneName) :: BasePart
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
	elseif color == "trim" then
		part.Color = trimColor(palette)
		part.Material = Enum.Material.SmoothPlastic
	else
		part.Color = palette[color]
		part.Material = Enum.Material.SmoothPlastic
	end
	part.Anchored = false
	part.CanTouch = false
	part.Massless = true
	-- big plates are solid to on-foot players (see MechBuilder.ArmorGroup); small details aren't
	local a, bb, c = size.X, size.Y, size.Z
	local mid = math.max(math.min(a, bb), math.min(math.max(a, bb), c))
	part.CanCollide = mid >= 0.9 and math.min(a, bb, c) >= 0.1 and (color == "main" or color == "panel" or color == "dark") and kind ~= "Seat"
	part.CollisionGroup = MechBuilder.ArmorGroup
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local offset = CFrame.new(pos * SCALE) * (rot or CFrame.identity)
	part.CFrame = b.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = b
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

-- A piece placed in model space (design units, rest pose) on a bone.
local function addAt(add: Add, boneName: string, kind: string, size: Vector3, at: CFrame, color: ColorKey): BasePart
	local loc = REST_DU[boneName]:ToObjectSpace(at)
	return add(boneName, kind, size, loc.Position, color, loc.Rotation)
end

-- Hexagonal prism facing front / back (+-Z): three rectangles 60 degrees
-- apart (depths staggered so no two faces share a plane). f = flat-to-flat.
local function hexZ(add: Add, b: string, center: Vector3, f: number, depth: number, color: ColorKey)
	local r = f / math.sqrt(3)
	for i = 0, 2 do
		add(b, "Block", Vector3.new(r, f, depth + i * 0.14), center, color, CFrame.Angles(0, 0, i * math.pi / 3))
	end
end

-- Hexagonal prism facing the sides (+-X), turned by `base` about X.
local function hexX(add: Add, b: string, center: Vector3, f: number, width: number, base: number, color: ColorKey)
	local r = f / math.sqrt(3)
	for i = 0, 2 do
		add(b, "Block", Vector3.new(width + i * 0.12, f, r), center, color, CFrame.Angles(base + i * math.pi / 3, 0, 0))
	end
end

local function buildHelmet(add: Add)
	local H = "Head" -- origin at the neck, on the chest top
	add(H, "Block", Vector3.new(1.4, 0.95, 1.45), Vector3.new(0, 0.36, -0.1), "main")
	add(H, "Block", Vector3.new(1.66, 0.14, 1.25), Vector3.new(0, 0.88, 0.08), "panel") -- brow cap
	add(H, "Block", Vector3.new(0.9, 0.25, 0.4), Vector3.new(0, 0.1, -0.82), "dark") -- chin
	for _, s in { 1, -1 } do
		add(H, "Block", Vector3.new(0.22, 0.6, 1.0), Vector3.new(s * 0.78, 0.36, 0.05), "dark") -- cheeks
	end
	-- vertical sensor slot
	add(H, "Block", Vector3.new(0.42, 0.62, 0.08), Vector3.new(0, 0.36, -0.86), "trim")
	add(H, "Block", Vector3.new(0.22, 0.42, 0.2), Vector3.new(0, 0.36, -0.86), "light")

	-- periscope turret: stepped tower, front lens, ring on top
	local P = "Periscope"
	add(P, "Block", Vector3.new(1.35, 1.3, 1.3), Vector3.new(0, 0.6, 0), "main")
	add(P, "Block", Vector3.new(1.0, 0.5, 1.05), Vector3.new(0, 1.5, 0.05), "main")
	add(P, "Block", Vector3.new(0.8, 0.24, 0.85), Vector3.new(0, 1.87, 0.05), "panel")
	add(P, "Block", Vector3.new(0.18, 0.2, 0.3), Vector3.new(0, 2.08, 0.05), "dark")
	add(P, "Cylinder", Vector3.new(0.12, 0.56, 0.56), Vector3.new(0, 2.43, 0.05), "trim", ROT_Z_AXIS) -- ring
	add(P, "Cylinder", Vector3.new(0.24, 0.3, 0.3), Vector3.new(0, 2.43, 0.05), "dark", ROT_Z_AXIS)
	add(P, "Cylinder", Vector3.new(0.12, 0.8, 0.8), Vector3.new(0, 0.82, -0.68), "dark", ROT_Z_AXIS) -- lens housing
	add(P, "Cylinder", Vector3.new(0.3, 0.42, 0.42), Vector3.new(0, 0.82, -0.7), "light", ROT_Z_AXIS)
	for _, s in { 1, -1 } do
		add(P, "Block", Vector3.new(0.1, 0.9, 0.9), Vector3.new(s * 0.72, 0.55, 0.15), "dark") -- side fins
	end
end

local function buildChest(add: Add)
	local T = "Torso" -- origin at the waist pivot; the pod frame
	local shellDepth = BACK_OUTER - FRONT_OUTER
	local shellZ = (BACK_OUTER + FRONT_OUTER) / 2
	-- interior fittings: never solid
	local function ghost(part: BasePart): BasePart
		part.CanCollide = false
		return part
	end

	-- pod shell, open at the back: narrow footwell below the ledges, full width above
	add(T, "Block", Vector3.new(FOOT_HALF * 2, FLOOR_TOP - FLOOR_BOTTOM, shellDepth), Vector3.new(0, (FLOOR_TOP + FLOOR_BOTTOM) / 2, shellZ), "dark").Name = "CockpitFloor"
	add(T, "Block", Vector3.new(INNER_HALF * 2, ROOF_TOP - ROOF_BOTTOM, shellDepth), Vector3.new(0, (ROOF_TOP + ROOF_BOTTOM) / 2, shellZ), "main")
	add(T, "Block", Vector3.new(1.7, 0.3, 3.4), Vector3.new(0, FLOOR_BOTTOM - 0.15, -0.2), "dark") -- belly
	-- front wall (fixed armor; the raised central block is on its outside)
	add(T, "Block", Vector3.new(FOOT_HALF * 2, STEP_Y - FLOOR_TOP, FRONT_T), Vector3.new(0, (FLOOR_TOP + STEP_Y) / 2, INNER_FRONT - FRONT_T / 2), "main").Name = "CockpitFront"
	add(T, "Block", Vector3.new(INNER_HALF * 2, ROOF_BOTTOM - STEP_Y, FRONT_T), Vector3.new(0, (STEP_Y + ROOF_BOTTOM) / 2, INNER_FRONT - FRONT_T / 2), "main")
	add(T, "Block", Vector3.new(2.45, 3.0, 0.35), Vector3.new(0, 3.1, FRONT_OUTER - 0.175), "main") -- central block
	add(T, "Block", Vector3.new(1.4, 1.5, 0.08), Vector3.new(0, 2.9, FRONT_OUTER - 0.39), "panel")
	for _, s in { 1, -1 } do
		-- light-grey chevron under the head
		add(T, "Block", Vector3.new(0.95, 0.16, 0.1), Vector3.new(s * 0.42, 4.25, FRONT_OUTER - 0.43 + s * 0.03), "trim", CFrame.Angles(0, 0, s * 0.3))
		add(T, "Block", Vector3.new(0.12, 2.7, 0.06), Vector3.new(s * 1.0, 2.95, FRONT_OUTER - 0.38), "dark") -- seams
	end
	hexZ(add, T, Vector3.new(0, 1.0, FRONT_OUTER - 0.2), 0.95, 0.46, "panel") -- hex belly plate

	for _, s in { 1, -1 } do
		add(T, "Block", Vector3.new(WAIST_HALF - FOOT_HALF, STEP_Y - 0.2 - FLOOR_BOTTOM, shellDepth), Vector3.new(s * (WAIST_HALF + FOOT_HALF) / 2, (STEP_Y - 0.2 + FLOOR_BOTTOM) / 2, shellZ), "dark") -- waist walls
		add(T, "Block", Vector3.new(POD_HALF - FOOT_HALF, 0.2, 1.25 - INNER_FRONT), Vector3.new(s * (POD_HALF + FOOT_HALF) / 2, STEP_Y - 0.1, (1.25 + INNER_FRONT) / 2), "dark") -- ledge
		add(T, "Block", Vector3.new(POD_HALF - INNER_HALF, ROOF_TOP - STEP_Y, shellDepth), Vector3.new(s * (POD_HALF + INNER_HALF) / 2, (ROOF_TOP + STEP_Y) / 2, shellZ), "main")

		-- flank armor: full width at the sensor slots, tapering to the waist
		local fw = FLANK_X - POD_HALF
		local fx = s * (FLANK_X + POD_HALF) / 2
		add(T, "Block", Vector3.new(fw, FLANK_TOP - 2.2, 3.65), Vector3.new(fx, (FLANK_TOP + 2.2) / 2, -0.275), "main")
		add(T, "Block", Vector3.new(0.77, 1.0, 3.5), Vector3.new(s * 2.035, 1.7, -0.25), "main")
		add(T, "Wedge", Vector3.new(3.35, 0.65, 0.77), Vector3.new(s * 2.035, 0.875, -0.25), "main", underSide(s))
		add(T, "Block", Vector3.new(0.08, 1.3, 2.3), Vector3.new(s * (FLANK_X + 0.04), 3.35, -0.4), "panel") -- side inset
		-- framed sensor slot on the upper chest
		local slotX = s * 2.18
		add(T, "Block", Vector3.new(1.05, 1.2, 0.12), Vector3.new(slotX, 2.9, -2.16), "trim")
		add(T, "Block", Vector3.new(0.8, 0.8, 0.12), Vector3.new(slotX, 2.9, -2.22), "dark")
		add(T, "Block", Vector3.new(0.6, 0.12, 0.08), Vector3.new(slotX, 2.9, -2.3), "light")
		add(T, "Block", Vector3.new(0.8, 1.2, 1.4), Vector3.new(s * 2.95, 3.75, 0.3), "dark") -- shoulder yoke

		-- thrusters on the flank backs, beside the flower, pointing back and down
		local mount = Vector3.new(s * 2.2, 1.8, 1.85)
		local dir = Vector3.new(0, -math.sin(0.6), math.cos(0.6))
		local tilt = CFrame.Angles(0.6, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0) -- cylinder axis along dir
		add(T, "Block", Vector3.new(0.8, 0.8, 0.7), mount, "dark")
		add(T, "Cylinder", Vector3.new(1.5, 1.0, 1.0), mount + dir * 0.85, "main", tilt)
		add(T, "Cylinder", Vector3.new(0.45, 0.8, 0.8), mount + dir * 1.75, "dark", tilt)

		-- interior: screens on the ledges and side walls, grips beside the couch
		add(T, "Block", Vector3.new(0.3, 0.07, 0.7), Vector3.new(s * 1.3, STEP_Y + 0.035, -1.0), "glow")
		add(T, "Block", Vector3.new(0.3, 0.07, 0.5), Vector3.new(s * 1.3, STEP_Y + 0.035, -0.1), "screen")
		add(T, "Block", Vector3.new(0.07, 0.6, 0.9), Vector3.new(s * (INNER_HALF - 0.035), 2.7, -0.7), "screen")
		ghost(add(T, "Block", Vector3.new(0.16, 0.7, 0.16), Vector3.new(s * 1.12, 2.0, COUCH_FACE + 0.1), "dark"))
	end
	add(T, "Block", Vector3.new(1.0, 0.08, 0.3), Vector3.new(0, ROOF_BOTTOM - 0.04, -0.2), "glow") -- dome light
	-- HUD bar hanging from the roof's front edge, screens facing the pilot
	ghost(add(T, "Block", Vector3.new(2.2, 0.4, 0.3), Vector3.new(0, ROOF_BOTTOM - 0.2, INNER_FRONT + 0.2), "dark"))
	add(T, "Block", Vector3.new(0.9, 0.2, 0.07), Vector3.new(-0.5, ROOF_BOTTOM - 0.2, INNER_FRONT + 0.385), "glow")
	add(T, "Block", Vector3.new(0.7, 0.2, 0.07), Vector3.new(0.6, ROOF_BOTTOM - 0.2, INNER_FRONT + 0.385), "screen")

	-- prone couch on the front wall: the pilot lies chest-down on it (stands
	-- against it when the mech is up); face screen above it
	ghost(add(T, "Block", Vector3.new(1.5, 1.7, COUCH_FACE - INNER_FRONT), Vector3.new(0, 2.85, (COUCH_FACE + INNER_FRONT) / 2), "panel"))
	add(T, "Block", Vector3.new(0.9, 0.45, 0.07), Vector3.new(0, 4.1, INNER_FRONT + 0.035), "screen")
	for i = 0, 2 do
		ghost(add(T, "Block", Vector3.new(1.3, 0.1, 0.06), Vector3.new(0, 2.3 + i * 0.55, COUCH_FACE + 0.03), "dark")) -- pad seams
	end
	local seat = add(T, "Seat", SEAT_SIZE, SEAT_POS, "dark") -- "PilotSeat", kept outside the armor folder
	seat.Transparency = 1
	seat.CanCollide = false

	-- collar around the sunken head
	add(T, "Block", Vector3.new(1.54, 0.45, 0.6), Vector3.new(0, ROOF_TOP + 0.225, 1.1), "panel")
	for _, s in { 1, -1 } do
		add(T, "Block", Vector3.new(0.35, 0.45, 1.5), Vector3.new(s * 0.95, ROOF_TOP + 0.225, 0.25), "panel")
	end
	-- antenna beside the head (left)
	add(T, "Block", Vector3.new(0.4, 0.25, 0.4), Vector3.new(-1.95, FLANK_TOP + 0.175, 0.75), "dark")
	add(T, "Cylinder", Vector3.new(1.55, 0.12, 0.12), Vector3.new(-1.95, FLANK_TOP + 1.05, 0.75), "dark", ROT_Y_AXIS)

	-- cannon pylon on the left of the chest top
	add(T, "Block", Vector3.new(0.8, 0.6, 1.3), Vector3.new(-2.25, FLANK_TOP + 0.28, 0.85), "dark")
	add(T, "Block", Vector3.new(0.2, 0.8, 0.9), Vector3.new(-1.75, 5.7, 0.9), "dark")

	-- rim fillers beside the footwell (the lower petals hinge on them)
	for _, s in { 1, -1 } do
		add(T, "Block", Vector3.new(POD_HALF - WAIST_HALF, STEP_Y - 0.25, 0.3), Vector3.new(s * (POD_HALF + WAIST_HALF) / 2, (STEP_Y - 0.05 + 0.2) / 2, BACK_OUTER - 0.15), "dark")
	end

	-- flower petals (petal frame: X along the hinge, Y toward the ridge, Z out;
	-- the outer face lies on the closed bud's surface)
	local function tri(b: string, p: Vector2, dir: number, a: number, h: number, color: ColorKey)
		local xd = Vector3.new(dir, 0, 0)
		local z = -xd
		local y = Vector3.yAxis
		local c = Vector3.new(p.X, p.Y, 0) + xd * (a / 2) + y * (h / 2) - Vector3.zAxis * (PETAL_T / 2)
		add(b, "Wedge", Vector3.new(PETAL_T, h, a), c, color, CFrame.fromMatrix(Vector3.zero, y:Cross(z), y, z))
	end
	for _, p in PETALS do
		local b = p.name
		local glowX = 0
		if p.kind == "end" then
			tri(b, Vector2.zero, 1, RIM_X, SLANT, "main")
			tri(b, Vector2.zero, -1, RIM_X, SLANT, "main")
		else
			local dir = if p.kind == "upper" then 1 else -1
			local edge = -dir * p.half -- the split edge (bud middle)
			local inner = edge + dir * p.seg
			add(b, "Block", Vector3.new(p.seg, SLANT, PETAL_T), Vector3.new((edge + inner) / 2, SLANT / 2, -PETAL_T / 2), "main")
			tri(b, Vector2.new(inner, 0), dir, dir * (dir * p.half - inner), SLANT, "main")
			glowX = (edge + inner) / 2 + dir * 0.2
		end
		add(b, "Block", Vector3.new(0.1, SLANT * 0.6, 0.06), Vector3.new(glowX, SLANT * 0.42, -PETAL_T - 0.03), "glow") -- inner glow strip
		add(b, "Block", Vector3.new(0.5, 0.18, 0.12), Vector3.new(glowX, 0.12, -PETAL_T - 0.06), "dark") -- hinge lug
		add(b, "Block", Vector3.new(0.14, SLANT * 0.7, 0.06), Vector3.new(glowX, SLANT * 0.42, 0.03), "panel") -- outer rib
	end

	-- cannon (CannonMount: pivot over the left shoulder, barrel forward)
	local C = "CannonMount"
	local cx = -0.55
	add(C, "Cylinder", Vector3.new(1.3, 0.75, 0.75), Vector3.new(-0.25, 0, 0), "dark") -- trunnion
	add(C, "Block", Vector3.new(0.9, 0.45, 1.8), Vector3.new(cx, 0.15, 0.2), "dark") -- cradle
	add(C, "Block", Vector3.new(1.0, 1.15, 4.4), Vector3.new(cx, 0.825, -0.7), "main") -- receiver
	add(C, "Block", Vector3.new(0.85, 1.0, 2.4), Vector3.new(cx, 0.8, 2.7), "main") -- stock
	add(C, "Block", Vector3.new(0.95, 1.4, 0.5), Vector3.new(cx, 0.75, 4.15), "panel") -- butt
	add(C, "Block", Vector3.new(0.75, 0.45, 2.2), Vector3.new(cx, 0.1, -1.6), "panel") -- lower body
	add(C, "Block", Vector3.new(0.7, 0.3, 3.2), Vector3.new(cx, 1.55, -1.1), "main") -- top rail
	for i = 0, 3 do
		add(C, "Block", Vector3.new(1.1, 0.4, 0.14), Vector3.new(cx, 0.95, -1.4 - i * 0.35), "dark", CFrame.Angles(0.35, 0, 0)) -- vents
	end
	add(C, "Block", Vector3.new(0.8, 0.8, 0.5), Vector3.new(cx, 0.75, -3.1), "panel") -- barrel collar
	add(C, "Cylinder", Vector3.new(4.1, 0.55, 0.55), Vector3.new(cx, 0.75, -4.95), "dark", ROT_Z_AXIS) -- barrel
	add(C, "Block", Vector3.new(0.85, 0.95, 1.75), Vector3.new(cx, 0.75, -7.775), "main") -- muzzle brake
	for _, z in { -7.3, -7.75, -8.2 } do
		add(C, "Block", Vector3.new(0.95, 0.5, 0.16), Vector3.new(cx, 0.75, z), "dark")
	end
	add(C, "Block", Vector3.new(0.45, 0.3, 2.1), Vector3.new(cx, 1.85, -0.3), "panel") -- scope
	add(C, "Block", Vector3.new(0.58, 0.48, 0.45), Vector3.new(cx, 2.0, -1.55), "main")
	add(C, "Block", Vector3.new(0.55, 0.44, 0.4), Vector3.new(cx, 2.0, 0.85), "main")
	add(C, "Cylinder", Vector3.new(0.1, 0.3, 0.3), Vector3.new(cx, 2.0, -1.8), "light", ROT_Z_AXIS)
	add(C, "Block", Vector3.new(0.06, 0.14, 2.6), Vector3.new(cx - 0.53, 1.0, 0.4), "trim") -- side stripe

	-- arms: shoulder blocks stay upright (model space), the rest follows the arm bones
	for _, sd in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local UA, LA, HD = n .. "UpperArm", n .. "LowerArm", n .. "Hand"
		add(UA, "Ball", Vector3.new(1.25, 1.25, 1.25), Vector3.zero, "dark")
		addAt(add, UA, "Block", Vector3.new(2.3, 1.75, 2.45), CFrame.new(s * 3.75, 13.675, 0.25), "main")
		addAt(add, UA, "Block", Vector3.new(1.6, 0.5, 2.3), CFrame.new(s * 3.4, 14.8, 0.3), "main")
		addAt(add, UA, "Wedge", Vector3.new(2.3, 0.5, 0.7), CFrame.new(s * 4.55, 14.8, 0.3) * slopeSide(s), "main")
		addAt(add, UA, "Block", Vector3.new(1.6, 0.18, 0.08), CFrame.new(s * 3.8, 13.95, -1.015), "panel")
		addAt(add, UA, "Block", Vector3.new(0.08, 1.2, 1.6), CFrame.new(s * 4.94, 13.6, 0.3), "panel")
		-- upper arm
		add(UA, "Block", Vector3.new(1.1, 1.5, 1.1), Vector3.new(0, -1.2, 0), "dark")
		add(UA, "Block", Vector3.new(1.4, 0.9, 1.4), Vector3.new(0, -1.6, 0), "main")
		add(UA, "Block", Vector3.new(0.9, 0.6, 0.3), Vector3.new(s * 0.1, -2.05, -0.72), "panel") -- elbow pad

		-- forearm: armored, light-grey cuff band
		add(LA, "Ball", Vector3.new(1.15, 1.15, 1.15), Vector3.zero, "dark")
		add(LA, "Block", Vector3.new(1.65, 2.55, 1.8), Vector3.new(0, -1.5, 0), "main")
		add(LA, "Block", Vector3.new(0.3, 2.2, 1.5), Vector3.new(s * 0.95, -1.4, 0), "panel")
		add(LA, "Block", Vector3.new(1.0, 1.6, 0.1), Vector3.new(0, -1.4, -0.94), "panel")
		add(LA, "Block", Vector3.new(1.8, 0.42, 1.95), Vector3.new(0, -2.95, 0), "trim") -- cuff band
		add(LA, "Block", Vector3.new(1.2, 0.5, 1.3), Vector3.new(0, -3.2, 0), "dark") -- wrist
		if s > 0 then
			-- right forearm guard with light-grey edges
			add(LA, "Block", Vector3.new(0.32, 3.6, 1.55), Vector3.new(1.3, -1.6, 0), "main")
			add(LA, "Block", Vector3.new(0.38, 3.6, 0.12), Vector3.new(1.3, -1.6, -0.835), "trim")
			add(LA, "Block", Vector3.new(0.38, 0.12, 1.4), Vector3.new(1.3, 0.26, -0.05), "trim")
		end

		-- clawed fist, palm facing in
		add(HD, "Block", Vector3.new(1.2, 1.0, 1.3), Vector3.new(0, -0.55, 0), "dark")
		add(HD, "Block", Vector3.new(0.3, 0.7, 1.1), Vector3.new(s * 0.62, -0.5, 0), "main") -- back of the hand
		for _, z in { -0.4, 0, 0.4 } do
			local f = CFrame.new(-s * 0.12, -1.2, z) * CFrame.Angles(0, 0, -s * 0.35)
			add(HD, "Block", Vector3.new(0.36, 0.8, 0.34), f.Position, "dark", f.Rotation)
		end
		local thumb = CFrame.new(-s * 0.45, -0.75, -0.55) * CFrame.Angles(-0.3, 0, -s * 0.3)
		add(HD, "Block", Vector3.new(0.28, 0.7, 0.28), thumb.Position, "dark", thumb.Rotation)
	end

	-- tall narrow shield on the left forearm (bone origin at its mount)
	local SH = "Shield"
	add(SH, "Block", Vector3.new(0.85, 1.2, 1.0), Vector3.new(0.6, 0.4, 0), "dark") -- bracket
	add(SH, "Block", Vector3.new(0.5, 9.0, 2.5), Vector3.new(0, -1.3, 0), "main")
	add(SH, "Block", Vector3.new(0.08, 7.8, 1.9), Vector3.new(-0.29, -1.3, 0), "panel")
	add(SH, "Block", Vector3.new(0.06, 7.0, 0.16), Vector3.new(-0.36, -1.3, -0.75), "trim")
	add(SH, "Block", Vector3.new(0.15, 6.4, 0.5), Vector3.new(0.3, -1.3, 0), "dark") -- inner rib
	add(SH, "Wedge", Vector3.new(0.5, 0.8, 2.5), Vector3.new(0, 3.6, 0), "main") -- pointed top
	add(SH, "Wedge", Vector3.new(0.5, 0.8, 2.5), Vector3.new(0, -6.2, 0), "main", FLIP) -- pointed bottom
end

local function buildLegs(add: Add)
	local W = "Waist" -- pelvis, origin at PELVIS_POS
	add(W, "Block", Vector3.new(2.6, 0.9, 2.0), Vector3.new(0, -0.05, 0.1), "dark")
	for _, s in { 1, -1 } do
		add(W, "Cylinder", Vector3.new(1.2, 0.95, 0.95), Vector3.new(s * 1.55, 0, 0), "dark") -- hip axles
	end
	-- central crotch plate
	add(W, "Block", Vector3.new(1.6, 0.6, 0.6), Vector3.new(0, 0.3, -1.0), "panel")
	add(W, "Block", Vector3.new(1.2, 2.0, 0.5), Vector3.new(0, -0.55, -1.15), "main")
	add(W, "Block", Vector3.new(0.7, 1.2, 0.08), Vector3.new(0, -0.5, -1.44), "panel")
	add(W, "Wedge", Vector3.new(1.2, 0.45, 0.5), Vector3.new(0, -1.775, -1.15), "main", FLIP * TURN)
	add(W, "Block", Vector3.new(1.5, 1.4, 0.5), Vector3.new(0, -0.4, 1.3), "main") -- rear plate

	for _, sd in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local UL, LL, F = n .. "UpperLeg", n .. "LowerLeg", n .. "Foot"
		-- A piece placed as on the sheet's side view: (fwd, y) = forward of the
		-- body center / height (design units), x = out from the leg's axis,
		-- pitch about X (+ = lower end forward); the splay roll is applied.
		local hipCF = CFrame.new(legPoint(s, Vector3.zero)) * splay(s)
		local function legAt(b: string, kind: string, size: Vector3, fwd: number, y: number, x: number, pitch: number, color: ColorKey, rot: CFrame?): BasePart
			local yu = (y - HIP_Y) / math.cos(LEG_SPLAY)
			return addAt(add, b, kind, size, hipCF * CFrame.new(s * x, yu, -fwd) * CFrame.Angles(pitch, 0, 0) * (rot or CFrame.identity), color)
		end
		-- the same on the (level) foot: x out from the foot bone
		local footPos = legPoint(s, ANKLE_D)
		local function footAt(kind: string, size: Vector3, fwd: number, y: number, x: number, color: ColorKey, rot: CFrame?): BasePart
			return addAt(add, F, kind, size, CFrame.new(footPos.X + s * x, y, -fwd) * (rot or CFrame.identity), color)
		end

		-- thigh: thick box, chamfered top outer edge, panels; plumb, its armor
		-- raked a little (rear edge lower end back, as drawn)
		add(UL, "Ball", Vector3.new(1.3, 1.3, 1.3), Vector3.zero, "dark")
		local rake = CFrame.new(0, -2.0, 0) * CFrame.Angles(-0.12, 0, 0) * CFrame.new(0, 2.0, -0.05)
		local function thigh(kind: string, size: Vector3, pos: Vector3, color: ColorKey, rot: CFrame?)
			local cf = rake * CFrame.new(pos) * (rot or CFrame.identity)
			add(UL, kind, size, cf.Position, color, cf.Rotation)
		end
		thigh("Block", Vector3.new(2.0, 1.8, 2.3), Vector3.new(0, -1.1, 0.15), "main")
		thigh("Block", Vector3.new(1.38, 0.5, 2.3), Vector3.new(-s * 0.24, 0.05, 0.15), "main")
		thigh("Wedge", Vector3.new(2.3, 0.5, 0.605), Vector3.new(s * 0.7525, 0.05, 0.15), "main", slopeSide(s))
		thigh("Block", Vector3.new(1.7, 1.3, 2.2), Vector3.new(s * 0.03, -2.55, 0.32), "main")
		thigh("Block", Vector3.new(1.3, 1.3, 0.08), Vector3.new(0, -1.1, -1.03), "panel")
		thigh("Block", Vector3.new(1.0, 0.4, 0.1), Vector3.new(s * 0.03, -2.85, -0.82), "panel")
		thigh("Block", Vector3.new(0.12, 1.4, 1.7), Vector3.new(s * 1.0, -1.15, 0.15), "panel")
		thigh("Block", Vector3.new(1.3, 1.5, 0.3), Vector3.new(0, -1.3, 1.42), "panel")
		-- rear knee pad: a long plate behind the knee, top end back
		legAt(UL, "Block", Vector3.new(1.4, 1.75, 0.6), -1.13, 5.34, 0, 0.56, "main")

		-- knee: axle with round caps (r 0.64 on the sheet)
		legAt(LL, "Cylinder", Vector3.new(1.7, 0.9, 0.9), 0, 5.66, 0, 0, "dark")
		for _, f in { 1, -1 } do
			legAt(LL, "Cylinder", Vector3.new(0.16, 1.28, 1.28), 0, 5.66, f * 0.9, 0, "main")
			legAt(LL, "Cylinder", Vector3.new(0.26, 0.96, 0.96), 0, 5.66, f * 0.9, 0, "panel")
		end
		-- wide strut from the knee forward-down to the hex shin plate
		legAt(LL, "Block", Vector3.new(1.1, 1.95, 0.9), 0.95, 5.0, 0, 0.93, "dark")
		-- hex shin plate forward of the knee (vertices at 10 deg + k * 60 deg)
		local HEX_F = 1.95
		for i = 0, 2 do
			legAt(LL, "Block", Vector3.new(1.6 + i * 0.12, HEX_F, HEX_F / math.sqrt(3)), 1.74, 4.19, 0, math.rad(10) + i * math.pi / 3, "main")
		end
		-- lower shin plate under the hex, raked back to the ankle
		legAt(LL, "Block", Vector3.new(1.46, 2.3, 1.15), 0.55, 2.9, 0, -0.314, "main")
		legAt(LL, "Block", Vector3.new(1.2, 1.6, 0.08), 0.0, 3.05, 0, -0.314, "panel")
		-- front rods: segmented frame from under the hex down to the ankle ball
		legAt(LL, "Block", Vector3.new(0.5, 1.25, 0.55), 1.68, 2.85, 0, -0.33, "dark")
		legAt(LL, "Block", Vector3.new(0.6, 0.3, 0.65), 1.47, 2.2, 0, -0.33, "panel")
		legAt(LL, "Block", Vector3.new(0.44, 0.95, 0.48), 1.3, 1.7, 0, -0.33, "dark")
		-- light-grey ankle band, square to the shin and turned 45 deg on the sheet
		legAt(LL, "Block", Vector3.new(1.9, 1.05, 0.85), -0.28, 1.8, 0, 0.8, "trim")

		-- foot (level): link under the band forward to a ball joint, rear and
		-- front blocks with a low arch, claws and spikes fore and aft
		local fx = 0.1
		footAt("Ball", Vector3.new(0.8, 0.8, 0.8), -0.33, 1.69, 0, "dark")
		footAt("Block", Vector3.new(0.7, 0.75, 0.6), -0.3, 1.25, fx, "dark")
		footAt("Block", Vector3.new(0.8, 0.5, 1.55), 0.22, 1.0, fx, "dark", CFrame.Angles(-0.05, 0, 0))
		footAt("Ball", Vector3.new(0.72, 0.72, 0.72), 0.97, 1.03, fx, "dark")
		footAt("Block", Vector3.new(1.6, 0.85, 0.95), -0.52, 0.5, fx, "main") -- heel
		footAt("Block", Vector3.new(1.75, 0.8, 1.25), 1.62, 0.45, fx, "main") -- toe
		footAt("Wedge", Vector3.new(1.55, 0.2, 0.9), 1.5, 0.95, fx, "main")
		footAt("Block", Vector3.new(1.4, 0.18, 3.2), 0.55, 0.09, fx, "dark") -- sole
		footAt("Block", Vector3.new(1.4, 0.1, 0.08), 2.27, 0.55, fx, "trim")
		for _, c in { 1, -1 } do
			local x = fx + c * s * 0.85
			footAt("Wedge", Vector3.new(0.3, 0.95, 0.6), 2.78, 0.83, x, "dark") -- toe claw (upright)
			footAt("Wedge", Vector3.new(0.42, 0.42, 1.25), 3.12, 0.21, x, "dark") -- toe spike
			footAt("Wedge", Vector3.new(1.1, 1.45, 0.43), 1.7, 0.725, fx + c * s * 1.25, "dark", slopeSide(c * s)) -- side talon
		end
		footAt("Wedge", Vector3.new(0.34, 0.95, 0.6), -1.55, 0.825, fx, "dark", TURN) -- heel claw (upright)
		footAt("Wedge", Vector3.new(0.44, 0.45, 1.6), -1.88, 0.225, fx, "dark", TURN) -- heel spike
	end
end

local SLOT_BUILDERS = {
	Helmet = buildHelmet,
	Chest = buildChest,
	Legs = buildLegs,
}

-- Builds the bare rig: root, bones, motors, humanoid. No armor.
function GunnerBuilder.buildRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", GunnerBuilder.TypeId) -- see MechTypes

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
		local b = Instance.new("Part")
		b.Name = def.name
		b.Size = Vector3.new(0.4, 0.4, 0.4)
		b.CFrame = REST[def.name]
		b.Transparency = 1
		b.CanCollide = false
		b.CanTouch = false
		b.CanQuery = false
		b.Massless = true
		b.Parent = model
		bones[def.name] = b

		local motor = Instance.new("Motor6D")
		motor.Name = def.joint
		motor.Part0 = parent
		motor.Part1 = b
		motor.C0 = REST[def.parent]:ToObjectSpace(REST[def.name])
		motor.C1 = CFrame.identity
		motor.Parent = b
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = GunnerBuilder.HipHeight
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
function GunnerBuilder.applySlot(model: Model, slot: string, variantId: string)
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
function GunnerBuilder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = GunnerBuilder.buildRig(name)
	for _, slot in MechConfig.Slots do
		GunnerBuilder.applySlot(model, slot, loadout[slot])
	end
	return model
end

return GunnerBuilder
