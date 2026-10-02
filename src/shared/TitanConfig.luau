--!strict
-- Tuning and data for the BRZ-01 "Titan" (type id "Titan"): the assembled
-- mech (MechAssembly) dressed in aged bronze / brass armour with teal gems.
-- See TitanBuilder (model, colours, cockpit, battery), TitanPose (kneel,
-- hatch, gait math), TitanDock (charging pylon) and the client TitanAnimator
-- / TitanPilot.
--
-- Colour variants reuse MechConfig's variant ids (so the inventory cards,
-- the EquipPiece remote and the per-slot "Helmet" / "Chest" / "Legs"
-- attributes work unchanged); each id maps to a Titan palette here:
--   Desert  -> Bronze     (default: aged bronze, polished brass, teal glow)
--   Navy    -> Gunmetal   (blued steel, amber glow)
--   Olive   -> Verdigris  (green copper patina, gold glow)
--   Crimson -> Obsidian   (black, red glow)
--   Arctic  -> Ivory      (ivory, gold trim, blue glow)

local TitanConfig = {}

TitanConfig.TypeId = "Titan"
TitanConfig.DisplayName = "BRZ-01"

-- Palette roles (TitanBuilder assigns one per part):
--   main   armour plates                          SmoothPlastic (crosshatched)
--   hi     raised / polished plates (brass)        SmoothPlastic (crosshatched)
--   dark   joints, frame (oxidised bronze)         Metal
--   recess deep recesses, bores                    Metal
--   trim   spikes, fins, bolts, rods (steel)       Metal
--   glow   gems: chest / knee / hip discs, knuckle rings, eye slit   Neon
export type Palette = {
	main: Color3,
	hi: Color3,
	dark: Color3,
	recess: Color3,
	trim: Color3,
	glow: Color3,
}

export type TitanVariant = { id: string, displayName: string, palette: Palette }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

TitanConfig.Variants = {
	Desert = {
		id = "Desert",
		displayName = "Bronze",
		palette = {
			main = rgb(138, 96, 46),
			hi = rgb(198, 156, 82),
			dark = rgb(82, 56, 34),
			recess = rgb(42, 30, 22),
			trim = rgb(196, 200, 206),
			glow = rgb(54, 236, 220),
		},
	},
	Navy = {
		id = "Navy",
		displayName = "Gunmetal",
		palette = {
			main = rgb(74, 80, 90),
			hi = rgb(122, 130, 140),
			dark = rgb(40, 43, 49),
			recess = rgb(22, 24, 28),
			trim = rgb(196, 200, 206),
			glow = rgb(255, 168, 36),
		},
	},
	Olive = {
		id = "Olive",
		displayName = "Verdigris",
		palette = {
			main = rgb(84, 148, 124),
			hi = rgb(146, 196, 166),
			dark = rgb(104, 68, 40),
			recess = rgb(38, 32, 24),
			trim = rgb(214, 182, 96),
			glow = rgb(255, 204, 64),
		},
	},
	Crimson = {
		id = "Crimson",
		displayName = "Obsidian",
		palette = {
			main = rgb(36, 34, 40),
			hi = rgb(66, 62, 72),
			dark = rgb(22, 20, 23),
			recess = rgb(12, 11, 13),
			trim = rgb(150, 152, 160),
			glow = rgb(255, 40, 28),
		},
	},
	Arctic = {
		id = "Arctic",
		displayName = "Ivory",
		palette = {
			main = rgb(230, 222, 200),
			hi = rgb(214, 174, 86),
			dark = rgb(118, 102, 80),
			recess = rgb(58, 50, 42),
			trim = rgb(222, 184, 88),
			glow = rgb(64, 150, 255),
		},
	},
} :: { [string]: TitanVariant }

TitanConfig.DefaultVariant = "Desert"

function TitanConfig.getVariant(id: string?): TitanVariant
	return TitanConfig.Variants[id or ""] or TitanConfig.Variants[TitanConfig.DefaultVariant]
end

-- Parked lineup (MechService): a block behind the WTK-99 one (x 110 .. 182,
-- z -150), facing the spawn. One BRZ-01 is ~2,900 parts, so only a few are
-- parked; every colour can be swapped in from the inventory while piloting.
TitanConfig.Lineup = {
	{ key = "BRZ01_Desert_Hatch", variantId = "Desert", x = 110, z = -150, pattern = "Crosshatch" },
	{ key = "BRZ01_Olive_Hatch", variantId = "Olive", x = 146, z = -150, pattern = "Crosshatch" },
	{ key = "BRZ01_Crimson_Hatch", variantId = "Crimson", x = 182, z = -150, pattern = "Crosshatch" },
}

-- Root collision box (studs). Its center sits RootHeight above the ground
-- (about the pelvis); its bottom is the Humanoid's HipHeight.
TitanConfig.RootHeight = 15.5
TitanConfig.RootSize = Vector3.new(7, 4, 6)
TitanConfig.CameraOffset = Vector3.new(0, 8, 0)

-- Get-in / get-out timings (seconds from PowerTime). The placeholder flow
-- (MechTypes cinematicBoarding = false): E seats the pilot in the chest
-- cockpit at once; the chest hatch shuts, the mech rises from its kneel and
-- hands over. TitanPilot runs a camera move over it.
TitanConfig.Board = {
	HatchCloseStart = 0.35,
	HatchCloseEnd = 0.95,
	PowerUp = 0.85,
	StandStart = 1.05,
	StandEnd = 2.25,
	Online = 2.35, -- controls handed over
}
TitanConfig.Exit = {
	KneelEnd = 1.3,
	HatchOpenStart = 1.15,
	HatchOpenEnd = 1.75,
	Unseat = 1.8, -- server unseats; the pilot's client puts the avatar down in front
	Off = 2.05,
}

-- Gait (TitanAnimator). Walk / sprint speeds are the shared MechConfig ones
-- (22 / 46, like the HWM-04B, VK-01 and GR-07), so PilotController needs no
-- per-type case. Feet are planted by IK: Cycle = studs travelled per full
-- two-step cycle, Duty = fraction of the cycle a foot is on the ground.
TitanConfig.Gait = {
	WalkCycle = 17,
	SprintCycle = 31,
	WalkDuty = 0.62,
	SprintDuty = 0.4,
	WalkLift = 2.2,
	SprintLift = 3.6,
	WalkCrouch = 1.5, -- hips drop while walking (studs) so the legs reach
	SprintCrouch = 2.4,
	WalkBob = 0.45,
	SprintBob = 0.9,
	SprintLean = 0.24, -- torso pitches forward at a run (radians)
	ArmSwing = 0.32,
	SprintArmSwing = 0.75,
}

-- Charging pylon at the back of the pad (TitanDock / MechBattery): a teal
-- arc jumps from its coil to the battery on the mech's back while parked.
TitanConfig.Dock = {
	Offset = Vector3.new(0, 0, 12.5), -- pylon base from the home spot (mech space: +Z = behind)
	Reach = 26, -- battery terminal to coil distance where the arc breaks
	PlugRange = 10, -- root within this of home to re-connect
	ReplugAt = 1.3, -- seconds into PoweringDown (the kneel is done)
	ChargeRate = 14, -- percent per second
}

return TitanConfig
