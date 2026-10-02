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
--   Mech2Pose.crouch(rig, k)       the powered-down rest crouch, 0..1
--   Mech2Pose.setCanopy(motors, c) head canopy 0 shut .. 1 open
--   Mech2Pose.powerTargets(model)  crouch / canopy / power from PowerState
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

function Mech2Pose.apply(rig: Rig, pose: { [string]: CFrame })
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

-- ===== powered-down rest crouch ==============================================
-- Hips sink back over planted feet, torso leans forward, head bowed (the
-- open canopy faces the pilot walking up), forearms resting on the thighs.

local CROUCH_DROP = 2.7 -- pelvis drop (studs)
local CROUCH_BACK = 0.45 -- pelvis back (+Z) so the knees go forward, not the hips
local CROUCH_LEAN = 0.32 -- torso pitch forward (radians)
local CROUCH_NECK = -0.3

function Mech2Pose.crouch(rig: Rig, k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local pose: { [string]: CFrame } = {}
	local s = smooth(k)
	local root = CFrame.new(0, -CROUCH_DROP * s, CROUCH_BACK * s) * CFrame.Angles(-0.12 * s, 0, 0)
	pose.Root = root
	for _, side in { "Left", "Right" } do
		local leg = rig.legs[side]
		if leg then
			local out = if side == "Left" then -0.25 else 0.25
			local yaw = if side == "Left" then 0.14 else -0.14
			Mech2Pose.legIK(rig, side, leg.ankle + Vector3.new(out * s, 0, 0), root, yaw * s, 0, pose, true)
		end
	end
	local a = curve(k, 0.2, 1)
	pose.Waist = CFrame.Angles(-CROUCH_LEAN * 0.6 * a, 0, 0)
	pose.Spine = CFrame.Angles(-CROUCH_LEAN * 0.4 * a, 0, 0)
	pose.Neck = CFrame.Angles(CROUCH_NECK * a, 0, 0)
	-- forearms down onto the thighs
	for _, side in { "Left", "Right" } do
		local sx = if side == "Right" then 1 else -1
		pose[side .. "Shoulder"] = CFrame.Angles(0.42 * a, 0, -sx * 0.1 * a)
		pose[side .. "Elbow"] = CFrame.Angles(0.75 * a, 0, 0)
		pose[side .. "Wrist"] = CFrame.Angles(0.15 * a, 0, 0)
		pose[side .. "PauldronJoint"] = CFrame.Angles(0.12 * a, 0, 0)
	end
	return pose
end

-- Opens the head canopy by c (0 shut .. 1 open).
function Mech2Pose.setCanopy(motors: { [string]: Motor6D }, c: number)
	local hinge = motors.CanopyHinge
	if hinge then
		hinge.Transform = CFrame.Angles(Mech2Config.CanopyOpen * smooth(c), 0, 0)
	end
end

function Mech2Pose.stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- crouch (0 standing .. 1 crouched), canopy (0 shut .. 1 open), power
-- (light level) for the current power state; last = exact (timed) values.
function Mech2Pose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = Mech2Pose.stateTime(model)
	local B, X = Mech2Pose.Board, Mech2Pose.Exit
	if state == "Boarding" then
		local crouch = 1 - smooth((t - B.StandStart) / (B.StandEnd - B.StandStart))
		local canopy = 1 - smooth((t - B.CanopyCloseStart) / (B.CanopyCloseEnd - B.CanopyCloseStart))
		return crouch, canopy, smooth((t - B.PowerUp) / 0.4), true
	elseif state == "PoweringDown" then
		local canopy = smooth((t - X.CanopyOpenStart) / (X.CanopyOpenEnd - X.CanopyOpenStart))
		return smooth(t / X.CrouchEnd), canopy, 1 - smooth(t / 0.6), true
	elseif state == "Off" then
		return 1, 1, 0, false
	end
	return 0, 0, 1, false
end

function Mech2Pose.applyStatic(motors: { [string]: Motor6D }, crouch: number, canopy: number)
	local rig = Mech2Pose.rig(motors)
	if not rig then
		return
	end
	if crouch <= 1e-4 then
		for name, j in rig.joints do
			if name ~= "CanopyHinge" then
				j.motor.Transform = CFrame.identity
			end
		end
	else
		Mech2Pose.apply(rig, Mech2Pose.crouch(rig, crouch))
	end
	Mech2Pose.setCanopy(motors, canopy)
end

function Mech2Pose.applyOff(motors: { [string]: Motor6D })
	Mech2Pose.applyStatic(motors, 1, 1)
end

return Mech2Pose
