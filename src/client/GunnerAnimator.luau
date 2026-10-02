--!strict
-- Client animator for GR-07 gunners (type "Gunner"). Runs on every client
-- from replicated state only (root velocity, "PowerState" / "PowerTime").
--
-- Placeholder: power states (lie down / stand up, flower petals, cannon,
-- lights via GunnerPose.powerTargets), a simple heavy procedural walk cycle
-- (hip and knee swing, short arm swing, the shield arm nearly still, bob,
-- lean, the cannon settling against the steps, a slow periscope sweep at
-- idle) and footstep / servo / cue sounds. MechAnimator skips gunners
-- (MechTypes hwmAnimator = false).
--
-- Pilot pose: the avatar rides in the pod welded to an invisible Seat; its
-- sit animation is stopped every frame (here, on every client; the pilot's
-- own client is the one that replicates), so it stays straight: standing in
-- the pod, lying prone on the couch while the mech is down.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunnerBuilder = require(Shared:WaitForChild("GunnerBuilder"))
local GunnerPose = require(Shared:WaitForChild("GunnerPose"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))

local GunnerAnimator = {}

local S = GunnerBuilder.Scale
local TAU = math.pi * 2
local LIGHT_DIM = 0.12
local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local HIP_SWING, HIP_SWING_SPRINT = 0.42, 0.6
local KNEE_BEND, KNEE_BEND_SPRINT = 0.8, 1.25
local ARM_SWING, ARM_SWING_SPRINT = 0.22, 0.45
local BOB, BOB_SPRINT = 0.35 * S, 0.65 * S
local SPRINT_LEAN = 0.25

local function strideFor(amp: number): number
	return 4 * GunnerBuilder.LegLength * 0.935 * math.sin(amp)
end
local STRIDE, STRIDE_SPRINT = strideFor(HIP_SWING), strideFor(HIP_SWING_SPRINT)

local B, X = GunnerPose.Board, GunnerPose.Exit
type Cue = { at: number, sound: string, volume: number, speed: number, stop: number? }
local CUES: { [string]: { Cue } } = {
	Boarding = {
		{ at = B.PetalsCloseStart, sound = "Hiss", volume = 0.5, speed = 1.3, stop = 0.7 },
		{ at = B.PetalsCloseEnd, sound = "Clunk", volume = 1.1, speed = 0.9 },
		{ at = B.PowerUp, sound = "PowerUp", volume = 0.8, speed = 1.1 },
		{ at = B.StandStart, sound = "StandUp", volume = 1, speed = 1.1 },
		{ at = B.StandEnd - 0.05, sound = "Stomp", volume = 1, speed = 1 },
	},
	PoweringDown = {
		{ at = 0, sound = "PowerDown", volume = 0.9, speed = 0.85 },
		{ at = 0.05, sound = "Hydraulic", volume = 0.8, speed = 1 },
		{ at = X.DownEnd - 0.1, sound = "Stomp", volume = 0.8, speed = 0.95 },
		{ at = X.PetalsOpenStart, sound = "Hiss", volume = 0.6, speed = 1.3, stop = 0.8 },
		{ at = X.PetalsOpenEnd, sound = "Clunk", volume = 0.8, speed = 0.8 },
	},
}
local CUE_SOUNDS = { "Clunk", "Hiss", "PowerUp", "PowerDown", "Hydraulic", "StandUp", "Stomp" }

type State = {
	root: BasePart,
	motors: { [string]: Motor6D },
	off: number,
	petals: number,
	power: number,
	appliedPower: number,
	lights: { BasePart }?,
	phase: number,
	amount: number,
	sprint: number,
	lastCos: number,
	stepSounds: { [string]: Sound },
	servo: Sound,
	cueSounds: { [string]: Sound },
	cueKey: string,
	cueT: number,
}

local states: { [Model]: State } = {}
local stepListeners: { (model: Model, side: string) -> () } = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

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

local function stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

local function setup(model: Model)
	if states[model] or MechTypes.idOf(model) ~= GunnerBuilder.TypeId then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root or not model.Parent then
		return
	end
	local motors: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
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
	local off, petals, power = GunnerPose.powerTargets(model)
	local st: State = {
		root = root,
		motors = motors,
		off = off,
		petals = petals,
		power = power,
		appliedPower = -1,
		lights = nil,
		phase = 0,
		amount = 0,
		sprint = 0,
		lastCos = 1,
		stepSounds = stepSounds,
		servo = servo,
		cueSounds = cueSounds,
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

local function playCues(model: Model, st: State)
	local state = model:GetAttribute("PowerState")
	local cues = if typeof(state) == "string" then CUES[state] else nil
	local key = tostring(state) .. tostring(model:GetAttribute("PowerTime"))
	local t = stateTime(model)
	if key ~= st.cueKey then
		st.cueKey = key
		st.cueT = if t < 0.3 then -1 else t -- joining mid-sequence: skip past cues
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

-- Dims the Neon lights toward LIGHT_DIM while powered down.
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

local function set(m: { [string]: Motor6D }, name: string, cf: CFrame)
	local motor = m[name]
	if motor then
		motor.Transform = cf
	end
end

-- Keeps the pilot's avatar straight in the pod: stops its (sit) animations.
local function straightenPilot(model: Model)
	local seat = model:FindFirstChild("PilotSeat")
	local hum = seat and seat:IsA("Seat") and seat.Occupant
	if not hum then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	for model, st in states do
		if not model.Parent then
			continue
		end
		local offT, petalsT, powerT, timed = GunnerPose.powerTargets(model)
		if timed then
			st.off, st.petals, st.power = offT, petalsT, powerT
		else
			local k = math.min(1, dt * 1.2)
			st.off += (offT - st.off) * k
			st.petals += (petalsT - st.petals) * k
			st.power += (powerT - st.power) * k
		end
		playCues(model, st)
		applyLights(model, st)
		local m = st.motors

		-- walk / sprint amounts from the root's speed
		local speed = 0
		if not st.root.Anchored then
			local v = st.root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		st.amount += (math.clamp(speed / MechConfig.WalkSpeed, 0, 1) - st.amount) * math.min(1, dt * 6)
		local sprintT = math.clamp((speed - MechConfig.WalkSpeed) / (MechConfig.SprintSpeed - MechConfig.WalkSpeed), 0, 1)
		st.sprint += (sprintT - st.sprint) * math.min(1, dt * 4)
		st.phase = (st.phase + dt * speed / lerp(STRIDE, STRIDE_SPRINT, st.sprint) * TAU) % TAU

		if st.off > 1e-4 then
			-- powered down / getting up: the off pose owns the body
			for name, cf in GunnerPose.offPose(st.off) do
				set(m, name, cf)
			end
			set(m, "PeriscopeTurret", CFrame.identity)
			st.amount = 0
		else
			local a, r = st.amount, st.sprint * st.amount
			local s, c = math.sin(st.phase), math.cos(st.phase)
			local breathe = math.sin(now * 1.6) * (1 - a)
			local hipAmp = lerp(HIP_SWING, HIP_SWING_SPRINT, st.sprint) * a
			local kneeAmp = lerp(KNEE_BEND, KNEE_BEND_SPRINT, st.sprint) * a
			local hipL, hipR = s * hipAmp, -s * hipAmp
			local kneeL, kneeR = math.max(0, c) * kneeAmp, math.max(0, -c) * kneeAmp
			set(m, "LeftHip", CFrame.Angles(hipL, 0, 0))
			set(m, "RightHip", CFrame.Angles(hipR, 0, 0))
			set(m, "LeftKnee", CFrame.Angles(-kneeL, 0, 0))
			set(m, "RightKnee", CFrame.Angles(-kneeR, 0, 0))
			set(m, "LeftAnkle", CFrame.Angles(kneeL - hipL, 0, 0))
			set(m, "RightAnkle", CFrame.Angles(kneeR - hipR, 0, 0))
			local bob = lerp(BOB, BOB_SPRINT, st.sprint) * a
			set(m, "Root", CFrame.new(0, -s * s * bob + breathe * 0.03 * S, 0) * CFrame.Angles(0, 0, s * (0.03 * a + 0.04 * r)))
			set(m, "Waist", CFrame.Angles(-0.05 * a - SPRINT_LEAN * r + breathe * 0.02, s * (0.1 * a + 0.15 * r), 0))
			set(m, "Neck", CFrame.Angles(0.04 * a + 0.25 * r - breathe * 0.02, -s * 0.08 * a, 0))
			local arm = lerp(ARM_SWING, ARM_SWING_SPRINT, st.sprint) * a
			-- the shield arm barely swings
			set(m, "LeftShoulder", CFrame.Angles(-s * arm * 0.3, 0, -breathe * 0.01))
			set(m, "RightShoulder", CFrame.Angles(s * arm, 0, breathe * 0.015))
			set(m, "LeftElbow", CFrame.Angles(0.05 * a + 0.2 * r, 0, 0))
			set(m, "RightElbow", CFrame.Angles(math.max(0, s) * 0.25 * a + 0.45 * r, 0, 0))
			-- the cannon dips a touch on each footfall; the periscope sweeps at idle
			set(m, "CannonPitch", CFrame.Angles(-0.03 * a * math.abs(c) + 0.05 * r + breathe * 0.01, 0, 0))
			set(m, "PeriscopeTurret", CFrame.Angles(0, math.sin(now * 0.35) * 0.5 * (1 - a), 0))
			set(m, "ShieldMount", CFrame.identity)

			-- footfall at full stride (cos crosses zero)
			if a > 0.25 then
				local side = if st.lastCos > 0 and c <= 0 then "Left" elseif st.lastCos < 0 and c >= 0 then "Right" else nil
				if side then
					local sound = st.stepSounds[side]
					if sound then
						sound.Volume = 0.8 + r * 0.35
						sound.PlaybackSpeed = 0.95 + math.random() * 0.2 + r * 0.1
						sound.TimePosition = 0
						sound:Play()
					end
					for _, fn in stepListeners do
						task.spawn(fn, model, side)
					end
				end
			end
			st.lastCos = c
		end
		GunnerPose.setPetals(m, st.petals)
		straightenPilot(model)
		st.servo.Volume = st.amount * 0.3 + st.sprint * st.amount * 0.2
		st.servo.PlaybackSpeed = 0.95 + st.amount * 0.3
	end
end

-- Subscribe to footfalls (camera shake for the local pilot).
function GunnerAnimator.onFootstep(fn: (model: Model, side: string) -> ())
	table.insert(stepListeners, fn)
end

function GunnerAnimator.start()
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

return GunnerAnimator
