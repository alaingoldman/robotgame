--!strict
-- Pose math for the CRM-01 "Crimson" (CrimsonBuilder), shared by clients and
-- the server. Same scheme as Mech2Pose / TitanPose: a pose maps motor name ->
-- `rel`, the child's rotation relative to its parent in MODEL axes (plus a
-- translation for "Root"), so Angles(a, 0, 0) is "pitch about model X,
-- positive = lower end forward". (The Crimson's bones are all axis aligned,
-- so the conversion is the identity, but the scheme keeps it general.)
--
--   CrimsonPose.rig(motors)          rest data measured from the motors (cached)
--   CrimsonPose.apply(rig, pose)     writes a pose to the Transforms
--   CrimsonPose.legIK(rig, side, ankleTarget, pelvisRel, yaw, footPitch, pose, lateral?)
--   CrimsonPose.kneel(rig, k)        the powered-down one-knee kneel, 0..1
--   CrimsonPose.setHatch(motors, h)  back pod hatch 0 shut .. 1 open
--   CrimsonPose.powerTargets(model)  kneel / hatch / power from PowerState
--   applyStatic / applyOff           server mirror and edit-mode preview

local CrimsonConfig = require(script.Parent.CrimsonConfig)

local CrimsonPose = {}

CrimsonPose.Board = CrimsonConfig.Board
CrimsonPose.Exit = CrimsonConfig.Exit

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
CrimsonPose.smooth = smooth

local function curve(k: number, a: number, b: number): number
	return smooth((k - a) / (b - a))
end
CrimsonPose.curve = curve

local function pitchOf(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

export type Joint = { motor: Motor6D, f: CFrame, fr: CFrame, fri: CFrame }
export type Leg = {
	hip: Vector3,
	knee: Vector3,
	ankle: Vector3,
	l1: number,
	l2: number,
	t0: number,
	s0: number,
	ankleHeight: number,
}
export type Rig = { joints: { [string]: Joint }, legs: { [string]: Leg }, pelvis: Vector3 }

local rigCache: { [Motor6D]: Rig } = setmetatable({}, { __mode = "k" }) :: any

function CrimsonPose.rig(motors: { [string]: Motor6D }): Rig?
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
	local ground = -CrimsonConfig.RootHeight
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
	if not joints.Root then
		return nil
	end
	local r: Rig = { joints = joints, legs = legs, pelvis = joints.Root.f.Position }
	rigCache[rootMotor] = r
	return r
end

-- The shoulder pads take part of their arm's swing (unless the pose sets
-- them), so they ride over the raised arm instead of the arm cutting in.
local PAD_FOLLOW = CrimsonConfig.Gait.PadFollow

function CrimsonPose.apply(rig: Rig, pose: { [string]: CFrame })
	for _, side in { "Right", "Left" } do
		local sh = pose[side .. "Shoulder"]
		if sh and not pose[side .. "PadJoint"] then
			local rx, _, rz = sh:ToEulerAnglesXYZ()
			pose[side .. "PadJoint"] = CFrame.Angles(rx * PAD_FOLLOW, 0, rz * 0.5)
		end
	end
	for name, rel in pose do
		local j = rig.joints[name]
		if j then
			j.motor.Transform = j.fri * rel * j.fr
		end
	end
end

-- Two-bone IK for one leg (see TitanPose.legIK). `ankle` = target ankle
-- (root space), `pelvisRel` = the pose's Root rel, `foot` = foot pitch
-- relative to the ground (0 flat, positive toe up). `lateral`: a hip roll
-- takes the sideways part so a planted foot doesn't slip sideways.
function CrimsonPose.legIK(rig: Rig, side: string, ankle: Vector3, pelvisRel: CFrame, yaw: number, foot: number, pose: { [string]: CFrame }, lateral: boolean?)
	local leg = rig.legs[side]
	if not leg then
		return
	end
	local pr = pelvisRel.Rotation
	local hipWorld = rig.pelvis + pelvisRel.Position + (pr * (leg.hip - rig.pelvis)) :: Vector3
	local v = (pr:Inverse() * (ankle - hipWorld)) :: Vector3
	v = (CFrame.Angles(0, -yaw, 0) * v) :: Vector3
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
	local aFoot = pr:Inverse() * CFrame.Angles(0, yaw, 0) * CFrame.Angles(foot, 0, 0)
	pose[side .. "Hip"] = aThigh
	pose[side .. "Knee"] = aThigh:Inverse() * aShin
	pose[side .. "Ankle"] = aShin:Inverse() * aFoot
end

-- ===== powered-down kneel ===================================================
-- "Taking a knee" like the BRZ-01 / PLD-02: right knee down with the shin
-- lying back to the foot, left foot planted forward and turned out, torso low
-- and a little forward (the back pod faces a pilot standing behind), head
-- bowed, the arms hanging with the blade tips resting on the floor.

local K = CrimsonConfig.Kneel

-- The knee joint sits at the FRONT of the knee (CrimsonConfig.Pivots), so
-- the knee vector from the hip leans forward at rest; `lean` turns it (the
-- whole thigh) further forward.
local function kneeRel(leg: Leg, lean: number): Vector3
	local v = leg.knee - leg.hip
	local c, s = math.cos(lean), math.sin(lean)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end

local function kneelDrop(rig: Rig): Vector3
	local leg = rig.legs.Right
	if not leg then
		return Vector3.new(0, -5, 0)
	end
	local ground = -CrimsonConfig.RootHeight
	local hipY = ground + K.KneeClear - kneeRel(leg, K.ThighLean).Y
	return Vector3.new(0, hipY - leg.hip.Y, K.PelvisBack)
end

function CrimsonPose.kneel(rig: Rig, k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local pose: { [string]: CFrame } = {}
	local drop = kneelDrop(rig)
	local root = CFrame.new(Vector3.new(0, drop.Y * smooth(k), drop.Z * curve(k, 0, 0.7)))
	pose.Root = root
	local ground = -CrimsonConfig.RootHeight
	local L = rig.legs.Left
	if L then
		local u = curve(k, 0, 0.45)
		local target = Vector3.new(L.ankle.X - K.LeftOut, ground + L.ankleHeight, L.hip.Z + drop.Z - K.LeftForward)
		local a = L.ankle:Lerp(target, u) + Vector3.new(0, K.StepLift * math.sin(math.pi * u), 0)
		CrimsonPose.legIK(rig, "Left", a, root, K.LeftYaw * u, 0, pose)
	end
	local R = rig.legs.Right
	if R then
		local u = curve(k, 0.2, 0.85)
		local kneeY = ground + K.KneeClear
		local footY = ground + R.ankleHeight + K.RightFootLift
		local back = math.sqrt(math.max(0, R.l2 * R.l2 - (footY - kneeY) ^ 2))
		local kneeZ = R.hip.Z + drop.Z + kneeRel(R, K.ThighLean).Z
		local target = Vector3.new(R.ankle.X, footY, kneeZ + back * 0.97)
		local a = R.ankle:Lerp(target, u) + Vector3.new(0, K.StepLift * 0.6 * math.sin(math.pi * u), 0)
		CrimsonPose.legIK(rig, "Right", a, root, K.RightYaw * u, K.RightFootPitch * u, pose)
	end
	local a = curve(k, 0.3, 1)
	pose.Waist = CFrame.Angles(-K.Lean * curve(k, 0.15, 1), 0, 0)
	pose.Neck = CFrame.Angles(K.Neck * a, 0.1 * a, 0)
	-- arms hang relaxed (big elbow bends show the cut caps), the blade tips rest on the floor
	pose.LeftShoulder = CFrame.Angles(K.LeftShoulder * a, 0, -K.LeftRoll * a)
	pose.LeftElbow = CFrame.Angles(K.LeftElbow * a, 0, 0)
	pose.LeftWrist = CFrame.Angles(K.LeftWrist * a, 0, 0)
	pose.RightShoulder = CFrame.Angles(K.RightShoulder * a, 0, K.RightRoll * a)
	pose.RightElbow = CFrame.Angles(K.RightElbow * a, 0, 0)
	pose.RightWrist = CFrame.Angles(K.RightWrist * a, 0, 0)
	-- the cleaver turns to a reverse grip: out beside the fist, then up along the forearm
	pose.CleaverGrip = CFrame.new(K.CleaverOut * curve(k, 0.25, 0.5), 0, 0) * CFrame.Angles(K.CleaverTurn * curve(k, 0.35, 0.95), 0, 0)
	return pose
end

-- ===== back hatch ===========================================================

-- Opens the pod hatch by h (0 shut .. 1 open); opening overshoots a little
-- and settles, closing slams.
local function backOut(x: number): number
	x = math.clamp(x, 0, 1)
	local c1 = 1.1
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

function CrimsonPose.setHatch(motors: { [string]: Motor6D }, h: number, closing: boolean?)
	local hinge = motors.HatchHinge
	if hinge then
		local u = if closing then h * h else backOut(h)
		hinge.Transform = CFrame.Angles(CrimsonConfig.Hatch.Open * u, 0, 0)
	end
end

function CrimsonPose.stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- kneel (0 standing .. 1 knelt), hatch (0 shut .. 1 open), power (light
-- level) for the current power state; last = exact (timed) values.
function CrimsonPose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = CrimsonPose.stateTime(model)
	local B, X = CrimsonPose.Board, CrimsonPose.Exit
	if state == "Boarding" then
		local kneel = 1 - smooth((t - B.StandStart) / (B.StandEnd - B.StandStart))
		local hatch = 1 - math.clamp((t - B.HatchCloseStart) / (B.HatchCloseEnd - B.HatchCloseStart), 0, 1)
		return kneel, hatch, smooth((t - B.PowerUp) / 0.35), true
	elseif state == "PoweringDown" then
		local hatch = math.clamp((t - X.HatchOpenStart) / (X.HatchOpenEnd - X.HatchOpenStart), 0, 1)
		return smooth(t / X.KneelEnd), hatch, 1 - smooth(t / 0.7), true
	elseif state == "Off" then
		return 1, 1, 0, false
	end
	return 0, 0, 1, false
end

function CrimsonPose.applyStatic(motors: { [string]: Motor6D }, kneel: number, hatch: number)
	local rig = CrimsonPose.rig(motors)
	if not rig then
		return
	end
	local pose = if kneel <= 1e-4 then {} else CrimsonPose.kneel(rig, kneel)
	for name, j in rig.joints do
		if not pose[name] and name ~= "HatchHinge" then
			j.motor.Transform = CFrame.identity
		end
	end
	CrimsonPose.apply(rig, pose)
	CrimsonPose.setHatch(motors, hatch)
end

function CrimsonPose.applyOff(motors: { [string]: Motor6D })
	CrimsonPose.applyStatic(motors, 1, 1)
end

return CrimsonPose
