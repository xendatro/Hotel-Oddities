local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DoorConfig = require(ReplicatedStorage.Configs.DoorConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local DoorService = {}

local Active: { [BasePart]: true } = {}
local sincePoll = 0

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

local function nearestPlayer(part: BasePart): Vector3?
	local nearest: Vector3? = nil
	local nearestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local position = CharacterService.GetPosition(player)
		if position then
			local distance = (position - part.Position).Magnitude
			if distance < nearestDistance then
				nearest = position
				nearestDistance = distance
			end
		end
	end

	return nearest
end

local function poll()
	for part in Active do
		local wasOpen = part:GetAttribute(DoorConfig.OpenAttribute) == true
		local position = nearestPlayer(part)
		local limit = if wasOpen then DoorConfig.CloseDistance else DoorConfig.OpenDistance
		local open = position ~= nil and (position - part.Position).Magnitude <= limit

		if open ~= wasOpen then
			part:SetAttribute(DoorConfig.OpenAttribute, open)
			part:SetAttribute(DoorConfig.OpenFromAttribute, if open then position else nil)
		elseif not open and part:GetAttribute(DoorConfig.OpenFromAttribute) ~= nil then
			part:SetAttribute(DoorConfig.OpenFromAttribute, nil)
		end
	end
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	sincePoll += deltaTime
	if sincePoll < DoorConfig.PollInterval then return end
	sincePoll %= DoorConfig.PollInterval
	poll()
end)

TagService:Listen("DoorPart", function(part: BasePart)
	if not part:IsA("BasePart") or not inSwingingDoorway(part) then return end
	Active[part] = true
	if part:GetAttribute(DoorConfig.OpenAttribute) == nil then
		part:SetAttribute(DoorConfig.OpenAttribute, false)
	end
	return true
end, function(part)
	if part:IsA("BasePart") then
		Active[part] = nil
	end
end, workspace)

poll()

return DoorService
