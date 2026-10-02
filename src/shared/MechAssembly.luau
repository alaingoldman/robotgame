--!strict
-- Puts the separately built mech pieces together into ONE rigged model:
--   LegBuilder  (MechLegs: pelvis, thighs, boots)
--   ChestBuilder (MechChest: torso + shoulder pads) on legs.Pelvis
--   HeadBuilder (MechHead) on the chest's NeckSocket
--   ArmBuilder  (RightArm / LeftArm) on the chest's shoulder sockets
-- The result is one Motor6D tree rooted at the pelvis, ready for animation:
--
--   Pelvis (PrimaryPart, root)
--   +- RightHip -> RightThigh -> RightKnee -> Shin -> Ankle -> Foot   (LegBuilder / BootBuilder)
--   +- LeftHip  -> LeftThigh  -> LeftKnee  -> Shin -> Ankle -> Foot
--   +- Waist -> Chest
--      +- NeckMount -> Collar -> Neck -> Head                        (HeadBuilder)
--      +- RightShoulderMount -> RightArmRoot -> RightShoulder -> RightUpperArm
--      |     -> RightElbow -> RightLowerArm -> RightWrist -> RightHand -> fingers / thumb
--      +- LeftShoulderMount  -> LeftArmRoot  -> ... (mirrored)
--
-- Each Motor6D is parented to its Part0. Every part is unanchored and welded
-- to its bone; anchor the Pelvis (or drive it) to place the mech. The model's
-- WorldPivot is the ground point between the feet (leg space origin), so
-- model:PivotTo(CFrame.new(x, groundY, z)) stands it on the ground, facing -Z.
--
-- The shoulder sockets come from ArmBuilder.Shoulder* (one source of truth,
-- measured off the full-body sheet), so the arm roots land exactly on them.

local ArmBuilder = require(script.Parent.ArmBuilder)
local BootBuilder = require(script.Parent.BootBuilder)
local ChestBuilder = require(script.Parent.ChestBuilder)
local HeadBuilder = require(script.Parent.HeadBuilder)
local LegBuilder = require(script.Parent.LegBuilder)

local MechAssembly = {}

export type BuildOptions = {
	colors: { [string]: Color3 }?,
	arms: ArmBuilder.BuildOptions?, -- splay / elbowBend / fingerCurl, both arms
	armR: ArmBuilder.BuildOptions?, -- per-side overrides (default: the sheet's poses)
	armL: ArmBuilder.BuildOptions?,
}

local function motor(name: string, p0: BasePart, p1: BasePart): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
	m.C1 = CFrame.identity
	m.Parent = p0
	return m
end

function MechAssembly.build(scale: number?, opts: BuildOptions?): Model
	local sc = scale or BootBuilder.DefaultScale
	local o = opts or {}

	local model = Instance.new("Model")
	model.Name = "AssembledMech"
	model:SetAttribute("Scale", sc)

	-- legs: built in leg space, ground at y = 0
	local legs = LegBuilder.build(sc, { colors = o.colors })
	legs.Parent = model
	local pelvis = legs:FindFirstChild("Pelvis") :: BasePart

	-- chest on the pelvis
	local chest = ChestBuilder.build(sc, { colors = o.colors })
	chest:PivotTo(pelvis.CFrame * ChestBuilder.pelvisOffset(sc))
	chest.Parent = model
	local chestBone = chest:FindFirstChild("Chest") :: BasePart
	motor("Waist", pelvis, chestBone)

	-- head on the neck socket
	local head = HeadBuilder.build(sc, { colors = o.colors })
	local neckSocket = chestBone:FindFirstChild("NeckSocket") :: Attachment
	head:PivotTo(neckSocket.WorldCFrame)
	head.Parent = model
	motor("NeckMount", chestBone, head:FindFirstChild("Collar") :: BasePart)

	-- arms on the shoulder sockets
	-- the sheet poses the two hands differently (FRONT view): the right hand
	-- (screen left) curls its fingers right in under the palm, the left one is
	-- an open claw with the thumb held closer to the palm
	local perSide: { [string]: ArmBuilder.BuildOptions } = {
		R = { fingerCurl = 1.45, thumbSpread = 36, loop = false },
		L = { fingerCurl = 0.8, thumbSpread = 40 },
	}
	for _, side in { "R", "L" } do
		local n = if side == "R" then "Right" else "Left"
		local armOpts: ArmBuilder.BuildOptions = table.clone(perSide[side])
		for k, v in (o.arms or {}) :: any do
			(armOpts :: any)[k] = v
		end
		for k, v in ((if side == "R" then o.armR else o.armL) or {}) :: any do
			(armOpts :: any)[k] = v
		end
		if o.colors and not armOpts.colors then
			armOpts.colors = o.colors
		end
		local arm = ArmBuilder.build(sc, side, armOpts)
		local socket = chestBone:FindFirstChild(n .. "ShoulderSocket") :: Attachment
		arm:PivotTo(socket.WorldCFrame)
		arm.Parent = model
		motor(n .. "ShoulderMount", chestBone, arm:FindFirstChild(n .. "ArmRoot") :: BasePart)
	end

	model.PrimaryPart = pelvis
	pelvis.PivotOffset = pelvis.CFrame:Inverse() -- model pivot = ground point (leg space origin)
	return model
end

return MechAssembly
