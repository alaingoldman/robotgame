local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
-- fresh copy of Shared so require() isn't served from a stale plugin cache
local src = RS:FindFirstChild("Shared")
local copy = src:Clone()
copy.Name = "SharedMeshExport_tmp"
copy.Parent = RS
local ok, res = pcall(function()
	local TitanBuilder = require(copy.TitanBuilder)
	local model = TitanBuilder.buildRig("MeshExportTmp")
	local out = { scale = TitanBuilder.Scale, groups = {}, bones = {} }
	local function bonesOf(names)
		for _, n in names do
			local b = model:FindFirstChild(n, true)
			if b then
				out.bones[n] = { b.CFrame:GetComponents() }
			end
		end
	end
	bonesOf({ "Chest", "Hatch", "Head", "Collar", "Pelvis", "HumanoidRootPart" })
	local function boneOf(p)
		for _, w in p:GetChildren() do
			if w:IsA("Weld") and w.Part1 == p and w.Part0 then return w.Part0 end
		end
		return nil
	end
	local function dump(group, folderName, names)
		local folder = model:FindFirstChild(folderName, true)
		local list = {}
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and names[p.Name] then
				local b = boneOf(p)
				table.insert(list, {
					name = p.Name, class = p.ClassName, bone = b and b.Name or "?",
					role = p:GetAttribute("TitanRole"),
					size = { p.Size.X, p.Size.Y, p.Size.Z },
					cf = { b.CFrame:ToObjectSpace(p.CFrame):GetComponents() },
				})
			end
		end
		out.groups[group] = list
	end
	dump("PadR", "RightPadArmor", { PadShell = true, PadStrap = true, PadLobe = true })
	dump("PadL", "LeftPadArmor", { PadShell = true, PadStrap = true, PadLobe = true })
	dump("Dome", "TorsoArmor", { ChestPlate = true, ChestCrescent = true, ChestLower = true, ChestSide = true })
	dump("Helmet", "HelmetArmor", { HelmetShell = true, HelmetCap = true })
	model:Destroy()
	return HttpService:JSONEncode(out)
end)
copy:Destroy()
if not ok then error(res) end
return res
