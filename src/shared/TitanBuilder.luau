--!strict
-- Builds the BRZ-01 "Titan" (type id "Titan", see TitanConfig) as a playable
-- mech around MechAssembly.build(): the assembled legs / chest / head / arms
-- (shape owned by Boot/Leg/Chest/Head/ArmBuilder + MechAssembly, NOT edited
-- here) plus everything a mech type needs, added after the build:
--
--   * HumanoidRootPart (invisible collision box) + Motor6D "Root" -> Pelvis,
--     Humanoid, model-level "PilotSeat", "MechType" = "Titan".
--   * Armor_Helmet / Armor_Chest / Armor_Legs folders (MechPattern, the
--     inventory slots): the head / chest + both arms / legs sub-models are
--     moved into them unchanged (welds and motors stay intact).
--   * Unique motor names: the two boots both build "Shin" / "Foot" bones
--     joined by "Ankle"; they are renamed Right|LeftShin, Right|LeftFoot,
--     Right|LeftAnkle so motors can be looked up by name.
--   * Colour: every visible part gets a palette role ("TitanRole" attribute:
--     main / hi / dark / recess / trim / glow / cell) picked by its name, with
--     the sheet colour it was built in as the fallback (see ROLE_BY_NAME and
--     ROLE_BY_COLOR). applySlot recolours a slot with a TitanConfig palette.
--   * Chest cockpit: the solid torso core blocks are removed and replaced by a
--     hollow cockpit (floor, walls, roof, seat, consoles); the front chest
--     plates (crescent dome, plate, lower plate, sides, big gem discs) are
--     re-welded to a "Hatch" bone on a Motor6D "HatchHinge" at their bottom
--     front edge, so the whole chest front swings down and open like a
--     drawbridge (TitanPose.setHatch).
--   * Battery pack on the upper back between the two exhaust tubes: casing,
--     four charge cells ("TitanCell" 1..4, lit by TitanAnimator from the
--     "Charge" attribute) and a terminal ("BatteryTerminal" attachment) for
--     the charging arc (TitanDock).
--
-- Model space: the ground point between the feet is the origin, facing -Z
-- (MechAssembly's leg space); the root sits RootHeight above it.

local MechBuilder = require(script.Parent.MechBuilder)
local MechConfig = require(script.Parent.MechConfig)
local TitanConfig = require(script.Parent.TitanConfig)
require(script.Parent.TitanPattern) -- registers the continuous-crosshatch pass (MechPattern.postApply)

local TitanBuilder = {}

TitanBuilder.TypeId = TitanConfig.TypeId
TitanBuilder.DisplayName = TitanConfig.DisplayName
TitanBuilder.Scale = MechConfig.Scale
TitanBuilder.RootHeight = TitanConfig.RootHeight
TitanBuilder.HipHeight = TitanConfig.RootHeight - TitanConfig.RootSize.Y / 2

local ROLE_ATTR = "TitanRole"
local SLOT_OF_MODEL = {
	MechHead = "Helmet",
	MechChest = "Chest",
	RightArm = "Chest",
	LeftArm = "Chest",
	MechLegs = "Legs",
}

-- ===== colour roles =========================================================

-- Part names (trailing digits stripped) -> role. Names come from the shape
-- modules; anything not listed falls back to its sheet colour below.
local ROLE_BY_NAME: { [string]: string } = {
	-- teal gems
	DiscBigFace = "glow",
	DiscSmallFace = "glow",
	KneeFace = "glow",
	HipDisc = "glow",
	Visor = "glow",
	KnuckleHole = "glow",
	CrestDisc = "glow",
	EarPodHub = "glow",
	-- pale steel details: spikes, fins, bolts, rods, slats
	Spike = "trim",
	SpikeCore = "trim",
	DropSpike = "trim",
	CrestBlade = "trim",
	CrestRidge = "trim",
	BoltHead = "trim",
	BoltPin = "trim",
	LatchRivet = "trim",
	LatchRod = "trim",
	Latch = "trim",
	Loop = "trim",
	PistonRod = "trim",
	KneeSlat = "trim",
	ExhaustRim = "trim",
	KneeHub = "trim",
	AnkleHub = "trim",
	ArmSocketHub = "trim",
	ShoulderHub = "trim",
	ElbowHub = "trim",
	CrestHub = "trim",
	-- polished brass on raised plates / rings
	ChestCrescent = "hi",
	CollarRing = "hi",
	CollarRim = "hi",
	DiscBigRing = "hi",
	DiscSmallRing = "hi",
	KnuckleRing = "hi",
	KneeGuardRidge = "hi",
	ShinRidge = "hi",
	InstepFace = "hi",
	KneeCapFace = "hi",
	HipPlateTip = "hi",
	HelmetSeam = "hi",
	HelmetCap = "hi",
	Faceplate = "hi",
	CheekGuard = "hi",
	EarBand = "hi",
	EarPod = "hi",
	CrestShield = "hi",
	SquarePlate = "hi",
	GauntletBand = "hi",
	CuffBand = "hi",
	SegmentPlate = "hi",
	PistonClamp = "hi",
	PistonKnuckle = "hi",
	AnkleRing = "hi",
	BackSpine = "hi",
	BackBand = "hi",
	KneeRim = "hi",
	ToeCap = "hi",
	PadStrap = "hi",
	-- deep recesses
	EarRecess = "recess",
	ExhaustBore = "recess",
	PalmFace = "recess",
	CollarFloor = "recess",
	VisorLip = "recess",
}

-- Sheet colours the shape modules build in (BootBuilder / ArmBuilder Colors).
local ROLE_BY_COLOR: { [string]: string } = {
	["106,125,142"] = "main",
	["112,128,142"] = "trim", -- rod
	["75,89,100"] = "dark", -- joint
	["88,104,117"] = "dark", -- joint face
	["80,95,108"] = "recess",
	["52,62,72"] = "recess",
	["58,69,79"] = "recess",
	["30,36,42"] = "recess", -- line / bore
}

local function colorKey(c: Color3): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function baseName(name: string): string
	return (string.gsub(name, "%d+$", ""))
end

local function roleOf(part: BasePart): string
	local byName = ROLE_BY_NAME[baseName(part.Name)]
	if byName then
		return byName
	end
	local byColor = ROLE_BY_COLOR[colorKey(part.Color)]
	if byColor then
		return byColor
	end
	local c = part.Color
	local lum = 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
	return if lum < 0.3 then "dark" else "main"
end

-- Paints one part for its role.
local function paint(part: BasePart, role: string, palette: TitanConfig.Palette)
	if role == "glow" or role == "cell" then
		part.Color = palette.glow
		part.Material = Enum.Material.Neon
		part:SetAttribute("LitColor", palette.glow)
		if role == "glow" then
			part:SetAttribute("MechLight", true) -- dimmed while powered down (TitanAnimator)
		end
	elseif role == "main" or role == "hi" then
		part.Color = (palette :: any)[role]
		part.Material = Enum.Material.SmoothPlastic
	else
		part.Color = (palette :: any)[role] or palette.dark
		part.Material = Enum.Material.Metal
	end
end

-- ===== helpers ==============================================================

local function weldTo(bone: BasePart, part: BasePart)
	for _, w in part:GetChildren() do
		if w:IsA("Weld") or w:IsA("WeldConstraint") then
			w:Destroy()
		end
	end
	local w = Instance.new("Weld")
	w.Part0 = bone
	w.Part1 = part
	w.C0 = bone.CFrame:ToObjectSpace(part.CFrame)
	w.Parent = part
end

-- A new armour part welded to `bone`, at `cf` (model space).
local function addPart(parent: Instance, bone: BasePart, name: string, size: Vector3, cf: CFrame, role: string, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute(ROLE_ATTR, role)
	p.Parent = parent
	weldTo(bone, p)
	return p
end

-- World-space bounds of a set of parts.
local function bounds(parts: { BasePart }): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in parts do
		local cf, s = d.CFrame, d.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = cf:PointToWorldSpace(Vector3.new(sx * s.X, sy * s.Y, sz * s.Z))
					lo, hi = lo:Min(p), hi:Max(p)
				end
			end
		end
	end
	return lo, hi
end

local function partsNamed(folder: Instance?, names: { string }): { BasePart }
	local out: { BasePart } = {}
	if not folder then
		return out
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and table.find(names, baseName(d.Name)) then
			table.insert(out, d)
		end
	end
	return out
end

-- ===== cockpit, hatch, battery =============================================
-- These find shape-module parts by name (ChestBuilder: TorsoArmor folder,
-- TorsoCore / TorsoCoreLow, ChestPlate / ChestCrescent / ChestLower /
-- ChestSide / DiscBig*, BackPlate / BackSpine / BackPanel / BackBlock,
-- Exhaust / ExhaustRim). If a rename breaks a lookup the mech still builds
-- (fixed fallback positions, no hatch) and says so once in the output.

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[TitanBuilder] " .. msg)
	end
end

local function torsoArmorOf(chestModel: Model): Instance?
	local f = chestModel:FindFirstChild("TorsoArmor")
	if not f then
		warnOnce("TorsoArmor", "ChestBuilder has no 'TorsoArmor' folder any more: cockpit / hatch / battery use fallback positions")
	end
	return f
end

-- Fallback cockpit box (model space, studs) when the torso core isn't found.
local FALLBACK_CORE_MIN = Vector3.new(-2.8, 19.9, -3.0)
local FALLBACK_CORE_MAX = Vector3.new(2.8, 25.4, 1.9)

local function buildCockpit(model: Model, chestModel: Model, chest: BasePart)
	local torsoArmor = torsoArmorOf(chestModel)
	local core = partsNamed(torsoArmor, { "TorsoCore", "TorsoCoreLow" })
	local lo, hi = FALLBACK_CORE_MIN, FALLBACK_CORE_MAX
	if #core == 0 then
		warnOnce("core", "no TorsoCore / TorsoCoreLow parts: cockpit uses its fallback box (the solid core, if renamed, may hide the pilot seat)")
	else
		lo, hi = bounds(core)
		for _, p in core do
			p:Destroy() -- the solid core becomes the hollow cockpit
		end
	end
	-- the roof sits under the collar: the gorget / throat (mesh skins or
	-- primitives) dip below the torso core's top and would show inside
	local top = hi.Y
	local asmRoot: Instance = chestModel.Parent or model -- the assembly (head, bones) at build time
	local headModel = asmRoot:FindFirstChild("MechHead", true)
	if headModel then
		for _, d in headModel:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local blo = bounds({ d })
				top = math.min(top, blo.Y - 0.05)
			end
		end
	end
	local okMeshes, TitanMeshes = pcall(require, script.Parent:FindFirstChild("TitanMeshes"))
	if okMeshes and typeof(TitanMeshes) == "table" and TitanMeshes.Meshes then
		for _, name in { "Titan_Gorget", "Titan_GorgetRecess", "Titan_ThroatFold" } do
			local e = TitanMeshes.Meshes[name]
			local boneName = e and e.bone
			local bonePart = boneName and asmRoot:FindFirstChild(boneName, true)
			if e and bonePart and bonePart:IsA("BasePart") then
				top = math.min(top, bonePart.Position.Y + e.offset.Y - e.size.Y / 2 - 0.05)
			end
		end
	end
	top = math.max(top, lo.Y + 4.4) -- never lower than a seated pilot needs
	hi = Vector3.new(hi.X, top, hi.Z)

	local folder = Instance.new("Folder")
	folder.Name = "Cockpit"
	folder.Parent = chestModel
	local cx = (lo.X + hi.X) / 2
	local w, h = hi.X - lo.X, hi.Y - lo.Y
	local t = 0.2
	local function box(name: string, size: Vector3, pos: Vector3, role: string): BasePart
		return addPart(folder, chest, name, size, CFrame.new(pos), role)
	end
	-- the side walls run the full box; floor, roof and back wall sit BETWEEN
	-- them (and the floor / roof stop short of the back wall), each kept E
	-- clear, so no two panel faces coincide (no z-fighting)
	local E = 0.02
	local innerW = w - 2 * t - 2 * E
	local slabZ0, slabZ1 = lo.Z + E, hi.Z - t - E
	box("CockpitFloor", Vector3.new(innerW, t, slabZ1 - slabZ0), Vector3.new(cx, lo.Y + t / 2, (slabZ0 + slabZ1) / 2), "recess")
	box("CockpitRoof", Vector3.new(innerW, t, slabZ1 - slabZ0), Vector3.new(cx, hi.Y - t / 2, (slabZ0 + slabZ1) / 2), "dark")
	box("CockpitBack", Vector3.new(innerW, h - 2 * t - 2 * E, t), Vector3.new(cx, (lo.Y + hi.Y) / 2, hi.Z - t / 2), "dark")
	local backFace = hi.Z - t -- inner face of the back wall
	for _, s in { 1, -1 } do
		local x = if s > 0 then hi.X - t / 2 else lo.X + t / 2
		local wallFace = x - s * t / 2
		box("CockpitWall", Vector3.new(t, h, hi.Z - lo.Z), Vector3.new(x, (lo.Y + hi.Y) / 2, (lo.Z + hi.Z) / 2), "dark")
		-- console screen in a dark bezel on each side wall
		box("CockpitBezel", Vector3.new(0.1, 0.8, 1.4), Vector3.new(wallFace - s * 0.06, lo.Y + 2.2, lo.Z + 1.3), "recess")
		box("CockpitScreen", Vector3.new(0.06, 0.6, 1.2), Vector3.new(wallFace - s * 0.12, lo.Y + 2.2, lo.Z + 1.3), "glow")
		-- cockpit light bars down the back wall: a lit tube in a dark channel, capped
		local barX = cx + s * 1.25
		local barH = h - 2 * t - 1.0
		local barY = (lo.Y + hi.Y) / 2
		box("CockpitLightFrame", Vector3.new(0.28, barH + 0.2, 0.12), Vector3.new(barX, barY, backFace - 0.07), "dark")
		box("CockpitLightBar", Vector3.new(0.12, barH, 0.08), Vector3.new(barX, barY, backFace - 0.13), "glow")
		for _, e in { 1, -1 } do
			box("CockpitLightCap", Vector3.new(0.3, 0.12, 0.18), Vector3.new(barX, barY + e * (barH / 2 + 0.03), backFace - 0.1), "trim")
		end
	end
	-- dome light in a frame under the roof, plus a soft fill light
	local roofFace = hi.Y - t
	local zc = (lo.Z + hi.Z) / 2
	box("CockpitDomeFrame", Vector3.new(1.7, 0.1, 0.75), Vector3.new(cx, roofFace - 0.06, zc), "dark")
	local dome = box("CockpitDome", Vector3.new(1.4, 0.06, 0.5), Vector3.new(cx, roofFace - 0.12, zc), "glow")
	local fill = Instance.new("PointLight")
	fill.Name = "CockpitLight"
	fill.Range = 7
	fill.Brightness = 0.6
	fill.Shadows = false
	fill.Parent = dome

	-- seat against the back wall: an R15 avatar sits with its head ~3.5 above the seat
	local seatY = lo.Y + 1.25
	local seatZ = hi.Z - 1.15
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(1.8, 0.3, 1.6)
	seat.CFrame = CFrame.new(cx, seatY, seatZ)
	seat.Anchored = false
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.Color = Color3.fromRGB(40, 30, 24)
	seat.Material = Enum.Material.Metal
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = model
	weldTo(chest, seat)
	box("SeatBack", Vector3.new(1.7, 2.2, 0.25), Vector3.new(cx, seatY + 1.2, hi.Z - t - 0.15), "dark")
	local postBottom = lo.Y + t + 0.02 -- clear of the floor's top face
	box("SeatPost", Vector3.new(0.8, seatY - postBottom, 0.8), Vector3.new(cx, (seatY + postBottom) / 2, seatZ), "dark")
	-- the clear interior (inside the wall / floor / roof / back panels)
	return Vector3.new(lo.X + t, lo.Y + t, lo.Z), Vector3.new(hi.X - t, hi.Y - t, hi.Z - t)
end

local function weldOf(part: BasePart): BasePart?
	for _, w in part:GetChildren() do
		if w:IsA("Weld") and w.Part1 == part and w.Part0 then
			return w.Part0
		end
	end
	return nil
end

-- Keeps the torso's own parts out of the cockpit: with the core gone, the
-- inner ends of the exhaust tubes, the back / shoulder blocks and the lower
-- flank fill would show through the open hatch. Rest pose, build space.
--   * exhaust tubes: left alone (ChestBuilder slides them clear: owner's edit)
--   * axis-aligned blocks: trimmed back out of the cockpit along the axis
--     that removes the least
--   * anything else (wedge fill) mostly (>= 60 %) inside: hidden
-- Hatch parts (they swing away), mesh skins, the cockpit and battery are left alone.
local function clearCockpit(chestModel: Model, ilo: Vector3, ihi: Vector3)
	local cleared = 0
	local function hide(p: BasePart)
		p.Transparency = 1
		p.CastShadow = false
		p:SetAttribute("CockpitHidden", true)
		cleared += 1
	end
	for _, d in chestModel:GetDescendants() do
		if not d:IsA("BasePart") or d:IsA("MeshPart") or d.Transparency >= 1 then
			continue
		end
		local f = d.Parent
		if f and (f.Name == "Cockpit" or f.Name == "Battery") then
			continue
		end
		local bone = weldOf(d)
		if not bone or bone.Name == "Hatch" then
			continue -- a bone itself, or swings away with the hatch
		end
		local plo, phi = bounds({ d })
		local olo, ohi = plo:Max(ilo), phi:Min(ihi)
		local ov = ohi - olo
		if ov.X <= 0.03 or ov.Y <= 0.03 or ov.Z <= 0.03 then
			continue
		end
		if string.find(d.Name, "^Exhaust") then
			continue -- the tubes were slid clear of the cockpit by the owner (ChestBuilder EXHAUST.slide)
		end
		local isBlock = d:IsA("Part") and d.Shape == Enum.PartType.Block
		local R = d.CFrame
		local aligned = math.abs(R.RightVector:Dot(Vector3.xAxis)) > 0.999 or math.abs(R.RightVector:Dot(Vector3.zAxis)) > 0.999 or math.abs(R.RightVector:Dot(Vector3.yAxis)) > 0.999
		aligned = aligned and (math.abs(R.UpVector.X) > 0.999 or math.abs(R.UpVector.Y) > 0.999 or math.abs(R.UpVector.Z) > 0.999)
		if isBlock and aligned then
			-- trim along the axis that removes the least (the part keeps its outer side)
			local best, bestCut = nil, math.huge
			for _, axis in { "X", "Y", "Z" } do
				local pl, ph = (plo :: any)[axis] :: number, (phi :: any)[axis] :: number
				local il, ih = (ilo :: any)[axis] :: number, (ihi :: any)[axis] :: number
				local cut = (ov :: any)[axis] :: number
				if (ph > ih + 0.05 or pl < il - 0.05) and cut < bestCut then
					best, bestCut = axis, cut
				end
			end
			if not best then
				hide(d)
				continue
			end
			local pl, ph = (plo :: any)[best] :: number, (phi :: any)[best] :: number
			local il, ih = (ilo :: any)[best] :: number, (ihi :: any)[best] :: number
			local keepLo, keepHi
			if ph > ih + 0.05 then
				keepLo, keepHi = ih + 0.01, ph
			else
				keepLo, keepHi = pl, il - 0.01
			end
			local newLo, newHi = plo, phi
			if best == "X" then
				newLo, newHi = Vector3.new(keepLo, plo.Y, plo.Z), Vector3.new(keepHi, phi.Y, phi.Z)
			elseif best == "Y" then
				newLo, newHi = Vector3.new(plo.X, keepLo, plo.Z), Vector3.new(phi.X, keepHi, phi.Z)
			else
				newLo, newHi = Vector3.new(plo.X, plo.Y, keepLo), Vector3.new(phi.X, phi.Y, keepHi)
			end
			local worldSize = newHi - newLo
			-- back into the part's local axes (axis-aligned: just a permutation)
			local ls = R:VectorToObjectSpace(worldSize)
			d.Size = Vector3.new(math.abs(ls.X), math.abs(ls.Y), math.abs(ls.Z))
			d.CFrame = R.Rotation + (newLo + newHi) / 2
			weldTo(bone, d)
			cleared += 1
			continue
		end
		local vol = (phi.X - plo.X) * (phi.Y - plo.Y) * (phi.Z - plo.Z)
		if vol > 0 and ov.X * ov.Y * ov.Z >= 0.6 * vol then
			hide(d)
		end
	end
	return cleared
end

-- Re-welds the chest front to a hinged "Hatch" bone.
local HATCH_PARTS = { "ChestPlate", "ChestCrescent", "ChestLower", "ChestSide", "DiscBigRing", "DiscBigFace" }

local function buildHatch(chestModel: Model, chest: BasePart)
	local parts = partsNamed(torsoArmorOf(chestModel), HATCH_PARTS)
	if #parts == 0 then
		warnOnce("hatch", "no chest front parts (" .. table.concat(HATCH_PARTS, " / ") .. "): the chest hatch is not built")
		return
	end
	local lo, hi = bounds(parts)
	-- hinge along the bottom edge, at the plate's inner face
	local hingeCF = CFrame.new(0, lo.Y + 0.15, math.min(hi.Z, lo.Z + 2.0))
	local hatch = Instance.new("Part")
	hatch.Name = "Hatch"
	hatch.Size = Vector3.new(0.4, 0.4, 0.4)
	hatch.CFrame = hingeCF
	hatch.Transparency = 1
	hatch.CanCollide = false
	hatch.CanTouch = false
	hatch.CanQuery = false
	hatch.Massless = true
	hatch.Anchored = false
	hatch.Parent = chestModel
	local m = Instance.new("Motor6D")
	m.Name = "HatchHinge"
	m.Part0 = chest
	m.Part1 = hatch
	m.C0 = chest.CFrame:ToObjectSpace(hingeCF)
	m.Parent = chest
	for _, p in parts do
		weldTo(hatch, p)
	end
end

local function buildBattery(chestModel: Model, chest: BasePart)
	local torsoArmor = torsoArmorOf(chestModel)
	-- between the exhaust tubes, on the back plate
	local back = partsNamed(torsoArmor, { "BackPlate", "BackSpine", "BackPanel", "BackBlock" })
	local exhausts = partsNamed(torsoArmor, { "Exhaust", "ExhaustRim" })
	local backZ = 2.6
	if #back == 0 then
		warnOnce("back", "no BackPlate / BackSpine / BackPanel / BackBlock parts: battery sits at its fallback depth")
	end
	if #exhausts == 0 then
		warnOnce("exhaust", "no Exhaust / ExhaustRim parts: battery uses its fallback width and height")
	end
	if #back > 0 then
		local _, hi = bounds(back)
		backZ = hi.Z
	end
	local gap = 3.0 -- half width between the tubes' inner edges
	local cy = 22.6
	if #exhausts > 0 then
		local inner = math.huge
		local ylo, yhi = math.huge, -math.huge
		-- the tubes slide down / out along their axis (ChestBuilder EXHAUST.slide,
		-- the owner's edit): measure them where they were before, so the battery
		-- keeps its place between them
		local slideStuds = 0
		local okChest, CB = pcall(require, script.Parent:FindFirstChild("ChestBuilder"))
		local okBoot, BB = pcall(require, script.Parent:FindFirstChild("BootBuilder"))
		if okChest and okBoot and typeof(CB) == "table" and typeof(CB.ExhaustSlide) == "number" then
			slideStuds = CB.ExhaustSlide * BB.CELL * TitanBuilder.Scale
		end
		for _, e in exhausts do
			local probe = e
			if slideStuds > 0 and e.Name == "Exhaust" then
				local ax = e.CFrame.RightVector
				local down = if ax.Y < 0 then ax else -ax
				probe = e:Clone()
				probe.CFrame = e.CFrame - down * slideStuds
			end
			local lo, hi = bounds({ probe })
			if probe ~= e then
				probe:Destroy()
			end
			local edge = if lo.X > 0 then lo.X elseif hi.X < 0 then -hi.X else 0
			if edge > 0.3 then
				inner = math.min(inner, edge)
			end
			ylo, yhi = math.min(ylo, lo.Y), math.max(yhi, hi.Y)
		end
		if inner < math.huge then
			gap = inner
		end
		cy = (ylo + yhi) / 2 + 0.6
	end
	local w = math.clamp(gap * 2 - 0.25, 1.8, 3.2)
	local h, d = 3.8, 1.5
	local z = backZ + d / 2 - 0.05
	local folder = Instance.new("Folder")
	folder.Name = "Battery"
	folder.Parent = chestModel
	local function at(x: number, y: number, zz: number): CFrame
		return CFrame.new(x, y, zz)
	end
	addPart(folder, chest, "BatteryCase", Vector3.new(w, h, d), at(0, cy, z), "dark")
	addPart(folder, chest, "BatteryFace", Vector3.new(w - 0.35, h - 0.35, 0.15), at(0, cy, z + d / 2 + 0.05), "main")
	-- four charge cells stacked bottom to top behind a window
	addPart(folder, chest, "BatteryWindow", Vector3.new(w - 0.9, h - 0.95, 0.1), at(0, cy - 0.1, z + d / 2 + 0.14), "recess")
	local cellH = (h - 1.3) / 4
	for i = 1, 4 do
		local y = cy - 0.1 - (h - 0.95) / 2 + 0.2 + (i - 0.5) * cellH
		local cell = addPart(folder, chest, "BatteryCell" .. i, Vector3.new(w - 1.2, cellH - 0.12, 0.08), at(0, y, z + d / 2 + 0.21), "cell")
		cell:SetAttribute("TitanCell", i)
	end
	-- brass clamps, steel bolts
	for _, s in { 1, -1 } do
		addPart(folder, chest, "BatteryClamp", Vector3.new(0.3, h + 0.2, d + 0.3), at(s * (w / 2 + 0.05), cy, z), "hi")
		for _, y in { cy + h / 2 - 0.3, cy - h / 2 + 0.3 } do
			addPart(folder, chest, "BatteryBolt", Vector3.new(0.2, 0.28, 0.28), at(s * (w / 2 + 0.25), y, z + d / 2 - 0.1), "trim", Enum.PartType.Cylinder)
		end
	end
	-- terminal on top: insulator stack + cap, the arc lands on the cap
	addPart(folder, chest, "BatteryCap", Vector3.new(w - 0.3, 0.3, d - 0.1), at(0, cy + h / 2 + 0.17, z), "hi") -- clear of the case top and the clamps
	addPart(folder, chest, "BatteryInsulator", Vector3.new(0.7, 0.55, 0.55), at(0, cy + h / 2 + 0.55, z + 0.1) * CFrame.Angles(0, 0, math.pi / 2), "dark", Enum.PartType.Cylinder)
	local cap = addPart(folder, chest, "BatteryTerminal", Vector3.new(0.6, 0.6, 0.6), at(0, cy + h / 2 + 1.0, z + 0.1), "trim", Enum.PartType.Ball)
	local a = Instance.new("Attachment")
	a.Name = "BatteryTerminal"
	a.Parent = cap
end

-- ===== rig ==================================================================

-- Builds the full mech (geometry included); colours default to Bronze.
function TitanBuilder.buildRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MechType", TitanBuilder.TypeId)

	-- required here, not at load: the shape modules are still being refined, and
	-- a broken one must not take MechTypes (every other mech) down with it
	local MechAssembly = require(script.Parent.MechAssembly) :: any
	local asm = MechAssembly.build(TitanBuilder.Scale) :: Model
	local pelvis = asm.PrimaryPart :: BasePart

	-- unique bone / motor names for the two boots
	for _, side in { "R", "L" } do
		local n = if side == "R" then "Right" else "Left"
		local boot = asm:FindFirstChild("Boot" .. side, true)
		if not boot then
			warnOnce("boot" .. side, "no 'Boot" .. side .. "' model: the " .. n .. " leg's Shin / Foot / Ankle keep their shared names (leg IK needs " .. n .. "Ankle)")
		end
		if boot then
			local shin = boot:FindFirstChild("Shin")
			local foot = boot:FindFirstChild("Foot")
			local ankle = shin and shin:FindFirstChild("Ankle")
			if shin then
				shin.Name = n .. "Shin"
			end
			if foot then
				foot.Name = n .. "Foot"
			end
			if ankle then
				ankle.Name = n .. "Ankle"
			end
		end
	end

	-- palette roles from the parts as built (before anything is added)
	for _, d in asm:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d:SetAttribute(ROLE_ATTR, roleOf(d))
		end
	end

	local chestModel = asm:FindFirstChild("MechChest") :: Model
	assert(chestModel, "[TitanBuilder] MechAssembly built no 'MechChest' model")
	local chest = chestModel:FindFirstChild("Chest") :: BasePart
	assert(chest, "[TitanBuilder] MechChest has no 'Chest' bone")
	local ilo, ihi = buildCockpit(model, chestModel, chest)
	buildHatch(chestModel, chest)
	buildBattery(chestModel, chest)
	clearCockpit(chestModel, ilo, ihi)

	-- a soft glow from the chest gems
	for _, p in partsNamed(chestModel, { "DiscBigFace" }) do
		local light = Instance.new("PointLight")
		light.Name = "GemLight"
		light.Range = 6
		light.Brightness = 0.6
		light.Shadows = false
		light.Parent = p
	end

	-- root collision box + Root motor to the pelvis
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = TitanConfig.RootSize
	root.CFrame = CFrame.new(0, TitanConfig.RootHeight, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = MechBuilder.RootGroup
	root.RootPriority = 100 -- stays the assembly root with a pilot welded in
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	local rootMotor = Instance.new("Motor6D")
	rootMotor.Name = "Root"
	rootMotor.Part0 = root
	rootMotor.Part1 = pelvis
	rootMotor.C0 = root.CFrame:ToObjectSpace(pelvis.CFrame)
	rootMotor.Parent = root

	-- sub-models into the armour slot folders
	local folders: { [string]: Folder } = {}
	for _, slot in MechConfig.Slots do
		local f = Instance.new("Folder")
		f.Name = "Armor_" .. slot
		f.Parent = model
		folders[slot] = f
	end
	for _, child in asm:GetChildren() do
		local slot = SLOT_OF_MODEL[child.Name]
		child.Parent = if slot then folders[slot] else folders.Chest
	end
	asm:Destroy()

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.Massless = true
			d.CanTouch = false
			if not d:IsA("Seat") then
				d.CanCollide = false
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
	humanoid.HipHeight = TitanBuilder.HipHeight
	humanoid.WalkSpeed = MechConfig.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.CameraOffset = TitanConfig.CameraOffset
	humanoid.Parent = model
	require(script.Parent.TitanMeshes).apply(model) -- MESH SKINS: swaps the curved wedge groups for imported MeshParts (ReplicatedStorage.TitanMeshes); no-op until they exist
	return model
end

-- Recolours one slot with a variant's palette (MechConfig variant id ->
-- TitanConfig palette). The geometry is the same for every variant.
function TitanBuilder.applySlot(model: Model, slot: string, variantId: string)
	local folder = model:FindFirstChild("Armor_" .. slot)
	if not folder then
		return
	end
	local palette = TitanConfig.getVariant(variantId).palette
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
	if slot == "Chest" then
		local seat = model:FindFirstChild("PilotSeat")
		if seat and seat:IsA("BasePart") then
			seat.Color = palette.recess
		end
	end
	model:SetAttribute(slot, variantId)
end

-- Builds a complete mech. `loadout` maps slot -> variant id.
function TitanBuilder.buildMech(name: string, loadout: { [string]: string }): Model
	local model = TitanBuilder.buildRig(name)
	for _, slot in MechConfig.Slots do
		TitanBuilder.applySlot(model, slot, loadout[slot] or TitanConfig.DefaultVariant)
	end
	return model
end

-- Key points around a parked (kneeling) mech whose root is at `rootCF`.
export type OffPoints = { prompt: Vector3, exit: Vector3, ground: number, forward: Vector3 }
function TitanBuilder.offPoints(rootCF: CFrame): OffPoints
	local look = rootCF.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local ground = rootCF.Y - TitanBuilder.RootHeight
	local base = Vector3.new(rootCF.X, ground, rootCF.Z)
	return {
		prompt = base + forward * 9, -- in front of the open chest hatch
		exit = base + forward * 11,
		ground = ground,
		forward = forward,
	}
end

return TitanBuilder
