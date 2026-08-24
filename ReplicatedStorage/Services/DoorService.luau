local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DoorService = {}

if not RunService:IsClient() then
	return DoorService
end

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local DoorConfig = require(ReplicatedStorage.Configs.DoorConfig)
local DoorPart = require(ReplicatedStorage.Classes.DoorPart)
local TagService = require(ReplicatedStorage.Services.TagService)

local MapDoors = CommunicationService.Get("Oddities", "MapDoors")

local Active: { [any]: true } = {}
local DoorwayCache: { [BasePart]: Model | false } = {}
local sincePoll = 0

type MapOpening = {
	CFrame: CFrame,
	Size: Vector3,
	Speed: number,
	Mode: string?,
	CloseSpeed: number?,
	IntervalMin: number?,
	IntervalMax: number?,
}

local MapOpenings: { [number]: MapOpening } = {}

local function enemyPositions(): ({ Vector3 }, { [string]: boolean })
	local positions = {}
	local forcedDoorways = {}
	for _, model in CollectionService:GetTagged(DoorConfig.EnemyTag) do
		if model:IsA("Model") then
			table.insert(positions, model:GetPivot().Position)
			local doorwayName = model:GetAttribute("ForcedDoorway")
			if typeof(doorwayName) == "string" then
				forcedDoorways[doorwayName] = true
			end
		end
	end
	return positions, forcedDoorways
end

local function nearestTo(positions: { Vector3 }, center: Vector3): (Vector3?, number)
	local nearest: Vector3? = nil
	local nearestDistance = math.huge

	for _, position in positions do
		if math.abs(position.Y - center.Y) > DoorConfig.MaxHeightDifference then continue end

		local distance = (position - center).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = position
		end
	end

	return nearest, nearestDistance
end

local function inSwingingDoorway(part: BasePart): boolean
	local instance: Instance? = part.Parent

	while instance and instance ~= workspace do
		local matched = true
		for _, tag in DoorConfig.DoorwayTags do
			if not instance:HasTag(tag) then
				matched = false
				break
			end
		end
		if matched then return true end

		instance = instance.Parent
	end

	return false
end

local function doorwayFor(part: BasePart): Model?
	local cached = DoorwayCache[part]
	if cached ~= nil then
		return if cached then cached else nil
	end

	local instance: Instance? = part.Parent
	while instance and instance ~= workspace do
		if instance:IsA("Model") and instance:HasTag("Doorway") and instance:HasTag("RoomDoor") then
			DoorwayCache[part] = instance
			return instance
		end
		instance = instance.Parent
	end
	DoorwayCache[part] = false
	return nil
end

local function isDoorInOpening(door, opening: MapOpening): boolean
	local offset = opening.CFrame:PointToObjectSpace(door.Part.Position)
	local half = opening.Size / 2
	return math.abs(offset.X) <= half.X
		and math.abs(offset.Y) <= half.Y
		and math.abs(offset.Z) <= half.Z
end

local function applyOpening(door, token: number, opening: MapOpening)
	if isDoorInOpening(door, opening) then
		if opening.Mode == "Chaos" then
			door:SetOddityChaos(
				token,
				opening.Speed,
				opening.CloseSpeed or opening.Speed,
				opening.IntervalMin or 0.3,
				opening.IntervalMax or 1.1
			)
		else
			door:SetOddityOpen(token, opening.Speed)
		end
	end
end

if MapDoors and MapDoors:IsA("RemoteEvent") then
	(MapDoors :: RemoteEvent).OnClientEvent:Connect(function(
		action: any,
		token: any,
		boxCFrame: any,
		boxSize: any,
		speed: any,
		mode: any,
		closeSpeed: any,
		intervalMin: any,
		intervalMax: any
	)
		if type(token) ~= "number" then return end

		if action == "Start" then
			if typeof(boxCFrame) ~= "CFrame" or typeof(boxSize) ~= "Vector3" or type(speed) ~= "number" then
				return
			end

			local previous = MapOpenings[token]
			if previous then
				for door in Active do
					door:ClearOddity(token)
				end
			end

			local opening: MapOpening = {
				CFrame = boxCFrame,
				Size = boxSize,
				Speed = math.clamp(speed, 0.05, 4),
				Mode = if mode == "Chaos" then "Chaos" else nil,
				CloseSpeed = if type(closeSpeed) == "number" then math.clamp(closeSpeed, 0.05, 4) else nil,
				IntervalMin = if type(intervalMin) == "number" then math.max(intervalMin, 0.05) else nil,
				IntervalMax = if type(intervalMax) == "number" then math.max(intervalMax, 0.06) else nil,
			}
			MapOpenings[token] = opening
			for door in Active do
				applyOpening(door, token, opening)
			end
		elseif action == "Stop" then
			if not MapOpenings[token] then return end
			MapOpenings[token] = nil
			for door in Active do
				door:ClearOddity(token)
			end
		end
	end)
end

local function poll()
	local playerPosition = CharacterService.GetPosition(Players.LocalPlayer)
	local enemies, forcedDoorways = enemyPositions()

	for door in Active do
		local center = door.Center

		local enemyPosition, enemyDistance = nearestTo(enemies, center)
		local forceLimit = door.Forced and DoorConfig.EnemyReleaseDistance or DoorConfig.EnemyForceDistance
		local doorway = doorwayFor(door.Part)
		local forceForReaction = doorway ~= nil and forcedDoorways[doorway.Name] == true
		local lockedFromInside = playerPosition ~= nil
			and door:IsInside(playerPosition :: Vector3)
			and (forceForReaction or enemyDistance <= forceLimit)
		door:SetForced(lockedFromInside)

		local nearest = playerPosition
		local nearestDistance = if playerPosition then (playerPosition - center).Magnitude else math.huge
		if not lockedFromInside and enemyPosition and enemyDistance < nearestDistance then
			nearest, nearestDistance = enemyPosition, enemyDistance
		end
		local limit = door:IsOpen() and DoorConfig.CloseDistance or DoorConfig.OpenDistance
		door:SetOpen(nearest ~= nil and nearestDistance <= limit, nearest)
	end
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	sincePoll += deltaTime
	if sincePoll >= DoorConfig.PollInterval then
		sincePoll = 0
		poll()
	end

	for door in Active do
		door:Step(deltaTime)
	end
end)

TagService:Listen("DoorPart", function(part: BasePart)
	if not inSwingingDoorway(part) then return end

	local door = DoorPart.new(part)
	Active[door] = true
	for token, opening in MapOpenings do
		applyOpening(door, token, opening)
	end
	return door
end, function(part, door)
	if part:IsA("BasePart") then
		DoorwayCache[part] = nil
	end
	if not door then return end
	Active[door] = nil
	door:Destroy()
end, workspace)

return DoorService
