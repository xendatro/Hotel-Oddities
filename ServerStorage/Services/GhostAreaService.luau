local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local POINT_ATTEMPTS = 12

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

local function chooseHallway(hallways: { Hallways.Hallway }, total: number): Hallways.Hallway
	local roll = math.random() * total
	for _, hallway in hallways do
		roll -= getArea(hallway)
		if roll <= 0 then return hallway end
	end
	return hallways[#hallways]
end

local function toHoverPoint(point: Vector3, fallback: Hallways.Hallway): Vector3
	local floor = Hallways.Nearest(point) or fallback
	return Vector3.new(point.X, floor.FloorY + Config.HoverHeight, point.Z)
end

function GhostAreaService:IsPlayerNear(position: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root and (root.Position - position).Magnitude <= Config.VanishDistance then
			return true
		end
	end
	return false
end

function GhostAreaService:GetRandomPoint(): Vector3?
	local hallways = Hallways.All()
	if #hallways == 0 then return nil end

	local total = 0
	for _, hallway in hallways do
		total += getArea(hallway)
	end

	for _ = 1, POINT_ATTEMPTS do
		local chosen = chooseHallway(hallways, total)
		local point = toHoverPoint(getRandomPointOver(chosen), chosen)
		if not self:IsPlayerNear(point) then return point end
	end
	return nil
end

return GhostAreaService
