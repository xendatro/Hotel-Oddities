local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HallwayCrushDamageService = {}

if not RunService:IsClient() then
	return HallwayCrushDamageService
end

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local MapCrush = CommunicationService.Get("Oddities", "MapCrush") :: RemoteEvent

type Interval = {
	Minimum: number,
	Maximum: number,
}

type Alcove = {
	Along: number,
	HalfWidth: number,
	Sign: number,
	Inner: number,
	Outer: number,
	Top: number,
}

type PlugRegion = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	Minimum: number,
	Maximum: number,
	ClearHalfWidth: number,
	FloorY: number,
}

type Region = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfWidth: number,
	FloorY: number,
	HeightWindow: number,
	BelowWindow: number,
	Lethal: { Interval },
	Alcoves: { Alcove },
	Plugs: { PlugRegion },
	AlcoveMargin: number,
	AlongMargin: number,
	ClearHalfWidth: number,
	KillWidth: number,
	MaximumOffset: number,
	CloseTime: number,
	StartedAt: number,
}

local localPlayer = Players.LocalPlayer
local Regions: { [number]: Region } = {}
local Reported: { [number]: true } = {}

local function currentOffset(region: Region): number
	local elapsed = math.clamp(workspace:GetServerTimeNow() - region.StartedAt, 0, region.CloseTime)
	local alpha = elapsed / region.CloseTime
	return region.MaximumOffset * alpha * alpha * (3 - 2 * alpha)
end

local function inAlcove(region: Region, position: Vector3, offset: number): boolean
	local relative = position - region.Center
	local along = relative:Dot(region.Axis)
	local across = relative:Dot(region.Across)
	local margin = region.AlcoveMargin

	for _, alcove in region.Alcoves do
		if math.abs(along - alcove.Along) > alcove.HalfWidth + region.AlongMargin then continue end
		if position.Y > alcove.Top or position.Y < region.FloorY - margin then continue end

		local depth = across * alcove.Sign
		if depth >= -margin and depth <= alcove.Outer + margin then
			return true
		end
	end
	return false
end

local function inPlug(region: Region, position: Vector3): boolean
	for _, plug in region.Plugs do
		local relative = position - plug.Center
		local along = relative:Dot(plug.Axis)
		if along < plug.Minimum or along > plug.Maximum then continue end
		if math.abs(relative:Dot(plug.Across)) > plug.ClearHalfWidth then continue end
		return true
	end
	return false
end

local function isCaught(region: Region, position: Vector3, offset: number): boolean
	local height = position.Y - region.FloorY
	if height > region.HeightWindow or height < -region.BelowWindow then return false end
	if inAlcove(region, position, offset) then return false end
	if inPlug(region, position) then return true end

	local relative = position - region.Center
	if math.abs(relative:Dot(region.Across)) > region.HalfWidth then return false end

	local along = relative:Dot(region.Axis)
	for _, interval in region.Lethal do
		if along >= interval.Minimum and along <= interval.Maximum then return true end
	end
	return false
end

MapCrush.OnClientEvent:Connect(function(action: string, token: number, region: Region?)
	if action == "Start" and region then
		Regions[token] = region
		Reported[token] = nil
	elseif action == "Stop" then
		Regions[token] = nil
		Reported[token] = nil
	end
end)

RunService.Heartbeat:Connect(function()
	if next(Regions) == nil then return end

	local root = CharacterService.GetAliveRoot(localPlayer)
	if not root then return end

	for token, region in Regions do
		if Reported[token] then continue end

		local offset = currentOffset(region)
		if (region.ClearHalfWidth - offset) * 2 > region.KillWidth then continue end
		if not isCaught(region, root.Position, offset) then continue end

		Reported[token] = true
		MapCrush:FireServer("Crushed", token)
	end
end)

return HallwayCrushDamageService
