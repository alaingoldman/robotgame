--!strict
-- Core gameplay loop (server). See CoreLoopConfig for the design numbers.
--   Scrapyard  the map (saved in the place; rebuilt only if missing)
--   State      per-player battery / scrap / locker / equipped / weapons / cargo
--   Gear       equipped parts + weapon on the character
--   Targets    hittable registry (junk + crates)
--   Combat     server-authoritative attacks
--   Junk       destructible scrap piles + part drops
--   Crates     timed supply crates
--   Loot       dropped items, carrying, expiry, delivery
--   Bases      plots, prompts, charging, delivery, respawn at base
--
-- Test hooks (eval_server_runtime):
--   local CL = require(game.ServerScriptService.Server.CoreLoop)
--   CL.debug.dropPart(player, "Legs", 3)  -- at the player's feet
--   CL.debug.crate()                      -- spawn a supply crate now
--   CL.debug.give(player, "Hammer")       -- weapon
--   player:SetAttribute("CoreDropBoost", 20)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Items = require(Shared:WaitForChild("CoreLoop"):WaitForChild("Items"))

local Remotes = require(script.Remotes)
local Scrapyard = require(script.Scrapyard)
local State = require(script.State)
local Gear = require(script.Gear)
local Combat = require(script.Combat)
local Loot = require(script.Loot)
local Junk = require(script.Junk)
local Crates = require(script.Crates)
local Bases = require(script.Bases)

local CoreLoop = {}

local started = false

function CoreLoop.start()
	if started or not CoreLoopConfig.Enabled then
		return
	end
	started = true
	Remotes.init()
	Players.RespawnTime = CoreLoopConfig.RespawnTime
	local yard = Scrapyard.ensure()
	State.start()
	Gear.start()
	Combat.start()
	Loot.start()
	Bases.start(yard)
	Junk.start(yard)
	Crates.start(yard)
end

CoreLoop.debug = {
	dropPart = function(player: Player, slot: string?, tier: number?)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local pos = root.Position + root.CFrame.LookVector * 8 - Vector3.new(0, 3, 0)
			return Loot.drop(Items.part(slot or Loot.randomSlot(), tier or 1), pos)
		end
		return nil
	end,
	dropAt = function(item: any, pos: Vector3)
		return Loot.drop(item, pos)
	end,
	crate = function()
		Crates.spawnNow()
	end,
	give = function(player: Player, id: string)
		State.giveWeapon(player, id)
	end,
	state = function(player: Player)
		return State.get(player)
	end,
	items = Items,
	State = State,
	Loot = Loot,
}

return CoreLoop
