--!strict
-- Client animator for WTK-99 ("Type99") walkers. Runs on every client from
-- replicated state only (root velocity, "PowerState" / "PowerTime"), so
-- everyone sees and hears every walker the same way.
--
-- Gait: foot-placement IK. Each foot is either planted (a fixed world
-- anchor) or swinging (an arc from where it lifted to a landing spot
-- predicted from the root's velocity: half a stance ahead of the foot's
-- neutral spot). A gait phase driven by distance travelled decides when
-- each foot lifts; when standing still, feet that are off their neutral spot
-- take settle steps. Every frame the pelvis frame is built (bob, sway,
-- squat, fold) and both legs are solved to their foot targets with
-- Type99Pose.legIK plus a hip roll for sideways reach, so planted feet stay
-- put in the world.
--
-- Also: power-state fold / canopy / lights (Type99Pose.powerTargets), hull
-- motion (bob, roll over the stance leg, pitch on acceleration, turn bank,
-- yaw sway), weapon lag springs, jump windup / air tuck / landing recoil,
-- idle look-around and system checks while piloted, footstep and servo sounds.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechBuilder = require(Shared:WaitForChild("MechBuilder"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechPose = require(Shared:WaitForChild("MechPose"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local Type99Builder = require(Shared:WaitForChild("Type99Builder"))
local Type99Pose = require(Shared:WaitForChild("Type99Pose"))

local Type99Animator = {}

local A = MechConfig.Type99Anim
local S = Type99Builder.Scale
local LEGS = Type99Builder.Legs
local TAU = math.pi * 2
local LIGHT_DIM = 0.12 -- light brightness while off
local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local SIDES = { "Left", "Right" }

local ROOT_HEIGHT = Type99Builder.RootHeight
local REST_ROOT = Type99Builder.restFrame("HumanoidRootPart")
local ANKLE_H = Type99Builder.restFrame("LeftFoot").Y -- ankle above the sole
local TOE = Vector3.new(0, -ANKLE_H, -2.3 * S) -- heel-peel pivot (foot frame)
local OFF_DROP = Type99Builder.OffDrop

-- gait
local MOVE_ON, MOVE_OFF = 1.5, 0.8 -- studs/s hysteresis between stepping and settling
local SETTLE_DIST, SETTLE_YAW = 1.3, 0.3 -- foot off its neutral spot by this much -> step
local SETTLE_DUR, SETTLE_LIFT = 0.5, 1.5
local BOB_WALK, BOB_SPRINT = 8, 15 -- footfall dip impulse (studs/s)
-- walk = a waddle: the body shifts well over each stance foot and rolls with
-- it, toes splayed out; the run tightens it up and pitches forward
local SWAY_WALK, SWAY_RUN = 0.95, 0.3 -- pelvis shift over the stance foot (studs)
local ROLL_WALK, ROLL_RUN = 0.065, 0.025 -- hull roll over the stance leg
local WADDLE_YAW = 0.06 -- hull twists toward the swinging leg
local TOE_SPLAY = 0.2 -- feet planted toes-out (radians)
local RUN_BACK = 1.6 -- running stance centers this far back (studs), for reach
local RUN_PITCH = 0.15 -- nose-down when running

-- jumping: root velocity + a ray to the ground (Humanoid states don't replicate)
local GROUND_TOL = 1.5
local COMP_W, COMP_Z = 9, 0.42 -- squat spring (in fold units, 1 = the full sit)
local LAND_COMP = 0.0055 -- squat velocity per stud/s of impact
local MAX_COMP = 0.5
local TUCK_RISE = Vector3.new(0, -8.6, 1.2) -- hip -> ankle while rising (legs folded up)
local TUCK_FALL = Vector3.new(0, -12.6, -2.2) -- falling: legs reach down and forward

type Foot = {
	side: string,
	hip: Vector3, -- hip position in the pelvis frame
	neutral: Vector3, -- rest ankle in root space
	splay: number, -- toes-out yaw offset
	planted: boolean,
	anchor: Vector3, -- world ankle position while planted (foot flat)
	yaw: number,
	from: Vector3, -- swing start (world ankle)
	fromYaw: number,
	fromPitch: number,
	t: number, -- swing progress 0..1
	dur: number,
	lift: number,
	pitchAmp: number,
	pending: boolean, -- the gait wants this foot to lift
	target: Vector3, -- latest swing landing spot
	targetYaw: number,
	cur: Vector3, -- last solved ankle target (world)
	pitch: number, -- last foot pitch
	sound: Sound?,
	thud: Sound?,
}

type Cue = { at: number, sound: string, volume: number, speed: number, stop: number? }

type State = {
	root: BasePart,
	motors: { [string]: Motor6D },
	feet: { [string]: Foot },
	rayParams: RaycastParams,
	fold: number,
	canopy: number,
	power: number,
	lights: { BasePart }?,
	appliedPower: number,
	moving: boolean,
	phase: number,
	amount: number, -- walk blend 0..1
	sprint: number, -- sprint blend 0..1
	fwdSpeed: number,
	accel: number, -- smoothed forward acceleration
	yawRate: number,
	dip: number, -- footfall dip spring (studs)
	dipV: number,
	sway: number, -- pelvis shift toward the stance foot (studs)
	pitch: number, -- hull pitch spring (radians)
	pitchV: number,
	bank: number,
	rail: number, -- railgun pitch lag spring
	railV: number,
	pod: number, -- missile pod pitch lag spring
	podV: number,
	gunYaw: number, -- weapons lag behind turns
	airborne: boolean,
	airTime: number,
	fallSpeed: number,
	air: number,
	comp: number, -- squat spring (fold units)
	compV: number,
	idleT: number,
	idleClock: number, -- held while fading out
	idleBlend: number,
	idleStepCycle: number, -- last idle cycle that took its step in place
	servo: Sound,
	sounds: { [string]: Sound },
	tokens: { [string]: number },
	cueKey: string,
	cueT: number,
}

local states: { [Model]: State } = {}
local stepListeners: { (model: Model, side: string, strength: number) -> () } = {}
local landListeners: { (model: Model, impact: number) -> () } = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function angleDiff(a: number, b: number): number
	return (b - a + math.pi) % TAU - math.pi
end

local function yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- One step of a damped spring toward `target` (semi-implicit Euler).
local function spring(x: number, v: number, target: number, w: number, z: number, dt: number): (number, number)
	v += (w * w * (target - x) - 2 * z * w * v) * dt
	return x + v * dt, v
end

local function makeSound(parent: Instance, id: string, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = 200
	s.Parent = parent
	return s
end

local function play(st: State, key: string, volume: number, speed: number, stopAfter: number?)
	local sound = st.sounds[key]
	if not sound then
		return
	end
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.TimePosition = 0
	sound:Play()
	if stopAfter then
		local token = (st.tokens[key] or 0) + 1
		st.tokens[key] = token
		task.delay(stopAfter, function()
			if st.tokens[key] == token then
				sound:Stop()
			end
		end)
	end
end

-- Power-state sound cues, seconds from the state's start (boarding: from
-- the end of the approach walk, see playCues).
local TB, TX = MechConfig.Type99Boarding, MechConfig.Type99Exit
local CUES: { [string]: { Cue } } = {
	Boarding = {
		{ at = TB.CanopyCloseStart, sound = "Hiss", volume = 0.6, speed = 1.1, stop = 0.5 },
		{ at = TB.CanopyCloseEnd - 0.05, sound = "Clunk", volume = 1, speed = 0.85 },
		{ at = TB.PowerUp, sound = "PowerUp", volume = 0.8, speed = 0.9 },
		{ at = TB.StandStart, sound = "StandUp", volume = 1, speed = 0.85 },
		{ at = TB.StandEnd - 0.05, sound = "Stomp", volume = 1, speed = 0.75 },
	},
	PoweringDown = {
		{ at = 0, sound = "PowerDown", volume = 0.9, speed = 0.75 },
		{ at = 0.05, sound = "Hydraulic", volume = 0.8, speed = 0.8 },
		{ at = TX.FoldEnd - 0.05, sound = "Stomp", volume = 0.8, speed = 0.9 },
		{ at = TX.CanopyOpenStart, sound = "Hiss", volume = 0.6, speed = 1.2, stop = 0.6 },
	},
}

local function stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

local function playCues(model: Model, st: State)
	local state = model:GetAttribute("PowerState")
	local key = tostring(state) .. tostring(model:GetAttribute("PowerTime"))
	local t = stateTime(model)
	if state == "Boarding" then
		t -= Type99Pose.boardWalk(model)
	end
	if key ~= st.cueKey then
		st.cueKey = key
		-- joining mid-sequence: skip cues that already went by
		st.cueT = if t < 0.3 then -1 else t
	end
	local cues = if typeof(state) == "string" then CUES[state] else nil
	if cues then
		for _, cue in cues do
			if st.cueT < cue.at and t >= cue.at then
				play(st, cue.sound, cue.volume, cue.speed, cue.stop)
			end
		end
	end
	st.cueT = t
end

local function setup(model: Model)
	if states[model] or MechTypes.idOf(model) ~= "Type99" then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root or not model.Parent then
		return
	end
	local motors = MechPose.motors(model)
	if not (motors.Root and motors.LeftHip and motors.RightHip) then
		return
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	rayParams.CollisionGroup = MechBuilder.RootGroup
	rayParams.RespectCanCollide = true

	local feet: { [string]: Foot } = {}
	for _, side in SIDES do
		local ankle = REST_ROOT:PointToObjectSpace(Type99Builder.restFrame(side .. "Foot").Position)
		local world = root.CFrame:PointToWorldSpace(ankle)
		local footPart = model:FindFirstChild(side .. "Foot")
		feet[side] = {
			side = side,
			hip = motors[side .. "Hip"].C0.Position,
			neutral = ankle,
			splay = if side == "Right" then -TOE_SPLAY else TOE_SPLAY,
			planted = true,
			anchor = world,
			yaw = yawOf(root.CFrame) + (if side == "Right" then -TOE_SPLAY else TOE_SPLAY),
			from = world,
			fromYaw = 0,
			fromPitch = 0,
			t = 0,
			dur = 0.5,
			lift = 0,
			pitchAmp = 0,
			pending = false,
			target = world,
			targetYaw = 0,
			cur = world,
			pitch = 0,
			sound = if footPart then makeSound(footPart, A.Sounds.Step, 1, false) else nil,
			thud = if footPart then makeSound(footPart, A.Sounds.StepThud, 0.5, false) else nil,
		}
	end

	local hull = model:FindFirstChild("Hull") or root
	local sounds: { [string]: Sound } = {}
	local ids: { [string]: string } = {
		Clunk = MechConfig.Sounds.Clunk,
		Hiss = MechConfig.Sounds.Hiss,
		PowerUp = MechConfig.Sounds.PowerUp,
		PowerDown = MechConfig.Sounds.PowerDown,
		Hydraulic = MechConfig.Sounds.Hydraulic,
		StandUp = MechConfig.Sounds.StandUp,
		Stomp = MechConfig.Sounds.Stomp,
		Whoosh = MechConfig.Sounds.Whoosh,
		LandImpact = MechConfig.Sounds.LandImpact,
		LandMetal = MechConfig.Sounds.LandMetal,
		Lift = A.Sounds.Lift,
	}
	for key, id in ids do
		sounds[key] = makeSound(hull, id, 1, false)
	end
	local servo = makeSound(hull, A.Sounds.Servo, 0, true)
	servo:Play()

	local fold, canopy, power = Type99Pose.powerTargets(model)
	local st: State = {
		root = root,
		motors = motors,
		feet = feet,
		rayParams = rayParams,
		fold = fold,
		canopy = canopy,
		power = power,
		lights = nil,
		appliedPower = -1,
		moving = false,
		phase = 0,
		amount = 0,
		sprint = 0,
		fwdSpeed = 0,
		accel = 0,
		yawRate = 0,
		dip = 0,
		dipV = 0,
		sway = 0,
		pitch = 0,
		pitchV = 0,
		bank = 0,
		rail = 0,
		railV = 0,
		pod = 0,
		podV = 0,
		gunYaw = 0,
		airborne = false,
		airTime = 0,
		fallSpeed = 0,
		air = 0,
		comp = 0,
		compV = 0,
		idleT = 0,
		idleClock = 0,
		idleBlend = 0,
		idleStepCycle = -1,
		servo = servo,
		sounds = sounds,
		tokens = {},
		cueKey = "",
		cueT = 0,
	}
	states[model] = st
	-- armor swaps rebuild the light parts
	for _, name in ARMOR_FOLDERS do
		local folder = model:FindFirstChild(name)
		if folder then
			folder.ChildAdded:Connect(function()
				st.lights = nil
			end)
		end
	end
	model.Destroying:Connect(function()
		states[model] = nil
	end)
end

-- Dims the Neon lights and screens toward LIGHT_DIM while powered down.
local function applyLights(model: Model, st: State)
	local lights = st.lights
	if not lights then
		local found = {}
		for _, name in ARMOR_FOLDERS do
			local folder = model:FindFirstChild(name)
			if folder then
				for _, d in folder:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("MechLight") then
						table.insert(found, d)
					end
				end
			end
		end
		lights = found
		st.lights = found
		st.appliedPower = -1
	end
	if math.abs(st.power - st.appliedPower) < 0.004 then
		return
	end
	st.appliedPower = st.power
	local k = lerp(LIGHT_DIM, 1, st.power)
	for _, part in lights :: { BasePart } do
		local lit = part:GetAttribute("LitColor")
		if typeof(lit) ~= "Color3" then
			lit = part.Color
			part:SetAttribute("LitColor", lit)
		end
		local c = lit :: Color3
		part.Color = Color3.new(c.R * k, c.G * k, c.B * k)
	end
end

local function groundY(st: State, pos: Vector3, fallback: number): number
	local hit = workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), st.rayParams)
	return if hit then hit.Position.Y else fallback
end

-- Takeoff / landing from the root's vertical velocity and a ground ray.
local function updateJump(model: Model, st: State, dt: number)
	local root = st.root
	if root.Anchored then
		st.airborne, st.airTime = false, 0
		return
	end
	local vy = root.AssemblyLinearVelocity.Y
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(ROOT_HEIGHT + 8), 0), st.rayParams)
	local gap = if hit then root.Position.Y - hit.Position.Y - ROOT_HEIGHT else math.huge
	local grounded = gap < GROUND_TOL and vy < 10
	if not st.airborne then
		if not grounded then
			st.airborne, st.airTime, st.fallSpeed = true, 0, 0
			for _, foot in st.feet do
				foot.pending = false
			end
			if vy > 20 then
				-- takeoff: legs kick straight, hydraulics fire
				st.compV -= 2.2
				st.railV -= 1.2
				st.podV -= 1.6
				play(st, "Whoosh", 0.9, 0.65 + math.random() * 0.1)
				play(st, "Hydraulic", 0.9, 1.25)
				play(st, "Hiss", 0.7, 1.05, 0.4)
			end
		end
		return
	end
	st.airTime += dt
	st.fallSpeed = math.max(st.fallSpeed, -vy)
	if not grounded then
		return
	end
	st.airborne = false
	-- feet come down where they are
	local ground = root.Position.Y - ROOT_HEIGHT
	local yaw = yawOf(root.CFrame)
	for _, foot in st.feet do
		foot.planted = true
		foot.anchor = Vector3.new(foot.cur.X, ground + ANKLE_H, foot.cur.Z)
		foot.yaw = yaw + foot.splay
	end
	local impact = st.fallSpeed
	if impact < 14 or st.airTime < 0.12 then
		return -- a step down, not a jump
	end
	-- landing: the legs absorb, the hull dips nose-down, the weapons keep going
	local k = math.min(impact, 120)
	st.compV += k * LAND_COMP * 10
	st.pitchV -= k * 0.02
	st.railV -= k * 0.022
	st.podV -= k * 0.03
	st.dipV -= k * 0.08
	local vol = math.clamp(impact / 80, 0.3, 1.3)
	play(st, "LandImpact", 1.4 * vol, 0.8 + math.random() * 0.08)
	play(st, "LandMetal", 0.9 * vol, 0.7 + math.random() * 0.08)
	play(st, "Stomp", 1.2 * vol, 0.7)
	play(st, "Hydraulic", 0.7 * vol, 1.1, 0.8)
	for _, fn in landListeners do
		task.spawn(fn, model, impact)
	end
end

-- Idle routine (seconds since standing still while online): hull looks
-- around, missile pod runs a system check, railgun lifts and settles, weight
-- shifts from leg to leg with a step in place, the chin sensor twitches.
local IDLE_DELAY = 1.5
local IDLE_CYCLE = 17
-- (time, hull yaw, hull pitch); negative yaw looks to the mech's right
local IDLE_LOOK = {
	{ 0, 0, 0 },
	{ 1.0, 0, 0 },
	{ 2.6, -0.42, -0.04 },
	{ 4.6, -0.42, -0.04 },
	{ 5.9, 0.04, 0.02 },
	{ 7.2, 0.04, 0.02 },
	{ 8.6, 0.36, -0.02 },
	{ 10.4, 0.36, -0.02 },
	{ 11.8, 0, 0 },
	{ 17, 0, 0 },
}
local POD_CHECK, RAIL_CHECK, STEP_AT = 5.2, 12.2, 15.0

local function keyed(t: number): (number, number)
	for i = 1, #IDLE_LOOK - 1 do
		local k0, k1 = IDLE_LOOK[i], IDLE_LOOK[i + 1]
		if t <= k1[1] then
			local u = smooth((t - k0[1]) / (k1[1] - k0[1]))
			return lerp(k0[2], k1[2], u), lerp(k0[3], k1[3], u)
		end
	end
	return 0, 0
end

type Idle = { yaw: number, pitch: number, sway: number, podPitch: number, podYaw: number, rail: number, chin: number }

local function idlePose(t: number): Idle
	local out: Idle = { yaw = 0, pitch = 0, sway = 0, podPitch = 0, podYaw = 0, rail = 0, chin = 0 }
	if t < IDLE_DELAY then
		return out
	end
	t = (t - IDLE_DELAY) % IDLE_CYCLE
	out.yaw, out.pitch = keyed(t)
	-- weight shift: onto the right leg, back, onto the left, back
	out.sway = 0.55 * math.sin(TAU * t / IDLE_CYCLE) * smooth(t / 1.5)
	-- missile pod system check: tilts up, three quick twitches, drops back with a bounce
	local u = t - POD_CHECK
	if u > 0 and u < 2.4 then
		local up = smooth(u / 0.35) * (1 - smooth((u - 1.5) / 0.5))
		local settle = if u > 1.5 then math.sin((u - 1.5) * 14) * math.exp(-(u - 1.5) * 5) * 0.05 else 0
		out.podPitch = 0.2 * up - settle
		if u > 0.5 and u < 1.35 then
			out.podYaw = 0.05 * math.sign(math.sin((u - 0.5) * TAU * 3.5))
		end
	end
	-- railgun raises, holds, settles back with a slight overshoot
	u = t - RAIL_CHECK
	if u > 0 and u < 3.6 then
		local up = smooth(u / 0.9)
		local down = smooth((u - 2.2) / 0.6)
		local bounce = if u > 2.8 then -math.sin((u - 2.8) * 10) * math.exp(-(u - 2.8) * 5) * 0.03 else 0
		out.rail = 0.15 * up * (1 - down) + bounce
	end
	-- chin sensor: quick twitches, hold, snap back
	for _, at in { 2.2, 9.1 } do
		local v = t - at
		if v > 0 and v < 1.4 then
			local dir = if at < 5 then 1 else -1
			out.chin += dir * 0.14 * (smooth(v / 0.08) - smooth((v - 1.1) / 0.12))
		end
	end
	return out
end

-- Neutral ankle spot of a foot for a root frame (world, foot flat on the ground).
local function neutralOf(foot: Foot, rootCF: CFrame): Vector3
	return rootCF:PointToWorldSpace(foot.neutral)
end

local function startSwing(st: State, foot: Foot, dur: number, lift: number, pitchAmp: number)
	foot.planted = false
	foot.pending = false
	foot.t = 0
	foot.dur = dur
	foot.lift = lift
	foot.pitchAmp = pitchAmp
	foot.from = foot.cur
	foot.fromYaw = foot.yaw
	foot.fromPitch = foot.pitch
	if st.amount > 0.3 then
		play(st, "Lift", 0.12 + 0.12 * st.sprint, 1.5 + math.random() * 0.2, 0.25)
	end
end

local function other(st: State, foot: Foot): Foot
	return st.feet[if foot.side == "Left" then "Right" else "Left"]
end

-- Foot plant: sound, dip, weapon kicks, listeners.
local function plant(model: Model, st: State, foot: Foot)
	foot.planted = true
	foot.anchor = foot.target
	foot.yaw = foot.targetYaw
	local a, r = st.amount, st.sprint * st.amount
	local strength = math.clamp(0.35 + 0.65 * a, 0.35, 1) * (1 + 0.5 * r)
	st.dipV -= lerp(BOB_WALK, BOB_SPRINT, st.sprint) * math.max(0.3, a)
	st.railV -= 0.35 * strength
	st.podV -= 0.5 * strength
	st.pitchV -= 0.05 * strength
	local sound, thud = foot.sound, foot.thud
	if sound then
		sound.Volume = 0.75 + 0.45 * strength
		sound.PlaybackSpeed = 0.66 + math.random() * 0.1 + r * 0.08
		sound.TimePosition = 0
		sound:Play()
	end
	if thud and a > 0.2 then
		thud.Volume = 0.25 + 0.35 * strength
		thud.PlaybackSpeed = 0.62 + math.random() * 0.08
		thud.TimePosition = 0
		thud:Play()
	end
	for _, fn in stepListeners do
		task.spawn(fn, model, foot.side, 0.3 + 0.3 * strength)
	end
end

local function set(m: { [string]: Motor6D }, name: string, cf: CFrame)
	local motor = m[name]
	if motor then
		motor.Transform = cf
	end
end

-- Solves one leg so its ankle reaches `footCF` (world; the foot takes its
-- orientation). Hip roll takes the sideways offset, the zig-zag leg IK the rest.
local REST = LEGS.rest
local function solveLeg(m: { [string]: Motor6D }, side: string, pelvisCF: CFrame, hip: Vector3, footCF: CFrame)
	local v = pelvisCF:VectorToObjectSpace(footCF.Position - pelvisCF:PointToWorldSpace(hip))
	local roll = math.clamp(math.atan2(v.X, -v.Y), -0.45, 0.45)
	local c, s = math.cos(roll), math.sin(roll)
	local y = -v.X * s + v.Y * c -- v rotated by -roll about Z
	local p1, p2, p3 = Type99Pose.legIK(Vector3.new(0, y, v.Z))
	local rz = CFrame.Angles(0, 0, roll)
	set(m, side .. "Hip", CFrame.Angles(-REST[1], 0, 0) * rz * CFrame.Angles(p1, 0, 0))
	set(m, side .. "MidJoint", CFrame.Angles((p2 - p1) - (REST[2] - REST[1]), 0, 0))
	set(m, side .. "Knee", CFrame.Angles((p3 - p2) - (REST[3] - REST[2]), 0, 0))
	local lowerRot = rz * CFrame.Angles(p3, 0, 0) * CFrame.Angles(-REST[3], 0, 0)
	set(m, side .. "Ankle", lowerRot:Inverse() * (pelvisCF.Rotation:Inverse() * footCF.Rotation))
end

local function stepMech(model: Model, st: State, dt: number)
	local fold, canopy, power, timed = Type99Pose.powerTargets(model)
	if timed then
		st.fold, st.canopy, st.power = fold, canopy, power
	else
		local k = math.min(1, dt * 2.5)
		st.fold += (fold - st.fold) * k
		st.canopy += (canopy - st.canopy) * k
		st.power += (power - st.power) * k
	end
	applyLights(model, st)
	playCues(model, st)

	local state = model:GetAttribute("PowerState")
	local online = state == "Online"
	local root = st.root
	local sdt = math.min(dt, 1 / 30)

	-- root where physics is about to put it this frame
	local rootCF = root.CFrame
	local vel, yawRate = Vector3.zero, 0
	if not root.Anchored then
		vel = root.AssemblyLinearVelocity
		yawRate = root.AssemblyAngularVelocity.Y
		rootCF = (rootCF + vel * dt) * CFrame.Angles(0, yawRate * dt, 0)
	end
	local vh = flat(vel)
	local speed = vh.Magnitude
	local look = rootCF.LookVector
	local fwd = vh:Dot(flat(look))
	st.accel += ((fwd - st.fwdSpeed) / math.max(dt, 1e-3) - st.accel) * math.min(1, dt * 6)
	st.fwdSpeed = fwd
	st.yawRate += (yawRate - st.yawRate) * math.min(1, dt * 8)

	updateJump(model, st, dt)
	st.air += ((if st.airborne then 1 else 0) - st.air) * math.min(1, sdt * (if st.airborne then 10 else 20))

	-- gait blends and parameters
	st.amount += (math.clamp(speed / A.WalkSpeed, 0, 1) - st.amount) * math.min(1, dt * 5)
	st.sprint += (math.clamp((speed - A.WalkSpeed) / (A.SprintSpeed - A.WalkSpeed), 0, 1) - st.sprint) * math.min(1, dt * 3)
	local duty = lerp(A.WalkDuty, A.SprintDuty, st.sprint)
	local stance = lerp(A.WalkStance, A.SprintStance, st.sprint) * math.clamp(0.35 + 0.65 * speed / A.WalkSpeed, 0.35, 1)
	local stride = stance / duty
	local liftH = lerp(A.WalkLift, A.SprintLift, st.sprint)
	local dir = if speed > 1e-3 then vh / speed else flat(look).Unit
	local ground = rootCF.Y - ROOT_HEIGHT
	local rootYaw = yawOf(rootCF)
	local L, R = st.feet.Left, st.feet.Right

	-- teleported (or streamed in somewhere new): feet go straight to their spots
	if (L.cur - neutralOf(L, rootCF)).Magnitude > 30 or (R.cur - neutralOf(R, rootCF)).Magnitude > 30 then
		for _, foot in st.feet do
			foot.planted, foot.pending = true, false
			foot.anchor = neutralOf(foot, rootCF)
			foot.yaw = rootYaw + foot.splay
			foot.cur = foot.anchor
		end
	end

	if state == "Off" or state == "Boarding" or (state == "PoweringDown" and st.fold > 0.15) then
		-- sat down / standing up on the spot: feet ease onto their neutral spots
		st.moving = false
		for _, foot in st.feet do
			if foot.planted then
				local n = neutralOf(foot, rootCF)
				local k = if state == "Off" then 1 else math.min(1, dt * 8)
				foot.anchor = foot.anchor:Lerp(n, k)
				foot.yaw += angleDiff(foot.yaw, rootYaw + foot.splay) * k
			end
		end
	elseif not st.airborne then
		local wasMoving = st.moving
		st.moving = if st.moving then speed > MOVE_OFF else speed > MOVE_ON
		if st.moving then
			if not wasMoving then
				-- first step with the foot that is furthest behind
				local back = if (L.anchor - R.anchor):Dot(dir) < 0 then L else R
				st.phase = (if back == L then 0 else 0.5) - 1e-4
			end
			local old = st.phase
			st.phase += speed * dt / stride
			for i, foot in { L, R } do
				local at = (i - 1) * 0.5
				local crossed = math.floor(st.phase - at) > math.floor(old - at)
				if crossed and foot.planted then
					foot.pending = true
				end
			end
			st.phase %= 1
			-- a planted foot left too far behind, or out to the side (turning), steps now
			for _, foot in { L, R } do
				if foot.planted and not foot.pending then
					local off = flat(foot.anchor - neutralOf(foot, rootCF))
					local side = math.abs(off:Dot(rootCF.RightVector))
					if off.Magnitude > stance * 0.5 * 1.35 + 1.5 or side > 2.5 then
						foot.pending = true
					end
				end
			end
		else
			-- settle: step a foot that is off its spot (or turned) back under the hull
			local worst: Foot?, worstDev = nil, 0
			for _, foot in { L, R } do
				if foot.planted then
					local dev = flat(foot.anchor - neutralOf(foot, rootCF)).Magnitude
					local yawDev = math.abs(angleDiff(foot.yaw, rootYaw + foot.splay))
					local score = math.max(dev / SETTLE_DIST, yawDev / SETTLE_YAW)
					if score > 1 and score > worstDev then
						worst, worstDev = foot, score
					end
				end
			end
			if worst then
				worst.pending = true
			end
		end
		for _, foot in { L, R } do
			local o = other(st, foot)
			if foot.pending and foot.planted and o.planted then
				if st.moving then
					local dur = math.clamp((1 - duty) * stride / math.max(speed, 2), 0.26, 0.75)
					startSwing(st, foot, dur, liftH, 0.55)
				else
					startSwing(st, foot, SETTLE_DUR, SETTLE_LIFT, 0.3)
				end
			end
		end
	end

	-- swing feet: arc toward a landing spot predicted from the root's velocity
	for _, foot in { L, R } do
		if not foot.planted and not st.airborne then
			foot.t = math.min(1, foot.t + dt / foot.dur)
			local remain = (1 - foot.t) * foot.dur
			local ahead = (rootCF + vh * remain) * CFrame.Angles(0, yawRate * math.min(remain, 0.3), 0)
			local lead = dir * (stance * 0.5 - RUN_BACK * st.sprint) * math.clamp((speed - 0.5) / 3, 0, 1)
			local tgt = neutralOf(foot, ahead) + lead
			local gy = groundY(st, tgt, ground)
			foot.target = Vector3.new(tgt.X, gy + ANKLE_H, tgt.Z)
			foot.targetYaw = yawOf(ahead) + foot.splay
			if foot.t >= 1 then
				plant(model, st, foot)
			end
		end
	end

	-- springs: footfall dip, hull pitch, landing squat, weapon lag
	st.dip, st.dipV = spring(st.dip, st.dipV, 0, 10, 0.38, sdt) -- bouncy
	local sprintR = st.sprint * st.amount
	local pitchTarget = -RUN_PITCH * sprintR - math.clamp(st.accel * 0.005, -0.1, 0.1) - 0.03 * st.amount
	if st.airborne then
		pitchTarget += math.clamp(root.AssemblyLinearVelocity.Y * 0.002, -0.08, 0.08)
	end
	st.pitch, st.pitchV = spring(st.pitch, st.pitchV, pitchTarget, 6, 0.45, sdt)
	st.comp, st.compV = spring(st.comp, st.compV, 0, COMP_W, COMP_Z, sdt)
	st.comp = math.clamp(st.comp, -0.12, MAX_COMP)
	st.rail, st.railV = spring(st.rail, st.railV, 0, 7, 0.28, sdt)
	st.pod, st.podV = spring(st.pod, st.podV, 0, 5.5, 0.22, sdt)
	st.gunYaw += (math.clamp(-st.yawRate * 0.04, -0.12, 0.12) - st.gunYaw) * math.min(1, dt * 5)
	st.bank += (math.clamp(st.yawRate * speed * 0.0016, -0.12, 0.12) - st.bank) * math.min(1, dt * 4)

	-- waddle: sway over the stance foot while the other swings
	local swayAmp = lerp(SWAY_WALK, SWAY_RUN, st.sprint)
	local swayTarget = 0
	if not L.planted and R.planted then
		swayTarget = swayAmp
	elseif not R.planted and L.planted then
		swayTarget = -swayAmp
	end
	swayTarget *= math.clamp(st.amount + 0.4, 0, 1)

	-- idle while piloted and standing still
	if online and speed < 1 and not st.airborne then
		st.idleT += dt
	else
		st.idleT = 0
	end
	if st.idleT > 0 then
		st.idleClock = st.idleT
	end
	st.idleBlend += ((if st.idleT > IDLE_DELAY then 1 else 0) - st.idleBlend) * math.min(1, dt * (if st.idleT > 0 then 1.5 else 5))
	local ib = st.idleBlend
	local idle = idlePose(st.idleClock)
	-- one step in place per idle cycle (alternating feet)
	if st.idleT > IDLE_DELAY then
		local cyc = math.floor((st.idleT - IDLE_DELAY) / IDLE_CYCLE)
		local ct = (st.idleT - IDLE_DELAY) % IDLE_CYCLE
		if ct > STEP_AT and cyc ~= st.idleStepCycle then
			st.idleStepCycle = cyc
			local foot = if cyc % 2 == 0 then R else L
			if foot.planted and other(st, foot).planted then
				startSwing(st, foot, 0.6, 1.3, 0.25)
			end
		end
	else
		st.idleStepCycle = -1
	end
	swayTarget += idle.sway * ib
	st.sway += (swayTarget - st.sway) * math.min(1, dt * lerp(5, 8, st.sprint))

	-- pelvis frame: fold / squat drop, footfall dip, sprint crouch, sway, hip twist
	local breathe = math.sin(os.clock() * 1.4) * 0.06 * (1 - st.amount) * (1 - st.fold) * st.power
	-- the sit drops and moves back; the squat (windup / landing) goes straight down
	local drop = OFF_DROP * st.fold + Vector3.new(0, OFF_DROP.Y * st.comp * (1 - st.fold), 0)
	local twist = math.sin(st.phase * TAU) * 0.04 * st.amount * (1 - st.air)
	local rootT = CFrame.new(drop.X + st.sway, drop.Y + st.dip - A.SprintCrouch * sprintR + breathe, drop.Z) * CFrame.Angles(0, twist, 0)
	set(st.motors, "Root", rootT)
	local pelvisCF = rootCF * st.motors.Root.C0 * rootT

	-- feet: planted (with heel peel at the back of the stance), swinging or tucked
	local airRise = if root.Anchored then 0 else math.clamp(root.AssemblyLinearVelocity.Y / A.JumpPower, -1, 1)
	local tuck = TUCK_FALL:Lerp(TUCK_RISE, math.clamp(0.5 + 0.5 * airRise, 0, 1))
	for _, foot in { L, R } do
		local footCF: CFrame
		local pitch = 0
		if foot.planted then
			-- heel lifts off (about the toes) as the body passes over and the foot trails
			local center = neutralOf(foot, rootCF) - dir * (RUN_BACK * st.sprint)
			local behind = -flat(foot.anchor - center):Dot(dir) / math.max(stance * 0.5, 1)
			if st.moving then
				pitch = -0.4 * smooth((behind - 0.55) / 0.5) * st.amount
			end
			local base = CFrame.new(foot.anchor) * CFrame.Angles(0, foot.yaw, 0)
			footCF = base * CFrame.new(TOE) * CFrame.Angles(pitch, 0, 0) * CFrame.new(-TOE)
		else
			local t = foot.t
			local e = t - math.sin(TAU * t) / TAU -- slow out, fast through, slow in
			local p = foot.from:Lerp(foot.target, e)
			local h = foot.lift * math.sin(math.pi * t ^ 0.8)
			-- toes hang down early in the swing, lift a little just before contact
			pitch = lerp(foot.fromPitch, 0, smooth(t / 0.25)) - foot.pitchAmp * math.sin(math.pi * math.clamp(t / 0.7, 0, 1)) + 0.15 * math.sin(math.pi * math.clamp((t - 0.62) / 0.38, 0, 1))
			local yaw = foot.fromYaw + angleDiff(foot.fromYaw, foot.targetYaw) * e
			footCF = CFrame.new(p + Vector3.new(0, h, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
		if st.air > 1e-3 then
			-- airborne: legs tuck up under the hull, toes drooping
			local airCF = pelvisCF * CFrame.new(foot.hip + tuck) * CFrame.Angles(-0.35, 0, 0)
			footCF = footCF:Lerp(airCF, st.air)
			pitch = lerp(pitch, -0.35, st.air)
		end
		foot.cur = footCF.Position
		foot.pitch = pitch
		solveLeg(st.motors, foot.side, pelvisCF, foot.hip, footCF)
	end

	-- hull: fold tilt, pitch spring, landing nose-dip, roll over the stance leg, bank, look-around
	local fk = Type99Pose.hullFold(st.fold)
	local hullPitch = Type99Builder.OffTilt * fk + st.pitch * (1 - fk) - 0.35 * math.max(0, st.comp) + idle.pitch * ib + breathe * 0.01
	local swayN = st.sway / SWAY_WALK -- -1 (on the left foot) .. 1 (right)
	local hullRoll = -swayN * lerp(ROLL_WALK, ROLL_RUN, st.sprint) * (SWAY_WALK / swayAmp) * st.amount + st.bank - twist * 0.3 - idle.sway * ib * 0.04
	local hullYaw = -twist * 0.7 + swayN * WADDLE_YAW * (1 - st.sprint) * st.amount + idle.yaw * ib
	set(st.motors, "HullTilt", CFrame.Angles(0, hullYaw, 0) * CFrame.Angles(hullPitch, 0, 0) * CFrame.Angles(0, 0, hullRoll))
	Type99Pose.setCanopy(st.motors, st.canopy)

	-- weapons: lag springs, sprint tuck, idle checks
	local weaponsOn = st.power * (1 - st.fold)
	set(st.motors, "RailgunMount", Type99Pose.railFold(st.fold) * CFrame.Angles((st.rail + idle.rail * ib - 0.04 * sprintR) * weaponsOn, st.gunYaw * weaponsOn, 0))
	set(st.motors, "MissileMount", CFrame.Angles((st.pod + idle.podPitch * ib) * weaponsOn, (st.gunYaw * 1.3 + idle.podYaw * ib) * weaponsOn, st.pod * 0.2 * weaponsOn))
	set(st.motors, "ChinMount", CFrame.Angles(st.rail * 0.4 * weaponsOn, (idle.chin * ib - st.gunYaw * 0.5) * weaponsOn, 0))

	-- servo / hydraulic whine: louder and higher with speed and hard landings
	local swinging = if L.planted and R.planted then 0 else 1
	st.servo.Volume = (st.amount * 0.28 + sprintR * 0.22 + swinging * 0.06 + math.min(0.45, math.abs(st.compV) * 0.25)) * st.power
	st.servo.PlaybackSpeed = 0.7 + st.amount * 0.22 + sprintR * 0.22
end

local function step(dt: number)
	for model, st in states do
		if model.Parent then
			stepMech(model, st, dt)
		end
	end
end

-- Subscribe to foot plants (strength ~0.3..0.75, for camera shake).
function Type99Animator.onFootstep(fn: (model: Model, side: string, strength: number) -> ())
	table.insert(stepListeners, fn)
end

-- Subscribe to landings (impact = fall speed, studs/s).
function Type99Animator.onLand(fn: (model: Model, impact: number) -> ())
	table.insert(landListeners, fn)
end

function Type99Animator.isAirborne(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.airborne
end

-- Deep squat before a jump; the pilot's client calls this as it jumps.
function Type99Animator.windup(model: Model)
	local st = states[model]
	if st then
		st.compV += 3.2
		st.podV += 0.8
		play(st, "Hydraulic", 0.6, 0.9, 0.4)
	end
end

-- Debug: planted flags and solved ankle targets.
function Type99Animator.debugFeet(model: Model): { [string]: { planted: boolean, cur: Vector3 } }?
	local st = states[model]
	if not st then
		return nil
	end
	local out = {}
	for side, foot in st.feet do
		out[side] = { planted = foot.planted, cur = foot.cur }
	end
	return out
end

function Type99Animator.start()
	CollectionService:GetInstanceAddedSignal("Mech"):Connect(function(inst)
		if inst:IsA("Model") then
			task.spawn(setup, inst)
		end
	end)
	for _, inst in CollectionService:GetTagged("Mech") do
		if inst:IsA("Model") then
			task.spawn(setup, inst)
		end
	end
	RunService.PreSimulation:Connect(step)
end

return Type99Animator
