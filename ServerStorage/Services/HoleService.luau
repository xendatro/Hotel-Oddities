local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Other = ReplicatedStorage.Props.Other

local HOLE_AREA_TAG = "HoleArea" -- parts marking floor a dug hole is allowed to surface in
local HOLE_LIFETIME = 30
local MAX_HOLE_PAIRS = 5

--- Owns the holes the shovel digs. A dig produces a *pair* sharing an `ID` attribute: the entry
--- where the player was standing and an exit somewhere inside a part tagged `HoleArea`. Crawling
--- into one surfaces at its twin (see the `Hole` class on the client). Pairs expire on a timer and
--- the oldest is culled once the world holds too many.
local HoleService = {}

local Pairs: { { Model } } = {}

-- A random point on the floor of a randomly chosen hole area, or nil if the place has none.
local function pickExit(): Vector3?
	local areas = TagService:GetTaggedOfAncestor(workspace, HOLE_AREA_TAG)
	if #areas == 0 then
		warn(`HoleService: no parts tagged "{HOLE_AREA_TAG}" -- the shovel has nowhere to surface`)
		return nil
	end

	local area = areas[math.random(1, #areas)] :: BasePart
	local size = area.Size
	local offset = Vector3.new(
		(math.random() - 0.5) * size.X,
		0.5,
		(math.random() - 0.5) * size.Z
	)
	return area.Position + offset
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
	if (root.Position - entryPosition).Magnitude > 10 then return false end

	return HoleService:CreateHolePair(entryPosition)
end

return HoleService
