--!strict
-- Mech type registry. Every mech model carries a "MechType" attribute
-- ("HWM04B", "Type99", "Knight", "Gunner" or "Titan"; missing = "HWM04B"); shared code looks up the
-- builder, pose module and per-type behavior here instead of assuming the
-- HWM-04B.
--
--   local def = MechTypes.get(model)      -- or MechTypes.get("Type99")
--   def.Builder.buildMech(name, loadout) / def.Builder.applySlot(model, slot, variant)
--   def.Pose                              -- MechPose / Type99Pose (type-specific API)
--   def.rootHeight                        -- root center above the ground (studs)
--   def.applyPowerPose(model, motors)     -- server mirror of the power-state pose
--   def.applyOff(motors, style)           -- full powered-down pose (edit preview)
--
-- Adding a type: write its Builder (buildRig / buildMech / applySlot,
-- RootHeight, the same Armor_<Slot> folders and a model-level "PilotSeat")
-- and a Pose module, then register it below.

local MechBuilder = require(script.Parent.MechBuilder)
local MechPose = require(script.Parent.MechPose)
local Type99Builder = require(script.Parent.Type99Builder)
local Type99Pose = require(script.Parent.Type99Pose)
local KnightBuilder = require(script.Parent.KnightBuilder)
local KnightPose = require(script.Parent.KnightPose)
local GunnerBuilder = require(script.Parent.GunnerBuilder)
local GunnerPose = require(script.Parent.GunnerPose)
-- BRZ-01 Titan (assembled mech): TitanBuilder / TitanPose / TitanDock / TitanConfig
local TitanBuilder = require(script.Parent.TitanBuilder)
local TitanPose = require(script.Parent.TitanPose)
local TitanDock = require(script.Parent.TitanDock)
local TitanConfig = require(script.Parent.TitanConfig)

local MechTypes = {}

MechTypes.Attribute = "MechType"
MechTypes.Default = "HWM04B"

export type TypeDef = {
	id: string,
	displayName: string, -- model names and signs ("HWM-04B", "WTK-99")
	Builder: any,
	Pose: any,
	rootHeight: number,
	-- the rear power socket + floor outlet cord (MechCord / MechBattery / CordController)
	hasCord: boolean,
	-- MechAnimator animates it; otherwise its own client animator does (Type99Animator)
	hwmAnimator: boolean,
	-- world point (on the ground) where the pilot prompt sits in the powered-down pose
	-- (boarding: HWM-04B walk-in / Olive climb, WTK-99 nose climb; see MechService,
	-- Boarding and Climb)
	promptPoint: (rootCF: CFrame, style: string?) -> Vector3,
	applyPowerPose: (model: Model, motors: { [string]: Motor6D }) -> (),
	applyOff: (motors: { [string]: Motor6D }, style: string?) -> (),
	-- false = placeholder get-in (instant seat, see MechService placeholderEnter):
	-- the Pose module then has Board.Online / Exit.Unseat / Exit.Off timings and
	-- the Builder an offPoints(rootCF) with .exit / .forward (PlaceholderPilot)
	cinematicBoarding: boolean?,
	-- adjusts the pilot seat weld once the avatar sits (GR-07: stands it upright in the pod)
	fitPilot: ((model: Model, hum: Humanoid) -> ())?,
	-- own charger (BRZ-01 dock): builds it on the pad, keeps "Plugged" up to
	-- date (MechBattery) and charges at chargeRate %/s while plugged
	buildDock: ((home: CFrame, parent: Instance) -> ())?,
	updatePlug: ((model: Model, root: BasePart) -> ())?,
	chargeRate: number?,
	-- per-type name for a MechConfig variant id (signs, model names)
	variantName: ((variantId: string) -> string)?,
}

MechTypes.Types = {
	HWM04B = {
		id = "HWM04B",
		displayName = "HWM-04B",
		Builder = MechBuilder,
		Pose = MechPose,
		rootHeight = MechBuilder.RootHeight,
		hasCord = true,
		hwmAnimator = true,
		promptPoint = function(rootCF: CFrame, style: string?): Vector3
			return MechBuilder.offPoints(rootCF, style).foot
		end,
		applyPowerPose = function(model: Model, motors: { [string]: Motor6D })
			local crouch, doors, ramp = MechPose.powerTargets(model)
			MechPose.applyStatic(motors, crouch, doors, ramp, MechPose.style(model))
		end,
		applyOff = function(motors: { [string]: Motor6D }, style: string?)
			MechPose.applyOff(motors, style)
		end,
	},
	Type99 = {
		id = "Type99",
		displayName = Type99Builder.DisplayName,
		Builder = Type99Builder,
		Pose = Type99Pose,
		rootHeight = Type99Builder.RootHeight,
		hasCord = false, -- wall charger + cable instead (Type99Charger)
		hwmAnimator = false,
		promptPoint = function(rootCF: CFrame, _style: string?): Vector3
			return Type99Builder.offPoints(rootCF).prompt
		end,
		applyPowerPose = function(model: Model, motors: { [string]: Motor6D })
			local fold, canopy = Type99Pose.powerTargets(model)
			Type99Pose.applyStatic(motors, fold, canopy)
		end,
		applyOff = function(motors: { [string]: Motor6D }, _style: string?)
			Type99Pose.applyOff(motors)
		end,
	},
	-- VK-01 "Valkyrie" knight (KnightBuilder / KnightPose / KnightAnimator)
	Knight = {
		id = KnightBuilder.TypeId,
		displayName = KnightBuilder.DisplayName,
		Builder = KnightBuilder,
		Pose = KnightPose,
		rootHeight = KnightBuilder.RootHeight,
		hasCord = true, -- floor outlet + rear power socket, like the HWM-04B (MechCord)
		hwmAnimator = false, -- KnightAnimator (same bone names, own geometry)
		cinematicBoarding = false,
		promptPoint = function(rootCF: CFrame, _style: string?): Vector3
			return KnightBuilder.offPoints(rootCF).prompt
		end,
		applyPowerPose = function(model: Model, motors: { [string]: Motor6D })
			local kneel, hatch = KnightPose.powerTargets(model)
			KnightPose.applyStatic(motors, kneel, hatch)
		end,
		applyOff = function(motors: { [string]: Motor6D }, _style: string?)
			KnightPose.applyOff(motors)
		end,
	},
	-- GR-07 "Bulwark" gunner (GunnerBuilder / GunnerPose / GunnerAnimator)
	Gunner = {
		id = GunnerBuilder.TypeId,
		displayName = GunnerBuilder.DisplayName,
		Builder = GunnerBuilder,
		Pose = GunnerPose,
		rootHeight = GunnerBuilder.RootHeight,
		hasCord = true, -- floor outlet + rear power socket (MechCord), between the thrusters
		hwmAnimator = false, -- GunnerAnimator
		cinematicBoarding = false,
		fitPilot = GunnerBuilder.fitPilot,
		promptPoint = function(rootCF: CFrame, _style: string?): Vector3
			return GunnerBuilder.offPoints(rootCF).prompt
		end,
		applyPowerPose = function(model: Model, motors: { [string]: Motor6D })
			local off, petals = GunnerPose.powerTargets(model)
			GunnerPose.applyStatic(motors, off, petals)
		end,
		applyOff = function(motors: { [string]: Motor6D }, _style: string?)
			GunnerPose.applyOff(motors)
		end,
	},
	-- BRZ-01 "Titan" (MechAssembly + TitanBuilder / TitanPose / TitanAnimator)
	Titan = {
		id = TitanBuilder.TypeId,
		displayName = TitanBuilder.DisplayName,
		Builder = TitanBuilder,
		Pose = TitanPose,
		rootHeight = TitanBuilder.RootHeight,
		hasCord = false, -- charges from its dock pylon instead (TitanDock)
		hwmAnimator = false, -- TitanAnimator
		cinematicBoarding = false, -- placeholder seat-in + TitanPilot camera move
		promptPoint = function(rootCF: CFrame, _style: string?): Vector3
			return TitanBuilder.offPoints(rootCF).prompt
		end,
		applyPowerPose = function(model: Model, motors: { [string]: Motor6D })
			local kneel, hatch = TitanPose.powerTargets(model)
			TitanPose.applyStatic(motors, kneel, hatch)
		end,
		applyOff = function(motors: { [string]: Motor6D }, _style: string?)
			TitanPose.applyOff(motors)
		end,
		buildDock = function(home: CFrame, parent: Instance)
			TitanDock.buildDock(home, parent)
		end,
		updatePlug = TitanDock.updatePlug,
		chargeRate = TitanDock.ChargeRate,
		variantName = function(variantId: string): string
			return TitanConfig.getVariant(variantId).displayName
		end,
	},
} :: { [string]: TypeDef }

-- The type id of a mech model.
function MechTypes.idOf(model: Instance): string
	local id = model:GetAttribute(MechTypes.Attribute)
	return if typeof(id) == "string" and MechTypes.Types[id] then id else MechTypes.Default
end

-- The type definition for a model or a type id.
function MechTypes.get(modelOrId: Instance | string): TypeDef
	if typeof(modelOrId) == "string" then
		return MechTypes.Types[modelOrId] or MechTypes.Types[MechTypes.Default]
	end
	return MechTypes.Types[MechTypes.idOf(modelOrId :: Instance)]
end

return MechTypes
