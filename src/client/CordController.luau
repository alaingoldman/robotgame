--!strict
-- Every mech's power cord, run locally on each client (see MechCord for the
-- geometry and MechBattery for the server's "Plugged" / "Charge" state).
--
--   Plugged  -- anchored, laid along MechCord.layout from the socket every
--               frame the socket moves: it drapes as the mech stands and
--               walks around the pad, and pulls taut as it walks away
--   Loose    -- the plug has snapped out: unanchored chain of ball-socket
--               segments hanging off the outlet, falling to the floor
--   Rest     -- settled on the floor and anchored again (no jitter, no cost)
--   Replug   -- tweening back up into the socket
--
-- Snapping and re-plugging follow the server's "Plugged" attribute (it
-- snaps once the socket is out of the cord's reach, MechBattery).
-- Cords collide with the world only (MechCord.Group).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechCord = require(Shared:WaitForChild("MechCord"))

local CordController = {}

local SOUNDS = MechConfig.Sounds
local D = MechCord.Diameter
local WHIP_SEGMENTS = 7 -- segments near the plug flung out by the snap
local REPLUG_TIME = 0.38 -- each segment's flight back up
local REPLUG_STAGGER = 0.2 -- the plug leads, the far end follows this much later
local SETTLE_SPEED = 0.8
local REACH = MechCord.reach()

type Entry = {
	model: Model,
	cord: MechCord.Cord,
	port: Vector3,
	home: CFrame,
	mode: string, -- "Plugged" | "Loose" | "Rest" | "Replug"
	lastPlug: CFrame?,
	looseT: number,
	fell: boolean, -- plug moving down fast (armed for the floor hit)
	hit: boolean,
	settleT: number,
	replugT: number,
	replugFrom: { CFrame },
	replugTo: { CFrame },
	replugFromLen: { number },
	replugToLen: { number },
	replugDone: boolean,
	socketFx: Attachment?,
	hitFx: Attachment,
	plugSounds: { [string]: Sound },
	socketSounds: { [string]: Sound },
	glow: BasePart?,
	light: PointLight?,
	glowKey: number,
	conns: { RBXScriptConnection },
}

local entries: { [Model]: Entry } = {}
local snappedEvent = Instance.new("BindableEvent")
CordController.Snapped = snappedEvent.Event -- (model) the plug just ripped out
local cordFolder: Folder
local rayParams = RaycastParams.new()

local function floorAt(p: Vector3): number
	local hit = workspace:Raycast(Vector3.new(p.X, p.Y + 40, p.Z), Vector3.new(0, -120, 0), rayParams)
	return if hit then hit.Position.Y else 0
end

local function sound(parent: Instance, id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 160
	s.Parent = parent
	return s
end

local function play(s: Sound?, volume: number?, speed: number?)
	if not s then
		return
	end
	if volume then
		s.Volume = volume
	end
	s.PlaybackSpeed = speed or 1
	s.TimePosition = 0
	s:Play()
end

-- Spark burst emitters + a flash light on an attachment.
local function makeFx(att: Attachment, direction: Enum.NormalId)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 220)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 20)),
	})
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Speed = NumberRange.new(14, 30)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Drag = 2
	sparks.Rate = 0
	sparks.EmissionDirection = direction
	sparks.ZOffset = 0.5
	sparks.Parent = att
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 120, 125))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	smoke.Lifetime = NumberRange.new(0.6, 1.1)
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(40, 40)
	smoke.Rate = 0
	smoke.EmissionDirection = direction
	smoke.Parent = att
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Color = Color3.fromRGB(255, 214, 130)
	flash.Range = 14
	flash.Brightness = 0
	flash.Shadows = false
	flash.Parent = att
end

local function burst(att: Attachment?, sparks: number, smoke: number, flash: number, color: Color3?)
	if not att then
		return
	end
	local em = att:FindFirstChild("Sparks") :: ParticleEmitter?
	local sm = att:FindFirstChild("Smoke") :: ParticleEmitter?
	local light = att:FindFirstChild("Flash") :: PointLight?
	if em then
		em.Color = if color then ColorSequence.new(Color3.new(1, 1, 1), color) else em.Color
		em:Emit(sparks)
	end
	if sm and smoke > 0 then
		sm:Emit(smoke)
	end
	if light then
		light.Color = color or Color3.fromRGB(255, 214, 130)
		light.Brightness = flash
		TweenService:Create(light, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	end
end

local SPARK_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 220)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 20)),
})

local function resetSparkColor(att: Attachment?)
	local em = att and att:FindFirstChild("Sparks") :: ParticleEmitter?
	if em then
		em.Color = SPARK_COLORS
	end
end

local function setAnchored(e: Entry, anchored: boolean)
	local segs = e.cord.segments
	for i, seg in segs do
		-- the far end stays fixed in the outlet
		seg.Anchored = anchored or i == #segs
	end
end

local function plugCFrame(e: Entry): CFrame?
	local att = MechCord.plugPoint(e.model)
	return if att then att.WorldCFrame else nil
end

-- Lays the plugged cord from the socket (only when the socket moved).
local function follow(e: Entry, force: boolean?)
	local plug = plugCFrame(e)
	if not plug then
		return
	end
	local last = e.lastPlug
	if not force and last and (last.Position - plug.Position).Magnitude < 0.01 and last.XVector:Dot(plug.XVector) > 0.9999 then
		return
	end
	e.lastPlug = plug
	MechCord.place(e.cord, MechCord.layout(plug, e.port, #e.cord.segments, floorAt), true)
end

-- The plug rips out of the socket: sparks, a pop, and the cord whips away.
local function snap(e: Entry)
	if e.mode ~= "Plugged" and e.mode ~= "Replug" then
		return
	end
	local plug = plugCFrame(e)
	e.mode = "Loose"
	e.looseT, e.settleT, e.fell, e.hit = 0, 0, false, false
	e.lastPlug = nil
	MechCord.resetLengths(e.cord)
	setAnchored(e, false)
	local segs = e.cord.segments
	-- backward out of the socket, and recoiling toward the outlet that yanked it
	local back = if plug then plug.XVector else segs[1].CFrame.LookVector
	local pull = e.port - segs[1].Position
	pull = Vector3.new(pull.X, 0, pull.Z)
	local mix = if pull.Magnitude > 1e-3 then back + pull.Unit * 0.8 else back
	local out = if mix.Magnitude > 0.1 then mix.Unit else back
	local side = Vector3.new(-out.Z, 0, out.X)
	local kick = (math.random() - 0.5) * 2
	for i = 1, math.min(WHIP_SEGMENTS, #segs - 1) do
		local w = (1 - (i - 1) / WHIP_SEGMENTS) ^ 1.5
		local seg = segs[i]
		seg.AssemblyLinearVelocity = out * (16 * w) + Vector3.new(0, 10 * w, 0) + side * (kick * 5 * w)
		seg.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (8 * w)
	end
	burst(e.socketFx, 45, 8, 12)
	play(e.socketSounds.Spark, 1.2, 1.05 + math.random() * 0.1)
	play(e.socketSounds.Pop, 1.4, 0.75)
	if e.light then
		e.light.Brightness = 0
	end
	snappedEvent:Fire(e.model)
end

-- Flies the cord back up into the socket.
local function replug(e: Entry)
	if e.mode == "Plugged" or e.mode == "Replug" then
		return
	end
	local plug = plugCFrame(e)
	if not plug then
		return
	end
	setAnchored(e, true)
	local segs = e.cord.segments
	local to, toLen = MechCord.frames(e.cord, MechCord.layout(plug, e.port, #segs, floorAt), true)
	e.replugFrom, e.replugTo, e.replugToLen = {}, to, toLen
	e.replugFromLen = {}
	for i, seg in segs do
		e.replugFrom[i] = seg.CFrame
		e.replugFromLen[i] = seg.Size.X
	end
	e.replugT = 0
	e.replugDone = false
	e.mode = "Replug"
	play(e.plugSounds.Whip, 0.6, 1.5)
end

local function backOut(x: number): number
	local s = 1.9
	x -= 1
	return 1 + (s + 1) * x * x * x + s * x * x
end

local function stepReplug(e: Entry, dt: number)
	e.replugT += dt
	local segs = e.cord.segments
	local n = #segs
	local cfs = {}
	local all = true
	for i, seg in segs do
		local delay = (i - 1) / math.max(1, n - 1) * REPLUG_STAGGER
		local u = math.clamp((e.replugT - delay) / REPLUG_TIME, 0, 1)
		if u < 1 then
			all = false
		end
		local k = backOut(u)
		local cf = e.replugFrom[i]:Lerp(e.replugTo[i], math.clamp(k, 0, 1.2))
		-- hop up in an arc on the way
		cf += Vector3.new(0, math.sin(math.min(u, 1) * math.pi) * 2.5 * (1 - (i - 1) / n), 0)
		cfs[i] = cf
		MechCord.setLength(e.cord, i, e.replugFromLen[i] + (e.replugToLen[i] - e.replugFromLen[i]) * math.min(k, 1))
	end
	workspace:BulkMoveTo(segs, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- the plug seats: clunk + charge hum
	if not e.replugDone and e.replugT >= REPLUG_TIME then
		e.replugDone = true
		play(e.socketSounds.Click, 1.1, 1.1)
		play(e.socketSounds.Clunk, 0.9, 1.35)
		play(e.socketSounds.Hum, 0.7, 1)
		burst(e.socketFx, 16, 0, 6, MechCord.GlowOn)
		task.delay(0.35, resetSparkColor, e.socketFx)
		e.glowKey = -1
	end
	if all then
		e.mode = "Plugged"
		e.lastPlug = nil
		follow(e, true)
	end
end

local function stepLoose(e: Entry, dt: number)
	e.looseT += dt
	local segs = e.cord.segments
	local plug = segs[1]
	local v = plug.AssemblyLinearVelocity
	if not e.hit then
		if v.Y < -8 then
			e.fell = true
		end
		local pos = plug.Position
		local near = pos.Y - floorAt(pos) < D * 1.3
		if (e.fell and near and v.Y > -3) or (near and e.looseT > 0.25 and v.Y > -3 and e.fell) then
			e.hit = true
			e.hitFx.WorldPosition = pos
			burst(e.hitFx, 28, 5, 8)
			play(e.plugSounds.SparkSmall, 0.9, 1.1 + math.random() * 0.15)
			play(e.plugSounds.Thud, 1.3, 0.9 + math.random() * 0.1)
			task.delay(0.12, play, e.plugSounds.Whip, 0.5, 0.9)
		elseif e.looseT > 3 then
			e.hit = true
		end
	end
	if e.looseT < 1.5 then
		return
	end
	local still = true
	for _, seg in segs do
		if seg.AssemblyLinearVelocity.Magnitude > SETTLE_SPEED then
			still = false
			break
		end
	end
	e.settleT = if still then e.settleT + dt else 0
	if e.settleT > 0.4 or e.looseT > 8 then
		e.mode = "Rest"
		setAnchored(e, true)
	end
end

-- Socket glow: pulsing green while charging, steady when full, dark unplugged.
local function stepGlow(e: Entry, now: number)
	local glow, light = e.glow, e.light
	if not (glow and light) then
		return
	end
	local plugged = (e.mode == "Plugged" or (e.mode == "Replug" and e.replugDone)) and e.model:GetAttribute("Plugged") == true
	local charge = e.model:GetAttribute("Charge")
	local charging = plugged and typeof(charge) == "number" and charge < 100
	local k: number
	if not plugged then
		k = 0
	elseif charging then
		k = 0.55 + 0.45 * math.sin(now * 6)
	else
		k = 1
	end
	if math.abs(k - e.glowKey) < 0.01 then
		return
	end
	e.glowKey = k
	glow.Color = MechCord.GlowOff:Lerp(MechCord.GlowOn, k)
	light.Brightness = 1.1 * k
end

local function cleanup(model: Model)
	local e = entries[model]
	if not e then
		return
	end
	entries[model] = nil
	for _, c in e.conns do
		c:Disconnect()
	end
	e.cord.folder:Destroy()
	e.hitFx:Destroy()
	if e.socketFx then
		e.socketFx:Destroy()
	end
	for _, s in e.socketSounds do
		s:Destroy()
	end
	if e.light then
		e.light.Brightness = 0
	end
end

local function setup(model: Model)
	if entries[model] then
		return
	end
	local home = model:GetAttribute("Home")
	local socket = model:WaitForChild("PowerSocket", 10)
	if typeof(home) ~= "CFrame" or not socket or not model:IsDescendantOf(workspace) or entries[model] then
		return
	end
	local hole = socket:WaitForChild("Hole", 5) :: BasePart?
	local glow = socket:FindFirstChild("Glow") :: BasePart?
	if not hole then
		return
	end
	local count = MechCord.segmentCount()
	local cord = MechCord.buildCord("PowerCord_" .. model.Name, count, cordFolder)
	local segs = cord.segments
	-- physics: a chain of ball joints, heavy and damped so it flops rather than bounces
	local props = PhysicalProperties.new(2.5, 1.2, 0, 10, 10)
	for i, seg in segs do
		seg.CanCollide = true
		seg.CollisionGroup = MechCord.Group
		seg.CustomPhysicalProperties = props
		for _, d in seg:GetChildren() do
			if d:IsA("BasePart") then
				d.CollisionGroup = MechCord.Group
			end
		end
		local len = cord.lengths[i]
		local a = Instance.new("Attachment")
		a.Name = "A"
		a.Position = Vector3.new(-len / 2, 0, 0)
		a.Parent = seg
		local b = Instance.new("Attachment")
		b.Name = "B"
		b.Position = Vector3.new(len / 2, 0, 0)
		b.Parent = seg
	end
	for i = 1, count - 1 do
		local joint = Instance.new("BallSocketConstraint")
		joint.Attachment0 = segs[i]:FindFirstChild("B") :: Attachment
		joint.Attachment1 = segs[i + 1]:FindFirstChild("A") :: Attachment
		joint.LimitsEnabled = true
		joint.UpperAngle = 50
		joint.Restitution = 0
		joint.MaxFrictionTorque = 25
		joint.Parent = segs[i]
	end

	local socketFx = Instance.new("Attachment")
	socketFx.Name = "CordFx"
	socketFx.Position = Vector3.new(0.3, 0, 0)
	socketFx.Parent = hole
	makeFx(socketFx, Enum.NormalId.Right)
	local hitFx = Instance.new("Attachment")
	hitFx.Name = "CordHitFx_" .. model.Name
	hitFx.Parent = workspace.Terrain
	makeFx(hitFx, Enum.NormalId.Top)

	local e: Entry = {
		model = model,
		cord = cord,
		port = MechCord.outletPort(home),
		home = home,
		mode = "Plugged",
		lastPlug = nil,
		looseT = 0,
		fell = false,
		hit = false,
		settleT = 0,
		replugT = 0,
		replugFrom = {},
		replugTo = {},
		replugFromLen = {},
		replugToLen = {},
		replugDone = false,
		socketFx = socketFx,
		hitFx = hitFx,
		plugSounds = {
			SparkSmall = sound(segs[1], SOUNDS.CordSparkSmall, 0.9),
			Thud = sound(segs[1], SOUNDS.CordThud, 1.3),
			Whip = sound(segs[1], SOUNDS.Whoosh, 0.5),
		},
		socketSounds = {
			Spark = sound(hole, SOUNDS.CordSpark, 1.2),
			Pop = sound(hole, SOUNDS.CordPop, 1.4),
			Click = sound(hole, SOUNDS.CordClick, 1.1),
			Clunk = sound(hole, SOUNDS.Clunk, 0.9),
			Hum = sound(hole, SOUNDS.ChargeHum, 0.7),
		},
		glow = glow,
		light = glow and glow:FindFirstChildOfClass("PointLight"),
		glowKey = -1,
		conns = {},
	}
	entries[model] = e

	if model:GetAttribute("Plugged") == true then
		follow(e, true)
	else
		-- joined while the mech is out: the cord lies by the pad
		e.mode = "Rest"
		local from = (home * CFrame.new(0, 0, 4)).Position
		MechCord.place(cord, MechCord.restLayout(from, e.port, count, floorAt), false)
	end

	table.insert(e.conns, model:GetAttributeChangedSignal("Plugged"):Connect(function()
		if model:GetAttribute("Plugged") == true then
			replug(e)
		else
			snap(e)
		end
	end))
	table.insert(e.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			cleanup(model)
		end
	end))
end

local function step(dt: number)
	local now = os.clock()
	for model, e in entries do
		if e.mode == "Plugged" then
			-- walked out of reach: rip it out now rather than a round trip
			-- later (the server's "Plugged" follows right behind)
			local plug = plugCFrame(e)
			if plug and model:GetAttribute("PowerState") == "Online" and (plug.Position - e.port).Magnitude > REACH + 1 then
				snap(e)
			else
				follow(e)
			end
		elseif e.mode == "Replug" then
			stepReplug(e, dt)
		elseif e.mode == "Loose" then
			stepLoose(e, dt)
		elseif model:GetAttribute("Plugged") == true then
			-- settled, but the server still has it plugged in (a local snap it
			-- never confirmed): go back to what the server says
			replug(e)
		end
		stepGlow(e, now)
	end
end

-- The cord mode of a mech (for debugging / tests).
function CordController.getMode(model: Model): string?
	local e = entries[model]
	return if e then e.mode else nil
end

function CordController.start()
	cordFolder = Instance.new("Folder")
	cordFolder.Name = "MechCords"
	cordFolder.Parent = workspace
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { cordFolder }
	rayParams.RespectCanCollide = true
	-- only what a cord would land on (the world): skips players, armor, mech roots
	task.spawn(function()
		local t0 = os.clock()
		while not PhysicsService:IsCollisionGroupRegistered(MechCord.Group) and os.clock() - t0 < 10 do
			task.wait(0.2)
		end
		rayParams.CollisionGroup = MechCord.Group
	end)

	CollectionService:GetInstanceAddedSignal("Mech"):Connect(function(inst)
		if inst:IsA("Model") then
			task.spawn(setup, inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Mech"):Connect(function(inst)
		if inst:IsA("Model") then
			cleanup(inst)
		end
	end)
	for _, inst in CollectionService:GetTagged("Mech") do
		if inst:IsA("Model") then
			task.spawn(setup, inst)
		end
	end
	RunService.PostSimulation:Connect(step)
end

return CordController
