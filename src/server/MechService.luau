--!strict
-- Spawns the mech lineup and handles entering, exiting and armor swaps.
--
-- The pilot's avatar stays their Character the whole time. Boarding seats it
-- in the cockpit's PilotSeat (massless, in the non-colliding "Pilot" group);
-- once the doors are shut the mech (a plain Humanoid NPC) is unanchored and
-- handed to the pilot's client, which drives it (see PilotController).
-- Player.Character never changes, so nothing is re-streamed on the way out.
--
-- Boarding and exiting are timed sequences (MechConfig.Boarding / Exit). The
-- server owns the state ("PowerState" + "PowerTime" attributes on the mech)
-- and seats / unseats the pilot; clients render the poses, walk their own
-- character up / down the ramp, and run camera and sounds.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechBuilder = require(Shared:WaitForChild("MechBuilder"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechCord = require(Shared:WaitForChild("MechCord"))
local MechPattern = require(Shared:WaitForChild("MechPattern"))
local MechPose = require(Shared:WaitForChild("MechPose"))

local MechService = {}

local S = MechBuilder.Scale
local LINEUP_Z = -46
local LINEUP_SPACING = 36
local BACK_ROW_Z = -92
local PAD_SIZE = 28
local RESPAWN_DELAY = 3
local ENTER_DISTANCE = 24 -- from the foot of the ramp
local ROOT_HEIGHT = MechBuilder.RootHeight -- root center above ground

local B, X = MechConfig.Boarding, MechConfig.Exit

local remotes: Folder
local pilotChanged: RemoteEvent

-- A player in (or boarding) a mech.
type Pilot = {
	model: Model,
	char: Model,
	hum: Humanoid,
	massless: { [BasePart]: boolean }, -- original Massless of the strapped-in parts
	conns: { RBXScriptConnection },
}
local pilots: { [Player]: Pilot } = {}
-- the running board/exit sequence per mech; replacing it cancels the old one
local sequences: { [Model]: {} } = {}
local mechFolder: Folder

-- One parking spot in the lineup. Each spot respawns its own mech.
type SpawnSpec = {
	key: string, -- unique per spot, used in pad names
	variantId: string,
	home: CFrame, -- on the ground, facing the way the mech should face
	pattern: string?, -- MechPattern name, nil for plain armor
	offPose: string?, -- powered-down pose style (MechBuilder.OffStyles), nil = "Kneel"
}

-- Ground-level CFrame at x, z facing the spawn point (+Z).
local function facingSpawn(x: number, z: number): CFrame
	return CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
end

local function buildSpecs(): { SpawnSpec }
	local specs: { SpawnSpec } = {}
	-- four colors, each twice: plain in the front row, crosshatch right behind it
	local half = LINEUP_SPACING / 2
	local columns = { { "Desert", -3 * half }, { "Olive", -half }, { "Arctic", half }, { "Navy", 3 * half } }
	-- experiment: the olive pair takes a knee instead of the deep kneel
	local offPoses: { [string]: string } = { Olive = "OneKnee" }
	for _, col in columns do
		local id, x = col[1] :: string, col[2] :: number
		table.insert(specs, {
			key = id,
			variantId = id,
			home = facingSpawn(x, LINEUP_Z),
			offPose = offPoses[id],
		})
		table.insert(specs, {
			key = id .. "_Hatch",
			variantId = id,
			home = facingSpawn(x, BACK_ROW_Z),
			pattern = "Crosshatch",
			offPose = offPoses[id],
		})
	end
	return specs
end

local specs: { SpawnSpec } = {}

local function buildPad(spec: SpawnSpec)
	local variant = MechConfig.getVariant(spec.variantId)
	local base = spec.home
	local pad = Instance.new("Part")
	pad.Name = "MechPad_" .. spec.key
	pad.Anchored = true
	pad.Size = Vector3.new(PAD_SIZE, 0.3, PAD_SIZE)
	pad.CFrame = base * CFrame.new(0, 0.15, 0)
	pad.Color = Color3.fromRGB(52, 54, 58)
	pad.Material = Enum.Material.DiamondPlate
	pad.Parent = mechFolder

	for _, z in { -(PAD_SIZE / 2 - 0.4), PAD_SIZE / 2 - 0.4 } do
		local stripe = Instance.new("Part")
		stripe.Name = "PadStripe"
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.Size = Vector3.new(PAD_SIZE, 0.32, 0.8)
		stripe.CFrame = base * CFrame.new(0, 0.16, z)
		stripe.Color = variant.palette.accent
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Parent = pad
	end
	-- the charging box the mech's power cord runs to
	MechCord.buildOutlet(base, pad)
end

local function setIdleVisuals(model: Model, idle: boolean)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
	local sign = root:FindFirstChildOfClass("BillboardGui")
	if prompt then
		prompt.Enabled = idle
	end
	if sign then
		sign.Enabled = idle
	end
end

-- Collision groups: mech armor is solid to on-foot players (they can climb
-- and stand on mechs, and walk into the cockpit) but ignores the world,
-- other armor and mech roots, so it never drags or snags a walking mech.
-- The invisible root box collides with the world and other roots only. A
-- seated pilot collides with nothing, so it can't push its own mech around.
local function setupCollisionGroups()
	local armor, root, players, pilot = MechBuilder.ArmorGroup, MechBuilder.RootGroup, MechBuilder.PlayerGroup, MechBuilder.PilotGroup
	for _, name in { armor, root, players, pilot } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(armor, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(armor, armor, false)
	PhysicsService:CollisionGroupSetCollidable(armor, root, false)
	PhysicsService:CollisionGroupSetCollidable(armor, players, true)
	PhysicsService:CollisionGroupSetCollidable(root, players, false)
	for _, other in { "Default", armor, root, players, pilot } do
		PhysicsService:CollisionGroupSetCollidable(pilot, other, false)
	end
	-- power cords lie on the world only: nothing trips on them
	local cord = MechCord.Group
	if not PhysicsService:IsCollisionGroupRegistered(cord) then
		PhysicsService:RegisterCollisionGroup(cord)
	end
	for _, other in { cord, armor, root, players, pilot } do
		PhysicsService:CollisionGroupSetCollidable(cord, other, false)
	end
end

-- The group a character's parts belong in: "Pilot" while strapped into a seat.
local function characterGroup(char: Model): string
	return if char:GetAttribute("Strapped") then MechBuilder.PilotGroup else MechBuilder.PlayerGroup
end

-- Puts every part of a character in its group, including parts added later.
local function trackCharacter(char: Model)
	local function tag(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = characterGroup(char)
		end
	end
	for _, d in char:GetDescendants() do
		tag(d)
	end
	char.DescendantAdded:Connect(tag)
end

-- Straps a seated pilot in: weightless (so it doesn't load the mech) and
-- non-colliding (so it never fights its own cockpit).
local function strap(p: Pilot)
	p.char:SetAttribute("Strapped", true)
	for _, d in p.char:GetDescendants() do
		if d:IsA("BasePart") then
			if p.massless[d] == nil then
				p.massless[d] = d.Massless
			end
			d.Massless = true
			d.CollisionGroup = MechBuilder.PilotGroup
		end
	end
end

local function unstrap(p: Pilot)
	p.char:SetAttribute("Strapped", nil)
	for part, was in p.massless do
		if part.Parent then
			part.Massless = was
		end
	end
	table.clear(p.massless)
	for _, d in p.char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = MechBuilder.PlayerGroup
		end
	end
end

local spawnMech: (specIndex: number) -> ()

local function setPower(model: Model, state: string)
	model:SetAttribute("PowerState", state)
	model:SetAttribute("PowerTime", workspace:GetServerTimeNow())
end

-- Height of the ground under a point, ignoring the given model.
local function groundY(model: Model, pos: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else 0
end

-- Humanoid states that make a tall mech topple over.
local function disableFalls(humanoid: Humanoid)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
end

local function seatOf(model: Model): Seat?
	return model:FindFirstChild("PilotSeat", true) :: Seat?
end

-- Frees whoever sits in the pilot seat.
local function unseat(model: Model, humanoid: Humanoid?)
	local seat = seatOf(model)
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	if humanoid and humanoid.Parent then
		humanoid.Sit = false
	end
end

-- Puts an unpiloted mech back into the squatting, ramp-down idle state.
local function resetToOff(model: Model)
	sequences[model] = nil
	model:SetAttribute("PilotId", nil)
	model:SetAttribute("BoardWalk", nil)
	setPower(model, "Off")
	setIdleVisuals(model, true)
end

local function park(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
	if not root.Anchored then
		-- automatic, not the server: a pilot unseated later must go back to
		-- its own player's physics
		root:SetNetworkOwnershipAuto()
	end
	-- stand upright on the ground where it stopped
	local _, yaw, _ = root.CFrame:ToOrientation()
	local pos = root.Position
	local y = groundY(model, pos) + ROOT_HEIGHT
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	root.CFrame = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, yaw, 0)
end

-- Ends a pilot's time in its mech right away (died, left, respawned, mech
-- destroyed): the mech is parked and, if `resetMech`, put back to sleep.
local function dropPilot(player: Player, resetMech: boolean)
	local p = pilots[player]
	if not p then
		return
	end
	pilots[player] = nil
	for _, c in p.conns do
		c:Disconnect()
	end
	local model = p.model
	sequences[model] = nil
	if model.Parent then
		park(model)
	end
	unseat(model, p.hum)
	unstrap(p)
	if resetMech then
		resetToOff(model)
	end
	if player.Parent then
		pilotChanged:FireClient(player, nil)
	end
end

-- Waits until `t` seconds into the mech's current power state, so yields
-- along the way don't push the timeline back.
local function waitUntil(model: Model, t: number)
	local t0 = model:GetAttribute("PowerTime")
	if typeof(t0) == "number" then
		task.wait(math.max(0, t0 + t - workspace:GetServerTimeNow()))
	end
end

-- Seconds a pilot at `from` gets to walk up the ramp to the seat. Clients
-- speed the walk up to fit (or glide the rest of a long route).
local function walkTime(model: Model, from: Vector3): number
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local style = MechPose.style(model)
	local len = MechBuilder.pathLength(from, MechBuilder.boardPath(root.CFrame, from, style))
	if style == "OneKnee" then
		-- walk to the foot of the raised ramp, climb it, walk up it
		local C = MechConfig.Climb
		return math.clamp(len / MechConfig.BoardWalkSpeed, C.ApproachMin, C.ApproachMax) + C.Climb + C.RampWalk
	end
	return math.clamp(len / MechConfig.BoardWalkSpeed, MechConfig.BoardWalkMin, MechConfig.BoardWalkMax)
end

-- Boarding: the pilot walks up the ramp, turns and sits; the doors close
-- around them and the mech stands up, then the pilot gets the controls.
local function boardSequence(player: Player, p: Pilot, token: {})
	local model = p.model
	local function valid(): boolean
		return sequences[model] == token and pilots[player] == p and model.Parent ~= nil
	end

	-- the client walks the character up the ramp and turns it round
	local walk = MechPose.boardWalk(model)
	waitUntil(model, walk + B.Sit)
	if not valid() then
		return
	end
	local seat = seatOf(model)
	if seat then
		seat:Sit(p.hum)
	end
	if not (seat and (seat.Occupant == p.hum or seat:FindFirstChild("SeatWeld"))) then
		dropPilot(player, true)
		return
	end
	strap(p)

	waitUntil(model, walk + B.Online)
	if not valid() then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	sequences[model] = nil
	root.Anchored = false
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
	-- the pilot's client runs the mech's humanoid (and the seated avatar with it)
	root:SetNetworkOwner(player)
	setPower(model, "Online")
	pilotChanged:FireClient(player, model, "Online")
end

local function enter(player: Player, model: Model)
	if pilots[player] or model:GetAttribute("PilotId") or model:GetAttribute("PowerState") ~= "Off" then
		return
	end
	local mechHum = model:FindFirstChildOfClass("Humanoid")
	if not mechHum or mechHum.Health <= 0 then
		return
	end
	local char = player.Character
	local charRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and charRoot and hum and hum.Health > 0) or hum.Sit then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local foot = MechBuilder.offPoints(root.CFrame, MechPose.style(model)).foot
	if ((charRoot.Position - foot) * Vector3.new(1, 0, 1)).Magnitude > ENTER_DISTANCE then
		return
	end

	local p: Pilot = { model = model, char = char, hum = hum, massless = {}, conns = {} }
	pilots[player] = p
	-- losing the avatar (death, reset, respawn) parks the mech again
	local function lost()
		dropPilot(player, true)
	end
	table.insert(p.conns, hum.Died:Connect(lost))
	table.insert(p.conns, player.CharacterRemoving:Connect(lost))
	model:SetAttribute("PilotId", player.UserId)
	model:SetAttribute("BoardWalk", walkTime(model, charRoot.Position))
	setIdleVisuals(model, false)
	setPower(model, "Boarding")
	local token = {}
	sequences[model] = token
	pilotChanged:FireClient(player, model, "Boarding")
	task.spawn(boardSequence, player, p, token)
end

-- Exit: the mech kneels with the doors shut, the doors and ramp open on the
-- seated pilot, who unbuckles and walks out.
local function exit(player: Player)
	local p = pilots[player]
	if not p or p.model:GetAttribute("PowerState") ~= "Online" then
		return
	end
	local model = p.model
	local token = {}
	sequences[model] = token
	park(model)
	setPower(model, "PoweringDown")
	pilotChanged:FireClient(player, model, "PoweringDown")

	-- kneel, doors open (see MechPose.powerTargets), then stand up
	waitUntil(model, X.Reveal + X.Stand)
	if sequences[model] ~= token or pilots[player] ~= p then
		return
	end
	pilots[player] = nil
	for _, c in p.conns do
		c:Disconnect()
	end
	unseat(model, p.hum)
	unstrap(p)
	-- the client walks the character down the ramp
	pilotChanged:FireClient(player, model, "Exiting")

	waitUntil(model, X.Reveal + X.Off)
	if sequences[model] == token then
		resetToOff(model)
	end
	-- back on foot (also if the mech was destroyed meanwhile)
	if player.Parent and pilots[player] == nil then
		pilotChanged:FireClient(player, nil)
	end
end

local function equip(player: Player, slot: unknown, variantId: unknown)
	local p = pilots[player]
	if not p or typeof(slot) ~= "string" or typeof(variantId) ~= "string" then
		return
	end
	local model = p.model
	if model:GetAttribute("PowerState") ~= "Online" then
		return
	end
	if not table.find(MechConfig.Slots, slot) then
		return
	end
	if MechConfig.getVariant(variantId).id ~= variantId then
		return
	end
	-- the pilot seat lives outside the armor folders, so the pilot stays put
	MechBuilder.applySlot(model, slot, variantId)
	-- the rebuilt slot comes back plain
	local pattern = model:GetAttribute("Pattern")
	MechPattern.apply(model, if typeof(pattern) == "string" then pattern else nil)
end

function spawnMech(specIndex: number)
	local spec = specs[specIndex]
	local variant = MechConfig.getVariant(spec.variantId)
	local suffix = if spec.pattern then " (Hatch)" else ""
	local model = MechBuilder.buildMech("HWM-04B " .. variant.displayName .. suffix, {
		Helmet = variant.id,
		Chest = variant.id,
		Legs = variant.id,
	})
	MechPattern.apply(model, spec.pattern)
	MechCord.buildSocket(model)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("HomeIndex", specIndex)
	model:SetAttribute("OffPose", spec.offPose)
	-- battery + power cord (see MechBattery): spawns full and plugged in at home
	model:SetAttribute("Home", spec.home)
	model:SetAttribute("Charge", 100)
	model:SetAttribute("Plugged", true)
	setPower(model, "Off")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	model:PivotTo(spec.home * CFrame.new(0, ROOT_HEIGHT, 0))

	-- the prompt sits at the foot of the ramp, where the pilot walks in
	local boardPoint = Instance.new("Attachment")
	boardPoint.Name = "BoardPoint"
	boardPoint.Parent = root
	boardPoint.WorldPosition = MechBuilder.offPoints(root.CFrame, spec.offPose).foot + Vector3.new(0, 3, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pilot"
	prompt.ObjectText = model.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.Parent = boardPoint
	prompt.Triggered:Connect(function(player)
		enter(player, model)
	end)

	local sign = Instance.new("BillboardGui")
	-- sized in studs so distant signs shrink instead of piling up on each other
	sign.Size = UDim2.fromScale(7 * S, 0.9 * S)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 7 * S, 0)
	sign.MaxDistance = 110
	sign.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "HWM-04B  //  " .. string.upper(variant.displayName) .. (if spec.pattern then "  //  CROSSHATCH" else "")
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = sign
	sign.Parent = root

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	disableFalls(humanoid)
	humanoid.Died:Connect(function()
		sequences[model] = nil
		for player, p in pilots do
			if p.model == model then
				-- the pilot goes down with the mech and respawns as usual
				local hum = p.hum
				dropPilot(player, false)
				if hum.Parent and hum.Health > 0 then
					hum.Health = 0
				end
			end
		end
		setIdleVisuals(model, false)
		-- clear the wreck so the pad respawns a fresh mech
		task.delay(RESPAWN_DELAY, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)
	-- the Humanoid doesn't need a neck, so losing the root (e.g. falling off
	-- the world) wouldn't kill it on its own
	root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(model) and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)

	local replaced = false
	model.AncestryChanged:Connect(function()
		if replaced or model:IsDescendantOf(workspace) then
			return
		end
		replaced = true
		task.delay(RESPAWN_DELAY, spawnMech, specIndex)
	end)

	CollectionService:AddTag(model, "Mech")
	model.Parent = mechFolder
end

-- Moves every part to where its joints put it, then anchors it, so a posed
-- mech holds still in edit mode (where joints aren't simulated).
local function bakePose(model: Model)
	local motors: { Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			table.insert(motors, d)
		end
	end
	-- parents are solved before children after as many passes as the rig is deep
	for _ = 1, 12 do
		for _, m in motors do
			local p0, p1 = m.Part0, m.Part1
			if p0 and p1 then
				p1.CFrame = p0.CFrame * m.C0 * m.Transform * m.C1:Inverse()
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Part0 and d.Part1 then
			d.Part1.CFrame = d.Part0.CFrame * d.C0 * d.C1:Inverse()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

-- Builds the lineup (pads + kneeling mechs) as a static Workspace.MechsPreview
-- folder so the mechs can be seen in Studio's edit mode. The server deletes it
-- on start and spawns the real mechs. Run from the command bar / MCP:
--   require(game.ServerScriptService.Server.MechService).buildPreview()
function MechService.buildPreview(): Folder
	local old = workspace:FindFirstChild("MechsPreview")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "MechsPreview"
	mechFolder = folder
	local cords: { { model: Model, home: CFrame, key: string } } = {}
	for _, spec in buildSpecs() do
		buildPad(spec)
		local variant = MechConfig.getVariant(spec.variantId)
		local model = MechBuilder.buildMech("Preview " .. spec.key, {
			Helmet = variant.id,
			Chest = variant.id,
			Legs = variant.id,
		})
		MechPattern.apply(model, spec.pattern)
		MechCord.buildSocket(model)
		model:SetAttribute("OffPose", spec.offPose)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Destroy()
		end
		model:PivotTo(spec.home * CFrame.new(0, ROOT_HEIGHT, 0))
		MechPose.applyOff(MechPose.motors(model), spec.offPose)
		bakePose(model)
		model.Parent = folder
		table.insert(cords, { model = model, home = spec.home, key = spec.key })
	end
	folder.Parent = workspace
	-- plugged-in cords in their hanging pose (anchored, no physics)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local exclude: { Instance } = {}
	for _, c in cords do
		table.insert(exclude, c.model)
	end
	params.FilterDescendantsInstances = exclude
	local function floorAt(p: Vector3): number
		local hit = workspace:Raycast(Vector3.new(p.X, 30, p.Z), Vector3.new(0, -60, 0), params)
		return if hit then hit.Position.Y else 0
	end
	for _, c in cords do
		local plug = MechCord.plugPoint(c.model)
		if plug then
			local count = MechCord.segmentCount()
			local cord = MechCord.buildCord("PowerCord", count, c.model)
			MechCord.place(cord, MechCord.layout(plug.WorldCFrame, MechCord.outletPort(c.home), count, floorAt), true)
			for _, d in cord.folder:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			-- plugged in and charging: the socket glows green
			local socket = c.model:FindFirstChild("PowerSocket")
			local glow = socket and socket:FindFirstChild("Glow")
			if glow and glow:IsA("BasePart") then
				glow.Color = MechCord.GlowOn
				local light = glow:FindFirstChildOfClass("PointLight")
				if light then
					light.Brightness = 1.1
				end
			end
		end
	end
	return folder
end

function MechService.start()
	-- the edit-mode preview is only for looking at; the real mechs spawn below
	local preview = workspace:FindFirstChild("MechsPreview")
	if preview then
		preview:Destroy()
	end
	MechPattern.ensureVariants()
	setupCollisionGroups()
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(trackCharacter)
		if player.Character then
			trackCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	remotes = Instance.new("Folder")
	remotes.Name = "MechRemotes"
	for _, name in { "PilotChanged", "ExitMech", "EquipPiece" } do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = remotes
	end
	pilotChanged = remotes:FindFirstChild("PilotChanged") :: RemoteEvent
	remotes.Parent = ReplicatedStorage

	mechFolder = Instance.new("Folder")
	mechFolder.Name = "Mechs"
	mechFolder.Parent = workspace

	local exitEvent = remotes:FindFirstChild("ExitMech") :: RemoteEvent
	local equipEvent = remotes:FindFirstChild("EquipPiece") :: RemoteEvent
	exitEvent.OnServerEvent:Connect(function(player)
		exit(player)
	end)
	equipEvent.OnServerEvent:Connect(equip)

	Players.PlayerRemoving:Connect(function(player)
		dropPilot(player, true)
	end)

	-- Mirror the kneel, doors and ramp on the server's copy of each mech (clients
	-- animate their own and Transform doesn't replicate), so seats and ramps
	-- sit where the clients see them.
	local motorCache: { [Model]: { [string]: Motor6D } } = {}
	RunService.PreSimulation:Connect(function()
		for _, inst in CollectionService:GetTagged("Mech") do
			if not inst:IsA("Model") or not inst.Parent then
				continue
			end
			local model = inst :: Model
			local motors = motorCache[model]
			if not motors then
				motors = MechPose.motors(model)
				motorCache[model] = motors
				model.Destroying:Connect(function()
					motorCache[model] = nil
				end)
			end
			local crouch, doors, ramp = MechPose.powerTargets(model)
			MechPose.applyStatic(motors, crouch, doors, ramp, MechPose.style(model))
		end
	end)

	-- charge, drain and when the cord is plugged in
	require(script.Parent.MechBattery).start()

	specs = buildSpecs()
	for i, spec in specs do
		buildPad(spec)
		spawnMech(i)
	end
end

return MechService
