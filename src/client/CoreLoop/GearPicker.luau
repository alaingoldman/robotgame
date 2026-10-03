--!strict
-- GEAR PICKER (owner / Studio): pick ANY armour piece or weapon and wear it
-- at once (server: CoreLoop/Picker re-checks permission). Shown only when the
-- server set the player attribute "GearPicker". Toggle with the HUD button
-- or G; Esc / gamepad B / X closes. Tabs ARMS / LEGS / CHEST / WEAPONS, one
-- card per tier (colour, number, name, "model not imported yet" when the
-- tier has no GearAssets id), plus FULL SET T# and UNEQUIP ALL.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local GearAssets = require(Shared:WaitForChild("GearAssets"))
local Fx = require(script.Parent.Fx)

local GearPicker = {}

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("CoreRemotes"):WaitForChild("GearPick") :: RemoteEvent

local COL = {
	bg = Color3.fromRGB(18, 20, 18),
	card = Color3.fromRGB(34, 37, 34),
	cardHover = Color3.fromRGB(46, 50, 46),
	text = Color3.fromRGB(228, 228, 216),
	dim = Color3.fromRGB(150, 152, 140),
	accent = Color3.fromRGB(236, 205, 40),
	red = Color3.fromRGB(255, 90, 70),
	line = Color3.fromRGB(60, 64, 60),
}
local TABS = { "Arms", "Legs", "Chest", "Weapons" }

local gui: ScreenGui
local panel: Frame
local scale: UIScale
local grid: ScrollingFrame
local toggle: TextButton
local tabButtons: { [string]: TextButton } = {}
local tab = "Arms"
local open = false
local state: any = { equipped = {}, weapon = "Fists" }

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
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, size: UDim2, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color or COL.card
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 12
	b.TextColor3 = COL.text
	b.Text = text
	b.Parent = parent
	corner(b, 5)
	return b
end

local function press(g: GuiObject)
	local s = g:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = g
	s.Scale = 0.9
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Fx.sound("Tick", 0.35, 1.3)
end

------------------------------------------------------------------ cards

local function card(order: number, title: string, sub: string, color: Color3, worn: boolean, missing: boolean, onClick: () -> ())
	local c = Instance.new("TextButton")
	c.LayoutOrder = order
	c.BackgroundColor3 = if worn then Color3.fromRGB(58, 54, 26) else COL.card
	c.AutoButtonColor = false
	c.Text = ""
	c.Parent = grid
	corner(c, 6)
	stroke(c, if worn then COL.accent else color, if worn then 2.5 else 1.2)
	local sw = Instance.new("Frame")
	sw.BackgroundColor3 = color
	sw.BorderSizePixel = 0
	sw.Position = UDim2.fromOffset(6, 6)
	sw.Size = UDim2.new(1, -12, 0, 6)
	sw.Parent = c
	corner(sw, 3)
	local t = label(c, title, 18, color, Enum.Font.GothamBlack)
	t.Position = UDim2.fromOffset(8, 16)
	t.Size = UDim2.new(1, -16, 0, 20)
	local n = label(c, sub, 11, COL.text, Enum.Font.GothamBold)
	n.Position = UDim2.fromOffset(8, 38)
	n.Size = UDim2.new(1, -16, 0, 28)
	n.TextWrapped = true
	n.TextYAlignment = Enum.TextYAlignment.Top
	if missing then
		local m = label(c, "model not imported yet", 9, COL.dim, Enum.Font.Gotham)
		m.Position = UDim2.new(0, 8, 1, -16)
		m.Size = UDim2.new(1, -16, 0, 12)
	elseif worn then
		local m = label(c, "WEARING", 9, COL.accent, Enum.Font.GothamBlack)
		m.Position = UDim2.new(0, 8, 1, -16)
		m.Size = UDim2.new(1, -16, 0, 12)
	end
	c.MouseEnter:Connect(function()
		if not worn then
			c.BackgroundColor3 = COL.cardHover
		end
	end)
	c.MouseLeave:Connect(function()
		if not worn then
			c.BackgroundColor3 = COL.card
		end
	end)
	c.Activated:Connect(function()
		press(c)
		onClick()
	end)
end

local function refresh()
	if not gui then
		return
	end
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == tab then Color3.fromRGB(70, 64, 24) else COL.card
		b.TextColor3 = if name == tab then COL.accent else COL.text
	end
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if tab == "Weapons" then
		local ids = table.clone(CoreLoopConfig.WeaponOrder)
		table.sort(ids, function(a, b)
			local wa, wb = CoreLoopConfig.Weapons[a], CoreLoopConfig.Weapons[b]
			if (wa.ranged == true) ~= (wb.ranged == true) then
				return not wa.ranged
			end
			return wa.tier < wb.tier
		end)
		for i, id in ids do
			local w = CoreLoopConfig.Weapons[id]
			local title = if id == "Fists" then "FISTS" else string.format("T%d %s", w.tier, if w.ranged then "RANGED" else "MELEE")
			card(i, title, w.name, w.color, state.weapon == id, id ~= "Fists" and GearAssets.Weapons == nil, function()
				remote:FireServer("Weapon", id)
			end)
		end
	else
		local slot = tab
		local worn = state.equipped and state.equipped[slot]
		for t = 1, CoreLoopConfig.MaxTier do
			local info = CoreLoopConfig.Tiers[t]
			card(t, string.format("T%d", t), info.name, info.color, worn ~= nil and worn.tier == t, GearAssets.Tiers[t] == nil, function()
				remote:FireServer("Piece", slot, t)
			end)
		end
	end
end

------------------------------------------------------------------ build

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoreGearPicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7

	toggle = button(gui, "GEAR PICKER  [G]", UDim2.fromOffset(150, 34), COL.bg)
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 20, 1, -72)
	toggle.TextSize = 13
	toggle.TextColor3 = COL.accent
	stroke(toggle, COL.accent, 1.5)
	toggle.Activated:Connect(function()
		press(toggle)
		GearPicker.setOpen(not open)
	end)

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(820, 520)
	panel.BackgroundColor3 = COL.bg
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 10)
	stroke(panel, COL.accent, 1.5)
	scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = label(panel, "GEAR PICKER  //  TEST ANY PIECE", 20, COL.text, Enum.Font.GothamBlack)
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.fromOffset(500, 30)
	local close = button(panel, "X", UDim2.fromOffset(32, 32))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Activated:Connect(function()
		GearPicker.setOpen(false)
	end)

	-- tabs
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(24, 54)
	tabs.Size = UDim2.fromOffset(500, 32)
	tabs.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	for i, name in TABS do
		local b = button(tabs, string.upper(name), UDim2.fromOffset(110, 32))
		b.LayoutOrder = i
		b.Activated:Connect(function()
			press(b)
			tab = name
			refresh()
		end)
		tabButtons[name] = b
	end
	local un = button(panel, "UNEQUIP ALL", UDim2.fromOffset(130, 32), Color3.fromRGB(70, 36, 32))
	un.AnchorPoint = Vector2.new(1, 0)
	un.Position = UDim2.new(1, -24, 0, 54)
	un.Activated:Connect(function()
		press(un)
		remote:FireServer("UnequipAll")
	end)

	-- full sets
	local sets = Instance.new("Frame")
	sets.BackgroundTransparency = 1
	sets.Position = UDim2.fromOffset(24, 94)
	sets.Size = UDim2.new(1, -48, 0, 50)
	sets.Parent = panel
	local sl = label(sets, "FULL SET", 10, COL.accent, Enum.Font.GothamBlack)
	sl.Size = UDim2.fromOffset(60, 50)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(64, 0)
	row.Size = UDim2.new(1, -64, 1, 0)
	row.Parent = sets
	local rg = Instance.new("UIGridLayout")
	rg.CellSize = UDim2.fromOffset(65, 22)
	rg.CellPadding = UDim2.fromOffset(4, 4)
	rg.SortOrder = Enum.SortOrder.LayoutOrder
	rg.Parent = row
	for t = 1, CoreLoopConfig.MaxTier do
		local info = CoreLoopConfig.Tiers[t]
		local b = button(row, "SET T" .. t, UDim2.fromOffset(65, 22))
		b.LayoutOrder = t
		b.TextSize = 10
		b.TextColor3 = info.color
		stroke(b, info.color, 1)
		b.Activated:Connect(function()
			press(b)
			remote:FireServer("Set", t)
		end)
	end

	grid = Instance.new("ScrollingFrame")
	grid.Position = UDim2.fromOffset(24, 152)
	grid.Size = UDim2.new(1, -48, 1, -170)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = panel
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(148, 92)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid

	gui.Parent = player:WaitForChild("PlayerGui")
end

------------------------------------------------------------------ public

function GearPicker.isOpen(): boolean
	return open
end

function GearPicker.setOpen(on: boolean)
	if on == open or not gui then
		return
	end
	open = on
	panel.Visible = on
	if on then
		local vp = workspace.CurrentCamera.ViewportSize
		local s = math.min(1, (vp.X - 30) / 820, (vp.Y - 30) / 520)
		scale.Scale = s * 0.85
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = s }):Play()
		refresh()
		Fx.sound("Pop", 0.4, 1.1)
		ContextActionService:BindActionAtPriority("CoreGearPickerClose", function(_, st)
			if st == Enum.UserInputState.Begin then
				GearPicker.setOpen(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 60, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("CoreGearPickerClose")
		Fx.sound("Pop", 0.3, 0.9)
	end
end

-- the owner's State snapshot (same as the HUD / locker get)
function GearPicker.setState(s: any)
	state = s
	if open then
		refresh()
	end
end

function GearPicker.start()
	local function apply()
		local ok = player:GetAttribute("GearPicker") == true
		if ok and not gui then
			build()
		end
		if gui then
			gui.Enabled = ok
			if not ok then
				GearPicker.setOpen(false)
			end
		end
	end
	player:GetAttributeChangedSignal("GearPicker"):Connect(apply)
	apply()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.G then
			return
		end
		if gui and gui.Enabled then
			GearPicker.setOpen(not open)
		end
	end)
end

return GearPicker
