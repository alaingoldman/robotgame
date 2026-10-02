--!strict
-- Builds the CRM-01 "Crimson" (type id "Crimson", CrimsonConfig) from the
-- owner's textured meshes (CrimsonMeshes): an invisible bone per part joined
-- by Motor6Ds at the meta.json pivots, every MeshPart (texture kept) welded
-- to its bone, plus what every mech type needs:
--
--   * HumanoidRootPart (invisible collision box on the hip line) + Motor6D
--     "Root" -> Pelvis, Humanoid, model-level "PilotSeat", "MechType".
--   * Armor_Helmet (head) / Armor_Chest (torso, pads, arms, pod) / Armor_Legs.
--   * Motors: Root, Waist, Neck, Right|Left Shoulder / Elbow / Wrist, Right|
--     Left Hip / Knee / Ankle, Right|Left PadJoint (the shoulder pad takes
--     part of the arm swing, CrimsonAnimator), HatchHinge.
--   * Blades: the cleaver welded in the right fist; a second one mounted on
--     the outside of the left forearm, tip down (CrimsonConfig.Blade).
--   * Back pod cockpit: an armoured pod on the back of the torso; its back
--     plate is a hatch hinged along its top edge ("HatchHinge") that swings
--     up and back while parked. Inside: liner, a seat, cyan screens and a
--     light; the seated pilot is shown as a scaled stand-in (CrimsonAnimator),
--     the real avatar is hidden.
--   * Battery: four charge cells ("CrimsonCell" 1..4) on the hatch, a
--     terminal ("BatteryTerminal") on top of the pod for the dock arc.
--   * Eyes ("CrimsonEye") on the head visor and core lights ("CrimsonCore")
--     that power up with the pilot in.

local RunService = game:GetService("RunService")

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)
local CrimsonConfig = require(script.Parent.CrimsonConfig)
local CrimsonMeshes = require(script.Parent.CrimsonMeshes)

local CrimsonBuilder = {}

CrimsonBuilder.TypeId = CrimsonConfig.TypeId
CrimsonBuilder.DisplayName = CrimsonConfig.DisplayName
CrimsonBuilder.RootHeight = CrimsonConfig.RootHeight
CrimsonBuilder.HipHeight = CrimsonConfig.RootHeight - CrimsonConfig.RootSize.Y / 2

local ROLE_ATTR = "CrimsonRole"
local PV = CrimsonConfig.Pivots
local BL = CrimsonConfig.Blade

local SLOT_OF_BONE: { [string]: string } = {
	Head = "Helmet",
	RightThigh = "Legs",
	RightShin = "Legs",
	RightFoot = "Legs",
	LeftThigh = "Legs",
	LeftShin = "Legs",
	LeftFoot = "Legs",
}

-- ===== helpers ==============================================================

local function paint(part: BasePart, role: string, palette: CrimsonConfig.Palette)
	if role == "glow" then
		part.Color = palette.glow
		part.Material = Enum.Material.Neon
		part:SetAttribute("LitColor", palette.glow)
	elseif role == "main" then
		part.Color = (palette :: any).main
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

local function blade(parent: Instance, bone: BasePart, name: string, cf: CFrame): BasePart?
	local t = CrimsonMeshes.template(CrimsonMeshes.Blade)
	if not t then
		return nil
	end
	local mp = t:Clone()
	mp.Name = name
	-- the template sits where it loaded (asset frame); its grip is the asset
	-- origin, so place it relative to that
	mp.CFrame = cf * CrimsonMeshes.modelCFrame(t)
	mp.Anchored = false
	mp.CanCollide = false
	mp.CanTouch = false
	mp.CanQuery = false
	mp.Massless = true
	mp.Parent = parent
	weld(bone, mp, bone.CFrame:ToObjectSpace(mp.CFrame))
	return mp
end

-- ===== back pod cockpit + battery ===========================================
-- The torso back (ray casts of the mesh, model space): z 3.55 at y 17,
-- 3.2 at y 15.5, 2.8 at y 14.5 (|x| <= 1; a groove at x 0), the head's back
-- hump reaches z 3.4 above y 18. The pod hangs on that slope; its hatch is
-- the pod's back face.
local POD = {
	top = 17.3,
	bottom = 13.9,
	halfW = 1.6,
	front = 2.85, -- inner face (into the torso back)
	back = 4.5, -- outer face, where the hatch closes
}
CrimsonBuilder.Pod = POD

local function wedge(parent: Instance, bone: BasePart, name: string, size: Vector3, cf: CFrame, role: string): BasePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.Massless = true
	w:SetAttribute(ROLE_ATTR, role)
	w.Parent = parent
	weld(bone, w, bone.CFrame:ToObjectSpace(cf))
	return w
end

local function buildPod(model: Model, folder: Instance, torso: BasePart)
	local pod = Instance.new("Folder")
	pod.Name = "Pod"
	pod.Parent = folder
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end
	local yc, h = (POD.top + POD.bottom) / 2, POD.top - POD.bottom
	local zc, d = (POD.front + POD.back) / 2, POD.back - POD.front
	local w = POD.halfW * 2
	local t = 0.2
	local ch = 0.45 -- chamfer on the outer edges
	-- shell: side walls with chamfered back corners, a roof bevelled down to
	-- the back (wedge slopes face up and back), a dark belly; dark frame
	-- round the opening
	for _, sx in { 1, -1 } do
		addPart(pod, torso, "PodWall", Vector3.new(t, h, d - ch), at(sx * (POD.halfW - t / 2), yc, zc - ch / 2), "main")
		addPart(pod, torso, "PodChamfer", Vector3.new(ch * 1.414, h, t), at(sx * (POD.halfW - ch / 2), yc, POD.back - ch / 2) * CFrame.Angles(0, sx * math.pi / 4, 0), "main")
		-- vents: a dark recess with steel louvres, a cyan running light
		addPart(pod, torso, "PodVent", Vector3.new(0.05, 1.3, d - 1.0), at(sx * (POD.halfW + 0.02), yc - 0.35, zc - 0.25), "dark")
		for i = 0, 3 do
			addPart(pod, torso, "PodLouvre", Vector3.new(0.12, 0.08, d - 1.1), at(sx * (POD.halfW + 0.05), yc - 0.85 + i * 0.33, zc - 0.25) * CFrame.Angles(0, 0, sx * 0.5), "trim")
		end
		local strip = addPart(pod, torso, "PodLight", Vector3.new(0.06, 0.1, d - 1.0), at(sx * (POD.halfW + 0.03), yc + 0.75, zc - 0.25), "glow")
		strip:SetAttribute("CrimsonCore", true)
		-- exhaust nozzle under each side
		addPart(pod, torso, "PodNozzle", Vector3.new(0.5, 0.62, 0.62), at(sx * 0.9, POD.bottom - 0.2, zc + 0.2) * CFrame.Angles(0, 0, math.pi / 2), "dark", Enum.PartType.Cylinder)
		addPart(pod, torso, "PodNozzleRing", Vector3.new(0.12, 0.72, 0.72), at(sx * 0.9, POD.bottom - 0.42, zc + 0.2) * CFrame.Angles(0, 0, math.pi / 2), "trim", Enum.PartType.Cylinder)
	end
	addPart(pod, torso, "PodRoof", Vector3.new(w - 2 * t, t, d - ch), at(0, POD.top - t / 2, zc - ch / 2), "main")
	wedge(pod, torso, "PodRoofBevel", Vector3.new(w, ch, ch), at(0, POD.top - ch / 2, POD.back - ch / 2) * CFrame.Angles(0, math.pi, 0), "main")
	addPart(pod, torso, "PodFloor", Vector3.new(w, t, d), at(0, POD.bottom + t / 2, zc), "main")
	addPart(pod, torso, "PodBelly", Vector3.new(w - 0.3, 0.25, d - 0.3), at(0, POD.bottom - 0.08, zc - 0.1), "dark")
	for _, sx in { 1, -1 } do
		addPart(pod, torso, "PodFrame", Vector3.new(0.14, h - ch - 0.1, 0.14), at(sx * (POD.halfW - ch - 0.02), yc - ch / 2, POD.back - 0.05), "dark")
	end
	addPart(pod, torso, "PodFrame", Vector3.new(w - 2 * ch, 0.14, 0.14), at(0, POD.bottom + t + 0.02, POD.back - 0.05), "dark")
	-- liner, seat, screens and a lamp inside
	addPart(pod, torso, "PodLiner", Vector3.new(w - 2 * t, h - 2 * t, 0.06), at(0, yc, POD.front + 0.05), "dark")
	for _, sx in { 1, -1 } do
		addPart(pod, torso, "PodLinerSide", Vector3.new(0.04, h - 2 * t - ch, d - ch - 0.1), at(sx * (POD.halfW - t - 0.03), yc - ch / 2, zc - ch / 2), "dark")
		local s = addPart(pod, torso, "PodScreen", Vector3.new(0.05, 0.45, 0.6), at(sx * (POD.halfW - t - 0.07), yc + 0.35, zc - 0.2), "glow")
		s:SetAttribute("CrimsonCore", true)
	end
	local seatY = POD.bottom + t + 0.3
	addPart(pod, torso, "SeatPan", Vector3.new(1.0, 0.16, 0.75), at(0, seatY, zc + 0.05), "trim")
	addPart(pod, torso, "SeatBack", Vector3.new(1.0, 1.1, 0.14), at(0, seatY + 0.62, POD.front + 0.2) * CFrame.Angles(-0.1, 0, 0), "dark")
	local bar = addPart(pod, torso, "PodLightBar", Vector3.new(w - 1.0, 0.07, 0.05), at(0, POD.top - t - 0.08, POD.front + 0.5), "glow")
	bar:SetAttribute("CrimsonCore", true)
	local light = Instance.new("PointLight")
	light.Name = "CockpitLight"
	light.Range = 6
	light.Brightness = 1
	light.Color = Color3.fromRGB(200, 255, 240)
	light.Shadows = true
	light.Parent = bar
	-- the real seat (invisible); the avatar on it is hidden and shown scaled
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(1, 0.2, 0.8)
	local seatCF = at(0, seatY, zc + 0.05) -- faces -Z, like the mech
	seat.CFrame = seatCF
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.Parent = model
	weld(torso, seat, torso.CFrame:ToObjectSpace(seatCF))

	-- battery terminal on a short mast on the roof (the dock arc lands on its ball)
	local tx, tz = 0.85, zc - 0.3
	addPart(pod, torso, "BatteryMastBase", Vector3.new(0.5, 0.18, 0.5), at(tx, POD.top + 0.09, tz), "dark")
	addPart(pod, torso, "BatteryPost", Vector3.new(0.6, 0.22, 0.22), at(tx, POD.top + 0.45, tz) * CFrame.Angles(0, 0, math.pi / 2), "trim", Enum.PartType.Cylinder)
	local ball = addPart(pod, torso, "BatteryTerminal", Vector3.new(0.4, 0.4, 0.4), at(tx, POD.top + 0.85, tz), "trim", Enum.PartType.Ball)
	local a = Instance.new("Attachment")
	a.Name = "BatteryTerminal"
	a.Parent = ball
	-- a whip antenna on the other side
	addPart(pod, torso, "Antenna", Vector3.new(0.07, 1.6, 0.07), at(-0.95, POD.top + 0.8, tz) * CFrame.Angles(0.15, 0, 0.1), "dark")
end

-- The hatch: the pod's back plate on the "Hatch" bone, armour layered on
-- it, and the four charge cells in a dark slot.
local function buildHatch(folder: Instance, hatch: BasePart)
	local hf = Instance.new("Folder")
	hf.Name = "Hatch"
	hf.Parent = folder
	local ch = 0.45
	local top, bottom = POD.top - ch, POD.bottom
	local yc, h = (top + bottom) / 2, top - bottom
	local z = POD.back + 0.08
	local w = (POD.halfW - ch) * 2 + 0.1
	local function at(x: number, y: number, zz: number): CFrame
		return CFrame.new(x, y, zz)
	end
	addPart(hf, hatch, "HatchPlate", Vector3.new(w, h, 0.16), at(0, yc, z), "main")
	-- raised armour plate with bevelled top and bottom
	local aw, ah = w - 0.35, h - 1.0
	addPart(hf, hatch, "HatchArmor", Vector3.new(aw, ah, 0.2), at(0, yc + 0.05, z + 0.17), "main")
	wedge(hf, hatch, "HatchBevelTop", Vector3.new(aw, 0.35, 0.2), at(0, yc + 0.05 + ah / 2 + 0.175, z + 0.17) * CFrame.Angles(0, math.pi, 0), "main")
	wedge(hf, hatch, "HatchBevelBottom", Vector3.new(aw, 0.35, 0.2), at(0, yc + 0.05 - ah / 2 - 0.175, z + 0.17) * CFrame.Angles(math.pi, 0, 0), "main")
	for _, sx in { 1, -1 } do
		addPart(hf, hatch, "HatchKnuckle", Vector3.new(0.55, 0.3, 0.3), at(sx * 0.75, top + 0.05, z - 0.05) * CFrame.Angles(0, 0, math.pi / 2), "dark", Enum.PartType.Cylinder)
		for _, sy in { 1, -1 } do
			addPart(hf, hatch, "HatchRivet", Vector3.new(0.14, 0.14, 0.14), at(sx * (aw / 2 - 0.15), yc + 0.05 + sy * (ah / 2 - 0.15), z + 0.29), "trim", Enum.PartType.Ball)
		end
	end
	-- battery slot: a dark recess with four cells (bottom = 1)
	local cy, cH = yc + 0.15, 1.5
	addPart(hf, hatch, "BatterySlot", Vector3.new(0.95, cH + 0.24, 0.06), at(0, cy, z + 0.29), "dark")
	local cellH = cH / 4
	for i = 1, 4 do
		local y = cy - cH / 2 + (i - 0.5) * cellH
		local cell = addPart(hf, hatch, "BatteryCell" .. i, Vector3.new(0.7, cellH - 0.1, 0.05), at(0, y, z + 0.32), "glow")
		cell:SetAttribute("CrimsonCell", i)
	end
	addPart(hf, hatch, "HatchHandle", Vector3.new(0.9, 0.12, 0.12), at(0, bottom + 0.35, z + 0.3), "trim")
	for _, sx in { 1, -1 } do
		addPart(hf, hatch, "HatchHandlePost", Vector3.new(0.1, 0.1, 0.2), at(sx * 0.4, bottom + 0.35, z + 0.2), "trim")
	end
end

-- ===== rig ==================================================================

function CrimsonBuilder.buildRig(name: string): Model
	if not CrimsonMeshes.available() and (RunService:IsServer() or not RunService:IsRunning()) then
		local ok, err = pcall(CrimsonMeshes.ensure)
		if not ok then
			warn("[CrimsonBuilder] loading mesh templates failed: " .. tostring(err))
		end
	end
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", CrimsonBuilder.TypeId)

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
	root.Size = CrimsonConfig.RootSize
	root.CFrame = CFrame.new(0, CrimsonConfig.RootHeight, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = MechBuilder.RootGroup
	root.RootPriority = 100
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local pelvis = bone("Pelvis", Vector3.new(0, CrimsonConfig.HipLine, 0))
	local torso = bone("Torso", PV.Waist)
	local head = bone("Head", PV.Neck)
	local hatch = bone("Hatch", CrimsonConfig.Hatch.Hinge)
	motor("Root", root, pelvis)
	motor("Waist", pelvis, torso)
	motor("Neck", torso, head)
	motor("HatchHinge", torso, hatch)
	for _, side in { "Right", "Left" } do
		local pad = bone(side .. "Pad", PV.Pad[side])
		local upper = bone(side .. "UpperArm", PV.Shoulder[side])
		local lower = bone(side .. "LowerArm", PV.Elbow[side])
		local hand = bone(side .. "Hand", PV.Wrist[side])
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
	for partName, e in CrimsonMeshes.Parts do
		local t = CrimsonMeshes.template(partName)
		local b = bones[e.bone]
		if not (t and b) then
			missing += 1
			continue
		end
		local mp = t:Clone()
		mp.Name = partName
		mp.CFrame = CrimsonMeshes.modelCFrame(t)
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanTouch = false
		mp.CanQuery = false
		mp.Massless = true
		mp.CastShadow = true
		for _, c in mp:GetChildren() do
			c:Destroy()
		end
		weld(b, mp, b.CFrame:ToObjectSpace(mp.CFrame))
		mp.Parent = folderOf(e.bone)
	end
	if missing > 0 then
		warn(string.format("[CrimsonBuilder] %d of the Crimson meshes have no template (ReplicatedStorage.%s): built without them", missing, CrimsonMeshes.FolderName))
	end

	-- the cleaver in the right fist: blade forward and down, edge underneath
	local grip = CFrame.new(BL.Grip) * CFrame.Angles(0, -BL.Yaw, 0) * CFrame.Angles(-math.pi / 2 + BL.Pitch, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	-- on its own "CleaverGrip" joint at the fist: parked, it turns to a reverse
	-- grip, the blade standing up along the outside of the forearm
	-- (CrimsonPose.kneel), and flips forward again as the mech stands
	local gripBone = bone("CleaverGrip", BL.Grip)
	motor("CleaverGrip", bones.RightHand, gripBone)
	blade(folders.Chest, gripBone, "Cleaver", grip)
	-- the arm blade: along the outside of the left forearm, tip down, edge forward
	if BL.ArmMount then
		local at = PV.Elbow.Left + BL.ArmOffset
		local mount = CFrame.new(at) * CFrame.Angles(0, 0, math.pi - BL.ArmTilt) * CFrame.Angles(0, -math.pi / 2, 0)
		blade(folders.Chest, bones.LeftLowerArm, "ArmBlade", mount)
		-- clamp bands holding it to the forearm
		for i, dy in { 0.2, -1.4 } do
			addPart(folders.Chest, bones.LeftLowerArm, "ArmBladeClamp" .. i, Vector3.new(0.75, 0.32, 1.1), CFrame.new(at + Vector3.new(0.4, dy, 0)), "dark")
		end
	end

	-- eyes on the visor (ray casts: the visor face is at z -1.2 .. -1.3 for
	-- |x| 0.4 .. 0.7 at y 19.1); dark while parked, lit with a pilot in
	for _, sx in { 1, -1 } do
		local eye = addPart(folders.Helmet, head, "Eye", Vector3.new(0.34, 0.1, 0.1), CFrame.new(sx * 0.52, 19.12, -1.3) * CFrame.Angles(0, 0, sx * -0.18), "glow")
		eye:SetAttribute("CrimsonEye", true)
	end

	buildPod(model, folders.Chest, torso)
	buildHatch(folders.Chest, hatch)

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
	humanoid.HipHeight = CrimsonBuilder.HipHeight
	humanoid.WalkSpeed = MechConfig.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.CameraOffset = CrimsonConfig.CameraOffset
	humanoid.Parent = model
	return model
end

-- Paints the built parts of one slot (the textured meshes stay as they are).
function CrimsonBuilder.applySlot(model: Model, slot: string, variantId: string)
	local folder = model:FindFirstChild("Armor_" .. slot)
	if not folder then
		return
	end
	local palette = CrimsonConfig.getVariant(variantId).palette
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

function CrimsonBuilder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = CrimsonBuilder.buildRig(name)
	for _, slot in MechConfig.Slots do
		CrimsonBuilder.applySlot(model, slot, loadout[slot] or CrimsonConfig.DefaultVariant)
	end
	return model
end

-- Key points around a parked mech whose root is at `rootCF`. The pod is on
-- its back, so the pilot boards from behind and is put down there.
export type OffPoints = { prompt: Vector3, exit: Vector3, ground: number, forward: Vector3 }
function CrimsonBuilder.offPoints(rootCF: CFrame): OffPoints
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local ground = rootCF.Y - CrimsonBuilder.RootHeight
	local base = Vector3.new(rootCF.X, ground, rootCF.Z)
	return {
		prompt = base - forward * 7 - right * 2.5,
		exit = base - forward * 7.5 - right * 3,
		ground = ground,
		forward = -forward, -- the exit faces away from the mech
	}
end

return CrimsonBuilder
