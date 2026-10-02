--!strict
-- Tunables for the core gameplay loop ("Scrapyard"): wear the EXO-1, smash
-- JUNK, carry dropped MECH PARTS home before they expire, equip them on your
-- exo, race the timed CRATES, manage your BATTERY.
--
-- Server: src/server/CoreLoop/* (Scrapyard map, Bases, PlayerState, Combat,
-- Junk, Crates, Loot). Client: src/client/CoreLoop/* (Hud, CombatClient,
-- CombatFx, LockerUi, Movement). Shared: src/shared/CoreLoop/* (PartBuilder,
-- Items). Everything is per session (the game has no save system yet).

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
	CarryDrain = 1.5, -- per second while carrying cargo
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

-- Weapons ("Fists" is always owned). Damage multiplies the base damage.
export type Weapon = {
	id: string,
	name: string,
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
CoreLoopConfig.Weapons = {
	Fists = {
		id = "Fists",
		name = "Exo Fists",
		damage = 1,
		cooldown = 0.26,
		cost = 2,
		range = 7.5,
		shake = 0.35,
		color = Color3.fromRGB(200, 200, 200),
		blurb = "Fast 3-hit combo",
	},
	Blade = {
		id = "Blade",
		name = "Scrap Blade",
		damage = 1.6,
		cooldown = 0.24,
		cost = 2,
		range = 9,
		shake = 0.4,
		color = Color3.fromRGB(120, 220, 255),
		blurb = "x1.6 damage, quick slashes",
	},
	Hammer = {
		id = "Hammer",
		name = "Piston Hammer",
		damage = 3.2,
		cooldown = 0.62,
		cost = 5,
		range = 9,
		aoe = 8,
		shake = 1,
		color = Color3.fromRGB(255, 150, 60),
		blurb = "x3.2 damage, slow, smashes everything near",
	},
	Rivet = {
		id = "Rivet",
		name = "Rivet Gun",
		damage = 1.1,
		cooldown = 0.17,
		cost = 2.5,
		range = 46,
		ranged = true,
		shake = 0.25,
		color = Color3.fromRGB(255, 220, 80),
		blurb = "x1.1 damage at range, rapid fire",
	},
} :: { [string]: Weapon }
CoreLoopConfig.WeaponOrder = { "Fists", "Blade", "Hammer", "Rivet" }

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
}
CoreLoopConfig.Junk = {
	MaxActive = 26,
	RespawnDelay = { 4, 9 },
	Kinds = {
		{ id = "Small", hp = 30, scrap = { 2, 4 }, drop = 0.07, weaponDrop = 0.012, cellDrop = 0.01, size = 3, weight = 5 },
		{ id = "Medium", hp = 80, scrap = { 5, 9 }, drop = 0.16, weaponDrop = 0.03, cellDrop = 0.025, size = 5, weight = 3 },
		{ id = "Large", hp = 180, scrap = { 12, 20 }, drop = 0.32, weaponDrop = 0.05, cellDrop = 0.05, size = 7.5, weight = 1.2 },
	} :: { JunkKind },
	-- tier odds for junk part drops (T1..T5)
	TierWeights = { 60, 28, 10, 2, 0 },
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
	TierWeights = { 0, 0, 45, 35, 20 },
}

---------------------------------------------------------------- loot
CoreLoopConfig.Loot = {
	PartExpiry = 45, -- seconds from the drop until a part / cell falls apart
	PickupRadius = 5.5,
	ScrapPickupRadius = 9, -- scrap is magnet-pulled
	WeaponLifetime = 40, -- weapons on the ground (no carry timer)
	LockerSize = 12,
}

---------------------------------------------------------------- parts
-- Five tiers; each tier is a mech family's look (built by PartBuilder).
export type Tier = { tier: number, name: string, family: string, color: Color3 }
CoreLoopConfig.Tiers = {
	{ tier = 1, name = "Scrap", family = "HWM", color = Color3.fromRGB(176, 176, 168) },
	{ tier = 2, name = "Salvage", family = "Type99", color = Color3.fromRGB(96, 220, 110) },
	{ tier = 3, name = "Military", family = "Knight", color = Color3.fromRGB(70, 160, 255) },
	{ tier = 4, name = "Prototype", family = "Gunner", color = Color3.fromRGB(190, 100, 255) },
	{ tier = 5, name = "Titan", family = "Titan", color = Color3.fromRGB(255, 196, 60) },
} :: { Tier }
CoreLoopConfig.FamilyNames = {
	HWM = "HWM-04B",
	Type99 = "WTK-99",
	Knight = "VK-01",
	Gunner = "GR-07",
	Titan = "BRZ-01",
}

CoreLoopConfig.Slots = { "Legs", "Arms", "Chest", "Head" }
-- Per-tier bonuses (x tier number).
CoreLoopConfig.Bonus = {
	LegsSpeed = 0.08, -- +8 % walk speed per tier
	LegsJump = 0.08,
	ArmsDamage = 0.2, -- +20 % damage per tier
	ChestBattery = 15, -- +15 max battery per tier
	ChestDrain = 0.05, -- -5 % battery drain per tier
	HeadLuck = 0.12, -- +12 % drop chance per tier
	HeadScanRange = 30, -- scanner range = 60 + 30 per tier
	HeadScanBase = 60,
}
CoreLoopConfig.RecycleScrapPerTier = 8

return CoreLoopConfig
