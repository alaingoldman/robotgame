--!strict
-- JUNK: destructible scrap piles (Small / Medium / Large, CoreLoopConfig.Junk)
-- kept topped up at random Scrapyard.JunkSpawns markers (Workspace.CoreJunk).
-- Built from a few anchored, colliding chunks round an invisible Root. On
-- destroy: the client debris burst (Fx "Break"), scrap for the killer, and a
-- roll for a dropped MECH PART (chance x the killer's Luck from a head part
-- x CoreLoopConfig.DropChanceMultiplier x the player attribute
-- "CoreDropBoost"), plus small weapon / battery-cell chances.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Items = require(Shared:WaitForChild("CoreLoop"):WaitForChild("Items"))
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Targets = require(script.Parent.Targets)
local Loot = require(script.Parent.Loot)

local Junk = {}

local J = CoreLoopConfig.Junk
local rng = Random.new()
local folder: Folder
local spawns: { Vector3 } = {}
local occupied: { [number]: Model } = {}
local active = 0

local PALETTE = {
	Color3.fromRGB(140, 78, 48),
	Color3.fromRGB(98, 56, 38),
	Color3.fromRGB(110, 114, 120),
	Color3.fromRGB(150, 60, 45),
	Color3.fromRGB(50, 90, 140),
	Color3.fromRGB(98, 106, 62),
	Color3.fromRGB(200, 120, 40),
	Color3.fromRGB(62, 65, 70),
}

local function chunk(model: Model, shape: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?)
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if shape == "Cyl" then
			q.Shape = Enum.PartType.Cylinder
		end
		p = q
	end
	p.Name = "Chunk"
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.CorrodedMetal
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
end

local function pick(): Color3
	return PALETTE[rng:NextInteger(1, #PALETTE)]
end

-- A scrap heap of ~size studs: a few big pieces + junk sticking out.
local function build(kind: CoreLoopConfig.JunkKind, ground: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Junk" .. kind.id
	local s = kind.size
	local base = CFrame.new(ground) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local style = rng:NextInteger(1, 3)
	if kind.id == "Small" then
		if style == 1 then
			-- dented barrel + a panel
			chunk(model, "Cyl", Vector3.new(2.6, 2, 2), base * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2 + 0.15), pick(), Enum.Material.Metal)
			chunk(model, "Block", Vector3.new(2.4, 0.3, 1.6), base * CFrame.new(0.9, 0.5, 0.6) * CFrame.Angles(0.4, 0.3, 0.2), pick())
		elseif style == 2 then
			-- crushed box of parts
			chunk(model, "Block", Vector3.new(2.4, 1.6, 2), base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, 0.08), pick())
			chunk(model, "Cyl", Vector3.new(2.2, 0.4, 0.4), base * CFrame.new(0.2, 1.8, 0) * CFrame.Angles(0.3, 0.5, 0.6), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
		else
			-- tyre + rim on a scrap plate
			chunk(model, "Cyl", Vector3.new(1.1, 2.6, 2.6), base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, 0), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber)
			chunk(model, "Block", Vector3.new(2.6, 0.4, 2.2), base * CFrame.new(0, 0.2, 0.4) * CFrame.Angles(0.1, 0.4, 0), pick())
		end
	elseif kind.id == "Medium" then
		-- engine block / appliance heap
		chunk(model, "Block", Vector3.new(3.4, 2.6, 2.8), base * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, 0.06), pick())
		chunk(model, "Block", Vector3.new(2.6, 1.4, 2.2), base * CFrame.new(0.3, 3.2, 0.2) * CFrame.Angles(0.15, 0.4, -0.12), pick())
		chunk(model, "Cyl", Vector3.new(3, 0.6, 0.6), base * CFrame.new(-1.4, 2.4, -0.6) * CFrame.Angles(0.2, 0.9, 0.5), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
		chunk(model, "Wedge", Vector3.new(1.4, 1.6, 2.4), base * CFrame.new(1.9, 0.8, 0.4) * CFrame.Angles(0, 1.6, 0), pick())
		if style ~= 2 then
			chunk(model, "Cyl", Vector3.new(0.9, 2.2, 2.2), base * CFrame.new(-1.6, 1.1, 1.2) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber)
		end
	else
		-- a crushed car / robot carcass
		local col = pick()
		chunk(model, "Block", Vector3.new(5, 2.4, 8.5), base * CFrame.new(0, 1.3, 0) * CFrame.Angles(0.04, 0, 0.1), col)
		chunk(model, "Block", Vector3.new(4.2, 1.6, 4), base * CFrame.new(0.2, 3.1, 0.6) * CFrame.Angles(0.08, 0.1, 0.18), col:Lerp(Color3.new(0, 0, 0), 0.25))
		for _, z in { -2.8, 2.8 } do
			chunk(model, "Cyl", Vector3.new(0.9, 2.2, 2.2), base * CFrame.new(2.5, 1.1, z), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber)
		end
		chunk(model, "Block", Vector3.new(3, 0.4, 2.6), base * CFrame.new(-1, 4.3, -2) * CFrame.Angles(0.5, 0.3, 0.4), pick())
		chunk(model, "Cyl", Vector3.new(4.5, 0.5, 0.5), base * CFrame.new(-1.5, 3.6, 2) * CFrame.Angles(0.6, 1.2, 0.3), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
		chunk(model, "Wedge", Vector3.new(4.6, 1.2, 2), base * CFrame.new(0, 2.9, -3.5) * CFrame.Angles(0, math.pi, 0), col)
	end
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.new(s * 0.7, s * 0.5, s * 0.7)
	root.CFrame = CFrame.new(ground + Vector3.new(0, s * 0.3, 0))
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

local function weightedKind(): CoreLoopConfig.JunkKind
	local total = 0
	for _, k in J.Kinds do
		total += k.weight
	end
	local r = rng:NextNumber() * total
	for _, k in J.Kinds do
		r -= k.weight
		if r <= 0 then
			return k
		end
	end
	return J.Kinds[1]
end

local function dropChance(base: number, player: Player?): number
	local luck = if player then (player:GetAttribute("Luck") :: number?) or 1 else 1
	local boost = if player then (player:GetAttribute("CoreDropBoost") :: number?) or 1 else 1
	return math.min(1, base * luck * boost * CoreLoopConfig.DropChanceMultiplier)
end

local spawnOne: () -> ()

local function onBreak(index: number, kind: CoreLoopConfig.JunkKind)
	return function(model: Model, killer: Player?, _by: { [Player]: number })
		local root = model.PrimaryPart
		local pos = if root then root.Position else Vector3.zero
		local ground = pos - Vector3.new(0, kind.size * 0.3, 0)
		local colors = {}
		for _, c in model:GetChildren() do
			if c:IsA("BasePart") and c.Name == "Chunk" then
				table.insert(colors, c.Color)
			end
		end
		Remotes.fxAll("Break", { pos = pos, size = kind.size, colors = colors, kind = kind.id })
		model:Destroy()
		occupied[index] = nil
		active -= 1
		if killer then
			State.addScrap(killer, rng:NextInteger(kind.scrap[1], kind.scrap[2]), pos)
		end
		-- drops
		if rng:NextNumber() < dropChance(kind.drop, killer) then
			local tier = Loot.rollTier(kind.tiers)
			Loot.drop(Items.part(Loot.randomSlot(), tier), ground)
		elseif rng:NextNumber() < dropChance(kind.weaponDrop, killer) then
			Loot.drop(Items.weapon(Loot.weaponForTier(Loot.rollTier(kind.tiers))), ground)
		elseif rng:NextNumber() < dropChance(kind.cellDrop, killer) then
			Loot.drop(Items.cell(if rng:NextNumber() < 0.6 then "Power" else "Coil"), ground)
		end
		task.delay(rng:NextNumber(J.RespawnDelay[1], J.RespawnDelay[2]), spawnOne)
	end
end

local function nearPlayer(p: Vector3, r: number): boolean
	for _, pl in Players:GetPlayers() do
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - p).Magnitude < r then
			return true
		end
	end
	return false
end

spawnOne = function()
	if active >= J.MaxActive or #spawns == 0 then
		return
	end
	-- a free spawn point, not right on top of a player
	local index: number? = nil
	for _ = 1, 20 do
		local i = rng:NextInteger(1, #spawns)
		if not occupied[i] and not nearPlayer(spawns[i], 6) then
			index = i
			break
		end
	end
	if not index then
		task.delay(2, spawnOne)
		return
	end
	local kind = weightedKind()
	local model, root = build(kind, spawns[index])
	occupied[index] = model
	active += 1
	model.Parent = folder
	Targets.register(model, root, { hp = kind.hp, kind = "Junk", radius = kind.size * 0.5, onBreak = onBreak(index, kind) })
	Remotes.fxAll("Spawn", { pos = spawns[index], size = kind.size })
end

function Junk.start(yard: Folder)
	folder = Instance.new("Folder")
	folder.Name = "CoreJunk"
	folder.Parent = workspace
	local markers = yard:FindFirstChild("JunkSpawns")
	if markers then
		for _, m in markers:GetChildren() do
			if m:IsA("BasePart") then
				table.insert(spawns, m.Position)
			end
		end
	end
	if #spawns == 0 then
		warn("[CoreLoop] no junk spawns in", yard:GetFullName())
		return
	end
	for _ = 1, J.MaxActive do
		spawnOne()
	end
end

function Junk.count(): number
	return active
end

return Junk
