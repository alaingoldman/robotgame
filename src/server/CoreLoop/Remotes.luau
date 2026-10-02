--!strict
-- ReplicatedStorage.CoreRemotes (created by the server; clients WaitForChild).
--   client -> server
--     Attack(aim: Vector3?)              swing the current weapon (aim = ranged direction)
--     Sprint(on: boolean)
--     Locker(action: string, arg: any)   "Equip" uid | "Unequip" slot | "Recycle" uid |
--                                        "Weapon" id | "BuyBattery"
--   server -> client
--     State(snapshot)                    locker / equipped / weapons (owner only)
--     Toast(text, color: Color3?, kind: string?)
--     Swing(player, combo, weaponId)     every client animates the attacker
--     Hit(info)                          sparks / numbers / shake (info.attacker)
--     Fx(kind, data)                     Break / Spawn / Snap / Deliver / Expire / CrateDrop /
--                                        CrateOpen / CrateFail / Scrap / Install
--     OpenLocker()                       the base's equip station / locker prompt

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local NAMES = { "Attack", "Sprint", "Locker", "State", "Toast", "Swing", "Hit", "Fx", "OpenLocker" }
local folder: Folder? = nil
local events: { [string]: RemoteEvent } = {}

function Remotes.init()
	if folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "CoreRemotes"
	for _, n in NAMES do
		local e = Instance.new("RemoteEvent")
		e.Name = n
		e.Parent = f
		events[n] = e
	end
	f.Parent = ReplicatedStorage
	folder = f
end

function Remotes.get(name: string): RemoteEvent
	Remotes.init()
	return events[name]
end

function Remotes.toast(player: Player, text: string, color: Color3?, kind: string?)
	Remotes.get("Toast"):FireClient(player, text, color, kind)
end

function Remotes.toastAll(text: string, color: Color3?, kind: string?)
	Remotes.get("Toast"):FireAllClients(text, color, kind)
end

function Remotes.fxAll(kind: string, data: any)
	Remotes.get("Fx"):FireAllClients(kind, data)
end

function Remotes.fx(player: Player, kind: string, data: any)
	Remotes.get("Fx"):FireClient(player, kind, data)
end

return Remotes
