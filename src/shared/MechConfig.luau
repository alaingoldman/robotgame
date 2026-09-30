--!strict
-- Shared tuning and data for the HWM-04B mech.

local MechConfig = {}

-- Armor slots. Each slot owns a set of body segments.
MechConfig.Slots = { "Helmet", "Chest", "Legs" }

MechConfig.SlotSegments = {
	Helmet = { "Head" },
	Chest = { "Torso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" },
	Legs = { "Waist", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

export type Palette = {
	main: Color3,
	panel: Color3,
	dark: Color3,
	accent: Color3,
	light: Color3,
}

export type Variant = {
	id: string,
	displayName: string,
	palette: Palette,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Five color variants. Geometry is identical; only the palette changes.
MechConfig.Variants = {
	{
		id = "Olive",
		displayName = "Olive Drab",
		palette = { main = rgb(98, 106, 62), panel = rgb(78, 85, 48), dark = rgb(44, 46, 50), accent = rgb(236, 205, 40), light = rgb(225, 40, 40) },
	},
	{
		id = "Desert",
		displayName = "Desert Tan",
		palette = { main = rgb(196, 166, 116), panel = rgb(166, 138, 94), dark = rgb(64, 56, 48), accent = rgb(240, 120, 30), light = rgb(225, 40, 40) },
	},
	{
		id = "Arctic",
		displayName = "Arctic",
		palette = { main = rgb(214, 219, 224), panel = rgb(176, 184, 192), dark = rgb(56, 62, 72), accent = rgb(50, 160, 235), light = rgb(60, 220, 255) },
	},
	{
		id = "Navy",
		displayName = "Navy",
		palette = { main = rgb(44, 58, 98), panel = rgb(32, 43, 76), dark = rgb(28, 30, 36), accent = rgb(240, 240, 240), light = rgb(225, 40, 40) },
	},
	{
		id = "Crimson",
		displayName = "Crimson",
		palette = { main = rgb(150, 36, 36), panel = rgb(118, 26, 28), dark = rgb(34, 31, 31), accent = rgb(235, 185, 50), light = rgb(255, 210, 60) },
	},
} :: { Variant }

function MechConfig.getVariant(id: string): Variant
	for _, v in MechConfig.Variants do
		if v.id == id then
			return v
		end
	end
	return MechConfig.Variants[1]
end

-- Global size of the mech. Every builder coordinate (bones, armor, root) is
-- multiplied by this, and so is everything measured in studs below. 1.7 is
-- the smallest size whose cockpit fits a full-size avatar with the hatch shut.
MechConfig.Scale = 1.7

-- Movement
MechConfig.WalkSpeed = 22
MechConfig.SprintSpeed = 46

-- Gait. Hip swing amplitudes (radians) are shared with MechAnimator so the
-- stride length always matches the leg motion and the feet don't slide.
MechConfig.LegLength = 7.7 * MechConfig.Scale -- hip to ankle
MechConfig.WalkHipSwing = 0.55
MechConfig.SprintHipSwing = 0.72

-- Studs travelled per full two-step cycle: each foot sweeps 2 * L * sin(amp)
-- while planted, and a cycle has two plants. Knee flex shortens the leg a bit.
local function strideFor(amp: number): number
	local effectiveLeg = MechConfig.LegLength * 0.935
	return 4 * effectiveLeg * math.sin(amp)
end

MechConfig.StrideLength = strideFor(MechConfig.WalkHipSwing) -- ~25
MechConfig.SprintStrideLength = strideFor(MechConfig.SprintHipSwing) -- ~32

-- Sounds (free Creator Store audio)
MechConfig.Sounds = {
	Footstep = "rbxassetid://18959856391",
	Servo = "rbxassetid://9118934517",
	Clunk = "rbxassetid://9116673678", -- hatch slams shut / ramp lands
	Hiss = "rbxassetid://9116495722", -- hatch pneumatics
	PowerUp = "rbxassetid://9117882920",
	PowerDown = "rbxassetid://9117869243",
	Hydraulic = "rbxassetid://9114854551", -- crouch
	StandUp = "rbxassetid://9114583506", -- giant servo powering up
	Stomp = "rbxassetid://9118240078", -- settles onto its feet
	Whoosh = "rbxassetid://132163823091536", -- jump takeoff
	LandImpact = "rbxassetid://9114036511", -- deep boom on landing
	LandMetal = "rbxassetid://9116673944", -- metal clunk on landing
	-- power cord + battery HUD
	CordSpark = "rbxassetid://9116279560", -- plug rips out: electric burst
	CordPop = "rbxassetid://9119669225", -- suction pop as the plug comes free
	CordSparkSmall = "rbxassetid://9116278051", -- plug end hits the floor
	CordThud = "rbxassetid://9118717475", -- heavy cable smacks the floor
	CordClick = "rbxassetid://9113808115", -- breaker click as it re-plugs
	ChargeHum = "rbxassetid://9117959201", -- buzzy charging swell
	UiPop = "rbxassetid://9119668978", -- HUD pops in / out
	UiTick = "rbxassetid://9120093264", -- a battery segment fills / empties
	LowBeep = "rbxassetid://9113936601", -- low battery warning
	-- pilot climbing a raised ramp
	ClimbGrab = "rbxassetid://9125681862", -- hands smack onto the metal lip
	ClimbLand = "rbxassetid://9125679183", -- boots land on the pad after hopping off
}

-- Jumping. JumpPower is the takeoff speed (studs/s): apex = v^2 / (2g),
-- ~9.8 studs at default gravity. While falling the owning client adds
-- FallGravity x extra gravity so the drop is quick and the landing heavy.
MechConfig.JumpPower = 62
MechConfig.JumpFallGravity = 1.3
MechConfig.JumpWindup = 0.08 -- quick squat before the legs fire (pilot only)
MechConfig.JumpCooldown = 0.4 -- after landing before the next jump

-- Power states, replicated as the mech's "PowerState" attribute. "PowerTime"
-- holds the server time the state began so every client plays it in sync.
--   Off -> Boarding -> Online -> PoweringDown -> Off
-- Getting in takes about 2.5 seconds, getting out about 3. The pilot's
-- avatar stays their Character the whole time: it sits in the cockpit seat
-- while the mech (a separate Humanoid, network-owned by the pilot) is driven.
--
-- Boarding starts with the pilot walking up the ramp. The walk takes a
-- variable time (the "BoardWalk" attribute, BoardWalkMin..BoardWalkMax
-- seconds); the times below are measured from the end of that walk.
MechConfig.Boarding = {
	TurnTime = 0.3, -- pilot turns to face out
	Sit = 0.3, -- server seats the pilot (and straps it in: massless, no collisions)
	RampCloseStart = 0.3, -- ramp retracts up into the cockpit in front of the seated pilot
	RampCloseEnd = 0.6,
	DoorCloseStart = 0.5, -- chest doors swing shut
	DoorCloseEnd = 0.9,
	Sealed = 0.95, -- pilot enclosed: the camera starts following the mech
	PowerUp = 0.95, -- lights come on
	StandStart = 1.0,
	StandEnd = 1.6,
	Online = 1.7, -- controls handed over (~2.5 s after pressing E)
}
MechConfig.BoardWalkMin = 0.5
MechConfig.BoardWalkMax = 0.9
MechConfig.BoardWalkSpeed = 34 -- walk speed cap while boarding; longer routes glide

-- Exit times. CrouchEnd / Reveal count from the start of PoweringDown; the
-- rest count from Reveal, when the doors start to open on the seated pilot.
MechConfig.Exit = {
	CrouchEnd = 0.7, -- kneels with the doors still shut
	Reveal = 0.85, -- doors start to open (the times below count from here)
	DoorOpen = 0.45, -- doors swing open, revealing the seated pilot
	RampOpenStart = 0.2, -- ramp extends back out once the doors are clear
	RampOpenEnd = 0.65,
	Stand = 0.85, -- pilot unbuckles and walks down the ramp
	Off = 2.15, -- controls returned (~3 s after pressing E)
}
MechConfig.ExitWalkSpeed = 28

-- Mechs whose off pose is "OneKnee" (see MechBuilder.OffStyles) hold their
-- ramp up off the ground, so the pilot climbs it. Their "BoardWalk" (see
-- above) is the approach walk plus Climb plus RampWalk: walk to the spot
-- under the lip, pull up onto the ramp, walk up it into the cockpit. On the
-- way out (from Exit.Stand) the pilot walks down to the lip, hops off and
-- lands. Every client animates the climb and the hop from these times.
MechConfig.Climb = {
	ApproachMin = 0.35, -- walk to the foot of the ramp (seconds, by distance)
	ApproachMax = 0.8,
	Climb = 1.1, -- reach, grab, hang, pull up, leg over, stand
	RampWalk = 0.6, -- up the ramp to the spot in front of the seat
	RampDown = 0.55, -- exit: out of the cockpit and down to the lip
	Hop = 0.38, -- off the lip to the ground
	Land = 0.3, -- landing squash
}

-- Power cord (see MechCord / MechBattery). At its pad the mech is plugged
-- into a floor outlet behind the pad and charges, also while boarded and
-- standing. The cord stays in while the socket is within reach of the outlet
-- (cord length minus Slack); walking further pulls it taut and it snaps out.
-- It re-plugs once the mech has knelt again after an exit (ReplugAt, seconds
-- into PoweringDown) if the mech is within PlugRange studs of its home spot;
-- otherwise the cord stays on the floor and the battery doesn't charge.
MechConfig.Cord = {
	Slack = 2.5, -- studs short of full length where the plug rips out
	ReplugAt = 0.85, -- the kneel is done
	PlugRange = 10, -- root within this of its home spot (the pad is 28 wide)
	-- outlet box behind the pad center and off to one side (studs); well clear
	-- of the mech parked 46 studs behind
	OutletDistance = 17,
	OutletSide = 5,
	HangLength = 11, -- extra cord for the drop from the socket and room to stand up
	Diameter = 1.0,
	SegmentLength = 1.2,
}

-- Battery, server-authoritative "Charge" attribute (0..100) on each mech.
-- Rates are percent per second. A full battery lasts ~2.8 min of sprinting,
-- ~6.7 min of walking. At 0 the mech limps: no sprint, no jump, half speed.
MechConfig.Battery = {
	ChargeRate = 15, -- plugged in (no drain while plugged, even online)
	IdleDrain = 0.08, -- online, standing still
	WalkDrain = 0.25,
	SprintDrain = 0.6,
	JumpCost = 2.5, -- per jump
	EmptySpeedFactor = 0.5, -- walk speed multiplier at 0 %
	Low = 20, -- red + beeping below this
}

-- Camera zoom limits while piloting; boarding hands over at FinalZoom.
MechConfig.PilotZoomMin = 14 * MechConfig.Scale
MechConfig.PilotZoomMax = 90 * MechConfig.Scale
MechConfig.BoardFinalZoom = 48
MechConfig.ExitZoom = 17 -- reveal shot distance, kept when following the pilot out

return MechConfig
