--!strict
-- Pose math for the GR-07 (GunnerBuilder), shared by clients and the server.
--
--   * offPose(k): the powered-down pose as joint transforms, blended by k
--     (0 standing .. 1 down) in two stages (GunnerBuilder.Crouch / Prone):
--     k 0..0.5 crouch with the feet planted (two-bone leg IK toward the
--     fixed ankles) while the body pitches forward and the hands reach for
--     the ground; k 0.5..1 lie down face first: the feet slide back and point,
--     the body lowers onto its chest and knee plates, forearms go flat ahead,
--     the cannon lays forward. Run backwards it is the stand-up.
--   * setPetals(motors, h): the flower hatch on the back, 0 shut .. 1 open,
--     each petal a little after the previous one (a ripple).
--   * powerTargets(model): off / petals / light levels for the PowerState +
--     PowerTime (GunnerPose.Board / Exit, the placeholder get-in timings).
--   * applyStatic / applyOff: the server mirror and the edit-mode preview.

local GunnerBuilder = require(script.Parent.GunnerBuilder)

local GunnerPose = {}

local S = GunnerBuilder.Scale
local LEGS = GunnerBuilder.Legs
local CR, PR = GunnerBuilder.Crouch, GunnerBuilder.Prone
local THIGH_LEN, SHIN_LEN = LEGS.thigh, LEGS.shin
local HIP_REST, SHIN_REST = LEGS.hipRest, LEGS.shinRest

-- Placeholder get-in / get-out timings (seconds from PowerTime). No
-- cinematic yet: the server lays the pilot in at once.
GunnerPose.Board = {
	PetalsCloseStart = 0.1,
	PetalsCloseEnd = 0.9,
	PowerUp = 0.7,
	StandStart = 0.9,
	StandEnd = 3.0,
	Online = 3.1, -- controls handed over
}
GunnerPose.Exit = {
	DownEnd = 2.1, -- lying down
	PetalsOpenStart = 1.9,
	PetalsOpenEnd = 2.7,
	Unseat = 2.75, -- server unseats; the pilot's client puts the avatar down beside it
	Off = 3.0,
}

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Two-bone leg IK: hip -> ankle `v` (pelvis frame, studs) with the knee
-- pushed toward `pole`. Returns the thigh and shin rotations (pelvis frame;
-- -Y runs down each segment, X is the knee hinge axis).
function GunnerPose.legIK(v: Vector3, pole: Vector3): (CFrame, CFrame)
	local d = math.clamp(v.Magnitude, math.abs(THIGH_LEN - SHIN_LEN) + 1e-3, THIGH_LEN + SHIN_LEN - 1e-3)
	local dir = v.Unit
	local along = (THIGH_LEN * THIGH_LEN - SHIN_LEN * SHIN_LEN + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, THIGH_LEN * THIGH_LEN - along * along))
	local p = (pole - dir * pole:Dot(dir)).Unit
	local knee = dir * along + p * h
	local hinge = dir:Cross(p).Unit
	local thigh = CFrame.fromMatrix(Vector3.zero, hinge, -knee.Unit)
	local shin = CFrame.fromMatrix(Vector3.zero, hinge, -(dir * d - knee).Unit)
	return thigh, shin
end

local HIP_C0 = CFrame.Angles(HIP_REST, 0, 0)
local KNEE_C0 = CFrame.Angles(SHIN_REST - HIP_REST, 0, 0)
local ANKLE_C0 = CFrame.Angles(-SHIN_REST, 0, 0)

-- Hip / Knee / Ankle transforms reaching hip -> ankle `v` (pelvis frame,
-- studs) with the knee toward `pole`; the foot ends up with rotation `foot`
-- (pelvis frame).
function GunnerPose.leg(v: Vector3, pole: Vector3, foot: CFrame): (CFrame, CFrame, CFrame)
	local thigh, shin = GunnerPose.legIK(v, pole)
	return HIP_C0:Inverse() * thigh, (thigh * KNEE_C0):Inverse() * shin, (shin * ANKLE_C0):Inverse() * foot
end

-- model-space rest points (studs)
local PELVIS = GunnerBuilder.restFrame("Waist").Position
local HIP: { [string]: Vector3 } = {}
local ANKLE: { [string]: Vector3 } = {}
local PRONE_ANKLE: { [string]: Vector3 } = {}
local PRONE_ROT = CFrame.Angles(PR.pitch, 0, 0)
local PRONE_FOOT = PRONE_ROT * CFrame.Angles(PR.foot, 0, 0) -- foot rotation, model space
for _, n in { "Right", "Left" } do
	HIP[n] = GunnerBuilder.restFrame(n .. "UpperLeg").Position
	ANKLE[n] = GunnerBuilder.restFrame(n .. "Foot").Position
	PRONE_ANKLE[n] = PELVIS + PR.pelvis * S + (PRONE_ROT * (HIP[n] - PELVIS + PR.legs * S)) :: Vector3
end

-- Upper body keyframes (arm bones are rolled out at rest; shoulder pitch +
-- swings the arm forward, elbow + bends the forearm forward / up).
GunnerPose.Arms = {
	crouch = {
		Right = { shoulder = CFrame.Angles(1.25, 0, -0.1), elbow = 0.15 },
		Left = { shoulder = CFrame.Angles(1.15, 0, 0.12), elbow = 0.05 },
		shield = CFrame.Angles(0.5, 0, 0), -- tipped up clear of the ground
	},
	prone = {
		Right = { shoulder = CFrame.Angles(math.pi / 2, 0, -0.12), elbow = 1.4 },
		Left = { shoulder = CFrame.Angles(math.pi / 2, 0, 0.12), elbow = 1.4 },
		-- laid flat on the ground beside the forearm: level, turned on its face, out a little
		shield = CFrame.new(-0.7 * GunnerBuilder.Scale, 0, 0) * CFrame.Angles(0.3, 0, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0.02 * GunnerBuilder.Scale, 0, 0),
	},
}

-- Joint transforms of the powered-down pose, blended by k (0 standing .. 1
-- lying face down). Also used backwards (standing up).
function GunnerPose.offPose(k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local a = smooth(k / 0.5) -- crouch
	local b = smooth((k - 0.5) / 0.5) -- lie down
	local pose: { [string]: CFrame } = {}
	local off = (CR.pelvis * a):Lerp(PR.pelvis, b) * S
	local pitch = lerp(CR.pitch * a, PR.pitch, b)
	local rot = CFrame.Angles(pitch, 0, 0)
	pose.Root = CFrame.new(off) * rot
	local out = lerp(CR.kneeOut * a, 0, b)
	local foot = rot:Inverse() * CFrame.identity:Lerp(PRONE_FOOT, b)
	for _, sd in { { "Right", 1 }, { "Left", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local hip = PELVIS + off + (rot * (HIP[n] - PELVIS)) :: Vector3
		-- feet stay planted while crouching, then slide back (lifted a little) as it lies down
		local target = ANKLE[n]:Lerp(PRONE_ANKLE[n], b) + Vector3.new(0, 0.6 * S * math.sin(math.pi * b), 0)
		local v = rot:Inverse() * (target - hip)
		local pole = Vector3.new(s * math.sin(out), 0, -math.cos(out))
		pose[n .. "Hip"], pose[n .. "Knee"], pose[n .. "Ankle"] = GunnerPose.leg(v, pole, foot)
	end
	pose.Waist = CFrame.Angles(lerp(CR.waist * a, PR.waist, b), 0, 0)
	pose.Neck = CFrame.Angles(lerp(CR.neck * a, PR.neck, b), 0, 0)
	pose.CannonPitch = CFrame.Angles(lerp(CR.cannon * a, PR.cannon, b), 0, 0)
	local c, p = GunnerPose.Arms.crouch, GunnerPose.Arms.prone
	for _, n in { "Right", "Left" } do
		local ca, pa = (c :: any)[n], (p :: any)[n]
		pose[n .. "Shoulder"] = CFrame.identity:Lerp(ca.shoulder, a):Lerp(pa.shoulder, b)
		pose[n .. "Elbow"] = CFrame.Angles(lerp(ca.elbow * a, pa.elbow, b), 0, 0)
	end
	pose.ShieldMount = CFrame.identity:Lerp(c.shield, a):Lerp(p.shield, b)
	return pose
end

-- Opens the flower hatch by h (0 shut .. 1 open); petal i lags a little
-- behind petal i - 1, so they ripple open (and shut) around the bud.
local PETAL_LAG = 0.06
local PETAL_SPAN = 1 - PETAL_LAG * (#GunnerBuilder.Petals - 1)
function GunnerPose.setPetals(motors: { [string]: Motor6D }, h: number)
	for i, p in GunnerBuilder.Petals do
		local m = motors[p.name .. "Hinge"]
		if m then
			local t = smooth((h - (i - 1) * PETAL_LAG) / PETAL_SPAN)
			m.Transform = CFrame.Angles(p.open * t, 0, 0)
		end
	end
end

local function stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- Targets for the mech's current power state: off (0 standing .. 1 lying
-- down), petals (0 shut .. 1 open) and light level. Timed states return
-- exact values (last result true); steady states are eased toward.
function GunnerPose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = stateTime(model)
	local B, X = GunnerPose.Board, GunnerPose.Exit
	if state == "Boarding" then
		local off = 1 - (t - B.StandStart) / (B.StandEnd - B.StandStart)
		local petals = 1 - (t - B.PetalsCloseStart) / (B.PetalsCloseEnd - B.PetalsCloseStart)
		return math.clamp(off, 0, 1), math.clamp(petals, 0, 1), smooth((t - B.PowerUp) / 0.4), true
	elseif state == "PoweringDown" then
		local petals = (t - X.PetalsOpenStart) / (X.PetalsOpenEnd - X.PetalsOpenStart)
		return math.clamp(t / X.DownEnd, 0, 1), math.clamp(petals, 0, 1), 1 - smooth(t / 0.5), true
	elseif state == "Off" then
		return 1, 1, 0, false
	end
	return 0, 0, 1, false
end

-- Sets the off pose and the petals (no walk cycle).
function GunnerPose.applyStatic(motors: { [string]: Motor6D }, off: number, petals: number)
	for name, cf in GunnerPose.offPose(off) do
		local m = motors[name]
		if m then
			m.Transform = cf
		end
	end
	GunnerPose.setPetals(motors, petals)
end

-- The full powered-down pose: lying face down, flower open.
function GunnerPose.applyOff(motors: { [string]: Motor6D })
	GunnerPose.applyStatic(motors, 1, 1)
end

return GunnerPose
