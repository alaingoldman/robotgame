--!strict
-- Registry of hittable things (junk piles, timed crates). Each target is a
-- Model with an anchored, invisible "Root" part at its centre; attributes
-- HP / MaxHP / TargetKind / Radius replicate to clients (HP bars, HUD), and
-- the CollectionService tag "CoreTarget" lets clients find them.

local CollectionService = game:GetService("CollectionService")

local Targets = {}

Targets.Tag = "CoreTarget"

export type Spec = {
	hp: number,
	kind: string,
	radius: number,
	onBreak: (model: Model, killer: Player?, damageBy: { [Player]: number }) -> (),
}
type Entry = { model: Model, root: BasePart, spec: Spec, hp: number, damageBy: { [Player]: number }, dead: boolean }

local entries: { [Model]: Entry } = {}

local function hpBar(model: Model, root: BasePart, radius: number)
	local g = Instance.new("BillboardGui")
	g.Name = "HpBar"
	g.Size = UDim2.fromOffset(110, 12)
	g.StudsOffsetWorldSpace = Vector3.new(0, radius + 1.6, 0)
	g.MaxDistance = 90
	g.Enabled = false
	g.AlwaysOnTop = true
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = bg
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 196, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 4)
	c2.Parent = fill
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Thickness = 1.5
	s.Parent = bg
	g.Adornee = root
	g.Parent = model
end

function Targets.register(model: Model, root: BasePart, spec: Spec)
	entries[model] = { model = model, root = root, spec = spec, hp = spec.hp, damageBy = {}, dead = false }
	model:SetAttribute("HP", spec.hp)
	model:SetAttribute("MaxHP", spec.hp)
	model:SetAttribute("TargetKind", spec.kind)
	model:SetAttribute("Radius", spec.radius)
	if spec.kind ~= "Crate" then
		hpBar(model, root, spec.radius)
	end
	CollectionService:AddTag(model, Targets.Tag)
	model.Destroying:Connect(function()
		entries[model] = nil
	end)
end

function Targets.unregister(model: Model)
	entries[model] = nil
end

function Targets.all(): { [Model]: Entry }
	return entries
end

function Targets.entry(model: Model): Entry?
	return entries[model]
end

-- Applies damage; returns (dealt, killed).
function Targets.damage(model: Model, amount: number, player: Player?): (number, boolean)
	local e = entries[model]
	if not e or e.dead then
		return 0, false
	end
	local dealt = math.min(amount, e.hp)
	e.hp -= dealt
	if player then
		e.damageBy[player] = (e.damageBy[player] or 0) + dealt
	end
	model:SetAttribute("HP", math.max(0, math.floor(e.hp + 0.5)))
	local bar = model:FindFirstChild("HpBar")
	if bar and bar:IsA("BillboardGui") then
		bar.Enabled = true
		local fill = bar:FindFirstChild("Bg") and (bar :: any).Bg:FindFirstChild("Fill")
		if fill then
			fill.Size = UDim2.fromScale(math.clamp(e.hp / e.spec.hp, 0, 1), 1)
		end
	end
	if e.hp <= 0 then
		e.dead = true
		entries[model] = nil
		task.spawn(e.spec.onBreak, model, player, e.damageBy)
		return dealt, true
	end
	return dealt, false
end

function Targets.isAlive(model: Model): boolean
	local e = entries[model]
	return e ~= nil and not e.dead
end

return Targets
