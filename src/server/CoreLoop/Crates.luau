--!strict
-- TIMED SUPPLY CRATES: every Interval seconds a crate slams down at a free
-- Scrapyard.CrateSpawns marker with a breakdown timer (Lifetime, ~30 s) and
-- lots of HP (more with more players). Anyone can hit it. Break it in time:
-- better loot pops out (a high-tier part / a weapon / a battery cell, from
-- CoreLoopConfig.Crates) and every contributor gets scrap. Too slow: it
-- collapses and the loot is lost. Clients read the "Expires" / "HP" / "MaxHP"
-- attributes for the ring, timer and HUD alert (tag "CoreCrate").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Items = require(Shared:WaitForChild("CoreLoop"):WaitForChild("Items"))
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Targets = require(script.Parent.Targets)
local Loot = require(script.Parent.Loot)

local Crates = {}

local CR = CoreLoopConfig.Crates
local rng = Random.new()
local folder: Folder
local spawns: { Vector3 } = {}
local active: { [Model]: number } = {} -- model -> spawn index

local function piece(model: Model, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	p.Name = name or "Plate"
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.Metal
	p.Anchored = false
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function build(ground: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "SupplyCrate"
	local base = CFrame.new(ground) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(6, 5, 6)
	root.CFrame = base * CFrame.new(0, 2.5, 0)
	root.Color = Color3.fromRGB(62, 65, 70)
	root.Material = Enum.Material.DiamondPlate
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root
	local function weld(p: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	end
	local yellow = Color3.fromRGB(236, 205, 40)
	local dark = Color3.fromRGB(34, 35, 38)
	-- frame edges + bands + a glowing lock
	for _, x in { -3, 3 } do
		for _, z in { -3, 3 } do
			weld(piece(model, Vector3.new(0.7, 5.3, 0.7), root.CFrame * CFrame.new(x, 0, z), dark, Enum.Material.Metal, "Edge"))
		end
	end
	for _, y in { -1.4, 1.4 } do
		weld(piece(model, Vector3.new(6.3, 0.5, 6.3), root.CFrame * CFrame.new(0, y, 0), yellow, Enum.Material.Metal, "Band"))
	end
	weld(piece(model, Vector3.new(6.4, 0.5, 6.4), root.CFrame * CFrame.new(0, 2.6, 0), dark, Enum.Material.Metal, "Lid"))
	local lock = piece(model, Vector3.new(1.4, 1.4, 0.4), root.CFrame * CFrame.new(0, 0, -3.15), Color3.fromRGB(80, 200, 255), Enum.Material.Neon, "Lock")
	lock.CanCollide = false
	weld(lock)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(80, 200, 255)
	light.Range = 16
	light.Brightness = 2
	light.Parent = lock
	-- the breakdown ring on the ground (clients shrink it with the timer)
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 18, 18)
	ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = Color3.fromRGB(80, 200, 255)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.6
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = model
	-- billboard: timer + HP (text / fill driven by clients from the attributes)
	local g = Instance.new("BillboardGui")
	g.Name = "CrateGui"
	g.Size = UDim2.fromOffset(170, 58)
	g.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 400
	g.Adornee = root
	local t = Instance.new("TextLabel")
	t.Name = "Timer"
	t.Size = UDim2.new(1, 0, 0, 30)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = string.format("%d", CR.Lifetime)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = g
	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.Position = UDim2.fromOffset(10, 36)
	bg.Size = UDim2.new(1, -20, 0, 14)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	for _, f in { bg, fill } do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 5)
		c.Parent = f
	end
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Parent = bg
	g.Parent = model
	return model, root
end

local function crateHP(): number
	return CR.HP + math.max(0, #Players:GetPlayers() - 1) * CR.HPPerExtraPlayer
end

local function rollLoot(): Items.Item
	local W = CR.LootWeights
	local r = rng:NextNumber() * (W.Part + W.Weapon + W.Battery)
	if r < W.Part then
		return Items.part(Loot.randomSlot(), Loot.rollTier(CR.TierWeights))
	elseif r < W.Part + W.Weapon then
		return Items.weapon(Loot.randomWeapon())
	end
	return Items.cell(if rng:NextNumber() < 0.6 then "Power" else "Coil")
end

local function spawnCrate()
	if #spawns == 0 then
		return
	end
	local n = 0
	for _ in active do
		n += 1
	end
	if n >= CR.MaxActive then
		return
	end
	local index: number? = nil
	for _ = 1, 20 do
		local i = rng:NextInteger(1, #spawns)
		local taken = false
		for _, j in active do
			if j == i then
				taken = true
			end
		end
		if not taken then
			index = i
			break
		end
	end
	if not index then
		return
	end
	local ground = spawns[index]
	local model, root = build(ground)
	local expires = workspace:GetServerTimeNow() + CR.Lifetime + 0.8
	model:SetAttribute("Expires", expires)
	model:SetAttribute("Lifetime", CR.Lifetime)
	local final = root.CFrame
	root.CFrame = final + Vector3.new(0, 70, 0)
	model.Parent = folder
	active[model] = index
	local done = false
	local hp = crateHP()
	Targets.register(model, root, {
		hp = hp,
		kind = "Crate",
		radius = 3.6,
		onBreak = function(m: Model, killer: Player?, by: { [Player]: number })
			done = true
			active[m] = nil
			local pos = root.Position
			Remotes.fxAll("CrateOpen", { pos = pos })
			m:Destroy()
			for player, dmg in by do
				if player.Parent and dmg > 0 then
					local share = math.clamp(dmg / hp, 0.2, 1)
					State.addScrap(player, math.floor(rng:NextInteger(CR.Scrap[1], CR.Scrap[2]) * share + 0.5), pos)
				end
			end
			local item = rollLoot()
			Loot.drop(item, ground)
			Remotes.toastAll(
				string.format("CRATE CRACKED by %s: %s!", if killer then killer.DisplayName else "someone", string.upper(Items.name(item))),
				Items.color(item),
				"crate"
			)
		end,
	})
	CollectionService:AddTag(model, "CoreCrate")
	-- the drop: falls in, slams (clients shake + dust)
	local tw = TweenService:Create(root, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = final })
	tw:Play()
	task.delay(0.7, function()
		if model.Parent then
			Remotes.fxAll("CrateDrop", { pos = ground, crate = model })
		end
	end)
	Remotes.toastAll("SUPPLY CRATE INCOMING! Break it in " .. CR.Lifetime .. "s", Color3.fromRGB(80, 200, 255), "crate")
	-- breakdown timer
	task.delay(expires - workspace:GetServerTimeNow(), function()
		if done or not model.Parent then
			return
		end
		done = true
		active[model] = nil
		Targets.unregister(model)
		Remotes.fxAll("CrateFail", { pos = root.Position })
		Remotes.toastAll("Crate collapsed - the loot is LOST", Color3.fromRGB(255, 90, 70), "crate")
		model:Destroy()
	end)
end

function Crates.spawnNow()
	spawnCrate()
end

function Crates.start(yard: Folder)
	folder = Instance.new("Folder")
	folder.Name = "CoreCrates"
	folder.Parent = workspace
	local markers = yard:FindFirstChild("CrateSpawns")
	if markers then
		for _, m in markers:GetChildren() do
			if m:IsA("BasePart") then
				table.insert(spawns, m.Position)
			end
		end
	end
	task.spawn(function()
		task.wait(CR.FirstDelay * CoreLoopConfig.CrateIntervalMultiplier)
		while true do
			if #Players:GetPlayers() > 0 then
				spawnCrate()
			end
			task.wait(rng:NextNumber(CR.Interval[1], CR.Interval[2]) * CoreLoopConfig.CrateIntervalMultiplier)
		end
	end)
end

return Crates
