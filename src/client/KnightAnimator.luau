--!strict
-- Client animator for VK-01 knights (type "Knight"). Runs on every client
-- from replicated state only (root velocity, "PowerState" / "PowerTime").
--
-- Phase 1 / placeholder: power states (kneel, chest hatch, wings, lights via
-- KnightPose.powerTargets), a simple procedural walk / sprint cycle (hip and
-- knee swing, arm swing, bob, lean) and footstep / servo / cue sounds.
-- MechAnimator skips knights (MechTypes hwmAnimator = false); the rig uses
-- the HWM-04B bone names, so it can be moved onto MechAnimator later with
-- per-type tuning.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KnightBuilder = require(Shared:WaitForChild("KnightBuilder"))
local KnightPose = require(Shared:WaitForChild("KnightPose"))
local LegIK = require(Shared:WaitForChild("LegIK"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))

local KnightAnimator = {}

local S = KnightBuilder.Scale
local LIGHT_DIM = 0.12
local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local ARM_SWING, ARM_SWING_SPRINT = 0.3, 0.65
local BOB, BOB_SPRINT = 0.3 * S, 0.6 * S
local SPRINT_LEAN = 0.3
-- planted-foot gait (LegIK): stance length front foot -> back foot (studs),
-- share of the cycle a foot is down, foot lift. Cadence follows from speed.
local STANCE, STANCE_SPRINT = 11, 15
local DUTY, DUTY_SPRINT = 0.62, 0.5
local LIFT, LIFT_SPRINT = 2.2, 3.6
local MAX_COMP = 2.6 -- deepest landing squat (studs)

local B, X = KnightPose.Board, KnightPose.Exit
type Cue = { at: number, sound: string, volume: number, speed: number, stop: number? }
local CUES: { [string]: { Cue } } = {
	Boarding = {
		{ at = B.HatchCloseStart, sound = "Hiss", volume = 0.5, speed = 1.3, stop = 0.5 },
		{ at = B.HatchCloseEnd, sound = "Clunk", volume = 1.1, speed = 0.9 },
		{ at = B.PowerUp, sound = "PowerUp", volume = 0.8, speed = 1.1 },
		{ at = B.StandStart, sound = "StandUp", volume = 1, speed = 1.1 },
		{ at = B.StandEnd - 0.05, sound = "Stomp", volume = 1, speed = 1 },
	},
	PoweringDown = {
		{ at = 0, sound = "PowerDown", volume = 0.9, speed = 0.85 },
		{ at = 0.05, sound = "Hydraulic", volume = 0.8, speed = 1 },
		{ at = X.KneelEnd - 0.1, sound = "Stomp", volume = 0.7, speed = 1.1 },
		{ at = X.HatchOpenStart, sound = "Hiss", volume = 0.6, speed = 1.3, stop = 0.6 },
		{ at = X.HatchOpenEnd, sound = "Clunk", volume = 0.8, speed = 0.8 },
	},
}
local CUE_SOUNDS = { "Clunk", "Hiss", "PowerUp", "PowerDown", "Hydraulic", "StandUp", "Stomp" }

type State = {
	root: BasePart,
	motors: { [string]: Motor6D },
	kneel: number,
	hatch: number,
	power: number,
	appliedPower: number,
	lights: { BasePart }?,
	amount: number,
	sprint: number,
	stepSounds: { [string]: Sound },
	servo: Sound,
	cueSounds: { [string]: Sound },
	cueKey: string,
	cueT: number,
	ik: LegIK.Rig?,
	walk: LegIK.Walk,
	legsFree: boolean, -- the walk owned the legs last frame (IK warm start valid)
	jump: LegIK.Air,
	idleT: number,
	look: number,
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
	if states[model] or MechTypes.idOf(model) ~= KnightBuilder.TypeId then
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
	local kneel, hatch, power = KnightPose.powerTargets(model)
	local st: State = {
		root = root,
		motors = motors,
		kneel = kneel,
		hatch = hatch,
		power = power,
		appliedPower = -1,
		lights = nil,
		amount = 0,
		sprint = 0,
		stepSounds = stepSounds,
		servo = servo,
		cueSounds = cueSounds,
		cueKey = "",
		cueT = 0,
		ik = LegIK.new(motors),
		walk = LegIK.newWalk(),
		legsFree = false,
		jump = LegIK.newAir(),
		idleT = 0,
		look = 0,
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

local GAIT: LegIK.Params = {
	stance = STANCE,
	stanceSprint = STANCE_SPRINT,
	duty = DUTY,
	dutySprint = DUTY_SPRINT,
	lift = LIFT,
	liftSprint = LIFT_SPRINT,
}

local function set(m: { [string]: Motor6D }, name: string, cf: CFrame)
	local motor = m[name]
	if motor then
		motor.Transform = cf
	end
end

local function step(dt: number)
	local now = os.clock()
	for model, st in states do
		if not model.Parent then
			continue
		end
		local kneelT, hatchT, powerT, timed = KnightPose.powerTargets(model)
		if timed then
			st.kneel, st.hatch, st.power = kneelT, hatchT, powerT
		else
			local k = math.min(1, dt * 2.5)
			st.kneel += (kneelT - st.kneel) * k
			st.hatch += (hatchT - st.hatch) * k
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
		local landed = LegIK.updateAir(st.jump, model, st.root, KnightBuilder.RootHeight, MAX_COMP, dt)
		if landed and landed > 15 then
			local sound = st.cueSounds.Stomp
			sound.Volume = math.min(1.4, 0.6 + landed / 60)
			sound.PlaybackSpeed = 0.9
			sound.TimePosition = 0
			sound:Play()
			for _, fn in landListeners do
				task.spawn(fn, model, landed)
			end
		end
		local air, comp = st.jump.air, st.jump.comp

		local ik = st.ik
		if st.kneel > 1e-4 or not ik then
			-- powered down / getting up: the kneel pose owns the body
			for name, cf in KnightPose.kneel(st.kneel) do
				set(m, name, cf)
			end
			st.amount = 0
			st.legsFree = false
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
			local s2 = math.sin(w.phase * 2)
			local idle = (1 - a) * (1 - air)
			local breathe = math.sin(now * 1.6) * idle
			-- idle: slow weight shift from foot to foot, a look around now and then
			if model:GetAttribute("PowerState") == "Online" and speed < 1 and not airborne then
				st.idleT += dt
			else
				st.idleT = 0
			end
			local shift = math.sin(now * 0.55) * 0.35 * S * idle
			local lookT = if st.idleT > 2 then math.sin(st.idleT * 0.45) * 0.45 + math.sin(st.idleT * 1.3) * 0.06 else 0
			st.look += (lookT - st.look) * math.min(1, dt * 3)

			-- body: sinks into the stride, drops at each footfall, rolls over the
			-- planted foot; lands into a squat
			local bob = lerp(BOB, BOB_SPRINT, st.sprint) * a
			local land = math.max(0, comp)
			local rootT = CFrame.new(shift + s * 0.12 * S * a, -w.drop * w.weight - s * s * bob + breathe * 0.05 * S - land, 0)
				* CFrame.Angles(0, 0, s * (0.03 * a + 0.04 * r) - shift * 0.02)
			set(m, "Root", rootT)
			LegIK.place(ik, w, rootT, air * 0.9)
			local lean = -0.06 * a - SPRINT_LEAN * r + s2 * 0.03 * r - 0.06 * air - 0.05 * land
			set(m, "Waist", CFrame.Angles(lean + breathe * 0.025, s * (0.1 * a + 0.15 * r) + st.look * 0.3, -shift * 0.015))
			set(m, "Neck", CFrame.Angles(0.04 * a + 0.25 * r - s2 * 0.02 * r - breathe * 0.03 + 0.05 * air, -s * 0.08 * a + st.look * 0.7, 0))
			local arm = lerp(ARM_SWING, ARM_SWING_SPRINT, st.sprint) * a
			local sway = math.sin(now * 0.8) * 0.04 * idle
			local airArm = 0.35 * air + 0.25 * math.min(1, land)
			set(m, "LeftShoulder", CFrame.Angles(-s * arm + sway + airArm * 0.5, 0, -0.04 - breathe * 0.02 - airArm * 0.6))
			set(m, "RightShoulder", CFrame.Angles(s * arm - sway + airArm * 0.5, 0, 0.04 + breathe * 0.02 + airArm * 0.6))
			set(m, "LeftElbow", CFrame.Angles(0.12 + math.max(0, -s) * 0.3 * a + 0.5 * r + 0.04 * idle + 0.3 * air, 0, 0))
			set(m, "RightElbow", CFrame.Angles(0.12 + math.max(0, s) * 0.3 * a + 0.5 * r + 0.04 * idle + 0.3 * air, 0, 0))
			set(m, "LeftWrist", CFrame.identity)
			-- wings sweep back at speed and flare in the air
			local wing = 0.12 * r - 0.2 * air + breathe * 0.015
			set(m, "WingLeftMount", CFrame.Angles(wing, 0, 0))
			set(m, "WingRightMount", CFrame.Angles(wing, 0, 0))

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
		KnightPose.setHatch(m, st.hatch)
		st.servo.Volume = st.amount * 0.3 + st.sprint * st.amount * 0.2
		st.servo.PlaybackSpeed = 0.95 + st.amount * 0.3
	end
end

-- Subscribe to footfalls (camera shake for the local pilot).
function KnightAnimator.onFootstep(fn: (model: Model, side: string) -> ())
	table.insert(stepListeners, fn)
end

-- Jump windup (the pilot's client, just before the jump): a quick squat.
function KnightAnimator.windup(model: Model)
	local st = states[model]
	if st then
		st.jump.compV += 16
	end
end

-- Subscribe to landings (impact = fall speed, studs/s).
function KnightAnimator.onLand(fn: (model: Model, impact: number) -> ())
	table.insert(landListeners, fn)
end

-- Whether a knight is off the ground (ground ray, see LegIK.updateAir).
function KnightAnimator.isAirborne(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.jump.airborne
end

function KnightAnimator.start()
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

return KnightAnimator
