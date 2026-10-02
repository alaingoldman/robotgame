--!strict
-- Procedural avatar climbs into and out of mechs:
--   * the raised ramp of a one-knee HWM-04B (off pose "OneKnee", see
--     MechBuilder.OffStyles and MechConfig.Climb): climb on, hop off.
--   * the WTK-99's nose (see Type99Builder.Cockpit and MechConfig.
--     Type99Boarding / Type99Exit): grab the nose handles and mantle onto the
--     nose, walk up the sloped deck and over the sill into the cockpit, turn
--     round and sit down in the seat; on the way out stand up, walk down the
--     deck and hop off the nose tip.
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
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local Type99Builder = require(Shared:WaitForChild("Type99Builder"))
local Type99Pose = require(Shared:WaitForChild("Type99Pose"))

local Climb = {}

local C, X = MechConfig.Climb, MechConfig.Exit
local TB, TX = MechConfig.Type99Boarding, MechConfig.Type99Exit
local T99_SCALE = Type99Builder.Scale
local T99_HOLD = 1.0 -- seconds past Sit the seated pose is held waiting for the seat weld
local SLOPE_LIFT = 0.3 -- standing on the sloped deck / floor: root this much higher
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
	foot: number, -- extra ankle pitch (toes up positive): feet along a slope, seated
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
		foot = lerp(a.foot, b.foot, t),
	}
end

type Key = { u: number, p: Pose }

local function pose(pos: Vector3, lean: number, waist: number, neck: number, hipL: number, kneeL: number, hipR: number, kneeR: number, arms: number): Pose
	return { pos = pos, lean = lean, waist = waist, neck = neck, hipL = hipL, kneeL = kneeL, hipR = hipR, kneeR = kneeR, arms = arms, armSwing = 0, armLift = 0, foot = 0 }
end

-- The lip frame: origin on the ramp's lip, -Z toward the mech, Y up.
type Frame = { cf: CFrame, ground: number, ramp: Vector3, rampLen: number, points: MechBuilder.OffPoints }
-- The WTK-99 nose frame: origin on the ground at the climb spot, -Z toward
-- the mech, Y up; key points of the way in are in world space.
type NoseFrame = {
	cf: CFrame,
	forward: Vector3,
	tip: Vector3,
	grips: { [string]: Vector3 },
	deckFront: Vector3, -- on the deck just past the tip
	sill: Vector3,
	dash: Vector3, -- top of the dashboard on the sill
	floor: Vector3, -- standing spot in front of the seat
	seat: CFrame, -- seat top
	slope: number, -- deck / floor slope (radians, rising toward the back)
}
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

local function makeActor(model: Model, char: Model, hrp: BasePart, hum: Humanoid, key: string, probe: Vector3, fallbackY: number): Actor
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
	local hit = workspace:Raycast(probe + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
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
		floorY = if hit then hit.Position.Y else fallbackY,
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

-- Puts the avatar in pose `p` with its root at `rootCF` (world, lean
-- included) and its hands on `grip` (world, per side) by `p.arms`.
local function applyAt(a: Actor, cf: CFrame, p: Pose, grip: { [string]: Vector3 }?)
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
	setJoint(a, "LeftAnkle", CFrame.Angles(p.kneeL - p.hipL + p.lean + p.foot, 0, 0))
	setJoint(a, "RightHip", CFrame.Angles(p.hipR, 0, 0))
	setJoint(a, "RightKnee", CFrame.Angles(-p.kneeR, 0, 0))
	setJoint(a, "RightAnkle", CFrame.Angles(p.kneeR - p.hipR + p.lean + p.foot, 0, 0))
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

-- Pose `p` with its root in the lip frame, facing `facing` (a rotation).
local function apply(a: Actor, f: Frame, p: Pose, facing: CFrame, grip: { [string]: Vector3 }?)
	applyAt(a, CFrame.new(f.cf * p.pos) * facing * CFrame.Angles(-p.lean, 0, 0), p, grip)
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

-- ============================================================ WTK-99 nose

local function noseFrame(model: Model): NoseFrame?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local p = Type99Builder.offPoints(root.CFrame)
	local ck = Type99Builder.Cockpit
	local function at(v: Vector3): Vector3
		return p.hull * (v * T99_SCALE)
	end
	local gx = Vector3.new(ck.gripX, 0, 0)
	local deckFront, sill = at(ck.deckFront), at(ck.sill)
	local run = (sill - deckFront) * Vector3.new(1, 0, 1)
	return {
		cf = CFrame.lookAt(p.climb, p.climb - p.forward),
		forward = p.forward,
		tip = at(ck.tip),
		grips = { Right = at(ck.grip + gx), Left = at(ck.grip - gx) },
		deckFront = deckFront,
		sill = sill,
		dash = at(Vector3.new(0, ck.dashTop, ck.sill.Z + 0.15)),
		floor = at(ck.floorStand),
		seat = p.seat,
		slope = math.atan2(sill.Y - deckFront.Y, run.Magnitude),
	}
end

-- Root CFrame of an avatar sat in the seat (the engine's SeatWeld puts the
-- root half the hip height above the seat top).
local function seatedCF(a: Actor, n: NoseFrame): CFrame
	return n.seat * CFrame.new(0, a.hum.HipHeight / 2, 0)
end

local function seatedPose(): Pose
	-- matches the default sit animation (thighs forward, shins down, feet flat)
	local p = pose(Vector3.zero, 0, -0.08, 0, 1.62, 1.25, 1.62, 1.25, 0)
	p.foot = 1.62 - 1.25
	p.armLift = 0.15
	return p
end

-- The walk into the cockpit: deck front -> sill -> over the dashboard ->
-- the standing spot (world root positions; a little high, since the feet
-- lie along the slope).
local function cockpitPath(a: Actor, n: NoseFrame): { Vector3 }
	local up = Vector3.new(0, a.stand + SLOPE_LIFT, 0)
	return {
		n.deckFront + up,
		n.sill + up,
		n.dash + Vector3.new(0, a.stand + 0.7, 0), -- a high step over the dashboard
		n.floor + up,
	}
end

-- Facing rotations: into the mech (toward its back) and out (its front).
local function facingIn(n: NoseFrame): CFrame
	return CFrame.lookAt(Vector3.zero, -n.forward)
end
local function facingOut(n: NoseFrame): CFrame
	return CFrame.lookAt(Vector3.zero, n.forward)
end

-- Yaw from `from` toward `to` by t; `dir` picks the side of a half turn.
local function yawBlend(from: CFrame, to: CFrame, t: number, dir: number?): CFrame
	local _, y0, _ = from:ToOrientation()
	local _, y1, _ = to:ToOrientation()
	local dy = (y1 - y0 + math.pi) % (2 * math.pi) - math.pi
	if dir and math.abs(math.abs(dy) - math.pi) < 0.2 then
		dy = dir * math.abs(dy)
	end
	return CFrame.Angles(0, y0 + dy * t, 0)
end

-- Ankle pitch that lays the feet along the sloped deck / floor for a facing.
local function footSlope(n: NoseFrame, facing: CFrame): number
	return n.slope * facing.LookVector:Dot(-n.forward)
end

local function standPose(n: NoseFrame, pos: Vector3): Pose
	local p = pose(pos, 0.12, 0.08, 0, 0.25, 0.3, 0.1, 0.2, 0)
	p.foot = n.slope
	return p
end

-- Boarding, t seconds after the approach walk.
local function animateNoseBoard(a: Actor, n: NoseFrame, t: number)
	local inward = facingIn(n)
	local function toLocal(v: Vector3): Vector3
		return n.cf:PointToObjectSpace(v)
	end
	local tipL, deckL = toLocal(n.tip), toLocal(n.deckFront)
	local gy = a.floorY + a.stand - n.cf.Position.Y -- standing on the pad (frame height)
	-- 1) mantle onto the nose: crouch and reach, spring up and grab the
	-- handles, right knee onto the tip, left leg up, stand on the deck
	if t < TB.Mantle then
		local u = t / TB.Mantle
		local keys: { Key } = {
			{ u = 0.2, p = pose(Vector3.new(0, gy - 0.4, 0.3), 0.3, 0.35, 0.45, 0.75, 1.35, 0.75, 1.35, 0.85) }, -- crouch, reach
			{ u = 0.4, p = pose(Vector3.new(0, gy + 0.6, 0.5), 0.25, 0.15, 0.35, 0.45, 0.7, 0.95, 1.7, 1) }, -- spring up, grab
			{ u = 0.62, p = pose(tipL + Vector3.new(0, 2.9, 0.9), 0.55, 0.45, 0.25, 0.35, 0.7, 1.75, 2.1, 1) }, -- right knee on the tip
			{ u = 0.82, p = pose(deckL + Vector3.new(0, 2.1, 1.7), 0.4, 0.35, 0.1, 1.5, 2.3, 1.5, 2.3, 0.55) }, -- kneeling on the nose
			{ u = 1.0, p = standPose(n, deckL + Vector3.new(0, a.stand + SLOPE_LIFT, 0)) },
		}
		keys[4].p.foot = n.slope * 0.5
		local p: Pose
		local facing = inward
		if u < keys[1].u then
			-- from wherever the approach walk ended
			local k = smooth(u / keys[1].u)
			p = blendPose(pose(toLocal(a.start.Position), 0, 0, 0, 0, 0, 0, 0, 0), keys[1].p, k)
			facing = yawBlend(a.start, inward, k)
		else
			p = keys[1].p
			for i = 2, #keys do
				local k0, k1 = keys[i - 1], keys[i]
				if u <= k1.u or i == #keys then
					p = blendPose(k0.p, k1.p, smooth((u - k0.u) / (k1.u - k0.u)))
					break
				end
			end
		end
		if u >= 0.4 then
			cue(a, "grab", "ClimbGrab", 0.9, 1.15, 0.8)
		end
		if u >= 0.62 then
			cue(a, "knee", "ClimbGrab", 0.45, 1.5, 0.5)
		end
		applyAt(a, CFrame.new(n.cf * p.pos) * facing * CFrame.Angles(-p.lean, 0, 0), p, n.grips)
		return
	end
	t -= TB.Mantle
	-- 2) up the deck and over the sill into the cockpit
	if t < TB.DeckWalk then
		local w = t / TB.DeckWalk
		local pts = cockpitPath(a, n)
		local _, total = along(pts, 0)
		local d = total * smooth(w)
		local pos = along(pts, d)
		-- high knees over the dashboard
		local dash = (pts[2] - pts[1]).Magnitude + (pts[3] - pts[2]).Magnitude
		local overSill = math.clamp(1 - math.abs(d - dash) / 1.4, 0, 1)
		local p = walkPose(Vector3.zero, d, 0.15, 0.25 + 0.8 * overSill)
		p.foot = n.slope
		p = blendPose(standPose(n, Vector3.zero), p, smooth(w / 0.2))
		applyAt(a, CFrame.new(pos) * inward * CFrame.Angles(-p.lean, 0, 0), p, nil)
		return
	end
	t -= TB.DeckWalk
	local standPos = n.floor + Vector3.new(0, a.stand + SLOPE_LIFT, 0)
	-- 3) turn round in front of the seat: two small steps
	if t < TB.Turn then
		local w = t / TB.Turn
		local facing = yawBlend(inward, facingOut(n), smooth(w), 1)
		local s = math.sin(w * math.pi * 2)
		local p = pose(Vector3.zero, 0.03, 0.05, 0, 0.35 * math.max(0, s), 0.2 + 0.6 * math.max(0, s), 0.35 * math.max(0, -s), 0.2 + 0.6 * math.max(0, -s), 0)
		p.foot = footSlope(n, facing)
		applyAt(a, CFrame.new(standPos) * facing, p, nil)
		return
	end
	t -= TB.Turn
	-- 4) sit down: bend, lower back into the seat
	local sitU = math.clamp(t / TB.SitDown, 0, 1)
	local stand = pose(Vector3.zero, 0.03, 0.05, 0, 0, 0.2, 0, 0.2, 0)
	stand.foot = -n.slope
	local mid = pose(Vector3.zero, 0.35, 0.3, 0.1, 1.2, 1.5, 1.2, 1.5, 0)
	mid.foot = 0.3
	mid.armLift = 0.35
	local p = if sitU < 0.5 then blendPose(stand, mid, smooth(sitU / 0.5)) else blendPose(mid, seatedPose(), smooth((sitU - 0.5) / 0.5))
	local cf = (CFrame.new(standPos) * facingOut(n)):Lerp(seatedCF(a, n), smooth(sitU))
	applyAt(a, cf * CFrame.Angles(-p.lean, 0, 0), p, nil)
end

-- Exit, x seconds after the server unseated the pilot.
local function animateNoseExit(a: Actor, n: NoseFrame, x: number)
	local outward = facingOut(n)
	local standPos = n.floor + Vector3.new(0, a.stand + SLOPE_LIFT, 0)
	-- 1) stand up out of the seat
	if x < TX.StandUp then
		local u = x / TX.StandUp
		local stand = pose(Vector3.zero, 0.05, 0.05, 0, 0.1, 0.2, 0.1, 0.2, 0)
		stand.foot = -n.slope
		local mid = pose(Vector3.zero, 0.4, 0.3, 0.1, 1.2, 1.5, 1.2, 1.5, 0)
		mid.foot = 0.3
		mid.armLift = 0.3
		local p = if u < 0.45 then blendPose(seatedPose(), mid, smooth(u / 0.45)) else blendPose(mid, stand, smooth((u - 0.45) / 0.55))
		local cf = seatedCF(a, n):Lerp(CFrame.new(standPos) * outward, smooth(u))
		applyAt(a, cf * CFrame.Angles(-p.lean, 0, 0), p, nil)
		return
	end
	x -= TX.StandUp
	local deckStand = n.deckFront + Vector3.new(0, a.stand + SLOPE_LIFT, 0)
	-- 2) over the sill and down the deck, facing out (downhill)
	if x < TX.DeckDown then
		local w = x / TX.DeckDown
		local pts = cockpitPath(a, n)
		local rev = { pts[4], pts[3], pts[2], pts[1] }
		local _, total = along(rev, 0)
		local d = total * smooth(w)
		local pos = along(rev, d)
		local overSill = math.clamp(1 - math.abs(d - (rev[2] - rev[1]).Magnitude) / 1.2, 0, 1)
		local p = walkPose(Vector3.zero, d, -0.05, 0.1 + 0.9 * overSill)
		p.foot = -n.slope
		-- going downhill the trailing foot is the low one: walk a little higher
		pos += Vector3.new(0, 0.25 * math.clamp((d - (rev[3] - rev[1]).Magnitude) / 1.5, 0, 1), 0)
		applyAt(a, CFrame.new(pos) * outward * CFrame.Angles(-p.lean, 0, 0), p, nil)
		return
	end
	x -= TX.DeckDown
	local landing = Vector3.new(n.cf.Position.X, a.floorY + a.stand, n.cf.Position.Z) + n.forward * 1.2
	-- 3) hop off the nose tip: a little up, then down onto the pad
	if x < TX.Hop then
		local h = x / TX.Hop
		local pos = deckStand:Lerp(landing, h) + Vector3.new(0, 4 * 0.9 * h * (1 - h), 0)
		local tuck = math.sin(math.pi * h)
		local p = pose(Vector3.zero, 0.1, 0.1, 0.1, 0.3 + 0.7 * tuck, 0.3 + 1.1 * tuck, 0.2 + 0.6 * tuck, 0.3 + 1.0 * tuck, 0)
		p.armLift = 0.9 + 0.4 * tuck
		p.foot = -n.slope * (1 - smooth(h / 0.4))
		applyAt(a, CFrame.new(pos) * outward * CFrame.Angles(-p.lean, 0, 0), p, nil)
		return
	end
	x -= TX.Hop
	cue(a, "land", "ClimbLand", 0.8, 1.1, 1)
	-- landing squash: quick down, slower recovery
	local l = x / TX.Land
	local s = if l < 0.25 then smooth(l / 0.25) else 1 - smooth((l - 0.25) / 0.75)
	local p = pose(Vector3.zero, 0.15 * s, 0.35 * s, -0.1 * s, 0.3 + 0.9 * s, 0.3 + 1.6 * s, 0.2 + 0.9 * s, 0.3 + 1.6 * s, 0)
	local rec = smooth(l / 0.2)
	p.hipL, p.kneeL = lerp(0.3, p.hipL, rec), lerp(0.3, p.kneeL, rec)
	p.hipR, p.kneeR = lerp(0.2, p.hipR, rec), lerp(0.3, p.kneeR, rec)
	p.armLift = 0.9 * (1 - smooth(l)) + 0.5 * s
	applyAt(a, CFrame.new(landing - Vector3.new(0, 0.9 * s, 0)) * outward * CFrame.Angles(-p.lean, 0, 0), p, nil)
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

-- Which climb (if any) runs on `model` right now: "board" / "exit", and the
-- sequence time for it.
local function activeClimb(model: Model): (string?, number)
	local state = model:GetAttribute("PowerState")
	local tau = MechPose.stateTime(model)
	if MechTypes.idOf(model) == "Type99" then
		if state == "Boarding" then
			local t = tau - Type99Pose.boardWalk(model)
			if t >= 0 and t < TB.Sit + T99_HOLD then
				return "board", t
			end
		elseif state == "PoweringDown" then
			local x = tau - TX.Unseat
			if x >= 0 and x < TX.StandUp + TX.DeckDown + TX.Hop + TX.Land then
				return "exit", x
			end
		end
		return nil, 0
	end
	if MechPose.style(model) ~= "OneKnee" then
		return nil, 0
	end
	if state == "Boarding" then
		local walkEnd = MechPose.boardWalk(model)
		if tau >= walkEnd - C.Climb - C.RampWalk and tau < walkEnd then
			return "board", tau
		end
	elseif state == "PoweringDown" then
		local x = MechPose.revealTime(model) - X.Stand
		if x >= 0 and x < C.RampDown + C.Hop + C.Land then
			return "exit", x
		end
	end
	return nil, 0
end

local function step()
	for _, inst in CollectionService:GetTagged("Mech") do
		if not inst:IsA("Model") or not inst.Parent then
			continue
		end
		local model = inst :: Model
		local key = tostring(model:GetAttribute("PowerState")) .. tostring(model:GetAttribute("PowerTime"))
		local kind, time = activeClimb(model)
		local a = actors[model]
		local char, hrp, hum
		if kind then
			char, hrp, hum = pilotOf(model)
		end
		if a and (not kind or a.key ~= key or a.char ~= char) then
			release(model)
			a = nil
		end
		if not (kind and char and hrp and hum) then
			continue
		end
		if MechTypes.idOf(model) == "Type99" then
			local n = noseFrame(model)
			if not n then
				continue
			end
			if not a then
				a = makeActor(model, char, hrp, hum, key, n.cf.Position + n.forward, n.cf.Position.Y)
				actors[model] = a
			end
			local actor = a :: Actor
			actor.hrp.Anchored = true
			if kind == "board" then
				animateNoseBoard(actor, n, time)
			else
				animateNoseExit(actor, n, time)
			end
			continue
		end
		local f = lipFrame(model)
		if not f then
			continue
		end
		if not a then
			a = makeActor(model, char, hrp, hum, key, f.points.foot + f.points.forward, f.points.ground)
			actors[model] = a
		end
		local actor = a :: Actor
		actor.hrp.Anchored = true
		if kind == "board" then
			animateBoard(actor, f, time, MechPose.boardWalk(model))
		else
			animateExit(actor, f, time)
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
