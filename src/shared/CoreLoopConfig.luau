--!strict
-- Tunables for the core gameplay loop ("Scrapyard"): wear the EXO-1, smash
-- JUNK, carry dropped ARMOUR / WEAPONS home before they expire, equip them,
-- race the timed CRATES, manage your BATTERY.
--
-- Server: src/server/CoreLoop/* (Scrapyard map, Bases, PlayerState, Combat,
-- Junk, Crates, Loot, Gear). Client: src/client/CoreLoop/* (Hud, LockerUi,
-- Controls, Fx, World). Shared: src/shared/CoreLoop/* (PartBuilder,
-- ArmorBuilder, GearMeshes, Items) + src/shared/GearAssets (mesh asset ids).
-- Everything is per session (the game has no save system yet).

local CoreLoopConfig = {}

CoreLoopConfig.Enabled = true

---------------------------------------------------------------- testing
-- Multiplies every drop chance (junk + crates). Also per player: the player
-- attribute "CoreDropBoost" (number) multiplies on top (eval / admin tests).
CoreLoopConfig.DropChanceMultiplier = 1
-- Crate spawn interval multiplier (0.2 = crates 5x as often) for tests.
CoreLoopConfig.CrateIntervalMultiplier = 1

---------------------------------------------------------------- world
-- The yard sits south of the spawn (+Z), clear of the mech lineups (-Z),
-- the EXO showcase (z ~ 20) and the assembled-mech preview (x ~ 160).
CoreLoopConfig.Yard = {
	Center = Vector3.new(0, 0, 160),
	Size = Vector2.new(240, 180), -- x, z (yard floor z 70 .. 250)
	FolderName = "Scrapyard",
}
-- Base plots: a row between the spawn and the yard gate (z ~ 52).
CoreLoopConfig.Bases = {
	Z = 50,
	X = { -84, -28, 28, 84 },
	PadSize = 26,
	-- respawn on your own base pad (instead of the spawn plate)
	SpawnAtBase = true,
}

---------------------------------------------------------------- player
-- Movement on foot in the loop. The EXO-1 is a heavy scrap rig, so the core
-- loop runs players a little slower than the mech world (StarterPlayer 32);
-- legs parts win the speed back.
CoreLoopConfig.BaseWalkSpeed = 26
CoreLoopConfig.SprintMultiplier = 1.4
CoreLoopConfig.CarryMultiplier = 0.72 -- carrying a part or cell
CoreLoopConfig.EmptyMultiplier = 0.55 -- battery at 0
CoreLoopConfig.RespawnTime = 2

CoreLoopConfig.Battery = {
	Max = 100,
	IdleRegen = 2.5, -- per second, after IdleDelay without draining
	IdleDelay = 1.8,
	BaseCharge = 45, -- per second on your base pad (the charger)
	SprintDrain = 7, -- per second while sprinting and moving
	CarryDrain = 0.6, -- per second while carrying cargo
	-- scrap shop at the charger: +Step max battery per purchase
	ShopStep = 20,
	ShopCosts = { 40, 80, 140, 220, 320, 450, 600 },
	-- battery upgrade cargo (drops): installed when delivered to your base
	CellBonus = 25, -- "Power Cell": +max
	CoilBonus = 0.35, -- "Charge Coil": +35 % recharge (idle + base)
	Low = 25, -- HUD warning below this %
}

---------------------------------------------------------------- combat
CoreLoopConfig.Combat = {
	BaseDamage = 10,
	ComboWindow = 0.65, -- seconds after a swing for the next combo step
	ComboMultipliers = { 1, 1.1, 1.7 }, -- jab, cross, haymaker
	CritChance = 0.12,
	CritMultiplier = 1.6,
	-- server slack on cooldowns (latency jitter)
	CooldownSlack = 0.06,
	-- melee reach: target surface within Range studs of the root, roughly in
	-- front (dot > FrontDot), or anywhere within CloseRange
	FrontDot = 0.25,
}

---------------------------------------------------------------- tiers
-- Tier colours: rust (T1) -> copper -> bronze -> brass -> gold (T20).
local RAMP: { { any } } = {
	{ 1, Color3.fromRGB(150, 82, 52) },
	{ 4, Color3.fromRGB(176, 104, 66) },
	{ 8, Color3.fromRGB(196, 136, 72) },
	{ 12, Color3.fromRGB(212, 166, 78) },
	{ 16, Color3.fromRGB(236, 194, 76) },
	{ 20, Color3.fromRGB(255, 228, 120) },
}
function CoreLoopConfig.tierColor(tier: number): Color3
	local t = math.clamp(tier, 1, 20)
	for i = 1, #RAMP - 1 do
		local a, b = RAMP[i], RAMP[i + 1]
		if t <= b[1] then
			return (a[2] :: Color3):Lerp(b[2] :: Color3, (t - a[1]) / (b[1] - a[1]))
		end
	end
	return RAMP[#RAMP][2] :: Color3
end

---------------------------------------------------------------- weapons
-- Weapons ("Fists" is always owned). Damage multiplies the base damage.
-- The 20 steampunk weapons (assets/gear_concepts/prompts.md): id "M01".."M10"
-- (melee) / "R01".."R10" (ranged); their mesh is node "W_" .. id of the
-- Weapons asset (GearAssets). Stats scale with the weapon's tier; `anim` is
-- the swing style the client plays (Fists / Blade = slash / Hammer = overhead
-- slam with an aoe / Rivet = aimed hitscan shot).
export type Weapon = {
	id: string,
	name: string,
	tier: number,
	anim: string,
	damage: number,
	cooldown: number,
	cost: number, -- battery per swing
	range: number,
	aoe: number?, -- radius: hits every target within it (in front)
	ranged: boolean?,
	shake: number,
	color: Color3,
	blurb: string,
}

-- { id, name, tier, style }
local WEAPON_LIST: { { any } } = {
	{ "M01", "Scrap Pipe-Wrench Club", 1, "light" },
	{ "M02", "Junkyard Chain Cleaver", 3, "medium" },
	{ "M03", "Boilerplate Rivet Sledgehammer", 5, "heavy" },
	{ "M04", "Coal Furnace Axe", 7, "medium" },
	{ "M05", "Clockwork Buzzsaw Greatsword", 8, "medium" },
	{ "M06", "Locomotive Piston Warhammer", 9, "heavy" },
	{ "M07", "Tesla Arc Sabre", 11, "light" },
	{ "M08", "Dreadnought Anchor Greatblade", 13, "heavy" },
	{ "M09", "Arcanum Rune Scythe", 17, "sweep" },
	{ "M10", "Emperor's Clockwork Halberd", 20, "heavy" },
	{ "R01", "Scrap Rivet Pistol", 1, "light" },
	{ "R02", "Junk Blunderbuss", 3, "heavy" },
	{ "R03", "Boilerplate Steam Crossbow", 5, "medium" },
	{ "R04", "Verdigris Copper Harpoon Gun", 6, "medium" },
	{ "R05", "Coal Mortar Hand-Cannon", 8, "heavy" },
	{ "R06", "Brass Gatling Pepperbox", 10, "rapid" },
	{ "R07", "Foundry Flamethrower", 12, "rapid" },
	{ "R08", "Tesla Coil Rifle", 14, "medium" },
	{ "R09", "Aether Ray Blaster", 17, "medium" },
	{ "R10", "Celestial Orrery Railgun", 20, "heavy" },
}

local weapons: { [string]: Weapon } = {
	Fists = {
		id = "Fists",
		name = "Exo Fists",
		tier = 0,
		anim = "Fists",
		damage = 1,
		cooldown = 0.26,
		cost = 2,
		range = 7.5,
		shake = 0.35,
		color = Color3.fromRGB(200, 200, 200),
		blurb = "Fast 3-hit combo",
	},
}
local order = { "Fists" }
for _, e in WEAPON_LIST do
	local id, name, t, style = e[1] :: string, e[2] :: string, e[3] :: number, e[4] :: string
	local ranged = string.sub(id, 1, 1) == "R"
	local w: Weapon
	if ranged then
		local base = 0.95 + 0.17 * t
		local mul, cd, cost = 1.4, 0.28, 3
		if style == "light" then
			mul, cd, cost = 1, 0.17, 2.5
		elseif style == "rapid" then
			mul, cd, cost = 0.72, 0.11, 2
		elseif style == "heavy" then
			mul, cd, cost = 2.3, 0.55, 5
		end
		w = {
			id = id,
			name = name,
			tier = t,
			anim = "Rivet",
			ranged = true,
			damage = base * mul,
			cooldown = cd,
			cost = cost,
			range = 38 + 2.2 * t + (if style == "heavy" then 10 else 0),
			shake = if style == "heavy" then 0.6 else 0.25,
			color = CoreLoopConfig.tierColor(t),
			blurb = "",
		}
	else
		local base = 1.25 + 0.2 * t
		local mul, cd, cost, anim, aoe = 1, 0.26, 2, "Blade", nil :: number?
		if style == "medium" then
			mul, cd, cost = 1.4, 0.36, 3
		elseif style == "sweep" then
			mul, cd, cost, aoe = 1.5, 0.42, 3.5, 8 + 0.1 * t
		elseif style == "heavy" then
			mul, cd, cost, anim, aoe = 2.1, 0.62, 5, "Hammer", 7 + 0.12 * t
		end
		w = {
			id = id,
			name = name,
			tier = t,
			anim = anim,
			aoe = aoe,
			damage = base * mul,
			cooldown = cd,
			cost = cost,
			range = 8.5 + 0.08 * t + (if style == "heavy" then 0.5 else 0),
			shake = if anim == "Hammer" then 1 else 0.4,
			color = CoreLoopConfig.tierColor(t),
			blurb = "",
		}
	end
	w.blurb = string.format(
		"T%d  x%.1f dmg  %.2fs%s%s",
		t,
		w.damage,
		w.cooldown,
		if w.aoe then "  area" else "",
		if ranged then string.format("  %dm", math.floor(w.range)) else ""
	)
	weapons[id] = w
	table.insert(order, id)
end
CoreLoopConfig.Weapons = weapons
CoreLoopConfig.WeaponOrder = order

-- Swing style for a weapon id (unknown ids -> Fists).
function CoreLoopConfig.weaponAnim(id: string?): string
	local w = if id then weapons[id] else nil
	return if w then w.anim else "Fists"
end

---------------------------------------------------------------- junk
export type JunkKind = {
	id: string,
	hp: number,
	scrap: { number }, -- min, max
	drop: number, -- part drop chance
	weaponDrop: number,
	cellDrop: number,
	size: number, -- rough footprint (studs)
	weight: number, -- spawn weight
	tiers: { number }, -- drop odds T1, T2, ... (armour and weapons)
}
CoreLoopConfig.Junk = {
	MaxActive = 26,
	RespawnDelay = { 4, 9 },
	Kinds = {
		{ id = "Small", hp = 30, scrap = { 2, 4 }, drop = 0.07, weaponDrop = 0.012, cellDrop = 0.01, size = 3, weight = 5, tiers = { 40, 30, 18, 10, 2 } },
		{ id = "Medium", hp = 80, scrap = { 5, 9 }, drop = 0.16, weaponDrop = 0.03, cellDrop = 0.025, size = 5, weight = 3, tiers = { 20, 24, 22, 16, 8, 5, 3, 1.5, 0.5 } },
		{ id = "Large", hp = 180, scrap = { 12, 20 }, drop = 0.32, weaponDrop = 0.05, cellDrop = 0.05, size = 7.5, weight = 1.2, tiers = { 6, 10, 14, 16, 14, 12, 9, 7, 5, 3, 2, 1.2, 0.6, 0.2 } },
	} :: { JunkKind },
}

---------------------------------------------------------------- crates
CoreLoopConfig.Crates = {
	FirstDelay = 20, -- seconds after the server starts
	Interval = { 35, 50 },
	MaxActive = 2,
	Lifetime = 30, -- breakdown timer
	HP = 500,
	HPPerExtraPlayer = 150, -- more players in the server = tougher crates
	Scrap = { 40, 60 },
	-- loot: one roll (part / weapon / battery upgrade) + scrap
	LootWeights = { Part = 55, Weapon = 25, Battery = 20 },
	-- T1..T20: crates start at T4; T18-20 are very rare
	TierWeights = { 0, 0, 0, 6, 10, 12, 12, 11, 10, 9, 7, 6, 5, 4, 3, 2, 1.4, 0.8, 0.45, 0.2 },
}

---------------------------------------------------------------- loot
CoreLoopConfig.Loot = {
	PartExpiry = 45, -- seconds from the drop until a part / cell falls apart
	PickupRadius = 5.5,
	ScrapPickupRadius = 9, -- scrap is magnet-pulled
	WeaponLifetime = 40, -- weapons on the ground (no carry timer)
	LockerSize = 12,
}

---------------------------------------------------------------- armour
-- Twenty steampunk tiers (assets/gear_concepts/prompts.md). Each tier is an
-- armour SET of three pieces: LEGS (both legs), ARMS (both arms) and CHEST
-- (chest + helmet). The 3D models come from GearAssets (asset ids); until a
-- tier's id is set, ArmorBuilder builds a procedural placeholder (PartBuilder
-- in the tier's `family` look, recoloured with `color` / `glow`).
export type Tier = { tier: number, name: string, family: string, color: Color3, glow: Color3 }
local TIER_LIST: { { any } } = {
	{ "Scrap Tin", "HWM", Color3.fromRGB(255, 140, 60) },
	{ "Junkyard Iron", "HWM", Color3.fromRGB(255, 150, 70) },
	{ "Boilerplate", "HWM", Color3.fromRGB(255, 190, 90) },
	{ "Verdigris Copper", "Type99", Color3.fromRGB(80, 230, 170) },
	{ "Coalworks", "Gunner", Color3.fromRGB(255, 120, 40) },
	{ "Brass Piston", "Type99", Color3.fromRGB(255, 200, 90) },
	{ "Clockwork", "Knight", Color3.fromRGB(255, 210, 120) },
	{ "Foundry", "Gunner", Color3.fromRGB(255, 110, 30) },
	{ "Rail Baron", "Knight", Color3.fromRGB(255, 80, 60) },
	{ "Ironclad", "Gunner", Color3.fromRGB(120, 220, 255) },
	{ "Tesla", "Type99", Color3.fromRGB(90, 170, 255) },
	{ "Aether Diver", "Type99", Color3.fromRGB(90, 255, 140) },
	{ "Dreadnought", "Gunner", Color3.fromRGB(255, 90, 60) },
	{ "Gilded Engine", "Knight", Color3.fromRGB(255, 190, 70) },
	{ "Cog Royal", "Knight", Color3.fromRGB(255, 60, 90) },
	{ "Sky Admiral", "Titan", Color3.fromRGB(120, 200, 255) },
	{ "Arcanum", "Titan", Color3.fromRGB(190, 110, 255) },
	{ "Sun Furnace", "Titan", Color3.fromRGB(255, 250, 200) },
	{ "Celestial Orrery", "Titan", Color3.fromRGB(110, 240, 255) },
	{ "Emperor's Clockheart", "Titan", Color3.fromRGB(255, 120, 210) },
}
CoreLoopConfig.MaxTier = #TIER_LIST
local tiers: { Tier } = {}
for i, e in TIER_LIST do
	tiers[i] = { tier = i, name = e[1] :: string, family = e[2] :: string, color = CoreLoopConfig.tierColor(i), glow = e[3] :: Color3 }
end
CoreLoopConfig.Tiers = tiers

-- Armour slots (the weapon is separate). An Arms item covers BOTH arms, Legs
-- both legs, Chest the torso AND the head (helmet). CHEST needs LEGS.
CoreLoopConfig.Slots = { "Legs", "Arms", "Chest" }
-- Per-tier bonuses (x tier number, T1..T20).
CoreLoopConfig.Bonus = {
	LegsSpeed = 0.025, -- +2.5 % walk speed per tier (T20 +50 %)
	LegsJump = 0.02,
	ArmsDamage = 0.1, -- +10 % damage per tier (T20 +200 %)
	ChestBattery = 6, -- +6 max battery per tier
	ChestDrain = 0.02, -- -2 % battery drain per tier (T20 -40 %)
	ChestLuck = 0.04, -- +4 % drop chance per tier (the helmet's scanner)
	ChestScanRange = 8, -- scanner range = 60 + 8 per tier
	ChestScanBase = 60,
}
CoreLoopConfig.RecycleScrapPerTier = 8

return CoreLoopConfig
