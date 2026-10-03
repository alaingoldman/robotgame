--!strict
-- On-foot controls for the core loop:
--   ATTACK  mouse left / gamepad R2 / the touch ATTACK button (hold = keep
--           swinging at the weapon's rate). Predicted: the swing animation and
--           whoosh play at once, the server confirms hits (Fx via Hit).
--           Melee snaps the character to face the nearest target in reach and
--           sends it as a hint; the Rivet Gun aims along the mouse / camera.
--   SPRINT  hold Shift / L3 (touch: SPRINT toggle button): faster, drains battery.
-- Movement: WalkSpeed / jump are set here from the server's attributes
-- (SpeedMul / JumpMul from legs, carrying, battery empty, sprint), and left
-- alone while seated / piloting / boarding / climbing.

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local ExoConfig = require(Shared:WaitForChild("ExoConfig"))
local Fx = require(script.Parent.Fx)

local Controls = {}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CoreRemotes")
local attackRemote = remotes:WaitForChild("Attack") :: RemoteEvent
local sprintRemote = remotes:WaitForChild("Sprint") :: RemoteEvent

local ClientRoot = script.Parent.Parent
local PilotController: any = require(ClientRoot:WaitForChild("PilotController"))
local Boarding: any = require(ClientRoot:WaitForChild("Boarding"))
local Climb: any = require(ClientRoot:WaitForChild("Climb"))

local held = false
local sprintHeld = false
local sprintSent = false
local lastAttack = 0
local combo = 0
local blocked: () -> boolean = function()
	return false
end

-- UI hooks (set by the HUD / locker): pause attacks while a menu is open.
function Controls.setBlocker(fn: () -> boolean)
	blocked = fn
end

local function weapon(): CoreLoopConfig.Weapon
	local id = player:GetAttribute("Weapon")
	return CoreLoopConfig.Weapons[if typeof(id) == "string" then id else "Fists"] or CoreLoopConfig.Weapons.Fists
end

local function onFoot(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or hum.Health <= 0 or hum.SeatPart then
		return nil, nil, nil
	end
	if PilotController.getMech() or Boarding.isActive() or Climb.isDriving(char) then
		return nil, nil, nil
	end
	return char, hum, root
end

local function nearestTarget(root: BasePart, reach: number): Model?
	local cam = workspace.CurrentCamera
	local fwd = root.CFrame.LookVector
	local camF = if cam then cam.CFrame.LookVector else fwd
	camF = Vector3.new(camF.X, 0, camF.Z)
	camF = if camF.Magnitude > 0.01 then camF.Unit else fwd
	local best, bestScore = nil, math.huge
	for _, m in CollectionService:GetTagged("CoreTarget") do
		if m:IsA("Model") and m.PrimaryPart and ((m:GetAttribute("HP") :: number?) or 0) > 0 then
			local c = m.PrimaryPart.Position
			local r = (m:GetAttribute("Radius") :: number?) or 2
			local d = Vector3.new(c.X - root.Position.X, 0, c.Z - root.Position.Z)
			local dist = d.Magnitude - r
			if dist <= reach and math.abs(c.Y - root.Position.Y) < r + 6 then
				local dir = if d.Magnitude > 0.01 then d.Unit else fwd
				local facing = math.max(dir:Dot(fwd), dir:Dot(camF))
				if facing > -0.2 or dist < 2 then
					local score = dist - facing * 3
					if score < bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	return best
end

local function aimDirection(root: BasePart): Vector3
	local cam = workspace.CurrentCamera
	if not cam then
		return root.CFrame.LookVector
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local target: Vector3
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		target = ray.Origin + ray.Direction * 200
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
		if hit then
			target = hit.Position
		end
	else
		target = cam.CFrame.Position + cam.CFrame.LookVector * 200
		local tgt = nearestTarget(root, 40)
		if tgt and tgt.PrimaryPart then
			target = tgt.PrimaryPart.Position
		end
	end
	local d = target - origin
	return if d.Magnitude > 0.1 then d.Unit else root.CFrame.LookVector
end

local function tryAttack()
	local char, hum, root = onFoot()
	if not (char and hum and root) or blocked() or player:GetAttribute("BatteryDead") == true then
		return
	end
	local w = weapon()
	local now = os.clock()
	if now - lastAttack < w.cooldown then
		return
	end
	local battery = (player:GetAttribute("Battery") :: number?) or 0
	local drainMul = (player:GetAttribute("DrainMul") :: number?) or 1
	if battery < w.cost * drainMul then
		lastAttack = now
		Fx.sound("Beep", 0.4, 1.2)
		Fx.shake(0.1)
		Controls.NoPower()
		return
	end
	combo = if now - lastAttack < CoreLoopConfig.Combat.ComboWindow + w.cooldown then (combo % 3) + 1 else 1
	lastAttack = now
	local aim: Vector3? = nil
	local hint: Model? = nil
	if w.ranged then
		aim = aimDirection(root)
		local flat = Vector3.new((aim :: Vector3).X, 0, (aim :: Vector3).Z)
		if flat.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
		Controls.Shot(root, aim :: Vector3)
	else
		hint = nearestTarget(root, (w.aoe or w.range) + 1.5)
		if hint and hint.PrimaryPart then
			local c = hint.PrimaryPart.Position
			local flat = Vector3.new(c.X - root.Position.X, 0, c.Z - root.Position.Z)
			if flat.Magnitude > 0.5 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			end
		end
	end
	Fx.swing(char, combo, w.id)
	Fx.sound("Swing", if w.anim == "Hammer" then 0.45 else 0.25, if w.anim == "Hammer" then 1.05 else 1.5 + combo * 0.12)
	attackRemote:FireServer(aim, hint)
end

-- hooks for the HUD / Fx (set in CoreLoop init)
function Controls.NoPower() end
function Controls.Shot(_root: BasePart, _aim: Vector3) end

local function setSprint(on: boolean)
	sprintHeld = on
end

------------------------------------------------------------------ movement

local function baseJump(hum: Humanoid): (number, number)
	local exo = (player.Character and player.Character:GetAttribute("ExoForm")) ~= nil
	local mul = if exo then ExoConfig.JumpMultiplier else 1
	return StarterPlayer.CharacterJumpPower * mul, StarterPlayer.CharacterJumpHeight * mul
end

local function movement()
	local char, hum, root = onFoot()
	if not (char and hum and root) then
		if sprintSent then
			sprintSent = false
			sprintRemote:FireServer(false)
		end
		return
	end
	local battery = (player:GetAttribute("Battery") :: number?) or 0
	local empty = battery <= 0.05
	-- dead battery away from base: frozen until RETURN (HUD) + recharge
	local dead = player:GetAttribute("BatteryDead") == true
	local carrying = player:GetAttribute("CarryKind") ~= nil
	local sprinting = sprintHeld and not empty and hum.MoveDirection.Magnitude > 0.1
	if sprinting ~= sprintSent then
		sprintSent = sprinting
		sprintRemote:FireServer(sprinting)
	end
	local speed = CoreLoopConfig.BaseWalkSpeed * ((player:GetAttribute("SpeedMul") :: number?) or 1)
	if carrying then
		speed *= CoreLoopConfig.CarryMultiplier
	end
	if dead then
		speed = 0
	elseif empty then
		speed *= CoreLoopConfig.EmptyMultiplier
	elseif sprinting then
		speed *= CoreLoopConfig.SprintMultiplier
	end
	if math.abs(hum.WalkSpeed - speed) > 0.05 then
		hum.WalkSpeed = speed
	end
	local jm = (player:GetAttribute("JumpMul") :: number?) or 1
	if dead then
		jm = 0
	elseif empty then
		jm *= 0.8
	end
	local jp, jh = baseJump(hum)
	if hum.UseJumpPower then
		if math.abs(hum.JumpPower - jp * jm) > 0.05 then
			hum.JumpPower = jp * jm
		end
	elseif math.abs(hum.JumpHeight - jh * jm) > 0.01 then
		hum.JumpHeight = jh * jm
	end
	if held then
		tryAttack()
	end
end

function Controls.isSprinting(): boolean
	return sprintSent
end

function Controls.start()
	ContextActionService:BindActionAtPriority("CoreAttack", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			if input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			if not onFoot() then
				return Enum.ContextActionResult.Pass
			end
			held = true
			tryAttack()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			held = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.ContextActionPriority.Medium.Value, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("CoreAttack", "HIT")
	ContextActionService:SetPosition("CoreAttack", UDim2.new(1, -170, 1, -150))

	ContextActionService:BindActionAtPriority("CoreSprint", function(_, state, input)
		if not onFoot() then
			return Enum.ContextActionResult.Pass
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			if state == Enum.UserInputState.Begin then
				setSprint(not sprintHeld)
				ContextActionService:SetTitle("CoreSprint", if sprintHeld then "RUN!" else "RUN")
			end
			return Enum.ContextActionResult.Sink
		end
		if state == Enum.UserInputState.Begin then
			setSprint(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setSprint(false)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("CoreSprint", "RUN")
	ContextActionService:SetPosition("CoreSprint", UDim2.new(1, -250, 1, -100))

	RunService.Heartbeat:Connect(movement)
	player.CharacterAdded:Connect(function()
		held = false
		combo = 0
	end)
end

return Controls
