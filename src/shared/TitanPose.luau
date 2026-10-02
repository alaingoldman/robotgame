--!strict
-- Pose math for the BRZ-01 Titan (TitanBuilder), shared by clients and the
-- server.
--
-- The assembled rig's bones carry arbitrary rest rotations (leaning boots,
-- splayed arms, curled fingers), so poses are written in MODEL axes and
-- converted per motor: a pose maps motor name -> `rel`, the child's rotation
-- relative to its parent expressed in model axes (as if the parent were at
-- rest; plus a translation for "Root", the pelvis offset). For a motor with
-- joint frame F (Part0 rest * C0) the Transform is F.Rotation^-1 * rel *
-- F.Rotation, so Angles(a, 0, 0) is always "pitch about model X" (positive =
-- lower end forward, toward -Z) whatever the bone's own rest frame is.
--
--   TitanPose.rig(motors)         rest data measured from the motors (cached)
--   TitanPose.apply(motors, pose) writes a pose (rel table) to the Transforms
--   TitanPose.legIK(rig, side, ankleTarget, pelvisRel, yaw, footPitch, pose, lateral?)
--   TitanPose.kneel(rig, k)       the powered-down one-knee kneel, 0..1
--   TitanPose.setHatch(motors, h) chest hatch 0 shut .. 1 open
--   TitanPose.powerTargets(model) kneel / hatch / light from PowerState
--   applyStatic / applyOff        server mirror and edit-mode preview

local TitanConfig = require(script.Parent.TitanConfig)

local TitanPose = {}

TitanPose.Board = TitanConfig.Board
TitanPose.Exit = TitanConfig.Exit

local HATCH_OPEN = -1.72 -- radians about the hinge: the chest front folds down and forward

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
TitanPose.smooth = smooth

local function curve(k: number, a: number, b: number): number
	return smooth((k - a) / (b - a))
end
TitanPose.curve = curve

local function pitchOf(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

-- ===== rig rest data =======================================================

export type Joint = { motor: Motor6D, f: CFrame, fr: CFrame, fri: CFrame }
export type Leg = {
	hip: Vector3, -- joint positions at rest (root space, studs)
	knee: Vector3,
	ankle: Vector3,
	l1: number, -- thigh / shin lengths in the leg plane (y, z)
	l2: number,
	t0: number, -- rest pitches of thigh / shin
	s0: number,
	ankleHeight: number, -- ankle above the ground at rest (foot flat)
}
export type Rig = { joints: { [string]: Joint }, legs: { [string]: Leg }, pelvis: Vector3 }

local rigCache: { [Motor6D]: Rig } = setmetatable({}, { __mode = "k" }) :: any

-- Rest frames from the motor tree (C0 / C1 only, so it works mid-animation).
function TitanPose.rig(motors: { [string]: Motor6D }): Rig?
	local rootMotor = motors.Root
	if not rootMotor then
		return nil
	end
	local cached = rigCache[rootMotor]
	if cached then
		return cached
	end
	local byPart1: { [BasePart]: Motor6D } = {}
	for _, m in motors do
		if m.Part1 then
			byPart1[m.Part1] = m
		end
	end
	local rootPart = rootMotor.Part0
	local rest: { [BasePart]: CFrame } = {}
	local function restOf(part: BasePart?): CFrame
		if not part or part == rootPart then
			return CFrame.identity
		end
		local r = rest[part]
		if r then
			return r
		end
		local m = byPart1[part]
		if not m then
			return CFrame.identity
		end
		r = restOf(m.Part0) * m.C0 * m.C1:Inverse()
		rest[part] = r
		return r
	end
	local joints: { [string]: Joint } = {}
	for name, m in motors do
		local f = restOf(m.Part0) * m.C0
		local fr = f.Rotation
		joints[name] = { motor = m, f = f, fr = fr, fri = fr:Inverse() }
	end
	local ground = -TitanConfig.RootHeight
	local legs: { [string]: Leg } = {}
	for _, n in { "Right", "Left" } do
		local hipJ, kneeJ, ankleJ = joints[n .. "Hip"], joints[n .. "Knee"], joints[n .. "Ankle"]
		if hipJ and kneeJ and ankleJ then
			local hip, knee, ankle = hipJ.f.Position, kneeJ.f.Position, ankleJ.f.Position
			local t, s = knee - hip, ankle - knee
			legs[n] = {
				hip = hip,
				knee = knee,
				ankle = ankle,
				l1 = Vector2.new(t.Y, t.Z).Magnitude,
				l2 = Vector2.new(s.Y, s.Z).Magnitude,
				t0 = pitchOf(t),
				s0 = pitchOf(s),
				ankleHeight = ankle.Y - ground,
			}
		end
	end
	local r: Rig = { joints = joints, legs = legs, pelvis = joints.Root.f.Position }
	rigCache[rootMotor] = r
	return r
end

-- Writes a pose (motor name -> rel CFrame, model axes) to the motors' Transforms.
function TitanPose.apply(rig: Rig, pose: { [string]: CFrame })
	for name, rel in pose do
		local j = rig.joints[name]
		if j then
			j.motor.Transform = j.fri * rel * j.fr
		end
	end
end

-- Two-bone IK for one leg. `ankle` = target ankle position (root space),
-- `pelvisRel` = the pose's Root rel (pelvis offset + rotation about its own
-- origin), `yaw` turns the leg plane out, `foot` = the foot's pitch relative
-- to the ground (0 = flat, positive = toe up). Writes Hip / Knee / Ankle.
function TitanPose.legIK(rig: Rig, side: string, ankle: Vector3, pelvisRel: CFrame, yaw: number, foot: number, pose: { [string]: CFrame }, lateral: boolean?)
	local leg = rig.legs[side]
	if not leg then
		return
	end
	local pr = pelvisRel.Rotation
	-- hip position with the pelvis moved / turned about its origin
	local hipWorld = rig.pelvis + pelvisRel.Position + (pr * (leg.hip - rig.pelvis)) :: Vector3
	local v = (pr:Inverse() * (ankle - hipWorld)) :: Vector3 -- pelvis frame
	v = (CFrame.Angles(0, -yaw, 0) * v) :: Vector3
	-- `lateral`: a hip roll takes the sideways part (pelvis sway / roll over
	-- the planted foot) so a planted foot doesn't slip sideways; the planar
	-- IK does the rest (the kneel poses stay planar)
	local roll = 0
	if lateral then
		local rest = leg.ankle - leg.hip
		roll = math.atan2(v.X, -v.Y) - math.atan2(rest.X, -rest.Y)
		v = (CFrame.Angles(0, 0, -roll) * v) :: Vector3
	end
	local p = Vector2.new(v.Y, v.Z)
	local l1, l2 = leg.l1, leg.l2
	local d = math.clamp(p.Magnitude, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local spread = math.acos(math.clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1))
	local thigh = math.atan2(-v.Z, -v.Y) + spread
	local kneeY, kneeZ = -l1 * math.cos(thigh), -l1 * math.sin(thigh)
	local shin = math.atan2(-(v.Z - kneeZ), -(v.Y - kneeY))
	local yawCF = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, roll)
	local aThigh = yawCF * CFrame.Angles(thigh - leg.t0, 0, 0)
	local aShin = yawCF * CFrame.Angles(shin - leg.s0, 0, 0)
	-- foot: level with the ground (undo the pelvis rotation), then pitched
	local aFoot = pr:Inverse() * CFrame.Angles(0, yaw, 0) * CFrame.Angles(foot, 0, 0)
	pose[side .. "Hip"] = aThigh
	pose[side .. "Knee"] = aThigh:Inverse() * aShin
	pose[side .. "Ankle"] = aShin:Inverse() * aFoot
end

-- Rest ankle position of a leg (root space) moved by `offset`.
function TitanPose.ankleRest(rig: Rig, side: string): Vector3
	local leg = rig.legs[side]
	return if leg then leg.ankle else Vector3.zero
end

-- ===== powered-down kneel ==================================================
-- "Taking a knee": right knee on the ground with the shin lying back to the
-- flat foot, left foot planted forward and turned out, torso upright and a
-- little forward, head bowed, left forearm across the raised left knee,
-- right fist resting by the right knee, fingers relaxed.

local KNEE_CLEAR = 1.35 -- right knee joint above the ground (the knee disc rests on it)
local LEFT_FORWARD = 5.8 -- left ankle ahead of its hip (studs)
local LEFT_YAW = 0.28
local RIGHT_YAW = -0.08
local KNEEL_WAIST = 0.1 -- torso pitch (positive leans forward; Waist rel uses -)
local KNEEL_NECK = -0.32
local STEP_LIFT = 2.4

local function fingerCurl(pose: { [string]: CFrame }, n: string, s: number, c: number)
	local rot = CFrame.Angles(0, 0, -s * c)
	for i = 1, 4 do
		pose[n .. "Finger" .. i .. "Knuckle"] = rot
		pose[n .. "Finger" .. i .. "Mid"] = rot
		pose[n .. "Finger" .. i .. "Tip"] = rot
	end
	pose[n .. "ThumbTip"] = CFrame.Angles(0, 0, -s * c * 0.6)
end
TitanPose.fingerCurl = fingerCurl

-- Pelvis drop of the full kneel (studs, model axes), from the leg lengths:
-- the right thigh hangs nearly straight down to a knee resting on the ground.
local function kneelDrop(rig: Rig): Vector3
	local leg = rig.legs.Right
	if not leg then
		return Vector3.new(0, -7, 0)
	end
	local ground = -TitanConfig.RootHeight
	local hipY = ground + KNEE_CLEAR + leg.l1 * math.cos(0.12)
	return Vector3.new(0, hipY - leg.hip.Y, 0.6)
end

-- The kneel blended by k (0 standing .. 1 knelt). Also run backwards
-- (standing up). Feet step with a lift; legs solved by IK so they land.
function TitanPose.kneel(rig: Rig, k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local pose: { [string]: CFrame } = {}
	local drop = kneelDrop(rig)
	local root = CFrame.new(Vector3.new(0, drop.Y * smooth(k), drop.Z * curve(k, 0, 0.7)))
	pose.Root = root
	local ground = -TitanConfig.RootHeight
	-- left foot steps forward first
	local L = rig.legs.Left
	if L then
		local u = curve(k, 0, 0.45)
		local target = Vector3.new(L.ankle.X - 0.6, ground + L.ankleHeight, L.hip.Z + drop.Z - LEFT_FORWARD)
		local a = L.ankle:Lerp(target, u) + Vector3.new(0, STEP_LIFT * math.sin(math.pi * u), 0)
		TitanPose.legIK(rig, "Left", a, root, LEFT_YAW * u, 0, pose)
	end
	-- right foot slides back as the knee goes down to the floor
	local R = rig.legs.Right
	if R then
		local u = curve(k, 0.2, 0.85)
		local hipY = R.hip.Y + drop.Y
		local kneeY = ground + KNEE_CLEAR
		local footY = ground + R.ankleHeight
		local back = math.sqrt(math.max(0, R.l2 * R.l2 - (footY - kneeY) ^ 2))
		local kneeZ = R.hip.Z + drop.Z - R.l1 * math.sin(0.12)
		local _ = hipY
		local target = Vector3.new(R.ankle.X, footY, kneeZ + back * 0.97)
		local a = R.ankle:Lerp(target, u) + Vector3.new(0, STEP_LIFT * 0.6 * math.sin(math.pi * u), 0)
		TitanPose.legIK(rig, "Right", a, root, RIGHT_YAW * u, 0, pose)
	end
	local a = curve(k, 0.3, 1)
	pose.Waist = CFrame.Angles(-KNEEL_WAIST * curve(k, 0.15, 1), 0, 0)
	pose.Neck = CFrame.Angles(KNEEL_NECK * a, 0.12 * a, 0)
	-- left forearm across the raised knee, right fist down by the right knee
	pose.LeftShoulder = CFrame.Angles(0.15 * a, 0, 0.1 * a)
	pose.LeftElbow = CFrame.Angles(0.9 * a, 0, 0)
	pose.LeftWrist = CFrame.Angles(0.2 * a, 0, 0)
	pose.RightShoulder = CFrame.Angles(0.25 * a, 0, -0.05 * a)
	pose.RightElbow = CFrame.Angles(0.3 * a, 0, 0)
	pose.RightWrist = CFrame.Angles(0.25 * a, 0, 0)
	fingerCurl(pose, "Left", -1, 0.25 * a)
	fingerCurl(pose, "Right", 1, 0.55 * a)
	return pose
end

-- Opens the chest hatch by h (0 shut .. 1 open).
function TitanPose.setHatch(motors: { [string]: Motor6D }, h: number)
	local hinge = motors.HatchHinge
	if hinge then
		hinge.Transform = CFrame.Angles(HATCH_OPEN * smooth(h), 0, 0)
	end
end

function TitanPose.stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- Targets for the mech's current power state: kneel (0 standing .. 1 knelt),
-- hatch (0 shut .. 1 open) and light level. Timed states return exact values
-- (last result true); steady states are eased toward.
function TitanPose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = TitanPose.stateTime(model)
	local B, X = TitanPose.Board, TitanPose.Exit
	if state == "Boarding" then
		local kneel = 1 - smooth((t - B.StandStart) / (B.StandEnd - B.StandStart))
		local hatch = 1 - smooth((t - B.HatchCloseStart) / (B.HatchCloseEnd - B.HatchCloseStart))
		return kneel, hatch, smooth((t - B.PowerUp) / 0.4), true
	elseif state == "PoweringDown" then
		local hatch = smooth((t - X.HatchOpenStart) / (X.HatchOpenEnd - X.HatchOpenStart))
		return smooth(t / X.KneelEnd), hatch, 1 - smooth(t / 0.6), true
	elseif state == "Off" then
		return 1, 1, 0, false
	end
	return 0, 0, 1, false
end

-- Sets the kneel and the hatch (no walk cycle). Standing = all identity.
function TitanPose.applyStatic(motors: { [string]: Motor6D }, kneel: number, hatch: number)
	local rig = TitanPose.rig(motors)
	if not rig then
		return
	end
	if kneel <= 1e-4 then
		for name, j in rig.joints do
			if name ~= "HatchHinge" then
				j.motor.Transform = CFrame.identity
			end
		end
	else
		TitanPose.apply(rig, TitanPose.kneel(rig, kneel))
	end
	TitanPose.setHatch(motors, hatch)
end

-- The full powered-down pose: knelt, hatch open.
function TitanPose.applyOff(motors: { [string]: Motor6D })
	TitanPose.applyStatic(motors, 1, 1)
end

return TitanPose
