--!strict
-- Server-side battery and power cord state for every mech.
--
-- Attributes on each mech (set here, read by clients):
--   "Plugged" -- the power cord is in the socket. It stays in through
--                boarding and while the piloted mech moves around near its
--                pad; once the socket gets farther than MechCord.reach() from
--                the outlet the taut cord rips out. It plugs back in once the
--                mech has knelt again after an exit (ReplugAt into
--                PoweringDown), but only near its home spot ("Home"
--                attribute, PlugRange). A mech parked elsewhere stays
--                unplugged and doesn't charge.
--   "Charge"  -- 0..100. Charges while plugged in (in any power state, with
--                no drain); unplugged and online it drains from the root's
--                (replicated) velocity: idle, walking, sprinting, plus a
--                chunk per jump. At 0 the pilot's client limps the mech (no
--                sprint / jump, half speed).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechCord = require(Shared:WaitForChild("MechCord"))
local MechPose = require(Shared:WaitForChild("MechPose"))

local MechBattery = {}

local BAT = MechConfig.Battery
local CORD = MechConfig.Cord
local SEND_INTERVAL = 0.1 -- seconds between Charge attribute updates
local SPRINT_SPEED = (MechConfig.WalkSpeed + MechConfig.SprintSpeed) / 2
local JUMP_VY = 25 -- upward speed that counts as a takeoff
local REACH = MechCord.reach()

type State = { charge: number, sent: number, sendT: number, lastVy: number, jumpT: number }
local states: { [Model]: State } = {}

-- Whether the mech stands close enough to its home spot to reach the outlet.
local function atHome(model: Model, root: BasePart): boolean
	local home = model:GetAttribute("Home")
	if typeof(home) ~= "CFrame" then
		return false
	end
	local d = root.Position - home.Position
	return Vector3.new(d.X, 0, d.Z).Magnitude <= CORD.PlugRange
end

-- Whether the socket has pulled farther from the outlet than the cord reaches.
local function overReach(model: Model): boolean
	local home = model:GetAttribute("Home")
	local plug = MechCord.plugPoint(model)
	if typeof(home) ~= "CFrame" or not plug then
		return true
	end
	return (plug.WorldPosition - MechCord.outletPort(home)).Magnitude > REACH
end

local function updatePlug(model: Model, root: BasePart)
	local plugged = model:GetAttribute("Plugged") == true
	local state = model:GetAttribute("PowerState")
	local t = MechPose.stateTime(model)
	if plugged then
		if overReach(model) then
			model:SetAttribute("Plugged", false)
		end
	elseif (state == "Off" or (state == "PoweringDown" and t >= CORD.ReplugAt)) and atHome(model, root) and not overReach(model) then
		-- (only within reach: a mech parked facing away would rip it straight back out)
		model:SetAttribute("Plugged", true)
	end
end

local function step(dt: number)
	local now = os.clock()
	for _, inst in CollectionService:GetTagged("Mech") do
		if not inst:IsA("Model") or not inst.Parent then
			continue
		end
		local model = inst :: Model
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local st = states[model]
		if not st then
			local c = model:GetAttribute("Charge")
			local start = if typeof(c) == "number" then c else 100
			st = { charge = start, sent = start, sendT = 0, lastVy = 0, jumpT = 0 }
			states[model] = st
			model.Destroying:Connect(function()
				states[model] = nil
			end)
		end
		updatePlug(model, root)
		-- another server script (or a test) set the charge directly: adopt it
		local attr = model:GetAttribute("Charge")
		if typeof(attr) == "number" and attr ~= st.sent then
			st.charge, st.sent = math.clamp(attr, 0, 100), attr
		end

		local state = model:GetAttribute("PowerState")
		local before = st.charge
		if model:GetAttribute("Plugged") == true then
			st.charge += BAT.ChargeRate * dt
		elseif state == "Online" and not root.Anchored then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local rate = if speed > SPRINT_SPEED then BAT.SprintDrain elseif speed > 3 then BAT.WalkDrain else BAT.IdleDrain
			st.charge -= rate * dt
			if v.Y > JUMP_VY and st.lastVy <= JUMP_VY and now - st.jumpT > 0.5 then
				st.jumpT = now
				st.charge -= BAT.JumpCost
			end
			st.lastVy = v.Y
		end
		st.charge = math.clamp(st.charge, 0, 100)

		-- replicate a few times a second (and right away at empty / full)
		st.sendT += dt
		local edge = st.charge ~= before and (st.charge == 0 or st.charge == 100)
		if st.sendT >= SEND_INTERVAL or edge then
			st.sendT = 0
			local rounded = math.floor(st.charge * 10 + 0.5) / 10
			if st.sent ~= rounded then
				st.sent = rounded
				model:SetAttribute("Charge", rounded)
			end
		end
	end
end

function MechBattery.start()
	RunService.Heartbeat:Connect(step)
end

return MechBattery
