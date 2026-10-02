--!strict
-- Builds the mech's LEGS: hips / pelvis + both thighs, standing on the
-- BootBuilder boots (knee down). Standalone piece, from the owner's second
-- reference sheet (FRONT / BACK views, thighs and hips over the boots); not
-- wired into any mech yet.
--
-- Same method and units as BootBuilder: everything is in GRID CELLS read off
-- the sheet (BootBuilder.CELL design units per cell, times `scale`). Leg
-- space: origin on the ground midway between the feet, +Y up, toe toward -Z.
-- Front-view polygons are { ox, h } pairs: ox = distance out from the
-- centreline toward the leg's own side (mirrored per side), h = height above
-- the ground. The sheet has no side view, so depths (z ranges) are inferred
-- from the boots: the thigh sits over the knee guard, from just behind the
-- knee joint to the front of the knee guard.
--
-- Sheet measurements (cells):                 sheet      built
--   waist band top / bottom                   23.6/21.6  23.4/21.6
--   hip plate top / outer / bottom            23.4/5.85/18.0  same
--   hip disc centre (ox, h), radius           3.75, 19.0, 0.55  same
--   thigh outer / inner edge (ox)             5.85 / 1.6  same
--   thigh bottom (front, inner / outer)       12.1 / 13.9  same
--   knee cap panel (front)                    14.45..12.2  same
--   dark knee band (front / back)             10.6..12 / 10.8..13  10.4..13.1
--   crotch plate: top / shoulders / point     21.85/19.9/15.5  same
--   back pelvis plate h, dark tail point      22.1..18.4, 15.4  same
--
-- Rig (all invisible bones, Motor6Ds named like MechBuilder's):
--   Pelvis (PrimaryPart, the model's pivot, at hip height)
--   RightThigh <- RightHip (Pelvis)      LeftThigh <- LeftHip (Pelvis)
--   BootR.Shin <- RightKnee (RightThigh)  BootL.Shin <- LeftKnee (LeftThigh)
--   Foot <- Ankle (Shin), inside each boot (BootBuilder)
-- The boots are BootBuilder.build(scale, side, { thighStub = false }) models
-- parented inside this one.

local BootBuilder = require(script.Parent.BootBuilder)

local LegBuilder = {}

local G = BootBuilder.Geometry

type Pt = { number }

-- ===== Proportions (grid cells) ==========================================

local STANCE = 9.2 -- boot centre to centre (same as BootBuilder)
local HIP: Pt = { 3.9, 19.0 } -- hip joint (ox, h); z below
local HIP_Z = -1.5
local PELVIS_Z = -1.5

-- waist / pelvis core (dark)
local WAIST = { halfW = 1.95, bottom = 21.6, top = 23.4, zFront = -3.0, zBack = 1.0 }
local PELVIS_CORE = { halfW = 1.6, bottom = 17.2, top = 21.6, zFront = -3.1, zBack = 0.95 }
-- dark belt band behind the crotch / hip plates (full-body sheet: solid +-5.5 at h 20 .. 22.5)
local BELT = { halfW = 3.4, bottom = 19.9, top = 22.45, zFront = -3.05, zBack = 1.15 }

-- crotch: upper hexagon plate + pointed shield (two halves forming a ridge)
local CROTCH_UPPER: { Pt } = { { -1.12, 21.85 }, { 1.12, 21.85 }, { 1.87, 21.4 }, { 1.87, 19.95 }, { -1.87, 19.95 }, { -1.87, 21.4 } }
local CROTCH_UPPER_Z = { -3.75, -2.6 }
local CROTCH_HALF: { Pt } = { { 0, 19.85 }, { 1.82, 19.85 }, { 1.55, 18.6 }, { 1.1, 17.3 }, { 0.6, 16.4 }, { 0, 15.65 } } -- long shield to a point (full-body sheet)
local CROTCH_Z = { -3.9, -3.25 } -- front face at the centre ridge, thickness
local CROTCH_ANGLE = math.rad(18) -- each half swept back from the centre ridge

-- back pelvis plate, raised centre panel, dark tail
local BACK_PLATE: { Pt } = { { -1.85, 22.1 }, { 1.85, 22.1 }, { 1.85, 19.4 }, { 0.85, 18.4 }, { -0.85, 18.4 }, { -1.85, 19.4 } }
local BACK_PLATE_Z = { 0.5, 1.4 }
local BACK_PANEL: { Pt } = { { -0.8, 22.0 }, { 0.8, 22.0 }, { 0.8, 18.45 }, { -0.8, 18.45 } }
local BACK_PANEL_Z = { 1.3, 1.55 }
-- dark pointed tail plate between the thighs (full-body BACK sheet), wide enough to close the gap
local BACK_TAIL: { Pt } = { { -1.35, 18.6 }, { 1.35, 18.6 }, { 1.3, 17.4 }, { 0.8, 16.2 }, { 0, 15.3 }, { -0.8, 16.2 }, { -1.3, 17.4 } }
local BACK_TAIL_Z = { 0.2, 1.2 }

-- hip armour: big shoulder-like plate over the thigh top, disc on its face
-- outer edge pulled in to ~5.3 (full-body FRONT sheet), split at h 21.5:
-- the deep lower plate and the shallower upper tip
local HIP_PLATE: { Pt } = { { 2.1, 20.5 }, { 2.0, 20.3 }, { 2.6, 18.7 }, { 3.36, 18.0 }, { 4.65, 18.3 }, { 5.62, 20.5 } }
local HIP_PLATE_MID: { Pt } = { { 2.62, 21.5 }, { 2.1, 20.5 }, { 5.62, 20.5 }, { 5.75, 20.8 }, { 5.55, 21.5 } }
local HIP_PLATE_TIP: { Pt } = { { 3.6, 23.4 }, { 2.62, 21.5 }, { 5.55, 21.5 }, { 5.25, 22.1 } }
local HIP_PLATE_Z = { -4.75, 2.2 } -- lowest part (side view -4.8 .. +2.2 at h 18.5 .. 20.5)
local HIP_PLATE_MID_Z = { -4.3, 2.1 } -- h 20.5 .. 21.5 (side view -4.2) -- lower part (full-body side view: -4.8 .. +2.2 at h 18.5 .. 21)
local HIP_PLATE_UPPER_Z = { -3.5, 1.3 } -- upper tip above h 21.5 is shallower (side view -3.2 at h 22 .. 24)
local HIP_PLATE_BEVEL: { Pt } = { { 3.85, 22.95 }, { 2.35, 20.15 } } -- line parallel to the top-inner edge
local HIP_DISC: Pt = { 3.75, 19.0 }
local HIP_DISC_R = 0.55

-- thigh core (front and back views share the outline)
-- outer edge pulled in ~0.5, inner edge ~0.3 (full-body FRONT sheet: thigh 1.3 .. 5.4)
local THIGH: { Pt } = { { 1.1, 19.6 }, { 5.2, 19.6 }, { 5.35, 14.9 }, { 5.05, 14.0 }, { 4.7, 13.9 }, { 4.55, 13.1 }, { 4.3, 12.5 }, { 2.6, 12.1 }, { 1.5, 12.6 }, { 1.2, 13.4 } }
local THIGH_Z = { -3.9, 0.4 }
-- panel lines drawn on the thigh's front / back faces (polylines)
local THIGH_FRONT_LINES: { { Pt } } = {
	{ { 5.0, 18.4 }, { 5.45, 14.4 } }, -- outer bevel
	{ { 1.72, 16.6 }, { 3.1, 16.1 }, { 4.1, 15.1 }, { 4.2, 14.4 } }, -- diagonal panel seam
}
local THIGH_BACK_LINES: { { Pt } } = {
	{ { 4.95, 18.6 }, { 4.95, 14.3 } },
	{ { 4.05, 18.5 }, { 4.05, 13.0 } },
	{ { 1.9, 13.6 }, { 4.9, 13.4 } },
}
-- outer side plate of the thigh (side profile { z, h }, BootBuilder style),
-- standing a little proud of the thigh's outer face
local THIGH_SIDE: { Pt } = { { -3.6, 19.3 }, { 0.15, 19.3 }, { 0.15, 13.7 }, { -1.0, 12.9 }, { -3.5, 13.6 } }
local THIGH_SIDE_X = { 5.05, 5.45 } -- ox range
local THIGH_SIDE_LINES: { { Pt } } = { { { -3.6, 16.2 }, { -1.6, 16.2 }, { 0.15, 17.2 } } }
-- knee cap: raised trapezoid at the bottom front of the thigh
local KNEE_CAP: { Pt } = { { 2.86, 14.45 }, { 3.7, 14.45 }, { 4.6, 12.4 }, { 2.5, 12.15 } }
local KNEE_CAP_Z = { -3.7, -3.1 }

-- dark knee housing between thigh and shin, with slats on its back
local KNEE_HOUSING = { halfW = 1.2, bottom = 10.4, top = 13.1, zFront = -2.9, zBack = 0.2 }
local KNEE_SLATS = { count = 5, d = 0.32, bottom = 10.7, top = 12.9, z = 0.22 }

-- ===== Helpers ============================================================

type Ctx = { u: number, color: { [string]: Color3 } }

-- Frame whose (local Z, local Y) plane is the front view of side s (+1 =
-- right leg at +X): poly { ox, h } -> world x = s * ox, extruded along Z.
-- A prism from z0 to z1 uses xc = -s * (z0 + z1) / 2 in this frame.
local function frontFrame(s: number): CFrame
	return CFrame.fromMatrix(Vector3.zero, -s * Vector3.zAxis, Vector3.yAxis)
end

local function slab(ctx: Ctx, parent: Instance, name: string, s: number, poly: { Pt }, z: { number }, color: Color3?, lines: boolean?)
	local xf = frontFrame(s)
	local z0, z1 = z[1], z[2]
	G.prism(ctx, parent, name, xf, poly, -s * (z0 + z1) / 2, z1 - z0, color or ctx.color.main)
	if lines ~= false then
		G.outline(ctx, parent, name .. "Line", xf, poly, -s * z0, s) -- front face
		G.outline(ctx, parent, name .. "Line", xf, poly, -s * z1, -s) -- back face
	end
end

-- Open polyline drawn as dark strips on a face at depth z (cells), facing
-- `facing` (-1 = front / -Z, +1 = back / +Z).
local function lines(ctx: Ctx, parent: Instance, name: string, s: number, polyline: { Pt }, z: number, facing: number)
	local xf = frontFrame(s)
	for i = 1, #polyline - 1 do
		G.outline(ctx, parent, name, xf, { polyline[i], polyline[i + 1] }, -s * z, -s * facing)
	end
end

local function box(ctx: Ctx, parent: Instance, name: string, cx: number, b: { [string]: number }, color: Color3): BasePart
	local u = ctx.u
	local p = G.newPart("Part", name, color, parent)
	p.Size = Vector3.new(b.halfW * 2, b.top - b.bottom, b.zBack - b.zFront) * u
	p.CFrame = CFrame.new(cx * u, (b.top + b.bottom) / 2 * u, (b.zFront + b.zBack) / 2 * u)
	return p
end

-- ===== Build ==============================================================

export type BuildOptions = {
	colors: { [string]: Color3 }?,
}

-- Hips + thighs + both boots, standing on y = 0 around the origin, facing -Z.
-- WorldPivot = the Pelvis bone (hip height).
function LegBuilder.build(scale: number?, opts: BuildOptions?): Model
	local sc = scale or BootBuilder.DefaultScale
	local u = BootBuilder.CELL * sc
	local o = opts or {}
	local colors = table.clone(BootBuilder.Colors)
	if o.colors then
		for k, v in o.colors do
			colors[k] = v
		end
	end
	local ctx: Ctx = { u = u, color = colors }

	local model = Instance.new("Model")
	model.Name = "MechLegs"
	model:SetAttribute("Scale", sc)

	local pelvis = G.bone("Pelvis", CFrame.new(0, HIP[2] * u, PELVIS_Z * u), u, model)
	model.PrimaryPart = pelvis
	local pelvisArmor = Instance.new("Folder")
	pelvisArmor.Name = "PelvisArmor"
	pelvisArmor.Parent = model

	-- --- pelvis ---
	box(ctx, pelvisArmor, "Waist", 0, WAIST, colors.joint)
	box(ctx, pelvisArmor, "PelvisCore", 0, PELVIS_CORE, colors.joint)
	box(ctx, pelvisArmor, "Belt", 0, BELT, colors.joint)
	-- hip bone: a dark joint housing from the belt out to each hip plate
	for _, s in { 1, -1 } do
		local cf = CFrame.new(s * (HIP[1] - 0.7) * u, (HIP[2] + 0.6) * u, HIP_Z * u)
		G.cylinder(ctx, pelvisArmor, "HipBone", cf, 2.6, 2.3, colors.joint)
	end
	slab(ctx, pelvisArmor, "CrotchUpper", 1, CROTCH_UPPER, CROTCH_UPPER_Z)
	do
		local zf, zb = CROTCH_Z[1], CROTCH_Z[2]
		for _, s in { 1, -1 } do
			local half: { Pt } = {}
			for _, p in CROTCH_HALF do
				table.insert(half, { s * p[1], p[2] })
			end
			-- sweep this half back about the vertical centre line on the front face
			local hinge = CFrame.new(0, 0, zf * u)
			local xf = hinge * CFrame.Angles(0, -s * CROTCH_ANGLE, 0) * hinge:Inverse() * frontFrame(1)
			G.prism(ctx, pelvisArmor, "CrotchPlate", xf, half, -(zf + zb) / 2, zb - zf, colors.main)
			G.outline(ctx, pelvisArmor, "CrotchPlateLine", xf, half, -zf, 1)
		end
	end
	slab(ctx, pelvisArmor, "BackPlate", 1, BACK_PLATE, BACK_PLATE_Z)
	slab(ctx, pelvisArmor, "BackPanel", 1, BACK_PANEL, BACK_PANEL_Z)
	slab(ctx, pelvisArmor, "BackTail", 1, BACK_TAIL, BACK_TAIL_Z, colors.recess)

	-- --- legs ---
	for _, side in { "R", "L" } do
		local s = if side == "R" then 1 else -1
		local n = if side == "R" then "Right" else "Left"

		local boot = BootBuilder.build(sc, side, { thighStub = false, colors = o.colors })
		boot:PivotTo(CFrame.new(s * STANCE / 2 * u, 0, 0) * boot:GetPivot())
		boot.Parent = model
		local shin = boot:FindFirstChild("Shin") :: BasePart
		local kneeX = shin.Position.X / u * s -- ox of the knee joint

		local thigh = G.bone(n .. "Thigh", CFrame.new(s * HIP[1] * u, HIP[2] * u, HIP_Z * u), u, model)
		local armor = Instance.new("Folder")
		armor.Name = n .. "ThighArmor"
		armor.Parent = model

		slab(ctx, armor, "Thigh", s, THIGH, THIGH_Z)
		for _, pl in THIGH_FRONT_LINES do
			lines(ctx, armor, "ThighLine", s, pl, THIGH_Z[1], -1)
		end
		for _, pl in THIGH_BACK_LINES do
			lines(ctx, armor, "ThighLine", s, pl, THIGH_Z[2], 1)
		end
		do
			-- side-profile frame: BootBuilder's (local X = world X), mirrored per side
			local x0, x1 = THIGH_SIDE_X[1], THIGH_SIDE_X[2]
			G.plate(ctx, armor, "ThighSide", CFrame.identity, THIGH_SIDE, s * (x0 + x1) / 2, x1 - x0)
			for _, pl in THIGH_SIDE_LINES do
				for i = 1, #pl - 1 do
					G.outline(ctx, armor, "ThighSideLine", CFrame.identity, { pl[i], pl[i + 1] }, s * x1, s)
				end
			end
		end
		slab(ctx, armor, "KneeCap", s, KNEE_CAP, KNEE_CAP_Z)
		slab(ctx, armor, "KneeCapFace", s, G.offset(KNEE_CAP, -0.2), { KNEE_CAP_Z[1] - 0.06, KNEE_CAP_Z[1] + 0.1 })
		slab(ctx, armor, "HipPlate", s, HIP_PLATE, HIP_PLATE_Z)
		slab(ctx, armor, "HipPlateMid", s, HIP_PLATE_MID, HIP_PLATE_MID_Z)
		slab(ctx, armor, "HipPlateTip", s, HIP_PLATE_TIP, HIP_PLATE_UPPER_Z)
		lines(ctx, armor, "HipPlateLine", s, HIP_PLATE_BEVEL, HIP_PLATE_Z[1], -1)
		lines(ctx, armor, "HipPlateLine", s, HIP_PLATE_BEVEL, HIP_PLATE_Z[2], 1)
		-- hip disc on the plate's front face (cylinder axis along Z)
		local discCF = CFrame.new(s * HIP_DISC[1] * u, HIP_DISC[2] * u, (HIP_PLATE_Z[1] - 0.08) * u) * CFrame.Angles(0, math.pi / 2, 0)
		G.cylinder(ctx, armor, "HipDisc", discCF, 0.2, HIP_DISC_R * 2, colors.main)
		G.cylinder(ctx, armor, "HipDiscLine", discCF * CFrame.new(0.06 * u, 0, 0), 0.04, HIP_DISC_R * 2 + 0.2, colors.line)

		-- knee housing (dark) and slats on its back
		box(ctx, armor, "KneeHousing", s * kneeX, KNEE_HOUSING, colors.joint)
		local sl = KNEE_SLATS
		for i = 1, sl.count do
			local ox = kneeX - KNEE_HOUSING.halfW + 0.35 + (i - 1) * (KNEE_HOUSING.halfW * 2 - 0.7) / (sl.count - 1)
			local a = Vector3.new(s * ox * u, sl.bottom * u, sl.z * u)
			local b = Vector3.new(s * ox * u, sl.top * u, sl.z * u)
			G.rod(ctx, armor, "KneeSlat", a, b, sl.d, colors.jointFace)
		end

		G.weldAll(armor, thigh)
		local hip = Instance.new("Motor6D")
		hip.Name = n .. "Hip"
		hip.Part0 = pelvis
		hip.Part1 = thigh
		hip.C0 = pelvis.CFrame:ToObjectSpace(thigh.CFrame)
		hip.Parent = pelvis
		local knee = Instance.new("Motor6D")
		knee.Name = n .. "Knee"
		knee.Part0 = thigh
		knee.Part1 = shin
		knee.C0 = thigh.CFrame:ToObjectSpace(shin.CFrame)
		knee.Parent = thigh
	end

	G.weldAll(pelvisArmor, pelvis)
	G.stripLines(model)
	model.WorldPivot = pelvis.CFrame
	return model
end

return LegBuilder
