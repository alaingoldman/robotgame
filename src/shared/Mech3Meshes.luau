--!strict
-- SRF-03 "Seraph" (type "Mech3") mesh templates. The owner uploaded the
-- textured winged mech (model asset 110252059423481: Model "Mech3", 19
-- MeshParts sharing one baked TextureID; source assets/meshes/mech3).
-- Templates live in ReplicatedStorage.Mech3Meshes, one MeshPart per name,
-- kept exactly where LoadAsset put them (the asset frame):
-- Mech3Meshes.ensure() loads them when missing (edit mode via the plugin, or
-- the server at start-up), like CrimsonMeshes.
--
-- Import rotation: Studio's importer turned the GLB 180 deg about Y (the
-- "_L" parts load at +X, the front faces +Z). The source frame (meta.json)
-- is the model frame: front -Z, +X = the mech's right. So a template's
-- model-space CFrame is ImportRotation * its loaded CFrame. The v2 import's
-- PBR material comes in as a SurfaceAppearance under each MeshPart; it stays
-- with the template and every clone (Mech3Builder keeps it).

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mech3Config = require(script.Parent.Mech3Config)

local Mech3Meshes = {}

Mech3Meshes.FolderName = "Mech3Meshes"
Mech3Meshes.ImportRotation = CFrame.Angles(0, math.pi, 0)
-- the current import (v2 once set: metal PBR, the SurfaceAppearance rides on each template)
Mech3Meshes.MechAsset = Mech3Config.AssetV2 or Mech3Config.AssetV1
Mech3Meshes.AssetAttr = "Mech3Asset" -- set on every template: which import it came from

-- part name -> bone (Mech3Builder). The mesh ids are v1's; a template only
-- counts while it came from the current asset (Mech3Asset attribute).
Mech3Meshes.Parts = {
	Head = { bone = "Helmet", mesh = 98026773126829 },
	Torso = { bone = "Torso", mesh = 98885215792558 },
	Pelvis = { bone = "Pelvis", mesh = 99328222842711 },
	Wing_L = { bone = "LeftWing", mesh = 109264411312045 },
	Wing_R = { bone = "RightWing", mesh = 85867029808253 },
	ShoulderPad_L = { bone = "LeftPad", mesh = 140053617858585 },
	ShoulderPad_R = { bone = "RightPad", mesh = 135583830345012 },
	UpperArm_L = { bone = "LeftUpperArm", mesh = 73984797934016 },
	UpperArm_R = { bone = "RightUpperArm", mesh = 131639118027639 },
	Forearm_L = { bone = "LeftLowerArm", mesh = 86537846906088 },
	Forearm_R = { bone = "RightLowerArm", mesh = 124421954696415 },
	Hand_L = { bone = "LeftHand", mesh = 127341069716161 },
	Hand_R = { bone = "RightHand", mesh = 121049677152315 },
	Thigh_L = { bone = "LeftThigh", mesh = 105976878282724 },
	Thigh_R = { bone = "RightThigh", mesh = 135009820099531 },
	Shin_L = { bone = "LeftShin", mesh = 82952579262965 },
	Shin_R = { bone = "RightShin", mesh = 118069328067321 },
	Foot_L = { bone = "LeftFoot", mesh = 120449297272620 },
	Foot_R = { bone = "RightFoot", mesh = 129659609820011 },
} :: { [string]: { bone: string, mesh: number } }

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(Mech3Meshes.FolderName)
end

function Mech3Meshes.template(name: string): MeshPart?
	local f = folder()
	local t = f and f:FindFirstChild(name)
	if not (t and t:IsA("MeshPart")) then
		return nil
	end
	if t:GetAttribute(Mech3Meshes.AssetAttr) ~= Mech3Meshes.MechAsset then
		local e = Mech3Meshes.Parts[name]
		-- v1 templates loaded before the attribute existed: recognised by their MeshId
		local legacy = Mech3Meshes.MechAsset == Mech3Config.AssetV1 and e and string.find(t.MeshId, string.format("%.0f", e.mesh), 1, true)
		if not legacy then
			return nil -- stale (an older upload)
		end
	end
	return t
end

-- A template's CFrame in model space (front -Z, +X = right, feet on y = 0).
function Mech3Meshes.modelCFrame(t: BasePart): CFrame
	return Mech3Meshes.ImportRotation * t.CFrame
end

function Mech3Meshes.missing(): { string }
	local out = {}
	for name in Mech3Meshes.Parts do
		if not Mech3Meshes.template(name) then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function Mech3Meshes.available(): boolean
	return #Mech3Meshes.missing() == 0
end

-- Loads the asset if any template is missing (yields). Returns the names
-- that still failed. Server / edit mode only.
function Mech3Meshes.ensure(): { string }
	local missing = Mech3Meshes.missing()
	if #missing == 0 then
		return missing
	end
	local f = folder()
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = Mech3Meshes.FolderName
		nf.Parent = ReplicatedStorage
		f = nf
	end
	local want: { [string]: boolean } = {}
	for _, n in missing do
		want[n] = true
	end
	local ok, res = pcall(InsertService.LoadAsset, InsertService, Mech3Meshes.MechAsset)
	if ok and res then
		for _, mp in res:GetDescendants() do
			if mp:IsA("MeshPart") and want[mp.Name] then
				for _, old in (f :: Instance):GetChildren() do
					if old.Name == mp.Name then
						old:Destroy()
					end
				end
				local cf = mp.CFrame -- keep the loaded (asset frame) placement
				mp.Anchored = true
				mp.CanCollide = false
				mp.CanTouch = false
				mp.CanQuery = false
				mp:SetAttribute(Mech3Meshes.AssetAttr, Mech3Meshes.MechAsset)
				mp.Parent = f
				mp.CFrame = cf
			end
		end
		res:Destroy()
	else
		warn("[Mech3Meshes] LoadAsset " .. tostring(Mech3Meshes.MechAsset) .. " failed: " .. tostring(res))
	end
	return Mech3Meshes.missing()
end

return Mech3Meshes
