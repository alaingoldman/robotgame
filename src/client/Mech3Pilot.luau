--!strict
-- SRF-03 "Seraph" boarding camera, local pilot only (after CrimsonPilot). The
-- Seraph uses the placeholder get-in (MechTypes cinematicBoarding = false,
-- see PlaceholderPilot / MechService placeholderEnter): E seats the avatar in
-- the neck socket at once (Mech3Animator shows a stand-in jumping up into
-- it), the helmet flips down over it, the eyes flicker on and the mech rises
-- from its kneel (Mech3Config.Board). This flies the camera over it: in front
-- and above as the pilot jumps in, close on the helmet as it comes down, low
-- on the face as the eyes light, out as it stands and its wings settle, then
-- behind it into the normal pilot camera when the controls are handed over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local Mech3Config = require(Shared:WaitForChild("Mech3Config"))

local Mech3Pilot = {}

local player = Players.LocalPlayer
local BIND = "Mech3BoardCam"
local running: {}? = nil

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Camera keys in the mech's root frame (it faces -Z, +Z = behind; the root is
-- on the hip line, the knelt neck socket about level with it, 1 stud ahead).
local B = Mech3Config.Board
local KEYS = {
	{ t = B.ClimbEnd + 0.15, eye = Vector3.new(7, 4.5, -12), focus = Vector3.new(0, 0, -1) }, -- the open socket, the pilot jumps in
	{ t = B.HatchCloseEnd, eye = Vector3.new(3.5, 2.5, -7.5), focus = Vector3.new(0, 0.3, -1) }, -- in on the helmet as it comes down
	{ t = B.PowerUp + 0.35, eye = Vector3.new(-2.5, -0.8, -9), focus = Vector3.new(0, 0.6, -1.5) }, -- low on the face: the eyes light
	{ t = B.StandEnd, eye = Vector3.new(-10, 4, -18), focus = Vector3.new(0, 5, 0) }, -- it rises off its knee
	{ t = B.Online, eye = Vector3.new(5, 17, 27), focus = Vector3.new(0, 10, 0) }, -- behind: hand over
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

function Mech3Pilot.start()
	local pilotChanged = ReplicatedStorage:WaitForChild("MechRemotes"):WaitForChild("PilotChanged") :: RemoteEvent
	pilotChanged.OnClientEvent:Connect(function(model: Model?, phase: string?)
		local mine = model ~= nil and MechTypes.idOf(model) == Mech3Config.TypeId
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

return Mech3Pilot
