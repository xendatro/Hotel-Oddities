local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

local Other = ReplicatedStorage.Props.Other

local MAZE_FLOOR_TAG = "MazeFloor"
local HOLE_LIFETIME = 30
local MAX_HOLE_PAIRS = 5

--- Owns the holes the shovel digs. A dig produces a *pair* sharing an `ID` attribute: the entry
--- where the player was standing and an exit somewhere on a part tagged `MazeFloor`. Crawling
--- into one surfaces at its twin (see the `Hole` class on the client). Pairs expire on a timer and
--- the oldest is culled once the world holds too many.
local HoleService = {}

local Pairs: { { Model } } = {}

-- Every tagged maze-floor part. Kept as a function because streamed/authored map pieces may change.
local function getMazeFloors(): { BasePart }
	local floors = {}
	for _, instance in TagService:GetTaggedOfAncestor(workspace, MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") then
			table.insert(floors, instance)
		end
	end
	return floors
end

-- A random point on top of a randomly chosen maze-floor part, or nil if the place has none.
local function pickExit(): Vector3?
	local floors = getMazeFloors()
	if #floors == 0 then
		warn(`HoleService: no parts tagged "{MAZE_FLOOR_TAG}" -- the shovel has nowhere to surface`)
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

--- Cuts an entry/exit pair, returning whether it succeeded.
function HoleService:CreateHolePair(entryPosition: Vector3): boolean
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
	entry:PivotTo(CFrame.new(entryPosition) * orientation)
	exit:PivotTo(CFrame.new(exitPosition) * orientation)
	entry.Parent = workspace
	exit.Parent = workspace

	Debris:AddItem(entry, HOLE_LIFETIME)
	Debris:AddItem(exit, HOLE_LIFETIME)

	table.insert(Pairs, { entry, exit })
	while #Pairs > MAX_HOLE_PAIRS do
		local oldest = table.remove(Pairs, 1)
		if oldest then
			for _, hole in oldest do
				hole:Destroy()
			end
		end
	end

	return true
end

ReplicatedStorage.Communication.Hole.Create.OnServerInvoke = function(player: Player, entryPosition: any)
	if typeof(entryPosition) ~= "Vector3" then return false end

	-- The client picks the entry point off its own raycast, so check it against where the player
	-- actually is before cutting anything.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	if (root.Position - entryPosition).Magnitude > ToolConfigs.Shovel.MaxDigDistance then return false end

	-- Rebuild the entry from the server's own MazeFloor raycast. The client chooses where the dummy
	-- appears, but cannot cut a real hole into an untagged prop or through a forged remote call.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = getMazeFloors()
	if #params.FilterDescendantsInstances == 0 then return false end

	local ground = workspace:Raycast(root.Position, Vector3.new(0, -ToolConfigs.Shovel.DigDepth, 0), params)
	if not ground then return false end

	return HoleService:CreateHolePair(ground.Position + Vector3.new(0, 0.5, 0))
end

return HoleService
