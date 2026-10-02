--!strict
-- Builds the SRF-03 "Seraph" (type id "Mech3", Mech3Config) from the owner's
-- textured meshes (Mech3Meshes): an invisible bone per part joined by
-- Motor6Ds at the meta.json pivots, every MeshPart (texture kept) welded to
-- its bone, plus what every mech type needs:
--
--   * HumanoidRootPart (invisible collision box on the hip line) + Motor6D
--     "Root" -> Pelvis, Humanoid, model-level "PilotSeat", "MechType".
--   * Armor_Helmet (head) / Armor_Chest (torso, wings, pads, arms) / Armor_Legs.
--   * Motors: Root, Waist, Neck, VisorLift (the helmet cockpit), Right|Left
--     WingRoot, PadJoint, Shoulder / Elbow / Wrist, Hip / Knee / Ankle.
--   * Helmet cockpit: the pilot sits in the neck socket inside the collar
--     ring (a lined tub with a seat, blue screens and a lamp). The helmet
--     ("Helmet" bone on "VisorLift") flips up and back on a rear hinge while
--     parked, and comes down over the pilot when boarding. The seated pilot is
--     shown as a scaled stand-in (Mech3Animator); the real avatar is hidden.
--   * Battery: four charge cells ("Mech3Cell" 1..4) in a slot on the back of
--     the backpack, a terminal ("BatteryTerminal") on a short arm above it for
--     the dock arc.
--   * Eyes ("Mech3Eye") on the visor and chest slits ("Mech3Core") that
--     power up with the pilot in (the baked texture's glow is faint).

local RunService = game:GetService("RunService")

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)
local Mech3Config = require(script.Parent.Mech3Config)
local Mech3Meshes = require(script.Parent.Mech3Meshes)

local Mech3Builder = {}

Mech3Builder.TypeId = Mech3Config.TypeId
Mech3Builder.DisplayName = Mech3Config.DisplayName
Mech3Builder.RootHeight = Mech3Config.RootHeight
Mech3Builder.HipHeight = Mech3Config.RootHeight - Mech3Config.RootSize.Y / 2

local ROLE_ATTR = "Mech3Role"
local PV = Mech3Config.Pivots
local HM = Mech3Config.Helmet

local SLOT_OF_BONE: { [string]: string } = {
	Head = "Helmet",
	Helmet = "Helmet",
	RightThigh = "Legs",
	RightShin = "Legs",
	RightFoot = "Legs",
	LeftThigh = "Legs",
	LeftShin = "Legs",
	LeftFoot = "Legs",
}

-- ===== helpers ==============================================================

local function paint(part: BasePart, role: string, palette: Mech3Config.Palette)
	if role == "glow" then
		part.Color = palette.glow
		part.Material = Enum.Material.Neon
		part:SetAttribute("LitColor", palette.glow)
	elseif role == "main" then
		part.Color = palette.main
		part.Material = Enum.Material.SmoothPlastic
	else
		part.Color = (palette :: any)[role] or palette.dark
		part.Material = Enum.Material.Metal
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

-- A plain part welded to `bone`, placed at model-space `cf`.
local function addPart(parent: Instance, bone: BasePart, name: string, size: Vector3, cf: CFrame, role: string, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute(ROLE_ATTR, role)
	p.Parent = parent
	weld(bone, p, bone.CFrame:ToObjectSpace(cf))
	return p
end


-- ===== neck-socket cockpit ==================================================
-- The torso mesh is open at the neck: inside the collar ring (|x| < ~0.6,
-- z -0.45 .. 0.95) it is hollow down to the waist. A lined tub closes it.
local TUB = { floor = 16.55, top = 17.4, halfW = 0.66, front = -0.5, back = 0.98 }
Mech3Builder.Tub = TUB

local function buildCockpit(model: Model, folder: Instance, torso: BasePart)
	local f = Instance.new("Folder")
	f.Name = "Cockpit"
	f.Parent = folder
	local zc, d = (TUB.front + TUB.back) / 2, TUB.back - TUB.front
	local yc, h = (TUB.floor + TUB.top) / 2, TUB.top - TUB.floor
	local t = 0.08
	addPart(f, torso, "TubFloor", Vector3.new(TUB.halfW * 2, 0.12, d), CFrame.new(0, TUB.floor - 0.06, zc), "dark")
	addPart(f, torso, "TubFront", Vector3.new(TUB.halfW * 2, h, t), CFrame.new(0, yc, TUB.front + t / 2), "dark")
	addPart(f, torso, "TubBack", Vector3.new(TUB.halfW * 2, h, t), CFrame.new(0, yc, TUB.back - t / 2), "dark")
	for _, sx in { 1, -1 } do
		addPart(f, torso, "TubSide", Vector3.new(t, h, d), CFrame.new(sx * (TUB.halfW - t / 2), yc, zc), "dark")
		-- small blue screens on the side walls, angled toward the seat
		local s = addPart(f, torso, "TubScreen", Vector3.new(0.04, 0.22, 0.32), CFrame.new(sx * (TUB.halfW - t - 0.03), TUB.floor + 0.55, TUB.front + 0.35) * CFrame.Angles(0, sx * 0.35, 0), "glow")
		s:SetAttribute("Mech3Core", true)
	end
	-- seat: pan, back, a steel-blue headrest
	local seatY, seatZ = HM.SeatY, HM.SeatZ
	addPart(f, torso, "SeatPan", Vector3.new(0.62, 0.08, 0.5), CFrame.new(0, seatY, seatZ), "trim")
	addPart(f, torso, "SeatBack", Vector3.new(0.62, 0.62, 0.08), CFrame.new(0, seatY + 0.34, seatZ + 0.3) * CFrame.Angles(-0.12, 0, 0), "main")
	addPart(f, torso, "Headrest", Vector3.new(0.34, 0.18, 0.08), CFrame.new(0, seatY + 0.74, seatZ + 0.36) * CFrame.Angles(-0.12, 0, 0), "trim")
	-- control sticks either side
	for _, sx in { 1, -1 } do
		addPart(f, torso, "Stick", Vector3.new(0.05, 0.3, 0.05), CFrame.new(sx * 0.33, seatY + 0.1, seatZ - 0.3), "trim")
	end
	local lamp = addPart(f, torso, "TubLamp", Vector3.new(0.5, 0.04, 0.04), CFrame.new(0, TUB.top - 0.1, TUB.front + 0.06), "glow")
	lamp:SetAttribute("Mech3Core", true)
	local light = Instance.new("PointLight")
	light.Name = "CockpitLight"
	light.Range = 4
	light.Brightness = 1
	light.Color = Color3.fromRGB(190, 225, 255)
	light.Shadows = true
	light.Parent = lamp
	-- the real seat (invisible); the avatar on it is hidden and shown scaled
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(0.6, 0.1, 0.5)
	local seatCF = CFrame.new(0, seatY, seatZ) -- faces -Z, like the mech
	seat.CFrame = seatCF
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.Parent = model
	weld(torso, seat, torso.CFrame:ToObjectSpace(seatCF))
end

-- The helmet hinge: two knuckles on the collar's back rim (torso) and a
-- strap from each into the helmet's base (helmet).
local function buildHinge(folder: Instance, torso: BasePart, helmet: BasePart)
	local h = HM.Hinge
	for _, sx in { 1, -1 } do
		local x = sx * 0.55
		addPart(folder, torso, "HingeKnuckle", Vector3.new(0.3, 0.34, 0.34), CFrame.new(x, h.Y, h.Z), "dark", Enum.PartType.Cylinder)
		addPart(folder, torso, "HingeCap", Vector3.new(0.06, 0.4, 0.4), CFrame.new(x + sx * 0.18, h.Y, h.Z), "trim", Enum.PartType.Cylinder)
		addPart(folder, helmet, "HingeStrap", Vector3.new(0.2, 0.55, 0.12), CFrame.new(x - sx * 0.25, h.Y + 0.25, h.Z - 0.05) * CFrame.Angles(-0.2, 0, 0), "trim")
	end
end

-- The battery: a dark slot with four cells on the back of the backpack
-- (back face z ~1.9 - 2.1 at x 0, y 15 - 17) and a terminal ball on a short
-- arm out of the backpack above it.
local function buildBattery(folder: Instance, torso: BasePart)
	local f = Instance.new("Folder")
	f.Name = "Battery"
	f.Parent = folder
	local z = 2.16
	local cy, cH = 16.05, 1.5
	addPart(f, torso, "BatterySlot", Vector3.new(0.9, cH + 0.26, 0.14), CFrame.new(0, cy, z), "dark")
	addPart(f, torso, "BatteryFrame", Vector3.new(1.02, 0.1, 0.18), CFrame.new(0, cy + cH / 2 + 0.16, z), "trim")
	addPart(f, torso, "BatteryFrame", Vector3.new(1.02, 0.1, 0.18), CFrame.new(0, cy - cH / 2 - 0.16, z), "trim")
	local cellH = cH / 4
	for i = 1, 4 do
		local y = cy - cH / 2 + (i - 0.5) * cellH
		local cell = addPart(f, torso, "BatteryCell" .. i, Vector3.new(0.66, cellH - 0.09, 0.05), CFrame.new(0, y, z + 0.08), "glow")
		cell:SetAttribute("Mech3Cell", i)
	end
	-- terminal: a short arm straight back out of the backpack above the slot
	-- (clear of the helmet when it tips back open)
	local tx, ty = 0.55, 17.8
	addPart(f, torso, "BatteryMastBase", Vector3.new(0.4, 0.4, 0.12), CFrame.new(tx, ty, 1.9), "dark")
	addPart(f, torso, "BatteryPost", Vector3.new(0.6, 0.18, 0.18), CFrame.new(tx, ty, 2.2) * CFrame.Angles(0, math.pi / 2, 0), "trim", Enum.PartType.Cylinder)
	local ball = addPart(f, torso, "BatteryTerminal", Vector3.new(0.34, 0.34, 0.34), CFrame.new(tx, ty, 2.58), "trim", Enum.PartType.Ball)
	local a = Instance.new("Attachment")
	a.Name = "BatteryTerminal"
	a.Parent = ball
end

-- ===== rig ==================================================================

function Mech3Builder.buildRig(name: string): Model
	if not Mech3Meshes.available() and (RunService:IsServer() or not RunService:IsRunning()) then
		local ok, err = pcall(Mech3Meshes.ensure)
		if not ok then
			warn("[Mech3Builder] loading mesh templates failed: " .. tostring(err))
		end
	end
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", Mech3Builder.TypeId)

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

	local bones: { [string]: BasePart } = {}
	local function bone(n: string, pos: Vector3): BasePart
		local b = newBone(folderOf(n), n, CFrame.new(pos))
		bones[n] = b
		return b
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Mech3Config.RootSize
	root.CFrame = CFrame.new(0, Mech3Config.RootHeight, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = MechBuilder.RootGroup
	root.RootPriority = 100
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local pelvis = bone("Pelvis", Vector3.new(0, Mech3Config.HipLine, 0))
	local torso = bone("Torso", PV.Waist)
	local head = bone("Head", PV.Neck)
	local helmet = bone("Helmet", HM.Hinge)
	motor("Root", root, pelvis)
	motor("Waist", pelvis, torso)
	motor("Neck", torso, head)
	motor("VisorLift", head, helmet)
	for _, side in { "Right", "Left" } do
		local wing = bone(side .. "Wing", PV.Wing[side])
		local pad = bone(side .. "Pad", PV.Pad[side])
		local upper = bone(side .. "UpperArm", PV.Shoulder[side])
		local lower = bone(side .. "LowerArm", PV.Elbow[side])
		local hand = bone(side .. "Hand", PV.Wrist[side])
		motor(side .. "WingRoot", torso, wing)
		motor(side .. "PadJoint", torso, pad)
		motor(side .. "Shoulder", torso, upper)
		motor(side .. "Elbow", upper, lower)
		motor(side .. "Wrist", lower, hand)
		local thigh = bone(side .. "Thigh", PV.Hip[side])
		local shin = bone(side .. "Shin", PV.Knee[side])
		local foot = bone(side .. "Foot", PV.Ankle[side])
		motor(side .. "Hip", pelvis, thigh)
		motor(side .. "Knee", thigh, shin)
		motor(side .. "Ankle", shin, foot)
	end

	-- the textured meshes, kept as they are (TextureID, no overlay)
	local missing = 0
	for partName, e in Mech3Meshes.Parts do
		local t = Mech3Meshes.template(partName)
		local b = bones[e.bone]
		if not (t and b) then
			missing += 1
			continue
		end
		local mp = t:Clone()
		mp.Name = partName
		mp.CFrame = Mech3Meshes.modelCFrame(t)
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanTouch = false
		mp.CanQuery = false
		mp.Massless = true
		mp.CastShadow = true
		for _, c in mp:GetChildren() do
			if not c:IsA("SurfaceAppearance") then -- v2: the metal PBR material stays
				c:Destroy()
			end
		end
		weld(b, mp, b.CFrame:ToObjectSpace(mp.CFrame))
		mp.Parent = folderOf(e.bone)
	end
	if missing > 0 then
		warn(string.format("[Mech3Builder] %d of the Mech3 meshes have no template (ReplicatedStorage.%s): built without them", missing, Mech3Meshes.FolderName))
	end

	-- eyes: slanted slits on the pointed visor (ray casts: the visor front is
	-- at z -1.92 for x 0.25 and -1.41 for x 0.65 at y 18.8, a 52 deg V)
	for _, sx in { 1, -1 } do
		local eye = addPart(folders.Helmet, helmet, "Eye", Vector3.new(0.4, 0.09, 0.08), CFrame.new(sx * 0.44, 18.9, -1.7) * CFrame.Angles(0, -sx * 0.9, 0) * CFrame.Angles(0, 0, sx * 0.22), "glow")
		eye:SetAttribute("Mech3Eye", true)
	end
	-- chest slits, like the sheet (the chest at y 15.45: z -1.75 at x 1.3, -1.44 at x 1.5)
	for _, sx in { 1, -1 } do
		local slit = addPart(folders.Chest, torso, "ChestSlit", Vector3.new(0.42, 0.1, 0.06), CFrame.new(sx * 1.36, 15.45, -1.68) * CFrame.Angles(0, -sx * 0.8, 0) * CFrame.Angles(0, 0, sx * 0.12), "glow")
		slit:SetAttribute("Mech3Core", true)
	end

	-- wing mounts: a charcoal bracket out of the backpack's flank to each wing
	-- root (behind the shoulder pad) and a hinge drum there, so the wings
	-- visibly hang off the back like the sheet's
	for _, side in { "Right", "Left" } do
		local sx = if side == "Right" then 1 else -1
		local root = PV.Wing[side]
		local x0, x1 = 1.45, math.abs(root.X) + 0.05
		local z = root.Z + 0.3
		addPart(folders.Chest, torso, "WingBracket", Vector3.new(x1 - x0, 0.42, 0.5), CFrame.new(sx * (x0 + x1) / 2, root.Y, z), "dark")
		addPart(folders.Chest, torso, "WingBracketCap", Vector3.new(x1 - x0 - 0.3, 0.12, 0.3), CFrame.new(sx * (x0 + x1) / 2, root.Y + 0.25, z), "trim")
		addPart(folders.Chest, torso, "WingHinge", Vector3.new(0.7, 0.62, 0.62), CFrame.new(sx * math.abs(root.X), root.Y, z) * CFrame.Angles(0, math.pi / 2, 0), "dark", Enum.PartType.Cylinder)
	end

	buildCockpit(model, folders.Chest, torso)
	buildHinge(folders.Chest, torso, helmet)
	buildBattery(folders.Chest, torso)

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
	humanoid.HipHeight = Mech3Builder.HipHeight
	humanoid.WalkSpeed = MechConfig.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.CameraOffset = Mech3Config.CameraOffset
	humanoid.Parent = model
	return model
end

-- Paints the built parts of one slot (the textured meshes stay as they are).
function Mech3Builder.applySlot(model: Model, slot: string, variantId: string)
	local folder = model:FindFirstChild("Armor_" .. slot)
	if not folder then
		return
	end
	local palette = Mech3Config.getVariant(variantId).palette
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute(ROLE_ATTR)
			if typeof(role) == "string" then
				paint(d, role, palette)
			end
		end
	end
	model:SetAttribute(slot, variantId)
end

function Mech3Builder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = Mech3Builder.buildRig(name)
	for _, slot in MechConfig.Slots do
		Mech3Builder.applySlot(model, slot, loadout[slot] or Mech3Config.DefaultVariant)
	end
	return model
end

-- Key points around a parked mech whose root is at `rootCF`. The cockpit is
-- the head; the pilot boards from in front, on the side of the knee that is
-- down (the mech's right), and is put down there again.
export type OffPoints = { prompt: Vector3, exit: Vector3, ground: number, forward: Vector3 }
function Mech3Builder.offPoints(rootCF: CFrame): OffPoints
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local ground = rootCF.Y - Mech3Builder.RootHeight
	local base = Vector3.new(rootCF.X, ground, rootCF.Z)
	return {
		prompt = base + forward * 6.5 + right * 2.5,
		exit = base + forward * 7.5 + right * 3,
		ground = ground,
		forward = forward, -- the exit faces away from the mech
	}
end

return Mech3Builder
