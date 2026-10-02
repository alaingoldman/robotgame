--!strict
-- PLACEHOLDER get-in / get-out, local pilot side, for mech types without a
-- boarding cinematic yet (MechTypes cinematicBoarding = false: VK-01 Knight,
-- GR-07 Gunner) until their cockpits are signed off. The server seats the
-- avatar at once ("Seated"), the hatch shuts, the mech stands and hands over
-- ("Online"). Exit: "Unseating" while it powers down and opens up, then
-- "Exiting": the server has unseated the avatar and this client (which owns
-- the avatar's physics) puts it down standing in front of the mech
-- (Builder.offPoints(rootCF).exit). PilotController handles controls / HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechTypes = require(Shared:WaitForChild("MechTypes"))
local Boarding = require(script.Parent.Boarding)

local PlaceholderPilot = {}

local player = Players.LocalPlayer

local function isPlaceholder(model: Model?): boolean
	return model ~= nil and MechTypes.get(model).cinematicBoarding == false
end

-- Waits (briefly) for the seat weld to go, then stands the avatar on the
-- ground in front of the mech, facing away from it.
local function putDown(model: Model)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and hrp and root) then
		return
	end
	local seat = model:FindFirstChild("PilotSeat", true)
	local t0 = os.clock()
	while os.clock() - t0 < 1 do
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if not weld and not hum.Sit then
			break
		end
		hum.Sit = false
		task.wait()
	end
	local p = MechTypes.get(model).Builder.offPoints(root.CFrame)
	local pos = p.exit + Vector3.new(0, hum.HipHeight + hrp.Size.Y / 2 + 0.1, 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(CFrame.lookAt(pos, pos + p.forward))
end

function PlaceholderPilot.start()
	local pilotChanged = ReplicatedStorage:WaitForChild("MechRemotes"):WaitForChild("PilotChanged") :: RemoteEvent
	pilotChanged.OnClientEvent:Connect(function(model: Model?, phase: string?)
		if not (model and isPlaceholder(model)) then
			return
		end
		if phase == "Online" then
			-- pilot camera zoom range (restored on foot by Boarding.reset)
			Boarding.saveOnFootZoom()
			player.CameraMaxZoomDistance = math.max(player.CameraMaxZoomDistance, MechConfig.PilotZoomMax)
			player.CameraMinZoomDistance = MechConfig.PilotZoomMin
			player.CameraMaxZoomDistance = MechConfig.PilotZoomMax
		elseif phase == "Exiting" then
			task.spawn(putDown, model)
		end
	end)
end

return PlaceholderPilot
