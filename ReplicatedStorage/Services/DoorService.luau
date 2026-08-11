local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DoorService = {}

if not RunService:IsClient() then
	return DoorService
end

local DoorConfig = require(ReplicatedStorage.Configs.DoorConfig)
local DoorPart = require(ReplicatedStorage.Classes.DoorPart)
local TagService = require(ReplicatedStorage.Services.TagService)

-- Every live slab, stepped together. Doors are animated locally, so this runs against ALL players'
-- characters rather than just the local one: a door another player walks through has to open here
-- too, or two clients disagree about the hotel.
local Active: { [any]: true } = {}
local sincePoll = 0

local function livingPositions(): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

-- Walks up to the model the slab belongs to, and answers whether that model is one this system owns.
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

local function poll()
	local positions = livingPositions()

	for door in Active do
		local center = door.Center
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

-- Keyed off the slab rather than the model around it: a model may hold two slabs that each need
-- their own swing, and the model's own tags are shared with other systems.
TagService:Listen("DoorPart", function(part: BasePart)
	if not inSwingingDoorway(part) then return end

	local door = DoorPart.new(part)
	Active[door] = true
	return door
end, function(_, door)
	if not door then return end
	Active[door] = nil
	door:Destroy()
end, workspace)

return DoorService
