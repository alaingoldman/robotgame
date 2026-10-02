--!strict
-- Server-authoritative exo attacks. The client fires Attack(aim?) on click /
-- tap / gamepad R2 and animates its own swing at once (prediction); here we
-- check cooldown (per weapon, with a little latency slack), battery, that
-- the attacker is alive and on foot, then find targets from the server's
-- view of the character:
--   melee   nearest target whose surface is within weapon.range of the root,
--           in front (dot > FrontDot) or very close; the Piston Hammer hits
--           every target within its aoe radius in front
--   ranged  (Rivet Gun) a raycast along the client's aim from the chest,
--           first thing hit must be a target, within weapon.range
-- damage = BaseDamage x combo step x DamageMul (arms) x weapon.damage x crit.
-- Every client gets Swing (animate the attacker) and Hit (sparks, numbers,
-- the attacker's own hit-stop / camera shake).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreLoopConfig = require(Shared:WaitForChild("CoreLoopConfig"))
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Targets = require(script.Parent.Targets)

local Combat = {}

local CB = CoreLoopConfig.Combat
local rng = Random.new()
local BAD = Color3.fromRGB(255, 90, 70)

type Hit = { model: Model, pos: Vector3, dist: number }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function meleeTargets(root: BasePart, w: CoreLoopConfig.Weapon): { Hit }
	local p = root.Position
	local f = flat(root.CFrame.LookVector)
	f = if f.Magnitude > 1e-3 then f.Unit else Vector3.zAxis
	local found: { Hit } = {}
	for model, e in Targets.all() do
		local c = e.root.Position
		local r = e.spec.radius
		if math.abs(c.Y - p.Y) > r + 6 then
			continue
		end
		local d = flat(c - p)
		local dist = d.Magnitude - r
		local reach = if w.aoe then math.max(w.range, w.aoe) else w.range
		if dist <= reach then
			local dot = if d.Magnitude > 1e-3 then d.Unit:Dot(f) else 1
			if dot >= CB.FrontDot or dist <= 2.5 then
				local toward = if d.Magnitude > 1e-3 then -d.Unit else -f
				local hp = c + toward * r * 0.85
				hp = Vector3.new(hp.X, math.clamp(p.Y + 0.6, c.Y - r, c.Y + r), hp.Z)
				table.insert(found, { model = model, pos = hp, dist = dist - dot * 2 })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.dist < b.dist
	end)
	if not w.aoe then
		return { found[1] }
	end
	return found
end

local function rangedTarget(char: Model, root: BasePart, aim: Vector3, w: CoreLoopConfig.Weapon): { Hit }
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local loot = workspace:FindFirstChild("CoreLoot")
	if loot then
		table.insert(ignore, loot)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(origin, aim * w.range, params)
	-- generous aim assist: if the ray hit nothing hittable, take the target
	-- nearest the ray (within its radius + 2 studs) that's in clear view
	local best: Hit? = nil
	if hit then
		for model in Targets.all() do
			if hit.Instance:IsDescendantOf(model) then
				return { { model = model, pos = hit.Position, dist = 0 } }
			end
		end
	end
	local maxT = if hit then (hit.Position - origin).Magnitude + 1 else w.range
	for model, e in Targets.all() do
		local c = e.root.Position
		local t = (c - origin):Dot(aim)
		if t > 0 and t < maxT + e.spec.radius then
			local perp = ((origin + aim * t) - c).Magnitude
			if perp <= e.spec.radius + 2 and (not best or t < best.dist) then
				best = { model = model, pos = c - aim * e.spec.radius * 0.8, dist = t }
			end
		end
	end
	return if best then { best } else {}
end

local function onAttack(player: Player, aim: any, hint: any)
	local st = State.get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (st and char and hum and root and hum.Health > 0) or hum.SeatPart then
		return
	end
	local w = CoreLoopConfig.Weapons[st.weapon] or CoreLoopConfig.Weapons.Fists
	local now = os.clock()
	if now - st.lastAttack < w.cooldown - CB.CooldownSlack then
		return
	end
	if not State.spend(player, w.cost) then
		State.toast(player, "nopower", "NO POWER - recharge at your base!", BAD, 2)
		return
	end
	st.combo = if now - st.lastAttack < CB.ComboWindow + w.cooldown then (st.combo % 3) + 1 else 1
	st.lastAttack = now
	Remotes.get("Swing"):FireAllClients(player, st.combo, w.id)

	local hits: { Hit }
	if w.ranged then
		local dir = if typeof(aim) == "Vector3" and aim.Magnitude > 0.1 then aim.Unit else root.CFrame.LookVector
		hits = rangedTarget(char, root, dir, w)
	else
		hits = meleeTargets(root, w)
		-- the client snapped to face its target and named it: trust it within reach
		local e = if typeof(hint) == "Instance" and hint:IsA("Model") then Targets.entry(hint) else nil
		if e then
			local c = e.root.Position
			local d = flat(c - root.Position)
			if d.Magnitude - e.spec.radius <= (w.aoe or w.range) + 2.5 and math.abs(c.Y - root.Position.Y) < e.spec.radius + 6 then
				local listed = false
				for _, h in hits do
					if h.model == hint then
						listed = true
					end
				end
				if not listed then
					local toward = if d.Magnitude > 1e-3 then -d.Unit else Vector3.zAxis
					local hp = c + toward * e.spec.radius * 0.85
					local hit: Hit = { model = hint, pos = Vector3.new(hp.X, math.clamp(root.Position.Y + 0.6, c.Y - e.spec.radius, c.Y + e.spec.radius), hp.Z), dist = 0 }
					if w.aoe then
						table.insert(hits, hit)
					else
						hits = { hit }
					end
				end
			end
		end
	end
	if #hits == 0 then
		return
	end
	local mul = CB.ComboMultipliers[st.combo] or 1
	local dmgMul = (player:GetAttribute("DamageMul") :: number?) or 1
	for _, h in hits do
		local crit = rng:NextNumber() < CB.CritChance
		local dmg = CB.BaseDamage * mul * dmgMul * w.damage * (if crit then CB.CritMultiplier else 1)
		local dealt, killed = Targets.damage(h.model, dmg, player)
		if dealt > 0 or killed then
			Remotes.get("Hit"):FireAllClients({
				attacker = player,
				target = h.model,
				pos = h.pos,
				damage = math.max(1, math.floor(dmg + 0.5)),
				crit = crit,
				killed = killed,
				weapon = w.id,
				combo = st.combo,
			})
		end
	end
end

function Combat.start()
	Remotes.get("Attack").OnServerEvent:Connect(onAttack)
end

return Combat
