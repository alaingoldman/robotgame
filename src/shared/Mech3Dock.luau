--!strict
-- SRF-03 charging post (Mech3Config.Dock), after the CRM-01's. A charcoal
-- and navy post stands behind-right of the pad; while the mech is parked at
-- home a blue arc runs from its emitter to the battery terminal on top of the
-- backpack (Mech3Animator draws it) and the battery charges. Walking off past Reach breaks the arc;
-- it re-connects once the mech has crouched again after an exit (ReplugAt)
-- near its home spot.
--
--   Mech3Dock.buildDock(home, parent)   the post (server pads, edit preview)
--   Mech3Dock.emitterPosition(home)     where the arc starts
--   Mech3Dock.terminal(model)           the battery terminal Attachment
--   Mech3Dock.updatePlug(model, root)   MechBattery hook: sets "Plugged"

local CollectionService = game:GetService("CollectionService")

local Mech3Config = require(script.Parent.Mech3Config)

local Mech3Dock = {}

local DOCK = Mech3Config.Dock
Mech3Dock.Tag = "Mech3Dock"
Mech3Dock.ChargeRate = DOCK.ChargeRate

function Mech3Dock.dockCFrame(home: CFrame): CFrame
	return home * CFrame.new(DOCK.Offset)
end

function Mech3Dock.emitterPosition(home: CFrame): Vector3
	return (Mech3Dock.dockCFrame(home) * CFrame.new(0, DOCK.EmitterHeight, 0)).Position
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

function Mech3Dock.buildDock(home: CFrame, parent: Instance): Model
	local pal = Mech3Config.getVariant(nil).palette
	local model = Instance.new("Model")
	model.Name = "Mech3Dock"
	local base = Mech3Dock.dockCFrame(home)
	local top = DOCK.EmitterHeight
	local up = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y
	local foot = part(model, "DockBase", Vector3.new(4.6, 0.8, 4.6), base * CFrame.new(0, 0.4, 0), pal.dark, Enum.Material.Metal)
	foot.CanCollide = true
	part(model, "DockPlinth", Vector3.new(3.4, 0.7, 3.4), base * CFrame.new(0, 1.15, 0), pal.trim, Enum.Material.Metal)
	-- charcoal mast with a blue channel up the front, steel-blue collars, navy head
	local mastH = top - 2.6
	local mast = part(model, "DockMast", Vector3.new(1.6, mastH, 1.6), base * CFrame.new(0, 1.5 + mastH / 2, 0), pal.dark, Enum.Material.Metal)
	mast.CanCollide = true
	part(model, "DockChannel", Vector3.new(0.6, mastH - 1.2, 0.12), base * CFrame.new(0, 1.5 + mastH / 2, -0.84), pal.glow, Enum.Material.Neon)
	for i, y in { 3.0, 1.5 + mastH * 0.55, 1.5 + mastH - 0.3 } do
		part(model, "DockCollar" .. i, Vector3.new(0.45, 2.1, 2.1), base * CFrame.new(0, y, 0) * up, pal.trim, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	-- emitter arm leaning toward the mech, ending in a glowing ball
	part(model, "DockHead", Vector3.new(2.0, 0.9, 2.0), base * CFrame.new(0, top - 1.1, 0), pal.main, Enum.Material.SmoothPlastic)
	part(model, "DockFin", Vector3.new(0.3, 1.6, 1.4), base * CFrame.new(0, top - 0.2, 0.3) * CFrame.Angles(-0.35, 0, 0), pal.trim, Enum.Material.Metal)
	local emitter = part(model, "DockEmitter", Vector3.new(1.1, 1.1, 1.1), base * CFrame.new(0, top, 0), pal.glow, Enum.Material.Neon, Enum.PartType.Ball)
	local a = Instance.new("Attachment")
	a.Name = "Arc"
	a.Parent = emitter
	local light = Instance.new("PointLight")
	light.Color = emitter.Color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = emitter
	CollectionService:AddTag(emitter, Mech3Dock.Tag)
	model.PrimaryPart = foot
	model.Parent = parent
	return model
end

function Mech3Dock.terminal(model: Model): Attachment?
	local a = model:FindFirstChild("BatteryTerminal", true)
	if a and a:IsA("BasePart") then
		a = a:FindFirstChild("BatteryTerminal")
	end
	return if a and a:IsA("Attachment") then a else nil
end

-- Server (MechBattery): the arc breaks past Reach; it reconnects once the
-- mech is down (Off, or PoweringDown past ReplugAt) near its home spot.
function Mech3Dock.updatePlug(model: Model, root: BasePart)
	local home = model:GetAttribute("Home")
	local term = Mech3Dock.terminal(model)
	if typeof(home) ~= "CFrame" or not term then
		return
	end
	local over = (term.WorldPosition - Mech3Dock.emitterPosition(home)).Magnitude > DOCK.Reach
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

return Mech3Dock
