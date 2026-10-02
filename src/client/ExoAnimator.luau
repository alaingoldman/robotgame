--!strict
-- Client-side motion for every EXO-1 exoskeleton in view (built by the
-- server, see ExoService / ExoBuilder): pulses the green lights, re-aims the
-- pistons that cross a joint, and walks the hoisted frame (Motor6D
-- Transforms driven by the root's speed). Purely cosmetic and local, so each
-- client animates all exos without any replication. Also binds the debug key
-- (ExoConfig.DebugKey) to the ExoToggle remote.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExoBuilder = require(Shared:WaitForChild("ExoBuilder"))
local ExoConfig = require(Shared:WaitForChild("ExoConfig"))

local ExoAnimator = {}

local F = ExoConfig.Frame
local COL = ExoConfig.Colors
local TAU = math.pi * 2

-- tagged instances, kept in sets
local function tracked(tag: string): { [Instance]: boolean }
	local set: { [Instance]: boolean } = {}
	for _, inst in CollectionService:GetTagged(tag) do
		set[inst] = true
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		set[inst] = true
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		set[inst] = nil
	end)
	return set
end

type Gait = {
	root: BasePart,
	motors: { [string]: Motor6D },
	phase: number,
	amount: number,
	air: number,
}
local gaits: { [Instance]: Gait } = {}

local function gaitOf(model: Instance): Gait?
	local g = gaits[model]
	if g and g.root.Parent then
		return g
	end
	local bone = model:FindFirstChild("ExoBone_Root")
	local weld = bone and bone:FindFirstChild("ExoWeld") :: Weld?
	local root = weld and weld.Part0
	if not root then
		return nil
	end
	local motors: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[(string.gsub(d.Name, "^ExoJoint_", ""))] = d
		end
	end
	g = { root = root, motors = motors, phase = 0, amount = 0, air = 0 }
	gaits[model] = g
	return g
end

local function set(g: Gait, name: string, cf: CFrame)
	local m = g.motors[name]
	if m then
		m.Transform = cf
	end
end

local function walkFrame(g: Gait, dt: number, t: number)
	local vel = g.root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local k = math.min(1, dt * 8)
	g.amount += (math.clamp(speed / 10, 0, 1) - g.amount) * k
	g.air += ((if math.abs(vel.Y) > 4 then 1 else 0) - g.air) * math.min(1, dt * 6)
	g.phase = (g.phase + dt * math.min(speed / F.Stride, F.MaxCadence) * TAU) % TAU
	local a, air, ph = g.amount * (1 - g.air), g.air, g.phase
	for _, sd in { { "R", 0 }, { "L", math.pi } } do
		local n, off = sd[1] :: string, sd[2] :: number
		local p = ph + off
		local hip = a * F.HipSwing * math.sin(p) + air * 0.45
		local knee = -(0.06 + a * F.KneeBend * math.max(0, math.cos(p))) - air * 0.9
		set(g, "Hip" .. n, CFrame.Angles(hip, 0, 0))
		set(g, "Knee" .. n, CFrame.Angles(knee, 0, 0))
		set(g, "Ankle" .. n, CFrame.Angles(-(hip + knee) * 0.8, 0, 0))
		-- arms swing against their own side's leg; elbows bent a little
		set(g, "Shoulder" .. n, CFrame.Angles(-a * F.ArmSwing * math.sin(p) - air * 0.3, 0, 0))
		set(g, "Elbow" .. n, CFrame.Angles(0.2 + 0.25 * a + air * 0.4, 0, 0))
	end
	local bob = -F.Bob * a * math.abs(math.cos(ph))
	set(g, "Root", CFrame.new(0, bob, 0) * CFrame.Angles(0, 0.06 * a * math.sin(ph), 0))
	set(g, "Waist", CFrame.Angles(0.03 * math.sin(t * 1.7) + 0.06 * a, -0.08 * a * math.sin(ph), 0))
end

function ExoAnimator.start()
	local lights = tracked(ExoBuilder.LightTag)
	local pistons = tracked(ExoBuilder.PistonTag)
	local frames = tracked(ExoBuilder.FrameTag)

	RunService.PreRender:Connect(function(dt)
		local t = os.clock()
		for part in lights do
			if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
				local phase = (part:GetAttribute("Phase") :: number?) or 0
				local f = 0.5 + 0.5 * math.sin(TAU * (t / ExoConfig.PulsePeriod + phase))
				part.Color = COL.glowDim:Lerp(COL.glow, f * f)
			end
		end
		for model in frames do
			if model:IsDescendantOf(workspace) then
				local g = gaitOf(model)
				if g then
					walkFrame(g, dt, t)
				end
			else
				gaits[model] = nil
			end
		end
		for folder in pistons do
			if folder:IsDescendantOf(workspace) then
				ExoBuilder.updatePiston(folder)
			end
		end
	end)

	if ExoConfig.AllowToggle then
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == ExoConfig.DebugKey then
				local remotes = ReplicatedStorage:FindFirstChild("ExoRemotes")
				local toggle = remotes and remotes:FindFirstChild("ExoToggle")
				if toggle and toggle:IsA("RemoteEvent") then
					toggle:FireServer("Cycle")
				end
			end
		end)
	end
end

return ExoAnimator
