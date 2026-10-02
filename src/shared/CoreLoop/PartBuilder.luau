--!strict
-- Human-scale MECH PARTS for the core loop, built from a handful of
-- primitive parts each (cheap enough to weld onto every player): LEGS, ARMS,
-- CHEST and HEAD, styled after the five mech families by tier
--   T1 HWM-04B  boxy plates + yellow hazard stripes + bolts
--   T2 WTK-99   rounded (cylinder) guards + green screen lights
--   T3 VK-01    angular: wedge spikes / fins, amber visor
--   T4 GR-07    heavy: thick plates, tanks and barrels, orange lights
--   T5 BRZ-01   bronze with steel trim bands, cyan glow, a crest
-- coloured with the families' own palettes (MechConfig / TitanConfig
-- variants), so a mixed set looks scruffy and mismatched on purpose.
--
-- Fitting: pieces are sized from the body part they sit on (Size + the R15
-- rig attachments, like ExoBuilder; R6 limbs are split into thirds) and
-- welded to it (Weld, C0 in the body part's space): massless, no collisions /
-- queries / touches, so they follow the animation and never fight the
-- Humanoid. The EXO-1 frame sits on the back / outer sides; these plates go
-- on the front and over the top, so the two overlap a little (scruffy).
--
--   PartBuilder.readBody(char)              -> Body?
--   PartBuilder.attach(body, item, parent)  -> Model (welded pieces)
--   PartBuilder.display(item)               -> Model (standalone loot model,
--       PrimaryPart "Handle"; the pieces hang on invisible proxy limbs)
--   PartBuilder.weapon(id)                  -> Model (PrimaryPart "Handle" =
--       the grip; weld it to a RightHand with PartBuilder.gripOffset)
--   PartBuilder.cell(which)                 -> Model (battery upgrade cargo)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local TitanConfig = require(Shared:WaitForChild("TitanConfig"))
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))

local PartBuilder = {}

PartBuilder.GearTag = "CoreGear"

export type Seg = { part: BasePart, a: Vector3, b: Vector3 } -- part space: a = top joint, b = bottom joint
export type Body = {
	kind: string,
	torso: BasePart,
	pelvis: BasePart?,
	head: BasePart,
	headSize: Vector3,
	segs: { [string]: Seg },
}

type Style = {
	family: string,
	main: Color3,
	panel: Color3,
	dark: Color3,
	accent: Color3,
	glow: Color3,
	trim: Color3,
	heavy: number,
}

------------------------------------------------------------------ reading

local function bodyPart(char: Instance, name: string): BasePart?
	local p = char:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function attPos(part: Instance, name: string): Vector3?
	local a = part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

local function seg15(char: Instance, partName: string, aName: string, bName: string?): Seg?
	local p = bodyPart(char, partName)
	if not p then
		return nil
	end
	local a = attPos(p, aName) or Vector3.new(0, p.Size.Y / 2, 0)
	local b = if bName then attPos(p, bName) or Vector3.new(0, -p.Size.Y / 2, 0) else Vector3.new(0, -p.Size.Y / 2, 0)
	return { part = p, a = a, b = b }
end

local function headSize(head: BasePart): Vector3
	if head:IsA("MeshPart") then
		return head.Size
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	local s = math.min(head.Size.Y, head.Size.Z) * (if mesh then mesh.Scale.Y else 1)
	return Vector3.new(s, s, s)
end

function PartBuilder.readBody(char: Model): Body?
	local head = bodyPart(char, "Head")
	if not head then
		return nil
	end
	local torso = bodyPart(char, "UpperTorso")
	if torso then
		local segs: { [string]: Seg } = {}
		for _, side in { "Right", "Left" } do
			local s = string.sub(side, 1, 1)
			segs[s .. "UA"] = seg15(char, side .. "UpperArm", side .. "ShoulderRigAttachment", side .. "ElbowRigAttachment") :: any
			segs[s .. "LA"] = seg15(char, side .. "LowerArm", side .. "ElbowRigAttachment", side .. "WristRigAttachment") :: any
			segs[s .. "H"] = seg15(char, side .. "Hand", side .. "WristRigAttachment") :: any
			segs[s .. "UL"] = seg15(char, side .. "UpperLeg", side .. "HipRigAttachment", side .. "KneeRigAttachment") :: any
			segs[s .. "LL"] = seg15(char, side .. "LowerLeg", side .. "KneeRigAttachment", side .. "AnkleRigAttachment") :: any
			segs[s .. "F"] = seg15(char, side .. "Foot", side .. "AnkleRigAttachment") :: any
		end
		return { kind = "R15", torso = torso, pelvis = bodyPart(char, "LowerTorso"), head = head, headSize = headSize(head), segs = segs }
	end
	local t6 = bodyPart(char, "Torso")
	if not t6 then
		return nil
	end
	-- R6: split each limb part into thirds
	local segs: { [string]: Seg } = {}
	local function split(p: BasePart?, s: string, names: { string })
		if not p then
			return
		end
		local h = p.Size.Y
		local cuts = { h / 2, h / 6, -h / 6 - h / 9, -h / 2 }
		for i, n in names do
			segs[s .. n] = { part = p, a = Vector3.new(0, cuts[i], 0), b = Vector3.new(0, cuts[i + 1], 0) }
		end
	end
	split(bodyPart(char, "Right Arm"), "R", { "UA", "LA", "H" })
	split(bodyPart(char, "Left Arm"), "L", { "UA", "LA", "H" })
	split(bodyPart(char, "Right Leg"), "R", { "UL", "LL", "F" })
	split(bodyPart(char, "Left Leg"), "L", { "UL", "LL", "F" })
	return { kind = "R6", torso = t6, pelvis = nil, head = head, headSize = headSize(head), segs = segs }
end

------------------------------------------------------------------ style

local function style(item: any): Style
	local tier = math.clamp(item.tier or 1, 1, 5)
	local family = CoreLoopConfig.Tiers[tier].family
	if family == "Titan" then
		local v = TitanConfig.getVariant(item.variant or "Desert")
		local p = v.palette :: any
		return { family = family, main = p.main, panel = p.hi, dark = p.dark, accent = p.trim, glow = p.glow, trim = p.trim, heavy = 1.15 }
	end
	local p = MechConfig.getVariant(item.variant or "Olive").palette
	local glow = if family == "Type99" then Color3.fromRGB(70, 235, 120) elseif family == "Knight" then Color3.fromRGB(255, 196, 70) elseif family == "Gunner" then Color3.fromRGB(255, 150, 50) else p.light
	return {
		family = family,
		main = p.main,
		panel = p.panel,
		dark = p.dark,
		accent = p.accent,
		glow = glow,
		trim = Color3.fromRGB(150, 155, 160),
		heavy = if family == "Gunner" then 1.3 elseif family == "HWM" then 1.05 else 1,
	}
end

------------------------------------------------------------------ pieces

type Ctx = { model: Model, st: Style }

local function make(shape: string, size: Vector3, color: Color3, mat: Enum.Material?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "Corner" then
		p = Instance.new("CornerWedgePart")
	else
		local q = Instance.new("Part")
		if shape == "Cyl" then
			q.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			q.Shape = Enum.PartType.Ball
		end
		p = q
	end
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = size.Magnitude > 0.6
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- A piece welded to `body`, `cf` in body space.
local function add(ctx: Ctx, body: BasePart, shape: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, name: string?): BasePart
	local p = make(shape, size, color, mat)
	p.Name = name or "Plate"
	p.CFrame = body.CFrame * cf
	local w = Instance.new("Weld")
	w.Part0 = body
	w.Part1 = p
	w.C0 = cf
	w.Parent = p
	p.Parent = ctx.model
	return p
end

local function glowPiece(ctx: Ctx, body: BasePart, shape: string, size: Vector3, cf: CFrame)
	local p = add(ctx, body, shape, size, cf, ctx.st.glow, Enum.Material.Neon, "Light")
	p.CastShadow = false
end

-- Frame of a segment at fraction t (0 = bottom joint, 1 = top joint): +Y up
-- the limb, +X the part's right, -Z forward.
local function frame(sg: Seg, t: number): CFrame
	local up = sg.a - sg.b
	if up.Magnitude < 1e-3 then
		up = Vector3.yAxis
	end
	up = up.Unit
	local right = Vector3.xAxis - up * up:Dot(Vector3.xAxis)
	right = if right.Magnitude < 1e-3 then Vector3.zAxis else right.Unit
	return CFrame.fromMatrix(sg.b:Lerp(sg.a, t), right, up)
end

local function len(sg: Seg): number
	return math.max((sg.a - sg.b).Magnitude, 0.2)
end

-- a limb guard (gauntlet / shin): box, or cylinder for the round families
local function guard(ctx: Ctx, sg: Seg, t: number, w: number, h: number, d: number, color: Color3)
	local cf = frame(sg, t)
	local fam = ctx.st.family
	if fam == "Type99" or fam == "Gunner" then
		local dia = math.max(w, d)
		add(ctx, sg.part, "Cyl", Vector3.new(h, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.SmoothPlastic, "Guard")
	else
		add(ctx, sg.part, "Block", Vector3.new(w, h, d), cf, color, Enum.Material.SmoothPlastic, "Guard")
	end
end

-- family signature trim around a limb (band / stripe / spike)
local function band(ctx: Ctx, sg: Seg, t: number, w: number, d: number, s: number)
	local st = ctx.st
	local cf = frame(sg, t)
	if st.family == "HWM" then
		add(ctx, sg.part, "Block", Vector3.new(w + 0.04, 0.14, d + 0.04), cf, st.accent, Enum.Material.SmoothPlastic, "Stripe").CastShadow = false
	elseif st.family == "Type99" then
		glowPiece(ctx, sg.part, "Block", Vector3.new(w * 0.5, 0.1, 0.06), cf * CFrame.new(0, 0, -d / 2 - 0.02))
	elseif st.family == "Knight" then
		add(ctx, sg.part, "Wedge", Vector3.new(0.14, 0.5, 0.45), cf * CFrame.new(s * (w / 2 + 0.06), 0.1, 0), st.accent, Enum.Material.Metal, "Spike")
	elseif st.family == "Gunner" then
		add(ctx, sg.part, "Cyl", Vector3.new(0.5, 0.22, 0.22), cf * CFrame.new(s * (w / 2 + 0.12), 0, 0.1) * CFrame.Angles(0, 0, math.pi / 2), st.dark, Enum.Material.Metal, "Tube")
	else
		local dia = math.max(w, d) + 0.06
		add(ctx, sg.part, "Cyl", Vector3.new(0.12, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), st.trim, Enum.Material.Metal, "Trim").CastShadow = false
	end
end

local function disc(ctx: Ctx, body: BasePart, pos: CFrame, dia: number, color: Color3)
	-- a hinge disc on the limb's X axis
	add(ctx, body, "Cyl", Vector3.new(0.14, dia, dia), pos, color, Enum.Material.Metal, "Hinge")
end

------------------------------------------------------------------ slots

local function buildLegs(ctx: Ctx, body: Body)
	local st = ctx.st
	local hv = st.heavy
	for _, side in { "R", "L" } do
		local s = if side == "R" then 1 else -1
		local ul, ll, ft = body.segs[side .. "UL"], body.segs[side .. "LL"], body.segs[side .. "F"]
		if ul then
			local w, d, l = ul.part.Size.X, ul.part.Size.Z, len(ul)
			-- thigh plate over the front + outer side plate
			add(ctx, ul.part, "Block", Vector3.new(w * 0.95 + 0.1, l * 0.62, 0.22 * hv), frame(ul, 0.55) * CFrame.new(0, 0, -d / 2 - 0.1 * hv), st.main, nil, "Thigh")
			add(ctx, ul.part, "Block", Vector3.new(0.2 * hv, l * 0.55, d * 0.85), frame(ul, 0.58) * CFrame.new(s * (w / 2 + 0.09 * hv), 0, 0), st.panel, nil, "ThighSide")
			band(ctx, ul, 0.32, w * 0.95 + 0.1, d + 0.2, s)
		end
		if ll then
			local w, d, l = ll.part.Size.X, ll.part.Size.Z, len(ll)
			-- knee cap (front) + hinge disc (outer side)
			local knee = frame(ll, 0.96)
			if st.family == "Knight" then
				add(ctx, ll.part, "Wedge", Vector3.new(w * 0.8, 0.55, 0.35), knee * CFrame.new(0, 0.12, -d / 2 - 0.2) * CFrame.Angles(0, math.pi, 0), st.accent, Enum.Material.Metal, "KneeCap")
			elseif st.family == "Type99" or st.family == "Gunner" then
				add(ctx, ll.part, "Ball", Vector3.new(w * 0.75, w * 0.75, w * 0.75), knee * CFrame.new(0, 0, -d / 2 + 0.05), st.dark, Enum.Material.Metal, "KneeCap")
			else
				add(ctx, ll.part, "Block", Vector3.new(w * 0.8, 0.5, 0.3), knee * CFrame.new(0, 0, -d / 2 - 0.12), st.dark, Enum.Material.Metal, "KneeCap")
			end
			disc(ctx, ll.part, knee * CFrame.new(s * (w / 2 + 0.08), 0, 0), w * 0.6, st.dark)
			-- shin guard
			guard(ctx, ll, 0.45, w + 0.18 * hv, l * 0.7, d + 0.18 * hv, st.main)
			band(ctx, ll, 0.62, w + 0.22 * hv, d + 0.22 * hv, s)
			if st.family == "Gunner" or st.family == "Titan" then
				glowPiece(ctx, ll.part, "Block", Vector3.new(0.12, l * 0.35, 0.06), frame(ll, 0.4) * CFrame.new(0, 0, -(d + 0.18 * hv) / 2 - 0.04))
			end
		end
		if ft then
			local fs = ft.part.Size
			-- boot shell + toe cap + heel light
			local c = frame(ft, 0) * CFrame.new(0, 0, 0)
			local fc = CFrame.new(0, 0, 0)
			if body.kind == "R15" then
				fc = CFrame.new(0, -fs.Y * 0.05, -fs.Z * 0.05)
			else
				fc = c
			end
			local shell = Vector3.new(fs.X + 0.22 * hv, math.max(fs.Y, 0.35) + 0.18, fs.Z * 1.05 + 0.2)
			add(ctx, ft.part, "Block", shell, fc, st.panel, nil, "Boot")
			local toe = fc * CFrame.new(0, shell.Y * 0.15, -shell.Z / 2 - 0.12)
			if st.family == "Knight" then
				add(ctx, ft.part, "Wedge", Vector3.new(shell.X * 0.9, shell.Y * 0.7, 0.5), toe * CFrame.Angles(0, math.pi, 0), st.accent, Enum.Material.Metal, "Toe")
			else
				add(ctx, ft.part, "Block", Vector3.new(shell.X * 0.9, shell.Y * 0.7, 0.3), toe, st.dark, Enum.Material.Metal, "Toe")
			end
			glowPiece(ctx, ft.part, "Block", Vector3.new(shell.X * 0.5, 0.08, 0.06), fc * CFrame.new(0, shell.Y * 0.2, shell.Z / 2 + 0.02))
		end
	end
	-- hip tassets on the pelvis sides
	local pel = body.pelvis
	if pel then
		for _, s in { 1, -1 } do
			add(ctx, pel, "Block", Vector3.new(0.22 * hv, pel.Size.Y * 1.6, pel.Size.Z * 0.8), CFrame.new(s * (pel.Size.X / 2 + 0.12), -pel.Size.Y * 0.3, 0), st.main, nil, "Tasset")
		end
		add(ctx, pel, "Block", Vector3.new(pel.Size.X * 0.5, pel.Size.Y * 1.2, 0.2), CFrame.new(0, -pel.Size.Y * 0.2, -pel.Size.Z / 2 - 0.1), st.dark, Enum.Material.Metal, "Codpiece")
	end
end

local function buildArms(ctx: Ctx, body: Body)
	local st = ctx.st
	local hv = st.heavy
	for _, side in { "R", "L" } do
		local s = if side == "R" then 1 else -1
		local ua, la, hd = body.segs[side .. "UA"], body.segs[side .. "LA"], body.segs[side .. "H"]
		if ua then
			local w, d, l = ua.part.Size.X, ua.part.Size.Z, len(ua)
			-- shoulder pad: a big plate over the top, tilted outward
			local top = frame(ua, 1) * CFrame.new(s * 0.08, 0.18, 0) * CFrame.Angles(0, 0, -s * math.rad(18))
			local pad = Vector3.new(w * 1.55 * hv, 0.32 * hv, d * 1.6)
			if st.family == "Type99" or st.family == "Gunner" then
				add(ctx, ua.part, "Cyl", Vector3.new(d * 1.4, w * 1.05 * hv, w * 1.05 * hv), top * CFrame.new(0, -0.1, 0) * CFrame.Angles(0, math.pi / 2, 0), st.main, nil, "Pad")
			else
				add(ctx, ua.part, "Block", pad, top, st.main, nil, "Pad")
				add(ctx, ua.part, "Block", Vector3.new(0.18, l * 0.35, d * 1.5), top * CFrame.new(s * pad.X / 2, -l * 0.17, 0), st.panel, nil, "PadLip")
			end
			if st.family == "Knight" then
				add(ctx, ua.part, "Wedge", Vector3.new(0.16, 0.7, d * 1.1), top * CFrame.new(s * w * 0.2, 0.5, 0), st.accent, Enum.Material.Metal, "Fin")
			elseif st.family == "HWM" then
				add(ctx, ua.part, "Block", Vector3.new(pad.X + 0.02, 0.06, 0.3), top * CFrame.new(0, pad.Y / 2 + 0.01, 0), st.accent, nil, "Stripe").CastShadow = false
			elseif st.family == "Titan" then
				add(ctx, ua.part, "Block", Vector3.new(pad.X + 0.04, 0.1, pad.Z + 0.04), top * CFrame.new(0, -pad.Y / 2, 0), st.trim, Enum.Material.Metal, "Trim").CastShadow = false
			end
			-- outer upper-arm plate
			add(ctx, ua.part, "Block", Vector3.new(0.2 * hv, l * 0.55, d * 0.9), frame(ua, 0.45) * CFrame.new(s * (w / 2 + 0.09), 0, 0), st.panel, nil, "Bicep")
		end
		if la then
			local w, d, l = la.part.Size.X, la.part.Size.Z, len(la)
			disc(ctx, la.part, frame(la, 0.98) * CFrame.new(s * (w / 2 + 0.08), 0, 0), w * 0.7, st.dark)
			-- chunky gauntlet
			guard(ctx, la, 0.42, w * 1.4 * hv, l * 0.8, d * 1.4 * hv, st.main)
			band(ctx, la, 0.66, w * 1.45 * hv, d * 1.45 * hv, s)
			glowPiece(ctx, la.part, "Block", Vector3.new(0.06, l * 0.4, 0.12), frame(la, 0.42) * CFrame.new(s * (w * 0.7 * hv + 0.03), 0, 0))
		end
		if hd then
			local hs = hd.part.Size
			-- an oversized mech fist shell round the hand
			local fist = Vector3.new(hs.X * 1.35 + 0.12, math.max(hs.Y, 0.5) * 0.85, hs.Z * 1.35 + 0.12) * Vector3.new(hv, 1, hv)
			add(ctx, hd.part, "Block", fist, frame(hd, 0.45), st.dark, Enum.Material.Metal, "Fist")
			add(ctx, hd.part, "Block", Vector3.new(fist.X * 0.9, 0.16, fist.Z + 0.06), frame(hd, 0.45) * CFrame.new(0, -fist.Y * 0.32, 0), st.accent, Enum.Material.Metal, "Knuckles")
		end
	end
end

local function buildChest(ctx: Ctx, body: Body)
	local st = ctx.st
	local hv = st.heavy
	local t = body.torso
	local W, H, D = t.Size.X, t.Size.Y, t.Size.Z
	-- breast plate (front); angular families get a prow of two wedges
	local front = CFrame.new(0, H * 0.08, -D / 2 - 0.14 * hv)
	if st.family == "Knight" or st.family == "Titan" then
		for _, s in { 1, -1 } do
			add(ctx, t, "Wedge", Vector3.new(0.26 * hv, H * 0.6, W * 0.46), front * CFrame.new(s * W * 0.23, 0, -0.08) * CFrame.Angles(0, s * math.pi / 2, 0) * CFrame.Angles(0, 0, 0), st.main, nil, "Prow")
		end
		add(ctx, t, "Block", Vector3.new(W * 0.9, H * 0.6, 0.22), front * CFrame.new(0, 0, 0.1), st.panel, nil, "Breast")
	else
		add(ctx, t, "Block", Vector3.new(W * 0.92, H * 0.62, 0.28 * hv), front, st.main, nil, "Breast")
	end
	-- reactor core light
	if st.family == "Type99" or st.family == "Gunner" then
		add(ctx, t, "Cyl", Vector3.new(0.12, H * 0.28, H * 0.28), front * CFrame.new(0, 0, -0.2 * hv) * CFrame.Angles(0, math.pi / 2, 0), st.dark, Enum.Material.Metal, "CoreRing")
		glowPiece(ctx, t, "Cyl", Vector3.new(0.14, H * 0.18, H * 0.18), front * CFrame.new(0, 0, -0.22 * hv) * CFrame.Angles(0, math.pi / 2, 0))
	else
		glowPiece(ctx, t, "Block", Vector3.new(W * 0.24, H * 0.14, 0.08), front * CFrame.new(0, 0, -0.16 * hv))
	end
	if st.family == "HWM" then
		for _, s in { 1, -1 } do
			add(ctx, t, "Block", Vector3.new(W * 0.1, H * 0.5, 0.06), front * CFrame.new(s * W * 0.36, 0, -0.16 * hv) * CFrame.Angles(0, 0, s * 0.5), st.accent, nil, "Hazard").CastShadow = false
		end
	end
	-- collar yoke over the top + side plates
	add(ctx, t, "Block", Vector3.new(W * 1.02, 0.3 * hv, D * 1.15), CFrame.new(0, H / 2 + 0.05, 0), st.dark, Enum.Material.Metal, "Yoke")
	for _, s in { 1, -1 } do
		add(ctx, t, "Block", Vector3.new(0.18 * hv, H * 0.6, D * 0.9), CFrame.new(s * (W / 2 + 0.08), -H * 0.05, 0), st.panel, nil, "Flank")
	end
	-- power pack on the back (behind the exo spine): two cells
	local back = CFrame.new(0, H * 0.05, D / 2 + 0.75)
	if st.family == "Gunner" or st.family == "Type99" then
		for _, s in { 1, -1 } do
			add(ctx, t, "Cyl", Vector3.new(H * 0.85, 0.55 * hv, 0.55 * hv), back * CFrame.new(s * W * 0.2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), st.main, nil, "Tank")
		end
	else
		add(ctx, t, "Block", Vector3.new(W * 0.62, H * 0.75, 0.55 * hv), back, st.main, nil, "Pack")
	end
	for _, s in { 1, -1 } do
		glowPiece(ctx, t, "Block", Vector3.new(0.14, H * 0.4, 0.08), back * CFrame.new(s * W * 0.12, 0, 0.32 * hv))
	end
	-- abdomen plates
	local pel = body.pelvis
	if pel then
		add(ctx, pel, "Block", Vector3.new(pel.Size.X * 0.7, pel.Size.Y * 1.4, 0.22), CFrame.new(0, pel.Size.Y * 0.4, -pel.Size.Z / 2 - 0.1), st.panel, nil, "Abs")
	end
end

local function buildHead(ctx: Ctx, body: Body)
	local st = ctx.st
	local head = body.head
	local hs = body.headSize
	local W, H, D = hs.X * 1.12 + 0.16, hs.Y, hs.Z * 1.12 + 0.16
	-- dome / cap
	if st.family == "Type99" or st.family == "Gunner" then
		add(ctx, head, "Ball", Vector3.new(W, W, D) * 1.02, CFrame.new(0, H * 0.18, 0.02), st.main, nil, "Dome")
	else
		add(ctx, head, "Block", Vector3.new(W, H * 0.42, D), CFrame.new(0, H * 0.34, 0.02), st.main, nil, "Cap")
	end
	-- side plates (ear pods) + back plate
	for _, s in { 1, -1 } do
		add(ctx, head, "Block", Vector3.new(0.16, H * 0.55, D * 0.75), CFrame.new(s * (W / 2 + 0.02), H * 0.02, 0.06), st.panel, nil, "Cheek")
		add(ctx, head, "Cyl", Vector3.new(0.14, H * 0.32, H * 0.32), CFrame.new(s * (W / 2 + 0.1), 0, 0.05), st.dark, Enum.Material.Metal, "EarPod")
	end
	-- brow + visor bar across the eyes
	add(ctx, head, "Block", Vector3.new(W * 0.98, 0.14, 0.2), CFrame.new(0, H * 0.14, -D / 2 - 0.02), st.dark, Enum.Material.Metal, "Brow")
	local visor = add(ctx, head, "Block", Vector3.new(W * 0.86, 0.1, 0.08), CFrame.new(0, H * 0.05, -D / 2 - 0.04), st.glow, Enum.Material.Neon, "Visor")
	visor.CastShadow = false
	visor.Transparency = 0.15
	-- family signatures
	if st.family == "HWM" then
		for _, s in { 1, -1 } do
			glowPiece(ctx, head, "Cyl", Vector3.new(0.1, 0.22, 0.22), CFrame.new(s * W * 0.25, H * 0.56, -D * 0.2) * CFrame.Angles(0, math.pi / 2, 0))
			add(ctx, head, "Block", Vector3.new(0.3, 0.2, 0.3), CFrame.new(s * W * 0.25, H * 0.56, -D * 0.1), st.dark, Enum.Material.Metal, "Lamp")
		end
		add(ctx, head, "Block", Vector3.new(W + 0.02, 0.08, 0.3), CFrame.new(0, H * 0.4, -D / 2 + 0.1), st.accent, nil, "Stripe").CastShadow = false
	elseif st.family == "Type99" then
		glowPiece(ctx, head, "Ball", Vector3.new(0.34, 0.34, 0.34), CFrame.new(W * 0.42, H * 0.36, -D * 0.12))
	elseif st.family == "Knight" then
		add(ctx, head, "Wedge", Vector3.new(0.14, H * 0.5, D * 0.9), CFrame.new(0, H * 0.75, 0.05), st.accent, Enum.Material.Metal, "Fin")
		add(ctx, head, "Wedge", Vector3.new(W * 0.7, 0.3, 0.3), CFrame.new(0, -H * 0.12, -D / 2 - 0.05) * CFrame.Angles(math.pi, 0, 0), st.dark, Enum.Material.Metal, "Chin")
	elseif st.family == "Gunner" then
		add(ctx, head, "Cyl", Vector3.new(1.1, 0.06, 0.06), CFrame.new(-W * 0.35, H * 0.8, 0.15) * CFrame.Angles(0, 0, math.pi / 2), st.trim, Enum.Material.Metal, "Antenna")
		add(ctx, head, "Cyl", Vector3.new(0.6, 0.3, 0.3), CFrame.new(W * 0.45, H * 0.2, -D * 0.2) * CFrame.Angles(0, math.pi / 2, 0), st.dark, Enum.Material.Metal, "Rangefinder")
		glowPiece(ctx, head, "Cyl", Vector3.new(0.04, 0.2, 0.2), CFrame.new(W * 0.45, H * 0.2, -D * 0.2 - 0.31) * CFrame.Angles(0, math.pi / 2, 0))
	else
		add(ctx, head, "Wedge", Vector3.new(0.18, H * 0.55, D * 1.05), CFrame.new(0, H * 0.78, 0.1), st.trim, Enum.Material.Metal, "Crest")
		add(ctx, head, "Block", Vector3.new(W + 0.04, 0.1, D + 0.04), CFrame.new(0, H * 0.14, 0.02), st.trim, Enum.Material.Metal, "Trim").CastShadow = false
	end
end

local BUILDERS = { Legs = buildLegs, Arms = buildArms, Chest = buildChest, Head = buildHead }

-- Welds the item's pieces onto a body; returns the model (parented to `parent`).
function PartBuilder.attach(body: Body, item: any, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Gear_" .. tostring(item.slot)
	model:SetAttribute("Slot", item.slot)
	model:SetAttribute("Tier", item.tier)
	local ctx: Ctx = { model = model, st = style(item) }
	local fn = BUILDERS[item.slot]
	if fn then
		fn(ctx, body)
	end
	model.Parent = parent
	return model
end

------------------------------------------------------------------ display (loot)

-- Invisible proxy limbs of a standard R15 body (sizes ~ the default blocky
-- avatar), arranged like a standing body so the pieces sit as they would on
-- a player. The loot model shows only the slot's pieces.
local function proxy(model: Model, root: BasePart, name: string, size: Vector3, pos: Vector3): BasePart
	local p = make("Block", size, Color3.new(), nil)
	p.Name = name
	p.Transparency = 1
	p.CFrame = root.CFrame * CFrame.new(pos)
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = CFrame.new(pos)
	w.Parent = p
	p.Parent = model
	return p
end

local function proxyBody(model: Model, root: BasePart): Body
	-- y relative to the root (the display's centre)
	local segs: { [string]: Seg } = {}
	local torso = proxy(model, root, "PxTorso", Vector3.new(1.9, 1.5, 1), Vector3.new(0, 1.35, 0))
	local pelvis = proxy(model, root, "PxPelvis", Vector3.new(1.9, 0.4, 1), Vector3.new(0, 0.4, 0))
	local head = proxy(model, root, "PxHead", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 2.75, 0))
	for _, side in { "R", "L" } do
		local s = if side == "R" then 1 else -1
		local ua = proxy(model, root, "Px" .. side .. "UA", Vector3.new(0.9, 1.3, 0.9), Vector3.new(s * 1.45, 1.4, 0))
		local la = proxy(model, root, "Px" .. side .. "LA", Vector3.new(0.85, 1.1, 0.85), Vector3.new(s * 1.45, 0.25, 0))
		local hd = proxy(model, root, "Px" .. side .. "H", Vector3.new(0.8, 0.6, 0.8), Vector3.new(s * 1.45, -0.55, 0))
		local ul = proxy(model, root, "Px" .. side .. "UL", Vector3.new(0.9, 1.3, 0.9), Vector3.new(s * 0.5, -0.45, 0))
		local ll = proxy(model, root, "Px" .. side .. "LL", Vector3.new(0.85, 1.25, 0.85), Vector3.new(s * 0.5, -1.7, 0))
		local ft = proxy(model, root, "Px" .. side .. "F", Vector3.new(0.85, 0.35, 1.1), Vector3.new(s * 0.5, -2.5, -0.1))
		segs[side .. "UA"] = { part = ua, a = Vector3.new(0, 0.5, 0), b = Vector3.new(0, -0.6, 0) }
		segs[side .. "LA"] = { part = la, a = Vector3.new(0, 0.5, 0), b = Vector3.new(0, -0.5, 0) }
		segs[side .. "H"] = { part = hd, a = Vector3.new(0, 0.25, 0), b = Vector3.new(0, -0.3, 0) }
		segs[side .. "UL"] = { part = ul, a = Vector3.new(0, 0.6, 0), b = Vector3.new(0, -0.6, 0) }
		segs[side .. "LL"] = { part = ll, a = Vector3.new(0, 0.6, 0), b = Vector3.new(0, -0.55, 0) }
		segs[side .. "F"] = { part = ft, a = Vector3.new(0, 0.15, 0), b = Vector3.new(0, -0.17, 0) }
	end
	return { kind = "R15", torso = torso, pelvis = pelvis, head = head, headSize = head.Size, segs = segs }
end

-- The slot's pieces centred on the model's Handle (anchor it to place it).
local DISPLAY_CENTRE = { Legs = Vector3.new(0, -1.1, 0), Arms = Vector3.new(0, 0.5, 0), Chest = Vector3.new(0, 1.2, 0), Head = Vector3.new(0, 2.75, 0) }
function PartBuilder.display(item: any): Model
	local model = Instance.new("Model")
	model.Name = "Loot_" .. tostring(item.slot)
	local handle = make("Block", Vector3.new(1, 1, 1), Color3.new(), nil)
	handle.Name = "Handle"
	handle.Transparency = 1
	handle.Parent = model
	model.PrimaryPart = handle
	-- proxies hang off a hidden "body root" offset so the slot centre lands on the handle
	local c = DISPLAY_CENTRE[item.slot] or Vector3.zero
	local root = proxy(model, handle, "PxRoot", Vector3.new(0.2, 0.2, 0.2), -c)
	local body = proxyBody(model, root)
	local gear = PartBuilder.attach(body, item, model)
	-- flatten: pieces straight into the model (they stay welded)
	for _, p in gear:GetChildren() do
		p.Parent = model
	end
	gear:Destroy()
	return model
end

------------------------------------------------------------------ weapons / cells

-- Grip offset (RightHand space): the weapon's long axis runs down the hand
-- (-Y), so a punch / raised arm points it forward.
PartBuilder.gripOffset = CFrame.new(0, -0.15, 0) * CFrame.Angles(0, 0, math.pi / 2) -- handle +X -> hand +Y

function PartBuilder.weapon(id: string): Model
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. id
	local handle = make("Cyl", Vector3.new(0.7, 0.32, 0.32), Color3.fromRGB(30, 30, 32), Enum.Material.Metal)
	handle.Name = "Handle"
	handle.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	handle.Parent = model
	model.PrimaryPart = handle
	local ctx: Ctx = { model = model, st = style({ tier = 1, variant = "Olive" }) }
	local w = CoreLoopConfig.Weapons[id]
	local col = if w then w.color else Color3.new(1, 1, 1)
	-- handle's own space: X is the long axis (cylinder); use a helper frame
	local H = CFrame.Angles(0, 0, -math.pi / 2) -- back to "Y up" in the grip's frame
	if id == "Blade" then
		add(ctx, handle, "Block", Vector3.new(0.9, 0.18, 0.5), H * CFrame.new(0, -0.45, 0), Color3.fromRGB(60, 62, 66), Enum.Material.Metal, "Guard")
		add(ctx, handle, "Wedge", Vector3.new(0.12, 3.4, 0.62), H * CFrame.new(0, -2.25, 0) * CFrame.Angles(math.pi, 0, 0), Color3.fromRGB(170, 175, 180), Enum.Material.Metal, "Blade")
		local edge = add(ctx, handle, "Block", Vector3.new(0.06, 3.0, 0.08), H * CFrame.new(0, -2.1, -0.3), col, Enum.Material.Neon, "Edge")
		edge.CastShadow = false
		add(ctx, handle, "Block", Vector3.new(0.14, 0.9, 0.3), H * CFrame.new(0, -1.0, 0.18), Color3.fromRGB(140, 78, 48), Enum.Material.CorrodedMetal, "Patch")
	elseif id == "Hammer" then
		add(ctx, handle, "Cyl", Vector3.new(2.6, 0.28, 0.28), H * CFrame.new(0, -1.3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 72, 76), Enum.Material.Metal, "Shaft")
		local headCF = H * CFrame.new(0, -2.75, 0)
		add(ctx, handle, "Block", Vector3.new(1.0, 1.1, 1.9), headCF, Color3.fromRGB(62, 65, 70), Enum.Material.DiamondPlate, "Head")
		add(ctx, handle, "Cyl", Vector3.new(0.5, 1.15, 1.15), headCF * CFrame.new(0, 0, -1.15) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(150, 155, 160), Enum.Material.Metal, "Face")
		add(ctx, handle, "Cyl", Vector3.new(0.3, 0.7, 0.7), headCF * CFrame.new(0, 0, 1.05) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(236, 205, 40), Enum.Material.Metal, "Piston")
		local glow = add(ctx, handle, "Block", Vector3.new(1.02, 0.14, 1.92), headCF, col, Enum.Material.Neon, "Glow")
		glow.CastShadow = false
	elseif id == "Rivet" then
		local body = H * CFrame.new(0, -0.6, 0)
		add(ctx, handle, "Block", Vector3.new(0.8, 1.3, 1.0), body, Color3.fromRGB(62, 65, 70), Enum.Material.Metal, "Body")
		add(ctx, handle, "Cyl", Vector3.new(1.4, 0.36, 0.36), body * CFrame.new(0, -1.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 155, 160), Enum.Material.Metal, "Barrel")
		add(ctx, handle, "Block", Vector3.new(0.5, 0.7, 0.5), body * CFrame.new(0, 0.1, 0.65), Color3.fromRGB(236, 205, 40), Enum.Material.Metal, "Mag")
		local tip = add(ctx, handle, "Cyl", Vector3.new(0.1, 0.4, 0.4), body * CFrame.new(0, -1.95, 0) * CFrame.Angles(0, 0, math.pi / 2), col, Enum.Material.Neon, "Muzzle")
		tip.CastShadow = false
	end
	return model
end

function PartBuilder.cell(which: string): Model
	local model = Instance.new("Model")
	model.Name = "Cell_" .. which
	local col = if which == "Coil" then Color3.fromRGB(80, 200, 255) else Color3.fromRGB(90, 255, 140)
	local handle = make("Cyl", Vector3.new(1.8, 1.2, 1.2), Color3.fromRGB(34, 35, 38), Enum.Material.Metal)
	handle.Name = "Handle"
	handle.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	handle.Parent = model
	model.PrimaryPart = handle
	local ctx: Ctx = { model = model, st = style({ tier = 1 }) }
	local core = add(ctx, handle, "Cyl", Vector3.new(1.3, 1.26, 1.26), CFrame.new(), col, Enum.Material.Neon, "Core")
	core.Transparency = 0.25
	for _, x in { -0.8, 0.8 } do
		add(ctx, handle, "Cyl", Vector3.new(0.25, 1.4, 1.4), CFrame.new(x, 0, 0), Color3.fromRGB(236, 205, 40), Enum.Material.Metal, "Cap")
	end
	if which == "Coil" then
		for i = -1, 1 do
			add(ctx, handle, "Cyl", Vector3.new(0.12, 1.5, 1.5), CFrame.new(i * 0.35, 0, 0), Color3.fromRGB(184, 115, 51), Enum.Material.Metal, "Winding")
		end
	end
	add(ctx, handle, "Block", Vector3.new(0.3, 0.3, 0.3), CFrame.new(1.05, 0, 0), Color3.fromRGB(150, 155, 160), Enum.Material.Metal, "Terminal")
	return model
end

return PartBuilder
