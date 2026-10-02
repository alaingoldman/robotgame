--!strict
-- Pose math for the VK-01 (KnightBuilder), shared by clients and the server.
--
--   * kneel(k): the powered-down one-knee kneel as joint transforms, blended
--     by k (0 standing .. 1 knelt). The left foot steps forward and out, the
--     right foot steps back onto its toe while the body sinks, legs solved by
--     two-bone IK (legIK) so feet land exactly; torso leans a touch, head
--     bows, the left hand comes to rest on the raised knee, wings fold.
--   * setHatch(motors, h): chest hatch 0 shut .. 1 open (HatchHinge).
--   * powerTargets(model): kneel / hatch / light levels for the PowerState +
--     PowerTime (KnightPose.Board / Exit, the placeholder get-in timings).
--   * applyStatic / applyOff: the server mirror and the edit-mode preview.
--
-- Leg angles are bone pitches in the level pelvis frame: 0 = straight down,
-- positive = lower end forward (-Z). A motor's Transform is the bone's pitch
-- minus what its rest pose and parents already give it.

local KnightBuilder = require(script.Parent.KnightBuilder)

local KnightPose = {}

local S = KnightBuilder.Scale
local LEGS = KnightBuilder.Legs
local K = KnightBuilder.Kneel
local THIGH_LEN, SHIN_LEN = LEGS.thigh, LEGS.shin
local HIP_REST, SHIN_REST = LEGS.hipRest, LEGS.shinRest
local ANKLE_REST = LEGS.ankle
local STEP_LIFT = 1.4 * S -- feet lift clear as they step

-- Placeholder get-in / get-out timings (seconds from PowerTime). No
-- cinematic yet: the server seats the pilot at once.
KnightPose.Board = {
	HatchCloseStart = 0.1,
	HatchCloseEnd = 0.55,
	PowerUp = 0.5,
	StandStart = 0.55,
	StandEnd = 1.55,
	Online = 1.65, -- controls handed over
}
KnightPose.Exit = {
	KneelEnd = 1.1,
	HatchOpenStart = 0.95,
	HatchOpenEnd = 1.45,
	Unseat = 1.5, -- server unseats; the pilot's client puts the avatar down in front
	Off = 1.75,
}

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function curve(k: number, a: number, b: number): number
	return smooth((k - a) / (b - a))
end

local function pitchOf(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

-- Two-bone leg IK in the leg's plane (knee forward): hip -> ankle (y, z of
-- `v`, studs) -> thigh and shin bone pitches.
function KnightPose.legIK(v: Vector3): (number, number)
	local p = Vector3.new(0, v.Y, v.Z)
	local d = math.clamp(p.Magnitude, math.abs(THIGH_LEN - SHIN_LEN) + 1e-3, THIGH_LEN + SHIN_LEN - 1e-3)
	local spread = math.acos(math.clamp((THIGH_LEN * THIGH_LEN + d * d - SHIN_LEN * SHIN_LEN) / (2 * THIGH_LEN * d), -1, 1))
	local thigh = pitchOf(p) + spread
	local knee = Vector3.new(0, -THIGH_LEN * math.cos(thigh), -THIGH_LEN * math.sin(thigh))
	return thigh, pitchOf(p - knee)
end

local HIP_UNREST = CFrame.Angles(-HIP_REST, 0, 0)

-- Hip / Knee / Ankle transforms for a leg whose plane is turned out by
-- `yaw`, reaching hip -> ankle `v` (pelvis frame, studs), foot pitch `foot`.
function KnightPose.leg(v: Vector3, yaw: number, foot: number): (CFrame, CFrame, CFrame)
	local local_ = (CFrame.Angles(0, -yaw, 0) * v) :: Vector3
	local thigh, shin = KnightPose.legIK(local_)
	return HIP_UNREST * CFrame.Angles(0, yaw, 0) * CFrame.Angles(thigh, 0, 0),
		CFrame.Angles(shin - thigh - (SHIN_REST - HIP_REST), 0, 0),
		CFrame.Angles(foot - shin + SHIN_REST, 0, 0)
end

-- Left arm reaching the raised left knee: shoulder rotation + elbow, solved
-- once (coordinate descent) against the full kneel.
-- arm bones lean out at rest (roll); segments run down each bone's -Y
local ARM_REST = KnightBuilder.restFrame("LeftUpperArm")
local UPPER = Vector3.new(0, -(KnightBuilder.restFrame("LeftLowerArm").Position - ARM_REST.Position).Magnitude, 0)
local FORE = Vector3.new(0, -(KnightBuilder.restFrame("LeftHand").Position - KnightBuilder.restFrame("LeftLowerArm").Position).Magnitude, 0)
local PALM = Vector3.new(0, -0.5 * S, 0)
local TORSO_REST = KnightBuilder.restFrame("Torso")
local ARM_C0 = TORSO_REST.Rotation:ToObjectSpace(ARM_REST.Rotation) -- shoulder rest rotation in the torso frame
local function armFK(rx: number, ry: number, rz: number, e: number): Vector3
	local r = ARM_C0 * CFrame.Angles(rx, ry, rz)
	return (r * (UPPER + (CFrame.Angles(e, 0, 0) * (FORE + PALM)) :: Vector3)) :: Vector3
end
local leftArm: { number }
do
	-- the kneeling torso frame and the knee cap in model space (studs)
	local torso = CFrame.new(TORSO_REST.Position + K.drop) * CFrame.Angles(K.waist, 0, 0)
	local hip = KnightBuilder.restFrame("LeftUpperLeg").Position + K.drop
	local cap = hip + K.leftKnee + (CFrame.Angles(0, K.leftYaw, 0) * Vector3.new(0, 0.7 * S, -0.9 * S)) :: Vector3
	local shoulder = TORSO_REST:PointToObjectSpace(ARM_REST.Position)
	local target = torso:PointToObjectSpace(cap) - shoulder
	local x = { 0.9, 0, 0.1, 0.6 }
	local function cost(): number
		local d = armFK(x[1], x[2], x[3], x[4]) - target
		return d:Dot(d) + 0.5 * x[2] * x[2] + (if x[4] < 0 then 10 * x[4] * x[4] else 0)
	end
	local step = 0.3
	local best = cost()
	for _ = 1, 400 do
		local improved = false
		for i = 1, 4 do
			for _, dir in { 1, -1 } do
				local old = x[i]
				x[i] = old + dir * step
				local c = cost()
				if c < best then
					best, improved = c, true
				else
					x[i] = old
				end
			end
		end
		if not improved then
			step *= 0.5
			if step < 1e-4 then
				break
			end
		end
	end
	leftArm = x
end
KnightPose.LeftArm = { shoulder = CFrame.Angles(leftArm[1], leftArm[2], leftArm[3]), elbow = leftArm[4], wrist = CFrame.Angles(0.35, 0, 0.3) }
KnightPose.RightArm = { shoulder = CFrame.Angles(0.12, 0, 0.02), elbow = 0.25 }
KnightPose.WingFold = 0.22 -- wings swing in and down when folded (radians)

-- Joint transforms of the kneel, blended by k (0 standing .. 1 knelt). Also
-- used backwards (standing up).
function KnightPose.kneel(k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local drop = K.drop
	local hip = Vector3.new(0, drop.Y * smooth(k), drop.Z * curve(k, 0, 0.75))
	local pose: { [string]: CFrame } = {}
	-- left foot: steps forward and out early
	local ul = curve(k, 0, 0.45)
	local leftAnkle = ANKLE_REST:Lerp(drop + K.leftAnkle, ul) + Vector3.new(0, STEP_LIFT * math.sin(math.pi * ul), 0)
	pose.LeftHip, pose.LeftKnee, pose.LeftAnkle = KnightPose.leg(leftAnkle - hip, K.leftYaw * ul, 0)
	-- right foot: steps back, rolls onto its toe as the knee goes down
	local ur = curve(k, 0.2, 0.85)
	local rightAnkle = ANKLE_REST:Lerp(drop + K.rightAnkle, ur) + Vector3.new(0, STEP_LIFT * math.sin(math.pi * ur), 0)
	pose.RightHip, pose.RightKnee, pose.RightAnkle = KnightPose.leg(rightAnkle - hip, 0, K.foot * smooth(ur))
	pose.Root = CFrame.new(hip)
	pose.Waist = CFrame.Angles(K.waist * curve(k, 0.2, 1), 0, 0)
	local a = curve(k, 0.35, 1)
	pose.Neck = CFrame.Angles(K.neck * a, 0, 0)
	local l, r = KnightPose.LeftArm, KnightPose.RightArm
	pose.LeftShoulder = CFrame.Angles(0, 0, -0.04):Lerp(l.shoulder, a)
	pose.LeftElbow = CFrame.Angles(l.elbow * a, 0, 0)
	pose.LeftWrist = CFrame.identity:Lerp(l.wrist, a)
	pose.RightShoulder = CFrame.Angles(0, 0, 0.04):Lerp(r.shoulder, a)
	pose.RightElbow = CFrame.Angles(r.elbow * a, 0, 0)
	local w = KnightPose.WingFold * curve(k, 0.3, 1)
	pose.WingLeftMount = CFrame.Angles(-w * 0.6, 0, -w)
	pose.WingRightMount = CFrame.Angles(-w * 0.6, 0, w)
	return pose
end

-- Opens the chest hatch by h (0 shut .. 1 open).
function KnightPose.setHatch(motors: { [string]: Motor6D }, h: number)
	local hinge = motors.HatchHinge
	if hinge then
		hinge.Transform = CFrame.Angles(K.hatchAngle * math.clamp(h, 0, 1), 0, 0)
	end
end

local function stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- Targets for the mech's current power state: kneel (0 standing .. 1 knelt),
-- hatch (0 shut .. 1 open) and light level. Timed states return exact values
-- (last result true); steady states are eased toward.
function KnightPose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = stateTime(model)
	local B, X = KnightPose.Board, KnightPose.Exit
	if state == "Boarding" then
		local kneel = 1 - smooth((t - B.StandStart) / (B.StandEnd - B.StandStart))
		local hatch = 1 - smooth((t - B.HatchCloseStart) / (B.HatchCloseEnd - B.HatchCloseStart))
		return kneel, hatch, smooth((t - B.PowerUp) / 0.4), true
	elseif state == "PoweringDown" then
		local hatch = smooth((t - X.HatchOpenStart) / (X.HatchOpenEnd - X.HatchOpenStart))
		return smooth(t / X.KneelEnd), hatch, 1 - smooth(t / 0.5), true
	elseif state == "Off" then
		return 1, 1, 0, false
	end
	return 0, 0, 1, false
end

-- Sets the kneel and the hatch (no walk cycle).
function KnightPose.applyStatic(motors: { [string]: Motor6D }, kneel: number, hatch: number)
	for name, cf in KnightPose.kneel(kneel) do
		local m = motors[name]
		if m then
			m.Transform = cf
		end
	end
	KnightPose.setHatch(motors, hatch)
end

-- The full powered-down pose: knelt, hatch open.
function KnightPose.applyOff(motors: { [string]: Motor6D })
	KnightPose.applyStatic(motors, 1, 1)
end

return KnightPose
