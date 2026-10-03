--!strict
-- Core gameplay loop (client): wires the CoreRemotes to the HUD, locker UI,
-- controls and effects. See CoreLoopConfig / server CoreLoop.
--   Fx        swings, hit-stop, shake, sparks, numbers, debris, sounds
--   Controls  attack / sprint input, movement speed from the server's stats
--   Hud       battery, scrap, cargo timer, slots, crate banner, toasts
--   LockerUi  equip station / part locker panel
--   World     loot labels + bob, crate ring / timer, base prompts, beacons

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreLoop = {}

local player = Players.LocalPlayer

function CoreLoop.start()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
	if not CoreLoopConfig.Enabled then
		return
	end
	local remotes = ReplicatedStorage:WaitForChild("CoreRemotes", 30)
	if not remotes then
		warn("[CoreLoop] no CoreRemotes from the server")
		return
	end
	local Fx = require(script.Fx)
	local Controls = require(script.Controls)
	local Hud = require(script.Hud)
	local LockerUi = require(script.LockerUi)
	local World = require(script.World)
	local GearPicker = require(script.GearPicker)

	Fx.start()
	Hud.start()
	LockerUi.start()
	GearPicker.start()
	World.start()
	Controls.start()
	Controls.setBlocker(function()
		return LockerUi.isOpen() or GearPicker.isOpen()
	end)
	Controls.NoPower = Hud.noPower
	-- rivet gun: a tracer from the muzzle along the aim
	Controls.Shot = function(root: BasePart, aim: Vector3)
		local from = root.Position + Vector3.new(0, 1.2, 0) + root.CFrame.RightVector * 1
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 220, 80)
		p.Size = Vector3.new(0.15, 0.15, 6)
		p.CFrame = CFrame.lookAt(from, from + aim) * CFrame.new(0, 0, -3)
		p.Parent = workspace.Terrain
		local TweenService = game:GetService("TweenService")
		TweenService:Create(p, TweenInfo.new(0.12, Enum.EasingStyle.Linear), { CFrame = p.CFrame * CFrame.new(0, 0, -((CoreLoopConfig.Weapons[(player:GetAttribute("Weapon") :: string?) or "R01"] or CoreLoopConfig.Weapons.R01).range) + 6), Transparency = 0.6 }):Play()
		game:GetService("Debris"):AddItem(p, 0.13)
		Fx.sparks(from + aim * 1.5, Color3.fromRGB(255, 220, 80), 5, 0.6)
		Fx.sound("AirPop", 0.35, 1.6 + math.random() * 0.2)
		Fx.shake(0.12)
	end

	local function rem(name: string): RemoteEvent
		return remotes:WaitForChild(name) :: RemoteEvent
	end

	rem("State").OnClientEvent:Connect(function(s)
		Hud.setState(s)
		LockerUi.setState(s)
		GearPicker.setState(s)
	end)
	rem("Toast").OnClientEvent:Connect(function(text, color, kind)
		Hud.toast(text, color, kind)
	end)
	rem("OpenLocker").OnClientEvent:Connect(function()
		LockerUi.setOpen(true)
	end)
	rem("Swing").OnClientEvent:Connect(function(who: Player, combo: number, weapon: string)
		if who == player then
			return -- already animated locally (prediction)
		end
		local char = who.Character
		if char then
			Fx.swing(char, combo, weapon)
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				Fx.sound("Swing", 0.2, 1.5, root.Position)
			end
		end
	end)
	rem("Hit").OnClientEvent:Connect(function(info)
		local mine = info.attacker == player
		local W = CoreLoopConfig.Weapons[info.weapon] or CoreLoopConfig.Weapons.Fists
		local heavy = info.crit or info.combo == 3 or CoreLoopConfig.weaponAnim(info.weapon) == "Hammer"
		local color = if info.crit then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(255, 210, 90)
		Fx.impact(info.pos, color, heavy)
		if info.target and info.target.Parent then
			Fx.flash(info.target)
			Fx.jiggle(info.target, if heavy then 1.6 else 1)
		end
		if mine then
			Fx.number(info.pos, if info.crit then tostring(info.damage) .. "!" else tostring(info.damage), color, info.crit)
			Fx.shake(W.shake * (if heavy then 1.6 else 1))
			Fx.hitStop(if heavy then 0.09 else 0.05)
			Fx.fovKick(if heavy then 2.5 else 1)
			Fx.sound(if heavy then "HitHeavy" else "Hit", if heavy then 0.6 else 0.45, (if heavy then 1 else 1.25) + math.random() * 0.25)
			if info.crit then
				Fx.sound("Crit", 0.5, 1.3)
			end
		else
			Fx.number(info.pos, tostring(info.damage), Color3.fromRGB(200, 200, 200), false)
			Fx.sound("Hit", 0.3, 1.2 + math.random() * 0.2, info.pos)
		end
	end)
	rem("Fx").OnClientEvent:Connect(function(kind: string, d: any)
		local char = player.Character
		local rp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local function near(pos: Vector3, r: number): number
			if not rp then
				return 0
			end
			return math.clamp(1 - (rp.Position - pos).Magnitude / r, 0, 1)
		end
		if kind == "Break" then
			Fx.breakBurst(d.pos, d.size, d.colors or {})
			Fx.shake(0.9 * near(d.pos, 40))
		elseif kind == "Spawn" then
			Fx.dust(d.pos, d.size * 0.6, Color3.fromRGB(150, 135, 115))
		elseif kind == "Scrap" then
			Hud.scrapGained(d.amount)
		elseif kind == "Drop" then
			Fx.ring(d.pos - Vector3.new(0, 1, 0), d.color, 10, 0.5)
			Fx.sparks(d.pos, d.color, 24, 1.2)
			Fx.sound("PowerUp", 0.35, 1.6, d.pos)
			if (d.tier or 0) >= 8 then
				Fx.ring(d.pos, d.color, 18, 0.7)
			end
		elseif kind == "Pickup" then
			Fx.sparks(d.pos, d.color, 16, 0.8)
			Fx.ring(d.pos, d.color, 6, 0.3)
			if d.player == player then
				Fx.sound("Pop", 0.6, 1.2)
				Fx.sound("Clamp", 0.4, 1.4)
				Fx.shake(0.3)
			end
		elseif kind == "Deliver" then
			Fx.ring(d.to, d.color, 14, 0.5)
			Fx.sparks(d.to + Vector3.new(0, 1, 0), d.color, 30, 1.2)
			if d.player == player then
				Fx.sound("ChargeUp", 0.5, 1.4)
				Fx.shake(0.4)
			end
		elseif kind == "Expire" then
			Fx.debris(d.pos, 3, { d.color, Color3.fromRGB(62, 65, 70) }, 10)
			Fx.sparks(d.pos, Color3.fromRGB(255, 90, 70), 26, 1.2)
			Fx.dust(d.pos, 2.5, Color3.fromRGB(90, 90, 95))
			Fx.sound("Thud", 0.5, 1.1, d.pos)
		elseif kind == "Snap" then
			local who = d.player :: Player
			local c = who and who.Character
			local wr = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if wr then
				Fx.ring(wr.Position - Vector3.new(0, 2.6, 0), Color3.fromRGB(90, 255, 140), 9, 0.35)
				Fx.sparks(wr.Position + Vector3.new(0, 1, 0), Color3.fromRGB(90, 255, 140), 20, 0.8)
				task.delay(0.35, function()
					local gear = c and c:FindFirstChild("CoreGear")
					local g = gear and gear:FindFirstChild("Gear_" .. tostring(d.slot))
					if g then
						Fx.flash(g, Color3.fromRGB(150, 255, 190))
					end
				end)
			end
			if who == player then
				Fx.sound("Clamp", 0.6, 1.15)
				Fx.sound("Hiss", 0.3, 1.4)
				Fx.shake(0.5)
				Fx.fovKick(3)
			end
		elseif kind == "Denied" then
			Fx.sound("Beep", 0.5, 0.8)
			Fx.shake(0.35)
		elseif kind == "Install" then
			Fx.sound("ChargeUp", 0.5, 1.2)
			if rp then
				Fx.ring(rp.Position - Vector3.new(0, 2.6, 0), Color3.fromRGB(90, 255, 140), 12, 0.45)
			end
		elseif kind == "CrateDrop" then
			Fx.dust(d.pos, 6)
			Fx.ring(d.pos + Vector3.new(0, 0.3, 0), Color3.fromRGB(80, 200, 255), 24, 0.5)
			Fx.sound("Stomp", 0.8, 1.1, d.pos)
			Fx.shake(1.4 * near(d.pos, 90))
		elseif kind == "CrateOpen" then
			Fx.breakBurst(d.pos, 7, { Color3.fromRGB(62, 65, 70), Color3.fromRGB(236, 205, 40), Color3.fromRGB(34, 35, 38) })
			Fx.ring(d.pos, Color3.fromRGB(80, 200, 255), 30, 0.6)
			Fx.sound("ChargeUp", 0.6, 1.3, d.pos)
			Fx.shake(1.6 * near(d.pos, 60))
		elseif kind == "CrateFail" then
			Fx.debris(d.pos, 6, { Color3.fromRGB(62, 65, 70), Color3.fromRGB(60, 50, 40) }, 14)
			Fx.dust(d.pos, 6, Color3.fromRGB(80, 80, 85))
			Fx.sparks(d.pos, Color3.fromRGB(255, 72, 72), 30, 1)
			Fx.sound("PowerDown", 0.7, 0.9, d.pos)
		end
	end)
	-- ask for the state in case the first one fired before we listened
	rem("Locker"):FireServer("Refresh")
end

return CoreLoop
