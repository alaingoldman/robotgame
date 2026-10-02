--!strict
-- Tuning and data for the SRF-03 "Seraph" (type id "Mech3"): the slim winged
-- navy mech built from the owner's turnaround sheet (Meshy mesh, asset
-- 110252059423481, 19 MeshParts with one baked texture, see
-- assets/meshes/mech3). See Mech3Meshes (templates), Mech3Builder (rig,
-- wings, helmet cockpit, battery), Mech3Pose (kneel, helmet lift, wings,
-- leg IK), Mech3Dock (charging post) and the client Mech3Animator /
-- Mech3Pilot.
--
-- Model space = the source data's frame (assets/meshes/mech3/meta.json):
-- feet on y = 0, front -Z, +X = the mech's right ("_R" parts), 1 unit = 1
-- stud, 20 studs tall.

local Mech3Config = {}

Mech3Config.TypeId = "Mech3"
Mech3Config.DisplayName = "SRF-03"

-- Palette roles for the parts built on top of the textured meshes (cockpit,
-- pistons, battery, eyes, dock). The meshes keep their baked texture.
export type Palette = {
	main: Color3, -- navy armour (matched to the baked texture)
	dark: Color3, -- charcoal joints / recesses
	trim: Color3, -- steel-blue panels
	glow: Color3, -- blue lights
}
export type Variant = { id: string, displayName: string, palette: Palette }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- One look; keyed by the shared MechConfig variant id the lineup uses.
Mech3Config.Variants = {
	Navy = {
		id = "Navy",
		displayName = "Seraph",
		palette = {
			main = rgb(56, 60, 76),
			dark = rgb(36, 38, 46),
			trim = rgb(122, 152, 178),
			glow = rgb(80, 185, 255),
		},
	},
} :: { [string]: Variant }

Mech3Config.DefaultVariant = "Navy"

function Mech3Config.getVariant(id: string?): Variant
	return Mech3Config.Variants[id or ""] or Mech3Config.Variants[Mech3Config.DefaultVariant]
end

-- Parked lineup (MechService): the next free spot left of the CRM-01
-- (x -182), same 36-stud spacing, facing the spawn.
Mech3Config.Lineup = {
	{ key = "SRF03_Seraph", variantId = "Navy", x = -218, z = -150 },
}

-- Imported mesh asset. v1 (110252059423481) = the first GLB (paper-look
-- texture). v2 = assets/meshes/mech3/Mech3_v2.glb: metal PBR texture
-- (SurfaceAppearance), pad flaps pulled onto the arms, wings 0.2 studs in
-- (meta_v2.json). Set AssetV2 to the owner's v2 import and the rig follows.
Mech3Config.AssetV1 = 110252059423481
Mech3Config.AssetV2 = nil :: number?
local WING_X = if Mech3Config.AssetV2 then 2.815 else 3.015

-- Pivots (studs, model space; assets/meshes/mech3/meta.json / meta_v2.json "pivots").
Mech3Config.Pivots = {
	Neck = Vector3.new(0, 17.45, -0.156),
	Waist = Vector3.new(0, 12.4, -0.058),
	Wing = { Right = Vector3.new(WING_X, 16.795, 1.021), Left = Vector3.new(-WING_X, 16.795, 1.021) },
	Shoulder = { Right = Vector3.new(2.612, 15.6, 0.094), Left = Vector3.new(-2.616, 15.6, 0.092) },
	Pad = { Right = Vector3.new(1.85, 16.9, 0.086), Left = Vector3.new(-1.85, 16.9, 0.089) },
	Elbow = { Right = Vector3.new(3.389, 13.85, 0.406), Left = Vector3.new(-3.384, 13.85, 0.406) },
	Wrist = { Right = Vector3.new(4.378, 10.85, -0.602), Left = Vector3.new(-4.396, 10.85, -0.588) },
	Hip = { Right = Vector3.new(1.294, 11.0, -0.008), Left = Vector3.new(-1.298, 11.0, -0.009) },
	Knee = { Right = Vector3.new(1.522, 7.2, -0.064), Left = Vector3.new(-1.521, 7.2, -0.116) },
	Ankle = { Right = Vector3.new(1.845, 1.55, 0.407), Left = Vector3.new(-1.847, 1.55, 0.405) },
}

-- The hip-joint line sits HipLine above the soles; the root collision box is
-- centred on it.
Mech3Config.HipLine = 11.0
Mech3Config.RootHeight = 11.0
Mech3Config.RootSize = Vector3.new(5, 3, 4)
Mech3Config.CameraOffset = Vector3.new(0, 12, 0)

-- Helmet cockpit: the pilot sits in the neck socket inside the collar ring
-- (the torso mesh is open there). Parked, the whole helmet flips up and back
-- on a hinge at the back of its base; it comes down over the pilot when
-- boarding.
Mech3Config.Helmet = {
	Hinge = Vector3.new(0, 17.45, 1.15), -- back of the helmet's base (model space)
	Lift = 0.3, -- studs up when open (clears the collar ring)
	Back = 0.1, -- studs back when open
	Tilt = 1.15, -- radians: the helmet flips up and back on its rear hinge, the face to the sky
	SeatY = 16.75, -- pilot seat pan height in the socket
	SeatZ = 0.22,
}
Mech3Config.PilotScale = 0.4 -- the stand-in pilot seated in the socket

-- Wings (WingRoot motors, rel in model axes, right wing; the left mirrors):
-- Flap = about Z (positive: tip up and out), Fold = about Y (positive: tip
-- swings back), Pitch = about X.
Mech3Config.Wings = {
	BreathFlap = 0.05, -- idle breathing amplitude
	BreathFold = 0.03,
	WalkFlap = 0.04, -- small counter-beat per step
	SprintFlap = 0.5, -- flared on sprint
	SprintFold = 0.42,
	JumpFlap = 0.6, -- spread on the way up
	KneelFlap = -0.12, -- parked: lowered and folded back
	KneelFold = 0.3,
}

-- Parked kneel (Mech3Pose.kneel): right knee on the floor with the shin
-- lying straight back (toes tucked under), left foot planted forward with
-- the shin vertical, torso a little forward, left forearm resting over the
-- raised left knee, right arm hanging, head bowed a little, wings folded.
Mech3Config.Kneel = {
	KneeClear = 1.15, -- right knee pivot above the ground (knee ball on the floor)
	ThighLean = 0.12, -- right thigh tipped forward (radians)
	PelvisBack = 0.6,
	LeftForward = 3.4, -- left ankle ahead of its hip (studs)
	LeftOut = 0.15,
	LeftYaw = 0.05,
	RightYaw = 0,
	RightFootLift = 1.5, -- ankle raised so the toe-down foot stands on its toe
	RightFootPitch = -0.9, -- toe tucked down under the ankle
	StepLift = 1.4,
	Lean = 0.3, -- torso pitch forward
	Neck = -0.15,
	LeftShoulder = 0.6,
	LeftRoll = -0.35, -- inward, over the raised thigh
	LeftElbow = 0.85,
	LeftWrist = -0.9, -- the hand hangs over the knee
	RightShoulder = 0.25,
	RightRoll = 0.06,
	RightElbow = 0.3,
	RightWrist = 0.1,
}

-- Get-in / get-out (seconds from PowerTime). Placeholder flow (MechTypes
-- cinematicBoarding = false): E puts the pilot in the neck socket (a
-- stand-in jumps up into it), the helmet comes down over it, the eyes flare,
-- the mech rises from its kneel and hands over. Mech3Pilot flies the camera.
Mech3Config.Board = {
	ClimbEnd = 0.8, -- the stand-in pilot has jumped into the socket
	HatchCloseStart = 0.8, -- the helmet starts down
	HatchCloseEnd = 1.3,
	PowerUp = 1.4, -- eyes and chest lights flare once it's sealed
	StandStart = 1.6,
	StandEnd = 2.8,
	Online = 2.9,
}
Mech3Config.Exit = {
	KneelEnd = 1.4,
	HatchOpenStart = 1.2,
	HatchOpenEnd = 1.8,
	Unseat = 1.9,
	Off = 2.25,
}

-- Gait (Mech3Animator): light and long-legged. Speeds are the shared
-- MechConfig ones (22 / 46). Cycle = studs per full two-step cycle, Duty =
-- stance share.
Mech3Config.Gait = {
	WalkCycle = 15,
	SprintCycle = 28,
	WalkDuty = 0.62,
	SprintDuty = 0.4,
	WalkLift = 1.5,
	SprintLift = 2.5,
	WalkCrouch = 0.8,
	SprintCrouch = 1.5,
	WalkBob = 0.4,
	SprintBob = 0.7,
	SprintLean = 0.24,
	ArmSwing = 0.3,
	SprintArmSwing = 0.5,
	PadFollow = 0.4, -- share of the shoulder swing the shoulder pad takes
}
Mech3Config.JumpWindup = 0.22

-- Charging post behind-right of the pad (Mech3Dock / MechBattery): a blue arc
-- jumps from its emitter to the terminal on top of the backpack while
-- parked.
Mech3Config.Dock = {
	Offset = Vector3.new(4.5, 0, 9.5), -- post base from the home spot (mech space: +Z = behind, +X = right)
	EmitterHeight = 15,
	Reach = 22,
	PlugRange = 8,
	ReplugAt = 1.4,
	ChargeRate = 14, -- percent per second
}

return Mech3Config
