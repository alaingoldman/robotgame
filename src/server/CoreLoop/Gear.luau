--!strict
-- Equipped parts + the held weapon, built on the server inside the
-- character (Model "CoreGear") so everyone sees them; welded, massless,
-- non-colliding (PartBuilder). Rebuilt on respawn, on every equip change and
-- when the avatar's body parts are swapped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartBuilder = require(Shared:WaitForChild("CoreLoop"):WaitForChild("PartBuilder"))
local State = require(script.Parent.State)

local Gear = {}

local pending: { [Player]: boolean } = {}

function Gear.rebuild(player: Player)
	local char = player.Character
	local st = State.get(player)
	if not (char and st and char.Parent) then
		return
	end
	local old = char:FindFirstChild("CoreGear")
	if old then
		old:Destroy()
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local body = PartBuilder.readBody(char)
	if not body then
		return
	end
	local model = Instance.new("Model")
	model.Name = "CoreGear"
	for _, slot in { "Legs", "Arms", "Chest", "Head" } do
		local it = st.equipped[slot]
		if it then
			local ok, err = pcall(PartBuilder.attach, body, it, model)
			if not ok then
				warn("[CoreLoop] gear build failed", slot, err)
			end
		end
	end
	if st.weapon ~= "Fists" then
		local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if hand and hand:IsA("BasePart") then
			local w = PartBuilder.weapon(st.weapon)
			local handle = w.PrimaryPart :: BasePart
			local off = PartBuilder.gripOffset
			if hand.Name == "Right Arm" then
				off = CFrame.new(0, -hand.Size.Y / 2 + 0.2, 0) * off
			end
			for _, d in w:GetDescendants() do
				if d:IsA("BasePart") then
					d.Massless = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Anchored = false
				end
			end
			handle.CFrame = hand.CFrame * off
			local weld = Instance.new("Weld")
			weld.Name = "Grip"
			weld.Part0 = hand
			weld.Part1 = handle
			weld.C0 = off
			weld.Parent = handle
			-- re-place the welded pieces relative to the moved handle
			for _, d in w:GetDescendants() do
				if d:IsA("Weld") and d ~= weld and d.Part0 == handle and d.Part1 then
					d.Part1.CFrame = handle.CFrame * d.C0
				end
			end
			w.Name = "Weapon"
			w.Parent = model
		end
	end
	model.Parent = char
end

local function schedule(player: Player, delay: number?)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(delay or 0.25, function()
		pending[player] = nil
		if player.Parent then
			Gear.rebuild(player)
		end
	end)
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	if not player:HasAppearanceLoaded() then
		local t0 = os.clock()
		while not player:HasAppearanceLoaded() and os.clock() - t0 < 6 and player.Character == char do
			task.wait(0.1)
		end
	end
	task.wait(0.3)
	if player.Character ~= char then
		return
	end
	char.ChildAdded:Connect(function(c)
		if c:IsA("BasePart") then
			schedule(player, 0.4)
		end
	end)
	Gear.rebuild(player)
end

function Gear.start()
	State.onGearChanged(function(player)
		schedule(player, 0)
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

return Gear
