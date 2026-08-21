local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

local GhostAreaService = {}

local Config = EnemyConfigs.Ghost

local function getArea(hallway: Hallways.Hallway): number
	return 4 * (hallway.HalfLength + Config.DriftMargin) * (hallway.HalfWidth + Config.DriftMargin)
end

local function getRandomPointOver(hallway: Hallways.Hallway): Vector3
	local surface = Vector3.new(hallway.Center.X, hallway.FloorY, hallway.Center.Z)
	local along = (math.random() * 2 - 1) * (hallway.HalfLength + Config.DriftMargin)
	local across = (math.random() * 2 - 1) * (hallway.HalfWidth + Config.DriftMargin)
	return surface + hallway.Axis * along + hallway.Across * across
end

function GhostAreaService:GetRandomPoint(): Vector3?
	local hallways = Hallways.All()
	if #hallways == 0 then return nil end

	local total = 0
	for _, hallway in hallways do
		total += getArea(hallway)
	end

	local chosen = hallways[#hallways]
	local roll = math.random() * total
	for _, hallway in hallways do
		roll -= getArea(hallway)
		if roll <= 0 then
			chosen = hallway
			break
		end
	end

	local point = getRandomPointOver(chosen)
	local floor = Hallways.Nearest(point) or chosen
	return Vector3.new(point.X, floor.FloorY + Config.HoverHeight, point.Z)
end

return GhostAreaService
