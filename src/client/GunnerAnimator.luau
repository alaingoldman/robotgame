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
local LegIK = require(Shared:WaitForChild("LegIK"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))

local GunnerAnimator = {}

local S = GunnerBuilder.Scale
local LIGHT_DIM = 0.12
local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local ARM_SWING, ARM_SWING_SPRINT = 0.22, 0.45
local BOB, BOB_SPRINT = 0.35 * S, 0.65 * S
local SPRINT_LEAN = 0.25
-- planted-foot gait (LegIK): a heavy, short-stepping walk; cadence follows speed
local GAIT: LegIK.Params = {
	stance = 10,
	stanceSprint = 13.5,
	duty = 0.64,
	dutySprint = 0.52,
	lift = 1.8,
	liftSprint = 3,
}
local MAX_COMP = 2.2 -- deepest landing squat (studs)

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
	amount: number,
	sprint: number,
	ik: LegIK.Rig?,
	walk: LegIK.Walk,
	legsFree: boolean,
	jump: LegIK.Air,
	idleT: number,
	look: number,
	stepSounds: { [string]: Sound },
	servo: Sound,
	cueSounds: { [string]: Sound },
	cueKey: string,
	cueT: number,
}

local states: { [Model]: State } = {}
local stepListeners: { (model: Model, side: string) -> () } = {}
local landListeners: { (model: Model, impact: number) -> () } = {}

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
		amount = 0,
		sprint = 0,
		ik = LegIK.new(motors),
		walk = LegIK.newWalk(),
		legsFree = false,
		jump = LegIK.newAir(),
		idleT = 0,
		look = 0,
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
		local landed = LegIK.updateAir(st.jump, model, st.root, GunnerBuilder.RootHeight, MAX_COMP, dt)
		if landed and landed > 15 then
			local sound = st.cueSounds.Stomp
			sound.Volume = math.min(1.5, 0.7 + landed / 55)
			sound.PlaybackSpeed = 0.8
			sound.TimePosition = 0
			sound:Play()
			for _, fn in landListeners do
				task.spawn(fn, model, landed)
			end
		end
		local air, comp = st.jump.air, st.jump.comp

		local ik = st.ik
		if st.off > 1e-4 or not ik then
			-- powered down / getting up: the off pose owns the body
			for name, cf in GunnerPose.offPose(st.off) do
				set(m, name, cf)
			end
			set(m, "PeriscopeTurret", CFrame.identity)
			st.amount = 0
			st.legsFree = false
			LegIK.resetFeet(st.walk)
		else
			if not st.legsFree then
				LegIK.adopt(ik)
				st.legsFree = true
			end
			local strike = LegIK.advance(ik, st.walk, GAIT, dt, speed, st.amount * (1 - air), st.sprint)
			local w = st.walk
			local a = st.amount * w.weight
			local r = st.sprint * a
			local s = math.sin(w.phase)
			local c = math.cos(w.phase)
			local idle = (1 - a) * (1 - air)
			local breathe = math.sin(now * 1.4) * idle
			if model:GetAttribute("PowerState") == "Online" and speed < 1 and not st.jump.airborne then
				st.idleT += dt
			else
				st.idleT = 0
			end
			-- idle: the heavy frame settles from foot to foot, the head checks around
			local shift = math.sin(now * 0.45) * 0.3 * S * idle
			local lookT = if st.idleT > 2.5 then math.sin(st.idleT * 0.4) * 0.35 else 0
			st.look += (lookT - st.look) * math.min(1, dt * 2.5)
			local bob = lerp(BOB, BOB_SPRINT, st.sprint) * a
			local land = math.max(0, comp)
			local rootT = CFrame.new(shift + s * 0.15 * S * a, -w.drop * w.dropK - s * s * bob + breathe * 0.05 * S - land, 0)
				* CFrame.Angles(0, 0, s * (0.03 * a + 0.04 * r) - shift * 0.02)
			set(m, "Root", rootT)
			local settled = LegIK.place(ik, w, rootT, air * 0.85, st.root.CFrame, dt)
			set(m, "Waist", CFrame.Angles(-0.05 * a - SPRINT_LEAN * r + breathe * 0.02 - 0.06 * land, s * (0.1 * a + 0.15 * r) + st.look * 0.25, -shift * 0.012))
			set(m, "Neck", CFrame.Angles(0.04 * a + 0.25 * r - breathe * 0.02 + 0.06 * air, -s * 0.08 * a + st.look * 0.6, 0))
			local arm = lerp(ARM_SWING, ARM_SWING_SPRINT, st.sprint) * a
			local airArm = 0.3 * air + 0.2 * math.min(1, land)
			-- the shield arm barely swings
			set(m, "LeftShoulder", CFrame.Angles(-s * arm * 0.3 + airArm * 0.3, 0, -breathe * 0.01 - airArm * 0.3))
			set(m, "RightShoulder", CFrame.Angles(s * arm + airArm * 0.4, 0, breathe * 0.015 + airArm * 0.5))
			set(m, "LeftElbow", CFrame.Angles(0.05 * a + 0.2 * r, 0, 0))
			set(m, "RightElbow", CFrame.Angles(math.max(0, s) * 0.25 * a + 0.45 * r + 0.03 * idle + 0.3 * air, 0, 0))
			-- the cannon dips a touch on each footfall and kicks on landing; the periscope sweeps at idle
			set(m, "CannonPitch", CFrame.Angles(-0.03 * a * math.abs(c) + 0.05 * r + breathe * 0.01 - 0.04 * land + 0.05 * air, 0, 0))
			set(m, "PeriscopeTurret", CFrame.Angles(0, math.sin(now * 0.35) * 0.5 * idle, 0))
			set(m, "ShieldMount", CFrame.identity)

			if settled and not strike then
				local sound = st.stepSounds[settled]
				if sound then
					sound.Volume = 0.45
					sound.PlaybackSpeed = 1.05 + math.random() * 0.15
					sound.TimePosition = 0
					sound:Play()
				end
			end
			if strike then
				local sound = st.stepSounds[strike]
				if sound then
					sound.Volume = 0.8 + r * 0.35
					sound.PlaybackSpeed = 0.95 + math.random() * 0.2 + r * 0.1
					sound.TimePosition = 0
					sound:Play()
				end
				for _, fn in stepListeners do
					task.spawn(fn, model, strike)
				end
			end
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

-- Jump windup (the pilot's client, just before the jump): a quick squat.
function GunnerAnimator.windup(model: Model)
	local st = states[model]
	if st then
		st.jump.compV += 16
	end
end

-- Subscribe to landings (impact = fall speed, studs/s).
function GunnerAnimator.onLand(fn: (model: Model, impact: number) -> ())
	table.insert(landListeners, fn)
end

-- Whether a gunner is off the ground (ground ray, see LegIK.updateAir).
function GunnerAnimator.isAirborne(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.jump.airborne
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
