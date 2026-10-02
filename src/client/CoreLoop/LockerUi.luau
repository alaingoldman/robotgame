--!strict
-- The base's PART LOCKER / EQUIP STATION panel (ScreenGui "CoreLocker").
-- Opened by the base prompts (OpenLocker remote). Left: your four slots (+
-- UNEQUIP) and weapons; right: locker cards with a 3D preview (click =
-- equip, the small button = recycle for scrap); bottom: battery upgrade.
-- The rule "no CHEST without LEGS" is enforced by the server; the panel
-- also shows it. Closes when you leave your base, on X, Esc or gamepad B.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local CoreShared = Shared:WaitForChild("CoreLoop")
local Items = require(CoreShared:WaitForChild("Items"))
local PartBuilder = require(CoreShared:WaitForChild("PartBuilder"))
local Fx = require(script.Parent.Fx)

local LockerUi = {}

local player = Players.LocalPlayer
local lockerRemote = ReplicatedStorage:WaitForChild("CoreRemotes"):WaitForChild("Locker") :: RemoteEvent

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

local gui: ScreenGui
local panel: Frame
local panelScale: UIScale
local slotRows: { [string]: { name: TextLabel, bonus: TextLabel, button: TextButton, stroke: UIStroke } } = {}
local weaponRow: Frame
local grid: ScrollingFrame
local countLabel: TextLabel
local shopLabel: TextLabel
local shopButton: TextButton
local hint: TextLabel
local state: any = { equipped = {}, locker = {}, weapons = { "Fists" }, weapon = "Fists", shopLevel = 0, lockerSize = 12 }
local open = false

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

local function press(gui: GuiObject)
	local s = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = gui
	s.Scale = 0.9
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Fx.sound("Tick", 0.35, 1.3)
end

local function preview(vp: ViewportFrame, item: any)
	for _, c in vp:GetChildren() do
		if not c:IsA("UICorner") then
			c:Destroy()
		end
	end
	local ok, model = pcall(PartBuilder.display, item)
	if not ok then
		return
	end
	local m = model :: Model
	m:PivotTo(CFrame.new())
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = size.Magnitude * 1.15 + 0.6
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0.55, 0.3, -1).Unit * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

------------------------------------------------------------------ build

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoreLocker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Enabled = false

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(820, 500)
	panel.BackgroundColor3 = COL.bg
	panel.BackgroundTransparency = 0.04
	panel.Parent = gui
	corner(panel, 10)
	stroke(panel, COL.accent, 1.5)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local title = label(panel, "BASE  //  EQUIP STATION", 20, COL.text, Enum.Font.GothamBlack)
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.fromOffset(500, 30)
	local stripe = Instance.new("Frame")
	stripe.BackgroundColor3 = COL.accent
	stripe.BorderSizePixel = 0
	stripe.Position = UDim2.fromOffset(24, 48)
	stripe.Size = UDim2.fromOffset(60, 3)
	stripe.Parent = panel
	local close = button(panel, "X", UDim2.fromOffset(32, 32))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.TextSize = 16
	close.Activated:Connect(function()
		LockerUi.setOpen(false)
	end)

	-- left column: slots
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(24, 62)
	left.Size = UDim2.fromOffset(300, 380)
	left.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = left
	for i, slot in CoreLoopConfig.Slots do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.fromOffset(300, 58)
		row.BackgroundColor3 = COL.card
		row.Parent = left
		corner(row, 6)
		local s = stroke(row, COL.line, 1)
		local tag = label(row, string.upper(slot), 11, COL.accent, Enum.Font.GothamBlack)
		tag.Position = UDim2.fromOffset(10, 6)
		tag.Size = UDim2.fromOffset(120, 12)
		local n = label(row, "EMPTY", 13, COL.dim)
		n.Position = UDim2.fromOffset(10, 20)
		n.Size = UDim2.fromOffset(200, 16)
		n.TextTruncate = Enum.TextTruncate.AtEnd
		local b = label(row, "", 11, COL.dim, Enum.Font.Gotham)
		b.Position = UDim2.fromOffset(10, 38)
		b.Size = UDim2.fromOffset(200, 14)
		b.TextTruncate = Enum.TextTruncate.AtEnd
		local un = button(row, "UNEQUIP", UDim2.fromOffset(76, 26))
		un.AnchorPoint = Vector2.new(1, 0.5)
		un.Position = UDim2.new(1, -10, 0.5, 0)
		un.Activated:Connect(function()
			press(un)
			lockerRemote:FireServer("Unequip", slot)
		end)
		slotRows[slot] = { name = n, bonus = b, button = un, stroke = s }
	end
	local wl = label(left, "WEAPON", 11, COL.accent, Enum.Font.GothamBlack)
	wl.LayoutOrder = 10
	wl.Size = UDim2.fromOffset(300, 16)
	weaponRow = Instance.new("Frame")
	weaponRow.LayoutOrder = 11
	weaponRow.BackgroundTransparency = 1
	weaponRow.Size = UDim2.fromOffset(300, 30)
	weaponRow.Parent = left
	local wlay = Instance.new("UIListLayout")
	wlay.FillDirection = Enum.FillDirection.Horizontal
	wlay.Padding = UDim.new(0, 6)
	wlay.Parent = weaponRow

	-- right: locker grid
	countLabel = label(panel, "LOCKER  0 / 12", 11, COL.accent, Enum.Font.GothamBlack)
	countLabel.Position = UDim2.fromOffset(344, 62)
	countLabel.Size = UDim2.fromOffset(300, 14)
	grid = Instance.new("ScrollingFrame")
	grid.Position = UDim2.fromOffset(344, 82)
	grid.Size = UDim2.fromOffset(452, 340)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = panel
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(140, 160)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid

	-- bottom: battery shop + hint
	shopLabel = label(panel, "", 13, COL.text)
	shopLabel.Position = UDim2.new(0, 24, 1, -48)
	shopLabel.Size = UDim2.fromOffset(420, 18)
	shopButton = button(panel, "UPGRADE BATTERY", UDim2.fromOffset(170, 30), Color3.fromRGB(40, 80, 50))
	shopButton.Position = UDim2.new(0, 450, 1, -54)
	shopButton.Activated:Connect(function()
		press(shopButton)
		lockerRemote:FireServer("BuyBattery")
	end)
	hint = label(panel, "Click a part to equip it. Legs / arms / head any time - CHEST needs LEGS.", 11, COL.dim, Enum.Font.Gotham)
	hint.Position = UDim2.new(0, 24, 1, -26)
	hint.Size = UDim2.fromOffset(700, 14)

	gui.Parent = player:WaitForChild("PlayerGui")
end

------------------------------------------------------------------ refresh

local function card(item: any, order: number)
	local c = Instance.new("TextButton")
	c.Name = item.uid
	c.LayoutOrder = order
	c.BackgroundColor3 = COL.card
	c.AutoButtonColor = false
	c.Text = ""
	c.Parent = grid
	corner(c, 6)
	local color = Items.color(item)
	local blocked = item.slot == "Chest" and not state.equipped.Legs
	stroke(c, if blocked then COL.red else color, 1.5)
	local vp = Instance.new("ViewportFrame")
	vp.Position = UDim2.fromOffset(5, 5)
	vp.Size = UDim2.new(1, -10, 0, 86)
	vp.BackgroundColor3 = Color3.fromRGB(26, 28, 26)
	vp.Ambient = Color3.fromRGB(150, 150, 150)
	vp.LightColor = Color3.fromRGB(255, 250, 235)
	vp.LightDirection = Vector3.new(-0.5, -1, 0.6)
	vp.Parent = c
	corner(vp, 4)
	preview(vp, item)
	local t = Items.tierInfo(item.tier or 1)
	local tierTag = label(c, string.upper(t.name) .. "  " .. string.upper(item.slot or ""), 10, color, Enum.Font.GothamBlack)
	tierTag.Position = UDim2.fromOffset(8, 94)
	tierTag.Size = UDim2.new(1, -16, 0, 12)
	local n = label(c, CoreLoopConfig.FamilyNames[t.family] or t.family, 12, COL.text, Enum.Font.GothamBold)
	n.Position = UDim2.fromOffset(8, 107)
	n.Size = UDim2.new(1, -16, 0, 14)
	local b = label(c, if blocked then "needs LEGS first" else Items.bonusText(item), 10, if blocked then COL.red else COL.dim, Enum.Font.Gotham)
	b.Position = UDim2.fromOffset(8, 122)
	b.Size = UDim2.new(1, -16, 0, 12)
	b.TextTruncate = Enum.TextTruncate.AtEnd
	local rec = button(c, string.format("RECYCLE +%d", (item.tier or 1) * CoreLoopConfig.RecycleScrapPerTier), UDim2.new(1, -16, 0, 18))
	rec.Position = UDim2.fromOffset(8, 137)
	rec.TextSize = 10
	rec.BackgroundColor3 = Color3.fromRGB(60, 40, 36)
	rec.Activated:Connect(function()
		press(rec)
		lockerRemote:FireServer("Recycle", item.uid)
	end)
	c.MouseEnter:Connect(function()
		c.BackgroundColor3 = COL.cardHover
	end)
	c.MouseLeave:Connect(function()
		c.BackgroundColor3 = COL.card
	end)
	c.Activated:Connect(function()
		press(c)
		lockerRemote:FireServer("Equip", item.uid)
	end)
end

local function refresh()
	if not gui then
		return
	end
	for slot, row in slotRows do
		local it = state.equipped[slot]
		if it then
			row.name.Text = string.upper(Items.name(it))
			row.name.TextColor3 = Items.color(it)
			row.bonus.Text = Items.bonusText(it)
			row.stroke.Color = Items.color(it)
			row.button.Visible = true
		else
			row.name.Text = if slot == "Chest" and not state.equipped.Legs then "EMPTY - needs LEGS" else "EMPTY"
			row.name.TextColor3 = COL.dim
			row.bonus.Text = ""
			row.stroke.Color = COL.line
			row.button.Visible = false
		end
	end
	for _, c in weaponRow:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local owned: { [string]: boolean } = {}
	for _, id in state.weapons or {} do
		owned[id] = true
	end
	for _, id in CoreLoopConfig.WeaponOrder do
		if owned[id] then
			local w = CoreLoopConfig.Weapons[id]
			local b = button(weaponRow, string.upper(if id == "Fists" then "FISTS" else w.name), UDim2.fromOffset(70, 28), if state.weapon == id then Color3.fromRGB(70, 64, 24) else COL.card)
			b.TextSize = 9
			b.TextWrapped = true
			if state.weapon == id then
				stroke(b, COL.accent, 1.5)
			end
			b.Activated:Connect(function()
				press(b)
				lockerRemote:FireServer("Weapon", id)
			end)
		end
	end
	for _, c in grid:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local list = table.clone(state.locker or {})
	table.sort(list, function(a, b)
		if (a.tier or 0) ~= (b.tier or 0) then
			return (a.tier or 0) > (b.tier or 0)
		end
		return (a.slot or "") < (b.slot or "")
	end)
	for i, it in list do
		card(it, i)
	end
	countLabel.Text = string.format("LOCKER  %d / %d", #list, state.lockerSize or 12)
	local cost = CoreLoopConfig.Battery.ShopCosts[(state.shopLevel or 0) + 1]
	local max = (player:GetAttribute("BatteryMax") :: number?) or 100
	if cost then
		shopLabel.Text = string.format("BATTERY  %d max   -   +%d for %d scrap", max, CoreLoopConfig.Battery.ShopStep, cost)
		shopButton.Visible = true
	else
		shopLabel.Text = string.format("BATTERY  %d max   -   shop maxed", max)
		shopButton.Visible = false
	end
end

function LockerUi.setState(s: any)
	state = s
	if open then
		refresh()
	end
end

function LockerUi.isOpen(): boolean
	return open
end

function LockerUi.setOpen(on: boolean)
	if on == open then
		return
	end
	open = on
	gui.Enabled = on
	if on then
		local vp = workspace.CurrentCamera.ViewportSize
		panelScale.Scale = math.min(1, (vp.X - 30) / 820, (vp.Y - 30) / 500) * 0.85
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = panelScale.Scale / 0.85 }):Play()
		refresh()
		Fx.sound("Pop", 0.4, 1.1)
		ContextActionService:BindActionAtPriority("CoreLockerClose", function(_, st)
			if st == Enum.UserInputState.Begin then
				LockerUi.setOpen(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("CoreLockerClose")
		Fx.sound("Pop", 0.3, 0.9)
	end
end

function LockerUi.start()
	build()
	player:GetAttributeChangedSignal("InBase"):Connect(function()
		if open and player:GetAttribute("InBase") ~= true then
			LockerUi.setOpen(false)
		end
	end)
	player:GetAttributeChangedSignal("BatteryMax"):Connect(function()
		if open then
			refresh()
		end
	end)
end

return LockerUi
