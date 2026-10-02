--!strict
-- Server-authoritative EXO-1 exoskeleton (see ExoBuilder / ExoConfig).
--
-- The exo is built HERE, on the server, inside the player's character: the
-- parts replicate to every client (everyone sees it) and die with the
-- character. They are massless, non-colliding, non-queryable pieces welded
-- into the character's own assembly, so the owning client keeps simulating
-- the character (network ownership is never touched) and nothing fights the
-- Humanoid. Only cosmetic motion (light pulse, pistons re-aimed across the
-- joints, the walking frame's gait) runs on the clients (ExoAnimator), since
-- Motor6D.Transform / per-frame weld tweaks don't replicate anyway and would
-- be wasted bandwidth.
--
-- The player attribute "ExoMode" is the wish ("Auto" = fit to the avatar,
-- "Frame" = force the hoisted walking frame, "Off"/nil = none); it survives
-- respawns. The character attribute "ExoForm" is what was built ("Worn" or
-- "Frame") and "ExoFit" why. While worn: WalkSpeed x WalkSpeedMultiplier,
-- JumpPower / JumpHeight x JumpMultiplier; restored on removal. The frame
-- also raises Humanoid.HipHeight to hoist the rider (restored too) and is
-- taken off while the rider sits in a seat (e.g. a mech cockpit).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExoBuilder = require(Shared:WaitForChild("ExoBuilder"))
local ExoConfig = require(Shared:WaitForChild("ExoConfig"))

local ExoService = {}

type Base = { walk: number, jumpPower: number, jumpHeight: number, hip: number }
type State = {
	char: Model,
	hum: Humanoid,
	model: Model,
	form: string,
	base: Base,
	boosted: Base,
	parts: { [Instance]: boolean }, -- body parts the exo hangs on
}
local states: { [Player]: State } = {}
local pending: { [Player]: boolean } = {}

local function restore(st: State)
	local hum, base, boosted = st.hum, st.base, st.boosted
	if hum.Parent then
		-- only undo our own change (leave values someone else set meanwhile)
		if math.abs(hum.WalkSpeed - boosted.walk) < 1e-3 then
			hum.WalkSpeed = base.walk
		end
		if math.abs(hum.JumpPower - boosted.jumpPower) < 1e-3 then
			hum.JumpPower = base.jumpPower
		end
		if math.abs(hum.JumpHeight - boosted.jumpHeight) < 1e-3 then
			hum.JumpHeight = base.jumpHeight
		end
		if math.abs(hum.HipHeight - boosted.hip) < 1e-3 then
			hum.HipHeight = base.hip
		end
	end
	if st.char.Parent then
		st.char:SetAttribute("ExoForm", nil)
		st.char:SetAttribute("ExoFit", nil)
	end
end

local function teardown(player: Player)
	local st = states[player]
	if not st then
		return
	end
	states[player] = nil
	st.model:Destroy()
	restore(st)
end

-- Builds the exo the player's "ExoMode" asks for on their current character.
local function build(player: Player)
	teardown(player)
	local mode = player:GetAttribute("ExoMode")
	if mode ~= "Auto" and mode ~= "Frame" then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root and hum.Health > 0) then
		return
	end
	local m = ExoBuilder.measure(char, hum, root)
	-- "Frame" mode or the debug character attribute ExoForceFrame skip the fit
	local rig, why = nil, "forced frame"
	if mode == "Auto" and not char:GetAttribute("ExoForceFrame") then
		rig, why = ExoBuilder.readRig(char, hum)
		if rig and m.headH < ExoConfig.StandardHeadHeight * ExoConfig.MinHeadFraction then
			rig, why = nil, string.format("too short (head %.2f)", m.headH)
		end
	end
	if not rig and hum.SeatPart then
		-- the frame comes off while seated; rebuilt when the rider gets up
		char:SetAttribute("ExoFit", "frame (waiting: seated)")
		return
	end

	local base: Base = { walk = hum.WalkSpeed, jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight, hip = hum.HipHeight }
	local model: Model
	local parts: { [Instance]: boolean } = {}
	local hip = base.hip
	if rig then
		model = ExoBuilder.buildWorn(char, rig)
		for _, inst in { rig.torso, rig.pelvis, rig.head, rig.leg.upper.part, rig.leg.lower.part } :: { Instance } do
			parts[inst] = true
		end
		for _, arm in rig.arms do
			parts[arm.upper.part] = true
			parts[arm.lower.part] = true
			parts[arm.hand.part] = true
		end
	else
		local lift: number
		model, lift = ExoBuilder.buildFrame(char, root, m)
		hip = base.hip + lift
		parts[root] = true
	end
	local boosted: Base = {
		walk = base.walk * ExoConfig.WalkSpeedMultiplier,
		jumpPower = if hum.UseJumpPower then base.jumpPower * ExoConfig.JumpMultiplier else base.jumpPower,
		jumpHeight = if hum.UseJumpPower then base.jumpHeight else base.jumpHeight * ExoConfig.JumpMultiplier,
		hip = hip,
	}
	hum.WalkSpeed = boosted.walk
	hum.JumpPower = boosted.jumpPower
	hum.JumpHeight = boosted.jumpHeight
	hum.HipHeight = boosted.hip
	local form = if rig then "Worn" else "Frame"
	states[player] = { char = char, hum = hum, model = model, form = form, base = base, boosted = boosted, parts = parts }
	char:SetAttribute("ExoForm", form)
	char:SetAttribute("ExoFit", why)
end

-- Rebuilds a moment later (coalesces bursts of body-part / seat changes).
local function schedule(player: Player, delay: number?)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(delay or 0.3, function()
		pending[player] = nil
		if player.Parent then
			build(player)
		end
	end)
end

local function onCharacter(player: Player, char: Model)
	teardown(player)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum or player.Character ~= char then
		return
	end
	-- wait for the avatar's body parts / scales before measuring
	if not player:HasAppearanceLoaded() then
		local done = false
		local conn = player.CharacterAppearanceLoaded:Connect(function()
			done = true
		end)
		local t0 = os.clock()
		while not done and os.clock() - t0 < 6 and player.Character == char do
			task.wait(0.1)
		end
		conn:Disconnect()
	end
	task.wait(0.2)
	if player.Character ~= char or not char.Parent then
		return
	end
	hum.Died:Connect(function()
		if states[player] and states[player].char == char then
			teardown(player)
		end
	end)
	-- a seated rider leaves the frame; standing up puts it back
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local st = states[player]
		if (st and st.form == "Frame" and hum.SeatPart) or (not st and hum.SeatPart == nil and char:GetAttribute("ExoFit") == "frame (waiting: seated)") then
			schedule(player, 0.1)
		end
	end)
	-- body parts swapped (HumanoidDescription re-applied, etc.): refit
	char.ChildAdded:Connect(function(c)
		if c:IsA("BasePart") and states[player] then
			schedule(player)
		end
	end)
	char.ChildRemoved:Connect(function(c)
		local st = states[player]
		if st and st.parts[c] then
			schedule(player)
		end
	end)
	char:GetAttributeChangedSignal("ExoForceFrame"):Connect(function()
		schedule(player, 0)
	end)
	build(player)
end

-- Equip (mode "Auto" = fit to the avatar, "Frame" = force the walking frame).
function ExoService.equip(player: Player, mode: string?)
	player:SetAttribute("ExoMode", if mode == "Frame" then "Frame" else "Auto")
	build(player)
end

function ExoService.unequip(player: Player)
	player:SetAttribute("ExoMode", "Off")
	teardown(player)
end

function ExoService.isEquipped(player: Player): boolean
	return states[player] ~= nil
end

local CYCLE = { Off = "Auto", Auto = "Frame", Frame = "Off" }

function ExoService.start()
	local remotes = Instance.new("Folder")
	remotes.Name = "ExoRemotes"
	local toggle = Instance.new("RemoteEvent")
	toggle.Name = "ExoToggle"
	toggle.Parent = remotes
	remotes.Parent = ReplicatedStorage
	-- debug / test hook: "Cycle" (Off -> Auto -> Frame -> Off), "Auto", "Frame", "Off"
	toggle.OnServerEvent:Connect(function(player, what)
		if not ExoConfig.AllowToggle or typeof(what) ~= "string" then
			return
		end
		local mode = if what == "Cycle" then CYCLE[(player:GetAttribute("ExoMode") :: string?) or "Off"] or "Auto" else what
		if mode == "Auto" or mode == "Frame" then
			ExoService.equip(player, mode)
		elseif mode == "Off" then
			ExoService.unequip(player)
		end
	end)

	local function watch(player: Player)
		if ExoConfig.AutoEquip and player:GetAttribute("ExoMode") == nil then
			player:SetAttribute("ExoMode", "Auto")
		end
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		pending[player] = nil
	end)
end

return ExoService
