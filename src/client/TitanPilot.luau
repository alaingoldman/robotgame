--!strict
-- BRZ-01 Titan boarding camera, local pilot only. The Titan uses the
-- placeholder get-in (MechTypes cinematicBoarding = false, see
-- PlaceholderPilot / MechService placeholderEnter): E seats the avatar in the
-- chest cockpit at once, the chest hatch swings shut and the mech rises from
-- its kneel (TitanConfig.Board). This module flies the camera over that:
-- from where the player stood, low across the front of the closing hatch,
-- up the chest as it stands, and round behind it into the normal pilot
-- camera when the controls are handed over ("Online").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local TitanConfig = require(Shared:WaitForChild("TitanConfig"))

local TitanPilot = {}

local player = Players.LocalPlayer
local BIND = "TitanBoardCam"
local running: {}? = nil

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Camera keys in the mech's root frame (it faces -Z): { time, eye, focus }.
local B = TitanConfig.Board
local KEYS = {
	{ t = 0.55, eye = Vector3.new(9, -7, -21), focus = Vector3.new(0, -4, -3) }, -- low, across the hatch
	{ t = B.StandStart + 0.5, eye = Vector3.new(-13, -2, -24), focus = Vector3.new(0, 0, -2) }, -- it rises
	{ t = B.Online, eye = Vector3.new(7, 13, 36), focus = Vector3.new(0, 9, 0) }, -- behind: hand over
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
	local startFocus = startCF.Position + startCF.LookVector * 20
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

function TitanPilot.start()
	local pilotChanged = ReplicatedStorage:WaitForChild("MechRemotes"):WaitForChild("PilotChanged") :: RemoteEvent
	pilotChanged.OnClientEvent:Connect(function(model: Model?, phase: string?)
		local isTitan = model ~= nil and MechTypes.idOf(model) == TitanConfig.TypeId
		if isTitan and phase == "Seated" then
			play(model :: Model)
		elseif running and (phase == "Online" or not isTitan) then
			-- controls handed over: back to the normal (custom) pilot camera
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

return TitanPilot
