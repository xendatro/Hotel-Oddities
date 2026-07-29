local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local GHOST_AREA_TAG = "GhostArea"

--- Owns the `GhostArea` tag: the volumes a `Ghost` is allowed to drift through. Areas are plain
--- block parts in workspace and nothing is attached to them, so this reads CollectionService
--- directly rather than holding a tag listener. A ghost travels in straight lines between points
--- and does not pathfind, so overlapping boxes are the only thing keeping it out of the void --
--- tag every space it may cross, not just the rooms it should end up in.
local GhostAreaService = {}

-- Studs cubed, used to weight the pick so a long corridor is not chosen as often as a closet.
local function getVolume(part: BasePart): number
	return part.Size.X * part.Size.Y * part.Size.Z
end

local function getRandomPointIn(part: BasePart): Vector3
	local half = part.Size / 2
	return part.CFrame:PointToWorldSpace(Vector3.new(
		(math.random() * 2 - 1) * half.X,
		(math.random() * 2 - 1) * half.Y,
		(math.random() * 2 - 1) * half.Z
	))
end

--- Every part currently tagged as a ghost area.
function GhostAreaService:GetAreas(): { BasePart }
	return TagService:GetTaggedOfAncestor(workspace, GHOST_AREA_TAG) :: any
end

--- A random point inside a random area, weighted by volume. Nil while nothing is tagged.
function GhostAreaService:GetRandomPoint(): Vector3?
	local areas = self:GetAreas()
	if #areas == 0 then return nil end

	local total = 0
	for _, part in areas do
		total += getVolume(part)
	end

	local roll = math.random() * total
	for _, part in areas do
		roll -= getVolume(part)
		if roll <= 0 then
			return getRandomPointIn(part)
		end
	end
	return getRandomPointIn(areas[#areas])
end

return GhostAreaService
