--!strict
-- GEAR PICKER (owner / Studio test tool): the client panel (client
-- CoreLoop/GearPicker) fires GearPick to put ANY armour piece or weapon on
-- at once, bypassing loot, the locker and "chest needs legs":
--   GearPick("Piece", slot, tier)   equip a Legs / Arms / Chest piece of tier 1..20
--   GearPick("Weapon", id)          hold a weapon (M01..M10, R01..R10, Fists)
--   GearPick("Set", tier)           all three armour pieces of a tier
--   GearPick("UnequipAll")          armour off, back to fists
-- Allowed in Studio, for the place's creator (or the owning group's owner)
-- and Picker.ExtraUsers. The player attribute "GearPicker" tells the client
-- to show the panel; the server re-checks on every request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Items = require(Shared:WaitForChild("CoreLoop"):WaitForChild("Items"))
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Picker = {}

Picker.ExtraUsers = { [1520431437] = true }

local allowed: { [Player]: boolean } = {}

local function check(player: Player): boolean
	if RunService:IsStudio() or Picker.ExtraUsers[player.UserId] then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	return ok and rank == 255
end

local function equipPiece(st: State.PlayerState, slot: string, tier: number)
	local old = st.equipped[slot]
	if old and #st.locker < CoreLoopConfig.Loot.LockerSize then
		table.insert(st.locker, old)
	end
	st.equipped[slot] = Items.part(slot, tier)
end

function Picker.start()
	local remote = Remotes.get("GearPick")
	remote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
		if not allowed[player] then
			return
		end
		local st = State.get(player)
		if not st or typeof(action) ~= "string" then
			return
		end
		local tier = if typeof(b) == "number" then math.clamp(math.floor(b), 1, CoreLoopConfig.MaxTier)
			elseif typeof(a) == "number" then math.clamp(math.floor(a), 1, CoreLoopConfig.MaxTier)
			else 1
		if action == "Piece" and typeof(a) == "string" and table.find(CoreLoopConfig.Slots, a) then
			equipPiece(st, a, tier)
		elseif action == "Set" then
			for _, slot in CoreLoopConfig.Slots do
				equipPiece(st, slot, tier)
			end
		elseif action == "Weapon" and typeof(a) == "string" and CoreLoopConfig.Weapons[a] then
			st.weapons[a] = true
			st.weapon = a
		elseif action == "UnequipAll" then
			for _, slot in CoreLoopConfig.Slots do
				st.equipped[slot] = nil
			end
			st.weapon = "Fists"
		else
			return
		end
		State.changed(player, true)
	end)
	local function add(player: Player)
		task.spawn(function()
			allowed[player] = check(player)
			player:SetAttribute("GearPicker", allowed[player])
		end)
	end
	Players.PlayerAdded:Connect(add)
	for _, p in Players:GetPlayers() do
		add(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		allowed[p] = nil
	end)
end

return Picker
