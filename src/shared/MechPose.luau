--!strict
-- Pose math shared by the client animator and the server.
--
--   * crouch(cr): the powered-down squat as hip / knee angles plus the body
--     drop, solved with two-bone IK so the feet stay exactly planted.
--   * oneKnee(k): the "OneKnee" off pose (model attribute "OffPose"), right
--     knee down, as a full set of joint transforms blended in by k.
--   * powerTargets(model): crouch / door / ramp / light levels for the mech's
--     current PowerState and PowerTime (see MechConfig.Boarding / Exit).
--   * applyStatic(motors, ...): the server mirrors the kneel, doors and ramp on its own
--     copy (Motor6D.Transform does not replicate), so seats and ramps are in
--     the same place on the server as on every client.

local RunService = game:GetService("RunService")

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)

local MechPose = {}

local S = MechBuilder.Scale
local B, X = MechConfig.Boarding, MechConfig.Exit

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function easeIn(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * x
end

local function easeOut(x: number): number
	x = 1 - math.clamp(x, 0, 1)
	return 1 - x * x * x
end

-- Leg segments in their bones' frames (studs), from the builder's joint layout.
local function boneOrigin(name: string): Vector3
	for _, def in MechBuilder.Bones do
		if def.name == name then
			return def.pos * S
		end
	end
	error("no bone " .. name)
end
local THIGH = boneOrigin("RightLowerLeg") - boneOrigin("RightUpperLeg")
local SHIN = boneOrigin("RightFoot") - boneOrigin("RightLowerLeg")

local function rotX(v: Vector3, a: number): Vector3
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end

-- Pitch of a downward-pointing vector: 0 straight down, positive = lower end forward (-Z).
local function pitchOf(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

-- Ankle position relative to the hip for extra hip/knee pitch on top of rest.
function MechPose.ankleOffset(hip: number, knee: number): Vector3
	local thighAngle = MechBuilder.HipRest + hip
	return rotX(THIGH, thighAngle) + rotX(SHIN, thighAngle + MechBuilder.KneeRest + knee)
end
local ANKLE_REST = MechPose.ankleOffset(0, 0)
local THIGH_LEN, SHIN_LEN = THIGH.Magnitude, SHIN.Magnitude
local SHIN_PITCH = pitchOf(SHIN)

-- Squat amount 0..1 -> hip angle, knee angle (extra pitch over rest) and the
-- body drop (Root transform offset, studs). Knees bend forward.
function MechPose.crouch(cr: number): (number, number, Vector3)
	if cr < 1e-4 then
		return 0, 0, Vector3.zero
	end
	local drop = MechBuilder.OffDrop * cr
	local thigh, shin = MechPose.legIK(ANKLE_REST - drop) -- hip -> ankle once the body has dropped
	return thigh - MechBuilder.HipRest, shin - thigh - MechBuilder.KneeRest, drop
end

-- Two-bone leg IK, knee bending forward: hip -> ankle vector (waist frame,
-- studs) -> thigh and shin bone pitches (world, level waist).
function MechPose.legIK(v: Vector3): (number, number)
	local d = math.clamp(v.Magnitude, math.abs(THIGH_LEN - SHIN_LEN) + 1e-3, THIGH_LEN + SHIN_LEN - 1e-3)
	local spread = math.acos(math.clamp((THIGH_LEN * THIGH_LEN + d * d - SHIN_LEN * SHIN_LEN) / (2 * THIGH_LEN * d), -1, 1))
	local thighPitch = pitchOf(v) + spread
	local knee = rotX(Vector3.new(0, -THIGH_LEN, 0), thighPitch)
	return thighPitch - pitchOf(THIGH), pitchOf(v - knee) - SHIN_PITCH
end

-- The mech's powered-down pose style ("OffPose" attribute): "Kneel" or "OneKnee".
function MechPose.style(model: Model): string
	local s = model:GetAttribute("OffPose")
	return if typeof(s) == "string" and MechBuilder.OffStyles[s] then s else "Kneel"
end

-- One-knee pose (see MechBuilder.OneKneeLegs), right knee down. Upper body
-- targets in radians; the gatling arm hangs to the ground beside the knee,
-- the left forearm rests across the raised left knee.
local LEGS = MechBuilder.OneKneeLegs
local ONE_KNEE = MechBuilder.OffStyles.OneKnee
local HIP_REST, KNEE_REST = MechBuilder.HipRest, MechBuilder.KneeRest
local STEP_LIFT = 1.6 * S -- the right foot lifts clear as it steps back
MechPose.OneKneeNeck = -0.12
-- shoulder (pitch, yaw, roll) and elbow, solved offline so the gatling's
-- barrels touch the floor ahead of the knee and the left forearm lies across
-- the raised knee
MechPose.OneKneeRightArm = { shoulder = CFrame.Angles(-0.55, 0, -0.25), elbow = 0.8 }
MechPose.OneKneeLeftArm = { shoulder = CFrame.Angles(2.1, -1.2, 1.2), elbow = 0.8 }

local function curve(k: number, a: number, b: number): number
	return smooth((k - a) / (b - a))
end

-- Joint transforms for the one-knee pose blended in by k (0 standing .. 1
-- knelt): the right foot steps back and rolls onto its toe while the body
-- sinks back over it; the left foot stays planted. Also used backwards
-- (standing up).
function MechPose.oneKnee(k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local drop = ONE_KNEE.drop
	local hip = Vector3.new(0, drop.Y * smooth(k), drop.Z * curve(k, 0, 0.7))
	local u = curve(k, 0, 0.75)
	local footPitch = LEGS.foot * smooth(u)
	-- right ankle: from standing to behind the knee, lifted clear on the way
	local ankle = ANKLE_REST:Lerp(drop + LEGS.rightAnkle, u) + Vector3.new(0, STEP_LIFT * math.sin(math.pi * u), 0)
	local pose: { [string]: CFrame } = {}
	local function leg(side: string, v: Vector3, foot: number)
		local thigh, shin = MechPose.legIK(v)
		pose[side .. "Hip"] = CFrame.Angles(thigh - HIP_REST, 0, 0)
		pose[side .. "Knee"] = CFrame.Angles(shin - thigh - KNEE_REST, 0, 0)
		pose[side .. "Ankle"] = CFrame.Angles(foot - shin + HIP_REST + KNEE_REST, 0, 0)
	end
	leg("Right", ankle - hip, footPitch)
	leg("Left", ANKLE_REST - hip, 0)
	pose.Root = CFrame.new(hip)
	pose.Waist = CFrame.Angles(ONE_KNEE.waist * MechPose.torsoCrouch(k), 0, 0)
	local a = curve(k, 0.35, 1)
	pose.Neck = CFrame.Angles(MechPose.OneKneeNeck * a, 0, 0)
	local r, l = MechPose.OneKneeRightArm, MechPose.OneKneeLeftArm
	pose.RightShoulder = CFrame.Angles(0, 0, 0.04):Lerp(r.shoulder, a)
	pose.RightElbow = CFrame.Angles(r.elbow * a, 0, 0)
	pose.LeftShoulder = CFrame.Angles(0, 0, -0.04):Lerp(l.shoulder, a)
	pose.LeftElbow = CFrame.Angles(l.elbow * a, 0, 0)
	return pose
end

-- Seconds since the mech's current power state began.
function MechPose.stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- Seconds since the doors started opening on an exiting pilot (negative before).
function MechPose.revealTime(model: Model): number
	if model:GetAttribute("PowerState") ~= "PoweringDown" then
		return -1
	end
	return MechPose.stateTime(model) - X.Reveal
end

-- Length of the boarding walk for this mech (seconds).
function MechPose.boardWalk(model: Model): number
	local w = model:GetAttribute("BoardWalk")
	return if typeof(w) == "number" then w else MechConfig.BoardWalkMin
end

-- Targets for the mech's current power state: crouch (0 standing .. 1
-- kneeling), doors and ramp (0 shut .. 1 open) and light level. Timed states
-- return exact values (last result true); steady states are eased toward.
function MechPose.powerTargets(model: Model, flicker: boolean?): (number, number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = MechPose.stateTime(model)
	if state == "Boarding" then
		t -= MechPose.boardWalk(model) -- times count from the end of the walk
		local crouch = 1 - smooth((t - B.StandStart) / (B.StandEnd - B.StandStart))
		-- heavy settle as the weight lands on the legs (not from one knee: a
		-- partial one-knee pose would lift a foot)
		local settle = t - B.StandEnd
		if settle > 0 and settle < 0.4 and MechPose.style(model) ~= "OneKnee" then
			crouch += 0.06 * math.sin(settle / 0.4 * math.pi)
		end
		local ramp = 1 - smooth((t - B.RampCloseStart) / (B.RampCloseEnd - B.RampCloseStart))
		local doors = 1 - easeIn((t - B.DoorCloseStart) / (B.DoorCloseEnd - B.DoorCloseStart))
		local u = (t - B.PowerUp) / 0.5
		local power = smooth(u)
		if flicker and u > 0 and u < 1 and math.random() < 0.35 then
			power *= 0.3 -- flicker on
		end
		return crouch, doors, ramp, power, true
	elseif state == "PoweringDown" then
		local crouch = smooth(t / X.CrouchEnd)
		local r = MechPose.revealTime(model)
		local doors = easeOut(r / X.DoorOpen)
		local ramp = easeIn((r - X.RampOpenStart) / (X.RampOpenEnd - X.RampOpenStart))
		return crouch, doors, ramp, 1 - smooth(t / 0.5), true
	elseif state == "Off" then
		return 1, 1, 1, 0, false
	end
	return 0, 0, 0, 1, false
end

-- Motor6Ds of a mech by name.
function MechPose.motors(model: Model): { [string]: Motor6D }
	local motors: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	return motors
end

-- Sets the kneel, torso bow, doors and ramp (no walk cycle). Used by the
-- server. The one-knee style also sets the arms and head.
function MechPose.applyStatic(motors: { [string]: Motor6D }, cr: number, doors: number, ramp: number, style: string?)
	local function set(name: string, cf: CFrame)
		local m = motors[name]
		if m then
			m.Transform = cf
		end
	end
	if style == "OneKnee" and cr > 1e-4 then
		for name, cf in MechPose.oneKnee(cr) do
			set(name, cf)
		end
	else
		local hip, knee, drop = MechPose.crouch(if style == "OneKnee" then 0 else cr)
		set("Root", CFrame.new(drop))
		set("Waist", CFrame.Angles(if style == "OneKnee" then 0 else MechBuilder.OffTorsoBow * MechPose.torsoCrouch(cr), 0, 0))
		for _, side in { "Left", "Right" } do
			set(side .. "Hip", CFrame.Angles(hip, 0, 0))
			set(side .. "Knee", CFrame.Angles(knee, 0, 0))
			set(side .. "Ankle", CFrame.Angles(-(hip + knee), 0, 0))
		end
	end
	MechPose.setCockpit(motors, doors, ramp, style)
end

-- Kneeling upper-body pose (radians), shared by the animator and the edit-mode preview.
MechPose.CrouchNeck = -0.3 -- head hangs
MechPose.CrouchShoulder = 0.5 -- arms reach forward over the knees
MechPose.CrouchSplay = 0.22 -- and out past them
MechPose.CrouchElbow = 0.8 -- forearms resting forward

-- The full powered-down pose (legs, torso, head, arms, open cockpit), no animation.
function MechPose.applyOff(motors: { [string]: Motor6D }, style: string?)
	MechPose.applyStatic(motors, 1, 1, 1, style)
	if style == "OneKnee" then
		return
	end
	local function set(name: string, cf: CFrame)
		local m = motors[name]
		if m then
			m.Transform = cf
		end
	end
	set("Neck", CFrame.Angles(MechPose.CrouchNeck, 0, 0))
	set("LeftShoulder", CFrame.Angles(MechPose.CrouchShoulder, 0, -0.04 - MechPose.CrouchSplay))
	set("RightShoulder", CFrame.Angles(MechPose.CrouchShoulder, 0, 0.04 + MechPose.CrouchSplay))
	set("LeftElbow", CFrame.Angles(MechPose.CrouchElbow, 0, 0))
	set("RightElbow", CFrame.Angles(MechPose.CrouchElbow, 0, 0))
end

-- The upper body bows a beat after the legs fold (and straightens a beat
-- after them when standing up).
function MechPose.torsoCrouch(cr: number): number
	return math.clamp(cr, 0, 1) ^ 0.7
end

-- Opens the doors and ramp by the given amounts (0 shut .. 1 open).
function MechPose.setCockpit(motors: { [string]: Motor6D }, doors: number, ramp: number, style: string?)
	local open = MechBuilder.DoorOpenAngle * doors
	local left, right, hinge = motors.DoorLeftHinge, motors.DoorRightHinge, motors.RampHinge
	if left then
		-- swing out to the side about the hinge pin only: any extra tilt would
		-- pull the door's hinge edge away from the chest corner and open a slit
		left.Transform = CFrame.Angles(0, open, 0)
	end
	if right then
		right.Transform = CFrame.Angles(0, -open, 0)
	end
	if hinge then
		-- the ramp never folds up; it shrinks back into the cockpit floor instead
		hinge.Transform = CFrame.Angles(MechBuilder.offStyle(style).rampAngle, 0, 0)
		local bone = hinge.Part1
		if bone then
			MechPose.scaleRamp(bone, ramp)
		end
	end
end

-- Retracts the ramp along its length toward the hinge (k = 1 full length ..
-- 0 gone), like stairs sliding up into the cockpit: every part welded to the
-- ramp bone keeps its width and thickness, shortens along the bone's Y axis
-- (hinge -> lip) and slides toward the hinge. Clients change sizes (the
-- server never does, so its sizes always replicate as the full ramp); the
-- server alone owns CanCollide, off while retracted. State lives in a
-- per-VM table (attributes would replicate between sides). Not weak-keyed:
-- an Instance's Lua wrapper can be collected while the part lives on, which
-- would lose its base and re-capture the shrunk size.
type RampBase = { size: Vector3, c0: CFrame, axis: Vector3, transparency: number, collide: boolean, k: number }
local rampBase: { [BasePart]: RampBase } = {}
local RAMP_MIN = 0.02

function MechPose.scaleRamp(bone: BasePart, k: number)
	-- GetJoints only works in the world (the edit-mode preview poses it off-world)
	if not bone:IsDescendantOf(workspace) then
		return
	end
	k = math.clamp(k, 0, 1)
	if k > 0.995 then
		k = 1 -- eased values land exactly on full size
	end
	local client = RunService:IsClient()
	for _, joint in bone:GetJoints() do
		if not joint:IsA("Weld") or joint.Part0 ~= bone then
			continue
		end
		local weld = joint :: Weld
		local part = weld.Part1
		if not part then
			continue
		end
		local base = rampBase[part]
		if not base then
			-- the ramp's length axis in the part's own frame (abs per component)
			local a = weld.C0.Rotation:VectorToObjectSpace(Vector3.yAxis)
			local axis = Vector3.new(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
			base = { size = part.Size, c0 = weld.C0, axis = axis, transparency = part.Transparency, collide = part.CanCollide, k = -1 }
			rampBase[part] = base
			part.Destroying:Once(function()
				rampBase[part] = nil
			end)
		end
		if base.k == k then
			continue
		end
		base.k = k
		if not client then
			part.CanCollide = base.collide and k > 0.5
			continue
		end
		local s = math.max(k, RAMP_MIN)
		local p = base.c0.Position
		part.Size = base.size * (Vector3.one + base.axis * (s - 1))
		weld.C0 = CFrame.new(p.X, p.Y * s, p.Z) * base.c0.Rotation
		part.Transparency = if k < RAMP_MIN then 1 else base.transparency
	end
end

return MechPose
