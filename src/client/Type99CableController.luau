--!strict
-- The WTK-99's charger hoses, run locally on each client (geometry in
-- Type99Charger; the server's "Plugged" / "Charge" state in MechBattery).
--
--   Plugged -- the connector is latched into the hull's CablePort; the two
--              hoses are laid every frame the port moves, the winch paying
--              out just enough for a nice sag (straighter as the mech walks off)
--   Eject   -- out of reach: the latch blows (hiss + clunk + steam + sparks),
--              the connector pops out and tumbles to the floor, then the winch
--              reels the hoses in, dragging it back to the charger
--   Dock    -- the connector drops into the charger's cradle (clunk)
--   Parked  -- sits in the cradle, hoses looped up into the glands
--   Replug  -- the winch pays out, the connector swings up to the port, slides
--              in and latches (clunk + charge-up wind-up, green sparks)
--
-- The charger's screen, light strips, gland light and beacon show the state.
-- Hoses and connector are anchored and scripted (no physics), in the
-- world-only "MechCord" collision group.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local Type99Charger = require(Shared:WaitForChild("Type99Charger"))

local Type99CableController = {}

local SOUNDS = MechConfig.Type99Charger.Sounds
local REACH = Type99Charger.reach()
local GRAVITY = 70
local REEL_START = 0.45 -- the winch kicks in after the connector has flown clear
local REEL_SPEED = 15 -- studs of hose per second
local LEASH = 0.9 -- the hose's straight-line reach, as a share of its length
local DOCK_TIME = 0.35
local REPLUG_FLY = 0.85
local REPLUG_SEAT = 0.22
local CHARGER_TAG = "Type99Charger"

type Entry = {
	model: Model,
	home: CFrame,
	chargerCF: CFrame,
	charger: Model?,
	findT: number,
	conn: Type99Charger.Connector,
	hoses: { Type99Charger.Hose },
	mode: string,
	t: number,
	connCF: CFrame,
	length: number,
	vel: Vector3,
	spin: Vector3,
	latch: number,
	hit: boolean,
	from: CFrame,
	lastPort: CFrame?,
	portFx: Attachment,
	dockFx: Attachment,
	sounds: { [string]: Sound },
	lightKey: string,
	conns: { RBXScriptConnection },
}

local entries: { [Model]: Entry } = {}
local ejectedEvent = Instance.new("BindableEvent")
Type99CableController.Ejected = ejectedEvent.Event -- (model) the connector just blew out
local folder: Folder
local rayParams = RaycastParams.new()
local rayExclude: { Instance } = {}

local function floorAt(p: Vector3): number
	local hit = workspace:Raycast(Vector3.new(p.X, p.Y + 30, p.Z), Vector3.new(0, -120, 0), rayParams)
	return if hit then hit.Position.Y else 0
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local function sound(parent: Instance, id: string, volume: number, looped: boolean?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped == true
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 170
	s.Parent = parent
	return s
end

local function play(s: Sound?, volume: number?, speed: number?, from: number?)
	if not s then
		return
	end
	if volume then
		s.Volume = volume
	end
	s.PlaybackSpeed = speed or 1
	s.TimePosition = from or 0
	s:Play()
end

-- Plays a long sound for `len` seconds, fading out at the end.
local function playFor(s: Sound, volume: number, speed: number, len: number)
	play(s, volume, speed)
	task.delay(len, function()
		local tw = TweenService:Create(s, TweenInfo.new(0.3), { Volume = 0 })
		tw:Play()
		tw.Completed:Wait()
		s:Stop()
	end)
end

local function emitter(att: Attachment, name: string, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Right -- the attachment's X: out of the port
	local obj: any = e
	for k, v in props do
		obj[k] = v
	end
	e.Parent = att
end

-- Steam puff, electric sparks and a flash light on an attachment.
local function makeFx(att: Attachment)
	emitter(att, "Steam", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 238, 240)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 4.5) }),
		Lifetime = NumberRange.new(0.6, 1.3),
		Speed = NumberRange.new(9, 20),
		Drag = 3.5,
		SpreadAngle = Vector2.new(28, 28),
		Acceleration = Vector3.new(0, 6, 0),
		RotSpeed = NumberRange.new(-90, 90),
		Rotation = NumberRange.new(0, 360),
		LightInfluence = 0.6,
	})
	emitter(att, "Sparks", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 250, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 110, 255)),
		}),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(12, 26),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -50, 0),
		Drag = 2,
		ZOffset = 0.5,
	})
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Range = 14
	flash.Brightness = 0
	flash.Shadows = false
	flash.Parent = att
end

local function burst(att: Attachment, steam: number, sparks: number, flash: number, color: Color3)
	local st = att:FindFirstChild("Steam") :: ParticleEmitter?
	local sp = att:FindFirstChild("Sparks") :: ParticleEmitter?
	local light = att:FindFirstChild("Flash") :: PointLight?
	if st and steam > 0 then
		st:Emit(steam)
	end
	if sp and sparks > 0 then
		sp.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		sp:Emit(sparks)
	end
	if light then
		light.Color = color
		light.Brightness = flash
		TweenService:Create(light, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	end
end

local SPARK_BLUE = Color3.fromRGB(120, 200, 255)

local function findCharger(e: Entry)
	for _, inst in CollectionService:GetTagged(CHARGER_TAG) do
		local home = inst:GetAttribute("Home")
		if inst:IsA("Model") and typeof(home) == "CFrame" and (home.Position - e.home.Position).Magnitude < 0.5 then
			e.charger = inst
			if not table.find(rayExclude, inst) then
				table.insert(rayExclude, inst)
				rayParams.FilterDescendantsInstances = rayExclude
			end
			return
		end
	end
end

local function lay(e: Entry)
	local mid = (e.connCF.Position + Type99Charger.glandCenter(e.home)) / 2
	Type99Charger.layHoses(e.hoses, e.chargerCF, e.connCF, e.length, floorAt(mid))
end

local function place(e: Entry)
	Type99Charger.placeConnector(e.conn, e.connCF, e.latch)
	lay(e)
end

-- Latched in: follow the port (only when it moved).
local function follow(e: Entry, force: boolean?)
	local port = Type99Charger.portCFrame(e.model)
	if not port then
		return
	end
	local last = e.lastPort
	if not force and last and (last.Position - port.Position).Magnitude < 0.01 and last.XVector:Dot(port.XVector) > 0.9999 then
		return
	end
	e.lastPort = port
	e.connCF = port
	e.latch = 0
	e.length = Type99Charger.hoseLength(Type99Charger.spanOf(e.chargerCF, port))
	place(e)
end

local function park(e: Entry)
	e.mode = "Parked"
	e.connCF = Type99Charger.parkCFrame(e.home)
	e.latch = 0
	e.length = Type99Charger.hoseLength(Type99Charger.spanOf(e.chargerCF, e.connCF))
	place(e)
end

local function stopWinch(e: Entry)
	local w = e.sounds.Winch
	if w.IsPlaying then
		local tw = TweenService:Create(w, TweenInfo.new(0.2), { Volume = 0 })
		tw:Play()
		task.delay(0.2, function()
			if e.mode == "Parked" or e.mode == "Plugged" then
				w:Stop()
			end
		end)
	end
end

-- Out of reach: the latch blows and the connector pops out.
local function eject(e: Entry)
	if e.mode ~= "Plugged" and e.mode ~= "Replug" then
		return
	end
	local port = Type99Charger.portCFrame(e.model) or e.connCF
	e.mode = "Eject"
	e.t = 0
	e.hit = false
	e.lastPort = nil
	e.connCF = port
	local root = e.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carry = if root then root.AssemblyLinearVelocity * 0.4 else Vector3.zero
	e.vel = port.XVector * 15 + Vector3.new(0, 9, 0) + carry
	e.spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * (5 + math.random() * 3)
	e.portFx.WorldCFrame = port
	burst(e.portFx, 14, 22, 10, SPARK_BLUE)
	task.delay(0.08, burst, e.portFx, 8, 0, 0, SPARK_BLUE)
	playFor(e.sounds.Release, 1.1, 1.0, 0.9)
	play(e.sounds.Clamp, 1.2, 1.15)
	playFor(e.sounds.Pop, 0.9, 1.1, 0.6)
	playFor(e.sounds.Steam, 0.7, 1.25, 0.7)
	ejectedEvent:Fire(e.model)
end

-- Rotates a CFrame by an angular velocity over dt.
local function spun(cf: CFrame, w: Vector3, dt: number): CFrame
	local a = w.Magnitude * dt
	if a < 1e-5 then
		return cf
	end
	return CFrame.new(cf.Position) * CFrame.fromAxisAngle(w.Unit, a) * cf.Rotation
end

local function stepEject(e: Entry, dt: number)
	e.t += dt
	local t = e.t
	e.latch = math.min(1, e.latch + dt / 0.08)
	-- ballistic flight, tumbling
	e.vel += Vector3.new(0, -GRAVITY * dt, 0)
	local pos = e.connCF.Position + e.vel * dt
	local floor = floorAt(pos) + 0.7
	if pos.Y < floor then
		pos = Vector3.new(pos.X, floor, pos.Z)
		if e.vel.Y < -3 and not e.hit then
			e.hit = true
			play(e.sounds.Thud, 1.2, 0.95 + math.random() * 0.1)
			e.portFx.WorldCFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
			burst(e.portFx, 3, 12, 5, Color3.fromRGB(255, 200, 90))
		end
		e.vel = Vector3.new(e.vel.X * 0.55, if e.vel.Y < -2 then -e.vel.Y * 0.25 else 0, e.vel.Z * 0.55)
		e.spin *= 0.5
	end
	-- bounce off the charger itself
	local bumped: boolean
	pos, e.vel, bumped = Type99Charger.collide(e.chargerCF, pos, e.vel, 0.8)
	if bumped then
		e.spin *= 0.6
	end
	-- the winch reels the hoses in; a hose shorter than the gap drags the connector
	local gland = Type99Charger.glandCenter(e.home)
	if t >= REEL_START then
		if not e.sounds.Winch.IsPlaying then
			e.sounds.Winch.Volume = 0.9
			play(e.sounds.Winch, 0.9, 1.15)
		end
		e.length = math.max(2.5, e.length - REEL_SPEED * dt)
		local d = pos - gland
		local leash = e.length * LEASH
		if d.Magnitude > leash then
			local dir = d.Unit
			pos = gland + dir * leash
			local out = e.vel:Dot(dir)
			if out > -REEL_SPEED * 0.6 then
				e.vel -= dir * (out + REEL_SPEED * 0.6)
			end
			e.spin *= 0.9
		end
	end
	e.connCF = spun(CFrame.new(pos) * e.connCF.Rotation, e.spin, dt)
	place(e)
	local parkPos = Type99Charger.parkCFrame(e.home).Position
	if (t > REEL_START and (pos - parkPos).Magnitude < 2.4) or t > 5 then
		e.mode = "Dock"
		e.t = 0
		e.from = e.connCF
	end
end

local function stepDock(e: Entry, dt: number)
	e.t += dt
	local k = smooth(e.t / DOCK_TIME)
	local target = Type99Charger.parkCFrame(e.home)
	e.connCF = e.from:Lerp(target, k)
	e.latch = 1 - k
	e.length = math.max(Type99Charger.hoseLength(Type99Charger.spanOf(e.chargerCF, e.connCF)), 2.5)
	place(e)
	if e.t >= DOCK_TIME then
		park(e)
		stopWinch(e)
		play(e.sounds.Dock, 1.0, 1.05)
		e.dockFx.WorldCFrame = target
		burst(e.dockFx, 4, 6, 3, Color3.fromRGB(255, 190, 90))
	end
end

-- Back in reach and sat down: swing the connector up into the port.
local function replug(e: Entry)
	if e.mode == "Plugged" or e.mode == "Replug" then
		return
	end
	e.mode = "Replug"
	e.t = 0
	e.from = e.connCF
	e.sounds.Winch.Volume = 0.8
	play(e.sounds.Winch, 0.8, 1.35)
end

local function stepReplug(e: Entry, dt: number)
	e.t += dt
	local port = Type99Charger.portCFrame(e.model)
	if not port then
		return
	end
	local t = e.t
	local pre = port.Position + port.XVector * 1.8
	if t < REPLUG_FLY then
		local u = smooth(t / REPLUG_FLY)
		local p0 = e.from.Position
		local p1 = p0 + e.from.XVector * 3 + Vector3.new(0, 5, 0)
		local p2 = pre + port.XVector * 4 + Vector3.new(0, 2, 0)
		local pos = bezier(p0, p1, p2, pre, u)
		e.connCF = CFrame.new(pos) * e.from.Rotation:Lerp(port.Rotation, u)
		e.latch = math.min(1, t / 0.15)
	else
		local u = math.clamp((t - REPLUG_FLY) / REPLUG_SEAT, 0, 1)
		e.connCF = port + port.XVector * (1.8 * (1 - u * u))
		e.latch = 1
	end
	e.length = Type99Charger.hoseLength(Type99Charger.spanOf(e.chargerCF, e.connCF))
	place(e)
	if t >= REPLUG_FLY + REPLUG_SEAT then
		e.mode = "Plugged"
		e.lastPort = nil
		follow(e, true)
		stopWinch(e)
		e.portFx.WorldCFrame = port
		burst(e.portFx, 5, 16, 7, Type99Charger.GlowOn)
		play(e.sounds.Clamp, 1.2, 1.3)
		playFor(e.sounds.ChargeUp, 0.8, 1.1, 1.6)
		e.lightKey = ""
	end
end

local function setText(label: Instance?, text: string, color: Color3)
	if label and label:IsA("TextLabel") then
		label.Text = text
		label.TextColor3 = color
	end
end

-- Charger screen, strips, gland light, beacon and the connector's LED.
local function stepLights(e: Entry, now: number)
	local charger = e.charger
	local plugged = e.mode == "Plugged" and e.model:GetAttribute("Plugged") == true
	local c = e.model:GetAttribute("Charge")
	local pct = if typeof(c) == "number" then math.floor(c + 0.5) else 0
	local busy = e.mode == "Eject" or e.mode == "Dock" or e.mode == "Replug"
	local status: string
	local color: Color3
	local k: number -- green strength
	if plugged and pct < 100 then
		status, color, k = "CHARGING", Type99Charger.GlowOn, 0.55 + 0.45 * math.sin(now * 5)
	elseif plugged then
		status, color, k = "CHARGED", Type99Charger.GlowOn, 1
	elseif e.mode == "Eject" or e.mode == "Dock" then
		status, color, k = "LINK LOST", Color3.fromRGB(255, 80, 60), 0
	elseif e.mode == "Replug" then
		status, color, k = "LINKING", Type99Charger.GlowStandby, 0
	else
		status, color, k = "STANDBY", Type99Charger.GlowStandby, 0
	end
	local flash = busy and math.sin(now * 14) > 0
	local key = string.format("%s|%d|%.2f|%s", status, pct, k, tostring(flash))
	if key == e.lightKey then
		return
	end
	e.lightKey = key
	local green = Type99Charger.GlowOff:Lerp(Type99Charger.GlowOn, k)
	e.conn.led.Color = if plugged then green else Type99Charger.GlowOff
	if not charger then
		return
	end
	local strip = if plugged then green else Type99Charger.GlowOff:Lerp(Type99Charger.GlowStandby, if busy and flash then 0.9 else 0.3)
	for _, name in { "StripL", "StripR" } do
		local p = charger:FindFirstChild(name) :: BasePart?
		if p then
			p.Color = strip
		end
	end
	local gland = charger:FindFirstChild("GlandLight") :: BasePart?
	if gland then
		gland.Color = if plugged then green else Type99Charger.GlowOff
		local light = gland:FindFirstChild("Glow") :: PointLight?
		if light then
			light.Brightness = if plugged then 0.9 * k else 0
		end
	end
	local beacon = charger:FindFirstChild("Beacon") :: BasePart?
	if beacon then
		beacon.Color = if busy and flash then Type99Charger.BeaconOn else Type99Charger.BeaconOff
		local light = beacon:FindFirstChild("Light") :: PointLight?
		if light then
			light.Brightness = if busy and flash then 2 else 0
		end
	end
	local screen = charger:FindFirstChild("Screen")
	local gui = screen and screen:FindFirstChild("Display")
	if gui then
		local dim = if e.mode == "Eject" and not flash then color:Lerp(Color3.new(0, 0, 0), 0.6) else color
		setText(gui:FindFirstChild("Status"), status, dim)
		setText(gui:FindFirstChild("Percent"), string.format("%d%%", pct), color)
	end
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
	e.conn.folder:Destroy()
	for _, h in e.hoses do
		h.folder:Destroy()
	end
	e.portFx:Destroy()
	e.dockFx:Destroy()
	-- the charger goes back to standby
	local charger = e.charger
	if charger then
		for _, name in { "StripL", "StripR", "GlandLight" } do
			local p = charger:FindFirstChild(name) :: BasePart?
			if p then
				p.Color = Type99Charger.GlowOff
			end
		end
		local gland = charger:FindFirstChild("GlandLight")
		local light = gland and gland:FindFirstChild("Glow") :: PointLight?
		if light then
			light.Brightness = 0
		end
	end
end

local function setup(model: Model)
	if entries[model] or not Type99Charger.applies(model) then
		return
	end
	local home = model:GetAttribute("Home")
	if typeof(home) ~= "CFrame" then
		return
	end
	-- wait for the hull (and its port) to stream in
	local t0 = os.clock()
	while not Type99Charger.portPart(model) and os.clock() - t0 < 10 and model.Parent do
		task.wait(0.2)
	end
	if not Type99Charger.portPart(model) or not model:IsDescendantOf(workspace) or entries[model] then
		return
	end
	local name = model.Name
	local conn = Type99Charger.buildConnector("T99Connector_" .. name, folder)
	local hoses = { Type99Charger.buildHose("T99Hose1_" .. name, folder), Type99Charger.buildHose("T99Hose2_" .. name, folder) }
	local portFx = Instance.new("Attachment")
	portFx.Name = "T99PortFx_" .. name
	portFx.Parent = workspace.Terrain
	makeFx(portFx)
	local chargerCF = Type99Charger.chargerCFrame(home)
	local dockFx = Instance.new("Attachment")
	dockFx.Name = "T99DockFx_" .. name
	dockFx.WorldCFrame = Type99Charger.parkCFrame(home)
	dockFx.Parent = workspace.Terrain
	makeFx(dockFx)

	local e: Entry = {
		model = model,
		home = home,
		chargerCF = chargerCF,
		charger = nil,
		findT = 0,
		conn = conn,
		hoses = hoses,
		mode = "Plugged",
		t = 0,
		connCF = Type99Charger.parkCFrame(home),
		length = 5,
		vel = Vector3.zero,
		spin = Vector3.zero,
		latch = 0,
		hit = false,
		from = CFrame.identity,
		lastPort = nil,
		portFx = portFx,
		dockFx = dockFx,
		sounds = {
			Release = sound(portFx, SOUNDS.Release, 1.1),
			Clamp = sound(portFx, SOUNDS.Clamp, 1.2),
			Pop = sound(portFx, SOUNDS.Pop, 0.9),
			Steam = sound(portFx, SOUNDS.Steam, 0.7),
			ChargeUp = sound(portFx, SOUNDS.ChargeUp, 0.8),
			Thud = sound(conn.body, MechConfig.Sounds.CordThud, 1.2),
			Winch = sound(dockFx, SOUNDS.Winch, 0.9, true),
			Dock = sound(dockFx, SOUNDS.Dock, 1.0),
		},
		lightKey = "",
		conns = {},
	}
	for k, snd in e.sounds do
		snd.Name = "T99" .. k
	end
	entries[model] = e
	findCharger(e)

	if model:GetAttribute("Plugged") == true then
		follow(e, true)
	else
		park(e)
	end

	table.insert(e.conns, model:GetAttributeChangedSignal("Plugged"):Connect(function()
		if model:GetAttribute("Plugged") == true then
			replug(e)
		else
			eject(e)
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
		if not e.charger or not e.charger.Parent then
			e.charger = nil
			if now - e.findT > 1 then
				e.findT = now
				findCharger(e)
			end
		end
		if e.mode == "Plugged" then
			-- walked out of reach: eject now rather than a round trip later
			-- (the server's "Plugged" follows right behind)
			local port = Type99Charger.portCFrame(model)
			if port and model:GetAttribute("PowerState") == "Online" and (port.Position - Type99Charger.glandCenter(e.home)).Magnitude > REACH + 0.5 then
				eject(e)
			else
				follow(e)
			end
		elseif e.mode == "Eject" then
			stepEject(e, dt)
		elseif e.mode == "Dock" then
			stepDock(e, dt)
		elseif e.mode == "Replug" then
			stepReplug(e, dt)
		elseif model:GetAttribute("Plugged") == true then
			-- parked, but the server still has it plugged in (a local eject it
			-- never confirmed): go back to what the server says
			replug(e)
		end
		stepLights(e, now)
	end
end

-- The connector mode of a mech (for debugging / tests).
function Type99CableController.getMode(model: Model): string?
	local e = entries[model]
	return if e then e.mode else nil
end

function Type99CableController.start()
	folder = Instance.new("Folder")
	folder.Name = "T99Hoses"
	folder.Parent = workspace
	rayExclude = { folder }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = rayExclude
	rayParams.RespectCanCollide = true
	-- only what a hose would land on (the world): skips players, armor, mech roots
	task.spawn(function()
		local t0 = os.clock()
		while not PhysicsService:IsCollisionGroupRegistered(Type99Charger.Group) and os.clock() - t0 < 10 do
			task.wait(0.2)
		end
		rayParams.CollisionGroup = Type99Charger.Group
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

return Type99CableController
