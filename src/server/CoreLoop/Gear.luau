--!strict
-- Equipped ARMOUR + the held weapon, built on the server inside the
-- character (Model "CoreGear") so everyone sees them; welded, massless,
-- non-colliding (ArmorBuilder). Each armour slot REPLACES the limbs it
-- covers: those body parts (plus the face, the accessories on them and the
-- EXO-1 pieces on them) are hidden here, on the server, and restored on
-- unequip / death. Rebuilt on respawn, on every equip change, when the
-- avatar's body parts / accessories / the exo are swapped, and when a gear
-- mesh asset finishes loading (GearMeshes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreShared = Shared:WaitForChild("CoreLoop")
local ArmorBuilder = require(CoreShared:WaitForChild("ArmorBuilder"))
local GearMeshes = require(CoreShared:WaitForChild("GearMeshes"))
local State = require(script.Parent.State)

local Gear = {}

local pending: { [Player]: boolean } = {}

local HIP_ATTR = "GearBaseHip" -- HipHeight before the boots raised it

local function clear(char: Model)
	local old = char:FindFirstChild("CoreGear")
	if old then
		old:Destroy()
	end
	ArmorBuilder.restore(char)
	local base = char:GetAttribute(HIP_ATTR)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if typeof(base) == "number" and hum then
		hum.HipHeight = base
	end
	char:SetAttribute(HIP_ATTR, nil)
end

function Gear.rebuild(player: Player)
	local char = player.Character
	local st = State.get(player)
	if not (char and st and char.Parent) then
		return
	end
	clear(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "CoreGear"
	local covered: { BasePart } = {}
	for _, slot in { "Legs", "Arms", "Chest" } do
		local it = st.equipped[slot]
		if it then
			local ok, res, hide = pcall(ArmorBuilder.attach, char, it, model)
			if ok then
				for _, p in hide do
					table.insert(covered, p)
				end
			else
				warn("[CoreLoop] gear build failed", slot, res)
			end
		end
	end
	if st.weapon ~= "Fists" then
		local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if hand and hand:IsA("BasePart") then
			local ok, w, c0 = pcall(ArmorBuilder.weapon, st.weapon, hand)
			if ok then
				local handle = w.PrimaryPart :: BasePart
				for _, d in w:GetDescendants() do
					if d:IsA("BasePart") then
						d.Massless = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.Anchored = false
					end
				end
				handle.CFrame = hand.CFrame * c0
				local weld = Instance.new("Weld")
				weld.Name = "Grip"
				weld.Part0 = hand
				weld.Part1 = handle
				weld.C0 = c0
				weld.Parent = handle
				-- re-place the welded pieces relative to the moved handle
				for _, d in w:GetDescendants() do
					if d:IsA("Weld") and d ~= weld and d.Part0 == handle and d.Part1 then
						d.Part1.CFrame = handle.CFrame * d.C0
					end
				end
				w.Name = "Weapon"
				w:SetAttribute("Id", st.weapon)
				w.Parent = model
			else
				warn("[CoreLoop] weapon build failed", st.weapon, w)
			end
		end
	end
	model.Parent = char
	ArmorBuilder.hide(char, covered)
	-- boots taller than the avatar's feet: stand on them, not in the floor
	local legs = model:FindFirstChild("Gear_Legs")
	local raise = legs and legs:GetAttribute("HipRaise")
	if typeof(raise) == "number" and raise > 0 then
		char:SetAttribute(HIP_ATTR, hum.HipHeight)
		hum.HipHeight += raise
	end
end

local function schedule(player: Player, delay: number?)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(delay or 0.25, function()
		pending[player] = nil
		if player.Parent then
			Gear.rebuild(player)
		end
	end)
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	if not player:HasAppearanceLoaded() then
		local t0 = os.clock()
		while not player:HasAppearanceLoaded() and os.clock() - t0 < 6 and player.Character == char do
			task.wait(0.1)
		end
	end
	task.wait(0.3)
	if player.Character ~= char then
		return
	end
	char.ChildAdded:Connect(function(c)
		-- swapped body parts, a new hat / hair, a rebuilt EXO-1
		if c:IsA("BasePart") or c:IsA("Accessory") or c.Name == "Exoskeleton" then
			schedule(player, 0.4)
		end
	end)
	hum.Died:Connect(function()
		-- the corpse gets its own limbs back (the armour comes off)
		clear(char)
	end)
	Gear.rebuild(player)
end

function Gear.start()
	State.onGearChanged(function(player)
		schedule(player, 0)
	end)
	-- a gear mesh finished loading: rebuild everyone (placeholder -> mesh)
	GearMeshes.onLoaded(function()
		for _, p in Players:GetPlayers() do
			schedule(p, 0.1)
		end
	end)
	GearMeshes.preloadAll()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

return Gear
