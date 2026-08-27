local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HallwayCrushDamageService = {}

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

type SealRegion = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	Minimum: number,
	Maximum: number,
	Plane: number,
	Depth: number,
	FloorY: number,
}

type Box = {
	AlongMinimum: number,
	AlongMaximum: number,
	AcrossMinimum: number,
	AcrossMaximum: number,
	VerticalMinimum: number,
	VerticalMaximum: number,
}

type DamageRegion = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfWidth: number,
	FloorY: number,
	HeightWindow: number,
	BelowWindow: number,
	Lethal: { Interval },
	Alcoves: { Alcove },
	Seals: { SealRegion },
	AlcoveMargin: number,
	AlongMargin: number,
}

type Region = DamageRegion & {
	ClearHalfWidth: number,
	KillWidth: number,
	MinimumHRPOverlap: number,
	MaximumOffset: number,
	CloseTime: number,
	StartedAt: number,
}

local SAMPLE_AXIS = 7

local function inBox(box: Box, along: number, across: number, vertical: number): boolean
	return along >= box.AlongMinimum
		and along <= box.AlongMaximum
		and across >= box.AcrossMinimum
		and across <= box.AcrossMaximum
		and vertical >= box.VerticalMinimum
		and vertical <= box.VerticalMaximum
end

function HallwayCrushDamageService.GetSquishFraction(root: BasePart, region: DamageRegion, slack: number): number
	local lethal: { Box } = {}
	local safe: { Box } = {}
	local verticalMinimum = region.FloorY - region.BelowWindow
	local verticalMaximum = region.FloorY + region.HeightWindow

	for _, interval in region.Lethal do
		table.insert(lethal, {
			AlongMinimum = interval.Minimum - slack,
			AlongMaximum = interval.Maximum + slack,
			AcrossMinimum = -region.HalfWidth,
			AcrossMaximum = region.HalfWidth,
			VerticalMinimum = verticalMinimum,
			VerticalMaximum = verticalMaximum,
		})
	end

	for _, alcove in region.Alcoves do
		local acrossMinimum = if alcove.Sign > 0 then -region.AlcoveMargin else -alcove.Outer - region.AlcoveMargin
		local acrossMaximum = if alcove.Sign > 0 then alcove.Outer + region.AlcoveMargin else region.AlcoveMargin
		table.insert(safe, {
			AlongMinimum = alcove.Along - alcove.HalfWidth - region.AlongMargin,
			AlongMaximum = alcove.Along + alcove.HalfWidth + region.AlongMargin,
			AcrossMinimum = acrossMinimum,
			AcrossMaximum = acrossMaximum,
			VerticalMinimum = region.FloorY - region.AlcoveMargin,
			VerticalMaximum = alcove.Top,
		})
	end

	if #lethal == 0 then return 0 end

	local trapped = 0
	local total = SAMPLE_AXIS ^ 3
	local size = root.Size
	for x = 1, SAMPLE_AXIS do
		local localX = ((x - 0.5) / SAMPLE_AXIS - 0.5) * size.X
		for y = 1, SAMPLE_AXIS do
			local localY = ((y - 0.5) / SAMPLE_AXIS - 0.5) * size.Y
			for z = 1, SAMPLE_AXIS do
				local localZ = ((z - 0.5) / SAMPLE_AXIS - 0.5) * size.Z
				local position = root.CFrame:PointToWorldSpace(Vector3.new(localX, localY, localZ))
				local relative = position - region.Center
				local along = relative:Dot(region.Axis)
				local across = relative:Dot(region.Across)

				local isLethal = false
				for _, box in lethal do
					if inBox(box, along, across, position.Y) then
						isLethal = true
						break
					end
				end
				if not isLethal then
					for _, seal in region.Seals do
						local sealRelative = position - seal.Center
						local sealAlong = sealRelative:Dot(seal.Axis)
						local sealAcross = sealRelative:Dot(seal.Across)
						if sealAlong >= seal.Minimum
							and sealAlong <= seal.Maximum
							and math.abs(sealAcross - seal.Plane) <= seal.Depth
							and position.Y >= verticalMinimum
							and position.Y <= verticalMaximum
						then
							isLethal = true
							break
						end
					end
				end
				if not isLethal then continue end

				local isSafe = false
				for _, box in safe do
					if inBox(box, along, across, position.Y) then
						isSafe = true
						break
					end
				end
				if not isSafe then trapped += 1 end
			end
		end
	end

	return trapped / total
end

if not RunService:IsClient() then
	return HallwayCrushDamageService
end

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local MapCrush = CommunicationService.Get("Oddities", "MapCrush") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local Regions: { [number]: Region } = {}
local Reported: { [number]: true } = {}

local function currentOffset(region: Region): number
	local elapsed = math.clamp(workspace:GetServerTimeNow() - region.StartedAt, 0, region.CloseTime)
	local alpha = elapsed / region.CloseTime
	return region.MaximumOffset * alpha * alpha * (3 - 2 * alpha)
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
		if HallwayCrushDamageService.GetSquishFraction(root, region, 0) < region.MinimumHRPOverlap then continue end

		Reported[token] = true
		MapCrush:FireServer("Crushed", token)
	end
end)

return HallwayCrushDamageService
