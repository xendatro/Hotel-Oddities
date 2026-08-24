local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local InventoryService = require(ServerStorage.Services.InventoryService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local ATTRIBUTES = PerkConfig.Loadout.Attributes
local BACKPACK_TIMEOUT = 10

export type Entry = {
	Quantity: number,
	Attributes: { [string]: any },
}

export type Snapshot = { [string]: Entry }

local LoadoutService = {}

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

		local tool = InventoryService:Get(player, name)
		if not tool then continue end

		for attribute, value in entry.Attributes do
			tool:SetAttribute(attribute, value)
		end
	end

	return true
end

function LoadoutService:IsEmpty(snapshot: Snapshot): boolean
	return next(snapshot) == nil
end

function LoadoutService:GetLivingCharacter(player: Player): Model?
	if player.Parent ~= Players then return nil end
	local root = CharacterService.GetAliveRoot(player)
	return if root then player.Character else nil
end

return LoadoutService
