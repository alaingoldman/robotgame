--!strict
-- Item records for the core loop (shared so the HUD / locker UI can name and
-- describe them). Items are plain tables sent over remotes:
--   Part:    { uid, kind = "Part", slot = "Legs"|"Arms"|"Chest"|"Head", tier = 1..5, variant = palette id }
--   Cell:    { uid, kind = "Cell", cell = "Power"|"Coil" }   (battery upgrade cargo)
--   Weapon:  { uid, kind = "Weapon", weapon = "Blade"|"Hammer"|"Rivet" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))

local Items = {}

export type Item = {
	uid: string,
	kind: string,
	slot: string?,
	tier: number?,
	variant: string?,
	cell: string?,
	weapon: string?,
}

local nextId = 0
function Items.uid(): string
	nextId += 1
	return string.format("i%d_%d", nextId, math.random(1000, 9999))
end

Items.Variants = { "Olive", "Desert", "Arctic", "Navy", "Crimson" }
-- BRZ-01 palettes (TitanConfig variant ids)
Items.TitanVariants = { "Desert", "Navy", "Olive" }

function Items.part(slot: string, tier: number, variant: string?): Item
	local t = math.clamp(tier, 1, 5)
	local pool = if t == 5 then Items.TitanVariants else Items.Variants
	return { uid = Items.uid(), kind = "Part", slot = slot, tier = t, variant = variant or pool[math.random(1, #pool)] }
end

function Items.cell(which: string): Item
	return { uid = Items.uid(), kind = "Cell", cell = which }
end

function Items.weapon(id: string): Item
	return { uid = Items.uid(), kind = "Weapon", weapon = id }
end

function Items.tierInfo(tier: number): CoreLoopConfig.Tier
	return CoreLoopConfig.Tiers[math.clamp(tier, 1, 5)]
end

-- "VK-01 Military Arms"
function Items.name(item: Item): string
	if item.kind == "Part" then
		local t = Items.tierInfo(item.tier or 1)
		return string.format("%s %s %s", CoreLoopConfig.FamilyNames[t.family] or t.family, t.name, item.slot or "?")
	elseif item.kind == "Cell" then
		return if item.cell == "Coil" then "Charge Coil" else "Power Cell"
	elseif item.kind == "Weapon" then
		local w = CoreLoopConfig.Weapons[item.weapon or "Fists"]
		return if w then w.name else "Weapon"
	end
	return "Item"
end

function Items.color(item: Item): Color3
	if item.kind == "Part" then
		return Items.tierInfo(item.tier or 1).color
	elseif item.kind == "Cell" then
		return Color3.fromRGB(90, 255, 140)
	elseif item.kind == "Weapon" then
		local w = CoreLoopConfig.Weapons[item.weapon or "Fists"]
		return if w then w.color else Color3.new(1, 1, 1)
	end
	return Color3.new(1, 1, 1)
end

-- Short bonus line ("+16% speed, +16% jump").
function Items.bonusText(item: Item): string
	local B = CoreLoopConfig.Bonus
	if item.kind == "Part" then
		local t = item.tier or 1
		if item.slot == "Legs" then
			return string.format("+%d%% speed  +%d%% jump", math.round(B.LegsSpeed * t * 100), math.round(B.LegsJump * t * 100))
		elseif item.slot == "Arms" then
			return string.format("+%d%% damage", math.round(B.ArmsDamage * t * 100))
		elseif item.slot == "Chest" then
			return string.format("+%d battery  -%d%% drain", B.ChestBattery * t, math.round(B.ChestDrain * t * 100))
		elseif item.slot == "Head" then
			return string.format("+%d%% loot  scanner %dm", math.round(B.HeadLuck * t * 100), B.HeadScanBase + B.HeadScanRange * t)
		end
	elseif item.kind == "Cell" then
		local Bt = CoreLoopConfig.Battery
		return if item.cell == "Coil" then string.format("+%d%% recharge", math.round(Bt.CoilBonus * 100)) else string.format("+%d max battery", Bt.CellBonus)
	elseif item.kind == "Weapon" then
		local w = CoreLoopConfig.Weapons[item.weapon or "Fists"]
		return if w then w.blurb else ""
	end
	return ""
end

-- Remote-safe copy (strings / numbers only).
function Items.clean(item: Item): Item
	return {
		uid = item.uid,
		kind = item.kind,
		slot = item.slot,
		tier = item.tier,
		variant = item.variant,
		cell = item.cell,
		weapon = item.weapon,
	}
end

return Items
