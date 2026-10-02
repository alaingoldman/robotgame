--!strict
-- Pose math for the WTK-99 (Type99Builder), shared by clients and the server.
--
--   * fold(k): the powered-down sit as joint transforms, blended by k (0
--     standing .. 1 folded): the hips drop and sit back (Root), the
--     three-segment zig-zag legs fold by IK (legIK) so the feet stay exactly
--     planted, and the hull tips nose-down (HullTilt) so the open cockpit is low.
--   * setCanopy(motors, k): canopy 0 shut .. 1 open (CanopyHinge).
--   * powerTargets(model): fold / canopy / light levels for the mech's
--     PowerState + PowerTime (MechConfig.Type99Boarding / Type99Exit).
--   * applyStatic / applyOff: the server mirror and the edit-mode preview.
--
-- Leg angles here are bone pitches in the level pelvis frame: 0 = segment
-- straight down, positive = lower end forward (-Z). A motor's Transform is
-- the bone's pitch minus what its rest pose and parents already give it.

local MechConfig = require(script.Parent.MechConfig)
local Type99Builder = require(script.Parent.Type99Builder)

local Type99Pose = {}

local LEGS = Type99Builder.Legs
local T, X = MechConfig.Type99Boarding, MechConfig.Type99Exit
local LEN, REST, FOLD = LEGS.lengths, LEGS.rest, LEGS.fold
-- the leg's shape is one scalar s: joint bends go from standing (0) to sat
-- down (1) and past (s < 0 stretches the zig-zag out, s > 1 folds it tighter)
local B1R, B2R = REST[2] - REST[1], REST[3] - REST[2]
local B1F, B2F = FOLD[2] - FOLD[1], FOLD[3] - FOLD[2]
local S_MIN, S_MAX = -1, 1.1

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function pitchOf(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

local function seg(len: number, pitch: number): Vector3
	return Vector3.new(0, -math.cos(pitch), -math.sin(pitch)) * len
end

-- Joint bends for shape s and the hip -> ankle vector with the upper thigh straight down.
local function shape(s: number): (number, number, Vector3)
	local b1 = B1R + (B1F - B1R) * s
	local b2 = B2R + (B2F - B2R) * s
	return b1, b2, seg(LEN[1], 0) + seg(LEN[2], b1) + seg(LEN[3], b1 + b2)
end

local _, _, reachMin = shape(S_MIN)
local _, _, reachMax = shape(S_MAX)
local D_MAX, D_MIN = reachMin.Magnitude, reachMax.Magnitude
Type99Pose.Reach = D_MAX -- longest hip -> ankle distance (studs)
Type99Pose.MinReach = D_MIN

-- Three-segment zig-zag leg IK: hip -> ankle vector (pelvis frame, studs;
-- only Y and Z are used) -> upper thigh, middle segment and lower leg bone
-- pitches. Solves the leg's shape for the distance (bisection; reach falls
-- steadily as s grows), then swings the whole leg to point at the ankle.
function Type99Pose.legIK(v: Vector3): (number, number, number)
	local d = math.sqrt(v.Y * v.Y + v.Z * v.Z)
	local s
	if d >= D_MAX then
		s = S_MIN
	elseif d <= D_MIN then
		s = S_MAX
	else
		local lo, hi = S_MIN, S_MAX
		for _ = 1, 18 do
			local mid = (lo + hi) / 2
			local _, _, f = shape(mid)
			if f.Magnitude > d then
				lo = mid
			else
				hi = mid
			end
		end
		s = (lo + hi) / 2
	end
	local b1, b2, f = shape(s)
	local p1 = pitchOf(Vector3.new(0, v.Y, v.Z)) - pitchOf(f)
	return p1, p1 + b1, p1 + b1 + b2
end

-- Leg motor transforms (Hip, MidJoint, Knee, Ankle) for bone pitches.
function Type99Pose.legTransforms(p1: number, p2: number, p3: number, foot: number): (CFrame, CFrame, CFrame, CFrame)
	return CFrame.Angles(p1 - REST[1], 0, 0),
		CFrame.Angles((p2 - p1) - (REST[2] - REST[1]), 0, 0),
		CFrame.Angles((p3 - p2) - (REST[3] - REST[2]), 0, 0),
		CFrame.Angles((foot - p3) - (LEGS.footRest - REST[3]), 0, 0)
end

-- The hull tips a beat after the legs start folding (and levels a beat
-- after them when standing up).
function Type99Pose.hullFold(k: number): number
	return math.clamp(k, 0, 1) ^ 0.7
end

-- The railgun tilts up against the hull's nose-down tilt as it folds.
function Type99Pose.railFold(k: number): CFrame
	return CFrame.Angles(Type99Builder.OffRailPitch * Type99Pose.hullFold(k), 0, 0)
end

-- Joint transforms of the powered-down sit, blended by k (0 standing .. 1 folded).
function Type99Pose.fold(k: number): { [string]: CFrame }
	k = math.clamp(k, 0, 1)
	local drop = Type99Builder.OffDrop * k
	local p1, p2, p3 = Type99Pose.legIK(LEGS.ankle - drop) -- feet stay where they stood
	local hip, mid, knee, ankle = Type99Pose.legTransforms(p1, p2, p3, 0)
	local out: { [string]: CFrame } = {
		Root = CFrame.new(drop),
		HullTilt = CFrame.Angles(Type99Builder.OffTilt * Type99Pose.hullFold(k), 0, 0),
		RailgunMount = Type99Pose.railFold(k),
	}
	for _, side in { "Left", "Right" } do
		out[side .. "Hip"] = hip
		out[side .. "MidJoint"] = mid
		out[side .. "Knee"] = knee
		out[side .. "Ankle"] = ankle
	end
	return out
end

-- Opens the canopy by k (0 shut .. 1 open).
function Type99Pose.setCanopy(motors: { [string]: Motor6D }, k: number)
	local hinge = motors.CanopyHinge
	if hinge then
		hinge.Transform = CFrame.Angles(Type99Builder.CanopyOpenAngle * math.clamp(k, 0, 1), 0, 0)
	end
end

local function stateTime(model: Model): number
	local t0 = model:GetAttribute("PowerTime")
	return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
end

-- Seconds of the boarding approach walk (the "BoardWalk" attribute).
function Type99Pose.boardWalk(model: Model): number
	local w = model:GetAttribute("BoardWalk")
	return if typeof(w) == "number" then w else T.ApproachMin
end

-- Targets for the mech's current power state: fold (0 standing .. 1 sat
-- down), canopy (0 shut .. 1 open) and light level. Timed states return
-- exact values (last result true); steady states are eased toward.
function Type99Pose.powerTargets(model: Model): (number, number, number, boolean)
	local state = model:GetAttribute("PowerState")
	local t = stateTime(model)
	if state == "Boarding" then
		t -= Type99Pose.boardWalk(model) -- times count from the end of the approach
		local fold = 1 - smooth((t - T.StandStart) / (T.StandEnd - T.StandStart))
		local canopy = 1 - smooth((t - T.CanopyCloseStart) / (T.CanopyCloseEnd - T.CanopyCloseStart))
		return fold, canopy, smooth((t - T.PowerUp) / 0.4), true
	elseif state == "PoweringDown" then
		local canopy = smooth((t - X.CanopyOpenStart) / (X.CanopyOpenEnd - X.CanopyOpenStart))
		return smooth(t / X.FoldEnd), canopy, 1 - smooth(t / 0.5), true
	elseif state == "Off" then
		return 1, 1, 0, false
	end
	return 0, 0, 1, false
end

-- Sets the fold and the canopy (no walk cycle).
function Type99Pose.applyStatic(motors: { [string]: Motor6D }, fold: number, canopy: number)
	for name, cf in Type99Pose.fold(fold) do
		local m = motors[name]
		if m then
			m.Transform = cf
		end
	end
	Type99Pose.setCanopy(motors, canopy)
end

-- The full powered-down pose: sat down, canopy open.
function Type99Pose.applyOff(motors: { [string]: Motor6D })
	Type99Pose.applyStatic(motors, 1, 1)
end

return Type99Pose
