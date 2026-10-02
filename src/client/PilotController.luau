--!strict
-- Local pilot state: driving, exit key, HUD and footstep camera shake.
--
-- The avatar stays the Character, sitting in the cockpit. The mech is a
-- separate Humanoid whose physics this client owns while piloting: every
-- frame the default controls' move vector is turned camera-relative and
-- fed to the mech's Humanoid:Move. Jump (Space / A / touch button) makes the
-- mech jump; the avatar itself can't jump out of its seat.
--
-- The server sends PilotChanged(model, phase):
--   "Boarding"     -> the character walks in and sits, no controls
--   "Online"       -> piloting: controls, HUD, sprint, exit
--   "PoweringDown" -> exiting: controls released while the mech squats
--   "Exiting"      -> unseated in the open cockpit, walks out, no controls
--   nil model      -> back on foot, controls returned

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Boarding = require(script.Parent.Boarding)
local MechAnimator = require(script.Parent.MechAnimator)
local Type99Animator = require(script.Parent.Type99Animator)
local TitanAnimator = require(script.Parent.TitanAnimator) -- BRZ-01 jump windup / airborne / landing
local KnightAnimator = require(script.Parent.KnightAnimator) -- VK-01 airborne / landing / footsteps
local GunnerAnimator = require(script.Parent.GunnerAnimator) -- GR-07 airborne / landing / footsteps
local Mech2Animator = require(script.Parent.Mech2Animator) -- PLD-02 jump windup / airborne / landing / footsteps
local CrimsonAnimator = require(script.Parent.CrimsonAnimator) -- CRM-01 jump windup / airborne / landing / footsteps
local MechConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MechConfig"))
local MechTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MechTypes"))

local PilotController = {}

local SPRINT_ACTION = "MechSprint"
local JUMP_ACTION = "MechJump"
-- above the PlayerModule's shift-lock binding so Shift sprints instead
local SPRINT_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local SPRINT_FOV_BOOST = 8

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("MechRemotes")
local pilotChanged = remotes:WaitForChild("PilotChanged") :: RemoteEvent
local exitMech = remotes:WaitForChild("ExitMech") :: RemoteEvent

local current: Model? = nil
local changedSignal = Instance.new("BindableEvent")
PilotController.Changed = changedSignal.Event

local shake = 0
local hud: ScreenGui

local pilotHumanoid: Humanoid? = nil
local driving = false
local sprinting = false
local baseFov: number? = nil
local fovBoost = 0
local jumpPending = false -- windup running
local lastLanded = 0

local function buildHud()
	hud = Instance.new("ScreenGui")
	hud.Name = "MechHud"
	hud.ResetOnSpawn = false
	hud.Enabled = false

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -24)
	bar.Size = UDim2.fromOffset(660, 44)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 20)
	bar.BackgroundTransparency = 0.25
	bar.Parent = hud
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(236, 205, 40)
	stroke.Thickness = 1.5
	stroke.Parent = bar

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(230, 230, 220)
	label.Text = "HWM-04B ONLINE   ·   [SHIFT] SPRINT   ·   [SPACE] JUMP   ·   [E] EXIT   ·   [I] INVENTORY"
	label.Parent = bar

	hud.Parent = player:WaitForChild("PlayerGui")
end

local function onExitAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		exitMech:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

-- Per-type movement: the WTK-99 has its own speeds, jump and animator.
local function isType99(model: Model?): boolean
	return model ~= nil and MechTypes.idOf(model) == "Type99"
end

local function speedsOf(model: Model?): (number, number)
	if isType99(model) then
		return MechConfig.Type99Anim.WalkSpeed, MechConfig.Type99Anim.SprintSpeed
	end
	return MechConfig.WalkSpeed, MechConfig.SprintSpeed
end

local function isTitan(model: Model?): boolean
	return model ~= nil and MechTypes.idOf(model) == "Titan"
end

local function jumpOf(model: Model?): (number, number)
	if isType99(model) then
		return MechConfig.Type99Anim.JumpPower, MechConfig.Type99Anim.JumpWindup
	end
	if isTitan(model) then
		return MechConfig.JumpPower, TitanAnimator.JumpWindup -- deeper crouch before the legs fire
	end
	if model ~= nil and MechTypes.idOf(model) == "Mech2" then
		return MechConfig.JumpPower, Mech2Animator.JumpWindup
	end
	if model ~= nil and MechTypes.idOf(model) == "Crimson" then
		return MechConfig.JumpPower, CrimsonAnimator.JumpWindup
	end
	return MechConfig.JumpPower, MechConfig.JumpWindup
end

-- Airborne state from whichever animator drives this mech type.
local function isAirborne(model: Model): boolean
	if isTitan(model) then
		return TitanAnimator.isAirborne(model)
	end
	local id = MechTypes.idOf(model)
	if id == "Knight" then
		return KnightAnimator.isAirborne(model)
	elseif id == "Gunner" then
		return GunnerAnimator.isAirborne(model)
	elseif id == "Mech2" then
		return Mech2Animator.isAirborne(model)
	elseif id == "Crimson" then
		return CrimsonAnimator.isAirborne(model)
	end
	return if isType99(model) then Type99Animator.isAirborne(model) else MechAnimator.isAirborne(model)
end

-- Battery flat (Charge 0, see MechBattery): no sprint, no jump, half speed.
local function batteryEmpty(): boolean
	local c = current and current:GetAttribute("Charge")
	return typeof(c) == "number" and c <= 0
end

local function targetSpeed(): number
	local walk, sprint = speedsOf(current)
	if batteryEmpty() then
		return walk * MechConfig.Battery.EmptySpeedFactor
	end
	return if sprinting then sprint else walk
end

local function setSprinting(on: boolean)
	sprinting = on
	local humanoid = pilotHumanoid
	if humanoid then
		humanoid.WalkSpeed = targetSpeed()
	end
end

-- Hold to sprint. WalkSpeed is only changed on this (network-owning) client;
-- MechAnimator derives the sprint pose from speed so everyone sees it.
local function onSprintAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setSprinting(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setSprinting(false)
	end
	return Enum.ContextActionResult.Sink
end

-- Grounded, not mid-jump and past the landing cooldown.
local function canJump(): boolean
	local humanoid = pilotHumanoid
	if not (driving and humanoid and current) or jumpPending or batteryEmpty() then
		return false
	end
	local state = humanoid:GetState()
	if isAirborne(current :: Model) or state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return false
	end
	return os.clock() - lastLanded >= MechConfig.JumpCooldown
end

-- Jump input makes the mech jump after a quick squat. Always sunk, so the
-- seated avatar never gets the jump.
local function onJumpAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin and canJump() then
		local model = current :: Model
		jumpPending = true
		local power, windup = jumpOf(model)
		if isType99(model) then
			Type99Animator.windup(model)
		elseif isTitan(model) then
			TitanAnimator.windup(model)
		elseif MechTypes.idOf(model) == "Knight" then
			KnightAnimator.windup(model)
		elseif MechTypes.idOf(model) == "Gunner" then
			GunnerAnimator.windup(model)
		elseif MechTypes.idOf(model) == "Mech2" then
			Mech2Animator.windup(model)
		elseif MechTypes.idOf(model) == "Crimson" then
			CrimsonAnimator.windup(model)
		else
			MechAnimator.windup(model)
		end
		task.delay(windup, function()
			jumpPending = false
			local humanoid = pilotHumanoid
			if driving and humanoid and current == model then
				humanoid.JumpPower = power
				humanoid.Jump = true
			end
		end)
	end
	return Enum.ContextActionResult.Sink
end

-- Keeps the seated avatar from jumping out of the cockpit seat.
local function lockAvatar(on: boolean)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, not on)
	end
end

-- Feeds the default controls' move vector to the mech, camera-relative.
local function drive()
	local humanoid = pilotHumanoid
	if not (driving and humanoid) then
		return
	end
	-- the battery can run flat (or get topped up) at any moment
	local speed = targetSpeed()
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
	local controls = Boarding.getControls()
	local move = if controls then controls:GetMoveVector() :: Vector3 else Vector3.zero
	local cf = workspace.CurrentCamera.CFrame
	local forward = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if forward.Magnitude < 1e-3 then
		-- looking straight down: the top of the screen is forward
		forward = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
	end
	forward = forward.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local dir = right * move.X - forward * move.Z
	if dir.Magnitude > 1 then
		dir = dir.Unit
	end
	humanoid:Move(dir, false)
end

-- Drops the pilot controls (driving, exit, sprint, HUD) but keeps the mech current.
local function releaseControls()
	driving = false
	local humanoid = pilotHumanoid
	if humanoid then
		humanoid:Move(Vector3.zero, false)
		humanoid.JumpPower = 0
	end
	jumpPending = false
	ContextActionService:UnbindAction(SPRINT_ACTION)
	ContextActionService:UnbindAction(JUMP_ACTION)
	ContextActionService:UnbindAction("ExitMech")
	setSprinting(false)
	hud.Enabled = false
end

local function setPiloting(model: Model?)
	current = model
	local camera = workspace.CurrentCamera
	if model then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		pilotHumanoid = humanoid
		sprinting = false
		if humanoid then
			humanoid.WalkSpeed = (speedsOf(model))
			if camera.CameraSubject ~= humanoid then
				camera.CameraSubject = humanoid
			end
			-- the pilot's client runs the humanoid; keep the mech from toppling
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
			humanoid.JumpPower = (jumpOf(model))
		end
		ProximityPromptService.Enabled = false
		driving = true
		local label = hud:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			label.Text = MechTypes.get(model).displayName .. " ONLINE   ·   [SHIFT] SPRINT   ·   [SPACE] JUMP   ·   [E] EXIT   ·   [I] INVENTORY"
		end
		lockAvatar(true)
		-- the controls stay on for the move vector: jump goes to the mech, never the seated avatar
		ContextActionService:BindActionAtPriority(JUMP_ACTION, onJumpAction, true, SPRINT_PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
		ContextActionService:SetTitle(JUMP_ACTION, "Jump")
		ContextActionService:BindAction("ExitMech", onExitAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
		ContextActionService:SetTitle("ExitMech", "Exit")
		ContextActionService:BindActionAtPriority(
			SPRINT_ACTION,
			onSprintAction,
			true,
			SPRINT_PRIORITY,
			Enum.KeyCode.LeftShift,
			Enum.KeyCode.RightShift,
			Enum.KeyCode.ButtonL3
		)
		ContextActionService:SetTitle(SPRINT_ACTION, "Sprint")
		if baseFov == nil then
			baseFov = camera.FieldOfView
		end
		fovBoost = 0
		hud.Enabled = true
	else
		releaseControls()
		pilotHumanoid = nil
		if baseFov then
			camera.FieldOfView = baseFov
			baseFov = nil
		end
		fovBoost = 0
	end
	changedSignal:Fire(model)
end

-- Back on foot after an exit: if the avatar was put down inside something
-- solid (the mech was parked against another mech or a wall, so the ramp /
-- nose / hatch exit spot is blocked), move it to the nearest clear spot on
-- the ground instead of leaving it wedged (stuck "Climbing" in the armor).
local STUCK_BOX = Vector3.new(2.6, 4.6, 1.6)
local function overlapsAt(char: Model, cf: CFrame): boolean
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	params.CollisionGroup = if hrp then hrp.CollisionGroup else "Default"
	return #workspace:GetPartBoundsInBox(cf, STUCK_BOX, params) > 0
end

local function unstick()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hrp and hum) or hum.Sit or hum.Health <= 0 or current then
		return
	end
	if not overlapsAt(char, hrp.CFrame) then
		return
	end
	local mechs = workspace:FindFirstChild("Mechs")
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { char }
	ray.RespectCanCollide = true
	local lift = hum.HipHeight + hrp.Size.Y / 2 -- root center above the feet
	local origin = hrp.Position
	for radius = 4, 40, 3 do
		local steps = math.max(8, math.floor(radius * 1.5))
		local best: CFrame? = nil
		for i = 0, steps - 1 do
			local a = i / steps * math.pi * 2
			local p = origin + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			local hit = workspace:Raycast(p + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), ray)
			-- stand on the world, not on top of a mech
			if hit and not (mechs and hit.Instance:IsDescendantOf(mechs)) then
				local cf = CFrame.new(hit.Position + Vector3.new(0, lift + 0.2, 0)) * hrp.CFrame.Rotation
				if not overlapsAt(char, cf) then
					best = cf
					break
				end
			end
		end
		if best then
			hrp.AssemblyLinearVelocity = Vector3.zero
			char:PivotTo(best)
			hum:ChangeState(Enum.HumanoidStateType.Landed)
			return
		end
	end
end

local function onPilotChanged(model: Model?, phase: string?)
	if model and phase == "Boarding" then
		-- no prompts (the E that boarded must not trigger anything else)
		ProximityPromptService.Enabled = false
		lockAvatar(true)
		Boarding.lockControls(true)
		Boarding.beginBoard(model)
	elseif model and phase == "Online" then
		Boarding.stop()
		setPiloting(model)
		Boarding.lockControls(false)
	elseif model and phase == "PoweringDown" then
		releaseControls()
		Boarding.lockControls(true)
		Boarding.beginExit(model)
	elseif model and (phase == "Seated" or phase == "Unseating") then
		-- placeholder get-in / get-out (VK-01, GR-07; no cinematic, see PlaceholderPilot)
		releaseControls()
		ProximityPromptService.Enabled = false
		lockAvatar(true)
		Boarding.lockControls(true)
	elseif model and phase == "Exiting" then
		-- unseated in the open cockpit; the exit sequence walks it out
		if current then
			setPiloting(nil)
		end
		lockAvatar(false)
		Boarding.lockControls(true)
	else
		if current then
			setPiloting(nil)
		end
		Boarding.reset()
		lockAvatar(false)
		Boarding.lockControls(false)
		ProximityPromptService.Enabled = true
		task.delay(0.4, unstick)
	end
end

function PilotController.getMech(): Model?
	return current
end

function PilotController.start()
	buildHud()
	pilotChanged.OnClientEvent:Connect(onPilotChanged)
	-- after the PlayerModule reads input (Input priority), before physics
	RunService:BindToRenderStep("MechDrive", Enum.RenderPriority.Input.Value + 1, drive)

	-- heavier fall on the owning client: the mech drops fast after the apex
	RunService.PreSimulation:Connect(function(dt)
		local humanoid = pilotHumanoid
		local root = humanoid and humanoid.RootPart
		local model = current
		if not (driving and model and root) or root.Anchored then
			return
		end
		local v = root.AssemblyLinearVelocity
		if v.Y < 8 and isAirborne(model) then
			root.AssemblyLinearVelocity = v - Vector3.new(0, workspace.Gravity * MechConfig.JumpFallGravity * dt, 0)
		end
	end)

	MechAnimator.onLand(function(model, impact)
		if model == current then
			lastLanded = os.clock()
			shake = math.max(shake, 0.6 + impact / 35)
		end
	end)

	MechAnimator.onFootstep(function(model)
		if model == current then
			shake = if sprinting then 0.5 else 0.35
		end
	end)

	-- the BRZ-01's animator (it adds its own landing thump)
	TitanAnimator.onLand(function(model, _impact)
		if model == current then
			lastLanded = os.clock()
		end
	end)

	-- VK-01 / GR-07 / PLD-02 / CRM-01 animators: footfall shake and landing thumps
	for _, anim in { KnightAnimator, GunnerAnimator, Mech2Animator, CrimsonAnimator } :: { any } do
		anim.onFootstep(function(model: Model, _side: string)
			if model == current then
				shake = math.max(shake, if sprinting then 0.5 else 0.35)
			end
		end)
		anim.onLand(function(model: Model, impact: number)
			if model == current then
				lastLanded = os.clock()
				shake = math.max(shake, 0.6 + impact / 35)
			end
		end)
	end

	-- the WTK-99's animator: heavier stomps, scaled per step
	Type99Animator.onLand(function(model, impact)
		if model == current then
			lastLanded = os.clock()
			shake = math.max(shake, 0.7 + impact / 30)
		end
	end)
	Type99Animator.onFootstep(function(model, _side, strength)
		if model == current then
			shake = math.max(shake, strength)
		end
	end)

	RunService:BindToRenderStep("MechCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		-- widen the view while actually running fast, not just holding Shift
		local fov = baseFov
		local humanoid = pilotHumanoid
		if current and fov and humanoid then
			local root = humanoid.RootPart
			local target = 0
			if sprinting and root then
				local v = root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				local walk, sprint = speedsOf(current)
				target = math.clamp((speed - walk) / (sprint - walk), 0, 1)
			end
			fovBoost += (target - fovBoost) * math.min(1, dt * 5)
			camera.FieldOfView = fov + fovBoost * SPRINT_FOV_BOOST
		end
		if shake > 0.01 and current then
			local k = shake * 0.12
			camera.CFrame *= CFrame.new(0, (math.random() - 0.5) * k, 0) * CFrame.Angles((math.random() - 0.5) * k * 0.05, 0, 0)
			shake *= math.exp(-dt * 12)
		end
	end)
end

return PilotController
