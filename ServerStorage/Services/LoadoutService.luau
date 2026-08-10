--- Copying what a player is carrying, and giving it back later.
---
--- Three things need this and they need it identically: the self revive, a friend's revive, and the
--- keep-items pass all take the same picture at the moment of death and hand the same picture back
--- once there is a Backpack to hand it to. It lives here rather than in any one of them so the
--- answer to "what does a death cost you" is written once.
---
--- A restore TOPS UP rather than overwrites. Between a death and the restore that follows it the
--- player may have respawned, been given a starting item, or picked something up -- restoring by
--- assignment would quietly delete all of that, so each stack is only raised to the quantity it had
--- at capture and anything already at or above it is left alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local InventoryService = require(ServerStorage.Services.InventoryService)

local ATTRIBUTES = PerkConfig.Loadout.Attributes
local BACKPACK_TIMEOUT = 10

export type Entry = {
	Quantity: number,
	Attributes: { [string]: any },
}

export type Snapshot = { [string]: Entry }

local LoadoutService = {}

--- Everything `player` is holding right now, stowed or equipped, as a plain table safe to keep past
--- the death of the character it was read from.
function LoadoutService:Capture(player: Player): Snapshot
	local snapshot: Snapshot = {}

	for name, tool in InventoryService:GetAll(player) do
		local attributes = {}
		for _, attribute in ATTRIBUTES do
			attributes[attribute] = tool:GetAttribute(attribute)
		end

		snapshot[name] = {
			Quantity = tool:GetAttribute("quantity") or 1,
			Attributes = attributes,
		}
	end

	return snapshot
end

--- Gives `snapshot` back to `player`, yielding for their Backpack if it has not replicated yet.
--- Returns false where it never arrived, which is the case where the player left mid-restore.
function LoadoutService:Restore(player: Player, snapshot: Snapshot): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
		or player:WaitForChild("Backpack", BACKPACK_TIMEOUT)
	if not backpack or not backpack:IsA("Backpack") then
		warn(`LoadoutService: no Backpack to restore {player.Name}'s loadout into`)
		return false
	end

	for name, entry in snapshot do
		local existing = InventoryService:Get(player, name)
		local held = if existing then existing:GetAttribute("quantity") or 1 else 0

		local missing = entry.Quantity - held
		if missing > 0 and not InventoryService:Add(player, name, missing) then
			continue
		end

		-- Read back rather than reusing `existing`: the tool may only have come into being on the
		-- `Add` above, and a tool the inventory refused has nothing to write onto.
		local tool = InventoryService:Get(player, name)
		if not tool then continue end

		for attribute, value in entry.Attributes do
			tool:SetAttribute(attribute, value)
		end
	end

	return true
end

--- Whether a snapshot is worth restoring at all. An empty one is a real answer -- a player who died
--- empty handed -- and saves the caller a Backpack wait for nothing.
function LoadoutService:IsEmpty(snapshot: Snapshot): boolean
	return next(snapshot) == nil
end

--- The player's character, but only while it is alive and standing somewhere. Every consumer of a
--- snapshot needs this same check before it can put anything back.
function LoadoutService:GetLivingCharacter(player: Player): Model?
	local character = player.Character
	if not character or player.Parent ~= Players then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character
	end
	return nil
end

return LoadoutService
