--!strict
-- The 20-tier steampunk ARMOUR on a character. Each armour slot REPLACES the
-- player's own limbs: the slot's body parts are hidden (Transparency 1, on the
-- server so everyone sees it) together with their face decals, the
-- accessories attached to them (hair / hats under the helmet) and the EXO-1
-- pieces welded to them; then a covering piece is welded centred on every
-- one of those body parts:
--   Arms   UpperArm / LowerArm / Hand   <- ArmR_Upper / ArmR_Lower / ArmR_Hand (+ L)
--   Legs   UpperLeg / LowerLeg / Foot   <- LegR_Upper / LegR_Lower / LegR_Foot (+ L)
--   Chest  UpperTorso                   <- Torso_Upper (covers LowerTorso too when the
--          LowerTorso                   <- Torso_Lower    set has no Torso_Lower)
--          Head                         <- Head (helmet)
-- (R6: each limb part takes its three nodes stacked in thirds.)
--
-- Covering piece = a clone of the tier's MeshPart (GearMeshes; keeps its
-- SurfaceAppearance / TextureID), turned from the source frame into the body
-- part's frame and scaled PER AXIS so it encloses the part x Margin while
-- keeping most of its own proportions (GearAssets.KeepAspect). Without a
-- mesh (no asset id yet / still loading) the piece is a procedural
-- placeholder: a tier-coloured shell around the part plus PartBuilder's
-- family plates recoloured for the tier.
--
--   ArmorBuilder.attach(char, item, parent)   -> (Model, { BasePart } covered)
--   ArmorBuilder.hide(char, covered)          hide covered parts + their extras
--   ArmorBuilder.restore(char)                undo every hide
--   ArmorBuilder.weapon(id, hand, fist?)      -> (Model, C0 in hand space)
--   ArmorBuilder.display(item)                -> loot / preview Model (PrimaryPart Handle)
--   ArmorBuilder.weaponDisplay(id)            -> loot Model (PrimaryPart Handle)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local GearAssets = require(Shared:WaitForChild("GearAssets"))
local GearMeta = require(Shared:WaitForChild("GearMeta"))
local GearMeshes = require(script.Parent:WaitForChild("GearMeshes"))
local PartBuilder = require(script.Parent:WaitForChild("PartBuilder"))

local ArmorBuilder = {}

local HIDE_ATTR = "GearHideT" -- original Transparency of a hidden part / decal
local BEAM_ATTR = "GearHideBeam"
ArmorBuilder.PieceTag = "CoreArmor"

type Cover = {
	part: BasePart, -- body part the piece welds to
	node: string, -- mesh node name
	box: CFrame, -- the covered box, in the part's space
	size: Vector3,
	primary: string, -- "Y" / "Z" / "U" (uniform): the axis fitted exactly
	holding: boolean?, -- the right hand holds a weapon
	joint: string?, -- rig attachment in `part` the node's pivot snaps to
	pivot: string?, -- GearMeta pivot name (shoulder_R, knee_L, neck ...)
}

------------------------------------------------------------------ body

local function bodyPart(char: Instance, name: string): BasePart?
	local p = char:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function headSize(head: BasePart): Vector3
	if head:IsA("MeshPart") then
		return head.Size
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		local s = math.min(head.Size.Y, head.Size.Z) * mesh.Scale.Y
		return Vector3.new(s * 1.2, s, s)
	end
	return head.Size
end

-- Box enclosing `a` (own space) and `b` (its current placement), in a's space.
local function unionBox(a: BasePart, b: BasePart): (CFrame, Vector3)
	local h = a.Size / 2
	local lo, hi = -h, h
	local rel = a.CFrame:ToObjectSpace(b.CFrame)
	local hb = b.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = rel * Vector3.new(sx * hb.X, sy * hb.Y, sz * hb.Z)
				lo = lo:Min(p)
				hi = hi:Max(p)
			end
		end
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end

local SIDES = { { "Right", "R" }, { "Left", "L" } }

-- The covers of `slot` on this character, and the body parts to hide.
function ArmorBuilder.covers(char: Model, slot: string, hasLower: boolean?): ({ Cover }, { BasePart })
	local covers: { Cover } = {}
	local hide: { BasePart } = {}
	local function add(p: BasePart?, node: string, box: CFrame?, size: Vector3?, primary: string?, joint: string?, pivot: string?)
		if not p then
			return
		end
		table.insert(covers, { part = p, node = node, box = box or CFrame.identity, size = size or p.Size, primary = primary or "Y", joint = joint, pivot = pivot })
	end
	local function hidePart(p: BasePart?)
		if p and not table.find(hide, p) then
			table.insert(hide, p)
		end
	end
	local r15 = bodyPart(char, "UpperTorso") ~= nil
	if r15 then
		if slot == "Arms" or slot == "Legs" then
			local names = if slot == "Arms"
				then { { "UpperArm", "_Upper", "Y", "Shoulder" }, { "LowerArm", "_Lower", "Y", "Elbow" }, { "Hand", "_Hand", "Y", "Wrist" } }
				else { { "UpperLeg", "_Upper", "Y", "Hip" }, { "LowerLeg", "_Lower", "Y", "Knee" }, { "Foot", "_Foot", "Z", "Ankle" } }
			local pre = if slot == "Arms" then "Arm" else "Leg"
			for _, side in SIDES do
				for _, n in names do
					local p = bodyPart(char, side[1] .. n[1])
					add(p, pre .. side[2] .. n[2], nil, nil, n[3], side[1] .. n[4] .. "RigAttachment", string.lower(n[4]) .. "_" .. side[2])
					hidePart(p)
				end
			end
		elseif slot == "Chest" then
			local upper = bodyPart(char, "UpperTorso") :: BasePart
			local lower = bodyPart(char, "LowerTorso")
			if lower and not hasLower then
				local box, size = unionBox(upper, lower)
				add(upper, "Torso_Upper", box, size)
			else
				add(upper, "Torso_Upper", nil, nil, "Y", "NeckRigAttachment", "neck")
				add(lower, "Torso_Lower", nil, nil, "Y", "WaistRigAttachment", "waist")
				-- a belt modelled as a front plate only: its turned copy closes the back
				add(lower, "Torso_LowerBack", nil, nil, "Y", "WaistRigAttachment", "waist")
			end
			hidePart(upper)
			hidePart(lower)
			local head = bodyPart(char, "Head")
			if head then
				add(head, "Head", nil, headSize(head), "U", "NeckRigAttachment", "neck")
				hidePart(head)
			end
		end
		return covers, hide
	end
	-- R6: one part per limb, its nodes stacked in thirds (top to bottom)
	local function thirds(p: BasePart?, nodes: { string })
		if not p then
			return
		end
		local h = p.Size.Y
		local cuts = { h / 2, h / 6, -h / 6 - h / 9, -h / 2 }
		for i, node in nodes do
			local top, bot = cuts[i], cuts[i + 1]
			add(p, node, CFrame.new(0, (top + bot) / 2, 0), Vector3.new(p.Size.X, top - bot, p.Size.Z), if i == 3 and string.sub(node, 1, 3) == "Leg" then "Z" else "Y")
		end
		hidePart(p)
	end
	if slot == "Arms" then
		thirds(bodyPart(char, "Right Arm"), { "ArmR_Upper", "ArmR_Lower", "ArmR_Hand" })
		thirds(bodyPart(char, "Left Arm"), { "ArmL_Upper", "ArmL_Lower", "ArmL_Hand" })
	elseif slot == "Legs" then
		thirds(bodyPart(char, "Right Leg"), { "LegR_Upper", "LegR_Lower", "LegR_Foot" })
		thirds(bodyPart(char, "Left Leg"), { "LegL_Upper", "LegL_Lower", "LegL_Foot" })
	elseif slot == "Chest" then
		local torso = bodyPart(char, "Torso")
		if torso then
			add(torso, "Torso_Upper")
			hidePart(torso)
		end
		local head = bodyPart(char, "Head")
		if head then
			add(head, "Head", nil, headSize(head), "U")
			hidePart(head)
		end
	end
	return covers, hide
end

------------------------------------------------------------------ hiding

local function hideInst(inst: Instance)
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		if inst:GetAttribute(HIDE_ATTR) == nil then
			inst:SetAttribute(HIDE_ATTR, (inst :: any).Transparency)
		end
		(inst :: any).Transparency = 1
	end
end

local function hideBeam(b: Beam)
	if b.Enabled then
		b:SetAttribute(BEAM_ATTR, true)
		b.Enabled = false
	end
end

local function weldedTo(p: BasePart, set: { [Instance]: boolean }): boolean
	for _, j in p:GetChildren() do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			local a, b = (j :: any).Part0, (j :: any).Part1
			if (a and set[a]) or (b and set[b]) then
				return true
			end
		end
	end
	return false
end

-- Hides the covered body parts, their decals (the face), the accessories
-- attached to them and the EXO-1 pieces / cables / pistons on them.
function ArmorBuilder.hide(char: Model, covered: { BasePart })
	local set: { [Instance]: boolean } = {}
	for _, p in covered do
		set[p] = true
		hideInst(p)
		for _, d in p:GetChildren() do
			if d:IsA("Decal") then
				hideInst(d)
			end
		end
	end
	-- layered clothing wraps whole regions: hide it when any of them is covered
	local names: { [string]: boolean } = {}
	for _, p in covered do
		names[p.Name] = true
	end
	local arms = names.RightUpperArm or names.LeftUpperArm or names["Right Arm"] or names["Left Arm"]
	local legs = names.RightUpperLeg or names.LeftUpperLeg or names["Right Leg"] or names["Left Leg"]
	local torso = names.UpperTorso or names.Torso
	local feet = names.RightFoot or names.LeftFoot or names["Right Leg"]
	local function layeredHit(acc: Accessory): boolean
		local t = acc.AccessoryType
		local A = Enum.AccessoryType
		if t == A.Jacket or t == A.Sweater or t == A.Shirt or t == A.TShirt then
			return (arms or torso) and true or false
		elseif t == A.Pants or t == A.Shorts or t == A.DressSkirt then
			return (legs or names.LowerTorso) and true or false
		elseif t == A.LeftShoe or t == A.RightShoe then
			return feet and true or false
		end
		return false
	end
	-- an accessory sits on a covered part: welded to it, or its attachment
	-- matches one of the part's (the avatar loader doesn't always leave a weld)
	local function onCovered(handle: BasePart): boolean
		if weldedTo(handle, set) then
			return true
		end
		for _, a in handle:GetChildren() do
			if a:IsA("Attachment") then
				for p in set do
					local m = p:FindFirstChild(a.Name)
					if m and m:IsA("Attachment") then
						return true
					end
				end
			end
		end
		return false
	end
	for _, acc in char:GetChildren() do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local layered = handle and handle:FindFirstChildOfClass("WrapLayer") ~= nil
			if handle and handle:IsA("BasePart") and ((layered and layeredHit(acc)) or onCovered(handle)) then
				hideInst(handle)
				for _, d in handle:GetDescendants() do
					hideInst(d)
				end
			end
		end
	end
	-- EXO-1 (ExoService builds it as "Exoskeleton" in the character)
	local exo = char:FindFirstChild("Exoskeleton")
	if exo then
		local hidden: { [Instance]: boolean } = {}
		for _, d in exo:GetDescendants() do
			if d:IsA("BasePart") and weldedTo(d, set) then
				hidden[d] = true
			end
		end
		-- a piston (Model with Body + Rod) goes as a whole if either end is covered
		for _, m in exo:GetDescendants() do
			if m:IsA("Model") then
				local any = false
				for _, d in m:GetDescendants() do
					if hidden[d] then
						any = true
						break
					end
				end
				if any then
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then
							hidden[d] = true
						end
					end
				end
			end
		end
		for d in hidden do
			hideInst(d)
		end
		for _, b in exo:GetDescendants() do
			if b:IsA("Beam") then
				local a0, a1 = b.Attachment0, b.Attachment1
				local p0 = a0 and a0.Parent
				local p1 = a1 and a1.Parent
				if (p0 and (set[p0] or hidden[p0])) or (p1 and (set[p1] or hidden[p1])) then
					hideBeam(b)
				end
			end
		end
	end
end

function ArmorBuilder.restore(char: Model)
	for _, d in char:GetDescendants() do
		local t = d:GetAttribute(HIDE_ATTR)
		if t ~= nil then
			(d :: any).Transparency = t
			d:SetAttribute(HIDE_ATTR, nil)
		end
		if d:GetAttribute(BEAM_ATTR) then
			(d :: Beam).Enabled = true
			d:SetAttribute(BEAM_ATTR, nil)
		end
	end
end

------------------------------------------------------------------ fitting

-- Extents of a box of local size `s` turned by rotation `r`.
local function extents(r: CFrame, s: Vector3): Vector3
	local x, y, z = r.XVector, r.YVector, r.ZVector
	return Vector3.new(
		math.abs(x.X) * s.X + math.abs(y.X) * s.Y + math.abs(z.X) * s.Z,
		math.abs(x.Y) * s.X + math.abs(y.Y) * s.Y + math.abs(z.Y) * s.Z,
		math.abs(x.Z) * s.X + math.abs(y.Z) * s.Y + math.abs(z.Z) * s.Z
	)
end

local function comp(v: Vector3, axis: number): number
	return if axis == 1 then v.X elseif axis == 2 then v.Y else v.Z
end

-- the target axis (1..3) a local axis vector mostly maps onto
local function dominant(v: Vector3): number
	local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
	return if ax >= ay and ax >= az then 1 elseif ay >= az then 2 else 3
end

-- Rotation turning direction a onto b (at most MAX_ALIGN; identity if degenerate).
local MAX_ALIGN = math.rad(40)
local function fromTo(a: Vector3, b: Vector3): CFrame
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then
		return CFrame.identity
	end
	a, b = a.Unit, b.Unit
	local axis = a:Cross(b)
	local sn = axis.Magnitude
	if sn < 1e-4 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis / sn, math.min(math.atan2(sn, a:Dot(b)), MAX_ALIGN))
end

local function prepClone(t: BasePart): BasePart
	local c = t:Clone()
	for _, d in c:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	c.Anchored = false
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.Massless = true
	c.CastShadow = true
	return c
end

local function weldTo(body: BasePart, p: BasePart, c0: CFrame, parent: Instance)
	p.CFrame = body.CFrame * c0
	local w = Instance.new("Weld")
	w.Name = "ArmorWeld"
	w.Part0 = body
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	p.Parent = parent
end

-- A mesh node's piece fitted onto one cover.
-- Rig fit (meta available, R15): the tier is ONE rig at a uniform scale per
-- limb group (arms / legs / chest, each kept within 10 % of the body-wide
-- average so the authored proportions hold); every node is placed by its
-- meta joint pivot on the matching R15 rig attachment (shoulder on shoulder,
-- neck on neck, ankle on ankle ...). A small per-axis growth (<= Stretch)
-- closes gaps where the avatar is chunkier than the armour.
export type RigScale = {
	Arms: number,
	Legs: number,
	Chest: number,
	raise: number?,
	-- per side ("R" / "L"): how far to move the whole arm / leg (in the limb
	-- parts' rest frame = the torso's) so it meets the armour's own shoulder /
	-- hip on the chest piece instead of the avatar's (narrower) joint
	shift: { [string]: Vector3 },
}

local function attPosIn(part: Instance?, name: string): Vector3?
	local a = part and part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

-- Some tiers' leg pieces were generated facing backwards (toes / knee plates
-- behind the leg). Such a piece is worn turned 180 deg about Y, each side
-- using the OTHER side's node (the mirror of a mirror = the piece reflected
-- front to back, so inner / outer stay right). Boots are detected from
-- GearMeta (the boot's bulk behind the ankle = toes backwards); thighs and
-- shins are kept as modelled. Override per tier with GearAssets.LegsReversed
-- [tier] = { Upper = .., Lower = .., Foot = .. } (or one boolean for all three).
local FLIP_Y = CFrame.Angles(0, math.pi, 0)
local bootCache: { [number]: boolean } = {}
local function bootReversed(tier: number): boolean
	local r = bootCache[tier]
	if r == nil then
		local meta = GearMeta.Tiers[tier]
		r = false
		if meta and meta.centres.LegR_Foot and meta.pivots.ankle_R then
			-- source front is -Z: a boot whose centre is behind the ankle points back
			r = meta.centres.LegR_Foot.Z - meta.pivots.ankle_R.Z > 0.05
		end
		bootCache[tier] = r
	end
	return r
end

-- seg: "Upper" / "Lower" / "Foot"
function ArmorBuilder.legReversed(tier: number, seg: string): boolean
	local o = GearAssets.LegsReversed[tier]
	if type(o) == "boolean" then
		return o
	elseif type(o) == "table" and o[seg] ~= nil then
		return o[seg] == true
	end
	-- only the boots were generated backwards: thighs / shins keep their
	-- modelled front (knee caps, emblems face forward as in the renders)
	return seg == "Foot" and bootReversed(tier)
end

local function otherSide(name: string): string
	return (string.gsub(name, "([RL])(_?)", function(c, u)
		return (if c == "R" then "L" else "R") .. u
	end, 1))
end

-- A Torso_Lower that is only a front plate (nothing behind the waist):
-- the back of the pelvis would show a hole between the chest and the legs.
function ArmorBuilder.beltFrontOnly(tier: number): boolean
	local meta = GearMeta.Tiers[tier]
	local c = meta and meta.centres.Torso_Lower
	local ext = meta and meta.extents and meta.extents.Torso_Lower
	if not (c and ext) then
		return false
	end
	return c.Z + ext.Z / 2 - meta.pivots.waist.Z < 0.2
end

-- The source node worn for `node` (legs of a reversed tier: the other side's;
-- the belt's back copy: the belt) and whether it is worn turned 180 deg.
function ArmorBuilder.sourceNode(tier: number, node: string): (string, boolean)
	if string.sub(node, 1, 3) == "Leg" and ArmorBuilder.legReversed(tier, string.sub(node, 6)) then
		return "Leg" .. otherSide(string.sub(node, 4)), true
	elseif node == "Torso_LowerBack" then
		return "Torso_Lower", true
	end
	return node, false
end

-- meta pivot `name` (hip_R, knee_L, neck ...) in the frame the piece is worn
-- in (`flip`: the piece is worn turned; leg pivots then come from the other side)
local function pivotOf(meta: any, tier: number, name: string, flip: boolean?): Vector3?
	if not flip then
		return meta.pivots[name]
	end
	local leg = string.match(name, "^(%a+)_[RL]$")
	local v = meta.pivots[if leg == "hip" or leg == "knee" or leg == "ankle" then otherSide(name) else name]
	return v and FLIP_Y * v
end

-- Per-group uniform scale of the tier's rig on this R15 body (nil: no rig fit).
function ArmorBuilder.rigScale(char: Model, tier: number): RigScale?
	local meta = GearMeta.Tiers[tier]
	if not meta then
		return nil
	end
	local P = meta.pivots
	local ut = char:FindFirstChild("UpperTorso")
	local ua, la = char:FindFirstChild("RightUpperArm"), char:FindFirstChild("RightLowerArm")
	local ul, ll, ft = char:FindFirstChild("RightUpperLeg"), char:FindFirstChild("RightLowerLeg"), char:FindFirstChild("RightFoot")
	local sh, el1 = attPosIn(ua, "RightShoulderRigAttachment"), attPosIn(ua, "RightElbowRigAttachment")
	local el2, wr = attPosIn(la, "RightElbowRigAttachment"), attPosIn(la, "RightWristRigAttachment")
	local hp, kn1 = attPosIn(ul, "RightHipRigAttachment"), attPosIn(ul, "RightKneeRigAttachment")
	local kn2, an1 = attPosIn(ll, "RightKneeRigAttachment"), attPosIn(ll, "RightAnkleRigAttachment")
	local an2 = attPosIn(ft, "RightAnkleRigAttachment")
	local nk, ws = attPosIn(ut, "NeckRigAttachment"), attPosIn(ut, "WaistRigAttachment")
	if not (sh and el1 and el2 and wr and hp and kn1 and kn2 and an1 and an2 and nk and ws and ft and ft:IsA("BasePart")) then
		return nil
	end
	local arm = ((sh :: Vector3) - el1).Magnitude + ((el2 :: Vector3) - wr).Magnitude
	local armM = (P.shoulder_R - P.elbow_R).Magnitude + (P.elbow_R - P.wrist_R).Magnitude
	local leg = ((hp :: Vector3) - kn1).Magnitude + ((kn2 :: Vector3) - an1).Magnitude + ((an2 :: Vector3).Y + (ft :: BasePart).Size.Y / 2)
	local legM = P.hip_R.Y -- sole at y = 0
	local torso = (nk :: Vector3).Y - (ws :: Vector3).Y
	local torsoM = P.neck.Y - P.waist.Y
	local sa, sl, sc = arm / armM, leg / legM, torso / torsoM
	local avg = (sa + sl + sc) / 3
	-- ONE uniform scale for the whole set (the authored proportions);
	-- lengths are matched per limb segment along the limb only (fitPiece)
	local rig: RigScale = { Arms = avg, Legs = avg, Chest = avg, shift = {} }
	-- the chest piece's own shoulders / hips (its scale: see fitPiece Torso_Upper)
	local cy = math.clamp(torso / torsoM, rig.Chest * 0.8, rig.Chest * 1.3)
	local lt = char:FindFirstChild("LowerTorso")
	local wl = attPosIn(lt, "WaistRigAttachment")
	for _, S in { "R", "L" } do
		local W = if S == "R" then "Right" else "Left"
		local shT = attPosIn(ut, W .. "ShoulderRigAttachment")
		local pS = P["shoulder_" .. S]
		if shT and pS then
			local target = (nk :: Vector3) + (pS - P.neck) * Vector3.new(rig.Chest, cy, rig.Chest)
			-- top of the arm piece vs the avatar's shoulder: keep the arm from riding up
			local d = target - (shT :: Vector3)
			rig.shift["Arm" .. S] = Vector3.new(d.X, math.clamp(d.Y, -0.3, 0.3), d.Z)
		end
		local hpT = attPosIn(lt, W .. "HipRigAttachment")
		local pH = pivotOf(meta, tier, "hip_" .. S, ArmorBuilder.legReversed(tier, "Upper"))
		if hpT and wl and pH then
			local lu = math.min(rig.Chest, 1)
			local target = (wl :: Vector3) + (pH - P.waist) * lu
			local d = target - (hpT :: Vector3)
			rig.shift["Leg" .. S] = Vector3.new(d.X, 0, d.Z) -- never lift / sink the legs
		end
	end
	return rig
end

local STRETCH = 1.12
-- node (side stripped) -> the joint at its lower end (attachment suffix in the
-- same body part, meta pivot prefix); none = the part's / piece's bottom
local SPANS: { [string]: { att: string?, pivot: string? } } = {
	Arm_Upper = { att = "ElbowRigAttachment", pivot = "elbow" },
	Arm_Lower = { att = "WristRigAttachment", pivot = "wrist" },
	Leg_Upper = { att = "KneeRigAttachment", pivot = "knee" },
	Leg_Lower = { att = "AnkleRigAttachment", pivot = "ankle" },
	Leg_Foot = {},
}

local function fitPiece(h: Model, t: BasePart, cv: Cover, parent: Instance, tier: number, rig: RigScale?): BasePart
	local rot = GearMeshes.importRotation(h) * t.CFrame.Rotation
	local src, flip = ArmorBuilder.sourceNode(tier, cv.node)
	local node = if cv.node == "Torso_LowerBack" then "Torso_Lower" else cv.node -- fit rules
	if flip then
		rot = FLIP_Y * rot
	end
	local turned = false
	-- an arm modelled in a T-pose (long along X): swing it down along the side
	if string.sub(cv.node, 1, 3) == "Arm" then
		local e = extents(rot, t.Size)
		if e.X > e.Y * 1.15 then
			local right = string.sub(cv.node, 4, 4) == "R"
			rot = CFrame.Angles(0, 0, if right then -math.pi / 2 else math.pi / 2) * rot
			turned = true
		end
	end
	local ext = extents(rot, t.Size)
	local meta = GearMeta.Tiers[tier]
	local centre = meta and meta.centres[src]
	if centre and flip then
		centre = FLIP_Y * centre
	end
	local piv = meta and cv.pivot and pivotOf(meta, tier, cv.pivot, flip)
	local att = cv.joint and cv.part:FindFirstChild(cv.joint)
	local scale: Vector3
	local place = cv.box
	local jointBall: { pos: Vector3, d: number }? = nil
	local group = if string.sub(cv.node, 1, 3) == "Arm" then "Arms" elseif string.sub(cv.node, 1, 3) == "Leg" then "Legs" else "Chest"
	if rig and centre and piv and att and att:IsA("Attachment") and not turned then
		local u = (rig :: any)[group] :: number
		local align = CFrame.identity
		local top = Vector3.zero -- the piece's top joint moved off the rig joint (thighs)
		if node == "Torso_Lower" then
			u = math.min(u, 1) -- the belt / pelvis never grows past its authored size
		elseif string.sub(cv.node, 5) == "_Hand" then
			-- hands: an armoured gauntlet fist at the set's own scale (the
			-- authored hand is about as wide as the forearm cuff), never sized
			-- from the avatar's small bare hand
			u *= GearAssets.HandScale
		end
		-- small capped growth per axis where the body part pokes out
		local target = cv.size * 1.04
		local grow = if string.sub(cv.node, 5) == "_Hand" then 1 else STRETCH
		local g = Vector3.new(
			math.clamp(target.X / (ext.X * u), 1, grow),
			math.clamp(target.Y / (ext.Y * u), 1, grow),
			math.clamp(target.Z / (ext.Z * u), 1, grow)
		)
		scale = g * u
		if node == "Torso_Lower" then
			-- bridge the waist (chest bottom) down past the hips (thigh tops):
			-- no dark band between chest and legs
			local hipA = cv.part:FindFirstChild("RightHipRigAttachment")
			if hipA and hipA:IsA("Attachment") then
				local spanA = (att :: Attachment).Position.Y - hipA.Position.Y + 0.3
				local spanM = piv.Y - (centre.Y - ext.Y / 2)
				if spanM > 0.02 then
					scale = Vector3.new(scale.X, math.clamp(spanA / spanM, scale.Y, scale.X * 4), scale.Z)
				end
			end
			-- no bulging seat: depth at most 1.3x the pelvis
			local maxZ = cv.size.Z * 1.3
			if ext.Z * scale.Z > maxZ then
				scale = Vector3.new(scale.X, scale.Y, maxZ / ext.Z)
			end
		end
		-- limb segments: stretch along the limb so the piece spans this
		-- avatar's joint to joint (the armour's own upper / lower split
		-- differs from R15's), within 0.7 .. 1.8 of the rig scale
		local span = SPANS[string.gsub(cv.node, "^(%a%a%a)[RL]_", "%1_")]
		if span then
			local sideL = string.sub(cv.node, 4, 4)
			local sideW = if sideL == "R" then "Right" else "Left"
			local aTop = (att :: Attachment).Position
			local bottomAvatar: Vector3
			local b = span.att and cv.part:FindFirstChild(sideW .. span.att)
			if b and b:IsA("Attachment") then
				bottomAvatar = b.Position
			else
				bottomAvatar = Vector3.new(aTop.X, -cv.part.Size.Y / 2, aTop.Z)
			end
			local bottomMeta: Vector3 = if span.pivot
				then pivotOf(meta, tier, span.pivot .. "_" .. sideL, flip) :: Vector3
				else Vector3.new(piv.X, centre.Y - ext.Y / 2, piv.Z)
			local spanA = (aTop - bottomAvatar).Magnitude
			if node == "Leg_Upper" or string.match(node, "^Leg[RL]_Upper$") then
				-- the thigh reaches up to the top of the avatar's thigh part (it
				-- pokes up past the hip joint into the pelvis on most bodies):
				-- the hips are covered instead of showing a hole under the chest
				local up = math.clamp(cv.part.Size.Y / 2 - 0.08 - aTop.Y, 0, spanA * 0.5)
				if up > 0.02 and spanA > 0.05 then
					local dir = (aTop - bottomAvatar).Unit
					top = dir * up
					spanA += up
				end
			end
			local spanM = (piv - bottomMeta).Magnitude
			if spanA > 0.05 and spanM > 0.05 then
				local sy = math.clamp(spanA / spanM, u * 0.7, u * 1.8)
				scale = Vector3.new(scale.X, math.max(sy, scale.Y * 0.98), scale.Z)
			end
			-- limb segments run joint to joint: an avatar whose rest pose is
			-- angled (A-pose bodies, the elbow out from the shoulder) gets the
			-- piece turned about its top joint onto that line
			if span.att then
				align = fromTo((bottomMeta - piv) * scale, bottomAvatar - aTop)
			end
		elseif string.sub(cv.node, 5) == "_Hand" then
			-- the fist continues the forearm's line (same turn as the forearm)
			local sideL = string.sub(cv.node, 4, 4)
			local sideW = if sideL == "R" then "Right" else "Left"
			local lower = cv.part.Parent and cv.part.Parent:FindFirstChild(sideW .. "LowerArm")
			local e = lower and lower:FindFirstChild(sideW .. "ElbowRigAttachment")
			local wl = lower and lower:FindFirstChild(sideW .. "WristRigAttachment")
			if e and wl and e:IsA("Attachment") and wl:IsA("Attachment") then
				-- the hand's rest placement in the forearm's space
				local handInLower = wl.CFrame * (att :: Attachment).CFrame:Inverse()
				local dA = handInLower:VectorToObjectSpace(wl.Position - e.Position)
				align = fromTo(meta.pivots["wrist_" .. sideL] - meta.pivots["elbow_" .. sideL], dA)
			end
		elseif cv.node == "Torso_Upper" then
			local w = cv.part:FindFirstChild("WaistRigAttachment")
			if w and w:IsA("Attachment") then
				local spanA = (att :: Attachment).Position.Y - w.Position.Y
				local spanM = piv.Y - meta.pivots.waist.Y
				if spanA > 0.05 and spanM > 0.05 then
					scale = Vector3.new(scale.X, math.clamp(spanA / spanM, u * 0.8, u * 1.3), scale.Z)
				end
			end
		end
		local o = (piv - centre) * scale
		local shift = (rig :: RigScale).shift[string.sub(cv.node, 1, 4)] or Vector3.zero
		place = CFrame.new(att.Position + shift + top) * align * CFrame.new(-o)
		local seg = string.sub(cv.node, 5)
		if seg == "_Lower" then
			-- a dark bearing in the elbow / knee: a bent joint would otherwise
			-- show the open (flat dark capped) top of the forearm / shin piece
			local e = ext * scale
			jointBall = { pos = att.Position + shift + top, d = math.min(e.X, e.Z) * 0.5 }
		end
		if cv.node == "LegR_Foot" and rig then
			-- how far the boot's sole sits below the foot's own bottom
			local sole = att.Position.Y - (piv.Y - 0) * scale.Y
			rig.raise = math.max(rig.raise or 0, -cv.part.Size.Y / 2 - sole)
		end
	else
		local target = cv.size * GearAssets.Margin
		local s = Vector3.new(target.X / math.max(ext.X, 1e-3), target.Y / math.max(ext.Y, 1e-3), target.Z / math.max(ext.Z, 1e-3))
		if cv.primary == "U" then
			local m = math.max(s.X, s.Y, s.Z)
			scale = Vector3.new(m, m, m)
		else
			local p = if cv.primary == "Z" then s.Z else s.Y
			local k = p * GearAssets.KeepAspect
			scale = Vector3.new(math.max(s.X, k), math.max(s.Y, k), math.max(s.Z, k))
			scale = if cv.primary == "Z" then Vector3.new(scale.X, scale.Y, s.Z) else Vector3.new(scale.X, s.Y, scale.Z)
		end
	end
	-- local axis i lands on body axis dominant(rot column i)
	local cols = { rot.XVector, rot.YVector, rot.ZVector }
	local sz = t.Size
	local c = prepClone(t)
	c.Name = cv.node
	c.Size = Vector3.new(sz.X * comp(scale, dominant(cols[1])), sz.Y * comp(scale, dominant(cols[2])), sz.Z * comp(scale, dominant(cols[3])))
	CollectionService:AddTag(c, ArmorBuilder.PieceTag)
	weldTo(cv.part, c, place * rot, parent)
	if jointBall then
		local b = Instance.new("Part")
		b.Name = cv.node .. "_Joint"
		b.Shape = Enum.PartType.Ball
		b.Size = Vector3.one * jointBall.d
		b.Material = Enum.Material.Metal
		-- the tier's metal, darkened: reads as part of the suit, not a black ball
		local info = CoreLoopConfig.Tiers[tier]
		b.Color = if info then info.color:Lerp(Color3.new(0, 0, 0), 0.55) else Color3.fromRGB(40, 38, 36)
		b.TopSurface = Enum.SurfaceType.Smooth
		b.BottomSurface = Enum.SurfaceType.Smooth
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.Massless = true
		CollectionService:AddTag(b, ArmorBuilder.PieceTag)
		weldTo(cv.part, b, CFrame.new(jointBall.pos), parent)
	end
	return c
end

------------------------------------------------------------------ placeholder

local function material(tier: number): Enum.Material
	if tier <= 3 then
		return Enum.Material.CorrodedMetal
	elseif tier <= 9 then
		return Enum.Material.DiamondPlate
	end
	return Enum.Material.Metal
end

-- A tier-coloured shell around the cover's box (hides the limb fully).
local function shell(cv: Cover, tier: number, parent: Instance)
	local info = CoreLoopConfig.Tiers[tier]
	local p = Instance.new("Part")
	p.Name = "Shell_" .. cv.node
	local size = cv.size * Vector3.new(1.1, 1.04, 1.1)
	if cv.node == "Head" then
		size = cv.size * 1.18
	end
	p.Size = size
	p.Color = info.color:Lerp(Color3.new(0, 0, 0), 0.35)
	p.Material = material(tier)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	CollectionService:AddTag(p, ArmorBuilder.PieceTag)
	weldTo(cv.part, p, cv.box, parent)
	if cv.node == "Head" then
		-- helmet visor
		local v = Instance.new("Part")
		v.Name = "Visor"
		v.Size = Vector3.new(size.X * 0.8, size.Y * 0.16, 0.08)
		v.Color = info.glow
		v.Material = Enum.Material.Neon
		v.Anchored = false
		v.CanCollide = false
		v.CanQuery = false
		v.CanTouch = false
		v.Massless = true
		v.CastShadow = false
		weldTo(cv.part, v, cv.box * CFrame.new(0, size.Y * 0.08, -size.Z / 2 - 0.03), parent)
	end
end

------------------------------------------------------------------ public

-- Builds the item's armour on the character; returns the model (parented to
-- `parent`) and the body parts it covers (to hide).
function ArmorBuilder.attach(char: Model, item: any, parent: Instance): (Model, { BasePart })
	local tier = math.clamp(item.tier or 1, 1, CoreLoopConfig.MaxTier)
	local slot = item.slot or "Arms"
	local model = Instance.new("Model")
	model.Name = "Gear_" .. slot
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Tier", tier)
	local h = GearMeshes.tier(tier)
	if not h then
		GearMeshes.request(tier)
	end
	local hasLower = h ~= nil and GearMeshes.node(h :: Model, "Torso_Lower") ~= nil
	local covers, hide = ArmorBuilder.covers(char, slot, hasLower)
	for _, cv in covers do
		cv.holding = item.holding == true
	end
	local meshed = 0
	if h then
		local rig = ArmorBuilder.rigScale(char, tier)
		for _, cv in covers do
			local t = GearMeshes.node(h, (ArmorBuilder.sourceNode(tier, cv.node)))
			if cv.node == "Torso_LowerBack" and not ArmorBuilder.beltFrontOnly(tier) then
				continue
			end
			if t then
				local ok, err = pcall(fitPiece, h, t, cv, model, tier, rig)
				if ok then
					meshed += 1
				else
					warn("[ArmorBuilder] fit failed", cv.node, err)
					shell(cv, tier, model)
				end
			else
				shell(cv, tier, model)
			end
		end
		model:SetAttribute("Mesh", true)
		-- boots taller than the feet: the character stands on them (Gear raises HipHeight)
		if slot == "Legs" and rig and (rig.raise or 0) > 0.02 then
			model:SetAttribute("HipRaise", rig.raise)
		end
	else
		for _, cv in covers do
			shell(cv, tier, model)
		end
		-- the family plates on top (PartBuilder, recoloured for the tier)
		local body = PartBuilder.readBody(char)
		if body then
			local ok, err = pcall(PartBuilder.attach, body, { slot = slot, tier = tier }, model)
			if not ok then
				warn("[ArmorBuilder] placeholder plates failed", slot, err)
			end
		end
		model:SetAttribute("Mesh", false)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.Anchored = false
		end
	end
	model.Parent = parent
	return model, hide
end

------------------------------------------------------------------ weapons

-- grip point (hand space) and the default weapon frame (see weapon())
local function handGrip(hand: BasePart): Vector3
	if hand.Name == "Right Arm" then
		return Vector3.new(0, -hand.Size.Y / 2 + 0.05, 0)
	end
	return Vector3.new(0, -0.15, 0)
end

local function weaponLength(w: CoreLoopConfig.Weapon): number
	return (if w.ranged then GearAssets.RangedLength else GearAssets.MeleeLength) + w.tier * GearAssets.LengthPerTier
end

-- Mesh weapon: the node's centre relative to the grip, in the source frame.
local function gripCentre(h: Model, t: BasePart, srcRot: CFrame, ranged: boolean): Vector3
	local known = GearMeta.WeaponCentres[t.Name]
	if known then
		return known -- meta.json: bbox centre relative to the grip
	end
	local flip = GearMeshes.importRotation(h)
	local c = flip * (t.Position - h:GetPivot().Position)
	local ext = extents(srcRot, t.Size)
	if c.Magnitude <= ext.Magnitude * 0.6 then
		return c
	end
	-- the pivot isn't the file's origin: grip near the weapon's back / bottom end
	if ranged then
		return Vector3.new(0, ext.Y * 0.2, -ext.Z * 0.22)
	end
	if ext.Y >= ext.Z and ext.Y >= ext.X then
		return Vector3.new(0, ext.Y * 0.38, 0)
	elseif ext.Z >= ext.X then
		return Vector3.new(0, 0, -ext.Z * 0.38)
	end
	return Vector3.new(ext.X * 0.38, 0, 0)
end

-- Rotation taking the weapon's source frame into hand space: its pointing
-- direction `d` (blade / barrel, from the grip) runs out of the fist along
-- the forearm (hand -Y), its `up` faces the hand's front (-Z). Melee then
-- points along the forearm; ranged points forward whenever the forearm does
-- (aiming, and the ready pose the client holds).
-- Rotation taking source direction d -> dT and up -> upT (hand space).
local function toHand(d: Vector3, up: Vector3, dT: Vector3, upT: Vector3): CFrame
	up = (up - d * up:Dot(d))
	up = if up.Magnitude > 1e-3 then up.Unit else (if math.abs(d.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis)
	local S = CFrame.fromMatrix(Vector3.zero, d:Cross(up), d, up)
	local T = CFrame.fromMatrix(Vector3.zero, dT:Cross(upT), dT, upT)
	return T * S:Inverse()
end

local function snapAxis(v: Vector3): Vector3
	local a = dominant(v)
	local s = if comp(v, a) >= 0 then 1 else -1
	return if a == 1 then Vector3.xAxis * s elseif a == 2 then Vector3.yAxis * s else Vector3.zAxis * s
end

local function meshWeapon(id: string, w: CoreLoopConfig.Weapon): (BasePart?, CFrame?)
	local h = GearMeshes.weapons()
	if not h then
		GearMeshes.request("Weapons")
		return nil, nil
	end
	local t = GearMeshes.node(h, "W_" .. id)
	if not t then
		return nil, nil
	end
	local srcRot = GearMeshes.importRotation(h) * t.CFrame.Rotation
	local ranged = w.ranged == true
	local c = gripCentre(h, t, srcRot, ranged)
	local ext = extents(srcRot, t.Size)
	-- pointing direction: along the longest axis, toward the centre
	local d: Vector3
	if ranged then
		d = if math.abs(c.Z) > 1e-3 then Vector3.new(0, 0, if c.Z < 0 then -1 else 1) else -Vector3.zAxis
		if ext.X > ext.Z * 1.3 then
			d = Vector3.new(if c.X < 0 then -1 else 1, 0, 0)
		end
	else
		local axis = snapAxis(Vector3.new(ext.X, ext.Y, ext.Z) * Vector3.new(0.9, 1, 1)) -- prefer Y on ties
		local along = c:Dot(axis)
		d = if along < 0 then -axis else axis
	end
	local up = if ranged then Vector3.yAxis else -Vector3.zAxis
	if math.abs(up:Dot(d)) > 0.9 then
		up = if ranged then -Vector3.zAxis else Vector3.xAxis
	end
	local k = weaponLength(w) / math.max(ext.X, ext.Y, ext.Z, 1e-3)
	local p = prepClone(t)
	p.Size = t.Size * k
	p.Name = if ranged then "Gun" else "Blade"
	-- grip in the clone's own (scaled) space
	local gripLocal = srcRot:Inverse():VectorToWorldSpace(-c) * k
	-- ranged: barrel along the forearm (forward when aiming / in the ready
	-- pose); melee: blade out of the top of the fist (hand -Z = up and a bit
	-- forward in the ready pose, forward on a swing), heavy side leading
	local rotHand = if ranged
		then toHand(d, up, -Vector3.yAxis, -Vector3.zAxis) * srcRot
		else toHand(d, up, -Vector3.zAxis, -Vector3.yAxis) * srcRot
	return p, rotHand * CFrame.new(-gripLocal)
end

-- The weapon model (PrimaryPart "Handle" = the grip) and the Weld C0 that
-- puts it in `hand`. Mesh when loaded, else PartBuilder's placeholder.
-- `fist` (optional): the armoured hand piece on `hand`; the grip then sits in
-- its centre (the armour arm is moved out to the chest piece's shoulders, so
-- the bare hand's grip would leave the weapon floating beside the gauntlet).
function ArmorBuilder.weapon(id: string, hand: BasePart, fist: BasePart?): (Model, CFrame)
	local w = CoreLoopConfig.Weapons[id] or CoreLoopConfig.Weapons.Fists
	local gripPos = handGrip(hand)
	if fist then
		local wld = fist:FindFirstChild("ArmorWeld")
		if wld and wld:IsA("Weld") and wld.Part0 == hand then
			gripPos = wld.C0.Position + Vector3.new(0, -0.05, 0)
		end
	end
	local grip = CFrame.new(gripPos)
	local okMesh, p, off = pcall(meshWeapon, id, w)
	if okMesh and p and off then
		if w.ranged then
			-- the gun's grip point sits at the top of its pistol grip: raise the
			-- gun (hand -Z = up in the ready pose) so the handle is in the fist
			-- (GunGrip[id]: the pistol grip sits that far (x length) ahead of
			-- the file's grip point: slide the gun back so the fist is on it)
			local len = weaponLength(w)
			local fwd = GearAssets.GunGrip[id] or 0
			grip = CFrame.new(gripPos + Vector3.new(0, fwd * len, -GearAssets.RangedGripLift * len))
		end
		local model = Instance.new("Model")
		model.Name = "Weapon_" .. id
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.2, 0.2, 0.2)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
		handle.Massless = true
		handle.Parent = model
		model.PrimaryPart = handle
		weldTo(handle, p :: BasePart, off :: CFrame, model)
		model:SetAttribute("Mesh", true)
		return model, grip
	end
	local m = PartBuilder.weapon(CoreLoopConfig.weaponAnim(id))
	-- tint the placeholder's glow to the weapon's tier, grow it with the tier
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Color = w.color
		end
	end
	local s = 1 + (w.tier or 0) * 0.02
	if s ~= 1 then
		m:ScaleTo(s)
	end
	m:SetAttribute("Mesh", false)
	return m, grip * PartBuilder.gripOffset
end

------------------------------------------------------------------ displays

local SLOT_NODES = {
	Arms = { "ArmR_Upper", "ArmR_Lower", "ArmR_Hand", "ArmL_Upper", "ArmL_Lower", "ArmL_Hand" },
	Legs = { "LegR_Upper", "LegR_Lower", "LegR_Foot", "LegL_Upper", "LegL_Lower", "LegL_Foot" },
	Chest = { "Torso_Upper", "Torso_Lower", "Head" },
}
local DISPLAY_HEIGHT = { Arms = 2.6, Legs = 3.2, Chest = 3.0 }

local function handleModel(name: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = model
	model.PrimaryPart = handle
	return model, handle
end

-- Loot / locker-preview model of an armour item: the tier's meshes as laid
-- out in the file (both arms / both legs / chest + helmet), else
-- PartBuilder's placeholder display.
function ArmorBuilder.display(item: any): Model
	local tier = math.clamp(item.tier or 1, 1, CoreLoopConfig.MaxTier)
	local h = GearMeshes.tier(tier)
	local nodes = SLOT_NODES[item.slot or "Arms"]
	if h and nodes then
		local flip = GearMeshes.importRotation(h)
		local parts: { BasePart } = {}
		for _, n in nodes do
			-- reversed legs: the other side's node turned around (see sourceNode)
			local src, turn = ArmorBuilder.sourceNode(tier, n)
			local t = GearMeshes.node(h, src)
			if t then
				local c = prepClone(t)
				c.CFrame = (if turn then FLIP_Y else CFrame.identity) * flip * t.CFrame
				table.insert(parts, c)
			end
		end
		if #parts > 0 then
			local model, handle = handleModel("Loot_" .. tostring(item.slot))
			local tmp = Instance.new("Model")
			for _, p in parts do
				p.Parent = tmp
			end
			local cf, size = tmp:GetBoundingBox()
			local k = (DISPLAY_HEIGHT[item.slot] or 3) / math.max(size.Y, 1e-3)
			for _, p in parts do
				local rel = cf.Rotation:Inverse() * (p.CFrame - cf.Position)
				p.Size *= k
				weldTo(handle, p, rel.Rotation + rel.Position * k, model)
			end
			tmp:Destroy()
			return model
		end
	end
	if not h then
		GearMeshes.request(tier)
	end
	return PartBuilder.display({ slot = item.slot, tier = tier })
end

function ArmorBuilder.weaponDisplay(id: string): Model
	local w = CoreLoopConfig.Weapons[id] or CoreLoopConfig.Weapons.Fists
	local okMesh, p = pcall(meshWeapon, id, w)
	if okMesh and p then
		local model, handle = handleModel("Weapon_" .. id)
		weldTo(handle, p :: BasePart, CFrame.identity, model)
		return model
	end
	local m = PartBuilder.weapon(CoreLoopConfig.weaponAnim(id))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Color = w.color
		end
	end
	return m
end

return ArmorBuilder
