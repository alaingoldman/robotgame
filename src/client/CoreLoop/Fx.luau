--!strict
-- Client juice for the core loop: procedural attack swings on ANY character
-- (Motor6D.Transform offsets written in PreSimulation, after the Animator's
-- step, composed on top of its pose, so walk / idle keep playing), hit-stop,
-- camera shake, sparks, damage numbers, debris bursts, shock rings, flashes
-- and sounds (the game's existing Creator Store sound ids, MechConfig).
-- Everything here is local and cosmetic.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))

local Fx = {}

local player = Players.LocalPlayer
local rng = Random.new()

------------------------------------------------------------------ sounds

local S = MechConfig.Sounds :: any
local IDS: { [string]: string } = {
	Hit = S.LandMetal,
	HitHeavy = S.Clunk,
	Swing = S.Whoosh,
	Break = S.LandImpact,
	Crit = S.CordSparkSmall,
	Spark = S.CordSpark,
	Pop = S.UiPop,
	Tick = S.UiTick,
	Beep = S.LowBeep,
	Snap = S.CordClick,
	Clamp = S.Clunk,
	Hiss = S.Hiss,
	Charge = S.ChargeHum,
	Thud = S.CordThud,
	Stomp = S.Stomp,
	PowerUp = S.PowerUp,
	PowerDown = S.PowerDown,
	Servo = S.Servo,
}
-- find the Type99 charger sound table wherever MechConfig keeps it
for _, v in MechConfig :: any do
	if typeof(v) == "table" and v.Sounds and typeof(v.Sounds) == "table" and v.Sounds.Clamp then
		IDS.Clamp = v.Sounds.Clamp
		IDS.Steam = v.Sounds.Steam
		IDS.AirPop = v.Sounds.Pop
		IDS.ChargeUp = v.Sounds.ChargeUp
	end
end

local soundRoot: Instance = SoundService

-- 2D sound (UI / own feedback), or 3D at a world position.
function Fx.sound(name: string, volume: number?, speed: number?, at: Vector3?)
	local id = IDS[name]
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = speed or 1
	if at then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		s.RollOffMinDistance = 12
		s.RollOffMaxDistance = 160
		s.Parent = a
		s:Play()
		Debris:AddItem(a, 4)
	else
		s.Parent = soundRoot
		s:Play()
		Debris:AddItem(s, 4)
	end
end

------------------------------------------------------------------ camera shake / hit-stop

local shakeAmp = 0
local shakeT = 0
local stopUntil = 0

function Fx.shake(amount: number)
	shakeAmp = math.min(shakeAmp + amount, 2.2)
end

-- Freezes the local attack animation for `seconds` (the "hit-stop").
function Fx.hitStop(seconds: number)
	stopUntil = math.max(stopUntil, os.clock() + seconds)
end

local fovKick = 0
function Fx.fovKick(amount: number)
	fovKick = math.max(fovKick, amount)
end

------------------------------------------------------------------ swings

type Anim = { t0: number, dur: number, combo: number, weapon: string, hold: number, freeze: number? }
local anims: { [Model]: Anim } = {}

local DUR = { Fists = 0.3, Blade = 0.3, Hammer = 0.62, Rivet = 0.16 }

function Fx.swing(char: Model, combo: number, weapon: string)
	local a = anims[char]
	local now = os.clock()
	if weapon == "Rivet" and a and a.weapon == "Rivet" then
		-- keep aiming: restart the recoil without dropping the arm
		a.t0 = now
		a.hold = now + 0.55
		return
	end
	anims[char] = { t0 = now, dur = DUR[weapon] or 0.3, combo = combo, weapon = weapon, hold = now + (if weapon == "Rivet" then 0.55 else 0) }
	-- blade trail
	if weapon == "Blade" then
		local gear = char:FindFirstChild("CoreGear")
		local w = gear and gear:FindFirstChild("Weapon")
		local blade = w and w:FindFirstChild("Blade")
		if blade and blade:IsA("BasePart") then
			local trail = blade:FindFirstChild("SwingTrail") :: Trail?
			if not trail then
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, blade.Size.Y * 0.45, 0)
				a0.Parent = blade
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -blade.Size.Y * 0.45, 0)
				a1.Parent = blade
				local t = Instance.new("Trail")
				t.Name = "SwingTrail"
				t.Attachment0 = a0
				t.Attachment1 = a1
				t.Lifetime = 0.14
				t.Color = ColorSequence.new(Color3.fromRGB(150, 230, 255))
				t.Transparency = NumberSequence.new(0.2, 1)
				t.LightEmission = 1
				t.FaceCamera = true
				t.Parent = blade
				trail = t
			end
			local tr = trail :: Trail
			tr.Enabled = true
			task.delay(0.28, function()
				tr.Enabled = false
			end)
		end
	end
end

-- Test hook: hold a swing at phase p (0..1) for `seconds` (screenshots).
function Fx.debugHold(char: Model, combo: number, weapon: string, p: number, seconds: number)
	local now = os.clock()
	anims[char] = { t0 = now, dur = DUR[weapon] or 0.3, combo = combo, weapon = weapon, hold = now + seconds, freeze = p }
end

-- The joint: a Motor6D, or an AnimationConstraint on avatars with the newer
-- physics joints (both expose .Transform).
local function motor(char: Model, part: string, name: string): any
	local p = char:FindFirstChild(part)
	local m = p and p:FindFirstChild(name)
	return if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then m else nil
end

-- smooth 0..1..0 strike curve with a wind-up dip
local function curve(p: number): (number, number)
	-- returns (strike amount, windup amount)
	if p < 0.22 then
		local k = p / 0.22
		return 0, math.sin(k * math.pi / 2)
	elseif p < 0.42 then
		local k = (p - 0.22) / 0.2
		return 1 - (1 - k) ^ 3, 1 - k
	else
		local k = (p - 0.42) / 0.58
		return 1 - k * k * (3 - 2 * k), 0
	end
end

local R = math.rad
local written: { [any]: { base: CFrame, out: CFrame } } = {}

local function apply(m: any, off: CFrame)
	if not m then
		return
	end
	local w = written[m]
	local base = m.Transform
	-- if nothing (no animation) rewrote the joint since our last write, start
	-- from the pose we composed on, not from our own output
	if w and base == w.out then
		base = w.base
	end
	local out = base * off
	m.Transform = out
	written[m] = { base = base, out = out }
end

local function pose(char: Model, a: Anim, now: number)
	local p = a.freeze or math.clamp((now - a.t0) / a.dur, 0, 1)
	local strike, wind = curve(p)
	local r15 = char:FindFirstChild("UpperTorso") ~= nil
	local rs = if r15 then motor(char, "RightUpperArm", "RightShoulder") else motor(char, "Torso", "Right Shoulder")
	local ls = if r15 then motor(char, "LeftUpperArm", "LeftShoulder") else motor(char, "Torso", "Left Shoulder")
	local re = if r15 then motor(char, "RightLowerArm", "RightElbow") else nil
	local le = if r15 then motor(char, "LeftLowerArm", "LeftElbow") else nil
	local waist = if r15 then motor(char, "UpperTorso", "Waist") else nil
	-- R6 shoulders hinge about their own Z axis; map our "raise forward" onto it
	local function raise(m: any, ang: number, yaw: number?, side: number)
		if not m then
			return
		end
		if r15 then
			apply(m, CFrame.Angles(0, yaw or 0, 0) * CFrame.Angles(ang, 0, 0))
		else
			apply(m, CFrame.Angles(0, 0, side * ang))
		end
	end
	if a.weapon == "Hammer" then
		-- overhead slam: lift high on the wind-up, smash down forward
		local ang = R(150) * wind + R(70) * strike
		raise(rs, ang, nil, 1)
		raise(ls, ang * 0.85, nil, -1)
		apply(re, CFrame.Angles(R(50) * wind, 0, 0))
		apply(le, CFrame.Angles(R(50) * wind, 0, 0))
		apply(waist, CFrame.Angles(R(10) * wind - R(22) * strike, 0, 0))
	elseif a.weapon == "Blade" then
		-- horizontal slash, alternating direction with the combo
		local dir = if a.combo % 2 == 1 then 1 else -1
		local yaw = dir * (R(-70) * (1 - p) + R(45) * p)
		raise(rs, R(80) * math.max(strike, wind * 0.6), yaw, 1)
		apply(re, CFrame.Angles(R(25) * wind, 0, 0))
		apply(waist, CFrame.Angles(0, dir * (R(-20) * wind + R(25) * strike), 0))
	elseif a.weapon == "Rivet" then
		-- arm up and aimed; a sharp recoil kick per shot
		local held = if now < a.hold then 1 else math.max(0, 1 - (now - a.hold) / 0.2)
		local kick = math.max(0, 1 - p) ^ 2
		raise(rs, R(88) * held + R(14) * kick, nil, 1)
		apply(re, CFrame.Angles(R(-6) * kick, 0, 0))
		apply(waist, CFrame.Angles(0, R(12) * held, 0))
	else
		-- fists: 1 = right jab, 2 = left jab, 3 = right haymaker
		local right = a.combo ~= 2
		local big = a.combo == 3
		local sh = if right then rs else ls
		local el = if right then re else le
		local side = if right then 1 else -1
		raise(sh, R(if big then 100 else 88) * strike - R(25) * wind, if big then side * R(-25) * wind + side * R(15) * strike else nil, side)
		apply(el, CFrame.Angles(R(if big then 70 else 80) * wind + R(10) * strike, 0, 0))
		-- the guard arm comes up a little
		local gs = if right then ls else rs
		local ge = if right then le else re
		raise(gs, R(35) * math.max(strike, wind), nil, -side)
		apply(ge, CFrame.Angles(R(90) * math.max(strike, wind), 0, 0))
		apply(waist, CFrame.Angles(0, side * (R(if big then 38 else 22) * strike - R(12) * wind), 0))
	end
end

------------------------------------------------------------------ particles

local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function attachmentAt(pos: Vector3, life: number): Attachment
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = workspace.Terrain
	Debris:AddItem(a, life)
	return a
end

function Fx.sparks(pos: Vector3, color: Color3, count: number, speed: number?)
	local a = attachmentAt(pos, 1.2)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEX
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new((speed or 1) * 18, (speed or 1) * 42)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.12, 0.32)
	e.Drag = 6
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Enabled = false
	e.Parent = a
	e:Emit(count)
end

function Fx.dust(pos: Vector3, size: number, color: Color3?)
	local a = attachmentAt(pos, 2.5)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE_TEX
	e.Color = ColorSequence.new(color or Color3.fromRGB(150, 135, 115))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size * 1.2) })
	e.Speed = NumberRange.new(size * 1.5, size * 3)
	e.SpreadAngle = Vector2.new(180, 30)
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Drag = 4
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Enabled = false
	e.Parent = a
	e:Emit(math.clamp(math.floor(size * 2.5), 6, 22))
end

local function flashBall(pos: Vector3, color: Color3, size: number, life: number)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.CastShadow = false
	b.Material = Enum.Material.Neon
	b.Color = color
	b.Size = Vector3.one * size * 0.4
	b.CFrame = CFrame.new(pos)
	b.Transparency = 0.1
	b.Parent = workspace.Terrain
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.05)
end

function Fx.ring(pos: Vector3, color: Color3, size: number, life: number?)
	local r = Instance.new("Part")
	r.Shape = Enum.PartType.Cylinder
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Material = Enum.Material.Neon
	r.Color = color
	r.Size = Vector3.new(0.2, 1, 1)
	r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	r.Transparency = 0.2
	r.Parent = workspace.Terrain
	TweenService:Create(r, TweenInfo.new(life or 0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, size, size), Transparency = 1 }):Play()
	Debris:AddItem(r, (life or 0.4) + 0.05)
end

-- Physical chunks flying out (local parts; they bounce, then fade).
function Fx.debris(pos: Vector3, size: number, colors: { Color3 }, n: number?)
	local count = n or math.clamp(math.floor(size * 2.2), 6, 18)
	for i = 1, count do
		local p = Instance.new("Part")
		local s = rng:NextNumber(0.25, 0.55) * size * 0.35 + 0.2
		p.Size = Vector3.new(s, s * rng:NextNumber(0.4, 1), s * rng:NextNumber(0.6, 1.4))
		p.Color = if #colors > 0 then colors[(i % #colors) + 1] else Color3.fromRGB(140, 78, 48)
		p.Material = Enum.Material.CorrodedMetal
		p.CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 1), rng:NextNumber(-1, 1)) * size * 0.25) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		p.CanQuery = false
		p.CanTouch = false
		p.CollisionGroup = "Default"
		p.Parent = workspace.Terrain
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.4), rng:NextNumber(-1, 1)).Unit
		p.AssemblyLinearVelocity = dir * rng:NextNumber(18, 34) * math.sqrt(size / 4)
		p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		task.delay(1.1 + rng:NextNumber(0, 0.4), function()
			if p.Parent then
				p.CanCollide = false
				TweenService:Create(p, TweenInfo.new(0.35), { Transparency = 1, Size = p.Size * 0.3 }):Play()
			end
		end)
		Debris:AddItem(p, 1.9)
	end
end

------------------------------------------------------------------ numbers / flashes

function Fx.number(pos: Vector3, text: string, color: Color3, big: boolean?)
	local a = attachmentAt(pos + Vector3.new(rng:NextNumber(-0.8, 0.8), 0.6, rng:NextNumber(-0.8, 0.8)), 1.2)
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(if big then 160 else 110, if big then 64 else 44)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.MaxDistance = 120
	g.Adornee = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = Color3.fromRGB(20, 10, 0)
	t.Parent = g
	local sc = Instance.new("UIScale")
	sc.Scale = if big then 2.2 else 1.7
	sc.Parent = t
	g.Parent = a
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local rise = TweenService:Create(g, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0) })
	rise:Play()
	task.delay(0.5, function()
		TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

-- White flash on a model (Highlight), very short.
function Fx.flash(model: Instance, color: Color3?)
	local h = Instance.new("Highlight")
	h.FillColor = color or Color3.new(1, 1, 1)
	h.FillTransparency = 0.15
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = workspace.Terrain
	TweenService:Create(h, TweenInfo.new(0.16), { FillTransparency = 1 }):Play()
	Debris:AddItem(h, 0.2)
end

-- Quick squash on a target model (local CFrame jiggle of its anchored parts).
local jiggling: { [Model]: boolean } = {}
function Fx.jiggle(model: Model, amount: number)
	if jiggling[model] then
		return
	end
	local root = model.PrimaryPart
	if not root or not root.Anchored then
		return
	end
	jiggling[model] = true
	local parts: { [BasePart]: CFrame } = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Anchored and p.Name ~= "Ring" then
			parts[p] = p.CFrame
		end
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > 0.18 or not model.Parent then
			for p, cf in parts do
				if p.Parent then
					p.CFrame = cf
				end
			end
			conn:Disconnect()
			jiggling[model] = nil
			return
		end
		local k = (1 - t / 0.18) * amount
		local off = Vector3.new(math.sin(t * 90) * k * 0.25, -math.abs(math.sin(t * 70)) * k * 0.15, math.cos(t * 80) * k * 0.2)
		local c = root.Position
		for p, cf in parts do
			if p.Parent then
				p.CFrame = cf + off + (cf.Position - c) * (-k * 0.04)
			end
		end
	end)
end

------------------------------------------------------------------ composite effects

function Fx.impact(pos: Vector3, color: Color3, heavy: boolean)
	Fx.sparks(pos, color, if heavy then 26 else 14, if heavy then 1.3 else 1)
	flashBall(pos, Color3.fromRGB(255, 240, 200), if heavy then 4.5 else 2.6, 0.12)
	if heavy then
		Fx.ring(pos, color, 9, 0.3)
	end
end

function Fx.breakBurst(pos: Vector3, size: number, colors: { Color3 })
	Fx.debris(pos, size, colors)
	Fx.dust(pos - Vector3.new(0, size * 0.25, 0), size)
	Fx.sparks(pos, Color3.fromRGB(255, 190, 80), 30, 1.4)
	flashBall(pos, Color3.fromRGB(255, 220, 160), size * 1.2, 0.18)
	Fx.ring(pos - Vector3.new(0, size * 0.28, 0), Color3.fromRGB(255, 200, 120), size * 3.2, 0.35)
	Fx.sound("Break", 0.7, rng:NextNumber(1.05, 1.3), pos)
end

------------------------------------------------------------------ start

function Fx.start()
	-- swings: write joint offsets after the Animator's step
	RunService.PreSimulation:Connect(function()
		local now = os.clock()
		for char, a in anims do
			if not char.Parent then
				anims[char] = nil
				continue
			end
			if char == player.Character and now < stopUntil then
				a.t0 += 1 / 60 -- hit-stop: hold the pose
				a.hold += 1 / 60
			end
			local finished = now - a.t0 > a.dur and now > a.hold + 0.2
			if finished then
				anims[char] = nil
			else
				pose(char, a, now)
			end
		end
	end)
	-- camera shake + FOV kick (after the camera scripts)
	local baseFov: number? = nil
	RunService:BindToRenderStep("CoreLoopShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		shakeT += dt
		if shakeAmp > 0.01 then
			local a = shakeAmp * 0.18
			local off = CFrame.Angles(math.noise(shakeT * 28, 1) * a * 0.12, math.noise(shakeT * 28, 2) * a * 0.12, math.noise(shakeT * 28, 3) * a * 0.06)
			cam.CFrame = cam.CFrame * CFrame.new(math.noise(shakeT * 30, 4) * a, math.noise(shakeT * 30, 5) * a, 0) * off
			shakeAmp *= math.exp(-dt * 9)
		else
			shakeAmp = 0
		end
		if fovKick > 0.05 then
			baseFov = baseFov or cam.FieldOfView
			cam.FieldOfView = (baseFov :: number) - fovKick
			fovKick *= math.exp(-dt * 14)
		elseif baseFov then
			cam.FieldOfView = baseFov
			baseFov = nil
			fovKick = 0
		end
	end)
end

return Fx
