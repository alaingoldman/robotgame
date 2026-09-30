--!strict
-- Inventory of mech armor pieces (Helmet / Chest / Legs x 5 color variants).
-- Clicking a piece equips it on the mech you are piloting.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechBuilder = require(Shared:WaitForChild("MechBuilder"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local PilotController = require(script.Parent.PilotController)

local Inventory = {}

local player = Players.LocalPlayer
local equipPiece = ReplicatedStorage:WaitForChild("MechRemotes"):WaitForChild("EquipPiece") :: RemoteEvent

local COLORS = {
	bg = Color3.fromRGB(18, 20, 18),
	card = Color3.fromRGB(34, 37, 34),
	cardHover = Color3.fromRGB(46, 50, 46),
	text = Color3.fromRGB(228, 228, 216),
	dim = Color3.fromRGB(150, 152, 140),
	accent = Color3.fromRGB(236, 205, 40),
}

-- framing in design units (x MechBuilder.Scale)
local SLOT_VIEW = {
	Helmet = { focus = Vector3.new(0, 15.0, -0.5), dist = 7.5 },
	Chest = { focus = Vector3.new(0, 12.0, -0.5), dist = 24 },
	Legs = { focus = Vector3.new(0, 5.4, 0), dist = 20 },
}
local VIEW_DIR = Vector3.new(0.6, 0.3, -1).Unit -- mech faces -Z; look at its front-right

local gui: ScreenGui
local panel: Frame
local status: TextLabel
local cards: { [string]: { [string]: { frame: Frame, stroke: UIStroke } } } = {}
local previewsBuilt = false
local attrConn: RBXScriptConnection? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function text(parent: Instance, str: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = str
	t.TextSize = size
	t.TextColor3 = color
	t.Font = font or Enum.Font.GothamBold
	t.Parent = parent
	return t
end

local function buildPreview(viewport: ViewportFrame, slot: string, variantId: string)
	local rig = MechBuilder.buildRig("Preview")
	MechBuilder.applySlot(rig, slot, variantId)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	rig.Parent = viewport

	local view = SLOT_VIEW[slot]
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local focus = view.focus * MechBuilder.Scale
	camera.CFrame = CFrame.lookAt(focus + VIEW_DIR * view.dist * MechBuilder.Scale, focus)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function refreshSelection()
	local mech = PilotController.getMech()
	for slot, row in cards do
		local equipped = mech and mech:GetAttribute(slot)
		for variantId, card in row do
			local on = equipped == variantId
			card.stroke.Color = on and COLORS.accent or Color3.fromRGB(60, 64, 60)
			card.stroke.Thickness = on and 2.5 or 1
		end
	end
	if mech then
		status.Text = "Click a piece to equip it on your mech."
		status.TextColor3 = COLORS.dim
	else
		status.Text = "Pilot a mech [E] to equip pieces."
		status.TextColor3 = COLORS.dim
	end
end

local function onCardClicked(slot: string, variantId: string)
	if not PilotController.getMech() then
		status.Text = "You need to be piloting a mech to equip pieces."
		status.TextColor3 = Color3.fromRGB(235, 90, 70)
		return
	end
	equipPiece:FireServer(slot, variantId)
end

local function buildCard(row: Frame, slot: string, variant: MechConfig.Variant, order: number)
	local card = Instance.new("TextButton")
	card.Name = variant.id
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(112, 132)
	card.BackgroundColor3 = COLORS.card
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = row
	corner(card, 6)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(60, 64, 60)
	stroke.Parent = card

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundColor3 = Color3.fromRGB(26, 28, 26)
	viewport.Position = UDim2.fromOffset(6, 6)
	viewport.Size = UDim2.new(1, -12, 0, 96)
	viewport.Ambient = Color3.fromRGB(150, 150, 150)
	viewport.LightColor = Color3.fromRGB(255, 250, 235)
	viewport.LightDirection = Vector3.new(-0.5, -1, 0.6)
	viewport.Parent = card
	corner(viewport, 4)

	local swatch = Instance.new("Frame")
	swatch.BackgroundColor3 = variant.palette.main
	swatch.BorderSizePixel = 0
	swatch.Position = UDim2.new(0, 8, 1, -22)
	swatch.Size = UDim2.fromOffset(12, 12)
	swatch.Parent = card
	corner(swatch, 3)

	local name = text(card, string.upper(variant.displayName), 11, COLORS.text)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.new(0, 26, 1, -28)
	name.Size = UDim2.new(1, -30, 0, 24)

	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = COLORS.cardHover
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = COLORS.card
	end)
	card.Activated:Connect(function()
		onCardClicked(slot, variant.id)
	end)

	cards[slot] = cards[slot] or {}
	cards[slot][variant.id] = { frame = card :: any, stroke = stroke }
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "MechInventory"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 20, 1, -24)
	toggle.Size = UDim2.fromOffset(150, 40)
	toggle.BackgroundColor3 = COLORS.bg
	toggle.BackgroundTransparency = 0.15
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = COLORS.text
	toggle.Text = "INVENTORY  [I]"
	toggle.Parent = gui
	corner(toggle, 6)
	local tStroke = Instance.new("UIStroke")
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tStroke.Color = COLORS.accent
	tStroke.Parent = toggle

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(780, 560)
	panel.BackgroundColor3 = COLORS.bg
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 10)
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = COLORS.accent
	pStroke.Thickness = 1.5
	pStroke.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local title = text(panel, "HANGAR  //  ARMOR INVENTORY", 20, COLORS.text)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.new(1, -80, 0, 32)

	local stripe = Instance.new("Frame")
	stripe.BackgroundColor3 = COLORS.accent
	stripe.BorderSizePixel = 0
	stripe.Position = UDim2.fromOffset(24, 50)
	stripe.Size = UDim2.new(0, 60, 0, 3)
	stripe.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = COLORS.card
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = COLORS.text
	close.Text = "X"
	close.Parent = panel
	corner(close, 6)

	for i, slot in MechConfig.Slots do
		local y = 68 + (i - 1) * 150
		local label = text(panel, string.upper(slot), 16, COLORS.accent)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(24, y + 50)
		label.Size = UDim2.fromOffset(110, 24)
		local sub = text(panel, if slot == "Helmet" then "Head" elseif slot == "Chest" then "Torso + arms" else "Cockpit + legs + feet", 11, COLORS.dim, Enum.Font.Gotham)
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Position = UDim2.fromOffset(24, y + 72)
		sub.Size = UDim2.fromOffset(110, 18)

		local row = Instance.new("Frame")
		row.Name = slot
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(140, y)
		row.Size = UDim2.new(1, -160, 0, 136)
		row.Parent = panel
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row

		for j, variant in MechConfig.Variants do
			buildCard(row, slot, variant, j)
		end
	end

	status = text(panel, "", 13, COLORS.dim, Enum.Font.Gotham)
	status.Position = UDim2.new(0, 24, 1, -40)
	status.Size = UDim2.new(1, -48, 0, 24)
	status.TextXAlignment = Enum.TextXAlignment.Left

	local function setOpen(open: boolean)
		panel.Visible = open
		if open and not previewsBuilt then
			previewsBuilt = true
			for slot, row in cards do
				for variantId, card in row do
					buildPreview(card.frame:FindFirstChild("Preview") :: ViewportFrame, slot, variantId)
				end
			end
		end
		if open then
			-- shrink the panel on small screens
			local vp = workspace.CurrentCamera.ViewportSize
			scale.Scale = math.min(1, (vp.X - 40) / 780, (vp.Y - 40) / 560)
			refreshSelection()
		end
	end
	Inventory.setOpen = setOpen

	toggle.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function Inventory.setOpen(_: boolean) end

function Inventory.start()
	buildGui()

	-- The default camera uses I for zoom, so bind above it and sink the key.
	ContextActionService:BindActionAtPriority("MechInventory", function(_, state)
		if state == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			Inventory.setOpen(not panel.Visible)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 100, Enum.KeyCode.I)

	PilotController.Changed:Connect(function(mech: Model?)
		if attrConn then
			attrConn:Disconnect()
			attrConn = nil
		end
		if mech then
			attrConn = mech.AttributeChanged:Connect(refreshSelection)
		end
		refreshSelection()
	end)
	refreshSelection()
end

return Inventory
