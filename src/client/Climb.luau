--!strict
-- Climbing onto (and hopping off) the raised ramp of a one-knee mech (off
-- pose "OneKnee", see MechBuilder.OffStyles and MechConfig.Climb).
--
-- Every client animates every pilot the same way from the mech's
-- PowerState / PowerTime timeline, so everyone sees the same climb:
--   * boarding: after the approach walk (Boarding walks the local pilot to
--     the spot under the lip) the avatar reaches up, grabs the lip, hangs,
--     pulls itself up, swings a leg over, stands and walks up the ramp to the
--     spot in front of the seat. Boarding then turns it and the server seats it.
--   * exit: once unseated it walks down the ramp to the lip, hops off and
--     lands with a squash.
-- Meanwhile the avatar's root is anchored (on this client only) and moved
-- along the path, and its R15 joints (Motor6Ds, or AnimationConstraints on
-- avatars with upgraded joints) are driven directly, overriding its
-- animations. R6 avatars just glide along the path.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechBuilder = require(Shared:WaitForChild("MechBuilder"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechPose = require(Shared:WaitForChild("MechPose"))

local Climb = {}

local C, X = MechConfig.Climb, MechConfig.Exit
local HANG_Z = 0.6 -- the hanging body is this far out in front of the lip
local RAMP_IN = 1.4 -- stands up this far up the ramp from the lip
local HOP_OUT = 2.0 -- lands this far out past the foot of the ramp
local HOP_ARC = 1.3
local STEP = 1.7 -- studs per step when walking the ramp

local JOINTS = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle",
}

-- An avatar joint: a Motor6D, or an AnimationConstraint on avatars with the
-- upgraded joints. Both pose Part1 at Part0 * C0 * Transform * C1:Inverse().
type Joint = any

local function c0(j: Joint): CFrame
	return if j:IsA("Motor6D") then j.C0 else (j.Attachment0 :: Attachment).CFrame
end

local function c1(j: Joint): CFrame
	return if j:IsA("Motor6D") then j.C1 else (j.Attachment1 :: Attachment).CFrame
end

type Arm = { shoulder: Joint, elbow: Joint, upper: number, lower: number }
type Actor = {
	char: Model,
	hrp: BasePart,
	hum: Humanoid,
	key: string, -- state + PowerTime of the sequence
	start: CFrame, -- where the avatar was when the sequence took it over
	joints: { [string]: Joint },
	arms: { Right: Arm?, Left: Arm? },
	r15: boolean,
	stand: number, -- root height above the floor when standing
	floorY: number, -- the floor in front of the ramp (world height; the pad is raised)
	shoulderUp: number, -- shoulder joints above the root
	armReach: number,
	cues: { [string]: boolean },
	sounds: { [string]: Sound },
}

local actors: { [Model]: Actor } = {} -- by mech

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Limb pose for one frame. Pitches in radians: lean tips the whole body
-- toward where it faces, waist bends the upper body forward, hips raise the
-- thighs, knees bend, neck looks up. arms: 0 at the sides .. 1 on the lip.
type Pose = {
	pos: Vector3, -- root position in the lip frame
	lean: number,
	waist: number,
	neck: number,
	hipL: number,
	kneeL: number,
	hipR: number,
	kneeR: number,
	arms: number,
	armSwing: number, -- walking arm swing (left forward positive)
	armLift: number, -- arms raised forward (hop / landing)
}

local function blendPose(a: Pose, b: Pose, t: number): Pose
	return {
		pos = a.pos:Lerp(b.pos, t),
		lean = lerp(a.lean, b.lean, t),
		waist = lerp(a.waist, b.waist, t),
		neck = lerp(a.neck, b.neck, t),
		hipL = lerp(a.hipL, b.hipL, t),
		kneeL = lerp(a.kneeL, b.kneeL, t),
		hipR = lerp(a.hipR, b.hipR, t),
		kneeR = lerp(a.kneeR, b.kneeR, t),
		arms = lerp(a.arms, b.arms, t),
		armSwing = lerp(a.armSwing, b.armSwing, t),
		armLift = lerp(a.armLift, b.armLift, t),
	}
end

type Key = { u: number, p: Pose }

local function pose(pos: Vector3, lean: number, waist: number, neck: number, hipL: number, kneeL: number, hipR: number, kneeR: number, arms: number): Pose
	return { pos = pos, lean = lean, waist = waist, neck = neck, hipL = hipL, kneeL = kneeL, hipR = hipR, kneeR = kneeR, arms = arms, armSwing = 0, armLift = 0 }
end

-- The lip frame: origin on the ramp's lip, -Z toward the mech, Y up.
type Frame = { cf: CFrame, ground: number, ramp: Vector3, rampLen: number, points: MechBuilder.OffPoints }
local function lipFrame(model: Model): Frame?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local p = MechBuilder.offPoints(root.CFrame, "OneKnee")
	local cf = CFrame.lookAt(p.lip, p.lip - p.forward)
	local up = cf:PointToObjectSpace(p.hinge)
	return { cf = cf, ground = p.ground - p.lip.Y, ramp = up.Unit, rampLen = up.Magnitude, points = p }
end

local function motorIn(char: Model, name: string): Joint?
	for _, d in char:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and d.Name == name then
			return d :: any
		end
	end
	return nil
end

local function makeActor(model: Model, char: Model, hrp: BasePart, hum: Humanoid, key: string, f: Frame): Actor
	local joints: { [string]: Joint } = {}
	for _, name in JOINTS do
		local m = motorIn(char, name)
		if m then
			joints[name] = m
		end
	end
	local r15 = hum.RigType == Enum.HumanoidRigType.R15 and joints.Waist ~= nil and joints.RightShoulder ~= nil
	local arms = {}
	local shoulderUp, armReach = 1.4, 2
	if r15 then
		for _, side in { "Right", "Left" } do
			local sh, el, wr = joints[side .. "Shoulder"], joints[side .. "Elbow"], joints[side .. "Wrist"]
			if sh and el and wr then
				local upper = (c0(el).Position - c1(sh).Position).Magnitude
				-- forearm plus the hand, gripping near its far end
				local lower = (c0(wr).Position - c1(el).Position).Magnitude + c1(wr).Position.Magnitude * 1.6
				arms[side] = { shoulder = sh, elbow = el, upper = upper, lower = lower }
				armReach = upper + lower
			end
		end
		-- rest-pose shoulder height above the root
		local rootJ, waist, sh = joints.Root, joints.Waist, joints.RightShoulder
		if rootJ and waist and sh then
			local ut = c0(rootJ) * c1(rootJ):Inverse() * c0(waist) * c1(waist):Inverse()
			shoulderUp = (ut * c0(sh)).Position.Y
		end
	end
	local stand = if r15 then hum.HipHeight + hrp.Size.Y / 2 else hrp.Size.Y / 2 + 2
	-- one ray for the floor height under the foot of the ramp
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, char }
	local foot = f.points.foot + f.points.forward
	local hit = workspace:Raycast(foot + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	local sounds = {}
	for _, name in { "ClimbGrab", "ClimbLand" } do
		local s = Instance.new("Sound")
		s.SoundId = (MechConfig.Sounds :: any)[name]
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 90
		s.Parent = hrp
		sounds[name] = s
	end
	return {
		char = char,
		hrp = hrp,
		hum = hum,
		key = key,
		start = hrp.CFrame,
		joints = joints,
		arms = arms,
		r15 = r15,
		stand = stand,
		floorY = if hit then hit.Position.Y else f.points.ground,
		shoulderUp = shoulderUp,
		armReach = armReach,
		cues = {},
		sounds = sounds,
	}
end

local function cue(a: Actor, name: string, sound: string, volume: number, speed: number, stopAfter: number?)
	if a.cues[name] then
		return
	end
	a.cues[name] = true
	local s = a.sounds[sound]
	if s then
		s.Volume = volume
		s.PlaybackSpeed = speed
		s.TimePosition = 0
		s:Play()
		if stopAfter then
			task.delay(stopAfter, function()
				s:Stop()
			end)
		end
	end
end

-- Shoulder + elbow transforms that put the hand on `target` (world), in the
-- plane of the body (elbows forward), for the upper torso at `ut`.
local function armIK(arm: Arm, ut: CFrame, target: Vector3): (CFrame, CFrame)
	local sh = arm.shoulder
	local d = ut:PointToObjectSpace(target) - c0(sh).Position
	local l1, l2 = arm.upper, arm.lower
	local dist = math.clamp(d.Magnitude, math.abs(l1 - l2) + 0.01, l1 + l2 - 0.01)
	local dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.new(0, -1, 0)
	local alpha = math.acos(math.clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1))
	local bend = math.pi - math.acos(math.clamp((l1 * l1 + l2 * l2 - dist * dist) / (2 * l1 * l2), -1, 1))
	local n = Vector3.xAxis - dir * dir.X
	n = if n.Magnitude > 1e-3 then n.Unit else Vector3.zAxis
	local upper = CFrame.fromAxisAngle(n, -alpha) * dir
	local rot = CFrame.fromMatrix(Vector3.zero, n, -upper)
	return c0(sh).Rotation:Inverse() * rot * c1(sh).Rotation, CFrame.Angles(bend, 0, 0)
end

local function setJoint(a: Actor, name: string, cf: CFrame)
	local m = a.joints[name]
	if m then
		m.Transform = cf
	end
end

-- Puts the avatar in pose `p` (root in the lip frame, facing `facing`, a
-- rotation) with its hands on `grip` (world, per side) by `p.arms`.
local function apply(a: Actor, f: Frame, p: Pose, facing: CFrame, grip: { [string]: Vector3 }?)
	local cf = CFrame.new(f.cf * p.pos) * facing * CFrame.Angles(-p.lean, 0, 0)
	a.hrp.CFrame = cf
	if not a.r15 then
		return
	end
	setJoint(a, "Root", CFrame.identity)
	local waistCF = CFrame.Angles(-p.waist, 0, 0)
	setJoint(a, "Waist", waistCF)
	setJoint(a, "Neck", CFrame.Angles(p.neck, 0, 0))
	-- feet stay level with the ground
	setJoint(a, "LeftHip", CFrame.Angles(p.hipL, 0, 0))
	setJoint(a, "LeftKnee", CFrame.Angles(-p.kneeL, 0, 0))
	setJoint(a, "LeftAnkle", CFrame.Angles(p.kneeL - p.hipL + p.lean, 0, 0))
	setJoint(a, "RightHip", CFrame.Angles(p.hipR, 0, 0))
	setJoint(a, "RightKnee", CFrame.Angles(-p.kneeR, 0, 0))
	setJoint(a, "RightAnkle", CFrame.Angles(p.kneeR - p.hipR + p.lean, 0, 0))
	local rootJ, waist = a.joints.Root, a.joints.Waist
	local ut = if rootJ and waist then cf * c0(rootJ) * c1(rootJ):Inverse() * c0(waist) * waistCF * c1(waist):Inverse() else cf
	for side, arm in a.arms do
		local s = if side == "Right" then 1 else -1
		local swing = p.armSwing * (if side == "Left" then 1 else -1)
		local rest = CFrame.Angles(swing + p.armLift, 0, s * (0.08 + 0.35 * p.armLift))
		local restElbow = CFrame.Angles(0.25 + 0.3 * p.armLift + math.abs(swing) * 0.4, 0, 0)
		local shCF, elCF = rest, restElbow
		if grip and grip[side] and p.arms > 0.001 then
			local ikS, ikE = armIK(arm, ut, grip[side])
			shCF, elCF = rest:Lerp(ikS, p.arms), restElbow:Lerp(ikE, p.arms)
		end
		arm.shoulder.Transform = shCF
		arm.elbow.Transform = elCF
		setJoint(a, side .. "Wrist", CFrame.identity)
	end
end

-- Walking pose along a path at distance `d` (for the leg cycle).
local function walkPose(pos: Vector3, d: number, lean: number, climb: number): Pose
	local ph = d / STEP * math.pi
	local s = math.sin(ph)
	local p = pose(pos, lean, 0.05 + climb * 0.1, 0, 0.55 * s + climb, 0.3 + math.max(0, s) * 0.9 + climb, -0.55 * s + climb, 0.3 + math.max(0, -s) * 0.9 + climb, 0)
	p.armSwing = 0.5 * s
	return p
end

-- Point at distance `d` along a polyline, and its total length.
local function along(points: { Vector3 }, d: number): (Vector3, number)
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	local left = math.clamp(d, 0, total)
	for i = 2, #points do
		local l = (points[i] - points[i - 1]).Magnitude
		if left <= l or i == #points then
			return points[i - 1]:Lerp(points[i], if l > 1e-4 then math.clamp(left / l, 0, 1) else 1), total
		end
		left -= l
	end
	return points[#points], total
end

-- Boarding: u counts through the climb (0..1), w through the ramp walk.
local function animateBoard(a: Actor, f: Frame, tau: number, walkEnd: number)
	local climbStart = walkEnd - C.Climb - C.RampWalk
	local u = (tau - climbStart) / C.Climb
	local facing = f.cf.Rotation -- toward the mech
	local g = a.floorY - f.cf.Position.Y + a.stand -- root height standing on the floor (lip frame)
	-- hanging from nearly straight arms a little out in front of the lip,
	-- knees tucked up so the feet clear the floor
	local hangY = math.max(-math.sqrt(math.max(0.1, (a.armReach * 0.96) ^ 2 - HANG_Z ^ 2)) - a.shoulderUp, g - 0.7)
	local deck = function(d: number): Vector3
		return f.ramp * d + Vector3.new(0, a.stand, 0)
	end
	local grip = {
		Right = f.cf * Vector3.new(0.85, 0.05, -0.15),
		Left = f.cf * Vector3.new(-0.85, 0.05, -0.15),
	}
	local foot = MechBuilder.HangOut
	local keys: { Key } = {
		{ u = 0.14, p = pose(Vector3.new(0, g - 0.4, foot), 0.1, 0.2, 0.55, 0.65, 1.3, 0.65, 1.3, 0.75) }, -- crouch, reach up
		{ u = 0.25, p = pose(Vector3.new(0, hangY + 0.6, HANG_Z + 0.1), -0.05, 0, 0.45, 0.25, 0.4, 0.2, 0.35, 1) }, -- hop, grab
		{ u = 0.38, p = pose(Vector3.new(0, hangY, HANG_Z), -0.08, 0, 0.35, 1.05, 1.95, 0.95, 1.85, 1) }, -- hang
		{ u = 0.66, p = pose(Vector3.new(0, 0.35 - a.shoulderUp, HANG_Z - 0.1), 0.25, 0.25, 0.15, 1.3, 1.9, 1.2, 1.8, 1) }, -- pulled up
		{ u = 0.83, p = pose(Vector3.new(0, 1.5, -0.25), 0.45, 0.25, -0.1, 1.9, 2.2, 0.3, 0.6, 1) }, -- knee over the lip
		{ u = 1.0, p = pose(deck(RAMP_IN), 0.2, 0.1, 0, 0.5, 0.55, 0.05, 0.15, 0) }, -- stand on the ramp
	}
	if u < 1 then
		local p: Pose
		local first = keys[1].p
		if u < keys[1].u then
			-- from wherever the approach walk ended
			local t = smooth(u / keys[1].u)
			local from = pose(f.cf:PointToObjectSpace(a.start.Position), 0, 0, 0, 0, 0, 0, 0, 0)
			p = blendPose(from, first, t)
			local _, yaw0, _ = a.start:ToOrientation()
			local _, yaw1, _ = facing:ToOrientation()
			local dy = (yaw1 - yaw0 + math.pi) % (2 * math.pi) - math.pi
			facing = CFrame.Angles(0, yaw0 + dy * t, 0)
		else
			p = first
			for i = 2, #keys do
				local k0, k1 = keys[i - 1], keys[i]
				if u <= k1.u or i == #keys then
					p = blendPose(k0.p, k1.p, smooth((u - k0.u) / (k1.u - k0.u)))
					break
				end
			end
		end
		-- the arms let go of the lip once the knee is on it
		if u > 0.83 then
			p.arms *= 1 - smooth((u - 0.83) / 0.12)
		end
		if u >= 0.25 then
			cue(a, "grab", "ClimbGrab", 0.9, 1.15, 0.8)
		end
		if u >= 0.8 then
			cue(a, "knee", "ClimbGrab", 0.45, 1.5, 0.5)
		end
		apply(a, f, p, facing, grip)
		return
	end
	-- walk up the ramp and into the cockpit
	local w = math.clamp((tau - climbStart - C.Climb) / C.RampWalk, 0, 1)
	local pts = { deck(RAMP_IN), deck(f.rampLen), f.cf:PointToObjectSpace(f.points.stand) + Vector3.new(0, a.stand, 0) }
	local _, total = along(pts, 0)
	local d = total * smooth(w)
	local pos = along(pts, d)
	local onRamp = math.clamp(1 - (d - (f.rampLen - RAMP_IN)) / 1.5, 0, 1)
	local p = walkPose(pos, d, 0.1 + 0.15 * onRamp, 0.3 * onRamp)
	-- ease out of the standing-up pose
	p = blendPose(keys[#keys].p, p, smooth(w / 0.25))
	apply(a, f, p, facing, nil)
end

-- Exit: x seconds since the pilot was unseated.
local function animateExit(a: Actor, f: Frame, x: number)
	local facing = CFrame.lookAt(Vector3.zero, f.points.forward) -- out
	local g = a.floorY - f.cf.Position.Y + a.stand
	local lipStand = f.ramp * 0.9 + Vector3.new(0, a.stand, 0)
	local landing = Vector3.new(0, g, MechBuilder.HangOut + HOP_OUT)
	if x < C.RampDown then
		local pts = {
			f.cf:PointToObjectSpace(a.start.Position),
			f.cf:PointToObjectSpace(f.points.stand) + Vector3.new(0, a.stand, 0),
			f.ramp * f.rampLen + Vector3.new(0, a.stand, 0),
			lipStand,
		}
		local _, total = along(pts, 0)
		local d = total * smooth(x / C.RampDown)
		local pos = along(pts, d)
		local _, yaw0, _ = a.start:ToOrientation()
		local _, yaw1, _ = facing:ToOrientation()
		local dy = (yaw1 - yaw0 + math.pi) % (2 * math.pi) - math.pi
		local t = smooth(x / 0.2)
		local p = walkPose(pos, d, -0.08, 0)
		apply(a, f, p, CFrame.Angles(0, yaw0 + dy * t, 0), nil)
		return
	end
	x -= C.RampDown
	if x < C.Hop then
		-- hop off the lip: a little up, then down onto the pad
		local h = x / C.Hop
		local pos = lipStand:Lerp(landing, h) + Vector3.new(0, 4 * HOP_ARC * h * (1 - h), 0)
		local tuck = math.sin(math.pi * h)
		local p = pose(pos, 0.1, 0.1, 0.1, 0.3 + 0.7 * tuck, 0.3 + 1.1 * tuck, 0.2 + 0.6 * tuck, 0.3 + 1.0 * tuck, 0)
		p.armLift = 0.9 + 0.4 * tuck
		apply(a, f, p, facing, nil)
		return
	end
	x -= C.Hop
	cue(a, "land", "ClimbLand", 0.8, 1.1, 1)
	-- landing squash: quick down, slower recovery
	local l = x / C.Land
	local s = if l < 0.25 then smooth(l / 0.25) else 1 - smooth((l - 0.25) / 0.75)
	local p = pose(landing - Vector3.new(0, 0.9 * s, 0), 0.15 * s, 0.35 * s, -0.1 * s, 0.3 + 0.9 * s, 0.3 + 1.6 * s, 0.2 + 0.9 * s, 0.3 + 1.6 * s, 0)
	-- legs straighten out of the hop
	local rec = smooth(l / 0.2)
	p.hipL, p.kneeL = lerp(0.3, p.hipL, rec), lerp(0.3, p.kneeL, rec)
	p.hipR, p.kneeR = lerp(0.2, p.hipR, rec), lerp(0.3, p.kneeR, rec)
	p.armLift = 0.9 * (1 - smooth(l)) + 0.5 * s
	apply(a, f, p, facing, nil)
end

local function release(model: Model)
	local a = actors[model]
	if not a then
		return
	end
	actors[model] = nil
	for _, m in a.joints do
		m.Transform = CFrame.identity
	end
	for _, s in a.sounds do
		task.delay(1.5, function()
			s:Destroy()
		end)
	end
	if a.hrp.Parent then
		a.hrp.AssemblyLinearVelocity = Vector3.zero
		a.hrp.AssemblyAngularVelocity = Vector3.zero
		a.hrp.Anchored = false
	end
end

-- The pilot's character, while it isn't strapped into the seat.
local function pilotOf(model: Model): (Model?, BasePart?, Humanoid?)
	local id = model:GetAttribute("PilotId")
	local player = if typeof(id) == "number" then Players:GetPlayerByUserId(id) else nil
	local char = player and player.Character
	if not char then
		return nil, nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return nil, nil, nil
	end
	-- still welded to the seat: moving it would drag the mech along
	local seat = model:FindFirstChild("PilotSeat", true)
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") and (weld.Part1 and weld.Part1:IsDescendantOf(char)) then
		return nil, nil, nil
	end
	return char, hrp, hum
end

local function step()
	for _, inst in CollectionService:GetTagged("Mech") do
		if not inst:IsA("Model") or not inst.Parent then
			continue
		end
		local model = inst :: Model
		if MechPose.style(model) ~= "OneKnee" then
			if actors[model] then
				release(model)
			end
			continue
		end
		local state = model:GetAttribute("PowerState")
		local key = tostring(state) .. tostring(model:GetAttribute("PowerTime"))
		local tau = MechPose.stateTime(model)
		local active, kind = false, ""
		if state == "Boarding" then
			local walkEnd = MechPose.boardWalk(model)
			active = tau >= walkEnd - C.Climb - C.RampWalk and tau < walkEnd
			kind = "board"
		elseif state == "PoweringDown" then
			local x = MechPose.revealTime(model) - X.Stand
			active = x >= 0 and x < C.RampDown + C.Hop + C.Land
			kind = "exit"
		end
		local a = actors[model]
		local char, hrp, hum
		if active then
			char, hrp, hum = pilotOf(model)
		end
		if a and (not active or a.key ~= key or a.char ~= char) then
			release(model)
			a = nil
		end
		if not (active and char and hrp and hum) then
			continue
		end
		local f = lipFrame(model)
		if not f then
			continue
		end
		if not a then
			a = makeActor(model, char, hrp, hum, key, f)
			actors[model] = a
		end
		local actor = a :: Actor
		actor.hrp.Anchored = true
		if kind == "board" then
			animateBoard(actor, f, tau, MechPose.boardWalk(model))
		else
			animateExit(actor, f, MechPose.revealTime(model) - X.Stand)
		end
	end
	for model in actors do
		if not model.Parent then
			release(model)
		end
	end
end

-- Whether the climb animation is currently driving `char`.
function Climb.isDriving(char: Model?): boolean
	for _, a in actors do
		if a.char == char then
			return true
		end
	end
	return false
end

function Climb.start()
	-- after the Animator has posed the avatars, before physics
	RunService.PreSimulation:Connect(step)
end

return Climb
