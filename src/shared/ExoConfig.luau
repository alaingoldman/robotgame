--!strict
-- Tuning for the EXO-1 exoskeleton worn on the player's back (see
-- ExoBuilder for the design note, ExoService for equip / unequip and
-- ExoAnimator for the idle pulse, pistons and the hoisted frame's walk).

local ExoConfig = {}

-- Debug / test hooks. AutoEquip gives every player the exo on spawn.
-- AllowToggle lets clients fire the "ExoToggle" remote (ExoRemotes folder);
-- DebugKey cycles off -> auto fit -> forced walking frame -> off.
ExoConfig.AutoEquip = true
ExoConfig.AllowToggle = true
ExoConfig.DebugKey = Enum.KeyCode.X

-- Augment while worn (restored on removal). JumpMultiplier scales JumpPower
-- or JumpHeight, whichever the Humanoid uses.
ExoConfig.WalkSpeedMultiplier = 1.4
ExoConfig.JumpMultiplier = 1.3

-- Fitting. A rig whose head centre is lower than MinHeadFraction x the
-- standard R15 head height (feet to head centre, ~4.5 studs) is too small to
-- wear the exo and rides the walking frame instead.
ExoConfig.StandardHeadHeight = 4.5
ExoConfig.MinHeadFraction = 0.6
ExoConfig.LeftArm = true -- lighter mirrored left arm (struts only)
ExoConfig.LeftKneeCap = true -- knee cap + hinge on the left knee too
-- Extra clearance (studs, x body scale) round the body when the avatar wears
-- layered clothing (a jacket / pants WrapLayer), so the exo sits on top of it.
ExoConfig.LayeredClothingPad = 0.12

-- Colours (gunmetal / black frame, steel rods, green lights).
ExoConfig.Colors = {
	frame = Color3.fromRGB(62, 65, 70), -- gunmetal struts
	dark = Color3.fromRGB(26, 27, 30), -- black plates and housings
	steel = Color3.fromRGB(150, 155, 160), -- piston rods, pins
	cable = Color3.fromRGB(18, 18, 20),
	glow = Color3.fromRGB(70, 255, 120), -- green lights, bright
	glowDim = Color3.fromRGB(18, 95, 45), -- green lights at the bottom of a pulse
}

-- Idle pulse of the green lights (seconds per breath).
ExoConfig.PulsePeriod = 2.4

-- Hoisted walking frame (avatars that can't wear the exo). Studs, frame
-- space: ground at y = 0 between the feet, facing -Z.
ExoConfig.Frame = {
	AnkleY = 0.42,
	KneeY = 1.6,
	HipY = 2.78,
	HipX = 0.5,
	PelvisY = 2.95,
	ShoulderY = 4.45,
	ShoulderX = 1.02,
	NeckY = 4.7,
	UpperArm = 1.15,
	Forearm = 1.05,
	-- gait
	HipSwing = 0.55, -- radians at full stride
	KneeBend = 0.9,
	ArmSwing = 0.35,
	Stride = 4.6, -- studs per two-step cycle
	MaxCadence = 2.3, -- cycles per second (fast runs slide a little)
	Bob = 0.08,
}

return ExoConfig
