--!strict
-- Dropped loot (Workspace.CoreLoot): mech PARTS and battery CELLS are cargo
-- (touch to pick up -> carried on your back, slower + battery drain, the
-- EXPIRY timer keeps running from the moment it dropped; bring it onto your
-- base pad before it runs out, or it falls apart). WEAPONS are grabbed
-- straight into your hands (no timer while held; on the ground they vanish
-- after Loot.WeaponLifetime).
--
-- Every loot model: Handle (anchored on the ground; clients bob / spin it
-- locally), tag "CoreLoot", attributes Kind / Name / Tier / Expires (server
-- time) / Color; a tall light beam in the item's colour. Carried cargo keeps
-- the "CoreLoot" tag off and gets "CoreCargo" instead.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local CoreShared = Shared:WaitForChild("CoreLoop")
local Items = require(CoreShared:WaitForChild("Items"))
local PartBuilder = require(CoreShared:WaitForChild("PartBuilder"))
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Loot = {}

local L = CoreLoopConfig.Loot
local BAD = Color3.fromRGB(255, 90, 70)

type Drop = { item: Items.Item, model: Model, expires: number }
local drops: { [Model]: Drop } = {}
local folder: Folder

local function now(): number
	return workspace:GetServerTimeNow()
end

local function buildModel(item: Items.Item): Model
	if item.kind == "Part" then
		local m = PartBuilder.display(item)
		m:ScaleTo(1.25)
		return m
	elseif item.kind == "Cell" then
		return PartBuilder.cell(item.cell or "Power")
	else
		local m = PartBuilder.weapon(item.weapon or "Blade")
		m:ScaleTo(1.4)
		return m
	end
end

local function beam(model: Model, handle: BasePart, color: Color3)
	local b = Instance.new("Part")
	b.Name = "Beam"
	b.Shape = Enum.PartType.Cylinder
	b.Size = Vector3.new(26, 0.6, 0.6)
	b.Color = color
	b.Material = Enum.Material.Neon
	b.Transparency = 0.55
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.CastShadow = false
	b.Massless = true
	b.Anchored = true
	b.CFrame = CFrame.new(handle.Position + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	b.Parent = model
end

-- Drops an item at `pos` (on the ground). `expires` = server time it falls
-- apart (default now + PartExpiry for cargo, WeaponLifetime for weapons).
function Loot.drop(item: Items.Item, pos: Vector3, expires: number?): Model
	local model = buildModel(item)
	model.Name = "Loot_" .. item.kind
	local handle = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = false
		end
	end
	handle.Anchored = true
	local _, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(pos + Vector3.new(0, math.max(size.Y / 2, 1) + 0.8, 0)) * CFrame.Angles(0, math.random() * 6.28, 0))
	local exp = expires or (now() + (if item.kind == "Weapon" then L.WeaponLifetime else L.PartExpiry))
	local color = Items.color(item)
	model:SetAttribute("Kind", item.kind)
	model:SetAttribute("Name", Items.name(item))
	model:SetAttribute("Bonus", Items.bonusText(item))
	model:SetAttribute("Tier", item.tier or 0)
	model:SetAttribute("Slot", item.slot)
	model:SetAttribute("Expires", exp)
	model:SetAttribute("Color", color)
	beam(model, handle, color)
	model.Parent = folder
	CollectionService:AddTag(model, "CoreLoot")
	drops[model] = { item = item, model = model, expires = exp }
	Remotes.fxAll("Drop", { pos = handle.Position, color = color, tier = item.tier or 0, kind = item.kind })
	return model
end

local function breakApart(model: Model, pos: Vector3, color: Color3)
	Remotes.fxAll("Expire", { pos = pos, color = color })
	model:Destroy()
end

------------------------------------------------------------------ cargo

local function carry(player: Player, d: Drop)
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	drops[d.model] = nil
	CollectionService:RemoveTag(d.model, "CoreLoot")
	local model = d.model
	local b = model:FindFirstChild("Beam")
	if b then
		b:Destroy()
	end
	local handle = model.PrimaryPart :: BasePart
	model:ScaleTo(model:GetScale() * 0.75)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Massless = true
			p.Anchored = false
		end
	end
	-- on the back, above the exo spine / chest pack, tilted
	local off = CFrame.new(0, torso.Size.Y * 0.5 + 0.6, torso.Size.Z / 2 + 1.5) * CFrame.Angles(math.rad(-20), math.rad(15), 0)
	handle.CFrame = torso.CFrame * off
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = off
	weld.Parent = handle
	model.Name = "Cargo"
	model.Parent = char
	CollectionService:AddTag(model, "CoreCargo")
	State.setCargo(player, { item = d.item, model = model, expires = d.expires })
	Remotes.fxAll("Pickup", { player = player, pos = handle.Position, color = Items.color(d.item), kind = d.item.kind })
	Remotes.toast(player, "GOT " .. string.upper(Items.name(d.item)) .. " - get it HOME!", Items.color(d.item), "carry")
end

-- Cargo lost (expired / died): it breaks apart where it is.
function Loot.loseCargo(player: Player, why: string)
	local st = State.get(player)
	local cargo = st and st.cargo
	if not cargo then
		return
	end
	State.setCargo(player, nil)
	local pos = if cargo.model and cargo.model.PrimaryPart then cargo.model.PrimaryPart.Position else Vector3.zero
	if cargo.model then
		breakApart(cargo.model, pos, Items.color(cargo.item))
	end
	Remotes.toast(player, why, BAD, "lost")
end

-- On your base pad: the cargo goes into the locker / equips / installs.
function Loot.deliver(player: Player, dropAt: Vector3)
	local st = State.get(player)
	local cargo = st and st.cargo
	if not cargo then
		return
	end
	State.setCargo(player, nil)
	local from = if cargo.model and cargo.model.PrimaryPart then cargo.model.PrimaryPart.Position else dropAt
	if cargo.model then
		cargo.model:Destroy()
	end
	Remotes.fxAll("Deliver", { player = player, from = from, to = dropAt, color = Items.color(cargo.item), kind = cargo.item.kind })
	if cargo.item.kind == "Cell" then
		State.installCell(player, cargo.item.cell or "Power")
	else
		State.deliverPart(player, cargo.item)
	end
end

------------------------------------------------------------------ pickup / expiry

local function tryPickup(player: Player, d: Drop)
	local st = State.get(player)
	if not st then
		return
	end
	if d.item.kind == "Weapon" then
		local id = d.item.weapon or "Blade"
		drops[d.model] = nil
		local pos = (d.model.PrimaryPart :: BasePart).Position
		d.model:Destroy()
		local fresh = State.giveWeapon(player, id)
		if not fresh then
			State.addScrap(player, 15, pos)
		end
		local w = CoreLoopConfig.Weapons[id]
		Remotes.fxAll("Pickup", { player = player, pos = pos, color = w.color, kind = "Weapon" })
		Remotes.toast(player, (if fresh then "NEW WEAPON: " else "EQUIPPED: ") .. string.upper(w.name) .. "  " .. w.blurb, w.color, "weapon")
		return
	end
	if st.cargo then
		State.toast(player, "full", "Hands full! Take your cargo home first", BAD, 2.5)
		return
	end
	carry(player, d)
end

local acc = 0
local function step(dt: number)
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	local t = now()
	-- ground drops: expiry + touch pickups
	for model, d in drops do
		if not model.Parent then
			drops[model] = nil
			continue
		end
		local handle = model.PrimaryPart
		if not handle then
			continue
		end
		if t >= d.expires then
			drops[model] = nil
			breakApart(model, handle.Position, Items.color(d.item))
			continue
		end
		if t - (d.expires - (if d.item.kind == "Weapon" then L.WeaponLifetime else L.PartExpiry)) < 0.5 then
			continue -- a moment to land before anyone can grab it
		end
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 and not hum.SeatPart then
				local off = root.Position - handle.Position
				if Vector3.new(off.X, 0, off.Z).Magnitude < L.PickupRadius and math.abs(off.Y) < 7 then
					tryPickup(player, d)
					break
				end
			end
		end
	end
	-- carried cargo expiry
	for _, player in Players:GetPlayers() do
		local st = State.get(player)
		if st and st.cargo and t >= st.cargo.expires then
			Loot.loseCargo(player, "TOO SLOW! " .. Items.name(st.cargo.item) .. " fell apart")
		end
	end
end

function Loot.start()
	folder = workspace:FindFirstChild("CoreLoot") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CoreLoot"
		folder.Parent = workspace
	end
	RunService.Heartbeat:Connect(step)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Connect(function()
					Loot.loseCargo(player, "You went down - your cargo broke apart")
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
		if p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Died:Connect(function()
					Loot.loseCargo(p, "You went down - your cargo broke apart")
				end)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		local st = State.get(p)
		if st and st.cargo and st.cargo.model then
			st.cargo.model:Destroy()
		end
	end)
end

-- Rolls a part tier from weights {T1..T5}.
function Loot.rollTier(weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = math.random() * total
	for i, w in weights do
		r -= w
		if r <= 0 and w > 0 then
			return i
		end
	end
	return 1
end

function Loot.randomSlot(): string
	return CoreLoopConfig.Slots[math.random(1, #CoreLoopConfig.Slots)]
end

function Loot.randomWeapon(): string
	local ids = { "Blade", "Hammer", "Rivet" }
	return ids[math.random(1, #ids)]
end

return Loot
