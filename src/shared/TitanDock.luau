--!strict
-- BRZ-01 charging pylon (TitanConfig.Dock). A brass-and-steel coil tower
-- stands at the back of the Titan's pad; while the mech is parked at home a
-- teal arc runs from the coil's emitter to the battery terminal on the
-- mech's back (TitanAnimator draws it) and the battery charges. Walking off
-- past Reach breaks the arc; it re-connects once the mech has knelt again
-- after an exit (ReplugAt) near its home spot.
--
--   TitanDock.buildDock(home, parent)   the pylon (server pads, edit preview)
--   TitanDock.emitterPosition(home)     where the arc starts
--   TitanDock.terminal(model)           the battery terminal Attachment
--   TitanDock.updatePlug(model, root)   MechBattery hook: sets "Plugged"

local CollectionService = game:GetService("CollectionService")

local TitanConfig = require(script.Parent.TitanConfig)

local TitanDock = {}

local DOCK = TitanConfig.Dock
TitanDock.Tag = "TitanDock"
TitanDock.ChargeRate = DOCK.ChargeRate
local EMITTER_HEIGHT = 15.5

-- Pylon base frame (on the ground) for a pad whose home spot is `home`.
function TitanDock.dockCFrame(home: CFrame): CFrame
	return home * CFrame.new(DOCK.Offset)
end

function TitanDock.emitterPosition(home: CFrame): Vector3
	return (TitanDock.dockCFrame(home) * CFrame.new(0, EMITTER_HEIGHT, 0)).Position
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function TitanDock.buildDock(home: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "TitanDock"
	local base = TitanDock.dockCFrame(home)
	local brass = Color3.fromRGB(176, 128, 60)
	local dark = Color3.fromRGB(58, 44, 34)
	local steel = Color3.fromRGB(190, 194, 200)
	local up = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
	local foot = part(model, "DockBase", Vector3.new(6, 1.2, 6), base * CFrame.new(0, 0.6, 0), dark, Enum.Material.Metal)
	foot.CanCollide = true
	part(model, "DockPlinth", Vector3.new(4.4, 1.0, 4.4), base * CFrame.new(0, 1.7, 0), brass, Enum.Material.SmoothPlastic)
	local column = part(model, "DockColumn", Vector3.new(10.5, 1.6, 1.6), base * CFrame.new(0, 7.4, 0) * up, dark, Enum.Material.Metal, Enum.PartType.Cylinder)
	column.CanCollide = true
	-- coil: stacked steel rings with brass spacers
	for i = 0, 7 do
		local y = 6.0 + i * 0.95
		part(model, "DockCoil", Vector3.new(0.45, 3.1 - i * 0.12, 3.1 - i * 0.12), base * CFrame.new(0, y, 0) * up, steel, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	for _, s in { 1, -1 } do
		part(model, "DockStrut", Vector3.new(0.4, 6, 0.4), base * CFrame.new(s * 1.9, 3.8, 0) * CFrame.Angles(0, 0, s * 0.18), brass, Enum.Material.SmoothPlastic)
	end
	part(model, "DockCrown", Vector3.new(0.6, 3.2, 3.2), base * CFrame.new(0, 14.2, 0) * up, brass, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local emitter = part(model, "DockEmitter", Vector3.new(1.8, 1.8, 1.8), base * CFrame.new(0, EMITTER_HEIGHT, 0), TitanConfig.getVariant(nil).palette.glow, Enum.Material.Neon, Enum.PartType.Ball)
	local a = Instance.new("Attachment")
	a.Name = "Arc"
	a.Parent = emitter
	local light = Instance.new("PointLight")
	light.Color = emitter.Color
	light.Range = 12
	light.Brightness = 1.4
	light.Parent = emitter
	CollectionService:AddTag(emitter, TitanDock.Tag)
	model.PrimaryPart = foot
	model.Parent = parent
	return model
end

function TitanDock.terminal(model: Model): Attachment?
	local a = model:FindFirstChild("BatteryTerminal", true)
	if a and a:IsA("BasePart") then
		a = a:FindFirstChild("BatteryTerminal")
	end
	return if a and a:IsA("Attachment") then a else nil
end

-- Server (MechBattery): the arc breaks past Reach; it reconnects once the
-- mech is down (Off, or PoweringDown past ReplugAt) near its home spot.
function TitanDock.updatePlug(model: Model, root: BasePart)
	local home = model:GetAttribute("Home")
	local term = TitanDock.terminal(model)
	if typeof(home) ~= "CFrame" or not term then
		return
	end
	local over = (term.WorldPosition - TitanDock.emitterPosition(home)).Magnitude > DOCK.Reach
	local plugged = model:GetAttribute("Plugged") == true
	if plugged then
		if over then
			model:SetAttribute("Plugged", false)
		end
		return
	end
	if over then
		return
	end
	local state = model:GetAttribute("PowerState")
	local t0 = model:GetAttribute("PowerTime")
	local t = if typeof(t0) == "number" then workspace:GetServerTimeNow() - t0 else math.huge
	local d = root.Position - home.Position
	if Vector3.new(d.X, 0, d.Z).Magnitude <= DOCK.PlugRange and (state == "Off" or (state == "PoweringDown" and t >= DOCK.ReplugAt)) then
		model:SetAttribute("Plugged", true)
	end
end

return TitanDock
