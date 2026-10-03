--!strict
-- Player BASES: the Scrapyard.Bases.Plot<i> pads. One plot per player on
-- join (the lowest free one; with more players than plots, plots are
-- shared). The owner's name goes on the sign; prompts: EQUIP STATION and
-- PART LOCKER (open the locker UI), CHARGER (scrap -> +battery). Standing on
-- your own pad: InBase = true (fast charging, see State) and any carried
-- cargo is delivered at once. Respawns put you on your pad
-- (CoreLoopConfig.Bases.SpawnAtBase).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Loot = require(script.Parent.Loot)

local Bases = {}

type Plot = { index: number, model: Model, pad: BasePart, owners: { Player } }
local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}

local function signText(plot: Plot)
	local sign = plot.model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("Gui")
	local label = gui and gui:FindFirstChild("Owner")
	if label and label:IsA("TextLabel") then
		if #plot.owners == 0 then
			label.Text = "FREE PLOT"
		else
			local names = {}
			for _, p in plot.owners do
				table.insert(names, string.upper(p.DisplayName))
			end
			label.Text = table.concat(names, " + ") .. (if #names == 1 then "'S BASE" else "")
		end
	end
end

local function assign(player: Player)
	if byPlayer[player] or #plots == 0 then
		return
	end
	local best: Plot? = nil
	for _, p in plots do
		if not best or #p.owners < #best.owners then
			best = p
		end
	end
	if best then
		table.insert(best.owners, player)
		byPlayer[player] = best
		player:SetAttribute("PlotIndex", best.index)
		signText(best)
	end
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	local i = table.find(plot.owners, player)
	if i then
		table.remove(plot.owners, i)
	end
	signText(plot)
end

function Bases.plotOf(player: Player): Plot?
	return byPlayer[player]
end

local function prompt(anchor: Instance?, action: string, object: string, onTrigger: (Player) -> ())
	if not (anchor and anchor:IsA("BasePart")) then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = anchor
	p.Triggered:Connect(onTrigger)
end

local function inside(plot: Plot, pos: Vector3): boolean
	local rel = plot.pad.CFrame:PointToObjectSpace(pos)
	local half = plot.pad.Size / 2
	return math.abs(rel.X) <= half.X + 1 and math.abs(rel.Z) <= half.Z + 1 and rel.Y > -2 and rel.Y < 14
end

local acc = 0
local function step(dt: number)
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	for _, player in Players:GetPlayers() do
		local st = State.get(player)
		local plot = byPlayer[player]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local now = false
		if st and plot and root and hum and hum.Health > 0 then
			now = inside(plot, root.Position)
		end
		if st then
			if now ~= st.inBase then
				st.inBase = now
				player:SetAttribute("InBase", now)
			end
			if now and st.cargo and plot then
				local dz = plot.model:FindFirstChild("DropZone")
				Loot.deliver(player, if dz and dz:IsA("BasePart") then dz.Position else plot.pad.Position)
			end
		end
	end
end

local function spawnAtBase(player: Player, char: Model)
	if not CoreLoopConfig.Bases.SpawnAtBase then
		return
	end
	local plot = byPlayer[player]
	local sp = plot and plot.model:FindFirstChild("SpawnPoint")
	if not (sp and sp:IsA("BasePart")) then
		return
	end
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root or player.Character ~= char then
		return
	end
	task.wait() -- after the default spawn placement
	local jitter = Vector3.new(math.random(-4, 4), 0, math.random(-3, 3))
	char:PivotTo(sp.CFrame + jitter)
end

function Bases.start(yard: Folder)
	local folder = yard:FindFirstChild("Bases")
	if folder then
		for _, m in folder:GetChildren() do
			local pad = m:FindFirstChild("Pad")
			if m:IsA("Model") and pad and pad:IsA("BasePart") then
				table.insert(plots, { index = (m:GetAttribute("PlotIndex") :: number?) or #plots + 1, model = m, pad = pad, owners = {} })
			end
		end
	end
	table.sort(plots, function(a, b)
		return a.index < b.index
	end)
	if #plots == 0 then
		warn("[CoreLoop] no base plots in", yard:GetFullName())
	end
	for _, plot in plots do
		local function owns(player: Player): boolean
			if byPlayer[player] == plot then
				return true
			end
			State.toast(player, "notyours", "That's not your base!", Color3.fromRGB(255, 90, 70))
			return false
		end
		local eq = plot.model:FindFirstChild("EquipStation")
		prompt(eq and eq:FindFirstChild("PromptAnchor"), "Equip Parts", "Equip Station", function(player)
			if owns(player) then
				State.send(player)
				Remotes.get("OpenLocker"):FireClient(player)
			end
		end)
		local lk = plot.model:FindFirstChild("Locker")
		prompt(lk and lk:FindFirstChild("PromptAnchor"), "Open", "Part Locker", function(player)
			if owns(player) then
				State.send(player)
				Remotes.get("OpenLocker"):FireClient(player)
			end
		end)
		local ch = plot.model:FindFirstChild("Charger")
		prompt(ch and ch:FindFirstChild("PromptAnchor"), "Upgrade Battery", "Charger", function(player)
			if owns(player) then
				State.buyBattery(player)
			end
		end)
	end
	local function join(player: Player)
		assign(player)
		player.CharacterAdded:Connect(function(char)
			spawnAtBase(player, char)
		end)
		if player.Character then
			task.spawn(spawnAtBase, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(join)
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerRemoving:Connect(release)
	RunService.Heartbeat:Connect(step)
	-- RETURN (dead battery): straight to your own pad, where it charges fast;
	-- carried cargo still on its timer is delivered there by step()
	Remotes.get("Locker").OnServerEvent:Connect(function(player, action)
		if action ~= "Return" or player:GetAttribute("BatteryDead") ~= true then
			return
		end
		Bases.returnHome(player)
	end)
end

function Bases.returnHome(player: Player): boolean
	local plot = byPlayer[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (plot and char and hum and hum.Health > 0) then
		return false
	end
	local sp = plot.model:FindFirstChild("SpawnPoint")
	local cf = if sp and sp:IsA("BasePart") then sp.CFrame else plot.pad.CFrame + Vector3.new(0, 3, 0)
	if hum.SeatPart then
		hum.Sit = false
	end
	char:PivotTo(cf + Vector3.new(math.random(-3, 3), 0, math.random(-2, 2)))
	Remotes.fx(player, "Install", {})
	Remotes.toast(player, "RETURNED TO BASE - recharging...", Color3.fromRGB(90, 255, 140))
	return true
end

return Bases
