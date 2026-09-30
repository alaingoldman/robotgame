--!strict
-- Chunky battery gauge, bottom-left (above the INVENTORY button), for the
-- local pilot's mech. Reads the server's "Charge" (0..100) and "Plugged"
-- attributes.
--
-- Pops in (bouncy scale + wiggle + pop sound) as the pilot gets the controls,
-- jolts when the power cord snaps out, and pops out when the pilot is back
-- on foot. Five segments fill green /
-- yellow / red, each change punches the segment with a tick; below 20 % the
-- gauge pulses red and beeps, at 0 % it flashes "EMPTY" (the mech limps).
-- A lightning bolt shows while plugged in and charging.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MechConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MechConfig"))

local BatteryHud = {}

local SEGMENTS = 5
local GREEN = Color3.fromRGB(88, 226, 104)
local YELLOW = Color3.fromRGB(255, 204, 44)
local RED = Color3.fromRGB(255, 72, 72)
local EMPTY_SEG = Color3.fromRGB(44, 46, 54)
local OUTLINE = Color3.fromRGB(240, 240, 246)
local LOW = MechConfig.Battery.Low

local player = Players.LocalPlayer

local gui: ScreenGui
local card: Frame
local cardScale: UIScale
local stroke: UIStroke
local segs: { Frame } = {}
local segScales: { UIScale } = {}
local percent: TextLabel
local percentScale: UIScale
local status: TextLabel
local bolt: TextLabel
local sounds: { [string]: Sound } = {}

local mech: Model? = nil
local shown = false
local popToken = 0
local level = -1 -- lit segments shown
local tier = "" -- color tier shown
local beepT = 0

local function charge(): number
	local c = mech and mech:GetAttribute("Charge")
	return if typeof(c) == "number" then c else 100
end

local function tierOf(c: number): string
	return if c > 50 then "green" elseif c >= LOW then "yellow" else "red"
end

local function colorOf(t: string): Color3
	return if t == "green" then GREEN elseif t == "yellow" then YELLOW else RED
end

local function play(name: string, volume: number, speed: number)
	local s = sounds[name]
	if s then
		s.Volume = volume
		s.PlaybackSpeed = speed
		s.TimePosition = 0
		s:Play()
	end
end

local function tween(inst: Instance, time: number, style: Enum.EasingStyle, dir: Enum.EasingDirection, props: { [string]: any }): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style, dir), props)
	t:Play()
	return t
end

local function punch(scale: UIScale, amount: number)
	scale.Scale = amount
	tween(scale, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, font: Enum.Font, pos: UDim2, size: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.Text = text
	l.Position = pos
	l.Size = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "BatteryHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Enabled = false

	-- anchored bottom-left, sitting above the INVENTORY [I] button (bottom 24..64)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 20, 1, -78)
	root.Size = UDim2.fromOffset(240, 88)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local screenScale = Instance.new("UIScale")
	screenScale.Name = "ScreenScale"
	screenScale.Parent = root

	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
	card.BackgroundTransparency = 0.08
	card.Parent = root
	corner(card, 18)
	stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(8, 8, 12)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 185))
	grad.Parent = card
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local title = label(card, "HWM-04B", Enum.Font.GothamBlack, UDim2.fromOffset(16, 8), UDim2.fromOffset(120, 16))
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(176, 182, 200)

	-- battery body + nub
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(16, 30)
	body.Size = UDim2.fromOffset(120, 46)
	body.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
	body.Parent = card
	corner(body, 10)
	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Thickness = 4
	bodyStroke.Color = OUTLINE
	bodyStroke.Parent = body
	local nub = Instance.new("Frame")
	nub.Name = "Nub"
	nub.Position = UDim2.fromOffset(139, 43)
	nub.Size = UDim2.fromOffset(8, 20)
	nub.BackgroundColor3 = OUTLINE
	nub.Parent = card
	corner(nub, 3)
	local gap, pad = 4, 6
	local w = (120 - pad * 2 - gap * (SEGMENTS - 1)) / SEGMENTS
	for i = 1, SEGMENTS do
		local s = Instance.new("Frame")
		s.Name = "Seg" .. i
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromOffset(pad + (i - 1) * (w + gap) + w / 2, 23)
		s.Size = UDim2.fromOffset(w, 34)
		s.BackgroundColor3 = EMPTY_SEG
		s.Parent = body
		corner(s, 5)
		local sc = Instance.new("UIScale")
		sc.Parent = s
		segs[i] = s
		segScales[i] = sc
	end
	bolt = label(body, "⚡", Enum.Font.GothamBlack, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	bolt.TextXAlignment = Enum.TextXAlignment.Center
	bolt.TextSize = 30
	bolt.ZIndex = 3
	bolt.Visible = false

	percent = label(card, "100%", Enum.Font.FredokaOne, UDim2.fromOffset(156, 20), UDim2.fromOffset(78, 42))
	percent.TextScaled = true
	local pStroke = Instance.new("UIStroke")
	pStroke.Thickness = 3
	pStroke.Color = Color3.fromRGB(8, 8, 12)
	pStroke.Parent = percent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 36
	limit.Parent = percent
	percentScale = Instance.new("UIScale")
	percentScale.Parent = percent

	status = label(card, "", Enum.Font.GothamBlack, UDim2.fromOffset(157, 62), UDim2.fromOffset(80, 16))
	status.TextSize = 12

	for name, id in { Pop = MechConfig.Sounds.UiPop, Tick = MechConfig.Sounds.UiTick, Beep = MechConfig.Sounds.LowBeep } do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = id
		s.Parent = gui
		sounds[name] = s
	end

	-- shrink on small screens (from the bottom-left corner)
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		screenScale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 640), 0.62, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Lit segments for a charge: any charge left lights at least one.
local function levelOf(c: number): number
	return if c <= 0 then 0 else math.clamp(math.ceil(c / (100 / SEGMENTS)), 1, SEGMENTS)
end

-- Paints the segments (no animation).
local function paint(c: number)
	level = levelOf(c)
	tier = tierOf(c)
	for i, s in segs do
		s.BackgroundColor3 = if i <= level then colorOf(tier) else EMPTY_SEG
	end
	percent.Text = string.format("%d%%", math.floor(c + 0.5))
end

local function popIn()
	if shown then
		return
	end
	shown = true
	popToken += 1
	local token = popToken
	paint(charge())
	-- segments light up one by one after the pop
	for i, s in segs do
		s.BackgroundColor3 = EMPTY_SEG
		segScales[i].Scale = 1
	end
	gui.Enabled = true
	cardScale.Scale = 0
	card.Rotation = -16
	tween(cardScale, 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	tween(card, 0.8, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, { Rotation = 0 })
	play("Pop", 0.9, 1.15)
	local lit, col = level, colorOf(tier)
	for i = 1, lit do
		task.delay(0.18 + i * 0.07, function()
			if popToken == token and shown then
				segs[i].BackgroundColor3 = col
				punch(segScales[i], 1.45)
				play("Tick", 0.35, 1 + i * 0.1)
			end
		end)
	end
	task.delay(0.2 + lit * 0.07, function()
		if popToken == token and shown then
			punch(percentScale, 1.3)
		end
	end)
end

local function popOut()
	if not shown then
		return
	end
	shown = false
	popToken += 1
	local token = popToken
	play("Pop", 0.8, 0.8)
	tween(card, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Rotation = 12 })
	local grow = tween(cardScale, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Scale = 1.12 })
	grow.Completed:Once(function()
		if popToken ~= token then
			return
		end
		local shrink = tween(cardScale, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In, { Scale = 0 })
		shrink.Completed:Once(function()
			if popToken == token then
				gui.Enabled = false
			end
		end)
	end)
end

-- Segment / color changes animate; low battery pulses and beeps.
local function update(dt: number)
	if not shown or not mech then
		return
	end
	local c = charge()
	percent.Text = string.format("%d%%", math.floor(c + 0.5))
	local newLevel, newTier = levelOf(c), tierOf(c)
	if newLevel ~= level or newTier ~= tier then
		local up = newLevel > level
		local changed = if up then newLevel else level
		local levelChanged = newLevel ~= level
		level, tier = newLevel, newTier
		for i, s in segs do
			s.BackgroundColor3 = if i <= level then colorOf(tier) else EMPTY_SEG
		end
		if levelChanged and changed >= 1 and changed <= SEGMENTS then
			-- the segment that filled pops out, the one that emptied squashes
			punch(segScales[changed], if up then 1.45 else 0.6)
			play("Tick", 0.45, if up then 1 + level * 0.1 else 0.8)
		end
		punch(percentScale, 1.25)
	end

	local plugged = mech:GetAttribute("Plugged") == true
	local now = os.clock()
	-- lightning bolt bobs while charging
	bolt.Visible = plugged
	if plugged then
		bolt.Rotation = math.sin(now * 5) * 8
		bolt.TextSize = 30 + math.sin(now * 10) * 3
	end

	local alarm = 0
	if c <= 0 then
		alarm = 0.5 + 0.5 * math.sin(now * 14)
		status.Text = "EMPTY!"
		status.TextColor3 = RED
	elseif c < LOW and not plugged then
		alarm = 0.5 + 0.5 * math.sin(now * 7)
		status.Text = "LOW!"
		status.TextColor3 = RED
	elseif plugged then
		status.Text = if c >= 100 then "FULL" else "CHARGING"
		status.TextColor3 = if c >= 100 then GREEN else YELLOW
	else
		status.Text = "BATTERY"
		status.TextColor3 = Color3.fromRGB(150, 156, 172)
	end
	status.TextTransparency = if c <= 0 then 0.6 * (1 - alarm) else 0
	stroke.Color = Color3.fromRGB(8, 8, 12):Lerp(RED, alarm)
	stroke.Thickness = 3 + alarm * 2
	if level >= 1 and tier == "red" then
		segs[1].BackgroundColor3 = RED:Lerp(Color3.fromRGB(110, 20, 20), alarm)
	end
	-- soft warning beeps (faster when empty)
	if alarm > 0 then
		beepT -= dt
		if beepT <= 0 then
			beepT = if c <= 0 then 1.0 else 1.8
			play("Beep", 0.3, if c <= 0 then 0.85 else 1)
		end
	else
		beepT = 0
	end
end

local plugConn: RBXScriptConnection? = nil

local function track(model: Model?)
	if plugConn then
		plugConn:Disconnect()
		plugConn = nil
	end
	mech = model
	if model then
		-- the cord re-plugging (on exit at the pad) jolts the gauge too
		plugConn = model:GetAttributeChangedSignal("Plugged"):Connect(function()
			if shown and model:GetAttribute("Plugged") == true then
				punch(cardScale, 1.12)
				punch(percentScale, 1.3)
				play("Tick", 0.5, 1.4)
			end
		end)
	end
end

-- The cord ripped out: the gauge jolts, the bolt drops away.
local function jolt()
	if not shown then
		return
	end
	punch(cardScale, 1.18)
	card.Rotation = 9
	tween(card, 0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, { Rotation = 0 })
	play("Pop", 0.8, 1.35)
end

function BatteryHud.start()
	build()
	local remotes = ReplicatedStorage:WaitForChild("MechRemotes")
	local pilotChanged = remotes:WaitForChild("PilotChanged") :: RemoteEvent
	pilotChanged.OnClientEvent:Connect(function(model: Model?, phase: string?)
		if not model then
			track(nil)
			popOut()
		elseif phase == "Boarding" then
			track(model)
		elseif phase == "Online" then
			-- pops in as the pilot gets the controls (plugged in: charging)
			if mech ~= model then
				track(model)
			end
			popIn()
		end
	end)
	RunService.RenderStepped:Connect(update)
end

-- Called as the local pilot's cord snaps out (CordController.Snapped).
function BatteryHud.cordSnapped(model: Model)
	if model == mech then
		if shown then
			jolt()
		else
			popIn()
		end
	end
end

return BatteryHud
