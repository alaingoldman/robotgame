--!strict
-- Tuning and data for the CRM-01 "Crimson" (type id "Crimson"): the chunky
-- red brawler built from the owner's textured Meshy mech (asset
-- 101342583030033, 17 MeshParts with one baked texture, see
-- assets/meshes/crimson) holding the cleaver (asset 123971673295763). See
-- CrimsonMeshes (templates), CrimsonBuilder (rig, blades, back hatch
-- cockpit, battery), CrimsonPose (kneel, hatch, leg IK), CrimsonDock
-- (charging post) and the client CrimsonAnimator / CrimsonPilot.
--
-- Model space = the source data's frame (assets/meshes/crimson/meta.json):
-- feet on y = 0, front -Z, +X = the mech's right ("_R" parts), 1 unit = 1
-- stud, 20 studs tall.

local CrimsonConfig = {}

CrimsonConfig.TypeId = "Crimson"
CrimsonConfig.DisplayName = "CRM-01"

-- Palette roles for the parts built on top of the textured meshes (hatch,
-- cockpit, battery, dock). The meshes keep their baked texture.
export type Palette = {
	main: Color3, -- crimson armour (matched to the baked texture)
	dark: Color3, -- gun-metal joints
	trim: Color3, -- worn steel edges
	glow: Color3, -- cyan lights
}
export type Variant = { id: string, displayName: string, palette: Palette }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

CrimsonConfig.Variants = {
	Crimson = {
		id = "Crimson",
		displayName = "Crimson",
		palette = {
			main = rgb(172, 26, 46),
			dark = rgb(46, 46, 44),
			trim = rgb(120, 122, 118),
			glow = rgb(60, 255, 210),
		},
	},
} :: { [string]: Variant }

CrimsonConfig.DefaultVariant = "Crimson"

function CrimsonConfig.getVariant(id: string?): Variant
	return CrimsonConfig.Variants[id or ""] or CrimsonConfig.Variants[CrimsonConfig.DefaultVariant]
end

-- Parked lineup (MechService): the free spot left of the PLD-02s, mirroring
-- the third BRZ-01 on the right, facing the spawn.
CrimsonConfig.Lineup = {
	{ key = "CRM01_Crimson", variantId = "Crimson", x = -182, z = -150 },
}

-- Pivots (studs, model space; meta.json "pivots", right side; left = x negated
-- with the measured z).
CrimsonConfig.Pivots = {
	Neck = Vector3.new(0, 17.9, 0.542),
	Waist = Vector3.new(0, 13.9, -0.101),
	Shoulder = { Right = Vector3.new(4.45, 16.8, 0.351), Left = Vector3.new(-4.45, 16.8, 0.345) },
	Pad = { Right = Vector3.new(2.0, 18.1, 0.617), Left = Vector3.new(-2.0, 18.1, 0.625) },
	Elbow = { Right = Vector3.new(6.066, 13.85, 0.367), Left = Vector3.new(-6.027, 13.85, 0.34) },
	Wrist = { Right = Vector3.new(6.903, 9.95, 0.048), Left = Vector3.new(-6.886, 9.95, 0.059) },
	Hip = { Right = Vector3.new(2.334, 12.2, 0.07), Left = Vector3.new(-2.314, 12.2, 0.111) },
	-- the knee hinge is at the FRONT of the knee (meta.json has the centre,
	-- z 0.1): bent, the front stays closed and the flat cut caps turn into the
	-- leg instead of facing out (the back of the knee folds inside the meshes)
	Knee = { Right = Vector3.new(2.581, 7.85, -1.5), Left = Vector3.new(-2.522, 7.85, -1.5) },
	Ankle = { Right = Vector3.new(3.601, 1.95, 0.308), Left = Vector3.new(-3.621, 1.95, 0.307) },
}

-- The hip-joint line sits HipLine above the soles; the root collision box is
-- centred on it.
CrimsonConfig.HipLine = 12.2
CrimsonConfig.RootHeight = 12.2
CrimsonConfig.RootSize = Vector3.new(6, 3, 5)
CrimsonConfig.CameraOffset = Vector3.new(0, 12, 0)

-- The cleaver in the right fist (meta.json blade: grip at the GLB origin,
-- blade along +Y, spine +X, edge -X). Held forward and down with the edge
-- underneath, like the concept.
CrimsonConfig.Blade = {
	Grip = Vector3.new(6.56, 8.616, -0.229), -- fist centre (model space)
	Pitch = -0.42, -- below horizontal (radians)
	Yaw = 0.06, -- tip a little outward
	-- the second blade, arm-mounted on the outside of the left forearm, tip down
	ArmMount = true,
	ArmOffset = Vector3.new(-2.1, -0.4, 0.15), -- from the left elbow pivot (model space)
	ArmTilt = 0.04, -- tip out from the forearm (radians)
}

-- Back hatch cockpit: an armoured plate over the back of the torso, hinged
-- along its top edge, swings up and back while parked; behind it a lit pod.
CrimsonConfig.Hatch = {
	Hinge = Vector3.new(0, 16.9, 4.55), -- model space (under the pod's roof bevel, at its back face)
	Open = -2.0, -- radians about X (negative: the lower edge swings back and up)
}
CrimsonConfig.PilotScale = 0.5 -- the stand-in pilot seated in the pod

-- Parked kneel (CrimsonPose.kneel, the BRZ-01 / PLD-02 one-knee kneel at
-- this size): right knee on the floor with the shin lying back, toes tucked
-- under (the big foot stands on its toe behind, clear of the shin); left
-- foot planted forward with the shin about vertical; torso nearly upright,
-- leaning a little forward; both arms hang relaxed, the cleaver turned
-- to a reverse grip standing up along the right forearm, the arm blade's
-- tip resting on the floor by the left foot.
CrimsonConfig.Kneel = {
	KneeClear = 1.0, -- right knee hinge (near the front of the knee) above the ground: the knee front on the floor
	ThighLean = 0.05, -- right thigh tipped forward (radians)
	PelvisBack = 0.4,
	LeftForward = 4.6, -- left ankle ahead of its hip (studs): the shin about vertical
	LeftOut = 0.2,
	LeftYaw = 0.08,
	RightYaw = -0.04,
	RightFootLift = 2.5, -- ankle raised so the toe-down foot stands on its toe
	RightFootPitch = -1.1, -- toe tucked down under the ankle
	StepLift = 1.6,
	Lean = 0.12, -- torso pitch forward
	Neck = -0.2,
	LeftShoulder = 0.45,
	LeftRoll = 0.06, -- out, clear of the raised left thigh
	LeftElbow = 0.35,
	LeftWrist = 0.05,
	RightShoulder = 0.3,
	RightRoll = 0.04,
	RightElbow = 0.4,
	RightWrist = 0,
	CleaverOut = 1.75, -- reverse grip: the blade beside the forearm's outer face (studs)
	CleaverTurn = 1.99, -- forward-down -> straight up (pi/2 + the held pitch)
}

-- Get-in / get-out (seconds from PowerTime). Placeholder flow (MechTypes
-- cinematicBoarding = false): E puts the pilot in the back pod (a stand-in
-- climbs up into it), the hatch slams, the eyes / cyan lights flare, the mech
-- rises from its kneel and hands over. CrimsonPilot flies the camera over it.
CrimsonConfig.Board = {
	ClimbEnd = 0.75, -- the stand-in pilot has climbed into the pod
	HatchCloseStart = 0.75,
	HatchCloseEnd = 1.2,
	PowerUp = 1.3, -- eyes and cyan lights flare once it's sealed
	StandStart = 1.55,
	StandEnd = 2.75,
	Online = 2.85,
}
CrimsonConfig.Exit = {
	KneelEnd = 1.4,
	HatchOpenStart = 1.2,
	HatchOpenEnd = 1.75,
	Unseat = 1.85,
	Off = 2.2,
}

-- Gait (CrimsonAnimator): a heavy brawler. Speeds are the shared MechConfig
-- ones (22 / 46). Cycle = studs per full two-step cycle, Duty = stance share.
CrimsonConfig.Gait = {
	WalkCycle = 15,
	SprintCycle = 27,
	WalkDuty = 0.64,
	SprintDuty = 0.42,
	WalkLift = 1.7,
	SprintLift = 2.6,
	WalkCrouch = 1.0,
	SprintCrouch = 1.7,
	WalkBob = 0.55,
	SprintBob = 0.85,
	SprintLean = 0.2,
	ArmSwing = 0.22, -- kept moderate: torso slivers show under a raised arm
	SprintArmSwing = 0.38,
	PadFollow = 0.4, -- share of the shoulder swing the shoulder pad takes
}
CrimsonConfig.JumpWindup = 0.24

-- Charging post at the back of the pad (CrimsonDock / MechBattery): a cyan
-- arc jumps from its emitter to the battery terminal while parked.
CrimsonConfig.Dock = {
	Offset = Vector3.new(4, 0, 10.5), -- post base from the home spot (mech space: +Z = behind, +X = right; the pilot boards behind-left)
	EmitterHeight = 15,
	Reach = 22,
	PlugRange = 8,
	ReplugAt = 1.4,
	ChargeRate = 14, -- percent per second
}

return CrimsonConfig
