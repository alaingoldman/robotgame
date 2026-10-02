--!strict
-- Local world dressing for the core loop:
--   loot     bob + spin (local CFrame of the anchored handle), a label with
--            the name / bonus / expiry countdown; visible within 40 studs, or
--            within your head part's scanner range (ScanRange) - through walls
--   cargo    countdown over every carried part (all players)
--   crates   the ring shrinks with the timer, the timer / HP bar update, the
--            crate shudders harder as it breaks down
--   bases    prompts of other players' plots are hidden; the charger prompt
--            shows the next upgrade's cost
--   beacons  "ScrapyardBlink" lights blink
--   camfade  map props right at / around the camera fade out locally (the
--            base locker / station sit behind the pad, so standing on the
--            drop zone facing the yard put the camera inside the locker and
--            its doors filled the bottom of the screen)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))

local World = {}

local player = Players.LocalPlayer

type LootView = { model: Model, handle: BasePart, base: CFrame, gui: BillboardGui, timer: TextLabel, phase: number }
local loots: { [Model]: LootView } = {}
local cargoGuis: { [Model]: { gui: BillboardGui, timer: TextLabel } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function makeLabel(model: Model, adornee: BasePart, color: Color3, name: string, bonus: string, offset: number): (BillboardGui, TextLabel)
	local g = Instance.new("BillboardGui")
	g.Name = "CoreLootLabel"
	g.Size = UDim2.fromOffset(190, 62)
	g.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	g.LightInfluence = 0
	g.AlwaysOnTop = true
	g.Adornee = adornee
	local n = Instance.new("TextLabel")
	n.Size = UDim2.new(1, 0, 0, 20)
	n.BackgroundTransparency = 1
	n.Font = Enum.Font.GothamBlack
	n.TextScaled = true
	n.Text = string.upper(name)
	n.TextColor3 = color
	n.TextStrokeTransparency = 0.2
	n.Parent = g
	local b = Instance.new("TextLabel")
	b.Position = UDim2.fromOffset(0, 20)
	b.Size = UDim2.new(1, 0, 0, 14)
	b.BackgroundTransparency = 1
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = bonus
	b.TextColor3 = Color3.fromRGB(228, 228, 216)
	b.TextStrokeTransparency = 0.3
	b.Parent = g
	local t = Instance.new("TextLabel")
	t.Name = "Timer"
	t.Position = UDim2.fromOffset(0, 35)
	t.Size = UDim2.new(1, 0, 0, 26)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = ""
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.Parent = g
	g.Parent = player:WaitForChild("PlayerGui")
	return g, t
end

local function addLoot(model: Instance)
	if not model:IsA("Model") or loots[model] then
		return
	end
	local handle = model.PrimaryPart or model:WaitForChild("Handle", 5) :: BasePart?
	if not handle or not model.Parent then
		return
	end
	local color = (model:GetAttribute("Color") :: Color3?) or Color3.new(1, 1, 1)
	local _, size = model:GetBoundingBox()
	local g, t = makeLabel(model, handle, color, tostring(model:GetAttribute("Name") or ""), tostring(model:GetAttribute("Bonus") or ""), size.Y / 2 + 2.2)
	loots[model] = { model = model, handle = handle, base = handle.CFrame, gui = g, timer = t, phase = math.random() * 6 }
end

local function removeLoot(model: Instance)
	local v = loots[model :: Model]
	if v then
		v.gui:Destroy()
		loots[model :: Model] = nil
	end
end

local function addCargo(model: Instance)
	if not model:IsA("Model") or cargoGuis[model] then
		return
	end
	local handle = model.PrimaryPart or model:FindFirstChild("Handle") :: BasePart?
	if not handle then
		return
	end
	local g = Instance.new("BillboardGui")
	g.Name = "CoreCargoTimer"
	g.Size = UDim2.fromOffset(70, 30)
	g.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	g.LightInfluence = 0
	g.AlwaysOnTop = true
	g.MaxDistance = 150
	g.Adornee = handle
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.1
	t.Parent = g
	g.Parent = player:WaitForChild("PlayerGui")
	cargoGuis[model] = { gui = g, timer = t }
end

local function track(tag: string, add: (Instance) -> (), remove: (Instance) -> ())
	for _, m in CollectionService:GetTagged(tag) do
		task.spawn(add, m)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
end

------------------------------------------------------------------ bases

local function setupPrompts()
	local yard = workspace:WaitForChild(CoreLoopConfig.Yard.FolderName, 30)
	local bases = yard and yard:WaitForChild("Bases", 10)
	if not bases then
		return
	end
	local function refresh()
		local mine = player:GetAttribute("PlotIndex")
		local level = (player:GetAttribute("ShopLevel") :: number?) or 0
		local cost = CoreLoopConfig.Battery.ShopCosts[level + 1]
		for _, plot in bases:GetChildren() do
			local own = plot:GetAttribute("PlotIndex") == mine
			for _, p in plot:GetDescendants() do
				if p:IsA("ProximityPrompt") then
					p.Enabled = own
					if p.ObjectText == "Charger" or p.ActionText:sub(1, 7) == "Upgrade" then
						p.ActionText = if cost then string.format("Upgrade Battery (%d scrap)", cost) else "Battery maxed"
					end
				end
			end
		end
	end
	refresh()
	player:GetAttributeChangedSignal("PlotIndex"):Connect(refresh)
	player:GetAttributeChangedSignal("ShopLevel"):Connect(refresh)
	bases.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(refresh)
		end
	end)
end

------------------------------------------------------------------ camera fade

local FADE_RANGE = 3 -- studs from the camera to a part's box where it starts fading
local FADE_MAX = 0.85 -- LocalTransparencyModifier just outside the touch range (touching / inside = fully hidden)
local faded: { [BasePart]: boolean } = {}
local fadeParams = OverlapParams.new()
fadeParams.FilterType = Enum.RaycastFilterType.Include
fadeParams.MaxParts = 64

local function boxDistance(part: BasePart, pos: Vector3): number
	local rel = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	local dx = math.max(math.abs(rel.X) - h.X, 0)
	local dy = math.max(math.abs(rel.Y) - h.Y, 0)
	local dz = math.max(math.abs(rel.Z) - h.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function fadeNearCamera()
	local yard = workspace:FindFirstChild("Scrapyard")
	local cam = workspace.CurrentCamera
	if not (yard and cam) then
		return
	end
	local pos = cam.CFrame.Position
	fadeParams.FilterDescendantsInstances = { yard }
	local seen: { [BasePart]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(pos, FADE_RANGE, fadeParams) do
		-- ground-level slabs (floor, pads, edges) never block the view
		if part.Transparency >= 1 or part.Position.Y + part.Size.Magnitude / 2 < 1.5 or part.Size.Y < 0.6 and part.Position.Y < 1 then
			continue
		end
		local d = boxDistance(part, pos)
		if d < FADE_RANGE then
			seen[part] = true
			faded[part] = true
			part.LocalTransparencyModifier = if d <= 0.6 then 1 else FADE_MAX * math.clamp(1 - (d - 0.6) / (FADE_RANGE - 0.6), 0, 1)
		end
	end
	for part in faded do
		if not seen[part] then
			part.LocalTransparencyModifier = 0
			faded[part] = nil
		end
	end
end

------------------------------------------------------------------ frame

local function step(dt: number)
	local t = os.clock()
	local st = now()
	local char = player.Character
	local rp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local scan = (player:GetAttribute("ScanRange") :: number?) or 0
	local see = math.max(40, scan)
	fadeNearCamera()
	for model, v in loots do
		if not model.Parent then
			removeLoot(model)
			continue
		end
		if v.handle.Anchored then
			v.handle.CFrame = v.base * CFrame.new(0, 0.45 * math.sin(t * 2.4 + v.phase), 0) * CFrame.Angles(0, (t * 1.3 + v.phase) % (math.pi * 2), 0)
		end
		local left = ((model:GetAttribute("Expires") :: number?) or st) - st
		v.timer.Text = string.format("%ds", math.max(0, math.ceil(left)))
		v.timer.TextColor3 = if left < 10 and math.sin(t * 12) > 0 then Color3.fromRGB(255, 72, 72) else Color3.new(1, 1, 1)
		local dist = if rp then (rp.Position - v.handle.Position).Magnitude else 0
		v.gui.Enabled = dist <= see
	end
	for model, c in cargoGuis do
		if not model.Parent then
			c.gui:Destroy()
			cargoGuis[model] = nil
			continue
		end
		local owner = Players:GetPlayerFromCharacter(model.Parent)
		local exp = owner and (owner:GetAttribute("CarryExpires") :: number?)
		if exp then
			local left = exp - st
			c.timer.Text = string.format("%d", math.max(0, math.ceil(left)))
			c.timer.TextColor3 = if left < 10 and math.sin(t * 12) > 0 then Color3.fromRGB(255, 72, 72) else Color3.new(1, 1, 1)
		end
	end
	-- crates
	for _, m in CollectionService:GetTagged("CoreCrate") do
		if not m:IsA("Model") then
			continue
		end
		local life = (m:GetAttribute("Lifetime") :: number?) or 30
		local left = ((m:GetAttribute("Expires") :: number?) or st) - st
		local k = math.clamp(left / life, 0, 1)
		local ring = m:FindFirstChild("Ring")
		if ring and ring:IsA("BasePart") then
			local d = 6.5 + 11.5 * k
			ring.Size = Vector3.new(0.15, d, d)
			ring.Color = Color3.fromRGB(80, 200, 255):Lerp(Color3.fromRGB(255, 72, 72), 1 - k)
		end
		local g = m:FindFirstChild("CrateGui")
		if g then
			local timer = g:FindFirstChild("Timer") :: TextLabel?
			if timer then
				timer.Text = string.format("%d", math.max(0, math.ceil(left)))
				timer.TextColor3 = if left < 8 and math.sin(t * 14) > 0 then Color3.fromRGB(255, 72, 72) else Color3.new(1, 1, 1)
			end
			local bar = g:FindFirstChild("Bar")
			local fill = bar and bar:FindFirstChild("Fill") :: Frame?
			if fill then
				local hp = ((m:GetAttribute("HP") :: number?) or 0) / math.max((m:GetAttribute("MaxHP") :: number?) or 1, 1)
				fill.Size = UDim2.fromScale(math.clamp(hp, 0, 1), 1)
			end
		end
		-- breakdown shudder (local, visual only): more violent as time runs out
		local root = m.PrimaryPart
		if root and root.Anchored and left < life * 0.5 and left > 0 then
			local base = (m:GetAttribute("_base") :: CFrame?)
			if not base then
				base = root.CFrame
				m:SetAttribute("_base", base)
			end
			local a = (1 - left / (life * 0.5)) * 0.12
			root.CFrame = (base :: CFrame) * CFrame.Angles(math.noise(t * 20, 1) * a, 0, math.noise(t * 20, 2) * a)
		end
	end
end

function World.start()
	track("CoreLoot", function(m)
		addLoot(m)
	end, removeLoot)
	track("CoreCargo", addCargo, function(m)
		local c = cargoGuis[m :: Model]
		if c then
			c.gui:Destroy()
			cargoGuis[m :: Model] = nil
		end
	end)
	RunService.RenderStepped:Connect(step)
	task.spawn(setupPrompts)
	-- blinking beacons
	task.spawn(function()
		local on = true
		while true do
			task.wait(0.6)
			on = not on
			for _, b in CollectionService:GetTagged("ScrapyardBlink") do
				if b:IsA("BasePart") then
					b.Transparency = if on then 0 else 0.85
					local l = b:FindFirstChildOfClass("PointLight")
					if l then
						l.Enabled = on
					end
				end
			end
		end
	end)
end

return World
