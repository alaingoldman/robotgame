--!strict
-- Pose math for the PLD-02 (Mech2Builder), shared by clients and the server.
-- Same scheme as TitanPose: poses map motor name -> `rel`, the child's
-- rotation relative to its parent in MODEL axes (plus a translation for
-- "Root"), converted per motor (the arm bones carry their 17 deg rest roll),
-- so Angles(a, 0, 0) is always "pitch about model X, positive = lower end
-- forward".
--
--   Mech2Pose.rig(motors)          rest data measured from the motors (cached)
--   Mech2Pose.apply(rig, pose)     writes a pose to the Transforms
--   Mech2Pose.legIK(rig, side, ankleTarget, pelvisRel, yaw, footPitch, pose, lateral?)
--   Mech2Pose.kneel(rig, k)        the powered-down one-knee kneel, 0..1
--   Mech2Pose.setHatch(motors, h)  chest hatch 0 shut .. 1 open
--   Mech2Pose.powerTargets(model)  kneel / hatch / power from PowerState
--   applyStatic / applyOff         server mirror and edit-mode preview

local Mech2Config = require(script.Parent.Mech2Config)

local Mech2Pose = {}

Mech2Pose.Board = Mech2Config.Board
Mech2Pose.Exit = Mech2Config.Exit

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
Mech2Pose.smooth = smooth

local function curve(k: number, a: number, b: number): number
	return smooth((k - a) / (b - a))
end
Mech2Pose.curve = curve

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

function Mech2Pose.rig(motors: { [string]: Motor6D }): Rig?
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
	local ground = -Mech2Config.RootHeight
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

-- TASSETS: each side's skirt plates (tasset_R / tasset_L meshes, hinged over
-- the hip ball at the top of the side plate) follow part of that thigh's
-- swing, clamped so the back plate never reaches the hip housing / core.
local TASSET_FOLLOW = 0.45
local TASSET_MAX = 0.22

function Mech2Pose.apply(rig: Rig, pose: { [string]: CFrame })
	for _, side in { "Right", "Left" } do
		local hip = pose[side .. "Hip"]
		if hip and not pose[side .. "TassetJoint"] then
			local rx, _, rz = hip:ToEulerAnglesXYZ()
			pose[side .. "TassetJoint"] = CFrame.Angles(math.clamp(rx * TASSET_FOLLOW, -TASSET_MAX, TASSET_MAX), 0, math.clamp(rz * 0.3, -0.08, 0.08))
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
function Mech2Pose.legIK(rig: Rig, side: string, ankle: Vector3, pelvisRel: CFrame, yaw: number, foot: number, pose: { [string]: CFrame }, lateral: boolean?)
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
-- "Taking a knee", the BRZ-01's parked pose (TitanPose.kneel) at the PLD-02's
-- size: right knee down with the shin lying back to the flat foot, left foot
-- planted forward and turned out, torso low and a little forward (the open
-- chest hatch faces the pilot), head bowed, left forearm across the raised
-- left knee, right fist by the right knee. Run backwards it stands up.

local K = Mech2Config.Kneel

local function kneelDrop(rig: Rig): Vector3
	local leg = rig.legs.Right
	if not leg then
		return Vector3.new(0, -3, 0)
	end
	local ground = -Mech2Config.RootHeight
	local hipY = ground + K.KneeClear + leg.l1 * math.cos(K.ThighLean)
	return Vector3.new(0, hipY - leg.hip.Y, K.PelvisBack)
end

function Mech2Pose.kneel(rig: Rig, k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local pose: { [string]: CFrame } = {}
	local drop = kneelDrop(rig)
	local root = CFrame.new(Vector3.new(0, drop.Y * smooth(k), drop.Z * curve(k, 0, 0.7)))
	pose.Root = root
	local ground = -Mech2Config.RootHeight
	-- left foot steps forward first
	local L = rig.legs.Left
	if L then
		local u = curve(k, 0, 0.45)
		local target = Vector3.new(L.ankle.X - K.LeftOut, ground + L.ankleHeight, L.hip.Z + drop.Z - K.LeftForward)
		local a = L.ankle:Lerp(target, u) + Vector3.new(0, K.StepLift * math.sin(math.pi * u), 0)
		Mech2Pose.legIK(rig, "Left", a, root, K.LeftYaw * u, 0, pose)
	end
	-- right foot slides back as the knee goes down to the floor
	local R = rig.legs.Right
	if R then
		local u = curve(k, 0.2, 0.85)
		local kneeY = ground + K.KneeClear
		local footY = ground + R.ankleHeight + K.RightFootLift
		local back = math.sqrt(math.max(0, R.l2 * R.l2 - (footY - kneeY) ^ 2))
		local kneeZ = R.hip.Z + drop.Z - R.l1 * math.sin(K.ThighLean)
		local target = Vector3.new(R.ankle.X, footY, kneeZ + back * 0.97)
		local a = R.ankle:Lerp(target, u) + Vector3.new(0, K.StepLift * 0.6 * math.sin(math.pi * u), 0)
		Mech2Pose.legIK(rig, "Right", a, root, K.RightYaw * u, K.RightFootPitch * u, pose)
	end
	local a = curve(k, 0.3, 1)
	pose.Waist = CFrame.Angles(-K.Lean * curve(k, 0.15, 1), 0, 0)
	pose.Neck = CFrame.Angles(K.Neck * a, 0.12 * a, 0)
	-- left forearm across the raised knee, right fist down by the right knee
	pose.LeftShoulder = CFrame.Angles(K.LeftShoulder * a, 0, 0.08 * a)
	pose.LeftElbow = CFrame.Angles(K.LeftElbow * a, 0, 0)
	pose.LeftWrist = CFrame.Angles(0.2 * a, 0, 0)
	pose.RightShoulder = CFrame.Angles(K.RightShoulder * a, 0, -0.04 * a)
	pose.RightElbow = CFrame.Angles(K.RightElbow * a, 0, 0)
	pose.RightWrist = CFrame.Angles(0.25 * a, 0, 0)
	pose.LeftPauldronJoint = CFrame.Angles(K.LeftShoulder * 0.35 * a, 0, 0)
	pose.RightPauldronJoint = CFrame.Angles(K.RightShoulder * 0.35 * a, 0, 0)
	return pose
end
Mech2Pose.crouch = Mech2Pose.kneel -- older name

-- ===== IRON MAN unfold ======================================================
local U = Mech2Config.Unfold

local function backOut(x: number): number
	x = math.clamp(x, 0, 1)
	local c1 = U.Overshoot
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- One part's opening (0 shut .. ~1 open) for the whole chest's opening h,
-- inside its window; opening overshoots a little, closing eases shut.
function Mech2Pose.part(h: number, window: { number }, closing: boolean?): number
	local u = math.clamp((h - window[1]) / (window[2] - window[1]), 0, 1)
	return if closing then smooth(u) else backOut(u)
end

-- The pauldrons lift and roll out while the chest is open (added on top of
-- the pose's own pauldron follow; call before apply).
function Mech2Pose.addUnfold(pose: { [string]: CFrame }, h: number, closing: boolean?)
	local p = Mech2Pose.part(h, U.Pauldrons, closing)
	if p <= 1e-4 then
		return
	end
	for _, side in { "Right", "Left" } do
		local sx = if side == "Right" then 1 else -1
		local key = side .. "PauldronJoint"
		pose[key] = (pose[key] or CFrame.identity) * CFrame.Angles(U.PauldronLift * p, 0, sx * U.PauldronRoll * p)
	end
end

-- Opens the chest by h (0 shut .. 1 open): the lower plate drops on its
-- bottom hinge, then the doors swing out on their outer hinges.
function Mech2Pose.setHatch(motors: { [string]: Motor6D }, h: number, closing: boolean?)
	local hinge = motors.HatchHinge
	if hinge then
		hinge.Transform = CFrame.Angles(Mech2Config.HatchOpen * Mech2Pose.part(h, U.Hatch, closing), 0, 0)
	end
	local d = Mech2Pose.part(h, U.Doors, closing)
	local r, l = motors.RightDoorHinge, motors.LeftDoorHinge
	if r then
		r.Transform = CFrame.Angles(0, -Mech2Config.DoorOpen * d, 0)
	end
	if l then
		l.Transform = CFrame.Angles(0, Mech2Config.DoorOpen * d, 0)
	end
end

function Mech2Pose.stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- kneel (0 standing .. 1 knelt), hatch (0 shut .. 1 open), power (light
-- level) for the current power state; last = exact (timed) values.
function Mech2Pose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = Mech2Pose.stateTime(model)
	local B, X = Mech2Pose.Board, Mech2Pose.Exit
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

function Mech2Pose.applyStatic(motors: { [string]: Motor6D }, kneel: number, hatch: number)
	local rig = Mech2Pose.rig(motors)
	if not rig then
		return
	end
	local pose = if kneel <= 1e-4 then {} else Mech2Pose.kneel(rig, kneel)
	Mech2Pose.addUnfold(pose, hatch)
	for name, j in rig.joints do
		if not pose[name] and not string.find(name, "Hinge$") then
			j.motor.Transform = CFrame.identity
		end
	end
	Mech2Pose.apply(rig, pose)
	Mech2Pose.setHatch(motors, hatch)
end

function Mech2Pose.applyOff(motors: { [string]: Motor6D })
	Mech2Pose.applyStatic(motors, 1, 1)
end

return Mech2Pose
