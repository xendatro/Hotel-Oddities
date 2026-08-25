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

type Region = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfWidth: number,
	FloorY: number,
	HeightWindow: number,
	BelowWindow: number,
	Lethal: { Interval },
	ClearHalfWidth: number,
	KillWidth: number,
	MaximumOffset: number,
	CloseTime: number,
	StartedAt: number,
}

local localPlayer = Players.LocalPlayer
local Regions: { [number]: Region } = {}
local Reported: { [number]: true } = {}

local function clearWidth(region: Region): number
	local elapsed = math.clamp(workspace:GetServerTimeNow() - region.StartedAt, 0, region.CloseTime)
	local alpha = elapsed / region.CloseTime
	local offset = region.MaximumOffset * alpha * alpha * (3 - 2 * alpha)
	return (region.ClearHalfWidth - offset) * 2
end

local function isCaught(region: Region, position: Vector3): boolean
	local height = position.Y - region.FloorY
	if height > region.HeightWindow or height < -region.BelowWindow then return false end

	local offset = position - region.Center
	if math.abs(offset:Dot(region.Across)) > region.HalfWidth then return false end

	local along = offset:Dot(region.Axis)
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
		if clearWidth(region) > region.KillWidth then continue end
		if not isCaught(region, root.Position) then continue end

		Reported[token] = true
		MapCrush:FireServer("Crushed", token)
	end
end)

return HallwayCrushDamageService
