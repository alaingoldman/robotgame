--!strict
-- Client animator for BRZ-01 Titans (type "Titan", TitanBuilder / TitanPose).
-- Runs on every client from replicated state only (root velocity,
-- "PowerState" / "PowerTime", "Charge", "Plugged").
--
--   * power states: kneel <-> stand, chest hatch, gem lights dimmed while off
--     (TitanPose.powerTargets with TitanConfig.Board / Exit timings)
--   * idle: breathing (chest rise, shoulders), weight shift, slow head looks,
--     restless fingers
--   * walk / sprint: IK-planted feet (stance slides back exactly with the
--     body so feet don't skate, swing arcs forward), hip drop + bob, pelvis
--     sway, torso counter-twist and sprint lean, arm swing, fists at a run
--   * footstep sounds + camera thumps for the local pilot, servo hum, cues
--   * battery: the four cells on the back show the charge; a teal arc jumps
--     from the dock pylon to the terminal while plugged in (TitanDock)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local TitanConfig = require(Shared:WaitForChild("TitanConfig"))
local TitanDock = require(Shared:WaitForChild("TitanDock"))
local TitanPose = require(Shared:WaitForChild("TitanPose"))

local TitanAnimator = {}

local player = Players.LocalPlayer
local G = TitanConfig.Gait
local TAU = math.pi * 2
local LIGHT_DIM = 0.1
local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local SLOTS = { "Helmet", "Chest", "Legs" }

local B, X = TitanConfig.Board, TitanConfig.Exit
type Cue = { at: number, sound: string, volume: number, speed: number, stop: number? }
local CUES: { [string]: { Cue } } = {
	Boarding = {
		{ at = 0, sound = "Clunk", volume = 0.8, speed = 1.2 },
		{ at = B.HatchCloseStart, sound = "Hiss", volume = 0.6, speed = 1.1, stop = 0.6 },
		{ at = B.HatchCloseEnd, sound = "Clunk", volume = 1.2, speed = 0.75 },
		{ at = B.PowerUp, sound = "PowerUp", volume = 0.9, speed = 0.9 },
		{ at = B.StandStart, sound = "StandUp", volume = 1.1, speed = 0.85 },
		{ at = B.StandEnd - 0.05, sound = "Stomp", volume = 1.2, speed = 0.8 },
	},
	PoweringDown = {
		{ at = 0, sound = "PowerDown", volume = 0.9, speed = 0.75 },
		{ at = 0.05, sound = "Hydraulic", volume = 0.9, speed = 0.85 },
		{ at = X.KneelEnd - 0.1, sound = "Stomp", volume = 0.9, speed = 0.85 },
		{ at = X.HatchOpenStart, sound = "Hiss", volume = 0.7, speed = 1.1, stop = 0.7 },
		{ at = X.HatchOpenEnd, sound = "Clunk", volume = 0.9, speed = 0.7 },
	},
}
local CUE_SOUNDS = { "Clunk", "Hiss", "PowerUp", "PowerDown", "Hydraulic", "StandUp", "Stomp" }

type State = {
	model: Model,
	root: BasePart,
	motors: { [string]: Motor6D },
	rig: TitanPose.Rig,
	kneel: number,
	hatch: number,
	power: number,
	appliedPower: number,
	lights: { BasePart }?,
	gemLights: { PointLight },
	cells: { BasePart }?,
	cellKey: string,
	phase: number,
	amount: number,
	sprint: number,
	lastPhase: number,
	seed: number,
	stepSounds: { [string]: Sound },
	thud: { [string]: Sound },
	servo: Sound,
	cueSounds: { [string]: Sound },
	cueKey: string,
	cueT: number,
	beams: { Beam }?,
	beamTried: number,
	-- jumping
	airborne: boolean,
	air: number, -- 0 grounded .. 1 airborne pose
	vy: number,
	compress: number, -- extra crouch: windup before takeoff, absorb after landing
	windupT: number?,
	landSounds: { Sound },
}

local states: { [Model]: State } = {}
local stepListeners: { (model: Model, side: string, strength: number) -> () } = {}
local landListeners: { (model: Model, impact: number) -> () } = {}
TitanAnimator.JumpWindup = 0.22 -- PilotController waits this long (crouch) before the jump fires
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local shake = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
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

local function stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

local function setup(model: Model)
	if states[model] or MechTypes.idOf(model) ~= TitanConfig.TypeId then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root or not model.Parent then
		return
	end
	-- a (re)spawned mech can be tagged before all ~3,000 parts have arrived:
	-- wait until its joints stop arriving before measuring the rig
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
	local rig = TitanPose.rig(motors)
	if not rig then
		return
	end
	local stepSounds, thud = {}, {}
	for _, side in { "Left", "Right" } do
		local foot = model:FindFirstChild(side .. "Foot", true)
		if foot then
			stepSounds[side] = makeSound(foot, MechConfig.Sounds.Footstep, 1, false)
			thud[side] = makeSound(foot, MechConfig.Sounds.Stomp, 0.35, false)
		end
	end
	local chest = model:FindFirstChild("Chest", true) or root
	local servo = makeSound(chest, MechConfig.Sounds.Servo, 0, true)
	servo:Play()
	local cueSounds = {}
	for _, key in CUE_SOUNDS do
		cueSounds[key] = makeSound(chest, (MechConfig.Sounds :: any)[key], 1, false)
	end
	local kneel, hatch, power = TitanPose.powerTargets(model)
	local st: State = {
		model = model,
		root = root,
		motors = motors,
		rig = rig,
		kneel = kneel,
		hatch = hatch,
		power = power,
		appliedPower = -1,
		lights = nil,
		gemLights = {},
		cells = nil,
		cellKey = "",
		phase = 0,
		amount = 0,
		sprint = 0,
		lastPhase = 0,
		seed = math.random() * 100,
		stepSounds = stepSounds,
		thud = thud,
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
			makeSound(chest, MechConfig.Sounds.LandImpact, 1, false),
			makeSound(chest, MechConfig.Sounds.LandMetal, 0.8, false),
		},
	}
	states[model] = st
	-- colour swaps repaint the lights / cells: re-read them
	model.AttributeChanged:Connect(function(attr)
		if table.find(SLOTS, attr) then
			st.lights = nil
			st.cells = nil
			st.cellKey = ""
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

-- Gem lights dim toward LIGHT_DIM while powered down.
local function applyLights(model: Model, st: State)
	local lights = st.lights
	if not lights then
		local found, gems = {}, {}
		for _, name in ARMOR_FOLDERS do
			local folder = model:FindFirstChild(name)
			if folder then
				for _, d in folder:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("MechLight") then
						table.insert(found, d)
					elseif d:IsA("PointLight") then
						table.insert(gems, d)
					end
				end
			end
		end
		lights = found
		st.lights = found
		st.gemLights = gems
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
	for _, l in st.gemLights do
		l.Brightness = 0.6 * st.power
		l.Enabled = st.power > 0.05
	end
end

-- The four cells on the back show the charge (25 % each); while charging the
-- next cell pulses; below Low the lit cells pulse red.
local function applyCells(model: Model, st: State, now: number)
	local cells = st.cells
	if not cells then
		local found: { BasePart } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and typeof(d:GetAttribute("TitanCell")) == "number" then
				found[d:GetAttribute("TitanCell") :: number] = d
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

-- The charging arc from the dock pylon to the battery terminal (local beams).
local function applyArc(model: Model, st: State, now: number)
	local plugged = model:GetAttribute("Plugged") == true
	if not st.beams then
		if now - st.beamTried < 1 then
			return
		end
		st.beamTried = now
		local home = model:GetAttribute("Home")
		local term = TitanDock.terminal(model)
		if typeof(home) ~= "CFrame" or not term then
			return
		end
		local at = TitanDock.emitterPosition(home)
		local arc: Attachment? = nil
		for _, p in CollectionService:GetTagged(TitanDock.Tag) do
			if p:IsA("BasePart") and (p.Position - at).Magnitude < 2 then
				arc = p:FindFirstChild("Arc") :: Attachment?
			end
		end
		if not arc then
			return
		end
		local lit = (st.cells and (st.cells :: any)[1] and (st.cells :: any)[1]:GetAttribute("LitColor")) or TitanConfig.getVariant(nil).palette.glow
		local beams = {}
		for i = 1, 2 do
			local b = Instance.new("Beam")
			b.Name = "TitanArc"
			b.Attachment0 = arc
			b.Attachment1 = term
			b.Color = ColorSequence.new(Color3.new(1, 1, 1), lit)
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 24
			b.Width0 = 0.35 / i
			b.Width1 = 0.35 / i
			b.Parent = term
			table.insert(beams, b)
		end
		st.beams = beams
	end
	local power = 0.6 + 0.4 * math.sin(now * 23 + st.seed)
	for i, b in st.beams :: { Beam } do
		b.Enabled = plugged
		if plugged then
			-- crackle: the curve jumps around a few times a second
			b.CurveSize0 = (math.noise(now * 7 + i * 3, st.seed) * 2) * 6
			b.CurveSize1 = (math.noise(now * 7 + i * 5, st.seed + 1) * 2) * -6
			b.Transparency = NumberSequence.new(1 - power * (if i == 1 then 0.85 else 1))
		end
	end
end

-- ===== standing pose: idle + walk / sprint ===================================

-- Foot offset for one foot at cycle phase p (0..1): stance slides from ahead
-- to behind at body speed, swing lifts and carries it forward again.
local function footPath(p: number, duty: number, travel: number, lift: number): (number, number, number)
	if p < duty then
		local u = p / duty
		return -travel / 2 + travel * u, 0, 0
	end
	local u = (p - duty) / (1 - duty)
	local e = TitanPose.smooth(u)
	return travel / 2 - travel * e, lift * math.sin(math.pi * u), math.sin(math.pi * u)
end

local function standPose(st: State, now: number): { [string]: CFrame }
	local rig = st.rig
	local pose: { [string]: CFrame } = {}
	local a, r = st.amount, st.sprint * st.amount
	local idle = 1 - a
	local t = now + st.seed
	local breathe = math.sin(t * 1.4)
	local shift = math.noise(t * 0.12, st.seed) -- slow weight shift

	local duty = lerp(G.WalkDuty, G.SprintDuty, st.sprint)
	local cycle = lerp(G.WalkCycle, G.SprintCycle, st.sprint)
	local travel = cycle * duty * a
	local lift = lerp(G.WalkLift, G.SprintLift, st.sprint) * a
	local p = st.phase
	local pl, pr = p, (p + 0.5) % 1
	local zl, yl, sl = footPath(pl, duty, travel, lift)
	local zr, yr, sr = footPath(pr, duty, travel, lift)

	-- hips: crouch for reach, bob twice a cycle (low at each heel strike),
	-- sway over the planted foot, small yaw with the stride
	local crouch = lerp(0.3, lerp(G.WalkCrouch, G.SprintCrouch, st.sprint), a) + breathe * 0.05 * idle + st.compress * 4.2
	local bob = lerp(G.WalkBob, G.SprintBob, st.sprint) * a * (0.5 + 0.5 * math.cos(p * 2 * TAU))
	local sway = math.sin(p * TAU) * 0.55 * a * (1 - 0.5 * st.sprint) + shift * 0.35 * idle
	local pelvis = CFrame.new(sway, -crouch - bob, 0) * CFrame.Angles(0, math.sin(p * TAU) * 0.08 * a, -math.sin(p * TAU) * 0.035 * a - shift * 0.02 * idle)
	pose.Root = pelvis

	local L, R = rig.legs.Left, rig.legs.Right
	if L then
		TitanPose.legIK(rig, "Left", L.ankle + Vector3.new(0, yl, zl), pelvis, 0, 0.3 * sl - 0.1 * a * math.max(0, zl / math.max(travel, 1e-3)), pose)
	end
	if R then
		TitanPose.legIK(rig, "Right", R.ankle + Vector3.new(0, yr, zr), pelvis, 0, 0.3 * sr - 0.1 * a * math.max(0, zr / math.max(travel, 1e-3)), pose)
	end

	-- torso: counter-twist against the hips, lean at a run, breathing
	local twist = -math.sin(p * TAU) * (0.1 * a + 0.06 * r)
	pose.Waist = CFrame.Angles(-(0.04 * a + G.SprintLean * r + 0.22 * st.compress) - breathe * 0.025 * idle, twist, math.sin(p * TAU) * 0.03 * a)
	-- head: steadies against the body, slow looks around while idle
	local lookYaw = math.noise(t * 0.18, st.seed + 7) * 0.9 * idle
	local lookPitch = math.noise(t * 0.13, st.seed + 11) * 0.25 * idle
	pose.Neck = CFrame.Angles(0.04 * a + G.SprintLean * r * 0.8 + lookPitch + breathe * 0.015 * idle, -twist * 0.8 + lookYaw, 0)
	-- arms swing against the legs (left arm with the right leg)
	local swing = lerp(G.ArmSwing, G.SprintArmSwing, st.sprint) * a
	local armL = -math.sin(p * TAU) * swing
	local armR = math.sin(p * TAU) * swing
	pose.LeftShoulder = CFrame.Angles(armL + 0.06 * r, 0, 0.03 + breathe * 0.02 * idle)
	pose.RightShoulder = CFrame.Angles(armR + 0.06 * r, 0, -0.03 - breathe * 0.02 * idle)
	pose.LeftElbow = CFrame.Angles(0.15 + math.max(0, armL) * 0.6 + 0.65 * r + breathe * 0.02 * idle, 0, 0)
	pose.RightElbow = CFrame.Angles(0.15 + math.max(0, armR) * 0.6 + 0.65 * r + breathe * 0.02 * idle, 0, 0)
	pose.LeftWrist = CFrame.Angles(0.05 * a, 0, 0)
	pose.RightWrist = CFrame.Angles(0.05 * a, 0, 0)
	-- fingers: restless while idle, clench into fists at a run
	local fidgetL = (math.noise(t * 0.5, st.seed + 3) + 0.5) * 0.35 * idle
	local fidgetR = (math.noise(t * 0.5, st.seed + 5) + 0.5) * 0.35 * idle
	TitanPose.fingerCurl(pose, "Left", -1, fidgetL + 0.15 * a + 0.75 * r)
	TitanPose.fingerCurl(pose, "Right", 1, fidgetR + 0.15 * a + 0.75 * r)
	return pose
end

-- Airborne: legs straight with toes pointed on the way up, knees tucked
-- (one leg forward) round the apex, reaching down again for the landing;
-- arms out for balance, torso curled a little over the tuck.
local function airPose(st: State, now: number): { [string]: CFrame }
	local rig = st.rig
	local pose: { [string]: CFrame } = {}
	local tuck = math.clamp(1 - math.abs(st.vy) / 38, 0, 1)
	tuck = TitanPose.smooth(tuck)
	local rising = if st.vy > 0 then 1 else 0
	local pelvis = CFrame.Angles(-0.08 * tuck, 0, 0)
	pose.Root = pelvis
	local L, R = rig.legs.Left, rig.legs.Right
	if L then
		TitanPose.legIK(rig, "Left", L.ankle + Vector3.new(0, 5.2 * tuck, -2.4 * tuck), pelvis, 0, -0.55 * rising * (1 - tuck) + 0.2 * tuck, pose)
	end
	if R then
		TitanPose.legIK(rig, "Right", R.ankle + Vector3.new(0, 3.6 * tuck, 2.2 * tuck), pelvis, 0, -0.55 * rising * (1 - tuck) - 0.3 * tuck, pose)
	end
	local flail = math.sin(now * 3) * 0.05
	pose.Waist = CFrame.Angles(-0.18 * tuck - 0.05, 0, 0)
	pose.Neck = CFrame.Angles(0.1 * tuck - 0.12 * (1 - tuck), 0, 0)
	pose.LeftShoulder = CFrame.Angles(0.15 + 0.2 * tuck, 0, -(0.6 + flail))
	pose.RightShoulder = CFrame.Angles(0.15 + 0.2 * tuck, 0, 0.6 + flail)
	pose.LeftElbow = CFrame.Angles(0.35, 0, 0)
	pose.RightElbow = CFrame.Angles(0.35, 0, 0)
	TitanPose.fingerCurl(pose, "Left", -1, 0.7)
	TitanPose.fingerCurl(pose, "Right", 1, 0.7)
	return pose
end

-- Airborne test from replicated state only: the root's height above the
-- ground under it (every client), plus its vertical speed.
local function updateAir(st: State, dt: number, now: number)
	local root = st.root
	if root.Anchored then
		st.airborne = false
		st.vy = 0
	else
		local v = root.AssemblyLinearVelocity
		rayParams.FilterDescendantsInstances = { st.model }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -80, 0), rayParams)
		local height = if hit then root.Position.Y - hit.Position.Y - TitanConfig.RootHeight else 99
		local wasAir = st.airborne
		local air = height > 2.2 or (height > 0.9 and math.abs(v.Y) > 10)
		if air and not wasAir then
			st.windupT = nil
			st.compress = 0
		elseif wasAir and not air then
			-- landing: absorb deep, thump
			local impact = math.max(0, -st.vy)
			st.compress = math.clamp(0.3 + impact / 70, 0.3, 1.1)
			for i, s in st.landSounds do
				s.Volume = (if i == 1 then 0.6 else 0.45) + math.min(impact / 80, 0.6)
				s.PlaybackSpeed = 0.75 + math.random() * 0.1
				s.TimePosition = 0
				s:Play()
			end
			if st.model:GetAttribute("PilotId") == player.UserId then
				shake = math.max(shake, 0.7 + impact / 30)
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
		-- crouch before the legs fire (pilot's client only)
		st.compress = math.max(st.compress, 0.75 * TitanPose.smooth((now - windupT) / TitanAnimator.JumpWindup))
		if now - windupT > TitanAnimator.JumpWindup + 0.5 then
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
		s.Volume = 0.9 + strength * 0.4
		s.PlaybackSpeed = 0.8 + math.random() * 0.12 + strength * 0.08
		s.TimePosition = 0
		s:Play()
	end
	local th = st.thud[side]
	if th then
		th.Volume = 0.25 + strength * 0.35
		th.PlaybackSpeed = 1.1 + math.random() * 0.1
		th.TimePosition = 0
		th:Play()
	end
	if st.model:GetAttribute("PilotId") == player.UserId then
		shake = math.max(shake, 0.4 + strength * 0.5)
	end
	for _, fn in stepListeners do
		task.spawn(fn, st.model, side, strength)
	end
end

local function step(dt: number)
	local now = os.clock()
	for model, st in states do
		if not model.Parent then
			continue
		end
		local kneelT, hatchT, powerT, timed = TitanPose.powerTargets(model)
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
		applyCells(model, st, now)
		applyArc(model, st, now)

		-- walk / sprint amounts from the root's speed
		local speed = 0
		if not st.root.Anchored then
			local v = st.root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		st.amount += (math.clamp(speed / (MechConfig.WalkSpeed * 0.8), 0, 1) - st.amount) * math.min(1, dt * 6)
		local sprintT = math.clamp((speed - MechConfig.WalkSpeed) / (MechConfig.SprintSpeed - MechConfig.WalkSpeed), 0, 1)
		st.sprint += (sprintT - st.sprint) * math.min(1, dt * 4)
		local cycle = lerp(G.WalkCycle, G.SprintCycle, st.sprint)
		-- an idle mech finishes its step (phase drifts to a planted pose)
		local rate = if speed > 0.5 then speed / cycle else 0
		st.lastPhase = st.phase
		st.phase = (st.phase + dt * rate) % 1

		updateAir(st, dt, now)
		local pose = standPose(st, now)
		if st.air > 0.01 then
			pose = blend(pose, airPose(st, now), st.air)
		end
		if st.kneel > 1e-4 then
			-- powered down / getting up: the kneel owns the body
			pose = blend(pose, TitanPose.kneel(st.rig, st.kneel), math.min(1, st.kneel * 4))
			st.amount *= 1 - math.min(1, st.kneel * 4)
		elseif st.amount > 0.3 and st.air < 0.2 then
			-- heel strikes: left at phase 0, right at 0.5
			local strength = 0.4 + 0.6 * st.sprint
			if st.lastPhase > st.phase then
				footfall(st, "Left", strength)
			elseif st.lastPhase < 0.5 and st.phase >= 0.5 then
				footfall(st, "Right", strength)
			end
		end
		TitanPose.apply(st.rig, pose)
		TitanPose.setHatch(st.motors, st.hatch)
		st.servo.Volume = st.amount * 0.32 + st.sprint * st.amount * 0.2 + st.kneel * (1 - st.kneel) * 1.2
		st.servo.PlaybackSpeed = 0.8 + st.amount * 0.25
	end
end

-- Jumping (PilotController): the pilot's client crouches before takeoff.
function TitanAnimator.windup(model: Model)
	local st = states[model]
	if st then
		st.windupT = os.clock()
	end
end

function TitanAnimator.isAirborne(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.airborne
end

-- Subscribe to landings (model, impact speed studs/s).
function TitanAnimator.onLand(fn: (model: Model, impact: number) -> ())
	table.insert(landListeners, fn)
end

-- Subscribe to footfalls (model, "Left" / "Right", strength 0..1).
function TitanAnimator.onFootstep(fn: (model: Model, side: string, strength: number) -> ())
	table.insert(stepListeners, fn)
end

function TitanAnimator.start()
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
	-- footstep thumps for the local pilot (after PilotController's own shake)
	RunService:BindToRenderStep("TitanStepShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
		if shake > 0.01 then
			local k = shake * 0.16
			local camera = workspace.CurrentCamera
			camera.CFrame *= CFrame.new(0, (math.random() - 0.5) * k, 0) * CFrame.Angles((math.random() - 0.5) * k * 0.05, 0, 0)
			shake *= math.exp(-dt * 11)
		end
	end)
end

return TitanAnimator
