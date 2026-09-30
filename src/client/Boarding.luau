--!strict
-- Client side of boarding and exiting (see MechConfig.Boarding / Exit).
--   * Walks the local pilot's character up the ramp into the cockpit, turns
--     it to face out (the server then seats it), and later walks it back
--     out. The character is physics-owned by this client, so everyone else
--     sees the walk, the turn and the seat through normal replication.
--   * Runs the local camera: a gentle push in on the seated pilot while the
--     doors close, a pull-back as the mech stands, and a reveal shot of
--     the cockpit when getting out.
--
-- Camera handoffs are seamless: before a cinematic ends, the default camera
-- is already running underneath (Custom, with the new subject and its zoom
-- pinned to the shot's distance) while this module still overrides the
-- result each frame. The override then blends into the default camera's
-- own output, so the first uncontrolled frame matches the last scripted one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MechBuilder = require(Shared:WaitForChild("MechBuilder"))
local MechConfig = require(Shared:WaitForChild("MechConfig"))
local MechPose = require(Shared:WaitForChild("MechPose"))

local Boarding = {}

local B, X = MechConfig.Boarding, MechConfig.Exit
local FINAL_ZOOM = MechConfig.BoardFinalZoom
local EXIT_ZOOM = MechConfig.ExitZoom
local PILOT_EYE = 2.9 -- camera focus above the seat top: the seated pilot's face
local REACHED = 2 -- studs (flat) that count as arriving at a waypoint
local BOARD_BLEND = 0.25 -- seconds to blend the last boarding shot into the default camera
local EXIT_BLEND = 0.4 -- same, from the reveal shot onto the pilot walking out

local player = Players.LocalPlayer

type Shot = { yaw: number, pitch: number, dist: number, focus: Vector3 }
type Seq = {
	kind: string, -- "board" | "exit"
	model: Model,
	key: string, -- PowerTime the sequence belongs to
	walking: boolean,
	turnFrom: CFrame?,
	camStart: Shot?, -- where the camera was when the cinematic took over
	followFrame: number?, -- frame the default camera started running underneath
	camDone: boolean,
}
-- blends the scripted shot `from()` into the default camera's output
type Blend = { t0: number, dur: number, from: () -> CFrame?, done: () -> () }

local seq: Seq? = nil
local blend: Blend? = nil
local controlsLocked = false
local onFootZoom: { min: number, max: number }? = nil
local frame = 0

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function easeOut(x: number): number
	x = 1 - math.clamp(x, 0, 1)
	return 1 - x * x
end

local function getControls(): any
	local ok, controls = pcall(function()
		local module = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		return module:GetControls()
	end)
	return if ok then controls else nil
end
Boarding.getControls = getControls

-- Locks (or unlocks) the player's movement input. Scripted MoveTo still works.
function Boarding.lockControls(on: boolean)
	controlsLocked = on
	local controls = getControls()
	if controls then
		if on then
			controls:Disable()
		else
			controls:Enable()
		end
	end
end

local function rootOf(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function localHumanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Sets both zoom limits, in the order that never has min above max.
local function setZoomLimits(min: number, max: number)
	if min > player.CameraMaxZoomDistance then
		player.CameraMaxZoomDistance = max
		player.CameraMinZoomDistance = min
	else
		player.CameraMinZoomDistance = min
		player.CameraMaxZoomDistance = max
	end
end

-- Remembers the on-foot zoom limits (once) before a mech changes them.
function Boarding.saveOnFootZoom()
	if not onFootZoom then
		onFootZoom = { min = player.CameraMinZoomDistance, max = player.CameraMaxZoomDistance }
	end
end

function Boarding.restoreOnFootZoom()
	local z = onFootZoom
	if z then
		onFootZoom = nil
		setZoomLimits(z.min, z.max)
	end
end

-- Starts the default camera on `subject` with its zoom pinned at `dist`, so
-- by the time a cinematic lets go it is already rendering the same shot.
local function follow(subject: Humanoid, dist: number)
	local camera = workspace.CurrentCamera
	setZoomLimits(dist, dist)
	camera.CameraSubject = subject
	camera.CameraType = Enum.CameraType.Custom
end

-- Standing root height above the floor for a character.
local function standHeight(hum: Humanoid, hrp: BasePart): number
	return hum.HipHeight + hrp.Size.Y / 2
end

-- Walks `hum` through `points`, fast enough to finish in `seconds` (up to
-- `maxSpeed`), stopping early when `stop()` says time is up. The caller
-- glides the character the rest of the way if needed.
local function walkPath(s: Seq, hum: Humanoid, hrp: BasePart, points: { Vector3 }, seconds: number, maxSpeed: number, stop: () -> boolean)
	s.walking = true
	local baseSpeed = hum.WalkSpeed
	local len = MechBuilder.pathLength(hrp.Position, points)
	hum.WalkSpeed = math.clamp(len / math.max(seconds, 0.05), baseSpeed, maxSpeed)
	local lift = Vector3.new(0, standHeight(hum, hrp), 0) -- aim at root height, not the floor
	task.spawn(function()
		for _, p in points do
			hum:MoveTo(p + lift)
			local lastPos, stuckFor = hrp.Position, 0
			while seq == s and hum.Parent and not stop() do
				local d = (p - hrp.Position) * Vector3.new(1, 0, 1)
				if d.Magnitude < REACHED then
					break
				end
				local dt = task.wait()
				-- blocked: move on to the next waypoint (the caller glides the rest)
				if (hrp.Position - lastPos).Magnitude < 0.02 then
					stuckFor += dt
					if stuckFor > 0.25 then
						break
					end
				else
					stuckFor = 0
				end
				lastPos = hrp.Position
			end
			if seq ~= s or not hum.Parent or stop() then
				break
			end
		end
		if hum.Parent then
			hum:Move(Vector3.zero)
			hum.WalkSpeed = baseSpeed
		end
	end)
end

-- Camera position for a shot around the mech. yaw 0 = in front of the mech,
-- 90 = its right side, 180 = behind it.
local function shotCFrame(model: Model, shot: Shot): CFrame
	local root = rootOf(model) :: BasePart
	local _, mechYaw, _ = root.CFrame:ToOrientation()
	local facing = CFrame.Angles(0, mechYaw, 0)
	local y, p = math.rad(shot.yaw), math.rad(shot.pitch)
	local dir = facing:VectorToWorldSpace(Vector3.new(math.sin(y) * math.cos(p), math.sin(p), -math.cos(y) * math.cos(p)))
	local pos = shot.focus + dir * shot.dist
	return CFrame.lookAt(pos, shot.focus)
end

local function lerpShot(a: Shot, b: Shot, u: number, zoomU: number): Shot
	return {
		yaw = a.yaw + (b.yaw - a.yaw) * u,
		pitch = a.pitch + (b.pitch - a.pitch) * u,
		dist = a.dist + (b.dist - a.dist) * zoomU,
		focus = a.focus:Lerp(b.focus, u),
	}
end

-- The current camera expressed as a shot around `focus`, so a cinematic can
-- orbit from wherever the camera was instead of cutting through the mech.
local function shotFrom(model: Model, cf: CFrame, focus: Vector3): Shot
	local root = rootOf(model) :: BasePart
	local _, mechYaw, _ = root.CFrame:ToOrientation()
	local offset = CFrame.Angles(0, mechYaw, 0):VectorToObjectSpace(cf.Position - focus)
	local dist = math.max(offset.Magnitude, 1)
	return {
		yaw = math.deg(math.atan2(offset.X, -offset.Z)),
		pitch = math.deg(math.asin(math.clamp(offset.Y / dist, -1, 1))),
		dist = dist,
		focus = focus,
	}
end

-- Blends from shot a to b, turning the short way round.
local function orbit(a: Shot, b: Shot, u: number): Shot
	local yawB = b.yaw
	while yawB - a.yaw > 180 do
		yawB -= 360
	end
	while yawB - a.yaw < -180 do
		yawB += 360
	end
	return lerpShot(a, { yaw = yawB, pitch = b.pitch, dist = b.dist, focus = b.focus }, u, u)
end

-- Where the default camera focuses on the mech: its root plus the R15
-- (unscaled) head offset and the humanoid's CameraOffset. Once the default
-- camera is running on the mech its own Focus is used instead.
local function mechFocus(model: Model, s: Seq?): Vector3
	local camera = workspace.CurrentCamera
	local hum = model:FindFirstChildOfClass("Humanoid")
	if s and s.followFrame and frame > s.followFrame and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == hum then
		return camera.Focus.Position
	end
	local root = rootOf(model) :: BasePart
	local offset = Vector3.new(0, 2, 0) + (if hum then hum.CameraOffset else Vector3.zero)
	return root.CFrame:PointToWorldSpace(offset)
end

local function finalShot(model: Model, s: Seq?): Shot
	return { yaw = 180, pitch = 16, dist = FINAL_ZOOM, focus = mechFocus(model, s) }
end

-- The seated pilot's face while the mech squats.
local function pilotFocus(model: Model): Vector3
	local root = rootOf(model) :: BasePart
	return MechBuilder.offPoints(root.CFrame, MechPose.style(model)).seat.Position + Vector3.new(0, PILOT_EYE, 0)
end

local function closeShot(model: Model): Shot
	return { yaw = 10, pitch = 10, dist = 14, focus = pilotFocus(model) }
end

local function revealShot(model: Model): Shot
	return { yaw = 18, pitch = 12, dist = EXIT_ZOOM, focus = pilotFocus(model) }
end

local function scriptable(): Camera
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	return camera
end

-- Advances the running handoff blend, if any.
local function stepBlend()
	local b = blend
	if not b then
		return
	end
	local camera = workspace.CurrentCamera
	local w = (os.clock() - b.t0) / b.dur
	local from = b.from()
	if w >= 1 or not from or camera.CameraType ~= Enum.CameraType.Custom then
		blend = nil
		b.done()
		return
	end
	-- camera.CFrame is the default camera's output for this frame
	camera.CFrame = from:Lerp(camera.CFrame, smooth(w))
end

local function finishBlend()
	local b = blend
	if b then
		blend = nil
		b.done()
	end
end

local function updateBoard(s: Seq, t: number)
	local model = s.model
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local onFoot = hum ~= nil and hrp ~= nil

	-- (a) walk up the ramp. A raised (one-knee) ramp: walk to the spot under
	-- its lip; Climb animates the climb and the walk up from there.
	local style = MechPose.style(model)
	local climbTime = if style == "OneKnee" then MechConfig.Climb.Climb + MechConfig.Climb.RampWalk else 0
	if onFoot and not s.walking and t < -climbTime then
		local root = rootOf(model) :: BasePart
		local path = MechBuilder.boardPath(root.CFrame, (hrp :: BasePart).Position, style)
		walkPath(s, hum :: Humanoid, hrp :: BasePart, path, -t - climbTime, MechConfig.BoardWalkSpeed, function()
			return MechPose.stateTime(model) - MechPose.boardWalk(model) >= -climbTime
		end)
	end
	-- (b) turn to face out, sliding onto the spot if the walk fell short
	if onFoot and t >= 0 and t < B.Sit + 0.25 and not (hum :: Humanoid).Sit then
		local h, r = hum :: Humanoid, hrp :: BasePart
		if not s.turnFrom then
			s.turnFrom = r.CFrame
			h.AutoRotate = false
			h:Move(Vector3.zero)
		end
		local root = rootOf(model) :: BasePart
		local p = MechBuilder.offPoints(root.CFrame, style)
		local pos = p.stand + Vector3.new(0, standHeight(h, r), 0)
		local target = CFrame.lookAt(pos, pos + p.forward)
		r.CFrame = (s.turnFrom :: CFrame):Lerp(target, smooth(t / B.TurnTime))
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end

	-- camera: default while walking, then (d) push in on the seated pilot
	-- while (e) the doors close, and pull back as the mech stands
	if t < 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local close = closeShot(model)
	if t < B.Sealed then
		scriptable()
		if not s.camStart then
			s.camStart = shotFrom(model, camera.CFrame, close.focus)
		end
		camera.CFrame = shotCFrame(model, orbit(s.camStart :: Shot, close, smooth(t / B.DoorCloseEnd)))
		return
	end
	-- doors shut: the default camera takes the mech underneath this shot
	local mechHum = model:FindFirstChildOfClass("Humanoid")
	if not s.followFrame and mechHum then
		s.followFrame = frame
		follow(mechHum, FINAL_ZOOM)
	end
	local u = (t - B.Sealed) / (B.Online - B.Sealed)
	camera.CFrame = shotCFrame(model, lerpShot(close, finalShot(model, s), smooth(u), easeOut(u)))
end

local function updateExit(s: Seq, t: number)
	local model = s.model
	local camera = workspace.CurrentCamera
	local r = MechPose.revealTime(model)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- reveal shot on the cockpit while the mech squats and opens up
	if not s.camDone then
		scriptable()
		local reveal = revealShot(model)
		if not s.camStart then
			s.camStart = shotFrom(model, camera.CFrame, reveal.focus)
		end
		camera.CFrame = shotCFrame(model, orbit(s.camStart :: Shot, reveal, smooth(t / X.CrouchEnd)))
		if r >= X.Stand and hum and not hum.Sit then
			-- follow the pilot down the ramp with the default camera
			s.camDone = true
			follow(hum, EXIT_ZOOM)
			blend = {
				t0 = os.clock(),
				dur = EXIT_BLEND,
				from = function(): CFrame?
					return if rootOf(model) then shotCFrame(model, reveal) else nil
				end,
				done = Boarding.restoreOnFootZoom,
			}
		end
	end

	-- walk down the ramp once the server has stood the pilot up (Climb hops
	-- the pilot off a raised one-knee ramp instead)
	if r >= X.Stand and not s.walking and hum and hrp and not hum.Sit and MechPose.style(model) ~= "OneKnee" then
		hum.AutoRotate = true
		local root = rootOf(model) :: BasePart
		local p = MechBuilder.offPoints(root.CFrame)
		walkPath(s, hum, hrp, { p.stand, p.hinge, p.lip, p.lip + p.forward * 5 }, X.Off - X.Stand - 0.2, MechConfig.ExitWalkSpeed, function()
			return MechPose.revealTime(model) >= X.Off - 0.05
		end)
	end
end

local function update()
	frame += 1
	local s = seq
	if s then
		local model = s.model
		local state = model:GetAttribute("PowerState")
		local alive = model:IsDescendantOf(workspace) and rootOf(model) ~= nil
		if alive and s.kind == "board" and state == "Online" then
			-- hold the final shot until PilotChanged hands over (Boarding.stop)
			updateBoard(s, B.Online)
		elseif not alive or tostring(model:GetAttribute("PowerTime")) ~= s.key then
			Boarding.stop()
		elseif s.kind == "board" and state == "Boarding" then
			updateBoard(s, MechPose.stateTime(model) - MechPose.boardWalk(model))
		elseif s.kind == "exit" and state == "PoweringDown" then
			updateExit(s, MechPose.stateTime(model))
		end
	end
	stepBlend()
end

local function begin(model: Model, kind: string)
	Boarding.stop()
	finishBlend()
	seq = {
		kind = kind,
		model = model,
		key = tostring(model:GetAttribute("PowerTime")),
		walking = false,
		turnFrom = nil,
		camStart = nil,
		followFrame = nil,
		camDone = false,
	}
end

-- Starts the local boarding sequence for `model` (state "Boarding").
function Boarding.beginBoard(model: Model)
	Boarding.saveOnFootZoom()
	begin(model, "board")
end

-- Starts the local exit sequence for `model` (state "PoweringDown").
function Boarding.beginExit(model: Model)
	begin(model, "exit")
end

-- Puts the default camera back on the local character.
local function releaseCamera()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local hum = localHumanoid()
	if hum then
		camera.CameraSubject = hum
	end
end

-- Ends the running sequence. A finished boarding blends its last shot into
-- the default camera (already following the mech); anything else that still
-- holds the camera gives it back to the character.
function Boarding.stop()
	local s = seq
	seq = nil
	if not s then
		return
	end
	local model = s.model
	if s.kind == "board" and s.followFrame and rootOf(model) then
		blend = {
			t0 = os.clock(),
			dur = BOARD_BLEND,
			from = function(): CFrame?
				return if rootOf(model) then shotCFrame(model, finalShot(model, s)) else nil
			end,
			done = function()
				setZoomLimits(MechConfig.PilotZoomMin, MechConfig.PilotZoomMax)
			end,
		}
	elseif workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable then
		releaseCamera()
	end
	local hum = localHumanoid()
	if hum then
		hum.AutoRotate = true
	end
end

-- Back on foot for any reason (exit finished, died, mech lost): ends any
-- sequence or blend and restores the on-foot camera.
function Boarding.reset()
	Boarding.stop()
	finishBlend()
	local camera = workspace.CurrentCamera
	local hum = localHumanoid()
	if camera.CameraType ~= Enum.CameraType.Custom or (hum and camera.CameraSubject ~= hum) then
		releaseCamera()
	end
	Boarding.restoreOnFootZoom()
end

function Boarding.isActive(): boolean
	return seq ~= nil
end

function Boarding.start()
	-- after the default camera (which is idle while Scriptable), before rendering
	RunService:BindToRenderStep("MechBoarding", Enum.RenderPriority.Camera.Value + 2, update)
	-- a respawned character gets fresh controls; keep them locked mid-sequence
	player.CharacterAdded:Connect(function()
		if controlsLocked then
			task.defer(Boarding.lockControls, true)
		end
	end)
end

return Boarding
