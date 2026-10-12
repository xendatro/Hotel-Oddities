-- Server half of gravity-warp playtests: hands out real items and runs the real
-- server warp (the same call the Sisters catch makes). Call through ServerBridge.
local ServerStorage = game:GetService("ServerStorage")

local GravityWarpService = require(ServerStorage.Services.GravityWarpService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local WarpServer = {}

function WarpServer.Give(player: Player, toolName: string, count: number?): boolean
	return InventoryService:Add(player, toolName, count or 1)
end

function WarpServer.Warp(player: Player, duration: number?, leadTime: number?): boolean
	return GravityWarpService:Warp(player, duration, leadTime)
end

function WarpServer.State(player: Player)
	local character = player.Character
	return {
		warping = GravityWarpService:IsWarping(character),
		canWarp = GravityWarpService:CanWarp(player),
	}
end

return WarpServer
