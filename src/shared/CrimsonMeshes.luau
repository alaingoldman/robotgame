--!strict
-- CRM-01 "Crimson" mesh templates. The owner uploaded the textured mech
-- (model asset 101342583030033: Model "Crimson_Mech", 17 MeshParts sharing
-- one baked TextureID) and the cleaver (123971673295763: one MeshPart
-- "Crimson_Blade"). Templates live in ReplicatedStorage.CrimsonMeshes, one
-- MeshPart per name, kept exactly where LoadAsset put them (the asset
-- frame): CrimsonMeshes.ensure() loads them when missing (edit mode via the
-- plugin, or the server at start-up), like Mech2Meshes.
--
-- Import rotation: Studio's importer turned the GLBs 180 deg about Y (in the
-- loaded asset the "_L" parts sit at +X and the front faces +Z; every part
-- has an identity rotation and its bounding-box centre as position). The
-- source frame (meta.json) is the model frame: front -Z, +X = the mech's
-- right. So a template's model-space CFrame is ImportRotation * its loaded
-- CFrame (checked: Hand_L loads at (6.55, 8.68, 0.22), its source bbox
-- centre is (-6.55, 8.68, -0.22)).

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrimsonMeshes = {}

CrimsonMeshes.FolderName = "CrimsonMeshes"
CrimsonMeshes.ImportRotation = CFrame.Angles(0, math.pi, 0)
CrimsonMeshes.MechAsset = 101342583030033
CrimsonMeshes.BladeAsset = 123971673295763
CrimsonMeshes.Blade = "Crimson_Blade"

-- part name -> bone (CrimsonBuilder) and its MeshId (a template only counts
-- while it holds this mesh)
CrimsonMeshes.Parts = {
	Head = { bone = "Head", mesh = 136299140890430 },
	Torso = { bone = "Torso", mesh = 132011765360777 },
	Pelvis = { bone = "Pelvis", mesh = 91866592082383 },
	ShoulderPad_L = { bone = "LeftPad", mesh = 72122461056071 },
	ShoulderPad_R = { bone = "RightPad", mesh = 126111589103686 },
	UpperArm_L = { bone = "LeftUpperArm", mesh = 139233203743829 },
	UpperArm_R = { bone = "RightUpperArm", mesh = 101352084985202 },
	Forearm_L = { bone = "LeftLowerArm", mesh = 98874447324004 },
	Forearm_R = { bone = "RightLowerArm", mesh = 95427654901850 },
	Hand_L = { bone = "LeftHand", mesh = 129602905113748 },
	Hand_R = { bone = "RightHand", mesh = 104275836613907 },
	Thigh_L = { bone = "LeftThigh", mesh = 110088583453377 },
	Thigh_R = { bone = "RightThigh", mesh = 74700366747857 },
	Shin_L = { bone = "LeftShin", mesh = 97226917896407 },
	Shin_R = { bone = "RightShin", mesh = 137738307865441 },
	Foot_L = { bone = "LeftFoot", mesh = 123843354294581 },
	Foot_R = { bone = "RightFoot", mesh = 70956026399455 },
} :: { [string]: { bone: string, mesh: number } }
CrimsonMeshes.BladeMesh = 138932707959119

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(CrimsonMeshes.FolderName)
end

local function meshOf(name: string): number?
	if name == CrimsonMeshes.Blade then
		return CrimsonMeshes.BladeMesh
	end
	local e = CrimsonMeshes.Parts[name]
	return e and e.mesh
end

function CrimsonMeshes.template(name: string): MeshPart?
	local f = folder()
	local t = f and f:FindFirstChild(name)
	if not (t and t:IsA("MeshPart")) then
		return nil
	end
	local id = meshOf(name)
	if id and not string.find(t.MeshId, string.format("%.0f", id), 1, true) then
		return nil -- stale (an older upload)
	end
	return t
end

-- A template's CFrame in model space (front -Z, +X = right, feet on y = 0).
function CrimsonMeshes.modelCFrame(t: BasePart): CFrame
	return CrimsonMeshes.ImportRotation * t.CFrame
end

function CrimsonMeshes.missing(): { string }
	local out = {}
	for name in CrimsonMeshes.Parts do
		if not CrimsonMeshes.template(name) then
			table.insert(out, name)
		end
	end
	if not CrimsonMeshes.template(CrimsonMeshes.Blade) then
		table.insert(out, CrimsonMeshes.Blade)
	end
	table.sort(out)
	return out
end

function CrimsonMeshes.available(): boolean
	return #CrimsonMeshes.missing() == 0
end

-- Loads the two assets if any template is missing (yields). Returns the
-- names that still failed. Server / edit mode only.
function CrimsonMeshes.ensure(): { string }
	local missing = CrimsonMeshes.missing()
	if #missing == 0 then
		return missing
	end
	local f = folder()
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = CrimsonMeshes.FolderName
		nf.Parent = ReplicatedStorage
		f = nf
	end
	local want: { [string]: boolean } = {}
	for _, n in missing do
		want[n] = true
	end
	for _, asset in { CrimsonMeshes.MechAsset, CrimsonMeshes.BladeAsset } do
		local ok, res = pcall(InsertService.LoadAsset, InsertService, asset)
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
					mp.Parent = f
					mp.CFrame = cf
				end
			end
			res:Destroy()
		else
			warn("[CrimsonMeshes] LoadAsset " .. tostring(asset) .. " failed: " .. tostring(res))
		end
	end
	return CrimsonMeshes.missing()
end

return CrimsonMeshes
