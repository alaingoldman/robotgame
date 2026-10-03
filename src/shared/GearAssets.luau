--!strict
-- Asset ids of the 20-tier steampunk gear models (assets/gear3d). Fill these
-- in after importing each GLB in Studio as a Model and publishing it
-- ("Save to Roblox" / Asset Manager -> copy the asset id):
--
--   Tiers[n]  = id of assets/gear3d/Gear_T<nn>.glb  (MeshParts ArmR_Upper,
--               ArmR_Lower, ArmR_Hand, ArmL_*, LegR_Upper, LegR_Lower,
--               LegR_Foot, LegL_*, Torso_Upper, optional Torso_Lower, Head)
--   Weapons   = id of assets/gear3d/Weapons.glb  (MeshParts W_M01..W_M10,
--               W_R01..W_R10, grip at the file's origin)
--
-- nil = not imported yet: the game builds a procedural placeholder for that
-- tier / the weapons (ArmorBuilder), so everything works with zero ids.
-- The server loads a model the first time someone needs it
-- (InsertService:LoadAsset -> ReplicatedStorage.GearMeshes, see GearMeshes).

local GearAssets = {}

GearAssets.Tiers = {
	[1] = 129774576203721, -- Scrap Tin
	[2] = 87859246085735, -- Junkyard Iron
	[3] = 121752361759430, -- Boilerplate
	[4] = 79624060491943, -- Verdigris Copper
	[5] = 132837181895917, -- Coalworks
	[6] = 113641051314199, -- Brass Piston
	[7] = nil, -- Clockwork
	[8] = nil, -- Foundry
	[9] = nil, -- Rail Baron
	[10] = nil, -- Ironclad
	[11] = nil, -- Tesla
	[12] = nil, -- Aether Diver
	[13] = nil, -- Dreadnought
	[14] = nil, -- Gilded Engine
	[15] = nil, -- Cog Royal
	[16] = nil, -- Sky Admiral
	[17] = nil, -- Arcanum
	[18] = nil, -- Sun Furnace
	[19] = nil, -- Celestial Orrery
	[20] = nil, -- Emperor's Clockheart
} :: { [number]: number? }

GearAssets.Weapons = nil :: number?

-- Fit tuning: an armour piece is scaled so it encloses the body part it
-- covers times Margin (per axis), keeping at least KeepAspect of its own
-- proportions (so a chunky pauldron stays chunky instead of being squashed).
GearAssets.Margin = 1.12
GearAssets.KeepAspect = 0.85
-- Weapon length (studs, longest side) by kind; a little longer per tier.
GearAssets.MeleeLength = 4.2
GearAssets.RangedLength = 2.6
GearAssets.LengthPerTier = 0.04

return GearAssets
