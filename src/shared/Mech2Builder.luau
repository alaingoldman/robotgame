--!strict
-- Builds the PLD-02 "Paladin" (type id "Mech2", Mech2Config) from the
-- imported meshes (Mech2Meshes): an invisible bone per rigid segment joined
-- by Motor6Ds at the pivots from assets/meshes/mech2/*/meta.json, every
-- coloured MeshPart welded to its bone, plus what every mech type needs:
--
--   * HumanoidRootPart (invisible collision box on the hip line) + Motor6D
--     "Root" -> Pelvis, Humanoid, model-level "PilotSeat", "MechType".
--   * Armor_Helmet (head + canopy) / Armor_Chest (torso, pauldrons, arms) /
--     Armor_Legs folders (MechPattern, inventory slots).
--   * Motors: Root, Waist, Spine, Neck, CanopyHinge, Right|Left Shoulder /
--     Elbow / Wrist, Right|Left Hip / Knee / Ankle, Right|Left PauldronJoint
--     (the pauldron follows part of the arm swing, Mech2Animator), Right|Left
--     TassetJoint (the skirt plates follow part of the thigh swing, Mech2Pose).
--   * Head cockpit: the pilot seat sits inside the head; the gold crown is a
--     canopy on "CanopyHinge" that lifts open while parked (Mech2Pose).
--   * Battery pack on the back between the gold fins: casing, four charge
--     cells ("Mech2Cell" 1..4) and a terminal ("BatteryTerminal") for the
--     charging arc (Mech2Dock).
--
-- Model space: the ground point between the feet is the origin, facing -Z.
-- Torso / leg / arm source frames have their origin on the hip-joint line,
-- HipLine (8.46 studs) above the soles.

local RunService = game:GetService("RunService")

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)
local Mech2Config = require(script.Parent.Mech2Config)
local Mech2Meshes = require(script.Parent.Mech2Meshes)

local Mech2Builder = {}

Mech2Builder.TypeId = Mech2Config.TypeId
Mech2Builder.DisplayName = Mech2Config.DisplayName
Mech2Builder.RootHeight = Mech2Config.RootHeight
Mech2Builder.HipHeight = Mech2Config.RootHeight - Mech2Config.RootSize.Y / 2

local ROLE_ATTR = "Mech2Role"
local H = Mech2Config.HipLine

-- Pivots (studs). Torso frame: hip-line centre; head frame: neck base; arm
-- frame: shoulder ball centre, hanging; leg frame: hip-joint centre (R).
local WAIST = Vector3.new(0, 5.2632, 0)
local SPINE = Vector3.new(0, 7.3032, 0.0816)
local NECK = Vector3.new(0, 10.5672, 0.0816)
local SHOULDER = Vector3.new(3.5, 9.2, 0.1632)
local HIP = Vector3.new(1.9511, 0, 0)
local KNEE = Vector3.new(0.2856, -4.4064, 0.1632)
local ANKLE = Vector3.new(0.5059, -7.548, 0.1632)
local ELBOW = Vector3.new(0, -3.13, 0)
local WRIST = Vector3.new(0.3, -6.93, 0)
local TASSET = Vector3.new(1.9511, 4.5696, 0) -- torso meta.json RightTasset
-- the arms hang rolled out by the fitted rest roll (torso README, fit_arms.py)
local ARM_ROLL = math.rad(17)

local SLOT_OF_BONE: { [string]: string } = {
	Head = "Helmet",
	Canopy = "Helmet",
	RightThigh = "Legs",
	RightShin = "Legs",
	RightFoot = "Legs",
	LeftThigh = "Legs",
	LeftShin = "Legs",
	LeftFoot = "Legs",
	RightTasset = "Legs",
	LeftTasset = "Legs",
}

-- ===== helpers ==============================================================

local function paint(part: BasePart, role: string, palette: Mech2Config.Palette)
	if role == "glow" then
		part.Color = palette.glow
		part.Material = Enum.Material.Neon
		part:SetAttribute("LitColor", palette.glow)
	else
		-- flat SmoothPlastic like the reference sheet (Metal turned the grey
		-- joints near-black and the gold brown in shade)
		part.Color = (palette :: any)[role] or palette.dark
		part.Material = Enum.Material.SmoothPlastic
	end
end

local function weld(bone: BasePart, part: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = bone
	w.Part1 = part
	w.C0 = c0
	w.Parent = part
end

local function newBone(parent: Instance, name: string, cf: CFrame): BasePart
	local b = Instance.new("Part")
	b.Name = name
	b.Size = Vector3.new(0.3, 0.3, 0.3)
	b.CFrame = cf
	b.Transparency = 1
	b.CanCollide = false
	b.CanTouch = false
	b.CanQuery = false
	b.Massless = true
	b.Parent = parent
	return b
end

local function motor(name: string, part0: BasePart, part1: BasePart): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	m.C1 = CFrame.identity
	m.Parent = part0
	return m
end

-- A plain armour part welded to `bone` at `local` (bone frame).
local function addPart(parent: Instance, bone: BasePart, name: string, size: Vector3, loc: CFrame, role: string, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = bone.CFrame * loc
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute(ROLE_ATTR, role)
	p.Parent = parent
	weld(bone, p, loc)
	return p
end

-- ===== battery ==============================================================
-- On the back plate between the gold fins (chest frame = torso frame minus
-- SPINE). Back profile of the uploaded chest meshes (OBJ ray casts along Z):
-- the white spine ridge peaks at z 2.16 for |x| < 0.8, the channel beside it
-- is at z 1.75 out to |x| 1.2, the gold fins start at |x| ~1.4 (z 2.4..2.9).
local function buildBattery(folder: Instance, chest: BasePart)
	local bat = Instance.new("Folder")
	bat.Name = "Battery"
	bat.Parent = folder
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(Vector3.new(x, y, z) - SPINE)
	end
	local w, h, d = 2.3, 2.1, 0.72
	local cy, z0 = 9.15, 2.06 -- centre height; inner face sits just into the spine ridge
	local zc = z0 + d / 2
	addPart(bat, chest, "BatteryCase", Vector3.new(w, h, d), at(0, cy, zc), "dark")
	addPart(bat, chest, "BatteryFace", Vector3.new(w - 0.3, h - 0.3, 0.1), at(0, cy, z0 + d + 0.04), "joint")
	local cellH = (h - 0.75) / 4
	for i = 1, 4 do
		local y = cy - (h - 0.75) / 2 + (i - 0.5) * cellH
		local cell = addPart(bat, chest, "BatteryCell" .. i, Vector3.new(w - 0.8, cellH - 0.1, 0.08), at(0, y, z0 + d + 0.12), "glow")
		cell:SetAttribute("Mech2Cell", i)
	end
	for _, s in { 1, -1 } do
		addPart(bat, chest, "BatteryClamp", Vector3.new(0.18, h + 0.1, d + 0.12), at(s * (w / 2 - 0.02), cy, zc + 0.02), "hi")
	end
	-- terminal on top: gold post + ball, the arc lands on the ball
	addPart(bat, chest, "BatteryCap", Vector3.new(w - 0.5, 0.16, d - 0.12), at(0, cy + h / 2 + 0.07, zc), "hi")
	addPart(bat, chest, "BatteryPost", Vector3.new(0.35, 0.22, 0.22), at(0, cy + h / 2 + 0.3, zc + 0.05) * CFrame.Angles(0, 0, math.pi / 2), "joint", Enum.PartType.Cylinder)
	local ball = addPart(bat, chest, "BatteryTerminal", Vector3.new(0.34, 0.34, 0.34), at(0, cy + h / 2 + 0.55, zc + 0.05), "hi", Enum.PartType.Ball)
	local a = Instance.new("Attachment")
	a.Name = "BatteryTerminal"
	a.Parent = ball
end

-- ===== rig ==================================================================

-- Builds the full mech (geometry included); colours default to the
-- reference palette. Needs the mesh templates (loaded on demand where
-- InsertService works: server / edit mode).
function Mech2Builder.buildRig(name: string): Model
	if not Mech2Meshes.available() and RunService:IsServer() then
		local ok, err = pcall(Mech2Meshes.ensure)
		if not ok then
			warn("[Mech2Builder] loading mesh templates failed: " .. tostring(err))
		end
	end
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", Mech2Builder.TypeId)

	local folders: { [string]: Folder } = {}
	for _, slot in MechConfig.Slots do
		local f = Instance.new("Folder")
		f.Name = "Armor_" .. slot
		f.Parent = model
		folders[slot] = f
	end
	local function folderOf(boneName: string): Folder
		return folders[SLOT_OF_BONE[boneName] or "Chest"]
	end

	local hip = Vector3.new(0, H, 0)
	local bones: { [string]: BasePart } = {}
	local function bone(n: string, cf: CFrame): BasePart
		local b = newBone(folderOf(n), n, cf)
		bones[n] = b
		return b
	end

	-- root collision box + torso / head
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Mech2Config.RootSize
	root.CFrame = CFrame.new(0, Mech2Config.RootHeight, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = MechBuilder.RootGroup
	root.RootPriority = 100 -- stays the assembly root with a pilot welded in
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local pelvis = bone("Pelvis", CFrame.new(hip))
	local abdomen = bone("Abdomen", CFrame.new(hip + WAIST))
	local chest = bone("Chest", CFrame.new(hip + SPINE))
	local head = bone("Head", CFrame.new(hip + NECK))
	local canopy = bone("Canopy", head.CFrame * CFrame.new(Mech2Config.CanopyHinge))
	motor("Root", root, pelvis)
	motor("Waist", pelvis, abdomen)
	motor("Spine", abdomen, chest)
	motor("Neck", chest, head)
	motor("CanopyHinge", head, canopy)

	for _, side in { "Right", "Left" } do
		local sx = if side == "Right" then 1 else -1
		local mirror = Vector3.new(sx, 1, 1)
		-- pauldron (on the chest, follows the shoulder a little) and the arm
		local socket = hip + SHOULDER * mirror
		local paul = bone(side .. "Pauldron", CFrame.new(socket))
		motor(side .. "PauldronJoint", chest, paul)
		local armCF = CFrame.new(socket) * CFrame.Angles(0, 0, sx * ARM_ROLL)
		local upper = bone(side .. "UpperArm", armCF)
		local lower = bone(side .. "LowerArm", armCF * CFrame.new(ELBOW))
		local hand = bone(side .. "Hand", armCF * CFrame.new(WRIST * mirror))
		motor(side .. "Shoulder", chest, upper)
		motor(side .. "Elbow", upper, lower)
		motor(side .. "Wrist", lower, hand)
		-- TASSETS: the skirt plates over this hip swing with the thigh (Mech2Pose.apply)
		local tasset = bone(side .. "Tasset", CFrame.new(hip + TASSET * mirror))
		motor(side .. "TassetJoint", pelvis, tasset)
		-- leg
		local hipPos = hip + HIP * mirror
		local thigh = bone(side .. "Thigh", CFrame.new(hipPos))
		local shin = bone(side .. "Shin", CFrame.new(hipPos + KNEE * mirror))
		local foot = bone(side .. "Foot", CFrame.new(hipPos + ANKLE * mirror))
		motor(side .. "Hip", pelvis, thigh)
		motor(side .. "Knee", thigh, shin)
		motor(side .. "Ankle", shin, foot)
	end

	-- the mesh skins, crosshatched (Mech2Meshes.crosshatch) except the small
	-- grey joints / dark pads and the hands, where the lattice is just noise
	local hatch = Mech2Meshes.crosshatch()
	local missing = 0
	for meshName, e in Mech2Meshes.Meshes do
		local t = Mech2Meshes.template(meshName)
		local b = bones[e.bone]
		if not (t and b) then
			missing += 1
			continue
		end
		local mp = t:Clone()
		mp.Name = meshName
		mp.Size = e.size
		local place = CFrame.new(e.offset) * Mech2Meshes.ImportRotation
		mp.CFrame = b.CFrame * place
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanTouch = false
		mp.CanQuery = false
		mp.Massless = true
		mp.CastShadow = true
		mp.TextureID = ""
		mp:SetAttribute(ROLE_ATTR, e.role)
		for _, c in mp:GetChildren() do
			c:Destroy()
		end
		if hatch and (e.role == "main" or e.role == "hi" or e.role == "accent") and not string.find(e.bone, "Hand$") then
			local sa = hatch:Clone()
			sa.AlphaMode = Enum.AlphaMode.Overlay
			sa.Parent = mp
		end
		weld(b, mp, place)
		mp.Parent = folderOf(e.bone)
	end
	if missing > 0 then
		warn(string.format("[Mech2Builder] %d of the mech2 meshes have no template (ReplicatedStorage.%s): built without them", missing, Mech2Meshes.FolderName))
	end

	-- head cockpit: the seat sits inside the head shell (the pilot is hidden
	-- while seated, Mech2Animator); a soft light under the canopy
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(1, 0.2, 1)
	seat.CFrame = head.CFrame * CFrame.new(0, 1.0, 0.3)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.Parent = model
	weld(head, seat, CFrame.new(0, 1.0, 0.3))
	local glow = addPart(folders.Helmet, head, "CockpitGlow", Vector3.new(0.9, 0.08, 0.9), CFrame.new(0, 2.05, -0.6), "glow")
	glow.Transparency = 1 -- just carries the light
	local light = Instance.new("PointLight")
	light.Name = "CockpitLight"
	light.Range = 5
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = glow

	buildBattery(folders.Chest, chest)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.Massless = true
			d.CanTouch = false
			d.CanCollide = false
			if not d:IsA("Seat") then
				d.CollisionGroup = MechBuilder.ArmorGroup
			end
		end
	end
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = Mech2Builder.HipHeight
	humanoid.WalkSpeed = MechConfig.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.CameraOffset = Mech2Config.CameraOffset
	humanoid.Parent = model
	return model
end

-- Recolours one slot with a variant's palette (MechConfig variant id ->
-- Mech2Config palette).
function Mech2Builder.applySlot(model: Model, slot: string, variantId: string)
	local folder = model:FindFirstChild("Armor_" .. slot)
	if not folder then
		return
	end
	local palette = Mech2Config.getVariant(variantId).palette
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute(ROLE_ATTR)
			if typeof(role) == "string" then
				paint(d, role, palette)
			end
		elseif d:IsA("PointLight") then
			d.Color = palette.glow
		end
	end
	model:SetAttribute(slot, variantId)
end

function Mech2Builder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = Mech2Builder.buildRig(name)
	for _, slot in MechConfig.Slots do
		Mech2Builder.applySlot(model, slot, loadout[slot] or Mech2Config.DefaultVariant)
	end
	return model
end

-- Key points around a parked mech whose root is at `rootCF`.
export type OffPoints = { prompt: Vector3, exit: Vector3, ground: number, forward: Vector3 }
function Mech2Builder.offPoints(rootCF: CFrame): OffPoints
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local ground = rootCF.Y - Mech2Builder.RootHeight
	local base = Vector3.new(rootCF.X, ground, rootCF.Z)
	return {
		prompt = base + forward * 6.5,
		exit = base + forward * 7.5,
		ground = ground,
		forward = forward,
	}
end

return Mech2Builder
