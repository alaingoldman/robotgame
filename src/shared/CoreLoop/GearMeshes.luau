--!strict
-- Steampunk gear mesh templates (asset ids in GearAssets), like
-- Mech3Meshes / CrimsonMeshes: the server loads an imported Model with
-- InsertService:LoadAsset the first time it is needed and keeps it in
-- ReplicatedStorage.GearMeshes (so clients can clone it too, e.g. the
-- locker previews):
--   GearMeshes/T07      the tier 7 set (MeshParts ArmR_Upper, LegL_Foot, Head ...)
--   GearMeshes/Weapons  W_M01 .. W_R10
-- Each holder carries the attribute AssetId (a changed id reloads) and
-- Flipped (true when Studio's importer turned the file 180 deg about Y:
-- detected from where the ArmR / ArmL or LegR / LegL nodes landed).
--
-- Source frame (the GLB): front -Z, +X = the character's right, i.e. the
-- same as a Roblox character's own frame. A node's rotation in the source
-- frame = GearMeshes.importRotation(holder) * node.CFrame.Rotation.
--
--   GearMeshes.tier(n) / .weapons()     -> holder Model? (loaded and current)
--   GearMeshes.node(holder, name)       -> BasePart?
--   GearMeshes.request(n | "Weapons")   (server) async load if an id is set
--   GearMeshes.onLoaded(fn(key))        (server) after a load finishes

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GearAssets = require(script.Parent.Parent:WaitForChild("GearAssets"))

local GearMeshes = {}

GearMeshes.FolderName = "GearMeshes"
local FLIP = CFrame.Angles(0, math.pi, 0)

local loading: { [string]: boolean } = {}
local failed: { [string]: number } = {} -- key -> asset id that failed
local listeners: { (string) -> () } = {}

local function keyOf(which: number | string): string
	if which == "Weapons" then
		return "Weapons"
	end
	return string.format("T%02d", which :: number)
end

local function assetOf(key: string): number?
	if key == "Weapons" then
		return GearAssets.Weapons
	end
	local n = tonumber(string.sub(key, 2))
	return if n then GearAssets.Tiers[n] else nil
end

local function holder(key: string): Model?
	local f = ReplicatedStorage:FindFirstChild(GearMeshes.FolderName)
	local m = f and f:FindFirstChild(key)
	local id = assetOf(key)
	if m and m:IsA("Model") and id and m:GetAttribute("AssetId") == id then
		return m
	end
	return nil
end

function GearMeshes.tier(tier: number): Model?
	return holder(keyOf(tier))
end

function GearMeshes.weapons(): Model?
	return holder("Weapons")
end

function GearMeshes.node(h: Instance, name: string): BasePart?
	local n = h:FindFirstChild(name, true)
	if n and n:IsA("BasePart") then
		return n
	end
	-- importers sometimes wrap a mesh in a Model named after the node
	if n then
		local p = n:FindFirstChildWhichIsA("BasePart", true)
		if p then
			return p
		end
	end
	return nil
end

-- Rotation taking the loaded (asset) frame back to the source frame.
function GearMeshes.importRotation(h: Instance): CFrame
	return if h:GetAttribute("Flipped") == false then CFrame.identity else FLIP
end

local function detectFlip(h: Instance): boolean?
	for _, pair in { { "ArmR_Upper", "ArmL_Upper" }, { "ArmR_Hand", "ArmL_Hand" }, { "LegR_Upper", "LegL_Upper" }, { "LegR_Foot", "LegL_Foot" } } do
		local r, l = GearMeshes.node(h, pair[1]), GearMeshes.node(h, pair[2])
		if r and l and math.abs(r.Position.X - l.Position.X) > 1e-3 then
			-- source: the right side is +X; after a 180 deg import it is -X
			return r.Position.X < l.Position.X
		end
	end
	return nil
end

function GearMeshes.onLoaded(fn: (string) -> ())
	table.insert(listeners, fn)
end

local function load(key: string, id: number)
	local ok, res = pcall(InsertService.LoadAsset, InsertService, id)
	if not ok or not res then
		failed[key] = id
		warn(string.format("[GearMeshes] LoadAsset %s (%s) failed: %s", tostring(id), key, tostring(res)))
		return
	end
	-- the asset's own Model (LoadAsset wraps it in another Model)
	local kids = res:GetChildren()
	local m: Model
	if #kids == 1 and kids[1]:IsA("Model") then
		m = kids[1] :: Model
		m.Parent = nil
		res:Destroy()
	else
		m = res
	end
	m.Name = key
	m:SetAttribute("AssetId", id)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if key ~= "Weapons" then
		local flip = detectFlip(m)
		m:SetAttribute("Flipped", if flip == nil then true else flip)
	else
		-- no left / right pair to detect: assume Studio's usual 180 deg turn
		m:SetAttribute("Flipped", true)
	end
	local f = ReplicatedStorage:FindFirstChild(GearMeshes.FolderName)
	if not f then
		f = Instance.new("Folder")
		f.Name = GearMeshes.FolderName
		f.Parent = ReplicatedStorage
	end
	local old = (f :: Instance):FindFirstChild(key)
	if old then
		old:Destroy()
	end
	m.Parent = f
	for _, fn in listeners do
		task.spawn(fn, key)
	end
end

-- Starts loading a tier (1..20) or "Weapons" if its id is set and it isn't
-- loaded yet. Never yields. Server / edit mode only.
function GearMeshes.request(which: number | string)
	if RunService:IsClient() and RunService:IsRunning() then
		return
	end
	local key = keyOf(which)
	local id = assetOf(key)
	if not id or holder(key) or loading[key] or failed[key] == id then
		return
	end
	loading[key] = true
	task.spawn(function()
		load(key, id)
		loading[key] = nil
	end)
end

-- Loads every configured id (server start-up).
function GearMeshes.preloadAll()
	for n = 1, 20 do
		GearMeshes.request(n)
	end
	GearMeshes.request("Weapons")
end

return GearMeshes
