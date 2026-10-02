--!strict
-- Per-player core-loop state (server only; per session - the game has no
-- save system yet): battery, scrap, part locker, equipped parts, weapons,
-- carried cargo, battery upgrades. Derived stats are published as PLAYER
-- attributes so every client can read them:
--   Battery, BatteryMax, Scrap, Weapon, SpeedMul, JumpMul, DamageMul,
--   DrainMul, RegenMul, Luck, ScanRange, InBase, PlotIndex,
--   CarryKind ("Part"/"Cell"/nil), CarryName, CarryTier, CarryExpires (server time)
-- The locker / equipped / weapon lists go to the owner via the State remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Items = require(Shared:WaitForChild("CoreLoop"):WaitForChild("Items"))
local Remotes = require(script.Parent.Remotes)

local State = {}

local BAT = CoreLoopConfig.Battery
local BON = CoreLoopConfig.Bonus

export type Cargo = { item: Items.Item, model: Model?, expires: number }
export type PlayerState = {
	battery: number,
	scrap: number,
	locker: { Items.Item },
	equipped: { [string]: Items.Item },
	weapons: { [string]: boolean },
	weapon: string,
	cargo: Cargo?,
	cells: number,
	coils: number,
	shopLevel: number,
	sprinting: boolean,
	lastDrain: number,
	lastAttack: number,
	combo: number,
	inBase: boolean,
	toastAt: { [string]: number },
}

local states: { [Player]: PlayerState } = {}
local gearListeners: { (Player) -> () } = {}

function State.get(player: Player): PlayerState?
	return states[player]
end

function State.onGearChanged(fn: (Player) -> ())
	table.insert(gearListeners, fn)
end

local function fireGear(player: Player)
	for _, fn in gearListeners do
		task.spawn(fn, player)
	end
end

local function tierOf(st: PlayerState, slot: string): number
	local it = st.equipped[slot]
	return if it then it.tier or 0 else 0
end

function State.batteryMax(st: PlayerState): number
	return BAT.Max + st.shopLevel * BAT.ShopStep + st.cells * BAT.CellBonus + tierOf(st, "Chest") * BON.ChestBattery
end

-- Derived stats -> player attributes.
function State.recompute(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local legs, arms, chest, head = tierOf(st, "Legs"), tierOf(st, "Arms"), tierOf(st, "Chest"), tierOf(st, "Head")
	local max = State.batteryMax(st)
	st.battery = math.min(st.battery, max)
	player:SetAttribute("BatteryMax", max)
	player:SetAttribute("Battery", math.floor(st.battery * 10 + 0.5) / 10)
	player:SetAttribute("SpeedMul", 1 + BON.LegsSpeed * legs)
	player:SetAttribute("JumpMul", 1 + BON.LegsJump * legs)
	player:SetAttribute("DamageMul", 1 + BON.ArmsDamage * arms)
	player:SetAttribute("DrainMul", 1 - BON.ChestDrain * chest)
	player:SetAttribute("RegenMul", 1 + st.coils * BAT.CoilBonus)
	player:SetAttribute("Luck", 1 + BON.HeadLuck * head)
	player:SetAttribute("ScanRange", if head > 0 then BON.HeadScanBase + BON.HeadScanRange * head else 0)
	player:SetAttribute("Weapon", st.weapon)
	player:SetAttribute("ShopLevel", st.shopLevel)
	player:SetAttribute("Cells", st.cells)
	player:SetAttribute("Coils", st.coils)
end

function State.send(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local locker = {}
	for _, it in st.locker do
		table.insert(locker, Items.clean(it))
	end
	local equipped = {}
	for slot, it in st.equipped do
		equipped[slot] = Items.clean(it)
	end
	local weapons = {}
	for id in st.weapons do
		table.insert(weapons, id)
	end
	Remotes.get("State"):FireClient(player, {
		locker = locker,
		equipped = equipped,
		weapons = weapons,
		weapon = st.weapon,
		shopLevel = st.shopLevel,
		lockerSize = CoreLoopConfig.Loot.LockerSize,
	})
end

function State.changed(player: Player, gear: boolean?)
	State.recompute(player)
	State.send(player)
	if gear then
		fireGear(player)
	end
end

-- Throttled toast (one per `key` per `gap` seconds).
function State.toast(player: Player, key: string, text: string, color: Color3?, gap: number?)
	local st = states[player]
	if not st then
		return
	end
	local now = os.clock()
	if now - (st.toastAt[key] or -99) < (gap or 1.5) then
		return
	end
	st.toastAt[key] = now
	Remotes.toast(player, text, color)
end

------------------------------------------------------------------ scrap / battery

function State.addScrap(player: Player, n: number, at: Vector3?)
	local st = states[player]
	if not st or n == 0 then
		return
	end
	st.scrap = math.max(0, st.scrap + n)
	player:SetAttribute("Scrap", st.scrap)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Scrap")
	if v and v:IsA("IntValue") then
		v.Value = st.scrap
	end
	if n > 0 then
		Remotes.fx(player, "Scrap", { amount = n, pos = at })
	end
end

-- Spends battery; false (and nothing spent) if there isn't enough.
function State.spend(player: Player, amount: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	local cost = amount * ((player:GetAttribute("DrainMul") :: number?) or 1)
	if st.battery < cost - 1e-6 or st.battery <= 0 then
		return false
	end
	st.battery = math.max(0, st.battery - cost)
	st.lastDrain = os.clock()
	player:SetAttribute("Battery", math.floor(st.battery * 10 + 0.5) / 10)
	return true
end

function State.refill(player: Player)
	local st = states[player]
	if st then
		st.battery = State.batteryMax(st)
		player:SetAttribute("Battery", st.battery)
	end
end

------------------------------------------------------------------ cargo attrs

function State.setCargo(player: Player, cargo: Cargo?)
	local st = states[player]
	if not st then
		return
	end
	st.cargo = cargo
	if cargo then
		player:SetAttribute("CarryKind", cargo.item.kind)
		player:SetAttribute("CarryName", Items.name(cargo.item))
		player:SetAttribute("CarryTier", cargo.item.tier or 0)
		player:SetAttribute("CarryExpires", cargo.expires)
	else
		player:SetAttribute("CarryKind", nil)
		player:SetAttribute("CarryName", nil)
		player:SetAttribute("CarryTier", nil)
		player:SetAttribute("CarryExpires", nil)
	end
end

------------------------------------------------------------------ locker / equip

local function findLocker(st: PlayerState, uid: string): (number?, Items.Item?)
	for i, it in st.locker do
		if it.uid == uid then
			return i, it
		end
	end
	return nil, nil
end

local SNAP = Color3.fromRGB(90, 255, 140)
local BAD = Color3.fromRGB(255, 90, 70)

function State.equip(player: Player, uid: string): boolean
	local st = states[player]
	if not st then
		return false
	end
	local i, it = findLocker(st, uid)
	if not (i and it and it.kind == "Part" and it.slot) then
		return false
	end
	local slot = it.slot :: string
	if slot == "Chest" and not st.equipped.Legs then
		State.toast(player, "chestRule", "CHEST needs LEGS first!", BAD, 0.4)
		Remotes.fx(player, "Denied", { slot = "Chest" })
		return false
	end
	table.remove(st.locker, i)
	local old = st.equipped[slot]
	if old then
		table.insert(st.locker, old)
	end
	st.equipped[slot] = it
	State.changed(player, true)
	Remotes.fxAll("Snap", { player = player, slot = slot, tier = it.tier })
	Remotes.toast(player, "EQUIPPED  " .. string.upper(Items.name(it)), Items.color(it))
	return true
end

function State.unequip(player: Player, slot: string)
	local st = states[player]
	if not st or not st.equipped[slot] then
		return
	end
	table.insert(st.locker, st.equipped[slot])
	st.equipped[slot] = nil
	if slot == "Legs" and st.equipped.Chest then
		table.insert(st.locker, st.equipped.Chest)
		st.equipped.Chest = nil
		State.toast(player, "chestOff", "The CHEST came off too (it needs legs)", BAD, 0.2)
	end
	State.changed(player, true)
end

function State.recycle(player: Player, uid: string)
	local st = states[player]
	if not st then
		return
	end
	local i, it = findLocker(st, uid)
	if not (i and it) then
		return
	end
	table.remove(st.locker, i)
	local n = (it.tier or 1) * CoreLoopConfig.RecycleScrapPerTier
	State.addScrap(player, n)
	Remotes.toast(player, string.format("Recycled for %d scrap", n), Color3.fromRGB(236, 205, 40))
	State.changed(player)
end

-- A delivered part: auto-equips into an empty slot (chest only with legs),
-- otherwise into the locker (a full locker recycles its worst part).
function State.deliverPart(player: Player, it: Items.Item)
	local st = states[player]
	if not st or not it.slot then
		return
	end
	local slot = it.slot :: string
	if not st.equipped[slot] and (slot ~= "Chest" or st.equipped.Legs) then
		table.insert(st.locker, it)
		State.equip(player, it.uid)
		return
	end
	if #st.locker >= CoreLoopConfig.Loot.LockerSize then
		local worst, wi = nil :: Items.Item?, 0
		for i, x in st.locker do
			if not worst or (x.tier or 0) < (worst.tier or 0) then
				worst, wi = x, i
			end
		end
		if worst then
			table.remove(st.locker, wi)
			State.addScrap(player, (worst.tier or 1) * CoreLoopConfig.RecycleScrapPerTier)
			Remotes.toast(player, "Locker full: recycled " .. Items.name(worst), BAD)
		end
	end
	table.insert(st.locker, it)
	if slot == "Chest" and not st.equipped.Legs and not st.equipped.Chest then
		Remotes.toast(player, "CHEST stored - equip LEGS first!", BAD)
	else
		Remotes.toast(player, "STORED  " .. string.upper(Items.name(it)) .. "  (equip at your base)", Items.color(it))
	end
	State.changed(player)
end

function State.installCell(player: Player, which: string)
	local st = states[player]
	if not st then
		return
	end
	if which == "Coil" then
		st.coils += 1
		Remotes.toast(player, string.format("CHARGE COIL installed: +%d%% recharge", math.round(BAT.CoilBonus * 100)), Color3.fromRGB(80, 200, 255))
	else
		st.cells += 1
		Remotes.toast(player, string.format("POWER CELL installed: +%d max battery", BAT.CellBonus), Color3.fromRGB(90, 255, 140))
	end
	State.changed(player)
	State.refill(player)
end

function State.giveWeapon(player: Player, id: string): boolean
	local st = states[player]
	if not st or not CoreLoopConfig.Weapons[id] then
		return false
	end
	local fresh = not st.weapons[id]
	st.weapons[id] = true
	st.weapon = id
	State.changed(player, true)
	return fresh
end

function State.setWeapon(player: Player, id: string)
	local st = states[player]
	if st and st.weapons[id] and st.weapon ~= id then
		st.weapon = id
		State.changed(player, true)
	end
end

function State.buyBattery(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local cost = BAT.ShopCosts[st.shopLevel + 1]
	if not cost then
		State.toast(player, "shop", "Battery shop maxed out!", BAD)
		return
	end
	if st.scrap < cost then
		State.toast(player, "shop", string.format("Need %d scrap (you have %d)", cost, st.scrap), BAD, 0.5)
		return
	end
	State.addScrap(player, -cost)
	st.shopLevel += 1
	State.changed(player)
	State.refill(player)
	Remotes.toast(player, string.format("BATTERY UPGRADED: %d max", State.batteryMax(st)), Color3.fromRGB(90, 255, 140))
	Remotes.fx(player, "Install", {})
end

------------------------------------------------------------------ tick

local function tick(dt: number)
	local now = os.clock()
	for player, st in states do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (root and hum and hum.Health > 0) then
			continue
		end
		local max = State.batteryMax(st)
		local drainMul = (player:GetAttribute("DrainMul") :: number?) or 1
		local regenMul = (player:GetAttribute("RegenMul") :: number?) or 1
		local v = root.AssemblyLinearVelocity
		local moving = Vector3.new(v.X, 0, v.Z).Magnitude > 3
		local drain = 0
		if st.sprinting and moving and st.battery > 0 and not hum.SeatPart then
			drain += BAT.SprintDrain
		end
		if st.cargo then
			drain += BAT.CarryDrain
		end
		local b = st.battery
		if st.inBase then
			b += BAT.BaseCharge * regenMul * dt
		elseif drain > 0 then
			b -= drain * drainMul * dt
			st.lastDrain = now
		elseif now - st.lastDrain > BAT.IdleDelay and now - st.lastAttack > BAT.IdleDelay then
			b += BAT.IdleRegen * regenMul * dt
		end
		b = math.clamp(b, 0, max)
		if math.abs(b - st.battery) > 1e-4 then
			local before = st.battery
			st.battery = b
			if math.abs(math.floor(b * 10 + 0.5) - math.floor(before * 10 + 0.5)) >= 1 then
				player:SetAttribute("Battery", math.floor(b * 10 + 0.5) / 10)
			end
		end
	end
end

------------------------------------------------------------------ lifecycle

local function add(player: Player)
	local st: PlayerState = {
		battery = BAT.Max,
		scrap = 0,
		locker = {},
		equipped = {},
		weapons = { Fists = true },
		weapon = "Fists",
		cargo = nil,
		cells = 0,
		coils = 0,
		shopLevel = 0,
		sprinting = false,
		lastDrain = 0,
		lastAttack = 0,
		combo = 0,
		inBase = false,
		toastAt = {},
	}
	states[player] = st
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local scrap = Instance.new("IntValue")
	scrap.Name = "Scrap"
	scrap.Parent = ls
	player:SetAttribute("Scrap", 0)
	State.recompute(player)
	player:SetAttribute("Battery", st.battery)
	task.defer(State.send, player)
end

function State.start()
	Players.PlayerAdded:Connect(add)
	for _, p in Players:GetPlayers() do
		if not states[p] then
			add(p)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
	end)
	Remotes.get("Sprint").OnServerEvent:Connect(function(player, on)
		local st = states[player]
		if st then
			st.sprinting = on == true
		end
	end)
	Remotes.get("Locker").OnServerEvent:Connect(function(player, action, arg)
		local st = states[player]
		if not st or typeof(action) ~= "string" then
			return
		end
		if action == "Equip" or action == "Unequip" or action == "Recycle" or action == "BuyBattery" then
			-- locker actions only at your base (the weapon swap works anywhere)
			if not st.inBase then
				State.toast(player, "base", "Go to your BASE to change parts", BAD)
				return
			end
		end
		if action == "Equip" and typeof(arg) == "string" then
			State.equip(player, arg)
		elseif action == "Unequip" and typeof(arg) == "string" then
			State.unequip(player, arg)
		elseif action == "Recycle" and typeof(arg) == "string" then
			State.recycle(player, arg)
		elseif action == "Weapon" and typeof(arg) == "string" then
			State.setWeapon(player, arg)
		elseif action == "BuyBattery" then
			State.buyBattery(player)
		elseif action == "Refresh" then
			State.send(player)
		end
	end)
	RunService.Heartbeat:Connect(tick)
end

return State
