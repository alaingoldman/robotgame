--!strict
-- EXO-1 showcase: three statue avatars wearing the worn exo (ExoBuilder),
-- standing on plinths in a row south of the spawn, facing it, so players can
-- walk round them. Workspace.ExoShowcase is built once in Studio edit mode
-- and saved with the place (Rojo leaves unmanaged Workspace children alone);
-- ensure() rebuilds it at runtime only if the saved folder is missing.
--
-- Statues: R15 dummies from official Roblox bundles (239 "Woman", 337 "City
-- Life Woman") and a shorter default body. HumanoidRootPart anchored, no
-- scripts / AI, name and health hidden; an invisible box per statue makes
-- them solid (the Humanoid would turn its own limb collisions off). Not
-- player characters, so ExoService never touches them; the exo's lights and
-- pistons carry ExoBuilder's tags, so ExoAnimator animates them on clients.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExoShowcase = {}

ExoShowcase.FolderName = "ExoShowcase"
ExoShowcase.Tag = "ExoStatue"

local ROW = CFrame.new(0, 0, 20) -- row centre on the ground; statues face -Z (the spawn)
local SPACING = 6
local PLINTH = Vector3.new(3.4, 0.6, 3.4)

type Spec = { name: string, label: string, bundle: number?, skin: Color3, scales: { [string]: number } }
local SPECS: { Spec } = {
	{
		name = "Woman",
		label = "Woman",
		bundle = 239,
		skin = Color3.fromRGB(234, 184, 146),
		scales = { BodyTypeScale = 0, ProportionScale = 0, HeightScale = 0.95, WidthScale = 0.85, DepthScale = 0.9, HeadScale = 1 },
	},
	{
		name = "CityLifeWoman",
		label = "City Life Woman",
		bundle = 337,
		skin = Color3.fromRGB(124, 92, 70),
		scales = { BodyTypeScale = 0.4, ProportionScale = 0.7, HeightScale = 0.95, WidthScale = 0.85, DepthScale = 0.9, HeadScale = 1 },
	},
	{
		name = "Short",
		label = "Short",
		bundle = nil,
		skin = Color3.fromRGB(204, 142, 105),
		scales = { BodyTypeScale = 0, ProportionScale = 0, HeightScale = 0.85, WidthScale = 0.85, DepthScale = 0.9, HeadScale = 0.95 },
	},
}

-- HumanoidDescription fields for a bundle's body parts / face / hair.
local FIELD = { [27] = "Torso", [28] = "RightArm", [29] = "LeftArm", [30] = "LeftLeg", [31] = "RightLeg", [17] = "Head", [18] = "Face", [41] = "HairAccessory" }

local function applyBundle(desc: HumanoidDescription, bundleId: number)
	local ok, details = pcall(AssetService.GetBundleDetailsAsync, AssetService, bundleId)
	if not ok or not details then
		warn("ExoShowcase: bundle", bundleId, details)
		return
	end
	for _, item in details.Items do
		if item.Type == "Asset" then
			local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.Id)
			local field = okInfo and info and FIELD[info.AssetTypeId]
			if field then
				(desc :: any)[field] = item.Id
			end
		end
	end
end

local function plinth(parent: Instance, at: CFrame): BasePart
	local base = Instance.new("Part")
	base.Name = "Plinth"
	base.Anchored = true
	base.Size = PLINTH
	base.CFrame = at * CFrame.new(0, PLINTH.Y / 2, 0)
	base.Color = Color3.fromRGB(52, 54, 58)
	base.Material = Enum.Material.DiamondPlate
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = parent
	-- green edge light on the front (pulses with the exo lights)
	local edge = Instance.new("Part")
	edge.Name = "PlinthLight"
	edge.Anchored = true
	edge.CanCollide = false
	edge.CanQuery = false
	edge.Size = Vector3.new(PLINTH.X - 0.4, 0.08, 0.08)
	edge.CFrame = at * CFrame.new(0, PLINTH.Y - 0.12, -PLINTH.Z / 2 - 0.02)
	edge.Color = Color3.fromRGB(70, 255, 120)
	edge.Material = Enum.Material.Neon
	CollectionService:AddTag(edge, "ExoLight")
	edge.Parent = base
	return base
end

local function label(base: BasePart, text: string, height: number)
	-- same look as the mech lineup signs (MechService), smaller
	local sign = Instance.new("BillboardGui")
	sign.Name = "Label"
	sign.Size = UDim2.fromScale(4.5, 0.55)
	sign.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	sign.MaxDistance = 60
	sign.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = string.upper(text) .. "  //  EXO-1"
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Parent = sign
	sign.Parent = base
end

-- Makes one statue on its plinth at `at` (ground CFrame, facing -Z).
local function statue(folder: Folder, exoBuilder: any, spec: Spec, at: CFrame)
	local desc = Instance.new("HumanoidDescription")
	if spec.bundle then
		applyBundle(desc, spec.bundle)
	end
	for k, v in spec.scales do
		(desc :: any)[k] = v
	end
	local c = spec.skin
	desc.HeadColor, desc.TorsoColor = c, c
	desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = c, c, c, c
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = spec.name
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- no Animate / Health scripts: it's a statue
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.PlatformStand = true
	root.Anchored = true
	root.CanCollide = false

	local base = plinth(folder, at)
	model.Parent = folder
	local top = at * CFrame.new(0, PLINTH.Y, 0)
	model:PivotTo(top * CFrame.new(0, hum.HipHeight + root.Size.Y / 2, 0))

	-- the exo, fitted to this body
	local rig = exoBuilder.readRig(model, hum)
	if rig then
		exoBuilder.buildWorn(model, rig)
	else
		warn("ExoShowcase: can't fit the exo on", spec.name)
	end

	-- solid like a statue: one invisible box round the body
	local cf, size = model:GetBoundingBox()
	local box = Instance.new("Part")
	box.Name = "StatueCollider"
	box.Anchored = true
	box.Transparency = 1
	box.CanQuery = false
	box.CanTouch = false
	box.Size = Vector3.new(math.min(size.X, 2.6), size.Y, math.min(size.Z, 1.6))
	box.CFrame = cf
	box.Parent = model

	label(base, spec.label, PLINTH.Y / 2 + size.Y + 0.9)
	model:SetAttribute("ExoStatue", true)
	CollectionService:AddTag(model, ExoShowcase.Tag)
end

-- Builds Workspace.ExoShowcase (replacing an old one). `exoBuilder` defaults
-- to ReplicatedStorage.Shared.ExoBuilder (pass a fresh copy from a plugin).
function ExoShowcase.build(exoBuilder: any?): Folder
	local builder = exoBuilder or require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ExoBuilder")) :: any
	local old = workspace:FindFirstChild(ExoShowcase.FolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ExoShowcase.FolderName
	folder.Parent = workspace
	for i, spec in SPECS do
		statue(folder, builder, spec, ROW * CFrame.new((i - 2) * SPACING, 0, 0))
	end
	return folder
end

-- Runtime: keep the saved showcase; build it only if the place has none.
function ExoShowcase.ensure()
	if workspace:FindFirstChild(ExoShowcase.FolderName) then
		return
	end
	task.spawn(ExoShowcase.build)
end

return ExoShowcase
