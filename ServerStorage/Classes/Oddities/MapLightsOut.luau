local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local LightService = require(ServerStorage.Services.LightService)
local Oddity = require(ServerStorage.Classes.Oddity)

local FLOOR_TAG = "MazeFloor"

type Chunk = {
	CFrame: CFrame,
	Size: Vector3,
	Position: Vector3,
}

local ActiveChunks: { [any]: Chunk } = {}

local MapLightsOut = Oddity.extend("MapLightsOut", Oddity)
MapLightsOut.Scope = "Map"
MapLightsOut.ConfigName = "MapOddityConfig"

local function setting(class: any, name: string, fallback: number): number
	local value = class.Settings and class.Settings[name]
	return if type(value) == "number" then value else fallback
end

local function getFloors(): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(FLOOR_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(floors, instance)
		end
	end
	return floors
end

local function floorYAt(position: Vector3): number
	local nearest = math.huge
	local floorY = position.Y
	for _, floor in getFloors() do
		local localPosition = floor.CFrame:PointToObjectSpace(position)
		local outsideX = math.max(math.abs(localPosition.X) - floor.Size.X / 2, 0)
		local outsideZ = math.max(math.abs(localPosition.Z) - floor.Size.Z / 2, 0)
		local distance = outsideX * outsideX + outsideZ * outsideZ
		if distance < nearest then
			nearest = distance
			floorY = floor.CFrame:PointToWorldSpace(Vector3.new(0, floor.Size.Y / 2, 0)).Y
		end
	end
	return floorY
end

local function makeChunk(class: any, position: Vector3): Chunk
	local size = math.max(setting(class, "ChunkSize", 160), 32)
	local height = math.max(setting(class, "ChunkHeight", 48), 8)
	local below = math.clamp(setting(class, "ChunkBelow", 4), 0, height)
	local floorY = floorYAt(position)
	local centre = Vector3.new(position.X, floorY + (height - below) / 2, position.Z)
	return {
		CFrame = CFrame.new(centre),
		Size = Vector3.new(size, height, size),
		Position = Vector3.new(position.X, floorY, position.Z),
	}
end

local function overlaps(first: Chunk, second: Chunk): boolean
	local offset = first.CFrame:PointToObjectSpace(second.CFrame.Position)
	local firstHalf = first.Size / 2
	local secondHalf = second.Size / 2
	return math.abs(offset.X) < firstHalf.X + secondHalf.X
		and math.abs(offset.Y) < firstHalf.Y + secondHalf.Y
		and math.abs(offset.Z) < firstHalf.Z + secondHalf.Z
end

local function isActive(chunk: Chunk): boolean
	for _, active in ActiveChunks do
		if overlaps(active, chunk) then return true end
	end
	return false
end

local function isFarFromPlayers(position: Vector3, distance: number): boolean
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root and (root.Position - position).Magnitude < distance then return false end
	end
	return true
end

local function hasEnoughLights(class: any, chunk: Chunk): boolean
	return #LightService:GetModelsInBox(chunk.CFrame, chunk.Size)
		>= math.max(math.floor(setting(class, "MinimumLights", 1)), 1)
end

function MapLightsOut.new(config: { [string]: any }?)
	local self = Oddity.new(config, MapLightsOut)
	self.Chunk = nil :: Chunk?
	self.LightClaim = nil :: any
	return self
end

function MapLightsOut.Resolve(class: any, position: Vector3): Chunk
	return makeChunk(class, position)
end

function MapLightsOut.Pick(class: any): Chunk?
	local points = DangerMapService:GetPoints()
	if #points == 0 then return nil end

	local attempts = math.max(math.floor(setting(class, "PickAttempts", 64)), 1)
	local minimumDistance = math.max(setting(class, "MinimumPlayerDistance", 32), 0)
	for _ = 1, attempts do
		local point = points[math.random(1, #points)]
		local chunk = makeChunk(class, point.Position)
		if isFarFromPlayers(chunk.Position, minimumDistance)
			and not isActive(chunk)
			and hasEnoughLights(class, chunk)
		then
			return chunk
		end
	end
	return nil
end

function MapLightsOut:CanStart(context: any): (boolean, string?)
	if type(context) ~= "table" or typeof(context.CFrame) ~= "CFrame"
		or typeof(context.Size) ~= "Vector3" or typeof(context.Position) ~= "Vector3"
	then
		return false, "that is not a valid map chunk"
	end

	local chunk = context :: Chunk
	if isActive(chunk) then return false, "that map chunk is already dark" end
	if not hasEnoughLights(self, chunk) then return false, "that map chunk has no lights" end
	return true, nil
end

function MapLightsOut:OnStart(context: Chunk): boolean
	self.Chunk = context
	local claim = LightService:DisableInBox(context.CFrame, context.Size)
	if #claim.Models == 0 then
		LightService:Release(claim)
		self.Chunk = nil
		return false
	end

	self.LightClaim = claim
	ActiveChunks[self] = context
	return true
end

function MapLightsOut:OnStop()
	if self.LightClaim then
		LightService:Release(self.LightClaim)
		self.LightClaim = nil
	end
	ActiveChunks[self] = nil
	self.Chunk = nil
end

return MapLightsOut
