--!strict
-- Surface patterns for mech armor, drawn as Texture layers over the armor.
--
-- "Crosshatch" is the weld-lattice image at half opacity: the 4x4 tile on big
-- faces, the finer 2x2 tile on small parts. Each Texture is tinted with its
-- part's Color, so each palette keeps its colors. Neon lights and invisible
-- parts are left alone.
--
-- The variants are declared in default.project.json (MaterialService);
-- ensureVariants() recreates any that are missing (server only, replicates).

local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")

local MechPattern = {}

type PatternDef = { largeImage: string, largeTile: number, smallImage: string, smallTile: number }

-- Color maps of the "Weld 4x4" / "Weld 2x2" crosshatch MaterialVariants,
-- laid on as semi-transparent Textures (MaterialVariants have no opacity).
MechPattern.Patterns = {
	Crosshatch = {
		largeImage = "rbxassetid://133133290921309",
		largeTile = 4,
		smallImage = "rbxassetid://93972722451997",
		smallTile = 2,
	},
} :: { [string]: PatternDef }

local OPACITY = 0.5 -- Texture.Transparency: the pattern at half strength
local TEXTURE_NAME = "PatternTex"
local FACES = {
	{ Enum.NormalId.Top, "X", "Z" },
	{ Enum.NormalId.Bottom, "X", "Z" },
	{ Enum.NormalId.Front, "X", "Y" },
	{ Enum.NormalId.Back, "X", "Y" },
	{ Enum.NormalId.Left, "Z", "Y" },
	{ Enum.NormalId.Right, "Z", "Y" },
}

-- name, color map, normal map, texture pack, studs per tile
local VARIANT_DEFS = {
	{ "Weld 4x4 Plastic", "rbxassetid://133133290921309", "rbxassetid://111184109610225", "rbxassetid://102130267281819", 4 },
	{ "Weld 2x2 Plastic", "rbxassetid://93972722451997", "rbxassetid://102954553386109", "rbxassetid://130034317968746", 2 },
}

local ARMOR_FOLDERS = { "Armor_Helmet", "Armor_Chest", "Armor_Legs" }
local SMALL_SIZE = 2 -- middle dimension below this uses the finer variant
local PATTERN_METAL = false -- dark Metal parts (joints, guns) keep their metal look
local BASE_ATTR = "PatternBase" -- original material, for removing the pattern

-- Creates any missing MaterialVariants. Safe to call more than once.
-- The pattern itself is drawn with Textures now, so these are optional; game
-- scripts may not be allowed to set MaterialVariant properties, so any
-- failure here is ignored rather than stopping the caller.
function MechPattern.ensureVariants()
	if not RunService:IsServer() then
		return
	end
	for _, d in VARIANT_DEFS do
		local name = d[1] :: string
		if not MaterialService:FindFirstChild(name) then
			pcall(function()
				local v = Instance.new("MaterialVariant")
				v.Name = name
				v.BaseMaterial = Enum.Material.Plastic
				v.ColorMap = d[2] :: string
				v.NormalMap = d[3] :: string
				v.StudsPerTile = d[5] :: number
				v.Parent = MaterialService
			end)
		end
	end
end

local function middleSize(s: Vector3): number
	local a, b, c = s.X, s.Y, s.Z
	return math.max(math.min(a, b), math.min(math.max(a, b), c))
end

local function patternable(part: BasePart): boolean
	if part.Transparency >= 1 then
		return false
	end
	local base = part:GetAttribute(BASE_ATTR)
	local material = if typeof(base) == "string" then base else part.Material.Name
	if material == "Neon" or material == "Glass" or material == "ForceField" then
		return false
	end
	return PATTERN_METAL or material ~= "Metal"
end

local function clear(part: BasePart)
	local base = part:GetAttribute(BASE_ATTR)
	if typeof(base) == "string" then
		part.Material = (Enum.Material :: any)[base]
		part:SetAttribute(BASE_ATTR, nil)
	end
	part.MaterialVariant = ""
	for _, c in part:GetChildren() do
		if c:IsA("Texture") and c.Name == TEXTURE_NAME then
			c:Destroy()
		end
	end
end

-- Lays the pattern image over every face that's big enough to show it.
local function addTextures(part: BasePart, def: PatternDef)
	local size = part.Size
	for _, f in FACES do
		local a, b = (size :: any)[f[2]] :: number, (size :: any)[f[3]] :: number
		if math.max(a, b) < 0.6 or math.min(a, b) < 0.2 then
			continue
		end
		local tile = if middleSize(size) < SMALL_SIZE or math.min(a, b) < 1 then def.smallTile else def.largeTile
		local t = Instance.new("Texture")
		t.Name = TEXTURE_NAME
		t.Face = f[1]
		t.Texture = if tile == def.smallTile then def.smallImage else def.largeImage
		t.StudsPerTileU = tile
		t.StudsPerTileV = tile
		t.Color3 = part.Color
		t.Transparency = OPACITY
		t.Parent = part
	end
end

-- Applies `pattern` to the model's visible armor (nil removes it) and
-- remembers it in the "Pattern" attribute. Idempotent; call again after
-- an armor slot is rebuilt.
function MechPattern.apply(model: Model, pattern: string?)
	local def = if pattern then MechPattern.Patterns[pattern] else nil
	model:SetAttribute("Pattern", if def then pattern else nil)
	for _, folderName in ARMOR_FOLDERS do
		local folder = model:FindFirstChild(folderName)
		if not folder then
			continue
		end
		for _, d in folder:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			clear(d)
			if def and patternable(d) then
				addTextures(d, def)
			end
		end
	end
end
return MechPattern
