--!strict
-- Procedural walk cycle + machine sounds for every mech in the world.
-- Runs on each client so everyone sees and hears every mech walking.
--
-- Also renders the power states (see MechConfig.Boarding / Exit): a powered-
-- down mech kneels with its chest doors and ramp open and its lights dark; boarding
-- and exiting play timed transitions and sound cues from the server's
-- "PowerState" / "PowerTime" attributes, so all clients stay in sync.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechBuilder = require(Shared:WaitForChild("MechBuilder"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechPose = require(Shared:WaitForChild("MechPose"))

local MechAnimator = {}

local S = MechBuilder.Scale
local TAU = math.pi * 2
local HIP_SWING = MechConfig.WalkHipSwing
local HIP_SWING_SPRINT = MechConfig.SprintHipSwing
local KNEE_BEND = 0.95
local KNEE_BEND_SPRINT = 1.45
local ARM_SWING = 0.28
local ARM_SWING_SPRINT_L = 0.6
local ARM_SWING_SPRINT_R = 0.35 -- gatling arm
local BOB = 0.35 * S
local BOB_SPRINT = 0.75 * S
local BREATHE = 0.04 * S
local SPRINT_LEAN = 0.4 -- upper body tips forward into the run
local SPRINT_TWIST = 0.22 -- torso swings with the stride when sprinting

-- jumping: airborne tuck, and damped springs for the landing recoil
local REST_GAP = MechBuilder.RootHeight -- root center above the ground when standing
local GROUND_TOL = 1.5 -- studs of gap that still count as grounded
local COMP_W, COMP_Z = 11, 0.4 -- body compression spring (rad/s, damping ratio)
local ARM_W, ARM_Z = 8, 0.35 -- arms lag the body: slower, bouncier
local LAND_COMP = 0.085 -- compression velocity per stud/s of impact
local LAND_ARMS = 0.09
local MAX_COMP = 0.6 -- of the full kneel

-- powered-down squat (radians at full crouch); legs come from MechPose's IK
local CROUCH_LEAN = MechBuilder.OffTorsoBow -- torso bows until the cockpit is level
local CROUCH_NECK = MechPose.CrouchNeck
local CROUCH_SHOULDER = MechPose.CrouchShoulder
local CROUCH_SPLAY = MechPose.CrouchSplay
local CROUCH_ELBOW = MechPose.CrouchElbow
local LIGHT_DIM = 0.12 -- light brightness while off

local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local CUE_SOUNDS = { "Clunk", "Hiss", "PowerUp", "PowerDown", "Hydraulic", "StandUp", "Stomp" }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

type Cue = { at: number, sound: string, volume: number, speed: number, stop: number? }

-- Sound cues per power state, in seconds from the state's start (boarding
-- cues count from the end of the pilot's walk, like MechConfig.Boarding).
local B, X = MechConfig.Boarding, MechConfig.Exit
local CUES: { [string]: { Cue } } = {
	Boarding = {
		{ at = B.RampCloseStart, sound = "Hiss", volume = 0.5, speed = 1.3, stop = 0.5 },
		{ at = B.DoorCloseEnd, sound = "Clunk", volume = 1.2, speed = 0.9 },
		{ at = B.PowerUp, sound = "PowerUp", volume = 0.8, speed = 1 },
		{ at = B.StandStart - 0.1, sound = "StandUp", volume = 1, speed = 1.05 },
		{ at = B.StandEnd - 0.05, sound = "Stomp", volume = 1.1, speed = 0.9 },
	},
	PoweringDown = {
		{ at = 0, sound = "PowerDown", volume = 0.9, speed = 0.8 },
		{ at = 0.05, sound = "Hydraulic", volume = 0.8, speed = 0.9 },
		{ at = X.CrouchEnd - 0.05, sound = "Stomp", volume = 0.6, speed = 1.1 },
		{ at = X.Reveal, sound = "Hiss", volume = 0.6, speed = 1.3, stop = 0.6 },
		{ at = X.Reveal + X.RampOpenEnd, sound = "Clunk", volume = 0.8, speed = 0.8 },
	},
}

type State = {
	root: BasePart,
	motors: { [string]: Motor6D },
	phase: number,
	amount: number,
	sprint: number,
	lastCos: number,
	stepSounds: { [string]: Sound },
	servo: Sound,
	cueSounds: { [string]: Sound },
	crouch: number, -- 0 standing .. 1 kneeling
	doors: number, -- 0 shut .. 1 open
	ramp: number, -- 0 retracted .. 1 fully extended
	power: number, -- light brightness 0..1
	cueKey: string, -- state + start time of the cues being played
	cueT: number,
	lights: { BasePart }?,
	appliedPower: number,
	rayParams: RaycastParams,
	airborne: boolean,
	airTime: number,
	fallSpeed: number, -- fastest downward speed this jump
	air: number, -- airborne pose blend 0..1
	comp: number, -- landing compression (spring), in kneel units
	compV: number,
	arm: number, -- arms flung out/down on landing (spring)
	armV: number,
	jumpSounds: { [string]: Sound },
	soundTokens: { [string]: number }, -- latest play per jump sound (for timed stops)
	idleT: number, -- seconds standing still while online
	look: number, -- idle head turn (yaw, radians)
	idleArmT: number, -- idle clock the arm fidgets read (held while fading out)
	idleBlend: number, -- 0..1, fades the arm fidgets out when moving
}

local states: { [Model]: State } = {}
local stepListeners: { (model: Model, side: string) -> () } = {}
local landListeners: { (model: Model, impact: number) -> () } = {}

local function makeSound(parent: Instance, id: string, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 180
	s.Parent = parent
	return s
end

-- Crouch, door, ramp and light targets (see MechPose.powerTargets).
function MechAnimator.powerTargets(model: Model): (number, number, number, number, boolean)
	return MechPose.powerTargets(model, true)
end

local function setup(model: Model)
	if states[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root or not model.Parent then
		return
	end
	local motors = MechPose.motors(model)

	local stepSounds = {}
	for _, side in { "Left", "Right" } do
		local foot = model:FindFirstChild(side .. "Foot")
		if foot then
			stepSounds[side] = makeSound(foot, MechConfig.Sounds.Footstep, 0.9, false)
		end
	end
	local torso = model:FindFirstChild("Torso") or root
	local servo = makeSound(torso, MechConfig.Sounds.Servo, 0, true)
	servo:Play()
	local cueSounds = {}
	for _, key in CUE_SOUNDS do
		cueSounds[key] = makeSound(torso, (MechConfig.Sounds :: any)[key], 1, false)
	end

	local jumpSounds = {}
	local jumpIds = {
		Whoosh = MechConfig.Sounds.Whoosh,
		Hydraulic = MechConfig.Sounds.Hydraulic,
		Hiss = MechConfig.Sounds.Hiss,
		LandImpact = MechConfig.Sounds.LandImpact,
		LandMetal = MechConfig.Sounds.LandMetal,
		Stomp = MechConfig.Sounds.Stomp,
		Whine = MechConfig.Sounds.StandUp,
	}
	for key, id in jumpIds do
		jumpSounds[key] = makeSound(torso, id, 1, false)
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	rayParams.CollisionGroup = MechBuilder.RootGroup
	rayParams.RespectCanCollide = true

	-- start in whatever pose the current state holds, without easing in
	local crouch, doors, ramp, power = MechAnimator.powerTargets(model)
	local st: State = {
		root = root,
		motors = motors,
		phase = 0,
		amount = 0,
		sprint = 0,
		lastCos = 1,
		idleT = 0,
		look = 0,
		idleArmT = 0,
		idleBlend = 0,
		stepSounds = stepSounds,
		servo = servo,
		cueSounds = cueSounds,
		crouch = crouch,
		doors = doors,
		ramp = ramp,
		power = power,
		cueKey = "",
		cueT = 0,
		lights = nil,
		appliedPower = -1,
		rayParams = rayParams,
		airborne = false,
		airTime = 0,
		fallSpeed = 0,
		air = 0,
		comp = 0,
		compV = 0,
		arm = 0,
		armV = 0,
		jumpSounds = jumpSounds,
		soundTokens = {},
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

local function set(motors: { [string]: Motor6D }, name: string, cf: CFrame)
	local m = motors[name]
	if m then
		m.Transform = cf
	end
end

local function playCues(model: Model, st: State)
	local state = model:GetAttribute("PowerState")
	local cues = if typeof(state) == "string" then CUES[state] else nil
	local key = tostring(state) .. tostring(model:GetAttribute("PowerTime"))
	local t = MechPose.stateTime(model)
	if state == "Boarding" then
		t -= MechPose.boardWalk(model)
	end
	if key ~= st.cueKey then
		st.cueKey = key
		-- joining mid-sequence: skip cues that already went by
		st.cueT = if MechPose.stateTime(model) < 0.3 then -1 else t
	end
	if cues then
		for _, cue in cues do
			if st.cueT < cue.at and t >= cue.at then
				local sound = st.cueSounds[cue.sound]
				sound.Volume = cue.volume
				sound.PlaybackSpeed = cue.speed
				sound.TimePosition = 0
				sound:Play()
				local stopAfter = cue.stop
				if stopAfter then
					task.delay(stopAfter, function()
						sound:Stop()
					end)
				end
			end
		end
	end
	st.cueT = t
end

-- Dims the mech's Neon lights toward LIGHT_DIM while powered down.
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

-- One step of a damped spring toward 0 (semi-implicit Euler).
local function spring(x: number, v: number, w: number, z: number, dt: number): (number, number)
	v += (-w * w * x - 2 * z * w * v) * dt
	return x + v * dt, v
end

local function playJump(st: State, key: string, volume: number, speed: number, stopAfter: number?)
	local sound = st.jumpSounds[key]
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.TimePosition = 0
	sound:Play()
	if stopAfter then
		local token = (st.soundTokens[key] or 0) + 1
		st.soundTokens[key] = token
		task.delay(stopAfter, function()
			if st.soundTokens[key] == token then
				sound:Stop()
			end
		end)
	end
end

-- Takeoff / landing from what every client can see: the root's vertical
-- velocity and a ray to the ground (Humanoid states don't replicate).
local function updateJump(model: Model, st: State, dt: number)
	local root = st.root
	if root.Anchored then
		st.airborne, st.airTime = false, 0
		return
	end
	local vy = root.AssemblyLinearVelocity.Y
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(REST_GAP + 8), 0), st.rayParams)
	local gap = if hit then root.Position.Y - hit.Position.Y - REST_GAP else math.huge
	local grounded = gap < GROUND_TOL and vy < 10
	if not st.airborne then
		if not grounded then
			st.airborne, st.airTime, st.fallSpeed = true, 0, 0
			if vy > 20 then
				-- takeoff: legs kick straight, hydraulics fire
				st.compV -= 2.5
				playJump(st, "Whoosh", 0.9, 0.75 + math.random() * 0.1)
				playJump(st, "Hydraulic", 0.9, 1.5)
				playJump(st, "Hiss", 0.7, 1.2, 0.35)
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
	local impact = st.fallSpeed
	if impact < 14 or st.airTime < 0.12 then
		return -- a step down, not a jump
	end
	-- landing: the body sinks into the legs and springs back; the arms keep going
	st.compV += math.min(impact, 120) * LAND_COMP
	st.armV += math.min(impact, 120) * LAND_ARMS
	local k = math.clamp(impact / 80, 0.3, 1.3)
	playJump(st, "LandImpact", 1.3 * k, 0.9 + math.random() * 0.1)
	playJump(st, "LandMetal", 0.8 * k, 0.8 + math.random() * 0.1)
	playJump(st, "Stomp", 1.1 * k, 0.8)
	playJump(st, "Whine", 0.6 * k, 1.35, 0.7)
	for _, fn in landListeners do
		task.spawn(fn, model, impact)
	end
end

-- Idle head scan: right, back to center, a little left, back to center, repeat.
-- Keys are (seconds into the cycle, yaw); negative yaw looks to the mech's right.
local IDLE_DELAY = 1.5
local IDLE_LOOK = {
	{ 0, 0 },
	{ 1.0, 0 },
	{ 1.7, -0.55 },
	{ 3.2, -0.55 },
	{ 3.9, 0 },
	{ 4.9, 0 },
	{ 5.4, 0.25 },
	{ 6.4, 0.25 },
	{ 7.0, 0 },
	{ 7.5, 0 },
}

local function idleLook(t: number): number
	if t < IDLE_DELAY then
		return 0
	end
	t = (t - IDLE_DELAY) % IDLE_LOOK[#IDLE_LOOK][1]
	for i = 1, #IDLE_LOOK - 1 do
		local k0, k1 = IDLE_LOOK[i], IDLE_LOOK[i + 1]
		if t <= k1[1] then
			local u = (t - k0[1]) / (k1[1] - k0[1])
			u = u * u * (3 - 2 * u)
			return k0[2] + (k1[2] - k0[2]) * u
		end
	end
	return 0
end

-- Idle arm fidgets on a 15 s loop (two head scans): a slow right shoulder
-- roll, then the left hand shaken out. Returns offsets (radians):
-- right shoulder pitch/roll, left shoulder roll, left elbow, left wrist.
local ARM_CYCLE = 15
local ROLL_START, ROLL_LEN = 3.0, 1.6
local SHAKE_START, SHAKE_LEN, SHAKE_HZ = 9.5, 1.4, 7

local function idleArms(t: number): (number, number, number, number, number)
	if t < IDLE_DELAY then
		return 0, 0, 0, 0, 0
	end
	t = (t - IDLE_DELAY) % ARM_CYCLE
	local rPitch, rRoll, lRoll, lElbow, lWrist = 0, 0, 0, 0, 0
	local u = (t - ROLL_START) / ROLL_LEN
	if u > 0 and u < 1 then
		-- one loop: shoulder lifts, rolls back, drops, comes forward
		local env = math.sin(math.pi * u)
		local th = u * TAU
		rPitch = 0.14 * math.sin(th) * env
		rRoll = 0.12 * (1 - math.cos(th)) * 0.5 * env
	end
	u = (t - SHAKE_START) / SHAKE_LEN
	if u > 0 and u < 1 then
		-- forearm comes up a little and the hand flicks side to side
		local lift = math.sin(math.pi * u)
		local shake = math.sin((t - SHAKE_START) * TAU * SHAKE_HZ) * math.sin(math.pi * math.min(1, u * 1.4))
		lElbow = 0.4 * lift
		lWrist = 0.32 * shake
		lRoll = -0.03 * shake - 0.05 * lift
	end
	return rPitch, rRoll, lRoll, lElbow, lWrist
end

local function step(dt: number)
	local now = os.clock()
	for model, st in states do
		if not model.Parent then
			continue
		end
		local crouchT, doorsT, rampT, powerT, timed = MechAnimator.powerTargets(model)
		if timed then
			st.crouch, st.doors, st.ramp, st.power = crouchT, doorsT, rampT, powerT
		else
			local k = math.min(1, dt * 2.5)
			st.crouch += (crouchT - st.crouch) * k
			st.doors += (doorsT - st.doors) * k
			st.ramp += (rampT - st.ramp) * k
			st.power += (powerT - st.power) * k
		end
		playCues(model, st)
		applyLights(model, st)
		local cr = st.crouch

		-- jump: airborne blend and the landing springs
		updateJump(model, st, dt)
		local sdt = math.min(dt, 1 / 30)
		st.air += ((if st.airborne then 1 else 0) - st.air) * math.min(1, sdt * (if st.airborne then 12 else 22))
		st.comp, st.compV = spring(st.comp, st.compV, COMP_W, COMP_Z, sdt)
		st.arm, st.armV = spring(st.arm, st.armV, ARM_W, ARM_Z, sdt)
		st.comp = math.clamp(st.comp, -0.2, MAX_COMP)
		local air, comp, arm = st.air, st.comp, st.arm
		local land = math.max(0, comp) -- squat part of the recoil
		-- rising: knees tucked up; falling: legs reach down for the ground
		local rise = if st.root.Anchored then 0 else math.clamp(st.root.AssemblyLinearVelocity.Y / MechConfig.JumpPower, -1, 1)
		local tuck = air * math.clamp(0.6 + 0.4 * rise, 0.3, 1)

		local root = st.root
		local speed = 0
		if not root.Anchored then
			local v = root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		-- walk amount (0..1) and sprint blend (0..1), both derived from speed
		local walkTarget = math.clamp(speed / MechConfig.WalkSpeed, 0, 1)
		local sprintTarget = math.clamp((speed - MechConfig.WalkSpeed) / (MechConfig.SprintSpeed - MechConfig.WalkSpeed), 0, 1)
		st.amount += (walkTarget - st.amount) * math.min(1, dt * 6)
		st.sprint += (sprintTarget - st.sprint) * math.min(1, dt * 4)

		-- stride grows with the sprint blend so cadence rises naturally
		local stride = lerp(MechConfig.StrideLength, MechConfig.SprintStrideLength, st.sprint)
		st.phase = (st.phase + dt * speed / stride * TAU) % TAU

		local a = st.amount * (1 - 0.85 * air) -- legs stop striding in the air
		local r = st.sprint * a -- never sprint-pose while standing still
		local s, c = math.sin(st.phase), math.cos(st.phase)
		local s2 = math.sin(st.phase * 2) -- twice per cycle: once per footfall
		local idle = 1 - a

		-- squat: IK keeps the feet flat and planted while the body drops. One-knee
		-- mechs use the symmetric squat only for landing recoil and override
		-- the body with their own pose below.
		local oneKnee = MechPose.style(model) == "OneKnee"
		local crK = if oneKnee then 0 else cr
		local crHip, crKnee, drop = MechPose.crouch(math.min(1, crK + land))
		-- the upper body straightens a beat after the legs when standing up
		local crTorso = MechPose.torsoCrouch(crK)
		local breathe = math.sin(now * 1.7) * idle * (1 - cr)

		-- legs: hip swings, knee bends while the leg swings forward, ankle keeps foot flat
		local hipAmp = lerp(HIP_SWING, HIP_SWING_SPRINT, st.sprint) * a
		local kneeAmp = lerp(KNEE_BEND, KNEE_BEND_SPRINT, st.sprint) * a
		local hipL, hipR = s * hipAmp + crHip + 0.45 * tuck, -s * hipAmp + crHip + 0.45 * tuck
		local kneeL = math.max(0, c) * kneeAmp - crKnee + 0.9 * tuck
		local kneeR = math.max(0, -c) * kneeAmp - crKnee + 0.9 * tuck
		local m = st.motors
		set(m, "LeftHip", CFrame.Angles(hipL, 0, 0))
		set(m, "RightHip", CFrame.Angles(hipR, 0, 0))
		set(m, "LeftKnee", CFrame.Angles(-kneeL, 0, 0))
		set(m, "RightKnee", CFrame.Angles(-kneeR, 0, 0))
		set(m, "LeftAnkle", CFrame.Angles(kneeL - hipL, 0, 0))
		set(m, "RightAnkle", CFrame.Angles(kneeR - hipR, 0, 0))

		-- body: heavy drop at each footfall, sway and roll over the planted foot
		local bob = lerp(BOB, BOB_SPRINT, st.sprint) * a
		local roll = s * (0.035 * a + 0.05 * r)
		set(m, "Root", CFrame.new(drop.X, drop.Y - s * s * bob + breathe * BREATHE * 0.5, drop.Z) * CFrame.Angles(0, 0, roll))
		-- torso: lean into the walk (hunch forward when sprinting), counter-twist against the hips
		local lean = -0.07 * a - SPRINT_LEAN * r + s2 * 0.03 * r + CROUCH_LEAN * crTorso - 0.1 * air - 0.45 * comp
		set(m, "Waist", CFrame.Angles(lean + breathe * 0.04, s * (0.11 * a + SPRINT_TWIST * r), -s * (0.02 * a + 0.05 * r)))
		-- head: lift against the lean so the visor stays level, damp the torso twist
		local nod = 0.04 * a + 0.3 * r - s2 * 0.025 * r - breathe * 0.04 + CROUCH_NECK * crTorso
		-- the head lags the body's drop on landing, then bobs back
		nod += 0.08 * air - 0.2 * comp - 0.012 * st.compV
		-- idle look-around while piloted and standing still
		if model:GetAttribute("PowerState") == "Online" and speed < 1 and not st.airborne then
			st.idleT += dt
		else
			st.idleT = 0
		end
		st.look += (idleLook(st.idleT) - st.look) * math.min(1, dt * 6)
		set(m, "Neck", CFrame.Angles(nod, -s * (0.09 * a + 0.16 * r) + st.look, s * 0.03 * r))

		-- arms swing opposite the legs; the gatling arm swings less. Sprinting pumps them hard.
		local armL = lerp(ARM_SWING, ARM_SWING_SPRINT_L, st.sprint) * a
		local armR = lerp(ARM_SWING * 0.5, ARM_SWING_SPRINT_R, st.sprint) * a
		local crArm, crElbow = CROUCH_SHOULDER * crTorso, CROUCH_ELBOW * crK
		-- jump: arms lift up and out in the air, then fling down and out to
		-- balance on landing (pitched against the torso bow so the hands hang low)
		crArm += 0.35 * air + 0.45 * comp - 0.1 * arm
		crElbow += 0.5 * air - 0.22 * arm
		local splay = CROUCH_SPLAY * crTorso + 0.4 * air + 0.5 * arm
		-- idle fidgets fade out (rather than snap) when the mech starts moving
		if st.idleT > 0 then
			st.idleArmT = st.idleT
		end
		st.idleBlend += ((if st.idleT > 0 then 1 else 0) - st.idleBlend) * math.min(1, dt * 8)
		local rPitch, rRoll, lRoll, lElbow, lWrist = idleArms(st.idleArmT)
		local ib = st.idleBlend
		set(m, "LeftShoulder", CFrame.Angles(-s * armL + crArm, 0, -0.04 - 0.06 * r - breathe * 0.02 - splay + lRoll * ib))
		set(m, "RightShoulder", CFrame.Angles(s * armR + crArm + rPitch * ib, 0, 0.04 + 0.04 * r + breathe * 0.02 + splay + rRoll * ib))
		set(m, "LeftElbow", CFrame.Angles(math.max(0, -s) * 0.3 * a + r * (0.4 - 0.25 * s) + crElbow + lElbow * ib, 0, 0))
		set(m, "RightElbow", CFrame.Angles(math.max(0, s) * 0.15 * a + r * (0.3 + 0.1 * s) + crElbow, 0, 0))
		set(m, "LeftWrist", CFrame.Angles(0, 0, lWrist * ib))

		-- one-knee kneel (and its transitions) replaces the body pose
		if oneKnee and cr > 1e-4 then
			for name, cf in MechPose.oneKnee(cr) do
				set(m, name, cf)
			end
		end

		-- cockpit doors and ramp
		MechPose.setCockpit(m, st.doors, st.ramp, if oneKnee then "OneKnee" else nil)

		-- footfall happens at full stride (cos crosses zero)
		if a > 0.25 then
			if st.lastCos > 0 and c <= 0 then
				MechAnimator._footstep(model, st, "Left")
			elseif st.lastCos < 0 and c >= 0 then
				MechAnimator._footstep(model, st, "Right")
			end
		end
		st.lastCos = c

		-- continuous servo whine while moving, louder and higher when sprinting
		st.servo.Volume = a * 0.35 + r * 0.25 + math.min(0.5, math.abs(st.compV) * 0.05)
		st.servo.PlaybackSpeed = 0.85 + a * 0.3 + r * 0.25
	end
end

function MechAnimator._footstep(model: Model, st: State, side: string)
	local sound = st.stepSounds[side]
	if sound then
		local r = st.sprint * st.amount
		sound.Volume = 0.9 + r * 0.35
		sound.PlaybackSpeed = 0.9 + math.random() * 0.2 + r * 0.12
		sound.TimePosition = 0
		sound:Play()
	end
	for _, fn in stepListeners do
		task.spawn(fn, model, side)
	end
end

-- Subscribe to footfalls (used for camera shake on the local pilot's mech).
function MechAnimator.onFootstep(fn: (model: Model, side: string) -> ())
	table.insert(stepListeners, fn)
end

-- Subscribe to landings (impact = fall speed, studs/s).
function MechAnimator.onLand(fn: (model: Model, impact: number) -> ())
	table.insert(landListeners, fn)
end

-- Whether a mech is off the ground (from its root's height, not Humanoid
-- state: the tall mech's Humanoid often reports Running while still falling).
function MechAnimator.isAirborne(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.airborne
end

-- Quick squat before a jump; the pilot's client calls this as it jumps.
function MechAnimator.windup(model: Model)
	local st = states[model]
	if st then
		st.compV += 5
	end
end

-- Current crouch amount (0 standing .. 1 kneeling) of a mech, if animated.
function MechAnimator.getCrouch(model: Model): number
	local st = states[model]
	return if st then st.crouch else 0
end

function MechAnimator.start()
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

return MechAnimator
