--!strict
-- Builds the EXO-1 exoskeleton (Elysium-style back rig) out of primitive
-- parts. Two forms:
--   * WORN (buildWorn): pieces welded to the wearer's own body parts, each
--     sized from that part's Size and placed from its rig attachments, so the
--     exo follows the character's animation and fits tall / short / wide
--     avatars. R15 uses the *RigAttachments; R6 maps the same pieces onto
--     Torso / Head / Right Arm / Right Leg.
--   * FRAME (buildFrame): for avatars that can't wear it (no humanoid limbs,
--     creatures, very short avatars). A standalone walking frame of standard
--     human height, centred on the HumanoidRootPart; the rider is hoisted
--     (Humanoid.HipHeight raised) into the frame's torso cage, its body centre
--     at the cage centre (between the frame's waist and shoulders), standing
--     on a cradle. The frame's joints are Motor6Ds animated by every client
--     (ExoAnimator).
--
-- DESIGN NOTE (worn form). Sizes are fractions of the body part they sit on
-- (W/H/D = part Size X/Y/Z, len = joint-to-joint length); k = UpperTorso
-- width / 1.94 (1 on a standard avatar) scales every thickness.
--   Spine (UpperTorso back):  column 0.16k x (neck..waist) x 0.14k, gunmetal
--     4 vertebra blocks 0.22W wide, black; green light strip down the spine
--     two thin spine pistons either side (steel); shoulder-blade plates
--     0.28W x 0.32H, black; shoulder yoke bar 0.64W, gunmetal
--   Shoulders: pivot hub over each blade (cylinder 0.34k, black, green cap),
--     brace out to the shoulder joint; shoulder bar (0.15k, gunmetal) from
--     the hub arching over the top of the shoulder down onto the chest unit
--   Chest (UpperTorso front): sternum unit 0.4W x 0.26H (black) with a
--     layered gunmetal plate, angled lip, 3 green lights + strip, two steel
--     ports; hose loops unit -> shoulder bars; green data line over the
--     shoulder to the spine; rib straps (black) unit -> side -> spine
--   Lower spine + hip belt (LowerTorso): belt ring 0.22k+ tall round the
--     pelvis (black), back housing 0.4W (gunmetal, green slit), front buckle
--     (steel), right hip side plate; lower spine bar up to the waist joint
--   Skull (Head back): centre plate 0.5W x 0.55H + two wrap-around side
--     plates (gunmetal / black), sensor port (steel cylinder, green lens),
--     neck strut + twin rod down to a socket ball on top of the spine;
--     green cable spine -> skull
--   Right arm: deltoid plate + shoulder hub, outer strut shoulder -> elbow,
--     upper cuff; elbow hinge (two concentric discs on the elbow axis, green
--     cap); outer forearm strut elbow -> wrist; wrist cuff ring; back-of-hand
--     plate + knuckle bar; elbow piston (live, see updatePiston) and two
--     cables (shoulder hub -> arm, upper arm -> forearm)
--   Left arm (lighter, ExoConfig.LeftArm): hub, struts, elbow disc, cuff
--   Left knee (ExoConfig.LeftKneeCap): hinge discs + knee cap + side link
--   Right leg (front): hip hinge disc on the outer side of the hip axis,
--     strut down the FRONT of the thigh + thigh plate (green strip), side
--     link to the knee hinge (outer side, on the knee axis), kneepad, shin
--     link + front shin strut + plate, ankle cuff ring; knee piston; cable
--     hip -> knee
-- Snug fit: shoulder / arm pieces sit FIT_GAP (0.04k) off the avatar's real
-- surface, read from its attachments (see "snug fit" below), so slim bodies
-- get no air gap and broad ones don't clip.
-- Joint rule: every strut belongs to ONE body part and ends exactly on that
-- part's rig attachment, shifted only along the joint's hinge axis (X), so
-- the two sides of an elbow / knee / hip hinge stay together when it bends.
-- Pistons that cross a joint are re-aimed every frame by the clients.
-- Colours / materials: gunmetal Metal (frame), black SmoothPlastic (plates),
-- steel Metal (rods / pins), green Neon (lights, pulsed by ExoAnimator),
-- black Beams (cables). All parts: Massless, CanCollide / CanQuery /
-- CanTouch false, welded (Weld, C0 in the body part's space).

local CollectionService = game:GetService("CollectionService")

local ExoConfig = require(script.Parent.ExoConfig)

local ExoBuilder = {}

ExoBuilder.ModelName = "Exoskeleton"
ExoBuilder.LightTag = "ExoLight"
ExoBuilder.PistonTag = "ExoPiston"
ExoBuilder.FrameTag = "ExoFrame"

local COL = ExoConfig.Colors
local F = ExoConfig.Frame

type ColorKey = "frame" | "dark" | "steel" | "glow"

export type Segment = { part: BasePart, a: Vector3, b: Vector3 } -- a = upper joint, b = lower joint (part space)
export type Arm = { upper: Segment, lower: Segment, hand: Segment, top: Vector3? } -- top: shoulder accessory point (UpperArm space)
export type Rig = {
	kind: string, -- "R15" | "R6"
	k: number,
	torso: BasePart,
	neck: Vector3, -- torso space
	waist: Vector3, -- torso space: bottom of the spine
	shoulders: { [string]: Vector3 }, -- torso space
	pelvis: BasePart,
	pelvisTop: Vector3, -- pelvis space: waist joint
	hip: Vector3, -- pelvis space: right hip joint
	head: BasePart,
	headSize: Vector3, -- visible head size
	headNeck: Vector3, -- head space
	arms: { [string]: Arm },
	leg: { upper: Segment, lower: Segment, foot: Segment },
	legL: { upper: Segment, lower: Segment }?, -- left leg (knee cap only)
	-- surface hints from the body's accessory attachments (R15; authored on the
	-- mesh surface by the body's creator), torso space
	collar: { [string]: Vector3 }?, -- top of each shoulder
	bodyBack: Vector3?, -- back surface (mid back)
	bodyFront: Vector3?, -- chest surface
}
export type Measure = {
	ground: number, -- world Y of the feet
	rootH: number, -- root centre above the ground the Humanoid holds it over
	feet: number, -- root centre above the lowest body part (the visible feet)
	headH: number, -- head centre above the feet
	height: number, -- feet to top
	width: number, -- root space X extent
	depth: number, -- root space Z extent
	halfW: number, -- farthest body point from the root, sideways (root space X)
	halfD: number, -- farthest body point from the root, front / back (root space Z)
	centerY: number, -- body centre (feet..top midpoint) relative to the root centre
}

----------------------------------------------------------------- reading

local function bodyPart(char: Instance, name: string): BasePart?
	local p = char:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function attPos(part: Instance, name: string): Vector3?
	local a = part:FindFirstChild(name)
	if a and a:IsA("Attachment") then
		return a.Position
	end
	return nil
end

local function seg15(char: Instance, partName: string, aName: string, bName: string?): Segment?
	local p = bodyPart(char, partName)
	if not p then
		return nil
	end
	local a = attPos(p, aName)
	if not a then
		return nil
	end
	local b = if bName then attPos(p, bName) else a - Vector3.new(0, p.Size.Y * 0.8, 0)
	if not b then
		return nil
	end
	return { part = p, a = a, b = b }
end

-- The head's visible size: MeshPart bounds, or a classic head's mesh.
local function headSize(head: BasePart): Vector3
	if head:IsA("MeshPart") then
		return head.Size
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	local s = math.min(head.Size.Y, head.Size.Z) * (if mesh then mesh.Scale.Y else 1)
	return Vector3.new(s, s, s)
end

local function jointC0(torso: BasePart, name: string): Vector3?
	local m = torso:FindFirstChild(name)
	if m and m:IsA("Motor6D") then
		return m.C0.Position
	end
	return nil
end

local function readR15(char: Model): Rig?
	local torso, pelvis, head = bodyPart(char, "UpperTorso"), bodyPart(char, "LowerTorso"), bodyPart(char, "Head")
	if not (torso and pelvis and head) then
		return nil
	end
	local neck, waist = attPos(torso, "NeckRigAttachment"), attPos(torso, "WaistRigAttachment")
	local rs, ls = attPos(torso, "RightShoulderRigAttachment"), attPos(torso, "LeftShoulderRigAttachment")
	local pTop, hip = attPos(pelvis, "WaistRigAttachment"), attPos(pelvis, "RightHipRigAttachment")
	local hNeck = attPos(head, "NeckRigAttachment")
	if not (neck and waist and rs and pTop and hip and hNeck) then
		return nil
	end
	local arms: { [string]: Arm } = {}
	for _, side in { "Right", "Left" } do
		local u = seg15(char, side .. "UpperArm", side .. "ShoulderRigAttachment", side .. "ElbowRigAttachment")
		local l = seg15(char, side .. "LowerArm", side .. "ElbowRigAttachment", side .. "WristRigAttachment")
		local h = seg15(char, side .. "Hand", side .. "WristRigAttachment")
		if u and l and h then
			arms[side] = { upper = u, lower = l, hand = h, top = attPos(u.part, side .. "ShoulderAttachment") }
		end
	end
	local lu = seg15(char, "RightUpperLeg", "RightHipRigAttachment", "RightKneeRigAttachment")
	local ll = seg15(char, "RightLowerLeg", "RightKneeRigAttachment", "RightAnkleRigAttachment")
	local lf = seg15(char, "RightFoot", "RightAnkleRigAttachment")
	local llu = seg15(char, "LeftUpperLeg", "LeftHipRigAttachment", "LeftKneeRigAttachment")
	local lll = seg15(char, "LeftLowerLeg", "LeftKneeRigAttachment", "LeftAnkleRigAttachment")
	if not (arms.Right and lu and ll and lf) then
		return nil
	end
	return {
		kind = "R15",
		k = math.clamp(torso.Size.X / 1.94, 0.6, 1.6),
		torso = torso,
		neck = neck,
		waist = waist,
		shoulders = { Right = rs, Left = ls or rs * Vector3.new(-1, 1, 1) },
		pelvis = pelvis,
		pelvisTop = pTop,
		hip = hip,
		head = head,
		headSize = headSize(head),
		headNeck = hNeck,
		arms = arms,
		leg = { upper = lu :: Segment, lower = ll :: Segment, foot = lf :: Segment },
		legL = if llu and lll then { upper = llu, lower = lll } else nil,
		collar = {
			Right = attPos(torso, "RightCollarAttachment") :: any,
			Left = attPos(torso, "LeftCollarAttachment") :: any,
		},
		bodyBack = attPos(torso, "BodyBackAttachment"),
		bodyFront = attPos(torso, "BodyFrontAttachment"),
	}
end

-- R6: one part per limb, so upper / lower / hand segments share the part
-- (no separation possible: the limb never bends).
local function limb6(p: BasePart, wristFrac: number): Arm
	local h = p.Size.Y
	local mid = Vector3.zero
	local wrist = Vector3.new(0, -h * wristFrac, 0)
	return {
		upper = { part = p, a = Vector3.new(0, h / 2, 0), b = mid },
		lower = { part = p, a = mid, b = wrist },
		hand = { part = p, a = wrist, b = Vector3.new(0, -h / 2, 0) },
	}
end

local function readR6(char: Model): Rig?
	local torso, head = bodyPart(char, "Torso"), bodyPart(char, "Head")
	local ra, rl = bodyPart(char, "Right Arm"), bodyPart(char, "Right Leg")
	if not (torso and head and ra and rl) then
		return nil
	end
	local ts = torso.Size
	local rs = jointC0(torso, "Right Shoulder") or Vector3.new(ts.X / 2, ts.Y / 4, 0)
	local ls = jointC0(torso, "Left Shoulder") or rs * Vector3.new(-1, 1, 1)
	local arms: { [string]: Arm } = { Right = limb6(ra, 0.36) }
	local la = bodyPart(char, "Left Arm")
	if la then
		arms.Left = limb6(la, 0.36)
	end
	local leg = limb6(rl, 0.38)
	local lleg = bodyPart(char, "Left Leg")
	local legL = if lleg then limb6(lleg, 0.38) else nil
	return {
		kind = "R6",
		k = math.clamp(ts.X / 2, 0.6, 1.6),
		torso = torso,
		neck = Vector3.new(0, ts.Y / 2, 0),
		waist = Vector3.new(0, -ts.Y * 0.28, 0),
		shoulders = { Right = Vector3.new(rs.X, rs.Y, 0), Left = Vector3.new(ls.X, ls.Y, 0) },
		pelvis = torso,
		pelvisTop = Vector3.new(0, -ts.Y * 0.28, 0),
		hip = Vector3.new(ts.X / 4, -ts.Y / 2, 0),
		head = head,
		headSize = headSize(head),
		headNeck = Vector3.new(0, -head.Size.Y / 2, 0),
		arms = arms,
		leg = { upper = leg.upper, lower = leg.lower, foot = leg.hand },
		legL = if legL then { upper = legL.upper, lower = legL.lower } else nil,
	}
end

-- The rig description used by buildWorn, or nil (+ why) if the character
-- can't wear the exo (missing parts / attachments, not a humanoid rig).
function ExoBuilder.readRig(char: Model, hum: Humanoid): (Rig?, string)
	if hum.RigType == Enum.HumanoidRigType.R15 then
		local rig = readR15(char)
		return rig, if rig then "R15" else "missing R15 parts"
	end
	local rig = readR6(char)
	return rig, if rig then "R6" else "missing R6 parts"
end

-- World-space height of a part's bounding box, half of it.
local function halfY(cf: CFrame, s: Vector3): number
	return math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
end

-- Standing measurements (from the Humanoid's own hip height, so it works
-- mid-air). Only the character's direct BaseParts count (no accessories).
function ExoBuilder.measure(char: Model, hum: Humanoid, root: BasePart): Measure
	local rootCF = root.CFrame
	local legH = 0
	if hum.RigType == Enum.HumanoidRigType.R6 then
		local leg = bodyPart(char, "Right Leg") or bodyPart(char, "Left Leg")
		legH = if leg then leg.Size.Y else 0
	end
	local ground = root.Position.Y - root.Size.Y / 2 - legH - hum.HipHeight
	local top = root.Position.Y + root.Size.Y / 2
	local bottom = math.huge
	local minP = Vector3.new(-root.Size.X / 2, 0, -root.Size.Z / 2)
	local maxP = Vector3.new(root.Size.X / 2, 0, root.Size.Z / 2)
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") and p ~= root then
			local hy = halfY(p.CFrame, p.Size)
			top = math.max(top, p.Position.Y + hy)
			bottom = math.min(bottom, p.Position.Y - hy)
			local rel = rootCF:ToObjectSpace(p.CFrame)
			local s = p.Size / 2
			local ex = math.abs(rel.RightVector.X) * s.X + math.abs(rel.UpVector.X) * s.Y + math.abs(rel.LookVector.X) * s.Z
			local ez = math.abs(rel.RightVector.Z) * s.X + math.abs(rel.UpVector.Z) * s.Y + math.abs(rel.LookVector.Z) * s.Z
			minP = minP:Min(rel.Position - Vector3.new(ex, 0, ez))
			maxP = maxP:Max(rel.Position + Vector3.new(ex, 0, ez))
		end
	end
	local head = bodyPart(char, "Head")
	local headY = if head then head.Position.Y else top
	return {
		ground = ground,
		rootH = root.Position.Y - ground,
		feet = root.Position.Y - (if bottom < math.huge then bottom else ground),
		headH = headY - ground,
		height = top - (if bottom < math.huge then bottom else ground),
		width = maxP.X - minP.X,
		depth = maxP.Z - minP.Z,
		halfW = math.max(-minP.X, maxP.X),
		halfD = math.max(-minP.Z, maxP.Z),
		centerY = (top + (if bottom < math.huge then bottom else ground)) / 2 - root.Position.Y,
	}
end

----------------------------------------------------------------- parts

type Ctx = { model: Model, k: number, pad: number, offsets: { [BasePart]: CFrame } }

-- A body part's size plus the layered-clothing pad (jackets / pants worn over
-- the body push the exo outwards so it isn't swallowed by the clothing).
local function sz(ctx: Ctx, part: BasePart): Vector3
	return part.Size + Vector3.new(2 * ctx.pad, 0, 2 * ctx.pad)
end

local SHAPES = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

local function make(kind: string, size: Vector3, color: ColorKey): BasePart
	local part: BasePart
	if kind == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = SHAPES[kind]
		part = p
	end
	part.Size = size
	if color == "glow" then
		part.Color = COL.glow
		part.Material = Enum.Material.Neon
		part:SetAttribute("Phase", math.random() * 0.6)
		CollectionService:AddTag(part, ExoBuilder.LightTag)
	elseif color == "steel" then
		part.Color = COL.steel
		part.Material = Enum.Material.Metal
	elseif color == "dark" then
		part.Color = COL.dark
		part.Material = Enum.Material.SmoothPlastic
	else
		part.Color = COL.frame
		part.Material = Enum.Material.Metal
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = size.Magnitude > 0.5
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Adds a piece welded to `body`; `cf` in body space.
local function add(ctx: Ctx, body: BasePart, kind: string, size: Vector3, cf: CFrame, color: ColorKey, name: string?): BasePart
	local part = make(kind, size, color)
	part.Name = name or ("Exo" .. body.Name .. kind)
	part.CFrame = body.CFrame * cf
	local weld = Instance.new("Weld")
	weld.Name = "ExoWeld"
	weld.Part0 = body
	weld.Part1 = part
	weld.C0 = cf
	weld.Parent = part
	part.Parent = ctx.model
	ctx.offsets[part] = cf
	return part
end

-- Frame at `pos` whose Y axis points along `dir`.
local function alongY(pos: Vector3, dir: Vector3): CFrame
	local up = dir.Unit
	local ref = if math.abs(up.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
	local right = (ref - up * ref:Dot(up)).Unit
	return CFrame.fromMatrix(pos, right, up)
end

-- Frame at `pos` whose X axis (a cylinder's axis) points along `dir`.
local function alongX(pos: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local ref = if math.abs(x.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	local y = (ref - x * ref:Dot(x)).Unit
	return CFrame.fromMatrix(pos, x, y)
end
ExoBuilder.alongX = alongX

local function block(ctx: Ctx, body: BasePart, size: Vector3, cf: CFrame, color: ColorKey, name: string?): BasePart
	return add(ctx, body, "Block", size, cf, color, name)
end

-- Square bar from p0 to p1 (body space), tx wide (X-ish) and tz deep.
local function bar(ctx: Ctx, body: BasePart, p0: Vector3, p1: Vector3, tx: number, tz: number, color: ColorKey, name: string?): BasePart
	local len = math.max((p1 - p0).Magnitude, 0.05)
	return add(ctx, body, "Block", Vector3.new(tx, len, tz), alongY((p0 + p1) / 2, p1 - p0), color, name)
end

local function rod(ctx: Ctx, body: BasePart, p0: Vector3, p1: Vector3, dia: number, color: ColorKey, name: string?): BasePart
	local len = math.max((p1 - p0).Magnitude, 0.05)
	return add(ctx, body, "Cylinder", Vector3.new(len, dia, dia), alongX((p0 + p1) / 2, p1 - p0), color, name)
end

local function disc(ctx: Ctx, body: BasePart, pos: Vector3, axis: Vector3, dia: number, thick: number, color: ColorKey, name: string?): BasePart
	return add(ctx, body, "Cylinder", Vector3.new(thick, dia, dia), alongX(pos, axis), color, name)
end

local function ball(ctx: Ctx, body: BasePart, pos: Vector3, dia: number, color: ColorKey, name: string?): BasePart
	return add(ctx, body, "Ball", Vector3.one * dia, CFrame.new(pos), color, name)
end

-- A rectangular cuff of four blocks round a limb (inner size inX x inZ).
local function ring(ctx: Ctx, body: BasePart, c: Vector3, inX: number, inZ: number, h: number, t: number, color: ColorKey)
	block(ctx, body, Vector3.new(inX + 2 * t, h, t), CFrame.new(c + Vector3.new(0, 0, -(inZ + t) / 2)), color)
	block(ctx, body, Vector3.new(inX + 2 * t, h, t), CFrame.new(c + Vector3.new(0, 0, (inZ + t) / 2)), color)
	block(ctx, body, Vector3.new(t, h, inZ), CFrame.new(c + Vector3.new(-(inX + t) / 2, 0, 0)), color)
	block(ctx, body, Vector3.new(t, h, inZ), CFrame.new(c + Vector3.new((inX + t) / 2, 0, 0)), color)
end

-- A round cuff (cylinder band, axis Y) round a limb whose size is `limb`:
-- mesh limbs are rounded, so a band sized from the box's mean width hugs them.
local function band(ctx: Ctx, body: BasePart, c: Vector3, limb: Vector3, h: number, t: number, color: ColorKey): BasePart
	-- (a MeshPart limb's box is ~25% wider than the visible limb)
	local dia = 0.75 * (limb.X + limb.Z) / 2 + 2 * t
	return add(ctx, body, "Cylinder", Vector3.new(h, dia, dia), alongX(c, Vector3.yAxis), color, "ExoCuff")
end

-- ---- snug fit -----------------------------------------------------------
-- Avatar meshes are often slimmer than their part boxes (slim / female
-- bodies: arms lean inside the box, shoulders slope below its top, the back
-- sits in front of its back face). Body MeshParts collide as boxes, so
-- raycasts can't see the real surface; instead the fit reads the joint and
-- accessory attachments (placed on the mesh by the body's creator) and keeps
-- every shoulder / arm piece FIT_GAP off that surface (+ the layered-clothing
-- pad when the avatar wears WrapLayer clothing). Broad / boxy bodies come out
-- exactly at their box faces, so nothing clips.
local FIT_GAP = 0.04 -- x k

-- A limb segment as a round cylinder along p0 -> p1 (part space; the
-- shoulder accessory / joint attachments), its radius what the box leaves
-- once the lean is taken out, clamped inside the box.
type Limb = { p0: Vector3, p1: Vector3, r: number, half: number, cuffR: number }
local function limbOf(ctx: Ctx, part: BasePart, p0: Vector3, p1: Vector3): Limb
	local size = part.Size
	local d = p1 - p0
	local slope = if math.abs(d.Y) > 1e-3 then math.abs(d.X / d.Y) else 0
	local r = math.max((size.X - slope * size.Y) / 2, 0.3 * size.Z, 0.05)
	r = math.min(r, size.X / 2)
	-- cuff radius: a leaning limb is a tapered, rounded mesh, thinner than
	-- the box suggests along most of its length; a straight one fills its box
	local round = (r + math.min(size.X, size.Z) / 2) / 2
	local cuffR = if slope > 0.08 then 0.8 * round else round
	return { p0 = p0, p1 = p1, r = r + ctx.pad, half = size.X / 2 + ctx.pad, cuffR = cuffR + ctx.pad }
end

-- Point on a limb's axis at height y (part space).
local function axisAt(l: Limb, y: number): Vector3
	local d = l.p1 - l.p0
	if math.abs(d.Y) < 1e-3 then
		return Vector3.new(l.p0.X, y, l.p0.Z)
	end
	return l.p0 + d * ((y - l.p0.Y) / d.Y)
end

-- Outer surface X (part space) of a limb on side s (+1 right, -1 left) at y.
local function outerX(l: Limb, y: number, s: number): number
	return s * math.min(l.half, s * axisAt(l, y).X + l.r)
end

-- Torso back / chest surface Z for the exo (attachments, nudged a little
-- towards the box face because they sit at mid back / mid chest).
local function backZ(ctx: Ctx, rig: Rig): number
	local box = rig.torso.Size.Z / 2
	local z = if rig.bodyBack and rig.bodyBack.Z > 0 then math.min(box, rig.bodyBack.Z + 0.3 * (box - rig.bodyBack.Z)) else box
	return z + ctx.pad
end
local function frontZ(ctx: Ctx, rig: Rig): number
	local box = rig.torso.Size.Z / 2
	local z = if rig.bodyFront and rig.bodyFront.Z < 0 then math.min(box, -rig.bodyFront.Z + 0.3 * (box + rig.bodyFront.Z)) else box
	return -(z + ctx.pad)
end

-- Height of the shoulder's top surface at |x| (torso space): slopes from the
-- neck joint down to the collar attachment (trapezius).
local function shoulderTop(ctx: Ctx, rig: Rig, x: number, side: string): number
	local ts = rig.torso.Size
	local top = math.min(rig.neck.Y, ts.Y / 2)
	local collar = rig.collar and rig.collar[side]
	if collar then
		local t = math.clamp(math.abs(x) / math.max(math.abs(collar.X), 0.05), 0, 1)
		top += (math.min(collar.Y, top) - top) * t
	end
	return top + ctx.pad
end

-- A round cuff of radius `r` round a limb axis point (cylinder band, axis Y).
local function cuff(ctx: Ctx, body: BasePart, c: Vector3, r: number, h: number, t: number, color: ColorKey): BasePart
	local dia = 2 * (r + t)
	return add(ctx, body, "Cylinder", Vector3.new(h, dia, dia), alongX(c, Vector3.yAxis), color, "ExoCuff")
end

-- An attachment inside exo part `part` at `bodyPoint` (its body's space),
-- X axis along `axis` (body space) so beam curves bulge that way.
local function attachIn(ctx: Ctx, part: BasePart, bodyPoint: Vector3, axis: Vector3): Attachment
	local off = ctx.offsets[part]
	local a = Instance.new("Attachment")
	a.Name = "ExoCable"
	a.CFrame = alongX(off:PointToObjectSpace(bodyPoint), off:VectorToObjectSpace(axis))
	a.Parent = part
	return a
end

-- A cable (Beam) between two exo parts, sagging along `bulge` (body space of
-- each end).
local function cable(ctx: Ctx, pa: BasePart, a: Vector3, pb: BasePart, b: Vector3, bulge: Vector3, curve: number, glow: boolean?)
	local a0 = attachIn(ctx, pa, a, bulge)
	local a1 = attachIn(ctx, pb, b, bulge)
	local beam = Instance.new("Beam")
	beam.Name = "ExoCable"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	local w = (if glow then 0.035 else 0.07) * ctx.k
	beam.Width0 = w
	beam.Width1 = w
	beam.Color = ColorSequence.new(if glow then COL.glow else COL.cable)
	beam.LightEmission = if glow then 1 else 0
	beam.LightInfluence = if glow then 0 else 1
	beam.Transparency = NumberSequence.new(0)
	beam.FaceCamera = true
	beam.Segments = 12
	beam.CurveSize0 = curve
	beam.CurveSize1 = -curve
	beam.Parent = pa
end

-- Telescoping piston from partA's point pA to partB's point pB (each in its
-- part's space). The cylinder body rides on A, the rod on B; both are
-- re-aimed by updatePiston so they stay in line as the joint bends.
local function piston(ctx: Ctx, partA: BasePart, pA: Vector3, partB: BasePart, pB: Vector3, dia: number, name: string)
	local folder = Instance.new("Model")
	folder.Name = name
	local dist = ((partA.CFrame * pA) - (partB.CFrame * pB)).Magnitude
	local len = math.max(dist * 0.62, 0.1)
	local body = make("Cylinder", Vector3.new(len, dia, dia), "dark")
	body.Name = "Body"
	local rodPart = make("Cylinder", Vector3.new(len, dia * 0.5, dia * 0.5), "steel")
	rodPart.Name = "Rod"
	for _, pair in { { body, partA, pA }, { rodPart, partB, pB } } do
		local part, owner, anchor = pair[1] :: BasePart, pair[2] :: BasePart, pair[3] :: Vector3
		part:SetAttribute("Anchor", anchor)
		local weld = Instance.new("Weld")
		weld.Name = "ExoWeld"
		weld.Part0 = owner
		weld.Part1 = part
		weld.C0 = CFrame.new(anchor)
		weld.Parent = part
		part.CFrame = owner.CFrame * weld.C0
		part.Parent = folder
	end
	-- end lugs on the owners
	ball(ctx, partA, pA, dia * 1.25, "frame", "PistonLug")
	ball(ctx, partB, pB, dia * 0.9, "steel", "PistonLug")
	CollectionService:AddTag(folder, ExoBuilder.PistonTag)
	folder.Parent = ctx.model
	ExoBuilder.updatePiston(folder)
end

-- Re-aims a piston's body and rod at each other (clients, every frame).
function ExoBuilder.updatePiston(folder: Instance)
	local body = folder:FindFirstChild("Body") :: BasePart?
	local rodPart = folder:FindFirstChild("Rod") :: BasePart?
	local bw = body and body:FindFirstChild("ExoWeld") :: Weld?
	local rw = rodPart and rodPart:FindFirstChild("ExoWeld") :: Weld?
	if not (body and rodPart and bw and rw and bw.Part0 and rw.Part0) then
		return
	end
	local p0, p1 = bw.Part0 :: BasePart, rw.Part0 :: BasePart
	local a = p0.CFrame * (body:GetAttribute("Anchor") :: Vector3)
	local b = p1.CFrame * (rodPart:GetAttribute("Anchor") :: Vector3)
	local d = b - a
	if d.Magnitude < 1e-3 then
		return
	end
	local dir = d.Unit
	bw.C0 = p0.CFrame:ToObjectSpace(alongX(a + dir * body.Size.X / 2, dir))
	rw.C0 = p1.CFrame:ToObjectSpace(alongX(b - dir * rodPart.Size.X / 2, dir))
end

local function newModel(): Model
	local model = Instance.new("Model")
	model.Name = ExoBuilder.ModelName
	return model
end

----------------------------------------------------------------- worn form

local function buildSpine(ctx: Ctx, rig: Rig): (BasePart, BasePart)
	local k, T, ts = ctx.k, rig.torso, sz(ctx, rig.torso)
	local zb = backZ(ctx, rig)
	local topY = rig.neck.Y - 0.1 * ts.Y
	local botY = rig.waist.Y
	local len = topY - botY
	local column = bar(ctx, T, Vector3.new(0, botY, zb + 0.1 * k), Vector3.new(0, topY, zb + 0.1 * k), 0.16 * k, 0.14 * k, "frame", "ExoSpine")
	for i = 0, 3 do
		local y = botY + 0.14 * len + i * 0.22 * len
		block(ctx, T, Vector3.new(0.22 * ts.X, 0.1 * k, 0.12 * k), CFrame.new(0, y, zb + 0.17 * k), "dark", "ExoVertebra")
	end
	block(ctx, T, Vector3.new(0.05 * k, 0.75 * len, 0.04 * k), CFrame.new(0, (topY + botY) / 2, zb + 0.24 * k), "glow", "ExoSpineLight")
	-- spine pistons either side
	for _, s in { 1, -1 } do
		local x = s * 0.13 * ts.X
		rod(ctx, T, Vector3.new(x, botY + 0.08 * len, zb + 0.08 * k), Vector3.new(x, botY + 0.5 * len, zb + 0.08 * k), 0.11 * k, "dark")
		rod(ctx, T, Vector3.new(x, botY + 0.45 * len, zb + 0.08 * k), Vector3.new(x, topY - 0.2 * len, zb + 0.08 * k), 0.06 * k, "steel")
		-- shoulder-blade plate
		block(ctx, T, Vector3.new(0.28 * ts.X, 0.32 * ts.Y, 0.06 * k), CFrame.new(s * 0.24 * ts.X, topY - 0.24 * ts.Y, zb + 0.03 * k) * CFrame.Angles(0, s * 0.18, 0), "dark", "ExoScapula")
	end
	-- shoulder yoke
	local yokeY = topY - 0.08 * ts.Y
	block(ctx, T, Vector3.new(0.68 * ts.X, 0.12 * k, 0.12 * k), CFrame.new(0, yokeY, zb + 0.13 * k), "frame", "ExoYoke")
	-- socket on top of the spine for the neck strut
	local socket = ball(ctx, T, Vector3.new(rig.neck.X, rig.neck.Y - 0.05 * k, zb * 0.85 + 0.08 * k), 0.24 * k, "frame", "ExoNeckSocket")
	return column, socket
end

local function buildShoulder(ctx: Ctx, rig: Rig, s: number, column: BasePart): BasePart
	local k, T, ts = ctx.k, rig.torso, sz(ctx, rig.torso)
	local zb = backZ(ctx, rig)
	local sh = rig.shoulders[if s > 0 then "Right" else "Left"]
	-- over the shoulder blade, kept inboard of a narrow shoulder joint
	local hubPos = Vector3.new(s * math.min(0.36 * ts.X, 0.72 * math.abs(sh.X)), sh.Y - 0.02 * ts.Y, zb + 0.11 * k)
	local hub = disc(ctx, T, hubPos, Vector3.zAxis, 0.34 * k, 0.14 * k, "dark", "ExoShoulderHub")
	disc(ctx, T, hubPos + Vector3.new(0, 0, 0.08 * k), Vector3.zAxis, 0.15 * k, 0.03 * k, "glow", "ExoHubLight")
	-- brace from the hub out to the shoulder joint
	bar(ctx, T, hubPos, Vector3.new(s * (math.abs(sh.X) + 0.02 * k), sh.Y + 0.02 * ts.Y, zb * 0.35), 0.11 * k, 0.11 * k, "frame", "ExoShoulderBrace")
	-- (the bar over the shoulder onto the chest is built by buildChest)
	-- hub to spine bar
	bar(ctx, T, hubPos, Vector3.new(0, hubPos.Y - 0.05 * ts.Y, zb + 0.12 * k), 0.1 * k, 0.1 * k, "frame")
	return hub
end

-- Front of the harness (Elysium chest rig): a layered sternum unit with
-- green lights and hose loops, shoulder bars arching from the back hubs over
-- the top of each shoulder down onto the unit, and a strap from the unit's
-- lower corner round each side of the ribcage to the spine. All on the
-- UpperTorso, hugging its surface (+ the layered-clothing pad).
local function buildChest(ctx: Ctx, rig: Rig, hubs: { [string]: BasePart }, column: BasePart)
	local k, T, ts = ctx.k, rig.torso, sz(ctx, rig.torso)
	local zf, zb = frontZ(ctx, rig), backZ(ctx, rig)
	-- shoulder line: top of the torso at the neck joint
	local topY = math.min(rig.neck.Y, ts.Y / 2) + 0.04 * k
	local pw, ph = 0.4 * ts.X, 0.26 * ts.Y
	local plateY = topY - 0.12 * ts.Y - ph / 2
	local unit = block(ctx, T, Vector3.new(pw, ph, 0.1 * k), CFrame.new(0, plateY, zf - 0.05 * k), "dark", "ExoChestUnit")
	block(ctx, T, Vector3.new(pw * 0.75, ph * 0.6, 0.07 * k), CFrame.new(0, plateY + 0.08 * ph, zf - 0.13 * k), "frame", "ExoChestPlate")
	block(ctx, T, Vector3.new(pw * 0.5, ph * 0.28, 0.05 * k), CFrame.new(0, plateY - 0.36 * ph, zf - 0.12 * k) * CFrame.Angles(0.3, 0, 0), "dark", "ExoChestLip")
	for i = -1, 1 do
		block(ctx, T, Vector3.new(0.05 * k, 0.05 * k, 0.03 * k), CFrame.new(i * 0.14 * pw, plateY + 0.12 * ph, zf - 0.18 * k), "glow", "ExoChestLight")
	end
	block(ctx, T, Vector3.new(pw * 0.4, 0.03 * k, 0.03 * k), CFrame.new(0, plateY - 0.15 * ph, zf - 0.17 * k), "glow", "ExoChestLight")
	for _, s in { 1, -1 } do
		disc(ctx, T, Vector3.new(s * 0.4 * pw, plateY + 0.3 * ph, zf - 0.12 * k), Vector3.zAxis, 0.1 * k, 0.06 * k, "steel", "ExoChestPort")
	end
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local hub = hubs[side]
		local hubPos = ctx.offsets[hub].Position
		local collar = rig.collar and rig.collar[side]
		local x = s * (if collar then math.min(0.37 * ts.X, 0.9 * math.abs(collar.X)) else 0.37 * ts.X)
		-- shoulder bar: back hub -> over the shoulder -> onto the chest unit,
		-- resting on the shoulder's sloped top (half its 0.08k thickness + gap)
		local barY = shoulderTop(ctx, rig, x, side) + (FIT_GAP + 0.04) * k
		local backTop = Vector3.new(x, barY, zb * 0.55)
		local frontTop = Vector3.new(x, barY, zf * 0.55)
		local corner = Vector3.new(s * 0.45 * pw, plateY + 0.35 * ph, zf - 0.07 * k)
		bar(ctx, T, hubPos, backTop, 0.13 * k, 0.09 * k, "frame", "ExoShoulderBar")
		local over = bar(ctx, T, backTop, frontTop, 0.15 * k, 0.08 * k, "frame", "ExoShoulderBar")
		bar(ctx, T, frontTop, corner, 0.13 * k, 0.09 * k, "frame", "ExoShoulderBar")
		ball(ctx, T, backTop, 0.14 * k, "dark")
		ball(ctx, T, frontTop, 0.14 * k, "dark")
		-- rib strap: unit corner round the side to the spine
		local y = plateY - 0.5 * ph - 0.06 * ts.Y
		local pts = {
			Vector3.new(s * 0.45 * pw, plateY - 0.4 * ph, zf - 0.08 * k),
			-- corners just outside a box torso's edge too (blocky bodies)
			Vector3.new(s * (0.48 * ts.X + 0.06 * k), y, zf * 0.95 - 0.07 * k),
			Vector3.new(s * (ts.X / 2 + 0.1 * k), y, 0),
			Vector3.new(s * (0.48 * ts.X + 0.06 * k), y, zb * 0.95 + 0.07 * k),
			Vector3.new(s * 0.08 * ts.X, y, zb + 0.06 * k),
		}
		for i = 1, #pts - 1 do
			bar(ctx, T, pts[i], pts[i + 1], 0.04 * k, 0.11 * k, "dark", "ExoRibStrap")
		end
		-- hose loop from the unit up to the shoulder bar
		cable(ctx, unit, Vector3.new(s * 0.5 * pw, plateY - 0.1 * ph, zf - 0.06 * k), over, frontTop + Vector3.new(s * 0.06 * k, 0, -0.02 * k), Vector3.new(s * 0.6, -0.5, -1), 0.18 * k)
	end
	-- green data line from the unit over the left shoulder to the spine
	cable(ctx, unit, Vector3.new(-0.2 * pw, plateY + 0.45 * ph, zf - 0.06 * k), column, Vector3.new(-0.05 * k, topY - 0.15 * ts.Y, zb + 0.18 * k), Vector3.new(0, 1, 0), 0.3 * k, true)
end

local function buildBelt(ctx: Ctx, rig: Rig)
	local k, P, ps = ctx.k, rig.pelvis, sz(ctx, rig.pelvis)
	local w, hip = rig.pelvisTop, rig.hip
	local beltY = (w.Y + hip.Y) / 2
	local beltH = math.max(0.24 * k, 0.6 * math.abs(w.Y - hip.Y))
	if rig.kind == "R6" then
		beltY = -ps.Y / 2 + 0.2 * ps.Y
		beltH = 0.3 * k
	end
	ring(ctx, P, Vector3.new(0, beltY, 0), ps.X + 0.04 * k, ps.Z + 0.04 * k, beltH, 0.08 * k, "dark")
	local zb = ps.Z / 2
	-- back housing (where the spine plugs into the belt)
	local housingTop = beltY + beltH * 0.9
	block(ctx, P, Vector3.new(0.38 * ps.X, beltH * 1.8, 0.2 * k), CFrame.new(0, beltY + 0.05 * k, zb + 0.16 * k), "frame", "ExoBeltHousing")
	block(ctx, P, Vector3.new(0.22 * ps.X, 0.04 * k, 0.03 * k), CFrame.new(0, beltY, zb + 0.27 * k), "glow", "ExoBeltLight")
	-- front buckle
	block(ctx, P, Vector3.new(0.3 * k, beltH * 0.8, 0.06 * k), CFrame.new(0, beltY, -(zb + 0.1 * k)), "steel", "ExoBuckle")
	-- right hip side plate
	block(ctx, P, Vector3.new(0.07 * k, beltH * 1.6, 0.42 * k), CFrame.new(ps.X / 2 + 0.11 * k, beltY - beltH * 0.25, 0), "frame", "ExoHipPlate")
	-- lower spine up to the waist joint (R15: the waist bends between torsos)
	if rig.kind == "R15" then
		bar(ctx, P, Vector3.new(0, housingTop, zb + 0.12 * k), Vector3.new(0, w.Y + 0.04 * k, zb + 0.12 * k), 0.15 * k, 0.13 * k, "frame", "ExoLowerSpine")
		ball(ctx, P, Vector3.new(0, w.Y + 0.02 * k, zb + 0.11 * k), 0.22 * k, "dark", "ExoWaistBall")
	end
end

local function buildSkull(ctx: Ctx, rig: Rig, socket: BasePart, column: BasePart)
	local k, H, hs = ctx.k, rig.head, rig.headSize
	local zb = hs.Z / 2
	local plateC = Vector3.new(0, 0.02 * hs.Y, zb + 0.03 * k)
	local plate = block(ctx, H, Vector3.new(0.5 * hs.X, 0.55 * hs.Y, 0.07 * k), CFrame.new(plateC), "frame", "ExoSkullPlate")
	for _, s in { 1, -1 } do
		block(ctx, H, Vector3.new(0.2 * hs.X, 0.36 * hs.Y, 0.05 * k), CFrame.new(s * 0.3 * hs.X, 0.02 * hs.Y, zb - 0.05 * hs.Z) * CFrame.Angles(0, s * 0.55, 0), "dark", "ExoSkullWing")
	end
	-- crown cap sloping over the top of the back of the head
	block(ctx, H, Vector3.new(0.36 * hs.X, 0.07 * k, 0.28 * hs.Z), CFrame.new(0, 0.36 * hs.Y, zb - 0.06 * hs.Z) * CFrame.Angles(0.7, 0, 0), "dark", "ExoSkullCap")
	-- sensor port
	local port = plateC + Vector3.new(0.12 * hs.X, 0.1 * hs.Y, 0.06 * k)
	disc(ctx, H, port, Vector3.zAxis, 0.2 * k, 0.09 * k, "steel", "ExoSensor")
	ball(ctx, H, port + Vector3.new(0, 0, 0.05 * k), 0.1 * k, "glow", "ExoSensorLens")
	block(ctx, H, Vector3.new(0.05 * k, 0.03 * k, 0.03 * k), CFrame.new(plateC + Vector3.new(-0.14 * hs.X, 0.12 * hs.Y, 0.05 * k)), "glow", "ExoSkullLight")
	-- neck strut: plate bottom -> the socket on the spine (same point at rest)
	local socketHead = rig.headNeck + (ctx.offsets[socket].Position - rig.neck)
	local strutTop = Vector3.new(0, plateC.Y - 0.25 * hs.Y, zb + 0.05 * k)
	local strut = bar(ctx, H, strutTop, socketHead, 0.11 * k, 0.11 * k, "frame", "ExoNeckStrut")
	rod(ctx, H, strutTop + Vector3.new(0.09 * k, 0, 0), socketHead + Vector3.new(0.09 * k, 0.04 * k, 0), 0.05 * k, "steel")
	-- green data cable from the spine up into the skull plate
	local t = sz(ctx, rig.torso)
	cable(ctx, column, Vector3.new(-0.05 * k, rig.neck.Y - 0.25 * t.Y, t.Z / 2 + 0.2 * k), plate, plateC + Vector3.new(-0.1 * hs.X, -0.2 * hs.Y, 0.04 * k), Vector3.new(0, 0, 1), 0.15 * k, true)
	cable(ctx, socket, Vector3.new(0.08 * k, rig.neck.Y - 0.08 * k, t.Z / 2 * 0.85 + 0.12 * k), strut, socketHead + Vector3.new(-0.06 * k, 0.12 * hs.Y, 0.04 * k), Vector3.new(0, 0, 1), 0.08 * k)
end

local function buildArm(ctx: Ctx, arm: Arm, s: number, full: boolean, hub: BasePart)
	local k = ctx.k
	local U, L, Hd = arm.upper, arm.lower, arm.hand
	local us, ls = sz(ctx, U.part), sz(ctx, L.part)
	local uLen, lLen = math.abs(U.a.Y - U.b.Y), math.abs(L.a.Y - L.b.Y)
	-- the limbs as slanted cylinders through their attachments (snug fit)
	local topPt = arm.top or Vector3.new(U.b.X, U.a.Y, U.b.Z)
	local lu = limbOf(ctx, U.part, topPt, U.b)
	local ll = limbOf(ctx, L.part, L.a, L.b)
	local gap = FIT_GAP * k
	local half = 0.045 * k -- half a strut's thickness
	-- elbow hinge offset along the hinge axis (X), measured from the joint and
	-- the same on both sides of it: outside whichever limb is wider there
	local oU = s * outerX(lu, U.b.Y, s) - s * U.b.X
	local oL = s * outerX(ll, L.a.Y, s) - s * L.a.X
	local ox = s * (math.max(oU, oL) + gap + half)
	local yTop = U.a.Y - 0.04 * us.Y
	local uTop = Vector3.new(outerX(lu, yTop, s) + s * (gap + half), yTop, axisAt(lu, yTop).Z)
	local elbowU = Vector3.new(U.b.X + ox, U.b.Y, U.b.Z)
	local elbowL = Vector3.new(L.a.X + ox, L.a.Y, L.a.Z)
	local yW = L.b.Y + 0.1 * ls.Y
	local wristL = Vector3.new(outerX(ll, yW, s) + s * (gap + half), yW, axisAt(ll, yW).Z)

	-- shoulder: deltoid plate + hub on the arm, cabled to the torso hub
	local yD = U.a.Y - 0.12 * uLen
	local dz = math.min(us.Z * 0.8, 2 * lu.r + 0.1 * k)
	local delt = block(ctx, U.part, Vector3.new(0.07 * k, 0.45 * uLen + 0.15 * k, dz), CFrame.new(outerX(lu, yD, s) + s * (gap + 0.035 * k), yD, axisAt(lu, yD).Z), "dark", "ExoDeltoid")
	local armHub = disc(ctx, U.part, uTop + Vector3.new(s * 0.03 * k, 0, 0), Vector3.xAxis, 0.3 * k, 0.12 * k, "frame", "ExoArmHub")
	local upper = bar(ctx, U.part, uTop, elbowU, 0.09 * k, 0.16 * k, "frame", "ExoUpperArmStrut")
	disc(ctx, U.part, elbowU, Vector3.xAxis, 0.34 * k, 0.1 * k, "dark", "ExoElbowOuter")
	local yC = U.b.Y + 0.55 * uLen
	cuff(ctx, U.part, axisAt(lu, yC), lu.cuffR + gap * 0.5, 0.12 * k, 0.04 * k, "dark")
	cable(ctx, hub, ctx.offsets[hub].Position + Vector3.new(0, -0.08 * k, 0.04 * k), armHub, uTop + Vector3.new(s * 0.05 * k, -0.06 * k, 0.06 * k), Vector3.new(0, -1, 0.3), 0.25 * k)
	_ = delt

	-- elbow hinge + forearm
	disc(ctx, L.part, elbowL + Vector3.new(s * 0.06 * k, 0, 0), Vector3.xAxis, 0.26 * k, 0.08 * k, "steel", "ExoElbowInner")
	if full then
		disc(ctx, L.part, elbowL + Vector3.new(s * 0.11 * k, 0, 0), Vector3.xAxis, 0.13 * k, 0.02 * k, "glow", "ExoElbowLight")
	end
	local fore = bar(ctx, L.part, elbowL, wristL, 0.09 * k, 0.15 * k, "frame", "ExoForearmStrut")
	local yWc = L.b.Y + 0.08 * ls.Y
	cuff(ctx, L.part, axisAt(ll, yWc), ll.cuffR + gap * 0.5, 0.2 * k, 0.05 * k, "frame")
	if not full then
		return
	end
	block(ctx, L.part, Vector3.new(0.03 * k, 0.05 * k, 0.12 * k), CFrame.new(wristL.X + s * 0.05 * k, yWc, wristL.Z), "glow", "ExoWristLight")
	-- elbow piston behind the hinge: stretches as the elbow bends
	piston(ctx, U.part, Vector3.new(U.b.X + ox + s * 0.07 * k, U.a.Y - 0.3 * uLen, U.b.Z + 0.16 * k), L.part, Vector3.new(L.a.X + ox + s * 0.07 * k, L.a.Y - 0.45 * lLen, L.a.Z + 0.12 * k), 0.1 * k, "ExoElbowPiston")
	cable(ctx, upper, Vector3.new(U.b.X + ox - s * 0.03 * k, U.a.Y - 0.5 * uLen, U.b.Z - 0.08 * k), fore, Vector3.new(L.a.X + ox - s * 0.03 * k, L.a.Y - 0.35 * lLen, L.a.Z - 0.08 * k), Vector3.new(0, 0, -1), 0.12 * k)

	-- back-of-hand plate + knuckle bar (only when the hand is its own part)
	if Hd.part ~= L.part then
		local hs = sz(ctx, Hd.part)
		local hx = s * (hs.X * 0.4 + gap)
		local plate = block(ctx, Hd.part, Vector3.new(0.05 * k, 0.35 * hs.Y + 0.08 * k, hs.Z * 0.5), CFrame.new(hx, Hd.a.Y - 0.25 * hs.Y, Hd.a.Z), "dark", "ExoHandPlate")
		block(ctx, Hd.part, Vector3.new(0.07 * k, 0.06 * k, hs.Z * 0.55), CFrame.new(hx + s * 0.01 * k, Hd.a.Y - 0.5 * hs.Y, Hd.a.Z), "frame", "ExoKnuckles")
		cable(ctx, fore, wristL + Vector3.new(0, 0, 0.05 * k), plate, Vector3.new(hx, Hd.a.Y - 0.1 * hs.Y, Hd.a.Z + 0.1 * k), Vector3.new(s, 0, 0), 0.06 * k)
	end
end

local function buildLeg(ctx: Ctx, rig: Rig)
	local k = ctx.k
	local U, L = rig.leg.upper, rig.leg.lower
	local us, ls = sz(ctx, U.part), sz(ctx, L.part)
	local uLen, lLen = math.abs(U.a.Y - U.b.Y), math.abs(L.a.Y - L.b.Y)
	local ox = math.max(us.X, ls.X) / 2 + 0.09 * k -- lateral (+X) on the hinge axes
	local hipHinge = Vector3.new(U.a.X + ox, U.a.Y - 0.04 * uLen, U.a.Z)
	local kneeU = Vector3.new(U.b.X + ox, U.b.Y, U.b.Z)
	local kneeL = Vector3.new(L.a.X + ox, L.a.Y, L.a.Z)
	local fz = -(us.Z / 2 + 0.07 * k) -- front of the thigh
	local fx = U.b.X + 0.12 * us.X

	-- hip hinge (outer side of the hip axis)
	local hipDisc = disc(ctx, U.part, hipHinge, Vector3.xAxis, 0.38 * k, 0.12 * k, "dark", "ExoHipHinge")
	disc(ctx, U.part, hipHinge + Vector3.new(0.07 * k, 0, 0), Vector3.xAxis, 0.16 * k, 0.02 * k, "glow", "ExoHipLight")
	-- front thigh strut + plate, linked to the hip and knee hinges at the side
	local frontTop = Vector3.new(fx, U.a.Y - 0.1 * uLen, fz)
	local frontBot = Vector3.new(fx, U.b.Y + 0.2 * uLen, fz)
	bar(ctx, U.part, frontTop, frontBot, 0.16 * k, 0.09 * k, "frame", "ExoThighStrut")
	bar(ctx, U.part, hipHinge, frontTop, 0.09 * k, 0.09 * k, "frame")
	bar(ctx, U.part, frontBot, kneeU, 0.09 * k, 0.1 * k, "frame")
	local plateC = Vector3.new(U.b.X - 0.05 * us.X, (U.a.Y + U.b.Y) / 2, fz + 0.02 * k)
	block(ctx, U.part, Vector3.new(0.42 * us.X, 0.45 * uLen, 0.06 * k), CFrame.new(plateC), "dark", "ExoThighPlate")
	block(ctx, U.part, Vector3.new(0.04 * k, 0.3 * uLen, 0.03 * k), CFrame.new(plateC + Vector3.new(-0.08 * us.X, 0, -0.04 * k)), "glow", "ExoThighLight")
	local kneeDisc = disc(ctx, U.part, kneeU, Vector3.xAxis, 0.36 * k, 0.1 * k, "dark", "ExoKneeOuter")

	-- knee hinge, kneepad, shin
	disc(ctx, L.part, kneeL + Vector3.new(0.06 * k, 0, 0), Vector3.xAxis, 0.26 * k, 0.08 * k, "steel", "ExoKneeInner")
	disc(ctx, L.part, kneeL + Vector3.new(0.11 * k, 0, 0), Vector3.xAxis, 0.12 * k, 0.02 * k, "glow", "ExoKneeLight")
	local shinZ = -(ls.Z / 2 + 0.06 * k)
	block(ctx, L.part, Vector3.new(0.55 * ls.X, 0.2 * lLen, 0.08 * k), CFrame.new(L.a.X, L.a.Y - 0.1 * lLen, shinZ) * CFrame.Angles(-0.12, 0, 0), "frame", "ExoKneePad")
	local shinTop = Vector3.new(L.a.X + 0.12 * ls.X, L.a.Y - 0.35 * lLen, shinZ)
	local shinBot = Vector3.new(L.a.X + 0.1 * ls.X, L.b.Y + 0.2 * lLen, shinZ)
	bar(ctx, L.part, kneeL, shinTop, 0.09 * k, 0.1 * k, "frame")
	local shin = bar(ctx, L.part, shinTop, shinBot, 0.15 * k, 0.09 * k, "frame", "ExoShinStrut")
	block(ctx, L.part, Vector3.new(0.38 * ls.X, 0.3 * lLen, 0.06 * k), CFrame.new(L.a.X - 0.06 * ls.X, (shinTop.Y + shinBot.Y) / 2, shinZ + 0.02 * k), "dark", "ExoShinPlate")
	-- ankle cuff
	local cuffC = Vector3.new(L.b.X, L.b.Y + 0.1 * lLen, L.b.Z)
	band(ctx, L.part, cuffC, ls, 0.18 * k, 0.05 * k, "frame")
	block(ctx, L.part, Vector3.new(0.12 * k, 0.05 * k, 0.03 * k), CFrame.new(cuffC + Vector3.new(0, 0, -(ls.Z / 2 + 0.11 * k))), "glow", "ExoAnkleLight")
	bar(ctx, L.part, shinBot, Vector3.new(shinBot.X, cuffC.Y + 0.09 * k, shinBot.Z), 0.12 * k, 0.08 * k, "frame")

	-- knee piston on the outer side: front of the thigh -> back of the shin
	piston(ctx, U.part, Vector3.new(U.b.X + ox + 0.08 * k, U.a.Y - 0.45 * uLen, U.b.Z - 0.12 * k), L.part, Vector3.new(L.a.X + ox + 0.08 * k, L.a.Y - 0.4 * lLen, L.a.Z + 0.1 * k), 0.1 * k, "ExoKneePiston")
	cable(ctx, hipDisc, hipHinge + Vector3.new(0.05 * k, -0.05 * k, 0.08 * k), kneeDisc, kneeU + Vector3.new(0.05 * k, 0.05 * k, 0.08 * k), Vector3.new(0, 0, 1), 0.15 * k)
	_ = shin
end

-- Knee cap + hinge disc on a leg without the full strut set (left knee).
local function buildKneeCap(ctx: Ctx, U: Segment, L: Segment, s: number)
	local k = ctx.k
	local us, ls = sz(ctx, U.part), sz(ctx, L.part)
	local lLen = math.abs(L.a.Y - L.b.Y)
	local ox = s * (math.max(us.X, ls.X) / 2 + 0.09 * k)
	disc(ctx, U.part, Vector3.new(U.b.X + ox, U.b.Y, U.b.Z), Vector3.xAxis, 0.3 * k, 0.08 * k, "dark", "ExoKneeOuter")
	disc(ctx, L.part, Vector3.new(L.a.X + ox + s * 0.05 * k, L.a.Y, L.a.Z), Vector3.xAxis, 0.22 * k, 0.06 * k, "steel", "ExoKneeInner")
	disc(ctx, L.part, Vector3.new(L.a.X + ox + s * 0.09 * k, L.a.Y, L.a.Z), Vector3.xAxis, 0.1 * k, 0.02 * k, "glow", "ExoKneeLight")
	local kz = -(ls.Z / 2 + 0.06 * k)
	block(ctx, L.part, Vector3.new(0.55 * ls.X, 0.2 * lLen, 0.08 * k), CFrame.new(L.a.X, L.a.Y - 0.1 * lLen, kz) * CFrame.Angles(-0.12, 0, 0), "frame", "ExoKneePad")
	-- side link from the hinge to the pad
	bar(ctx, L.part, Vector3.new(L.a.X + ox, L.a.Y, L.a.Z), Vector3.new(L.a.X + s * 0.25 * ls.X, L.a.Y - 0.12 * lLen, kz), 0.07 * k, 0.08 * k, "frame")
end

-- Builds the worn exo onto a rig (see readRig); returns the model (parented
-- to the character).
function ExoBuilder.buildWorn(char: Model, rig: Rig): Model
	local model = newModel()
	local layered = false
	for _, acc in char:GetChildren() do
		local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
		if handle and handle:FindFirstChildOfClass("WrapLayer") then
			layered = true
		end
	end
	local ctx: Ctx = { model = model, k = rig.k, pad = if layered then ExoConfig.LayeredClothingPad * rig.k else 0, offsets = {} }
	local column, socket = buildSpine(ctx, rig)
	local hubs: { [string]: BasePart } = {}
	for _, side in { "Right", "Left" } do
		hubs[side] = buildShoulder(ctx, rig, if side == "Right" then 1 else -1, column)
	end
	buildChest(ctx, rig, hubs, column)
	buildBelt(ctx, rig)
	buildSkull(ctx, rig, socket, column)
	buildArm(ctx, rig.arms.Right, 1, true, hubs.Right)
	if ExoConfig.LeftArm and rig.arms.Left then
		buildArm(ctx, rig.arms.Left, -1, false, hubs.Left)
	end
	buildLeg(ctx, rig)
	if ExoConfig.LeftKneeCap and rig.legL then
		buildKneeCap(ctx, rig.legL.upper, rig.legL.lower, -1)
	end
	model:SetAttribute("ExoForm", "Worn")
	model:SetAttribute("ExoRig", rig.kind)
	model.Parent = char
	return model
end

----------------------------------------------------------------- frame form

-- Rest frames of the frame's bones (frame space; each bone's origin is its
-- joint, its segment hangs along -Y). sx / hx: shoulder / hip joint X (the
-- cage widens round a wide rider).
local WAIST_Y = F.PelvisY + 0.25
local TORSO_C = (WAIST_Y + F.ShoulderY) / 2 -- centre of the torso cage
type BoneSpec = { name: string, parent: string, pos: Vector3, joint: string }
local function frameBones(sx: number, hx: number): { BoneSpec }
	local bones: { BoneSpec } = {
		{ name = "Pelvis", parent = "Root", pos = Vector3.new(0, F.PelvisY, 0), joint = "Root" },
		{ name = "Chest", parent = "Pelvis", pos = Vector3.new(0, WAIST_Y, 0), joint = "Waist" },
	}
	for _, sd in { { "R", 1 }, { "L", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local sh = Vector3.new(s * sx, F.ShoulderY, 0)
		table.insert(bones, { name = "UpperArm" .. n, parent = "Chest", pos = sh, joint = "Shoulder" .. n })
		table.insert(bones, { name = "Forearm" .. n, parent = "UpperArm" .. n, pos = sh - Vector3.new(0, F.UpperArm, 0), joint = "Elbow" .. n })
		table.insert(bones, { name = "Thigh" .. n, parent = "Pelvis", pos = Vector3.new(s * hx, F.HipY, 0), joint = "Hip" .. n })
		table.insert(bones, { name = "Shin" .. n, parent = "Thigh" .. n, pos = Vector3.new(s * hx, F.KneeY, 0), joint = "Knee" .. n })
		table.insert(bones, { name = "Foot" .. n, parent = "Shin" .. n, pos = Vector3.new(s * hx, F.AnkleY, 0), joint = "Ankle" .. n })
	end
	return bones
end

local function bonePart(name: string): BasePart
	local p = make("Block", Vector3.one * 0.2, "frame")
	p.Name = "ExoBone_" .. name
	p.Transparency = 1
	p.CastShadow = false
	return p
end

-- Builds the hoisted walking frame under `root` and returns it plus the
-- HipHeight the Humanoid needs added to carry the rider in it.
-- Layout: the frame is centred on the HumanoidRootPart (same X / Z). The
-- rider's body centre (feet..top) sits at the centre of the frame's torso
-- cage (between waist and shoulders) whatever its size. A small rider stands
-- on a cradle plate hung in the cage; a bigger one's legs hang below the
-- cage on belly straps (legs straddle the frame's hips, which sit at the
-- centre line).
-- The cage (rings at waist and shoulder height, corner posts, spine behind,
-- chest unit + crossing straps in front, shoulder bars arching over) is sized
-- round the rider's body; front / back is capped, so a long creature's head
-- and tail poke out. The arms hang outside the cage, the legs carry it.
function ExoBuilder.buildFrame(char: Model, root: BasePart, m: Measure): (Model, number)
	local model = newModel()
	local ctx: Ctx = { model = model, k = 1, pad = 0, offsets = {} }
	local hw = math.max(m.halfW + 0.2, 0.75) -- cage half width
	local hd = math.clamp(m.halfD + 0.15, 0.5, 1.25) -- cage half depth
	local sx = hw + 0.24 -- shoulder joints just outside the cage
	local hx = math.clamp(hw * 0.55, F.HipX, 0.85)
	-- rider body centre (feet..top) on the torso cage centre, whatever its size;
	-- only kept from pushing its feet into the ground
	local rootH = math.max(TORSO_C - m.centerY, m.feet + 0.4)
	local floorY = rootH - m.feet -- the rider's feet, frame space
	local frameRoot = bonePart("Root")
	frameRoot.CFrame = root.CFrame * CFrame.new(0, -rootH, 0)
	local rootWeld = Instance.new("Weld")
	rootWeld.Name = "ExoWeld"
	rootWeld.Part0 = root
	rootWeld.Part1 = frameRoot
	rootWeld.C0 = CFrame.new(0, -rootH, 0)
	rootWeld.Parent = frameRoot
	frameRoot.Parent = model

	local rest: { [string]: CFrame } = { Root = CFrame.identity }
	local parts: { [string]: BasePart } = { Root = frameRoot }
	for _, b in frameBones(sx, hx) do
		local p = bonePart(b.name)
		rest[b.name] = CFrame.new(b.pos)
		p.CFrame = frameRoot.CFrame * rest[b.name]
		local motor = Instance.new("Motor6D")
		motor.Name = "ExoJoint_" .. b.joint
		motor.Part0 = parts[b.parent]
		motor.Part1 = p
		motor.C0 = rest[b.parent]:Inverse() * rest[b.name]
		motor.Parent = parts[b.parent]
		p.Parent = model
		parts[b.name] = p
	end
	ctx.offsets[frameRoot] = CFrame.identity

	local thighL, shinL = F.HipY - F.KneeY, F.KneeY - F.AnkleY
	local pelvis, chest = parts.Pelvis, parts.Chest
	-- pelvis
	block(ctx, pelvis, Vector3.new(2 * hx + 0.3, 0.4, 0.55), CFrame.new(0, 0, 0.05), "dark", "ExoPelvis")
	block(ctx, pelvis, Vector3.new(2 * hx + 0.36, 0.1, 0.6), CFrame.new(0, 0.18, 0.05), "frame")
	block(ctx, pelvis, Vector3.new(0.5, 0.05, 0.03), CFrame.new(0, 0, -0.24), "glow", "ExoPelvisLight")
	bar(ctx, pelvis, Vector3.new(0, 0.1, 0.2), Vector3.new(0, 0.3, hd + 0.12), 0.2, 0.2, "frame") -- pelvis to spine

	-- torso cage (chest bone space: origin at the waist)
	local shY = F.ShoulderY - WAIST_Y
	local topY = F.NeckY - WAIST_Y
	local yb, yt = 0.02, shY + 0.06
	local zb = hd + 0.12 -- spine behind the cage
	for _, y in { yb, yt } do
		bar(ctx, chest, Vector3.new(-hw, y, -hd), Vector3.new(hw, y, -hd), 0.13, 0.13, "frame", "ExoCageRing")
		bar(ctx, chest, Vector3.new(-hw, y, hd), Vector3.new(hw, y, hd), 0.13, 0.13, "frame", "ExoCageRing")
		for _, s in { 1, -1 } do
			bar(ctx, chest, Vector3.new(s * hw, y, -hd), Vector3.new(s * hw, y, hd), 0.13, 0.13, "frame", "ExoCageRing")
		end
	end
	for _, s in { 1, -1 } do
		for _, z in { -hd, hd } do
			bar(ctx, chest, Vector3.new(s * hw, yb, z), Vector3.new(s * hw, yt, z), 0.12, 0.12, "frame", "ExoCagePost")
		end
	end
	-- spine behind the cage, sensor head on top
	local column = bar(ctx, chest, Vector3.new(0, -0.3, zb), Vector3.new(0, topY, zb), 0.24, 0.24, "frame", "ExoSpine")
	for i = 0, 4 do
		block(ctx, chest, Vector3.new(0.5, 0.1, 0.16), CFrame.new(0, 0.05 + i * (topY - 0.2) / 5, zb + 0.15), "dark", "ExoVertebra")
	end
	block(ctx, chest, Vector3.new(0.06, topY * 0.8, 0.04), CFrame.new(0, topY * 0.45, zb + 0.24), "glow", "ExoSpineLight")
	bar(ctx, chest, Vector3.new(0, topY - 0.05, zb), Vector3.new(0, topY + 0.25, zb), 0.14, 0.14, "frame", "ExoNeckStrut")
	block(ctx, chest, Vector3.new(0.5, 0.3, 0.4), CFrame.new(0, topY + 0.4, zb), "dark", "ExoSensorHead")
	block(ctx, chest, Vector3.new(0.56, 0.06, 0.44), CFrame.new(0, topY + 0.57, zb), "frame")
	block(ctx, chest, Vector3.new(0.4, 0.07, 0.04), CFrame.new(0, topY + 0.42, zb + 0.21), "glow", "ExoSensorLight")

	-- front chest unit (mirrors the worn exo's sternum unit)
	local fz = -hd - 0.08
	local unitY = shY - 0.3
	local uw = math.min(0.8, 2 * hw - 0.2)
	local unit = block(ctx, chest, Vector3.new(uw, 0.5, 0.12), CFrame.new(0, unitY, fz), "dark", "ExoChestUnit")
	block(ctx, chest, Vector3.new(uw * 0.75, 0.3, 0.08), CFrame.new(0, unitY + 0.05, fz - 0.09), "frame", "ExoChestPlate")
	block(ctx, chest, Vector3.new(uw * 0.5, 0.14, 0.06), CFrame.new(0, unitY - 0.2, fz - 0.08) * CFrame.Angles(0.3, 0, 0), "dark")
	for i = -1, 1 do
		block(ctx, chest, Vector3.new(0.06, 0.06, 0.03), CFrame.new(i * uw * 0.18, unitY + 0.05, fz - 0.15), "glow", "ExoChestLight")
	end
	block(ctx, chest, Vector3.new(uw * 0.4, 0.03, 0.03), CFrame.new(0, unitY - 0.12, fz - 0.08), "glow", "ExoChestLight")

	for _, s in { 1, -1 } do
		-- shoulder hub outside the cage
		local hubPos = Vector3.new(s * sx, shY, 0)
		local hub = ball(ctx, chest, hubPos, 0.46, "frame", "ExoShoulderHub")
		disc(ctx, chest, hubPos + Vector3.new(s * 0.22, 0, 0), Vector3.xAxis, 0.2, 0.04, "glow", "ExoHubLight")
		bar(ctx, chest, hubPos, Vector3.new(s * hw, yt, 0), 0.14, 0.14, "frame")
		-- shoulder bar: spine top, over the shoulder, down onto the chest unit
		local backTop = Vector3.new(s * hw * 0.55, yt + 0.22, hd * 0.6)
		local frontTop = Vector3.new(s * hw * 0.55, yt + 0.22, -hd * 0.6)
		bar(ctx, chest, Vector3.new(s * 0.12, topY - 0.15, zb), backTop, 0.15, 0.12, "frame", "ExoShoulderBar")
		bar(ctx, chest, backTop, frontTop, 0.15, 0.12, "frame", "ExoShoulderBar")
		bar(ctx, chest, frontTop, Vector3.new(s * uw * 0.4, unitY + 0.2, fz), 0.15, 0.12, "frame", "ExoShoulderBar")
		ball(ctx, chest, backTop, 0.2, "dark")
		ball(ctx, chest, frontTop, 0.2, "dark")
		-- harness straps crossing in front of the rider
		bar(ctx, chest, Vector3.new(s * hw, yt, -hd - 0.03), Vector3.new(-s * hw, yb, -hd - 0.03), 0.08, 0.08, "dark", "ExoChestStrap")
		-- hose loop chest unit -> shoulder hub
		cable(ctx, unit, Vector3.new(s * uw * 0.45, unitY - 0.1, fz - 0.04), hub, hubPos + Vector3.new(0, -0.1, -0.15), Vector3.new(0, -1, -0.5), 0.35)
		-- back pistons beside the spine
		rod(ctx, chest, Vector3.new(s * 0.32, yb, zb - 0.04), Vector3.new(s * 0.32, yb + 0.6, zb - 0.04), 0.14, "dark")
		rod(ctx, chest, Vector3.new(s * 0.32, yb + 0.55, zb - 0.04), Vector3.new(s * 0.32, yt - 0.05, zb - 0.04), 0.07, "steel")
	end
	cable(ctx, column, Vector3.new(0.1, topY - 0.2, zb - 0.1), unit, Vector3.new(0, unitY + 0.25, fz + 0.05), Vector3.new(0, 1, 0), 0.4, true)

	-- cradle (on the root, so it never moves against the rider): a floor plate
	-- under a small rider's feet, hung from the cage's waist ring; belly
	-- straps across the waist ring when the rider's legs hang below it
	local cy = floorY - 0.04
	if floorY < WAIST_Y - 0.05 then
		for _, z in { -0.5, 0, 0.5 } do
			bar(ctx, frameRoot, Vector3.new(-hw, WAIST_Y + 0.02, z * hd), Vector3.new(hw, WAIST_Y + 0.02, z * hd), 0.1, 0.05, "dark", "ExoBellyStrap")
		end
		block(ctx, frameRoot, Vector3.new(2 * hw - 0.2, 0.04, 0.04), CFrame.new(0, WAIST_Y + 0.06, 0), "glow", "ExoCradleLight")
	else
		block(ctx, frameRoot, Vector3.new(2 * hw - 0.05, 0.08, 2 * hd - 0.05), CFrame.new(0, cy, 0), "dark", "ExoCradle")
		block(ctx, frameRoot, Vector3.new(2 * hw - 0.2, 0.04, 0.04), CFrame.new(0, cy + 0.02, -hd + 0.04), "glow", "ExoCradleLight")
	end
	if cy > WAIST_Y + 0.12 then
		for _, s in { 1, -1 } do
			for _, z in { -1, 1 } do
				local p = Vector3.new(s * (hw - 0.06), 0, z * (hd - 0.06))
				rod(ctx, frameRoot, p + Vector3.new(0, cy, 0), p + Vector3.new(0, WAIST_Y, 0), 0.06, "steel")
			end
		end
	end

	-- legs
	for _, sd in { { "R", 1 }, { "L", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local thigh, shin, foot = parts["Thigh" .. n], parts["Shin" .. n], parts["Foot" .. n]
		disc(ctx, pelvis, Vector3.new(s * hx, F.HipY - F.PelvisY, 0), Vector3.xAxis, 0.46, 0.2, "frame", "ExoHipHub")
		bar(ctx, thigh, Vector3.zero, Vector3.new(0, -thighL, 0), 0.24, 0.24, "frame", "ExoThighStrut")
		block(ctx, thigh, Vector3.new(0.3, 0.7 * thighL, 0.06), CFrame.new(0, -0.45 * thighL, -0.16), "dark", "ExoThighPlate")
		block(ctx, thigh, Vector3.new(0.05, 0.4 * thighL, 0.03), CFrame.new(0, -0.45 * thighL, -0.2), "glow", "ExoThighLight")
		disc(ctx, shin, Vector3.zero, Vector3.xAxis, 0.38, 0.34, "dark", "ExoKnee")
		disc(ctx, shin, Vector3.new(s * 0.18, 0, 0), Vector3.xAxis, 0.16, 0.04, "glow", "ExoKneeLight")
		block(ctx, shin, Vector3.new(0.34, 0.26, 0.1), CFrame.new(0, -0.12, -0.2) * CFrame.Angles(-0.12, 0, 0), "frame", "ExoKneePad")
		bar(ctx, shin, Vector3.zero, Vector3.new(0, -shinL, 0), 0.2, 0.2, "frame", "ExoShinStrut")
		block(ctx, shin, Vector3.new(0.28, 0.5 * shinL, 0.06), CFrame.new(0, -0.5 * shinL, -0.14), "dark", "ExoShinPlate")
		ring(ctx, shin, Vector3.new(0, -shinL + 0.14, 0), 0.22, 0.22, 0.16, 0.06, "frame")
		disc(ctx, foot, Vector3.zero, Vector3.xAxis, 0.26, 0.28, "steel", "ExoAnkle")
		block(ctx, foot, Vector3.new(0.5, 0.2, 1.0), CFrame.new(0, -F.AnkleY + 0.1, -0.18), "dark", "ExoFoot")
		block(ctx, foot, Vector3.new(0.52, 0.1, 0.3), CFrame.new(0, -F.AnkleY + 0.25, -0.5), "frame")
		piston(ctx, thigh, Vector3.new(s * 0.16, -0.25 * thighL, -0.05), shin, Vector3.new(s * 0.16, -0.35 * shinL, 0.12), 0.12, "ExoKneePiston")
	end
	-- arms
	for _, sd in { { "R", 1 }, { "L", -1 } } do
		local n, s = sd[1] :: string, sd[2] :: number
		local ua, fa = parts["UpperArm" .. n], parts["Forearm" .. n]
		bar(ctx, ua, Vector3.zero, Vector3.new(0, -F.UpperArm, 0), 0.18, 0.18, "frame", "ExoUpperArmStrut")
		block(ctx, ua, Vector3.new(0.06, 0.6 * F.UpperArm, 0.26), CFrame.new(s * 0.13, -0.45 * F.UpperArm, 0), "dark", "ExoBicepPlate")
		disc(ctx, fa, Vector3.zero, Vector3.xAxis, 0.32, 0.26, "dark", "ExoElbow")
		disc(ctx, fa, Vector3.new(s * 0.14, 0, 0), Vector3.xAxis, 0.14, 0.03, "glow", "ExoElbowLight")
		bar(ctx, fa, Vector3.zero, Vector3.new(0, -F.Forearm, 0), 0.17, 0.17, "frame", "ExoForearmStrut")
		block(ctx, fa, Vector3.new(0.24, 0.5 * F.Forearm, 0.06), CFrame.new(0, -0.45 * F.Forearm, -0.11), "dark", "ExoForearmPlate")
		ring(ctx, fa, Vector3.new(0, -F.Forearm + 0.1, 0), 0.19, 0.19, 0.16, 0.05, "frame")
		block(ctx, fa, Vector3.new(0.22, 0.2, 0.28), CFrame.new(0, -F.Forearm - 0.12, 0), "dark", "ExoPalm")
		for i = -1, 1 do
			block(ctx, fa, Vector3.new(0.06, 0.24, 0.06), CFrame.new(i * 0.07, -F.Forearm - 0.32, -0.08) * CFrame.Angles(0.25, 0, 0), "frame", "ExoClaw")
		end
		piston(ctx, ua, Vector3.new(s * 0.04, -0.3 * F.UpperArm, 0.15), fa, Vector3.new(s * 0.04, -0.4 * F.Forearm, 0.12), 0.1, "ExoElbowPiston")
	end

	CollectionService:AddTag(model, ExoBuilder.FrameTag)
	model:SetAttribute("ExoForm", "Frame")
	model.Parent = char
	return model, rootH - m.rootH
end

return ExoBuilder
