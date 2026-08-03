local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

--- Owns where a `Ghost` is allowed to be: the air over the hotel.
---
--- There is nothing to author. The region is the parts tagged `MazeFloor` -- the same corridors
--- everything else walks -- padded outwards by `DriftMargin` and lifted to `HoverHeight` over the
--- floor. A ghost travels in straight lines through walls, so corridors plus a margin is a region it
--- can cross freely, and one that follows the building rather than a box drawn around it: the outer
--- edge of the drift region is the outer edge of the hotel with a little air past it, which is what
--- lets one occasionally be seen floating outside a window.
---
--- Height comes from the floor nearest wherever it is headed rather than from the region, so a ghost
--- sits at one honest height above the ground instead of anywhere in a volume. Flat by construction,
--- and the same flat over every storey the hotel grows.
local GhostAreaService = {}

local Config = EnemyConfigs.Ghost

-- Square studs of air over one corridor, used to weight the pick so a long hallway is chosen more
-- often than a short one. Padded, because the margin is part of what is being drawn from -- without
-- it a stub of corridor would be picked as often as its own doorway is wide.
local function getArea(hallway: Hallways.Hallway): number
	return 4 * (hallway.HalfLength + Config.DriftMargin) * (hallway.HalfWidth + Config.DriftMargin)
end

-- A random point over `hallway`, out to the margin on every side, at floor level. The margin is
-- applied in the corridor's own frame, so it reaches out past the walls rather than past whichever
-- way the hallway happens to run.
local function getRandomPointOver(hallway: Hallways.Hallway): Vector3
	local surface = Vector3.new(hallway.Center.X, hallway.FloorY, hallway.Center.Z)
	local along = (math.random() * 2 - 1) * (hallway.HalfLength + Config.DriftMargin)
	local across = (math.random() * 2 - 1) * (hallway.HalfWidth + Config.DriftMargin)
	return surface + hallway.Axis * along + hallway.Across * across
end

--- Somewhere a ghost may drift to: a random point over a random corridor, weighted by area, at
--- hovering height above the floor nearest it. Nil while nothing is tagged `MazeFloor`.
function GhostAreaService:GetRandomPoint(): Vector3?
	local hallways = Hallways.All()
	if #hallways == 0 then return nil end

	local total = 0
	for _, hallway in hallways do
		total += getArea(hallway)
	end

	local chosen = hallways[#hallways]
	local roll = math.random() * total
	for _, hallway in hallways do
		roll -= getArea(hallway)
		if roll <= 0 then
			chosen = hallway
			break
		end
	end

	-- Out in the margin the nearest floor is not always the corridor the point was drawn over -- it
	-- can be the one on the other side of the wall it has drifted through, or none nearer than the
	-- one it came from, out beyond the building. Asking again is what keeps the height honest there.
	local point = getRandomPointOver(chosen)
	local floor = Hallways.Nearest(point) or chosen
	return Vector3.new(point.X, floor.FloorY + Config.HoverHeight, point.Z)
end

return GhostAreaService
