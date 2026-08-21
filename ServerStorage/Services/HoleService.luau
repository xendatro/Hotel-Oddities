local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local Other = ReplicatedStorage.Props.Other

local MAZE_FLOOR_TAG = "MazeFloor"
local HOLE_TAG = "Hole"
local CREATOR_ATTRIBUTE = "CreatorUserId"
local HOLE_LIFETIME = 30
local MAX_HOLE_PAIRS = 5

local HoleService = {}

type HolePair = {
	Models: { Model },
	Owner: Player?,
}

local Pairs: { HolePair } = {}

local function destroyPair(pair: HolePair)
	for _, hole in pair.Models do
		hole:Destroy()
	end
end

local function removePair(pair: HolePair)
	local index = table.find(Pairs, pair)
	if index then table.remove(Pairs, index) end
	destroyPair(pair)
end

local function getMazeFloors(): { BasePart }
	local floors = {}
	for _, instance in TagService:GetTaggedOfAncestor(workspace, MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") then
			table.insert(floors, instance)
		end
	end
	return floors
end

local function pickExit(): Vector3?
	local floors = getMazeFloors()
	if #floors == 0 then
		warn(`HoleService: no parts tagged "{MAZE_FLOOR_TAG}" -- nowhere to put a hole`)
		return nil
	end

	local floor = floors[math.random(1, #floors)]
	local size = floor.Size
	local offset = Vector3.new(
		(math.random() - 0.5) * size.X,
		size.Y / 2 + 0.5,
		(math.random() - 0.5) * size.Z
	)
	return floor.CFrame:PointToWorldSpace(offset)
end

function HoleService:CreateHolePair(entryPosition: Vector3, owner: Player?): boolean
	local exitPosition = pickExit()
	if not exitPosition then return false end

	local template = Other:FindFirstChild("Hole")
	if not template then
		warn("HoleService: no Hole model in ReplicatedStorage.Props.Other")
		return false
	end

	local id = HttpService:GenerateGUID()
	local x, y, z = template:GetPivot():ToOrientation()
	local orientation = CFrame.fromOrientation(x, y, z)

	local entry = template:Clone()
	local exit = template:Clone()

	entry:SetAttribute("ID", id)
	exit:SetAttribute("ID", id)
	entry:SetAttribute(CREATOR_ATTRIBUTE, if owner then owner.UserId else nil)
	exit:SetAttribute(CREATOR_ATTRIBUTE, if owner then owner.UserId else nil)
	entry:PivotTo(CFrame.new(entryPosition) * orientation)
	exit:PivotTo(CFrame.new(exitPosition) * orientation)
	entry.Parent = workspace
	exit.Parent = workspace

	local pair: HolePair = {
		Models = { entry, exit },
		Owner = owner,
	}
	table.insert(Pairs, pair)
	task.delay(HOLE_LIFETIME, function()
		removePair(pair)
	end)

	while #Pairs > MAX_HOLE_PAIRS do
		local oldest = table.remove(Pairs, 1)
		if oldest then
			destroyPair(oldest)
		end
	end

	return true
end

function HoleService:RemoveForPlayer(player: Player)
	for index = #Pairs, 1, -1 do
		local pair = Pairs[index]
		if pair.Owner == player or (pair.Owner and pair.Owner.UserId == player.UserId) then
			table.remove(Pairs, index)
			destroyPair(pair)
		end
	end

	for _, hole in TagService:GetTaggedOfAncestor(workspace, HOLE_TAG) do
		if hole:GetAttribute(CREATOR_ATTRIBUTE) == player.UserId then
			hole:Destroy()
		end
	end
end

ReplicatedStorage.Communication.Hole.Create.OnServerInvoke = function(player: Player, entryPosition: any)
	if typeof(entryPosition) ~= "Vector3" then return false end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	if (root.Position - entryPosition).Magnitude > ToolConfigs.Shovel.MaxDigDistance then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = getMazeFloors()
	if #params.FilterDescendantsInstances == 0 then return false end

	local ground = workspace:Raycast(root.Position, Vector3.new(0, -ToolConfigs.Shovel.DigDepth, 0), params)
	if not ground then return false end

	return HoleService:CreateHolePair(ground.Position + Vector3.new(0, 0.5, 0), player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	HoleService:RemoveForPlayer(player)
end)

return HoleService
