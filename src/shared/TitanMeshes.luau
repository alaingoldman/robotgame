--!strict
-- Optional MeshPart skins for the BRZ-01 Titan's curved armour.
--
-- The shoulder pads, the chest bulge and the helmet shell are built by
-- ChestBuilder / HeadBuilder from hundreds of thin wedge facets, so the
-- crosshatch Texture can't flow across them (TitanPattern leaves them plain).
-- assets/meshes/*.obj are the SAME surfaces exported as single meshes with
-- proper UVs (1 texture repeat = 4 studs = MechPattern's large crosshatch
-- tile). Once the owner has imported them into ReplicatedStorage.TitanMeshes
-- (see assets/meshes/README.md), TitanMeshes.apply swaps each wedge group for
-- one welded MeshPart; until then it does nothing and the wedge build stays.
--
-- Per mesh, missing template = that group keeps its wedges (each is optional).
-- The crosshatch comes from a SurfaceAppearance on the template, or, for
-- every template without one, ReplicatedStorage.TitanMeshes.Crosshatch (a
-- SurfaceAppearance). The MeshParts get the wedges' palette role ("TitanRole"), so
-- TitanBuilder.applySlot recolours them like any other part. The crosshatch
-- is a SurfaceAppearance on the template (AlphaMode Overlay, ColorMap =
-- Titan_Crosshatch_Overlay.png: black at alpha 0.5 * (1 - lattice), i.e. the
-- same "part colour * (0.5 + 0.5 * lattice)" as the 50% tinted Textures). It
-- is shown only while the mech has a pattern (MechPattern "Pattern"
-- attribute), synced from MechPattern.postApply. MeshPart.TextureID is NOT
-- used: Studio test showed it ignores the alpha (MeshPart.Color doesn't show
-- through), while SurfaceAppearance Overlay does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MechPattern = require(script.Parent.MechPattern)

local TitanMeshes = {}

TitanMeshes.FolderName = "TitanMeshes" -- ReplicatedStorage.<FolderName>: MeshPart templates by name
local MESH_ATTR = "TitanMesh"
-- Studio's 3D importer turned every .obj 180 deg about Y (x -> -x, z -> -z; checked
-- vertex by vertex against the files via EditableMesh), so the templates are
-- turned back by this when placed. Size is unaffected.
TitanMeshes.ImportRotation = CFrame.Angles(0, math.pi, 0)

type Entry = {
	bone: string, -- bone the mesh is welded to
	model: string, -- sub-model holding that bone
	folder: string, -- folder holding the wedge parts it replaces
	parts: { [string]: boolean }, -- wedge part names it replaces
	all: boolean?, -- HEAD/COLLAR MESHES: replaces EVERY BasePart in the folder (the whole primitive head / gorget)
	set: string?, -- HEAD/COLLAR MESHES: applied only when every template of this set exists (no half-built head)
	supersededBy: string?, -- skipped once that set is complete (the old helmet skins under the new head)
	role: string, -- TitanRole palette role
	offset: Vector3, -- mesh bounding-box centre in the bone's frame (studs, Scale 1.7)
	size: Vector3, -- mesh bounding-box size (studs)
}

-- Exported from the Scale 1.7 build (assets/meshes/README.md has the same table).
TitanMeshes.Meshes = {
	Titan_ShoulderPad_R = {
		bone = "Chest", model = "MechChest", folder = "RightPadArmor", parts = { PadShell = true }, role = "main",
		offset = Vector3.new(5.3285, 6.5076, 0.6936), size = Vector3.new(4.488, 6.324, 4.488),
	},
	Titan_ShoulderPad_L = {
		bone = "Chest", model = "MechChest", folder = "LeftPadArmor", parts = { PadShell = true }, role = "main",
		offset = Vector3.new(-5.3285, 6.5076, 0.6936), size = Vector3.new(4.488, 6.324, 4.488),
	},
	Titan_ChestDome = {
		bone = "Hatch", model = "MechChest", folder = "TorsoArmor", parts = { ChestPlate = true, ChestLower = true, ChestSide = true }, role = "main",
		offset = Vector3.new(0, 2.5224, -0.8768), size = Vector3.new(6.4954, 4.9368, 1.9584),
	},
	Titan_ChestCrescent = {
		bone = "Hatch", model = "MechChest", folder = "TorsoArmor", parts = { ChestCrescent = true }, role = "hi",
		offset = Vector3.new(0, 2.1756, -1.0007), size = Vector3.new(6.4464, 1.8768, 1.7107),
	},
	Titan_Helmet = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = { HelmetShell = true }, role = "main",
		offset = Vector3.new(0, 1.4059, 0.0082), size = Vector3.new(2.1542, 1.9145, 3.4435),
		supersededBy = "Head",
	},
	Titan_HelmetCap = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = { HelmetCap = true }, role = "hi",
		offset = Vector3.new(0, 0.9588, 0.0082), size = Vector3.new(2.1542, 1.02, 3.3782),
		supersededBy = "Head",
	},

	-- HEAD/COLLAR MESHES (assets/meshes/README.md, "Head and collar"): the head and neck
	-- modelled from the owner's FRONT / SIDE / BACK head views. Set "Head"
	-- replaces the whole primitive helmet (HelmetArmor), set "Collar" the
	-- whole HeadBuilder gorget (CollarArmor) and, via ThroatFold, the
	-- ChestBuilder ThroatPlates + CollarRing. Offsets: mesh bounding-box centre in the bone frame.
	Titan_HeadMain = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = {}, all = true, set = "Head", role = "main",
		offset = Vector3.new(0, 0.7222, -0.2596), size = Vector3.new(2.5786, 3.6312, 3.4628),
	},
	Titan_HeadTrim = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = {}, all = true, set = "Head", role = "hi",
		offset = Vector3.new(0, 0.1102, -0.5467), size = Vector3.new(2.9539, 2.5541, 2.8723),
	},
	Titan_HeadCrest = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = {}, all = true, set = "Head", role = "trim",
		offset = Vector3.new(0, 2.2114, -1.6238), size = Vector3.new(0.6202, 2.6602, 0.7181),
	},
	Titan_HeadVisor = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = {}, all = true, set = "Head", role = "glow",
		offset = Vector3.new(0, 0.5467, -1.325), size = Vector3.new(1.6157, 0.4896, 0.7119),
	},
	Titan_HeadRecess = {
		bone = "Head", model = "MechHead", folder = "HelmetArmor", parts = {}, all = true, set = "Head", role = "recess",
		offset = Vector3.new(0, 0.9792, -0.083), size = Vector3.new(2.5214, 1.4688, 3.1469),
	},
	Titan_Gorget = {
		bone = "Collar", model = "MechHead", folder = "CollarArmor", parts = {}, all = true, set = "Collar", role = "main",
		offset = Vector3.new(0, 0.8609, 0.6528), size = Vector3.new(4.4717, 2.9458, 4.2432),
	},
	Titan_GorgetRecess = {
		bone = "Collar", model = "MechHead", folder = "CollarArmor", parts = {}, all = true, set = "Collar", role = "recess",
		offset = Vector3.new(0, 1.0608, 0.6528), size = Vector3.new(3.8189, 2.6112, 3.5904),
	},
	-- also drops ChestBuilder's brass CollarRing: it doubled the gorget (the sheet
	-- shows one ring round the head) and its 20 box segments looked jagged next to it
	Titan_ThroatFold = {
		bone = "Chest", model = "MechChest", folder = "TorsoArmor", parts = { ThroatPlate = true, CollarRing = true }, set = "Collar", role = "main",
		offset = Vector3.new(0, 6.3811, -1.7952), size = Vector3.new(2.1542, 1.2403, 1.1424),
	},
} :: { [string]: Entry }

local function templates(): Instance?
	return ReplicatedStorage:FindFirstChild(TitanMeshes.FolderName)
end

local function template(name: string): MeshPart?
	local folder = templates()
	local t = folder and folder:FindFirstChild(name)
	return if t and t:IsA("MeshPart") then t else nil
end

-- HEAD/COLLAR MESHES: true when every template of a mesh set is present.
local function setComplete(set: string): boolean
	for name, e in TitanMeshes.Meshes do
		if e.set == set and not template(name) then
			return false
		end
	end
	return true
end

-- True when at least one template is present.
function TitanMeshes.available(): boolean
	for name in TitanMeshes.Meshes do
		if template(name) then
			return true
		end
	end
	return false
end

local function findModel(model: Instance, name: string): Instance?
	for _, d in model:GetDescendants() do
		if d.Name == name and d:IsA("Model") then
			return d
		end
	end
	return nil
end

-- Swaps every wedge group whose template exists for its MeshPart. Call on a
-- freshly built Titan rig (TitanBuilder.buildRig), before applySlot. No-op
-- without templates.
function TitanMeshes.apply(model: Model)
	if not templates() then
		return
	end
	-- HEAD/COLLAR MESHES: several meshes can replace the same parts (a set),
	-- so the replaced parts are collected and destroyed after all are placed
	local doomed: { [BasePart]: boolean } = {}
	for name, e in TitanMeshes.Meshes do
		local t = template(name)
		if t and e.set and not setComplete(e.set) then
			continue -- part of a set that isn't fully imported: keep the primitive build
		end
		if t and e.supersededBy and setComplete(e.supersededBy) then
			continue -- the old helmet skins step aside for the modelled head
		end
		local sub = if t then findModel(model, e.model) else nil
		local bone = sub and sub:FindFirstChild(e.bone, true)
		local folder = sub and sub:FindFirstChild(e.folder, true)
		if not (t and bone and bone:IsA("BasePart") and folder) then
			continue
		end
		local sample: BasePart? = nil
		local swapped = false
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				if p:GetAttribute(MESH_ATTR) ~= nil then
					swapped = swapped or p:GetAttribute(MESH_ATTR) == name
				elseif e.all or e.parts[p.Name] then
					sample = sample or p
					doomed[p] = true
				end
			end
		end
		if swapped or not sample then
			continue -- already swapped (or the builder renamed its parts)
		end
		local mp = t:Clone()
		mp.Name = name
		mp.Size = e.size -- exact export size, whatever unit the importer assumed
		local place = CFrame.new(e.offset) * TitanMeshes.ImportRotation
		mp.CFrame = bone.CFrame * place
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanTouch = false
		mp.CanQuery = false
		mp.Massless = true
		mp.CastShadow = true
		mp.TextureID = "" -- an imported texture would hide MeshPart.Color (TextureID ignores alpha)
		mp.CollisionGroup = sample.CollisionGroup
		mp.Color = sample.Color
		mp.Material = sample.Material
		mp:SetAttribute("TitanRole", e.role)
		mp:SetAttribute("PatternPlain", true) -- no per-face Textures (TitanPattern drops them); the SurfaceAppearance draws the pattern
		mp:SetAttribute(MESH_ATTR, name)
		for _, c in mp:GetChildren() do
			if c:IsA("SurfaceAppearance") then
				c.AlphaMode = Enum.AlphaMode.Overlay
				c:Destroy() -- added back by syncPattern while a pattern is on
			elseif not c:IsA("Attachment") then
				c:Destroy()
			end
		end
		local w = Instance.new("Weld")
		w.Part0 = bone
		w.Part1 = mp
		w.C0 = place
		w.Parent = mp
		mp.Parent = folder
	end
	for p in doomed do
		p:Destroy()
	end
	TitanMeshes.syncPattern(model)
end

-- Shows the crosshatch SurfaceAppearance on the mesh skins while the mech has
-- a pattern (MechPattern sets the "Pattern" attribute), hides it otherwise.
function TitanMeshes.syncPattern(model: Model)
	local on = model:GetAttribute("Pattern") ~= nil
	for _, d in model:GetDescendants() do
		local name = d:GetAttribute(MESH_ATTR)
		if not (d:IsA("MeshPart") and typeof(name) == "string") then
			continue
		end
		local sa = d:FindFirstChildOfClass("SurfaceAppearance")
		if on and not sa then
			local t = template(name)
			local folder = templates()
			local shared = folder and folder:FindFirstChild("Crosshatch")
			local src = (t and t:FindFirstChildOfClass("SurfaceAppearance"))
				or (if shared and shared:IsA("SurfaceAppearance") then shared else nil)
			if src then
				local c = src:Clone()
				c.AlphaMode = Enum.AlphaMode.Overlay
				c.Parent = d
			end
		elseif not on and sa then
			sa:Destroy()
		end
	end
end

-- chain after TitanPattern's pass (TitanBuilder requires TitanPattern first)
local previous = MechPattern.postApply.Titan
MechPattern.postApply.Titan = function(model: Model)
	if previous then
		previous(model)
	end
	TitanMeshes.syncPattern(model)
end

return TitanMeshes
