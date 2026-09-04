local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.MapOddityConfig)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local HallwayRegion = {}

export type Span = Hallways.StraightSpan

local livingRoot = CharacterService.GetAliveRoot

function HallwayRegion.Same(first: Span, second: Span): boolean
	local sameDirection = (first.Start - second.Start).Magnitude <= Config.SpatialPadding
		and (first.Finish - second.Finish).Magnitude <= Config.SpatialPadding
	local oppositeDirection = (first.Start - second.Finish).Magnitude <= Config.SpatialPadding
		and (first.Finish - second.Start).Magnitude <= Config.SpatialPadding
	return sameDirection or oppositeDirection
end

function HallwayRegion.At(position: Vector3, includeRoomFloors: boolean?): Span?
	if not Hallways.At(position, includeRoomFloors) then return nil end
	return Hallways.StraightSpanAt(position)
end

local function width(span: Span): number
	if span.HalfWidth then return span.HalfWidth end

	for _, candidate in Hallways.StraightSpans() do
		if candidate.HalfWidth and HallwayRegion.Same(candidate, span) then
			return candidate.HalfWidth
		end
	end

	local nearest = Hallways.Nearest(span.Center)
	return if nearest then nearest.HalfWidth else 0
end

local function floorY(span: Span): number
	local hallway = Hallways.Nearest(span.Center)
	return if hallway then hallway.FloorY else span.Center.Y
end

function HallwayRegion.Box(span: Span): (CFrame, Vector3)
	local heightWindow = math.max(Config.HallwayHeightWindow, 0)
	local belowWindow = math.max(Config.HallwayBelowWindow, 0)
	local floor = floorY(span)
	local center = Vector3.new(
		span.Center.X,
		floor + (heightWindow - belowWindow) / 2,
		span.Center.Z
	)
	local padding = math.max(Config.SpatialPadding, 0)
	local halfWidth = width(span)
	local cframe = CFrame.lookAt(center, center + span.Axis, Vector3.yAxis)
	local size = Vector3.new(
		halfWidth * 2 + padding * 2,
		heightWindow + belowWindow,
		span.Length + padding * 2
	)
	return cframe, size
end

function HallwayRegion.Occupant(span: Span): Vector3?
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root then
			local playerSpan = HallwayRegion.At(root.Position)
			if playerSpan and HallwayRegion.Same(playerSpan, span) then return root.Position end
		end
	end
	return nil
end

function HallwayRegion.HasPlayer(span: Span): boolean
	return HallwayRegion.Occupant(span) ~= nil
end

function HallwayRegion.RandomDistant(): Span?
	local spans = Hallways.StraightSpans()
	if #spans == 0 then return nil end

	local distant = {}
	for _, span in spans do
		local farEnough = true
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if root and (root.Position - span.Center).Magnitude < Config.MinimumPlayerDistance then
				farEnough = false
				break
			end
		end
		if farEnough then table.insert(distant, span) end
	end

	local choices = if #distant > 0 then distant else spans
	return choices[math.random(1, #choices)]
end

local function weightedChoice(spans: { Span }, dangerWeight: number): Span?
	if #spans == 0 then return nil end

	local total = 0
	local weights = table.create(#spans)
	for index, span in spans do
		local danger = math.clamp(DangerMapService:GetDanger(span.Center), 0, 1)
		local weight = 1 + danger * math.max(dangerWeight, 0)
		weights[index] = weight
		total += weight
	end

	local roll = math.random() * total
	for index, weight in weights do
		roll -= weight
		if roll <= 0 then return spans[index] end
	end
	return spans[#spans]
end

function HallwayRegion.RandomDistantWeighted(
	dangerWeight: number,
	accept: ((Span) -> boolean)?
): Span?
	local distant = {}
	local choices = {}

	for _, span in Hallways.StraightSpans() do
		if accept and not accept(span) then continue end
		table.insert(choices, span)

		local farEnough = true
		for _, player in Players:GetPlayers() do
			local root = livingRoot(player)
			if root and (root.Position - span.Center).Magnitude < Config.MinimumPlayerDistance then
				farEnough = false
				break
			end
		end
		if farEnough then table.insert(distant, span) end
	end

	return weightedChoice(if #distant > 0 then distant else choices, dangerWeight)
end

function HallwayRegion.RandomBiased(occupiedChance: number): Span?
	local spans = Hallways.StraightSpans()
	if #spans == 0 then return nil end

	if math.random() <= occupiedChance then
		local occupied = {}
		for _, span in spans do
			if HallwayRegion.HasPlayer(span) then table.insert(occupied, span) end
		end
		if #occupied > 0 then return occupied[math.random(1, #occupied)] end
	end

	return spans[math.random(1, #spans)]
end

function HallwayRegion.RandomOccupied(): Span?
	local spans = {}
	for _, span in Hallways.StraightSpans() do
		if HallwayRegion.HasPlayer(span) then table.insert(spans, span) end
	end
	if #spans == 0 then return nil end
	return spans[math.random(1, #spans)]
end

return HallwayRegion
