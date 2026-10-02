--!strict
-- CRM-01 "Crimson" boarding camera, local pilot only (after CrimsonPilot). The
-- Crimson uses the placeholder get-in (MechTypes cinematicBoarding = false,
-- see PlaceholderPilot / MechService placeholderEnter): E seats the avatar in
-- the back pod at once (CrimsonAnimator shows a stand-in jumping up into it),
-- the hatch slams, the eyes flicker on and the mech rises from its kneel
-- (CrimsonConfig.Board). This flies the camera over it: behind and above
-- the open pod as the pilot climbs in and the hatch shuts, round to the front,
-- low on the face as the eyes light, up as it stands, then behind it into
-- the normal pilot camera when the controls are handed over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local CrimsonConfig = require(Shared:WaitForChild("CrimsonConfig"))

local CrimsonPilot = {}

local player = Players.LocalPlayer
local BIND = "CrimsonBoardCam"
local running: {}? = nil

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Camera keys in the mech's root frame (it faces -Z, +Z = behind; the root is
-- on the hip line, the knelt pod about 2.5 studs below it).
local B = CrimsonConfig.Board
local KEYS = {
	{ t = B.ClimbEnd + 0.15, eye = Vector3.new(-6.5, 3.5, 15), focus = Vector3.new(0, -2.5, 3) }, -- the open pod, the pilot jumps in
	{ t = B.HatchCloseEnd, eye = Vector3.new(-4.5, 1.5, 11), focus = Vector3.new(0, -2.5, 3) }, -- in on the hatch as it slams
	{ t = B.PowerUp + 0.35, eye = Vector3.new(3.5, -1.5, -12), focus = Vector3.new(0, 0.5, -1) }, -- round the front, low: the eyes light
	{ t = B.StandEnd, eye = Vector3.new(-9, 4, -17), focus = Vector3.new(0, 5, 0) }, -- it rises off its knee
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

function CrimsonPilot.start()
	local pilotChanged = ReplicatedStorage:WaitForChild("MechRemotes"):WaitForChild("PilotChanged") :: RemoteEvent
	pilotChanged.OnClientEvent:Connect(function(model: Model?, phase: string?)
		local mine = model ~= nil and MechTypes.idOf(model) == CrimsonConfig.TypeId
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

return CrimsonPilot
