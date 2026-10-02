--!strict
-- Continuous crosshatch for the BRZ-01 Titan. MechPattern lays the pattern
-- as one Texture per part face; the Titan's curved / faceted armour is made
-- of hundreds of thin wedge facets, and each Texture starts at its own face
-- corner, so the lattice came out chopped into dashes that don't line up
-- from facet to facet. This runs right after MechPattern.apply (its
-- postApply hook, registered below) and re-phases every Texture:
--
--   * one tile size / image for the whole mech (MechPattern's large tile),
--     same Transparency as every other mech
--   * faces are grouped per bone (parts welded to the same bone move
--     together) and linked to their neighbours: touching, near-coplanar
--     (normals within ~37 deg) faces
--   * a flood fill from the biggest face of each patch sets each neighbour's
--     OffsetStudsU / V so its lattice continues exactly where the previous
--     facet's left off (matched at the facets' shared edge; axis swaps / flips
--     between facets are mapped onto the parent's axes)
--
-- Texture mapping per face (measured in Studio): texcoord(p) = (p - O) . U
-- + Offset, with U the viewer's right and O the face's top-left corner seen
-- from outside; "up" is +Y for the four side faces, +Z on Top, +X on Bottom.

local MechPattern = require(script.Parent.MechPattern)

local TitanPattern = {}

local TEX_NAME = "PatternTex"
local NORMAL_DOT = 0.8
local PLANE_GAP = 0.35 -- studs between neighbouring facet planes
-- Textures can't rotate: a patch only grows across joins where the next
-- facet's lattice is turned less than JOIN_MIS against it, so every patch is
-- continuous inside; tiny patches that couldn't join anything (a few
-- randomly turned facets) lose the pattern instead of showing a broken bit.
local JOIN_MIS = math.rad(14)
local MIN_PATCH = 6
local MIN_AREA = 6 -- studs^2
local SPLIT_FACTOR = 1.6 -- see the patchwork test at the end of align
-- Densely triangulated curved surfaces (the chest dome, helmet shell, toe
-- caps, finger segments...): facets far smaller than a pattern tile, each
-- turned its own way, so the lattice would break on every facet. A surface
-- (one part name on one bone) of at least DENSE_COUNT wedge facets averaging
-- under DENSE_AREA studs^2 gets no pattern at all.
local DENSE_COUNT = 20
local DENSE_AREA = 0.6

-- Face frames in part-local axes: normal, U (texture right), up (-V).
local FACE: { [Enum.NormalId]: { n: Vector3, u: Vector3, up: Vector3 } } = {
	[Enum.NormalId.Front] = { n = -Vector3.zAxis, u = -Vector3.xAxis, up = Vector3.yAxis },
	[Enum.NormalId.Back] = { n = Vector3.zAxis, u = Vector3.xAxis, up = Vector3.yAxis },
	[Enum.NormalId.Right] = { n = Vector3.xAxis, u = -Vector3.zAxis, up = Vector3.yAxis },
	[Enum.NormalId.Left] = { n = -Vector3.xAxis, u = Vector3.zAxis, up = Vector3.yAxis },
	[Enum.NormalId.Top] = { n = Vector3.yAxis, u = -Vector3.xAxis, up = Vector3.zAxis },
	[Enum.NormalId.Bottom] = { n = -Vector3.yAxis, u = -Vector3.zAxis, up = Vector3.xAxis },
}

type Face = {
	tex: Texture,
	n: Vector3, -- bone space
	u: Vector3,
	v: Vector3,
	o: Vector3, -- texture origin corner
	c: Vector3, -- face center
	r: number, -- half diagonal
	area: number,
	-- solved: texcoord(p) = (p . U) * su + ... expressed as offsets
	done: boolean,
	name: string, -- part name without its trailing digits
	patch: number, -- flood-fill patch id
	mis: number, -- in-plane turn (radians) against the facet it was matched to
}

local function abs(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- The face of `part` a Texture sits on, in `bone`'s space.
local function faceOf(tex: Texture, part: BasePart, bone: BasePart): Face?
	local f = FACE[tex.Face]
	if not f then
		return nil
	end
	local rel = bone.CFrame:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local hn = abs(f.n):Dot(half)
	local hu = abs(f.u):Dot(half)
	local hv = abs(f.up):Dot(half)
	local nL, uL, upL = f.n, f.u, f.up
	local centerL = nL * hn
	local originL = centerL - uL * hu + upL * hv -- top-left
	local R = rel.Rotation
	return {
		tex = tex,
		n = (R * nL) :: Vector3,
		u = (R * uL) :: Vector3,
		v = -((R * upL) :: Vector3),
		o = rel:PointToWorldSpace(originL),
		c = rel:PointToWorldSpace(centerL),
		r = math.sqrt(hu * hu + hv * hv),
		area = 4 * hu * hv,
		done = false,
		name = (string.gsub(part.Name, "%d+$", "")),
		mis = 0,
		patch = 0,
	}
end

local function wrap(x: number, tile: number): number
	return x - math.floor(x / tile) * tile
end

-- Texture coordinates of point p on face f with its current offsets.
local function coords(f: Face, p: Vector3): (number, number)
	local d = p - f.o
	return d:Dot(f.u) + f.tex.OffsetStudsU, d:Dot(f.v) + f.tex.OffsetStudsV
end

-- Sets f's offsets so that its coords at p equal (cu, cv).
local function pin(f: Face, p: Vector3, cu: number, cv: number, tile: number)
	local d = p - f.o
	f.tex.OffsetStudsU = wrap(cu - d:Dot(f.u), tile)
	f.tex.OffsetStudsV = wrap(cv - d:Dot(f.v), tile)
end

-- Whether b touches a (near-coplanar neighbour), and b's in-plane lattice
-- turn against a (radians, mod 90 deg).
local function joinOf(a: Face, b: Face): number?
	if a.n:Dot(b.n) < NORMAL_DOT then
		return nil
	end
	local dc = b.c - a.c
	if dc.Magnitude > (a.r + b.r) * 1.02 or math.abs(dc:Dot(a.n)) > PLANE_GAP then
		return nil
	end
	local bu = b.u - a.n * b.u:Dot(a.n)
	local m = bu.Magnitude
	local align = if m > 1e-4 then math.max(math.abs(bu:Dot(a.u)), math.abs(bu:Dot(a.v))) / m else 1
	return math.acos(math.clamp(align, -1, 1))
end

local function boneOf(part: BasePart): BasePart
	for _, w in part:GetChildren() do
		if w:IsA("Weld") and w.Part1 == part and w.Part0 then
			return w.Part0
		end
	end
	return part
end

-- Re-phases every pattern Texture on the model (no-op without a pattern).
function TitanPattern.align(model: Model)
	local pattern = model:GetAttribute("Pattern")
	local def = if typeof(pattern) == "string" then MechPattern.Patterns[pattern] else nil
	if not def then
		return
	end
	local tile = def.largeTile
	-- faces grouped per bone
	local groups: { [BasePart]: { Face } } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Texture") and d.Name == TEX_NAME then
			local part = d.Parent
			-- curved surfaces (shoulder pads, chest bulge, helmet, toe caps) are
			-- tagged PatternPlain by their builders: the owner wants them plain
			if part and part:GetAttribute("PatternPlain") then
				d:Destroy()
				continue
			end
			if part and part:IsA("BasePart") then
				d.Texture = def.largeImage
				d.StudsPerTileU = tile
				d.StudsPerTileV = tile
				local bone = boneOf(part)
				local f = faceOf(d, part, bone)
				if f then
					local g = groups[bone]
					if not g then
						g = {}
						groups[bone] = g
					end
					table.insert(g, f)
				end
			end
		end
	end
	for _, faces in groups do
		-- biggest faces seed the fill
		table.sort(faces, function(a, b)
			return a.area > b.area
		end)
		local n = #faces
		local wedgeCount: { [string]: number } = {}
		local wedgeArea: { [string]: number } = {}
		for _, f in faces do
			if (f.tex.Parent :: Instance):IsA("WedgePart") then
				wedgeCount[f.name] = (wedgeCount[f.name] or 0) + 1
				wedgeArea[f.name] = (wedgeArea[f.name] or 0) + f.area
			end
		end
		for _, f in faces do
			local c = wedgeCount[f.name]
			if c and c >= DENSE_COUNT and wedgeArea[f.name] / c < DENSE_AREA then
				f.done = true
				f.tex:Destroy()
			end
		end
		for i = 1, n do
			local seed = faces[i]
			if seed.done then
				continue
			end
			seed.done = true
			seed.patch = i
			-- seed: lattice anchored at the bone origin projection
			pin(seed, seed.c, seed.c:Dot(seed.u), seed.c:Dot(seed.v), tile)
			local queue = { seed }
			local head = 1
			local links, bad = 0, 0
			while head <= #queue do
				local a = queue[head]
				head += 1
				for j = 1, n do
					local b = faces[j]
					if b.done then
						continue
					end
					local mis = joinOf(a, b)
					if not mis then
						continue
					end
					-- only grow the patch across joins where b's lattice isn't turned
					-- against a's (Textures can't rotate); b may seed its own patch
					links += 1
					if mis > JOIN_MIS then
						bad += 1
						continue
					end
					-- shared edge ~ midway; map b's axes onto a's (swaps / flips)
					local q = (a.c + b.c) / 2
					local au, av = coords(a, q)
					local du, dv = b.u:Dot(a.u), b.u:Dot(a.v)
					local cu, cv
					if math.abs(du) >= math.abs(dv) then
						-- U along U: V along V
						cu = if du >= 0 then au else -au
						cv = if b.v:Dot(a.v) >= 0 then av else -av
					else
						-- U along V: V along U
						cu = if dv >= 0 then av else -av
						cv = if b.v:Dot(a.u) >= 0 then au else -au
					end
					pin(b, q, cu, cv, tile)
					b.mis = mis
					b.patch = i
					b.done = true
					table.insert(queue, b)
				end
			end
			-- a lone facet (or a few) whose lattice can't continue into any
			-- neighbour: plain is better than a stray broken bit of pattern
			local area = 0
			for _, f in queue do
				area += f.area
			end
			if #queue < MIN_PATCH and area < MIN_AREA and links > 0 then
				for _, f in queue do
					f.tex:Destroy()
				end
			end
		end
		-- A surface (one part name on this bone) that the turn rule split into
		-- many more patches than it has geometric pieces (facets linked by
		-- touching / near-coplanar alone) is a mesh of randomly turned
		-- triangles: no pattern rather than a patchwork.
		local parent: { [Face]: Face } = {}
		local function find(f: Face): Face
			local r = f
			while parent[r] and parent[r] ~= r do
				r = parent[r]
			end
			parent[f] = r
			return r
		end
		for i = 1, n do
			local a = faces[i]
			if a.patch == 0 then
				continue
			end
			for j = i + 1, n do
				local b = faces[j]
				if b.patch ~= 0 and b.name == a.name and joinOf(a, b) then
					local ra, rb = find(a), find(b)
					if ra ~= rb then
						parent[ra] = rb
					end
				end
			end
		end
		local pieces: { [string]: { [Face]: boolean } } = {}
		local patches: { [string]: { [number]: boolean } } = {}
		local sizes: { [string]: number } = {}
		for _, f in faces do
			if f.patch ~= 0 then
				pieces[f.name] = pieces[f.name] or {}
				pieces[f.name][find(f)] = true
				patches[f.name] = patches[f.name] or {}
				patches[f.name][f.patch] = true
				sizes[f.name] = (sizes[f.name] or 0) + 1
			end
		end
		local function count(t: { [any]: boolean }): number
			local c = 0
			for _ in t do
				c += 1
			end
			return c
		end
		local patchwork: { [string]: boolean } = {}
		for name, set in pieces do
			local g, pc = count(set), count(patches[name])
			if sizes[name] >= MIN_PATCH and pc > g * SPLIT_FACTOR + 2 then
				patchwork[name] = true
			end
		end
		for _, f in faces do
			if f.patch ~= 0 and patchwork[f.name] and f.tex.Parent then
				f.tex:Destroy()
			end
		end
	end
end

-- Run after every MechPattern.apply on a Titan (spawn, armour swaps).

MechPattern.postApply.Titan = TitanPattern.align

return TitanPattern
