--!strict
-- Client animator for SRF-03 "Seraph" mechs (type "Mech3", Mech3Builder /
-- Mech3Pose), after CrimsonAnimator. Runs on every client from replicated
-- state only (root velocity, "PowerState" / "PowerTime", "Charge",
-- "Plugged"):
--
--   * power states: one-knee kneel <-> stand, the helmet cockpit flipping
--     up / down, cockpit light; eyes / chest slits flicker on once sealed
--   * idle: slow breathing (chest heave, shoulders roll, a slow sway) with
--     the wings breathing with it
--   * walk / sprint: a light long-legged gait - IK-planted feet
--     (LegIK.settle), hip sway, torso counter-twist, sprint lean, arm swing
--     (the shoulder pads follow, Mech3Pose.apply); the wings beat a little
--     with the steps and flare up and back on a sprint
--   * jump: windup crouch, wings spread on the way up, tuck, landing absorb
--   * footstep / landing sounds, servo hum, power cues, step shake
--   * battery: the four cells on the backpack show the charge; a blue arc
--     jumps from the dock post to the terminal while plugged in (Mech3Dock)
--   * helmet cockpit: whoever sits in the pilot seat is hidden and shown as a
--     local stand-in clone scaled to Mech3Config.PilotScale; while boarding
--     it jumps from in front of the mech up into the open neck socket

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local Mech3Config = require(Shared:WaitForChild("Mech3Config"))
local Mech3Dock = require(Shared:WaitForChild("Mech3Dock"))
local Mech3Pose = require(Shared:WaitForChild("Mech3Pose"))
local LegIK = require(Shared:WaitForChild("LegIK"))

local Mech3Animator = {}

local player = Players.LocalPlayer
local G = Mech3Config.Gait
local W = Mech3Config.Wings
local TAU = math.pi * 2
local SLOTS = { "Helmet", "Chest", "Legs" }

local B, X = Mech3Config.Board, Mech3Config.Exit
type Cue = { at: number, sound: string, volume: number, speed: number, stop: number? }
local CUES: { [string]: { Cue } } = {
	Boarding = {
		{ at = 0, sound = "Clunk", volume = 0.7, speed = 1.3 },
		{ at = B.HatchCloseStart, sound = "Hydraulic", volume = 0.6, speed = 1.3 },
		{ at = B.HatchCloseEnd, sound = "Clunk", volume = 1.0, speed = 0.8 },
		{ at = B.PowerUp, sound = "PowerUp", volume = 0.8, speed = 1.05 },
		{ at = B.StandStart, sound = "StandUp", volume = 0.9, speed = 1.0 },
		{ at = B.StandEnd - 0.05, sound = "Stomp", volume = 0.9, speed = 0.95 },
	},
	PoweringDown = {
		{ at = 0, sound = "PowerDown", volume = 0.8, speed = 0.9 },
		{ at = 0.05, sound = "Hydraulic", volume = 0.8, speed = 1.0 },
		{ at = X.HatchOpenStart, sound = "Hiss", volume = 0.6, speed = 1.2, stop = 0.6 },
		{ at = X.HatchOpenEnd, sound = "Clunk", volume = 0.8, speed = 0.9 },
	},
}
local CUE_SOUNDS = { "Clunk", "Hiss", "PowerUp", "PowerDown", "Hydraulic", "StandUp", "Stomp" }

type State = {
	model: Model,
	root: BasePart,
	motors: { [string]: Motor6D },
	rig: Mech3Pose.Rig,
	crouch: number,
	hatch: number, -- helmet cockpit: 0 shut .. 1 open
	power: number,
	cockpitLights: { PointLight }?,
	eyes: { BasePart }?,
	cells: { BasePart }?,
	cellKey: string,
	phase: number,
	lastPhase: number,
	feet: LegIK.Feet,
	moving: boolean,
	walkW: number,
	settled: string?,
	dt: number,
	amount: number,
	sprint: number,
	seed: number,
	stepSounds: { [string]: Sound },
	servo: Sound,
	cueSounds: { [string]: Sound },
	cueKey: string,
	cueT: number,
	beams: { Beam }?,
	beamTried: number,
	airborne: boolean,
	air: number,
	vy: number,
	compress: number,
	windupT: number?,
	landSounds: { Sound },
}

local states: { [Model]: State } = {}
local stepListeners: { (model: Model, side: string, strength: number) -> () } = {}
local landListeners: { (model: Model, impact: number) -> () } = {}
local hidden: { [Model]: Seat } = {} -- pilot characters hidden in a helmet cockpit
Mech3Animator.JumpWindup = Mech3Config.JumpWindup
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.CollisionGroup = "MechRoot"
local shake = 0

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
	if states[model] or MechTypes.idOf(model) ~= Mech3Config.TypeId then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root or not model.Parent then
		return
	end
	-- wait until the joints stop arriving (streaming) before measuring the rig
	local t0, last = os.clock(), -1
	while os.clock() - t0 < 20 and model.Parent do
		local count = 0
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				count += 1
			end
		end
		if count == last and model:FindFirstChild("Root", true) then
			break
		end
		last = count
		task.wait(0.3)
	end
	if states[model] or not model.Parent then
		return
	end
	local motors: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local rig = Mech3Pose.rig(motors)
	if not rig then
		return
	end
	local stepSounds = {}
	for _, side in { "Left", "Right" } do
		local foot = model:FindFirstChild(side .. "Foot", true)
		if foot then
			stepSounds[side] = makeSound(foot, MechConfig.Sounds.Footstep, 0.9, false)
		end
	end
	local chest = model:FindFirstChild("Torso", true) or root
	local servo = makeSound(chest, MechConfig.Sounds.Servo, 0, true)
	servo:Play()
	local cueSounds = {}
	for _, key in CUE_SOUNDS do
		cueSounds[key] = makeSound(chest, (MechConfig.Sounds :: any)[key], 1, false)
	end
	local crouch, canopy, power = Mech3Pose.powerTargets(model)
	local st: State = {
		model = model,
		root = root,
		motors = motors,
		rig = rig,
		crouch = crouch,
		hatch = canopy,
		power = power,
		cockpitLights = nil,
		eyes = nil,
		cells = nil,
		cellKey = "",
		phase = 0,
		lastPhase = 0,
		feet = LegIK.newFeet(),
		moving = false,
		walkW = 0,
		settled = nil,
		dt = 1 / 60,
		amount = 0,
		sprint = 0,
		seed = math.random() * 100,
		stepSounds = stepSounds,
		servo = servo,
		cueSounds = cueSounds,
		cueKey = "",
		cueT = 0,
		beams = nil,
		beamTried = 0,
		airborne = false,
		air = 0,
		vy = 0,
		compress = 0,
		windupT = nil,
		landSounds = {
			makeSound(chest, MechConfig.Sounds.LandImpact, 0.9, false),
			makeSound(chest, MechConfig.Sounds.LandMetal, 0.7, false),
		},
	}
	states[model] = st
	-- colour swaps repaint the cells / lights: re-read them
	model.AttributeChanged:Connect(function(attr)
		if table.find(SLOTS, attr) then
			st.cells = nil
			st.cellKey = ""
			st.cockpitLights = nil
			if st.beams then
				for _, b in st.beams do
					b:Destroy()
				end
				st.beams = nil
			end
		end
	end)
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
		st.cueT = if t < 0.3 then -1 else t
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

-- Cockpit light: on while the helmet is open or the mech is powered. The
-- eyes and the blue core lights (chest slits, cockpit screens) come on with
-- the power, flickering as they catch, once the helmet is down.
local function applyCockpit(model: Model, st: State, now: number)
	local lights = st.cockpitLights
	if not lights then
		local found, eyes = {}, {}
		for _, d in model:GetDescendants() do
			if d:IsA("PointLight") and d.Name == "CockpitLight" then
				table.insert(found, d)
			elseif d:IsA("BasePart") and (d:GetAttribute("Mech3Eye") or d:GetAttribute("Mech3Core")) then
				table.insert(eyes, d)
			end
		end
		lights = found
		st.cockpitLights = found
		st.eyes = eyes
	end
	local p = st.power
	local flicker = 1
	if p > 0.02 and p < 0.98 then
		flicker = if math.noise(now * 30, st.seed) > -0.1 then 1 else 0.25
	end
	local k = 0.06 + 0.94 * p * flicker
	for _, e in st.eyes or {} do
		local lit = e:GetAttribute("LitColor")
		if typeof(lit) == "Color3" then
			local kk = if e:GetAttribute("Mech3Core") then math.max(k, 0.25 * st.hatch) else k
			e.Color = Color3.new(lit.R * kk, lit.G * kk, lit.B * kk)
		end
	end
	for _, l in lights :: { PointLight } do
		l.Brightness = 0.9 * math.max(st.hatch, p * 0.3)
		l.Enabled = l.Brightness > 0.03
	end
end

-- The four cells on the battery show the charge (25 % each); while charging
-- the next cell pulses; below Low the lit cells pulse red.
local function applyCells(model: Model, st: State, now: number)
	local cells = st.cells
	if not cells then
		local found: { BasePart } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and typeof(d:GetAttribute("Mech3Cell")) == "number" then
				found[d:GetAttribute("Mech3Cell") :: number] = d
			end
		end
		cells = found
		st.cells = found
	end
	local c = model:GetAttribute("Charge")
	local charge = if typeof(c) == "number" then c else 100
	local plugged = model:GetAttribute("Plugged") == true
	local low = charge < MechConfig.Battery.Low
	local pulse = 0.55 + 0.45 * math.sin(now * (if low then 9 else 6))
	local key = string.format("%d%s%s%.1f", math.floor(charge), tostring(plugged), tostring(low), if plugged or low then pulse else 0)
	if key == st.cellKey then
		return
	end
	st.cellKey = key
	for i, cell in cells :: { BasePart } do
		local lit = cell:GetAttribute("LitColor")
		local base = if typeof(lit) == "Color3" then lit else cell.Color
		if low then
			base = Color3.fromRGB(255, 50, 40)
		end
		local full = charge >= i * 25 - 0.5
		local partial = not full and charge > (i - 1) * 25
		local k
		if full then
			k = if low then pulse else 1
		elseif partial and plugged then
			k = 0.25 + 0.75 * pulse
		elseif partial then
			k = 0.5
		else
			k = 0.07
		end
		cell.Color = Color3.new(base.R * k, base.G * k, base.B * k)
	end
end

-- The charging arc from the dock post to the battery terminal (local beams).
local function applyArc(model: Model, st: State, now: number)
	local plugged = model:GetAttribute("Plugged") == true
	if not st.beams then
		if now - st.beamTried < 1 then
			return
		end
		st.beamTried = now
		local home = model:GetAttribute("Home")
		local term = Mech3Dock.terminal(model)
		if typeof(home) ~= "CFrame" or not term then
			return
		end
		local at = Mech3Dock.emitterPosition(home)
		local arc: Attachment? = nil
		for _, p in CollectionService:GetTagged(Mech3Dock.Tag) do
			if p:IsA("BasePart") and (p.Position - at).Magnitude < 2 then
				arc = p:FindFirstChild("Arc") :: Attachment?
			end
		end
		if not arc then
			return
		end
		local cell = st.cells and (st.cells :: any)[1]
		local lit = (cell and cell:GetAttribute("LitColor")) or Mech3Config.getVariant(nil).palette.glow
		local beams = {}
		for i = 1, 2 do
			local b = Instance.new("Beam")
			b.Name = "Mech3Arc"
			b.Attachment0 = arc
			b.Attachment1 = term
			b.Color = ColorSequence.new(Color3.new(1, 1, 1), lit)
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 20
			b.Width0 = 0.28 / i
			b.Width1 = 0.28 / i
			b.Parent = term
			table.insert(beams, b)
		end
		st.beams = beams
	end
	local power = 0.6 + 0.4 * math.sin(now * 23 + st.seed)
	for i, b in st.beams :: { Beam } do
		b.Enabled = plugged
		if plugged then
			b.CurveSize0 = (math.noise(now * 7 + i * 3, st.seed) * 2) * 4
			b.CurveSize1 = (math.noise(now * 7 + i * 5, st.seed + 1) * 2) * -4
			b.Transparency = NumberSequence.new(1 - power * (if i == 1 then 0.85 else 1))
		end
	end
end

-- ===== standing pose: idle + walk / sprint ===================================

local SETTLE: LegIK.SettleParams = { dist = 0.55, dur = 0.26, lift = 0.9 }

local function footPath(p: number, duty: number, travel: number, lift: number): (number, number, number)
	if p < duty then
		local u = p / duty
		return -travel / 2 + travel * u, 0, 0
	end
	local u = (p - duty) / (1 - duty)
	local m = travel * (1 - duty) / math.max(duty, 1e-3)
	local u2, u3 = u * u, u * u * u
	local z = (2 * u3 - 3 * u2 + 1) * (travel / 2) + (u3 - 2 * u2 + u) * m + (-2 * u3 + 3 * u2) * (-travel / 2) + (u3 - u2) * m
	return z, lift * math.sin(math.pi * u), math.sin(math.pi * u)
end

-- (the shoulder pads follow in Mech3Pose.apply)
local function armPose(pose: { [string]: CFrame }, side: string, pitch: number, elbow: number, roll: number)
	pose[side .. "Shoulder"] = CFrame.Angles(pitch, 0, roll)
	pose[side .. "Elbow"] = CFrame.Angles(elbow, 0, 0)
end

local function standPose(st: State, now: number): { [string]: CFrame }
	local rig = st.rig
	local pose: { [string]: CFrame } = {}
	local a, r = st.amount, st.sprint * st.amount
	local idle = 1 - a
	local t = now + st.seed
	-- heavy breathing: a slow, deep heave (in ~1.6 s, out ~2.4 s)
	local bp = (t * 0.25) % 1
	local breathe = if bp < 0.4 then -math.cos(bp / 0.4 * math.pi) else math.cos((bp - 0.4) / 0.6 * math.pi)
	local shift = math.noise(t * 0.12, st.seed)

	local duty = lerp(G.WalkDuty, G.SprintDuty, st.sprint)
	local cycle = lerp(G.WalkCycle, G.SprintCycle, st.sprint)
	local travel = cycle * duty * a
	local lift = lerp(G.WalkLift, G.SprintLift, st.sprint) * a
	local p = st.phase
	local zl, yl, sl = footPath(p, duty, travel, lift)
	local zr, yr, sr = footPath((p + 0.5) % 1, duty, travel, lift)

	local crouch = lerp(0.25, lerp(G.WalkCrouch, G.SprintCrouch, st.sprint), a) + breathe * 0.09 * idle + st.compress * 3.0
	-- the body lands hard on each step: the bob dips right after a heel strike
	local stepP = (p * 2) % 1
	local bob = lerp(G.WalkBob, G.SprintBob, st.sprint) * a * (0.5 + 0.5 * math.cos(stepP * TAU)) + 0.12 * a * math.exp(-stepP * 9)
	local sway = math.sin(p * TAU) * 0.6 * a * (1 - 0.4 * st.sprint) + shift * 0.25 * idle
	local hipYaw = math.sin(p * TAU) * (0.13 * a + 0.05 * r)
	local hipRoll = -math.sin(p * TAU) * (0.09 * a - 0.03 * r) - shift * 0.025 * idle
	local pelvis = CFrame.new(sway, -crouch - bob, 0) * CFrame.Angles(0, hipYaw, hipRoll)
	pose.Root = pelvis

	local L, R = rig.legs.Left, rig.legs.Right
	if L and R then
		local rest = { Left = L.ankle, Right = R.ankle }
		local gait = { Left = L.ankle + Vector3.new(0, yl, zl), Right = R.ankle + Vector3.new(0, yr, zr) }
		local targets, gaitK, landed = LegIK.settle(st.feet, st.root.CFrame, rest, gait, st.moving, st.walkW, st.air > 0.01, st.dt, SETTLE)
		st.settled = landed
		local fl = (0.3 * sl - 0.1 * a * math.max(0, zl / math.max(travel, 1e-3))) * gaitK.Left
		local fr = (0.3 * sr - 0.1 * a * math.max(0, zr / math.max(travel, 1e-3))) * gaitK.Right
		Mech3Pose.legIK(rig, "Left", targets.Left, pelvis, 0, fl, pose, true)
		Mech3Pose.legIK(rig, "Right", targets.Right, pelvis, 0, fr, pose, true)
	end

	-- torso: counter-twist against the hips, rolls over the planted leg, the
	-- chest heaves with the breath; sprinting leans in, shoulders forward
	local twist = -math.sin(p * TAU) * (0.15 * a + 0.06 * r)
	local roll = math.sin(p * TAU) * 0.06 * a + shift * 0.02 * idle
	pose.Waist = CFrame.Angles(-(0.06 * a + G.SprintLean * r + 0.22 * st.compress) + breathe * 0.035 * idle, twist, roll)
	local lookYaw = math.noise(t * 0.16, st.seed + 7) * 0.6 * idle
	local lookPitch = math.noise(t * 0.11, st.seed + 11) * 0.15 * idle
	pose.Neck = CFrame.Angles(0.05 * a + G.SprintLean * r * 0.7 + lookPitch - breathe * 0.03 * idle, -twist * 0.7 + lookYaw, -roll * 0.5)
	local swing = lerp(G.ArmSwing, G.SprintArmSwing, st.sprint) * a
	local armL = -math.sin(p * TAU) * swing
	local armR = math.sin(p * TAU) * swing
	-- shoulders roll out a little on each breath (the arms hang off them)
	local heave = breathe * 0.025 * idle
	armPose(pose, "Left", armL + 0.05 * r, 0.1 + math.max(0, armL) * 0.3 + 0.3 * r, -(0.02 + heave))
	armPose(pose, "Right", 0.05 + armR + 0.05 * r, 0.16 + math.max(0, armR) * 0.3 + 0.3 * r, 0.02 + heave)
	pose.LeftWrist = CFrame.Angles(0.05 * a, 0, 0)
	pose.RightWrist = CFrame.Angles(0.05 * a, 0, 0)
	-- wings: breathe with the chest, a small beat per step, flared up and
	-- back on a sprint, pressed down a little by a landing / windup
	local flap = W.BreathFlap * breathe * idle + W.WalkFlap * math.sin(p * 2 * TAU) * a * (1 - st.sprint) + W.SprintFlap * r - 0.25 * st.compress
	local fold = W.BreathFold * breathe * idle + W.SprintFold * r + 0.1 * st.compress
	Mech3Pose.wings(pose, flap, fold, -0.1 * r)
	return pose
end

-- Airborne: legs reach down on the way up, knees tuck round the apex (one
-- leg forward), arms out for balance.
local function airPose(st: State, now: number): { [string]: CFrame }
	local rig = st.rig
	local pose: { [string]: CFrame } = {}
	local tuck = Mech3Pose.smooth(math.clamp(1 - math.abs(st.vy) / 34, 0, 1))
	local rising = if st.vy > 0 then 1 else 0
	local pelvis = CFrame.Angles(-0.08 * tuck, 0, 0)
	pose.Root = pelvis
	local L, R = st.rig.legs.Left, st.rig.legs.Right
	if L then
		Mech3Pose.legIK(rig, "Left", L.ankle + Vector3.new(0, 3.0 * tuck, -1.4 * tuck), pelvis, 0, -0.5 * rising * (1 - tuck) + 0.2 * tuck, pose)
	end
	if R then
		Mech3Pose.legIK(rig, "Right", R.ankle + Vector3.new(0, 2.1 * tuck, 1.3 * tuck), pelvis, 0, -0.5 * rising * (1 - tuck) - 0.3 * tuck, pose)
	end
	local flail = math.sin(now * 3) * 0.05
	pose.Waist = CFrame.Angles(-0.16 * tuck - 0.05, 0, 0)
	pose.Neck = CFrame.Angles(0.1 * tuck - 0.12 * (1 - tuck), 0, 0)
	armPose(pose, "Left", 0.15 + 0.15 * tuck, 0.3, -(0.25 + flail))
	armPose(pose, "Right", 0.15 + 0.15 * tuck, 0.3, 0.25 + flail)
	-- wings spread on the way up, half-open round the apex and the fall
	Mech3Pose.wings(pose, W.JumpFlap * (0.55 + 0.45 * rising) * (1 - 0.3 * tuck), 0.15 + 0.15 * tuck)
	return pose
end

local function updateAir(st: State, dt: number, now: number)
	local root = st.root
	if root.Anchored then
		st.airborne = false
		st.vy = 0
	else
		local v = root.AssemblyLinearVelocity
		rayParams.FilterDescendantsInstances = { st.model }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -60, 0), rayParams)
		local height = if hit then root.Position.Y - hit.Position.Y - Mech3Config.RootHeight else 99
		local wasAir = st.airborne
		local air = height > 1.6 or (height > 0.7 and math.abs(v.Y) > 10)
		if air and not wasAir then
			st.windupT = nil
			st.compress = 0
		elseif wasAir and not air then
			local impact = math.max(0, -st.vy)
			st.compress = math.clamp(0.3 + impact / 70, 0.3, 1.0)
			for i, s in st.landSounds do
				s.Volume = (if i == 1 then 0.55 else 0.4) + math.min(impact / 80, 0.5)
				s.PlaybackSpeed = 0.85 + math.random() * 0.1
				s.TimePosition = 0
				s:Play()
			end
			if st.model:GetAttribute("PilotId") == player.UserId then
				shake = math.max(shake, 0.6 + impact / 35)
			end
			for _, fn in landListeners do
				task.spawn(fn, st.model, impact)
			end
		end
		st.airborne = air
		st.vy = v.Y
	end
	local windupT = st.windupT
	if windupT and not st.airborne then
		st.compress = math.max(st.compress, 0.75 * Mech3Pose.smooth((now - windupT) / Mech3Animator.JumpWindup))
		if now - windupT > Mech3Animator.JumpWindup + 0.5 then
			st.windupT = nil
		end
	else
		st.compress *= math.exp(-dt * 4.5)
	end
	st.air += ((if st.airborne then 1 else 0) - st.air) * math.min(1, dt * (if st.airborne then 9 else 14))
end

local function blend(a: { [string]: CFrame }, b: { [string]: CFrame }, w: number): { [string]: CFrame }
	if w <= 0 then
		return a
	elseif w >= 1 then
		return b
	end
	local out: { [string]: CFrame } = {}
	for k, v in a do
		out[k] = v:Lerp(b[k] or CFrame.identity, w)
	end
	for k, v in b do
		if not out[k] then
			out[k] = CFrame.identity:Lerp(v, w)
		end
	end
	return out
end

local function footfall(st: State, side: string, strength: number)
	local s = st.stepSounds[side]
	if s then
		s.Volume = 0.7 + strength * 0.4
		s.PlaybackSpeed = 0.95 + math.random() * 0.12 + strength * 0.08
		s.TimePosition = 0
		s:Play()
	end
	if st.model:GetAttribute("PilotId") == player.UserId then
		shake = math.max(shake, 0.3 + strength * 0.4)
	end
	for _, fn in stepListeners do
		task.spawn(fn, st.model, side, strength)
	end
end

-- Hides (LocalTransparencyModifier, on every client) whoever sits in a
-- SRF-03's neck socket; shows them again once they're out.
local beamWas: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function setHidden(char: Model, on: boolean)
	local v = if on then 1 else 0
	for _, d in char:GetDescendants() do
		if d:IsA("Beam") or d:IsA("Trail") or d:IsA("ParticleEmitter") then
			-- cables / trails on worn gear (EXO-1 hoses) don't take the modifier
			if on and beamWas[d] == nil then
				beamWas[d] = d.Enabled
				d.Enabled = false
			elseif not on and beamWas[d] ~= nil then
				d.Enabled = beamWas[d] :: boolean
				beamWas[d] = nil
			end
		elseif d:IsA("ForceField") then
			d.Visible = not on -- the spawn bubble would hang round the cockpit
		elseif d:IsA("BasePart") then
			d.LocalTransparencyModifier = v
		elseif d:IsA("Decal") then
			-- the face decal (not every engine build exposes the modifier on decals)
			pcall(function()
				(d :: any).LocalTransparencyModifier = v
			end)
		end
	end
end

-- The stand-in pilot: a local clone of the seated avatar (its look: body,
-- clothes, accessories, worn gear), scaled down to fit the neck socket,
-- posed seated and welded to the seat. Visual only (no collisions, no mass).
local dolls: { [Model]: Model } = {} -- character -> stand-in
local SEATED = {
	-- R15 joint -> extra C0 rotation for a seated pose
	LeftHip = CFrame.Angles(math.rad(85), 0, 0),
	RightHip = CFrame.Angles(math.rad(85), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-80), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-80), 0, 0),
	LeftShoulder = CFrame.Angles(math.rad(35), 0, 0),
	RightShoulder = CFrame.Angles(math.rad(35), 0, 0),
	LeftElbow = CFrame.Angles(math.rad(40), 0, 0),
	RightElbow = CFrame.Angles(math.rad(40), 0, 0),
}

-- Seats the stand-in: each SEATED joint's C0 = its rest rotation * the seat
-- bend (absolute, so it can run again: ScaleTo on a model with a Humanoid
-- rebuilds the joints, which straightened the legs).
local function seatPose(doll: Model)
	for _, x in doll:GetDescendants() do
		if x:IsA("Motor6D") and SEATED[x.Name] then
			local rest = x:GetAttribute("RestRot")
			if typeof(rest) == "CFrame" then
				x.C0 = CFrame.new(x.C0.Position) * rest * SEATED[x.Name]
			end
		end
	end
end

local function makeDoll(char: Model, seat: BasePart): Model?
	local was = char.Archivable
	char.Archivable = true
	local ok, doll = pcall(function()
		return char:Clone()
	end)
	char.Archivable = was
	if not ok or not doll then
		return nil
	end
	local d = doll :: Model
	d.Name = "PilotStandIn"
	for _, tag in CollectionService:GetTags(d) do
		CollectionService:RemoveTag(d, tag)
	end
	for _, x in d:GetDescendants() do
		-- drop the clone's tags, so nothing else drives it (ExoAnimator re-aims
		-- tagged EXO-1 pistons with unscaled anchors: a bar across the cockpit)
		for _, tag in CollectionService:GetTags(x) do
			CollectionService:RemoveTag(x, tag)
		end
		if x:IsA("Script") or x:IsA("LocalScript") or x:IsA("Sound") or x:IsA("Animator") or x:IsA("ForceField") then
			x:Destroy()
		elseif x:IsA("BasePart") then
			x.Anchored = false
			x.CanCollide = false
			x.CanTouch = false
			x.CanQuery = false
			x.Massless = true
			x.LocalTransparencyModifier = 0
		elseif x:IsA("Beam") or x:IsA("Trail") or x:IsA("ParticleEmitter") then
			x.Enabled = false
		elseif x:IsA("Motor6D") and SEATED[x.Name] then
			x:SetAttribute("RestRot", x.C0.Rotation)
		end
	end
	local hum = d:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = true
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.EvaluateStateMachine = false
	end
	local hrp = d:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		d:Destroy()
		return nil
	end
	d.PrimaryPart = hrp
	d:SetAttribute("BaseScale", d:GetScale())
	seatPose(d)
	d.Parent = workspace
	return d
end

-- Where the stand-in sits: hips on the seat pan, at the pilot scale.
local function seatedCF(doll: Model, seat: BasePart): CFrame
	local hrp = doll.PrimaryPart :: BasePart
	local lift = hrp.Size.Y * 0.5 + 0.12 * Mech3Config.PilotScale
	return seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + lift, 0.12)
end

local INTRO = Mech3Config.Board.ClimbEnd -- seconds: the pilot jumps up into the open neck socket, shrinking to fit

-- Places a stand-in: during the first INTRO seconds of boarding it steps in
-- from the boarding spot (anchored, scaling down), then it is welded to the
-- seat for good.
local function placeDoll(doll: Model, seat: BasePart, model: Model)
	if doll:GetAttribute("Welded") then
		return
	end
	local hrp = doll.PrimaryPart :: BasePart
	local base = doll:GetAttribute("BaseScale") :: number
	local t = stateTime(model)
	local boarding = model:GetAttribute("PowerState") == "Boarding"
	local u = if boarding then math.clamp(t / INTRO, 0, 1) else 1
	if u < 1 then
		for _, x in doll:GetDescendants() do
			if x:IsA("BasePart") then
				x.Anchored = true
			end
		end
		local e = Mech3Pose.smooth(u)
		local scale = base * (1 + (Mech3Config.PilotScale - 1) * e)
		pcall(function()
			doll:ScaleTo(scale)
		end)
		seatPose(doll)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local fromCF = seatedCF(doll, seat)
		if root then
			local p = (MechTypes.get(model).Builder :: any).offPoints(root.CFrame)
			local stand = p.prompt + Vector3.new(0, hrp.Size.Y * 1.5 + 1.4 * scale / base, 0)
			fromCF = CFrame.lookAt(stand, stand - p.forward)
		end
		local toCF = seatedCF(doll, seat)
		local cf = fromCF:Lerp(toCF, e) + Vector3.new(0, math.sin(math.pi * e) * 3.2, 0) -- a jump up
		doll:PivotTo(cf)
		return
	end
	pcall(function()
		doll:ScaleTo(base * Mech3Config.PilotScale)
	end)
	seatPose(doll)
	doll:PivotTo(seatedCF(doll, seat))
	for _, x in doll:GetDescendants() do
		if x:IsA("BasePart") then
			x.Anchored = false
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = seat
	w.Part1 = hrp
	w.Parent = hrp
	doll:SetAttribute("Welded", true)
end

local function updateHidden()
	local now: { [Model]: Seat } = {}
	for model in states do
		local seat = model:FindFirstChild("PilotSeat")
		if seat and seat:IsA("Seat") then
			local occ = seat.Occupant
			local char = occ and occ.Parent
			if char and char:IsA("Model") then
				now[char] = seat
			end
		end
	end
	for char, seat in now do
		setHidden(char, true)
		local doll = dolls[char]
		if doll and (not doll.Parent or (doll:GetAttribute("Seat") ~= seat:GetFullName())) then
			doll:Destroy()
			doll = nil
		end
		if not doll then
			local made = makeDoll(char, seat)
			if made then
				made:SetAttribute("Seat", seat:GetFullName())
				dolls[char] = made
				doll = made
			end
		end
		local mech = seat:FindFirstAncestorOfClass("Model")
		if doll and mech then
			placeDoll(doll, seat, mech)
		end
	end
	for char in hidden do
		if not now[char] and char.Parent then
			setHidden(char, false)
		end
	end
	for char, doll in dolls do
		if not now[char] then
			doll:Destroy()
			dolls[char] = nil
		end
	end
	hidden = now
end

local function step(dt: number)
	local now = os.clock()
	for model, st in states do
		if not model.Parent then
			continue
		end
		local crouchT, canopyT, powerT, timed = Mech3Pose.powerTargets(model)
		if timed then
			st.crouch, st.hatch, st.power = crouchT, canopyT, powerT
		else
			local k = math.min(1, dt * 2.5)
			st.crouch += (crouchT - st.crouch) * k
			st.hatch += (canopyT - st.hatch) * k
			st.power += (powerT - st.power) * k
		end
		playCues(model, st)
		applyCockpit(model, st, now)
		applyCells(model, st, now)
		applyArc(model, st, now)

		local speed = 0
		if not st.root.Anchored then
			local v = st.root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		st.amount += (math.clamp(speed / (MechConfig.WalkSpeed * 0.8), 0, 1) - st.amount) * math.min(1, dt * 6)
		local sprintT = math.clamp((speed - MechConfig.WalkSpeed) / (MechConfig.SprintSpeed - MechConfig.WalkSpeed), 0, 1)
		st.sprint += (sprintT - st.sprint) * math.min(1, dt * 4)
		local cycle = lerp(G.WalkCycle, G.SprintCycle, st.sprint)
		local rate = if speed > 0.5 then speed / cycle else 0
		st.lastPhase = st.phase
		st.phase = (st.phase + dt * rate) % 1
		st.moving = if st.moving then speed > 0.5 and st.amount > 0.03 else speed > 1.5 and st.amount > 0.1
		st.walkW += ((if st.moving then 1 else 0) - st.walkW) * math.min(1, dt * (if st.moving then 8 else 5))
		st.dt = dt

		updateAir(st, dt, now)
		local pose = standPose(st, now)
		if st.air > 0.01 then
			pose = blend(pose, airPose(st, now), st.air)
		end
		if st.crouch > 1e-4 then
			pose = blend(pose, Mech3Pose.kneel(st.rig, st.crouch), math.min(1, st.crouch * 4))
			st.amount *= 1 - math.min(1, st.crouch * 4)
			st.feet = LegIK.newFeet()
		elseif st.settled and st.air < 0.2 then
			footfall(st, st.settled, 0.2)
		elseif st.amount > 0.3 and st.air < 0.2 then
			local strength = 0.4 + 0.6 * st.sprint
			if st.lastPhase > st.phase then
				footfall(st, "Left", strength)
			elseif st.lastPhase < 0.5 and st.phase >= 0.5 then
				footfall(st, "Right", strength)
			end
		end
		local closing = model:GetAttribute("PowerState") == "Boarding"
		Mech3Pose.apply(st.rig, pose)
		Mech3Pose.setHelmet(st.motors, st.hatch, closing)
		st.servo.Volume = st.amount * 0.28 + st.sprint * st.amount * 0.18 + st.crouch * (1 - st.crouch) * 1.0
		st.servo.PlaybackSpeed = 0.95 + st.amount * 0.3
	end
end

function Mech3Animator.windup(model: Model)
	local st = states[model]
	if st then
		st.windupT = os.clock()
	end
end

function Mech3Animator.isAirborne(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.airborne
end

function Mech3Animator.onLand(fn: (model: Model, impact: number) -> ())
	table.insert(landListeners, fn)
end

function Mech3Animator.onFootstep(fn: (model: Model, side: string, strength: number) -> ())
	table.insert(stepListeners, fn)
end

function Mech3Animator.start()
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
	-- after the camera's own transparency pass (first person / occlusion)
	RunService:BindToRenderStep("Mech3HidePilot", Enum.RenderPriority.Camera.Value + 10, updateHidden)
	RunService:BindToRenderStep("Mech3StepShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
		if shake > 0.01 then
			local k = shake * 0.14
			local camera = workspace.CurrentCamera
			camera.CFrame *= CFrame.new(0, (math.random() - 0.5) * k, 0) * CFrame.Angles((math.random() - 0.5) * k * 0.05, 0, 0)
			shake *= math.exp(-dt * 11)
		end
	end)
end

return Mech3Animator
