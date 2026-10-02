--!strict
-- Tuning and data for the PLD-02 "Paladin" (type id "Mech2", the owner's
-- "mech2"): the white / gold / blue mech built from the imported meshes in
-- assets/meshes/mech2 (Mech2Meshes). See Mech2Builder (rig, colours,
-- cockpit, battery), Mech2Pose (kneel, chest hatch, leg IK), Mech2Dock
-- (charging post) and the client Mech2Animator / Mech2Pilot.
--
-- Colour variants reuse MechConfig's variant ids (inventory cards, the
-- EquipPiece remote and the per-slot attributes work unchanged); each id
-- maps to a palette here. Desert = the reference sheet colours.

local Mech2Config = {}

Mech2Config.TypeId = "Mech2"
Mech2Config.DisplayName = "PLD-02"

-- Palette roles (one per mesh, from the mesh colour names):
--   main    White armour                     SmoothPlastic (all flat, like the sheet)
--   hi      Gold trim / plates
--   accent  Blue under-suit / recesses
--   joint   Grey / Joint (balls, cores)
--   dark    DarkGrey (pads, wrist bands)
--   glow    cockpit / battery lights         Neon
export type Palette = {
	main: Color3,
	hi: Color3,
	accent: Color3,
	joint: Color3,
	dark: Color3,
	glow: Color3,
}
export type Variant = { id: string, displayName: string, palette: Palette }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Mech2Config.Variants = {
	-- the reference sheet (README colour tables)
	Desert = {
		id = "Desert",
		displayName = "Paladin",
		palette = {
			main = rgb(240, 240, 236),
			hi = rgb(212, 169, 58),
			accent = rgb(47, 111, 191),
			joint = rgb(134, 134, 136),
			dark = rgb(90, 90, 90),
			glow = rgb(90, 190, 255),
		},
	},
	Navy = {
		id = "Navy",
		displayName = "Nightfall",
		palette = {
			main = rgb(46, 54, 74),
			hi = rgb(212, 169, 58),
			accent = rgb(30, 160, 200),
			joint = rgb(96, 100, 110),
			dark = rgb(34, 36, 42),
			glow = rgb(80, 230, 255),
		},
	},
	Olive = {
		id = "Olive",
		displayName = "Verdant",
		palette = {
			main = rgb(226, 228, 216),
			hi = rgb(190, 160, 70),
			accent = rgb(70, 120, 70),
			joint = rgb(120, 124, 116),
			dark = rgb(70, 74, 66),
			glow = rgb(150, 255, 120),
		},
	},
	Crimson = {
		id = "Crimson",
		displayName = "Crusader",
		palette = {
			main = rgb(236, 234, 230),
			hi = rgb(200, 160, 60),
			accent = rgb(170, 34, 40),
			joint = rgb(120, 120, 124),
			dark = rgb(60, 56, 58),
			glow = rgb(255, 80, 60),
		},
	},
	Arctic = {
		id = "Arctic",
		displayName = "Glacier",
		palette = {
			main = rgb(248, 250, 255),
			hi = rgb(190, 200, 214),
			accent = rgb(120, 190, 240),
			joint = rgb(150, 156, 166),
			dark = rgb(84, 92, 104),
			glow = rgb(140, 220, 255),
		},
	},
} :: { [string]: Variant }

Mech2Config.DefaultVariant = "Desert"

function Mech2Config.getVariant(id: string?): Variant
	return Mech2Config.Variants[id or ""] or Mech2Config.Variants[Mech2Config.DefaultVariant]
end

-- Parked lineup (MechService): left of the GR-07 block, mirroring the
-- BRZ-01 one on the right, facing the spawn.
Mech2Config.Lineup = {
	{ key = "PLD02_Desert", variantId = "Desert", x = -110, z = -150 },
	{ key = "PLD02_Navy", variantId = "Navy", x = -146, z = -150 },
}

-- Model space: the ground point between the feet is the origin, facing -Z.
-- The hip-joint line sits HipLine above the soles (legs meta.json); the
-- root collision box is centred on it.
Mech2Config.HipLine = 8.4603
Mech2Config.RootHeight = 8.4603
Mech2Config.RootSize = Vector3.new(5, 3, 4)
Mech2Config.CameraOffset = Vector3.new(0, 10, 0)

-- Chest cockpit: the front chest plates are a hatch (hatch_* meshes) hinged
-- along their bottom edge (torso meta HatchHinge); it folds down and forward
-- while parked (Mech2Pose.setHatch). Behind it the core is hollow: a lit
-- cockpit with a seat; the seated pilot is shown as a scaled stand-in
-- (Mech2Animator), the real avatar is hidden.
Mech2Config.HatchHinge = Vector3.new(0, 6.4464, -1.8768) -- torso frame (studs)
Mech2Config.HatchOpen = -1.45 -- radians (the lower plate drops forward and down)
Mech2Config.PilotScale = 0.6 -- the stand-in pilot in the chest cockpit
-- IRON MAN opening: the chest doors (door_R / door_L meshes) swing out on
-- vertical hinges at their outer edges, the pauldrons lift and roll out.
-- Each part opens in its own window of the 0..1 opening, so they unfold one
-- after another (lower plate, doors, pauldrons) and fold back in reverse,
-- with a little overshoot as each one opens.
Mech2Config.DoorHinge = Vector3.new(2.3011, 7.9968, -1.428) -- torso frame, right door (left: x negated)
Mech2Config.DoorOpen = 1.95 -- radians about Y (right door: negative)
Mech2Config.Unfold = {
	Hatch = { 0.0, 0.45 },
	Doors = { 0.18, 0.72 },
	Pauldrons = { 0.4, 1.0 },
	PauldronRoll = 0.38, -- out
	PauldronLift = -0.22, -- tips back
	Overshoot = 1.2, -- back-out easing strength while opening
}

-- Parked kneel (Mech2Pose.kneel, the BRZ-01's one-knee pose at this size).
Mech2Config.Kneel = {
	KneeClear = 1.62, -- right knee joint above the ground: the shin plate just touches it (EditableMesh check)
	ThighLean = 0.12, -- right thigh tipped forward (radians)
	PelvisBack = 0.35,
	LeftForward = 3.0, -- left ankle ahead of its hip (studs)
	LeftOut = 0.3,
	LeftYaw = 0.28,
	RightYaw = -0.08,
	RightFootLift = 0.35, -- ankle up a little so the shin lies flatter (its front faces the floor)
	RightFootPitch = -0.12, -- toe down onto the floor
	StepLift = 1.3,
	Lean = 0.12, -- torso pitch forward
	Neck = -0.3,
	LeftShoulder = 0.2,
	LeftElbow = 0.95,
	RightShoulder = 0.25,
	RightElbow = 0.3,
}

-- Get-in / get-out (seconds from PowerTime). Placeholder flow (MechTypes
-- cinematicBoarding = false): E seats the pilot in the chest at once, the
-- hatch swings shut, the mech rises from its kneel and hands over.
-- Mech2Pilot flies the camera over it.
Mech2Config.Board = {
	HatchCloseStart = 0.4, -- the chest folds shut around the pilot (pauldrons, doors, lower plate)
	HatchCloseEnd = 1.15,
	PowerUp = 1.15, -- eyes light up once it's shut
	StandStart = 1.3,
	StandEnd = 2.4,
	Online = 2.5,
}
Mech2Config.Exit = {
	KneelEnd = 1.3,
	HatchOpenStart = 1.1, -- unfolds: lower plate, doors, pauldrons
	HatchOpenEnd = 1.9,
	Unseat = 1.95,
	Off = 2.2,
}

-- Gait (Mech2Animator). Speeds are the shared MechConfig ones (22 / 46).
-- Cycle = studs travelled per full two-step cycle, Duty = stance fraction.
Mech2Config.Gait = {
	WalkCycle = 12.5,
	SprintCycle = 24,
	WalkDuty = 0.62,
	SprintDuty = 0.4,
	WalkLift = 1.5,
	SprintLift = 2.2,
	WalkCrouch = 1.1, -- reach: stance +-3.9 studs with a 7.55 leg
	SprintCrouch = 1.8, -- reach: stance +-4.8 studs
	WalkBob = 0.4,
	SprintBob = 0.65,
	SprintLean = 0.22,
	ArmSwing = 0.3,
	SprintArmSwing = 0.55,
}
Mech2Config.JumpWindup = 0.2

-- Charging post at the back of the pad (Mech2Dock / MechBattery): a blue arc
-- jumps from its emitter to the battery on the mech's back while parked.
Mech2Config.Dock = {
	Offset = Vector3.new(0, 0, 9.5), -- post base from the home spot (mech space: +Z = behind)
	EmitterHeight = 13.5,
	Reach = 20, -- battery terminal to emitter distance where the arc breaks
	PlugRange = 8, -- root within this of home to re-connect
	ReplugAt = 1.3, -- seconds into PoweringDown (knelt)
	ChargeRate = 14, -- percent per second
}

return Mech2Config
