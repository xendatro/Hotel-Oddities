local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HallwayCrushVfxService = {}

if not RunService:IsClient() then
	return HallwayCrushVfxService
end

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MapOddityConfig = require(ReplicatedStorage.Configs.MapOddityConfig)
local VfxConfig = require(ReplicatedStorage.Configs.VfxConfig)
local VfxService = require(ReplicatedStorage.Services.VfxService)

local CRUSH = VfxConfig.Crush
local TEMPLATES = VfxConfig.Templates
local SAFE_MARGIN = MapOddityConfig.Effects.HallwayCrush.SafeMargin or 0

type Interval = {
	Minimum: number,
	Maximum: number,
}

type Region = {
	Center: Vector3,
	Axis: Vector3,
	FloorY: number,
	Lethal: { Interval },
	ClearHalfWidth: number,
	MaximumOffset: number,
	CloseTime: number,
	StartedAt: number,
}

type Wall = {
	Effect: any,
	Interval: Interval,
	Side: number,
}

type Crush = {
	Region: Region,
	Height: number,
	Walls: { Wall },
	Sealed: boolean,
}

local MapCrush = CommunicationService.Get("Oddities", "MapCrush") :: RemoteEvent

local Crushes: { [number]: Crush } = {}

local function alphaOf(region: Region): number
	local elapsed = math.clamp(workspace:GetServerTimeNow() - region.StartedAt, 0, region.CloseTime)
	return elapsed / region.CloseTime
end

local function measureHeight(region: Region): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = {}
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(ignore, player.Character) end
	end
	params.FilterDescendantsInstances = ignore

	local nearWall = region.Center + Vector3.yAxis:Cross(region.Axis) * region.ClearHalfWidth * CRUSH.CeilingProbeAcross
	local origin = Vector3.new(nearWall.X, region.FloorY + 3, nearWall.Z)
	local hit = workspace:Raycast(origin, Vector3.yAxis * CRUSH.CeilingSearch, params)
	if not hit then return CRUSH.CeilingFallback end
	return hit.Position.Y - region.FloorY
end

local function frameAt(region: Region, along: number, across: number, height: number): CFrame
	local axis = region.Axis
	local acrossAxis = Vector3.yAxis:Cross(axis)
	local point = region.Center + axis * along + acrossAxis * across
	return CFrame.fromMatrix(Vector3.new(point.X, region.FloorY + height, point.Z), axis, acrossAxis, Vector3.yAxis)
end

local function wallFrame(crush: Crush, wall: Wall, offset: number): CFrame
	local region = crush.Region
	local along = (wall.Interval.Minimum + wall.Interval.Maximum) / 2
	local across = wall.Side * math.max(region.ClearHalfWidth - offset, 0)
	return frameAt(region, along, across, crush.Height - CRUSH.CeilingInset)
end

local function stopWalls(crush: Crush)
	for _, wall in crush.Walls do
		if wall.Effect then wall.Effect:Stop() end
	end
	table.clear(crush.Walls)
end

local function seal(crush: Crush)
	crush.Sealed = true
	stopWalls(crush)

	local region = crush.Region
	for _, interval in region.Lethal do
		if interval.Maximum - interval.Minimum < CRUSH.MinimumLength then continue end
		for _, ending in { { interval.Minimum - SAFE_MARGIN, -1 }, { interval.Maximum + SAFE_MARGIN, 1 } } do
			local point = region.Center + region.Axis * ending[1]
			local position = Vector3.new(point.X, region.FloorY + crush.Height / 2, point.Z)
			local outward = region.Axis * ending[2]
			VfxService:Play(TEMPLATES.CrushSeal, CFrame.lookAt(position, position + outward), {
				Size = Vector3.new(1, crush.Height, 0.3),
			})
		end
	end
end

local function start(token: number, region: Region)
	local crush: Crush = {
		Region = region,
		Height = measureHeight(region),
		Walls = {},
		Sealed = false,
	}
	Crushes[token] = crush

	for _, interval in region.Lethal do
		local length = interval.Maximum - interval.Minimum
		if length < CRUSH.MinimumLength then continue end
		for _, side in { 1, -1 } do
			local wall: Wall = { Effect = nil, Interval = interval, Side = side }
			wall.Effect = VfxService:Play(TEMPLATES.CrushDust, wallFrame(crush, wall, 0), {
				Size = Vector3.new(length, 0.6, 0.3),
			})
			if wall.Effect then table.insert(crush.Walls, wall) end
		end
	end
end

local function stop(token: number)
	local crush = Crushes[token]
	if not crush then return end
	Crushes[token] = nil
	stopWalls(crush)
end

MapCrush.OnClientEvent:Connect(function(action: string, token: number, region: any)
	if action == "Start" and type(region) == "table" then
		stop(token)
		start(token, region)
	elseif action == "Stop" then
		stop(token)
	end
end)

RunService.Heartbeat:Connect(function()
	for _, crush in Crushes do
		if crush.Sealed then continue end

		local alpha = alphaOf(crush.Region)
		local offset = crush.Region.MaximumOffset * alpha * alpha * (3 - 2 * alpha)
		for _, wall in crush.Walls do
			wall.Effect:SetCFrame(wallFrame(crush, wall, offset))
		end
		if alpha >= CRUSH.SealAt then
			seal(crush)
		end
	end
end)

return HallwayCrushVfxService
