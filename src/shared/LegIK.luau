--!strict
-- Planted-foot walk for two-legged rigs (hip / knee / ankle pitch joints).
-- Used by the client animators (MechAnimator, KnightAnimator,
-- GunnerAnimator) so feet stay put on the ground while the body moves over
-- them, instead of the legs swinging on a sine and the feet skating.
--
--   local rig = LegIK.new(motors)            -- once per mech (nil: no usable legs)
--   local s = LegIK.stride(rig, length, duty) -- walk drop / lift for a stance length
--   LegIK.gait(phase01, duty, length, lift)   -- one foot's offset along the cycle
--   LegIK.solve(rig, "Left", target, rootT)   -- sets Hip / Knee / Ankle Transforms
--
-- Space: targets are ankle-joint positions in HumanoidRootPart space (studs,
-- -Z forward). `rootT` is the Root motor's Transform for this frame (the
-- animator's bob / drop / sway), so the solve keeps the feet on their
-- targets however the body moves. The solve is numeric (damped Gauss-Newton
-- on hip and knee pitch, warm-started from the last frame) so it works with
-- each rig's own joint offsets, rest bends and splay rolls without
-- per-type math. The ankle then levels the foot (plus an extra pitch).

local LegIK = {}

export type Leg = {
	hip: Motor6D,
	knee: Motor6D,
	ankle: Motor6D,
	rest: Vector3, -- rest ankle position, root space
	restFoot: CFrame, -- rest foot frame (rotation only), root space
	hipA: number, -- last solution (warm start)
	kneeA: number,
	rollA: number, -- hip roll (sideways reach: body sway / roll over the planted foot)
	kneeMax: number, -- knee pitch at which the leg is straight (bends below it)
}
export type Rig = {
	root: Motor6D,
	legs: { [string]: Leg },
	reach: number, -- hip -> ankle length with the leg straight (shortest leg)
	height: number, -- hip -> ankle height at rest
}

local SIDES = { "Left", "Right" }

local function pitchOf(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

-- hip-parent frame in root space for a Root transform
local function parentFrame(rig: Rig, rootT: CFrame): CFrame
	local r = rig.root
	return r.C0 * rootT * r.C1:Inverse()
end

-- ankle joint frame relative to the hip parent for hip pitch / knee pitch / hip roll
local function ankleFrame(leg: Leg, a: number, b: number, c: number?): CFrame
	local hip, knee, ankle = leg.hip, leg.knee, leg.ankle
	return hip.C0 * CFrame.Angles(0, 0, c or 0) * CFrame.Angles(a, 0, 0) * hip.C1:Inverse() * knee.C0 * CFrame.Angles(b, 0, 0) * knee.C1:Inverse() * ankle.C0
end

function LegIK.new(motors: { [string]: Motor6D }): Rig?
	local root = motors.Root
	if not root then
		return nil
	end
	local legs: { [string]: Leg } = {}
	local reach, height = math.huge, 0
	for _, side in SIDES do
		local hip, knee, ankle = motors[side .. "Hip"], motors[side .. "Knee"], motors[side .. "Ankle"]
		if not (hip and knee and ankle) or hip.Part0 ~= root.Part1 then
			return nil
		end
		local leg: Leg = {
			hip = hip,
			knee = knee,
			ankle = ankle,
			rest = Vector3.zero,
			restFoot = CFrame.identity,
			hipA = 0,
			kneeA = 0,
			rollA = 0,
			kneeMax = 0,
		}
		local base = root.C0 * root.C1:Inverse()
		local restAnkle = base * ankleFrame(leg, 0, 0)
		leg.rest = restAnkle.Position
		leg.restFoot = (restAnkle * ankle.C1:Inverse()).Rotation
		-- straight knee: the shin lines up with the thigh (both in the thigh's frame)
		local thigh = (hip.C1:Inverse() * knee.C0).Position - hip.C1:Inverse().Position
		local shin = (knee.C0.Rotation * knee.C1:Inverse() * ankle.C0).Position
		leg.kneeMax = pitchOf(thigh) - pitchOf(shin) - 0.04
		reach = math.min(reach, thigh.Magnitude + shin.Magnitude)
		local hipPos = (base * hip.C0).Position
		height = math.max(height, hipPos.Y - leg.rest.Y)
		legs[side] = leg
	end
	return { root = root, legs = legs, reach = reach, height = height }
end

-- How far the body has to sink so a stance of `length` studs (front foot to
-- back foot) stays within reach (keeps a little bend in the knee).
function LegIK.dropFor(rig: Rig, length: number): number
	local r = rig.reach * 0.97
	local half = length / 2
	local h = math.sqrt(math.max(0, r * r - half * half))
	return math.max(0, rig.height - h)
end

-- One foot along the cycle. u = 0..1 (0 = heel strike, foot furthest
-- forward); the first `duty` of the cycle it is planted and slides back
-- (in root space) at exactly the body's speed, then it swings forward
-- through an arc. Returns forward offset (studs, + = ahead of rest), lift
-- (studs) and the foot's extra pitch (radians, + = toes up).
function LegIK.gait(u: number, duty: number, length: number, lift: number): (number, number, number)
	u %= 1
	if u < duty then
		local k = u / duty
		-- heel peels off the ground at the very end of the stance
		local peel = math.max(0, (k - 0.85) / 0.15)
		return length * (0.5 - k), 0, -0.25 * peel * peel
	end
	local w = (u - duty) / (1 - duty)
	-- Hermite from the back to the front, leaving and landing at the
	-- planted foot's speed (so there's no skid at lift-off or touchdown)
	local m = -length * (1 - duty) / duty
	local w2, w3 = w * w, w * w * w
	local f = (2 * w3 - 3 * w2 + 1) * (-length / 2) + (w3 - 2 * w2 + w) * m + (-2 * w3 + 3 * w2) * (length / 2) + (w3 - w2) * m
	-- lift peaks early (foot clears the ground fast), sets down gently
	local up = lift * math.sin(math.pi * math.min(1, w * 1.15)) ^ 0.8
	-- toes hang after lift-off, come level, tip up just before the strike
	local pitch = -0.35 * math.sin(math.pi * math.min(1, w / 0.6)) + 0.22 * math.sin(math.pi * math.clamp((w - 0.7) / 0.3, 0, 1))
	return f, up, pitch
end

-- Solves one leg so its ankle reaches `target` (root space) with the body
-- posed by `rootT`, and levels the foot plus `footPitch`. Sets the three
-- Transforms and returns the remaining error (studs).
function LegIK.solve(rig: Rig, side: string, target: Vector3, rootT: CFrame, footPitch: number?): number
	local leg = rig.legs[side]
	local parent = parentFrame(rig, rootT)
	local t = parent:PointToObjectSpace(target)
	local a, b, c = leg.hipA, leg.kneeA, leg.rollA
	if a ~= a or b ~= b or c ~= c then
		a, b, c = 0, 0, 0
	end
	local err = 0
	local H = 1e-3
	for _ = 1, 6 do
		local p = ankleFrame(leg, a, b, c).Position
		local e = t - p
		err = e.Magnitude
		if err < 0.005 then
			break
		end
		local ja = (ankleFrame(leg, a + H, b, c).Position - p) / H
		local jb = (ankleFrame(leg, a, b + H, c).Position - p) / H
		local jc = (ankleFrame(leg, a, b, c + H).Position - p) / H
		-- damped normal equations (3x3, Cramer); the roll is damped harder so
		-- the pitches do the reaching and the roll only takes the sideways part
		local l = 0.02
		local m11, m12, m13 = ja:Dot(ja) + l, ja:Dot(jb), ja:Dot(jc)
		local m22, m23, m33 = jb:Dot(jb) + l, jb:Dot(jc), jc:Dot(jc) + l * 4
		local g1, g2, g3 = ja:Dot(e), jb:Dot(e), jc:Dot(e)
		local det = m11 * (m22 * m33 - m23 * m23) - m12 * (m12 * m33 - m23 * m13) + m13 * (m12 * m23 - m22 * m13)
		if math.abs(det) < 1e-9 then
			break
		end
		local da = (g1 * (m22 * m33 - m23 * m23) - m12 * (g2 * m33 - m23 * g3) + m13 * (g2 * m23 - m22 * g3)) / det
		local db = (m11 * (g2 * m33 - m23 * g3) - g1 * (m12 * m33 - m23 * m13) + m13 * (m12 * g3 - g2 * m13)) / det
		local dc = (m11 * (m22 * g3 - g2 * m23) - m12 * (m12 * g3 - g2 * m13) + g1 * (m12 * m23 - m22 * m13)) / det
		a = math.clamp(a + math.clamp(da, -0.5, 0.5), -2.2, 2.2)
		b = math.clamp(b + math.clamp(db, -0.5, 0.5), -2.6, leg.kneeMax)
		c = math.clamp(c + math.clamp(dc, -0.2, 0.2), -0.35, 0.35)
	end
	leg.hipA, leg.kneeA, leg.rollA = a, b, c
	leg.hip.Transform = CFrame.Angles(0, 0, c) * CFrame.Angles(a, 0, 0)
	leg.knee.Transform = CFrame.Angles(b, 0, 0)
	-- level the foot: rotate it back to its rest orientation (root space)
	local foot = (parent * ankleFrame(leg, a, b, c)).Rotation
	local want = leg.restFoot * CFrame.Angles(footPitch or 0, 0, 0)
	local rel = foot:Inverse() * want * leg.ankle.C1.Rotation
	local x, _, z = rel:ToEulerAnglesXYZ()
	leg.ankle.Transform = CFrame.Angles(x, 0, z)
	return err
end

-- ============================================================ walk driver
-- Per-mech walk state for advance / place. `phase` is in radians and lines
-- up with the animators' sine conventions: sin(phase) = 1 at the left heel
-- strike (left foot furthest forward), -1 at the right one.
export type Walk = {
	phase: number,
	length: number, -- current stance length (studs)
	duty: number,
	lift: number,
	drop: number, -- body sink that keeps the stance within reach
	weight: number, -- 0..1 how much the gait owns the feet (eases to rest when stopping)
	lastU: number,
}
export type Params = {
	stance: number, -- walk stance length (studs, front foot to back foot)
	stanceSprint: number,
	duty: number, -- share of the cycle a foot is planted
	dutySprint: number,
	lift: number, -- swing foot clearance (studs)
	liftSprint: number,
}

function LegIK.newWalk(): Walk
	return { phase = 0, length = 0, duty = 0.6, lift = 0, drop = 0, weight = 0, lastU = 0 }
end

local TAU = math.pi * 2

-- Advances the cycle by the distance travelled. `amount` 0..1 = walking
-- (from speed), `sprint` 0..1 = the run blend. Returns "Left" / "Right" on
-- a heel strike this frame.
function LegIK.advance(rig: Rig, w: Walk, p: Params, dt: number, speed: number, amount: number, sprint: number): string?
	local full = p.stance + (p.stanceSprint - p.stance) * sprint
	-- shorter steps while getting going / slowing down
	w.length = full * (0.45 + 0.55 * math.clamp(amount, 0, 1))
	w.duty = p.duty + (p.dutySprint - p.duty) * sprint
	w.lift = p.lift + (p.liftSprint - p.lift) * sprint
	w.drop = LegIK.dropFor(rig, w.length)
	local moving = amount > 0.05 and speed > 0.5
	w.weight += ((if moving then 1 else 0) - w.weight) * math.min(1, dt * (if moving then 8 else 5))
	if moving then
		-- planted feet move back at exactly the body speed: one cycle per
		-- length / duty studs
		w.phase = (w.phase + dt * speed * w.duty / w.length * TAU) % TAU
	end
	local u = (w.phase / TAU - 0.25) % 1
	local strike: string? = nil
	if moving and w.weight > 0.3 then
		if w.lastU > 0.75 and u < 0.25 then
			strike = "Left"
		elseif w.lastU < 0.5 and u >= 0.5 then
			strike = "Right"
		end
	end
	w.lastU = u
	return strike
end

-- Places both feet for this frame: gait offsets (scaled by the walk weight),
-- plus `tuck` (0..1: legs drawn up in the air) and `spread` (studs each
-- foot steps out sideways, e.g. a wider idle stance).
function LegIK.place(rig: Rig, w: Walk, rootT: CFrame, tuck: number?, spread: number?)
	local u0 = (w.phase / TAU - 0.25) % 1
	local tk = tuck or 0
	for i, side in SIDES do
		local u = if i == 1 then u0 else (u0 + 0.5) % 1
		local f, up, pitch = LegIK.gait(u, w.duty, w.length, w.lift)
		local k = w.weight
		-- settling to rest: a foot still off its spot lifts a little on the way in
		local settle = 4 * k * (1 - k) * math.min(1, math.abs(f) / 3) * 0.8
		local out = (spread or 0) * (if side == "Left" then -1 else 1)
		local target = rig.legs[side].rest
			+ Vector3.new(out, up * k + settle + tk * rig.height * 0.28, -f * k - tk * rig.height * 0.08)
		LegIK.solve(rig, side, target, rootT, pitch * k - 0.3 * tk)
	end
end

-- Spring step (value, velocity) toward 0.
function LegIK.spring(x: number, v: number, w: number, z: number, dt: number): (number, number)
	v += (-w * w * x - 2 * z * w * v) * dt
	return x + v * dt, v
end

-- ============================================================ jump / landing
-- Airborne from the root's height over the ground (Humanoid states don't
-- replicate); a landing kicks a squat spring by the fall speed.
--   air:  0..1 airborne blend
--   comp: landing squat (studs the body sinks), springs back
export type Air = { airborne: boolean, air: number, comp: number, compV: number, fallV: number }

function LegIK.newAir(): Air
	return { airborne = false, air = 0, comp = 0, compV = 0, fallV = 0 }
end

local AIR_TOL = 1.5 -- studs of gap that still count as grounded
local COMP_W, COMP_Z = 11, 0.45
local LAND_COMP = 0.05 -- squat velocity factor per stud/s of impact
local airParams = RaycastParams.new()
airParams.FilterType = Enum.RaycastFilterType.Exclude
airParams.RespectCanCollide = true
airParams.CollisionGroup = "MechRoot" -- what the root stands on (MechBuilder.RootGroup): not players / pilots

-- Returns the impact speed on the frame it lands (else nil).
function LegIK.updateAir(air: Air, model: Model, root: BasePart, rootHeight: number, maxComp: number, dt: number): number?
	local sdt = math.min(dt, 1 / 30)
	local landed: number? = nil
	if root.Anchored then
		air.airborne = false
	else
		airParams.FilterDescendantsInstances = { model }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(rootHeight + 30), 0), airParams)
		local gap = if hit then root.Position.Y - hit.Position.Y - rootHeight else math.huge
		local vy = root.AssemblyLinearVelocity.Y
		local was = air.airborne
		if was then
			air.airborne = not (gap < AIR_TOL and vy <= 1)
		else
			air.airborne = gap > AIR_TOL * 2 or vy > 12
		end
		if was and not air.airborne then
			landed = math.max(0, -air.fallV)
			air.compV += math.min(landed :: number, 60) * LAND_COMP * COMP_W
		end
		air.fallV = vy
	end
	air.air += ((if air.airborne then 1 else 0) - air.air) * math.min(1, sdt * (if air.airborne then 10 else 20))
	air.comp, air.compV = LegIK.spring(air.comp, air.compV, COMP_W, COMP_Z, sdt)
	air.comp = math.clamp(air.comp, -0.5, maxComp)
	return landed
end

-- Rest ankle position of a leg (root space).
function LegIK.rest(rig: Rig, side: string): Vector3
	return rig.legs[side].rest
end

-- Forgets the warm start (after another pose owned the legs).
function LegIK.reset(rig: Rig)
	for _, leg in rig.legs do
		leg.hipA, leg.kneeA, leg.rollA = 0, 0, 0
	end
end

-- Reads the current hip / knee Transforms as the warm start, so a solve
-- right after a scripted pose (kneel, landing) starts where the legs are.
function LegIK.adopt(rig: Rig)
	for _, leg in rig.legs do
		local x, _, z = leg.hip.Transform:ToEulerAnglesYXZ()
		leg.hipA, leg.rollA = x, math.clamp(z, -0.35, 0.35)
		leg.kneeA = (leg.knee.Transform:ToEulerAnglesXYZ())
	end
end

return LegIK
