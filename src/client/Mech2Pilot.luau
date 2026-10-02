--!strict
-- PLD-02 boarding camera, local pilot only. The PLD-02 uses the placeholder
-- get-in (MechTypes cinematicBoarding = false, see PlaceholderPilot /
-- MechService placeholderEnter): E seats the avatar in the chest cockpit at
-- once, the chest hatch swings shut and the mech rises from its kneel
-- (Mech2Config.Board). This flies the camera over it: in close on the chest
-- as the hatch comes up, round the side as it stands, and up behind it into
-- the normal pilot camera when the controls are handed over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local Mech2Config = require(Shared:WaitForChild("Mech2Config"))

local Mech2Pilot = {}

local player = Players.LocalPlayer
local BIND = "Mech2BoardCam"
local running: {}? = nil

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Camera keys in the mech's root frame (it faces -Z; the root is on the hip line).
local B = Mech2Config.Board
local KEYS = {
	{ t = 0.65, eye = Vector3.new(3, 6.2, -9.5), focus = Vector3.new(0, 5.3, -1) }, -- the chest, hatch swinging shut
	{ t = B.StandStart + 0.6, eye = Vector3.new(-9, 8, -12), focus = Vector3.new(0, 8, 0) }, -- it rises off its knee
	{ t = B.Online, eye = Vector3.new(5, 15, 25), focus = Vector3.new(0, 10, 0) }, -- behind: hand over
}

local function stop()
	running = nil
	RunService:UnbindFromRenderStep(BIND)
end

local function play(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	stop()
	local token = {}
	running = token
	local camera = workspace.CurrentCamera
	local startCF = camera.CFrame
	local startFocus = startCF.Position + startCF.LookVector * 15
	local rootCF = root.CFrame
	local t0 = model:GetAttribute("PowerTime")
	local function now(): number
		return if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else 0
	end
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 3, function()
		if running ~= token then
			return
		end
		local t = now()
		local prevT, prevEye, prevFocus = 0, startCF.Position, startFocus
		local eye, focus = prevEye, prevFocus
		for _, k in KEYS do
			local e, f = (rootCF * CFrame.new(k.eye)).Position, (rootCF * CFrame.new(k.focus)).Position
			if t <= k.t then
				local u = smooth((t - prevT) / (k.t - prevT))
				eye, focus = prevEye:Lerp(e, u), prevFocus:Lerp(f, u)
				break
			end
			prevT, prevEye, prevFocus = k.t, e, f
			eye, focus = e, f
		end
		camera.CFrame = CFrame.lookAt(eye, focus)
		camera.Focus = CFrame.new(focus)
		if t >= B.Online + 0.6 or model:GetAttribute("PowerState") == "Off" or not model.Parent then
			stop()
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
end

function Mech2Pilot.start()
	local pilotChanged = ReplicatedStorage:WaitForChild("MechRemotes"):WaitForChild("PilotChanged") :: RemoteEvent
	pilotChanged.OnClientEvent:Connect(function(model: Model?, phase: string?)
		local mine = model ~= nil and MechTypes.idOf(model) == Mech2Config.TypeId
		if mine and phase == "Seated" then
			play(model :: Model)
		elseif running and (phase == "Online" or not mine) then
			stop()
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end)
	player.CharacterAdded:Connect(function()
		if running then
			stop()
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end)
end

return Mech2Pilot
