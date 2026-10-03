--!strict
-- Core-loop HUD (ScreenGui "CoreHud"), in the game's dark-panel / yellow
-- accent style (Inventory, BatteryHud):
--   bottom centre  EXO battery bar (charging bolt, sprint tag, low / empty
--                  warnings) + SCRAP counter
--   above it       carried-cargo pill: name, tier colour, draining expiry bar
--   right edge     equipped slots: LEGS / ARMS / CHEST / HEAD + WEAPON
--   top centre     crate alert banner + toasts
--   world          "YOUR BASE" marker while carrying cargo
-- Hidden while piloting a mech. Scales down on small screens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Items = require(Shared:WaitForChild("CoreLoop"):WaitForChild("Items"))
local Fx = require(script.Parent.Fx)
local Controls = require(script.Parent.Controls)

local Hud = {}

local player = Players.LocalPlayer
local ClientRoot = script.Parent.Parent
local PilotController: any = require(ClientRoot:WaitForChild("PilotController"))

local COL = {
	bg = Color3.fromRGB(18, 20, 18),
	card = Color3.fromRGB(34, 37, 34),
	text = Color3.fromRGB(228, 228, 216),
	dim = Color3.fromRGB(150, 152, 140),
	accent = Color3.fromRGB(236, 205, 40),
	green = Color3.fromRGB(88, 226, 104),
	yellow = Color3.fromRGB(255, 204, 44),
	red = Color3.fromRGB(255, 72, 72),
	cyan = Color3.fromRGB(80, 200, 255),
	empty = Color3.fromRGB(44, 46, 54),
}

local gui: ScreenGui
local root: Frame
local batFill: Frame
local batText: TextLabel
local batStroke: UIStroke
local batScale: UIScale
local boltLabel: TextLabel
local sprintTag: TextLabel
local scrapText: TextLabel
local scrapScale: UIScale
local carry: Frame
local carryName: TextLabel
local carryTime: TextLabel
local carryFill: Frame
local carryScale: UIScale
local slotsFrame: Frame
local slotTiles: { [string]: { frame: Frame, name: TextLabel, bonus: TextLabel, stroke: UIStroke, scale: UIScale } } = {}
local banner: Frame
local bannerText: TextLabel
local toasts: Frame
local baseMarker: BillboardGui
local baseMarkerText: TextLabel
local arrows: { [string]: TextLabel } = {}

local state: any = { equipped = {}, locker = {}, weapons = { "Fists" }, weapon = "Fists" }

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function stroke(p: Instance, color: Color3, t: number): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = t
	s.Parent = p
	return s
end

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color
	t.Font = font or Enum.Font.GothamBold
	t.Parent = parent
	return t
end

local function panel(parent: Instance, name: string, size: UDim2, pos: UDim2, anchor: Vector2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = COL.bg
	f.BackgroundTransparency = 0.12
	f.Parent = parent
	corner(f, 8)
	return f
end

local function punch(s: UIScale, amount: number)
	s.Scale = amount
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

------------------------------------------------------------------ build

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoreHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local screenScale = Instance.new("UIScale")
	screenScale.Parent = root

	-- battery (bottom centre)
	local bat = panel(root, "Battery", UDim2.fromOffset(380, 54), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
	batStroke = stroke(bat, COL.accent, 1.5)
	batScale = Instance.new("UIScale")
	batScale.Parent = bat
	local title = label(bat, "EXO BATTERY", 11, COL.accent, Enum.Font.GothamBlack)
	title.Position = UDim2.fromOffset(12, 5)
	title.Size = UDim2.fromOffset(120, 14)
	title.TextXAlignment = Enum.TextXAlignment.Left
	batText = label(bat, "100 / 100", 12, COL.text, Enum.Font.GothamBold)
	batText.AnchorPoint = Vector2.new(1, 0)
	batText.Position = UDim2.new(1, -12, 0, 5)
	batText.Size = UDim2.fromOffset(160, 14)
	batText.TextXAlignment = Enum.TextXAlignment.Right
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(12, 23)
	track.Size = UDim2.new(1, -24, 0, 20)
	track.BackgroundColor3 = COL.empty
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = bat
	corner(track, 5)
	batFill = Instance.new("Frame")
	batFill.Name = "Fill"
	batFill.Size = UDim2.fromScale(1, 1)
	batFill.BackgroundColor3 = COL.green
	batFill.BorderSizePixel = 0
	batFill.Parent = track
	corner(batFill, 5)
	-- segment ticks
	for i = 1, 9 do
		local tick = Instance.new("Frame")
		tick.BackgroundColor3 = COL.bg
		tick.BackgroundTransparency = 0.3
		tick.BorderSizePixel = 0
		tick.Position = UDim2.new(i / 10, -1, 0, 0)
		tick.Size = UDim2.new(0, 2, 1, 0)
		tick.ZIndex = 2
		tick.Parent = track
	end
	boltLabel = label(track, "CHARGING", 12, Color3.fromRGB(20, 30, 20), Enum.Font.GothamBlack)
	boltLabel.Size = UDim2.fromScale(1, 1)
	boltLabel.ZIndex = 3
	boltLabel.Visible = false
	sprintTag = label(bat, "SPRINT", 10, COL.cyan, Enum.Font.GothamBlack)
	sprintTag.Position = UDim2.fromOffset(110, 5)
	sprintTag.Size = UDim2.fromOffset(60, 14)
	sprintTag.TextXAlignment = Enum.TextXAlignment.Left
	sprintTag.Visible = false

	-- scrap (right of the battery)
	local scrap = panel(root, "Scrap", UDim2.fromOffset(120, 54), UDim2.new(0.5, 200, 1, -18), Vector2.new(0, 1))
	stroke(scrap, Color3.fromRGB(60, 64, 60), 1)
	scrapScale = Instance.new("UIScale")
	scrapScale.Parent = scrap
	local st = label(scrap, "SCRAP", 11, COL.accent, Enum.Font.GothamBlack)
	st.Position = UDim2.fromOffset(12, 5)
	st.Size = UDim2.fromOffset(80, 14)
	st.TextXAlignment = Enum.TextXAlignment.Left
	scrapText = label(scrap, "0", 24, COL.text, Enum.Font.GothamBlack)
	scrapText.Position = UDim2.fromOffset(12, 20)
	scrapText.Size = UDim2.new(1, -24, 0, 28)
	scrapText.TextXAlignment = Enum.TextXAlignment.Left

	-- carried cargo (above the battery)
	carry = panel(root, "Carry", UDim2.fromOffset(380, 50), UDim2.new(0.5, 0, 1, -80), Vector2.new(0.5, 1))
	carry.Visible = false
	carryScale = Instance.new("UIScale")
	carryScale.Parent = carry
	stroke(carry, COL.accent, 1.5)
	local ct = label(carry, "CARRYING - GET IT HOME", 10, COL.dim, Enum.Font.GothamBlack)
	ct.Position = UDim2.fromOffset(12, 4)
	ct.Size = UDim2.fromOffset(250, 12)
	ct.TextXAlignment = Enum.TextXAlignment.Left
	carryName = label(carry, "", 15, COL.text, Enum.Font.GothamBlack)
	carryName.Position = UDim2.fromOffset(12, 16)
	carryName.Size = UDim2.new(1, -90, 0, 18)
	carryName.TextXAlignment = Enum.TextXAlignment.Left
	carryName.TextTruncate = Enum.TextTruncate.AtEnd
	carryTime = label(carry, "45", 26, COL.text, Enum.Font.GothamBlack)
	carryTime.AnchorPoint = Vector2.new(1, 0)
	carryTime.Position = UDim2.new(1, -12, 0, 6)
	carryTime.Size = UDim2.fromOffset(70, 30)
	carryTime.TextXAlignment = Enum.TextXAlignment.Right
	local ctrack = Instance.new("Frame")
	ctrack.Position = UDim2.new(0, 12, 1, -10)
	ctrack.Size = UDim2.new(1, -24, 0, 5)
	ctrack.BackgroundColor3 = COL.empty
	ctrack.BorderSizePixel = 0
	ctrack.Parent = carry
	corner(ctrack, 3)
	carryFill = Instance.new("Frame")
	carryFill.Size = UDim2.fromScale(1, 1)
	carryFill.BackgroundColor3 = COL.accent
	carryFill.BorderSizePixel = 0
	carryFill.Parent = ctrack
	corner(carryFill, 3)

	-- equipped slots (right edge)
	slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "Slots"
	slotsFrame.AnchorPoint = Vector2.new(1, 0.5)
	slotsFrame.Position = UDim2.new(1, -14, 0.5, 0)
	slotsFrame.Size = UDim2.fromOffset(170, 4 * 52)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = slotsFrame
	for i, slot in { "Legs", "Arms", "Chest", "Weapon" } do
		local f = Instance.new("Frame")
		f.Name = slot
		f.LayoutOrder = i
		f.Size = UDim2.fromOffset(170, 46)
		f.BackgroundColor3 = COL.bg
		f.BackgroundTransparency = 0.18
		f.Parent = slotsFrame
		corner(f, 6)
		local s = stroke(f, Color3.fromRGB(60, 64, 60), 1)
		local sc = Instance.new("UIScale")
		sc.Parent = f
		local tag = label(f, string.upper(slot), 10, COL.accent, Enum.Font.GothamBlack)
		tag.Position = UDim2.fromOffset(10, 4)
		tag.Size = UDim2.fromOffset(80, 12)
		tag.TextXAlignment = Enum.TextXAlignment.Left
		local n = label(f, "EMPTY", 12, COL.dim, Enum.Font.GothamBold)
		n.Position = UDim2.fromOffset(10, 16)
		n.Size = UDim2.new(1, -16, 0, 14)
		n.TextXAlignment = Enum.TextXAlignment.Left
		n.TextTruncate = Enum.TextTruncate.AtEnd
		local b = label(f, "", 10, COL.dim, Enum.Font.Gotham)
		b.Position = UDim2.fromOffset(10, 30)
		b.Size = UDim2.new(1, -16, 0, 12)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextTruncate = Enum.TextTruncate.AtEnd
		slotTiles[slot] = { frame = f, name = n, bonus = b, stroke = s, scale = sc }
	end

	-- crate banner + toasts (top centre)
	banner = panel(root, "CrateBanner", UDim2.fromOffset(420, 40), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
	banner.Visible = false
	stroke(banner, COL.cyan, 2)
	bannerText = label(banner, "", 15, COL.text, Enum.Font.GothamBlack)
	bannerText.Size = UDim2.fromScale(1, 1)
	toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.AnchorPoint = Vector2.new(0.5, 0)
	toasts.Position = UDim2.new(0.5, 0, 0, 56)
	toasts.Size = UDim2.fromOffset(560, 200)
	toasts.BackgroundTransparency = 1
	toasts.Parent = root
	local tl = Instance.new("UIListLayout")
	tl.Padding = UDim.new(0, 4)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = toasts

	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		screenScale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 640), 0.6, 1)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- off-screen direction arrows (crate / home)
	for name, c in { Crate = COL.cyan, Home = COL.green } do
		local a = label(gui, utf8.char(0x25B2), 34, c, Enum.Font.GothamBlack)
		a.Name = name .. "Arrow"
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.Size = UDim2.fromOffset(40, 40)
		a.TextStrokeTransparency = 0.3
		a.Visible = false
		arrows[name] = a
	end

	-- world marker over your base pad (shown while carrying)
	baseMarker = Instance.new("BillboardGui")
	baseMarker.Name = "CoreBaseMarker"
	baseMarker.Size = UDim2.fromOffset(150, 46)
	baseMarker.AlwaysOnTop = true
	baseMarker.LightInfluence = 0
	baseMarker.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	baseMarker.Enabled = false
	local mb = Instance.new("Frame")
	mb.Size = UDim2.fromScale(1, 1)
	mb.BackgroundColor3 = COL.bg
	mb.BackgroundTransparency = 0.2
	mb.Parent = baseMarker
	corner(mb, 6)
	stroke(mb, COL.green, 2)
	baseMarkerText = label(mb, "YOUR BASE", 14, COL.green, Enum.Font.GothamBlack)
	baseMarkerText.Size = UDim2.fromScale(1, 1)
	baseMarker.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

------------------------------------------------------------------ toasts

local toastN = 0
function Hud.toast(text: string, color: Color3?, kind: string?)
	toastN += 1
	local f = Instance.new("Frame")
	f.LayoutOrder = toastN
	f.Size = UDim2.fromOffset(0, 30)
	f.AutomaticSize = Enum.AutomaticSize.X
	f.BackgroundColor3 = COL.bg
	f.BackgroundTransparency = 0.1
	f.Parent = toasts
	corner(f, 6)
	local s = stroke(f, color or COL.accent, 1.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = f
	local t = label(f, text, 15, color or COL.text, Enum.Font.GothamBlack)
	t.Size = UDim2.fromScale(0, 1)
	t.AutomaticSize = Enum.AutomaticSize.X
	local sc = Instance.new("UIScale")
	sc.Parent = f
	punch(sc, 1.25)
	-- keep at most 4
	local kids = {}
	for _, c in toasts:GetChildren() do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	table.sort(kids, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #kids - 4 do
		kids[i]:Destroy()
	end
	if kind == "crate" then
		Fx.sound("Beep", 0.35, 1.6)
	elseif kind == "lost" then
		Fx.sound("PowerDown", 0.45, 1.4)
	end
	task.delay(if kind == "crate" or kind == "lost" then 3.6 else 2.8, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			TweenService:Create(s, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			task.wait(0.27)
			f:Destroy()
		end
	end)
end

------------------------------------------------------------------ state

function Hud.setState(s: any)
	local prev = state
	state = s
	for _, slot in CoreLoopConfig.Slots do
		local tile = slotTiles[slot]
		local it = s.equipped and s.equipped[slot]
		if it then
			local c = Items.color(it)
			tile.name.Text = string.upper(Items.name(it))
			tile.name.TextColor3 = c
			tile.bonus.Text = Items.bonusText(it)
			tile.stroke.Color = c
			tile.stroke.Thickness = 2
		else
			tile.name.Text = if slot == "Chest" and not (s.equipped and s.equipped.Legs) then "EMPTY  (needs legs)" else "EMPTY"
			tile.name.TextColor3 = COL.dim
			tile.bonus.Text = ""
			tile.stroke.Color = Color3.fromRGB(60, 64, 60)
			tile.stroke.Thickness = 1
		end
		local before = prev.equipped and prev.equipped[slot]
		if (before and before.uid) ~= (it and it.uid) then
			punch(tile.scale, 1.15)
		end
	end
	local w = CoreLoopConfig.Weapons[s.weapon or "Fists"] or CoreLoopConfig.Weapons.Fists
	local wt = slotTiles.Weapon
	wt.name.Text = string.upper(w.name)
	wt.name.TextColor3 = if w.id == "Fists" then COL.text else w.color
	wt.bonus.Text = w.blurb
	wt.stroke.Color = if w.id == "Fists" then Color3.fromRGB(60, 64, 60) else w.color
	if prev.weapon ~= s.weapon then
		punch(wt.scale, 1.15)
	end
end

function Hud.getState(): any
	return state
end

function Hud.scrapGained(amount: number)
	punch(scrapScale, 1.25)
	local f = label(root, "+" .. amount, 20, COL.accent, Enum.Font.GothamBlack)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0.5, 210, 1, -76)
	f.Size = UDim2.fromOffset(100, 24)
	f.TextXAlignment = Enum.TextXAlignment.Left
	f.TextStrokeTransparency = 0.4
	TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 210, 1, -110), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.75, function()
		f:Destroy()
	end)
	Fx.sound("Tick", 0.35, 1.5 + math.random() * 0.2)
end

function Hud.noPower()
	punch(batScale, 1.12)
	batStroke.Color = COL.red
	task.delay(0.25, function()
		batStroke.Color = COL.accent
	end)
end

------------------------------------------------------------------ per frame

-- Points an edge arrow at `pos` when it is off screen (or behind the camera).
local function arrowTo(name: string, pos: Vector3?)
	local a = arrows[name]
	local cam = workspace.CurrentCamera
	if not (a and cam and pos) then
		if a then
			a.Visible = false
		end
		return
	end
	local vp = cam.ViewportSize
	local sp, onScreen = cam:WorldToViewportPoint(pos)
	if onScreen and sp.Z > 0 and sp.X > 30 and sp.X < vp.X - 30 and sp.Y > 30 and sp.Y < vp.Y - 30 then
		a.Visible = false
		return
	end
	local centre = vp / 2
	local d = Vector2.new(sp.X, sp.Y) - centre
	if sp.Z < 0 then
		d = -d
	end
	if d.Magnitude < 1 then
		d = Vector2.new(0, -1)
	end
	local u = d.Unit
	local rx, ry = vp.X / 2 - 50, vp.Y / 2 - 60
	local k = math.min(rx / math.max(math.abs(u.X), 1e-3), ry / math.max(math.abs(u.Y), 1e-3))
	local p = centre + u * k
	a.Position = UDim2.fromOffset(p.X, p.Y)
	a.Rotation = math.deg(math.atan2(u.Y, u.X)) + 90
	a.Visible = true
end

local lastBeep = 0
local lastShownBattery = -1
local carryWas = false

local function plotPad(): BasePart?
	local idx = player:GetAttribute("PlotIndex")
	local yard = workspace:FindFirstChild(CoreLoopConfig.Yard.FolderName)
	local bases = yard and yard:FindFirstChild("Bases")
	local plot = bases and bases:FindFirstChild("Plot" .. tostring(idx))
	local pad = plot and plot:FindFirstChild("Pad")
	return if pad and pad:IsA("BasePart") then pad else nil
end

local function update()
	local piloting = PilotController.getMech() ~= nil
	root.Visible = not piloting
	local t = os.clock()

	-- battery
	local b = (player:GetAttribute("Battery") :: number?) or 0
	local max = (player:GetAttribute("BatteryMax") :: number?) or 100
	local f = math.clamp(b / math.max(max, 1), 0, 1)
	batFill.Size = UDim2.fromScale(f, 1)
	local pct = f * 100
	local col = if pct > 50 then COL.green elseif pct >= CoreLoopConfig.Battery.Low then COL.yellow else COL.red
	local charging = player:GetAttribute("InBase") == true and f < 0.999
	if charging then
		col = col:Lerp(Color3.new(1, 1, 1), 0.25 + 0.2 * math.sin(t * 10))
	elseif pct < CoreLoopConfig.Battery.Low then
		col = col:Lerp(Color3.new(1, 1, 1), 0.3 * (0.5 + 0.5 * math.sin(t * 12)))
		if t - lastBeep > 1.2 and not piloting and pct > 0 then
			lastBeep = t
			Fx.sound("Beep", 0.18, 1.3)
		end
	end
	batFill.BackgroundColor3 = col
	boltLabel.Visible = charging
	if b <= 0.05 then
		batText.Text = "NO POWER - GO HOME"
		batText.TextColor3 = if math.sin(t * 10) > 0 then COL.red else COL.text
	else
		batText.Text = string.format("%d / %d", math.floor(b + 0.5), math.floor(max + 0.5))
		batText.TextColor3 = COL.text
	end
	local shown = math.floor(b)
	if lastShownBattery >= 0 and shown > lastShownBattery + 8 then
		punch(batScale, 1.06)
	end
	if math.abs(shown - lastShownBattery) >= 1 then
		lastShownBattery = shown
	end
	sprintTag.Visible = Controls.isSprinting()
	scrapText.Text = tostring((player:GetAttribute("Scrap") :: number?) or 0)

	-- carry
	local kind = player:GetAttribute("CarryKind")
	if kind then
		local exp = (player:GetAttribute("CarryExpires") :: number?) or 0
		local left = math.max(0, exp - workspace:GetServerTimeNow())
		local total = CoreLoopConfig.Loot.PartExpiry
		if not carryWas then
			carryWas = true
			carry.Visible = true
			punch(carryScale, 1.2)
		end
		local tier = (player:GetAttribute("CarryTier") :: number?) or 0
		local c = if kind == "Cell" then Color3.fromRGB(90, 255, 140) else Items.tierInfo(math.max(tier, 1)).color
		carryName.Text = string.upper(tostring(player:GetAttribute("CarryName") or ""))
		carryName.TextColor3 = c
		carryTime.Text = string.format("%d", math.ceil(left))
		carryFill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
		local hurry = left < 10
		carryFill.BackgroundColor3 = if hurry then COL.red else c
		carryTime.TextColor3 = if hurry and math.sin(t * 14) > 0 then COL.red else COL.text
		if hurry and math.floor(left) ~= math.floor(left + 1 / 60) and left > 0.2 then
			Fx.sound("Tick", 0.45, if left < 5 then 1.8 else 1.4)
			punch(carryScale, 1.05)
		end
		local pad = plotPad()
		baseMarker.Adornee = pad
		baseMarker.Enabled = pad ~= nil and player:GetAttribute("InBase") ~= true
		local char = player.Character
		local rp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pad and rp then
			baseMarkerText.Text = string.format("YOUR BASE  %dm", math.floor((pad.Position - rp.Position).Magnitude))
		end
	elseif carryWas then
		carryWas = false
		carry.Visible = false
		baseMarker.Enabled = false
	end
	local homePad = if kind and player:GetAttribute("InBase") ~= true and not piloting then plotPad() else nil
	arrowTo("Home", if homePad then homePad.Position else nil)

	-- crate banner: the crate with the least time left
	local best: Model? = nil
	local bestLeft = math.huge
	for _, m in CollectionService:GetTagged("CoreCrate") do
		if m:IsA("Model") then
			local exp = (m:GetAttribute("Expires") :: number?) or 0
			local left = exp - workspace:GetServerTimeNow()
			if left > 0 and left < bestLeft then
				best, bestLeft = m, left
			end
		end
	end
	if best and not piloting then
		banner.Visible = true
		local hp = ((best:GetAttribute("HP") :: number?) or 0) / math.max((best:GetAttribute("MaxHP") :: number?) or 1, 1)
		local char = player.Character
		local rp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dist = if rp and best.PrimaryPart then (best.PrimaryPart.Position - rp.Position).Magnitude else 0
		bannerText.Text = string.format("SUPPLY CRATE   %ds   HP %d%%   %dm", math.ceil(bestLeft), math.floor(hp * 100 + 0.5), math.floor(dist))
		bannerText.TextColor3 = if bestLeft < 8 and math.sin(t * 12) > 0 then COL.red else COL.text
	else
		banner.Visible = false
	end
	arrowTo("Crate", if best and best.PrimaryPart and not piloting then best.PrimaryPart.Position else nil)
end

function Hud.start()
	build()
	RunService.RenderStepped:Connect(update)
end

return Hud
