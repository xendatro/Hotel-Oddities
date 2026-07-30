--- Finds the furthest place from everybody that nobody can see: what something that has just been
--- caught being looked at needs, which is to be somewhere else entirely.
---
--- The search space is the floor parts tagged `MazeFloor`, and that tag is doing two jobs. It saves
--- sampling a thousand loose parts to work out which of them are standable, and -- while the maze still
--- leaks at the edges -- it is what keeps something running away from running out of the building. Only
--- tagged floor is a candidate, so wherever the tag stops, fleeing stops.
---
--- Candidates are scored on distance to the nearest pair of eyes, which is the whole of what "as far
--- away as it can get" means with people scattered around a maze, and the best of them are then checked
--- properly: a figure has to fit there, and nobody may be able to see one standing there. Scoring is
--- arithmetic and checking is raycasts, so the order matters -- only the top handful ever get cast at.
---
--- Eyes come from `EnemyObservationService`, which means real reported camera positions rather than a
--- guess at where a head is. That is the difference between hiding behind something and hiding behind
--- something the camera is looking over the top of.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)

local ENEMY_TAG = "Enemy"
local MAZE_FLOOR_TAG = "MazeFloor" -- every floor part something is allowed to flee onto

local STANDING_HEIGHT = 5 -- studs of headroom a figure needs to stand somewhere unclipped
local STANDING_CLEARANCE = 0.5 -- studs of the box held off the floor, so the floor is not an overlap
-- Studs above a candidate a hider is tested for being visible at. Head and shin, because a spot behind
-- a bed hides a body and not a head, and either one showing is being seen.
local SAMPLE_HEIGHTS = { 4.5, 1 }
local FLOOR_PROBE_UP = 4 -- studs above a candidate the floor probe starts at
local FLOOR_PROBE_DOWN = 8 -- and how far down it looks from there
local MAX_FLOOR_DROP = 3 -- studs between the tagged floor and what is actually standable there
local AREA_PER_SAMPLE = 400 -- square studs of floor each candidate stands in for: a 20x20 patch
local MAX_SAMPLES_PER_PART = 24 -- so one enormous baseplate cannot eat the whole budget
local CANDIDATE_LIMIT = 400 -- scored candidates; cheap, but not free
local VERIFY_LIMIT = 24 -- how many of the best ones earn the raycasts

local HideSpotService = {}

local warnedAboutTag = false

-- Everything that must not read as cover: no character or enemy should hide anything, least of all the
-- one doing the hiding.
local function buildFilter(): { Instance }
	local filter = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		table.insert(filter, model)
	end
	return filter
end

-- The tagged floor, shuffled. Shuffled because the candidate budget runs out long before a real maze
-- does, and taking the first four hundred samples off the front of the list would mean the far end of
-- the building never gets considered -- which is precisely the end worth running to.
local function getFloors(): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") then
			table.insert(floors, instance)
		end
	end

	for index = #floors, 2, -1 do
		local swap = math.random(index)
		floors[index], floors[swap] = floors[swap], floors[index]
	end
	return floors
end

-- A random point on `part`'s top face, held a body's width in from the edges so a candidate is not
-- half inside whatever is standing along the floor's border.
local function samplePoint(part: BasePart, agentRadius: number): Vector3
	local half = part.Size / 2
	local x = (math.random() * 2 - 1) * math.max(half.X - agentRadius, 0)
	local z = (math.random() * 2 - 1) * math.max(half.Z - agentRadius, 0)
	return part.CFrame * Vector3.new(x, half.Y, z)
end

local function distanceToNearest(eyes: { Vector3 }, point: Vector3): number
	local nearest = math.huge
	for _, eye in eyes do
		nearest = math.min(nearest, (eye - point).Magnitude)
	end
	return nearest
end

-- The floor position a figure could actually stand on at `position`, or nil where one could not: the
-- tagged floor turned out to have something on it, or there is no room to stand.
--
-- The room it insists on is the agent's own width rather than a body's, and that is the whole point of
-- taking a radius. The navmesh holds walkable ground that far off every wall, so a spot any tighter
-- than the agent is a spot the pathfinder will not route to -- and an unreachable hiding place is not a
-- near miss, it is a dead stop in the middle of a corridor while three paths fail to compute.
local function findStanding(
	params: RaycastParams,
	overlap: OverlapParams,
	position: Vector3,
	agentRadius: number
): Vector3?
	local from = position + Vector3.new(0, FLOOR_PROBE_UP, 0)
	local result = workspace:Raycast(from, Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0), params)
	if not result or math.abs(result.Position.Y - position.Y) > MAX_FLOOR_DROP then return nil end

	local size = Vector3.new(agentRadius * 2, STANDING_HEIGHT, agentRadius * 2)
	local centre = result.Position + Vector3.new(0, STANDING_HEIGHT / 2 + STANDING_CLEARANCE, 0)
	if #workspace:GetPartBoundsInBox(CFrame.new(centre), size, overlap) > 0 then return nil end
	return result.Position
end

-- Whether any of `eyes` could make out a figure standing on `floorPosition`.
local function isVisible(params: RaycastParams, eyes: { Vector3 }, floorPosition: Vector3): boolean
	for _, height in SAMPLE_HEIGHTS do
		local point = floorPosition + Vector3.new(0, height, 0)
		for _, eye in eyes do
			local direction = point - eye
			if direction.Magnitude < 1e-3 or workspace:Raycast(eye, direction, params) == nil then
				return true
			end
		end
	end
	return false
end

--- The furthest floor position from every living player that a figure could stand on unseen, or nil
--- when none of the tagged floor offers one. Returns a floor position, which is what pathfinding and
--- `Humanoid:MoveTo` want.
---
--- `agentRadius` is the caller's own `AgentParams.AgentRadius`, and passing anything else is asking for
--- somewhere it cannot get to: every candidate has to have that much room around it, because that is
--- what the navmesh the caller will path over was built with.
---
--- A few hundred cheap candidates and a few dozen raycasts, on the calling thread. Ask once per
--- retreat, not once per frame.
function HideSpotService:Find(agentRadius: number): Vector3?
	local floors = getFloors()
	if #floors == 0 then
		if not warnedAboutTag then
			warnedAboutTag = true
			warn(`[enemies] nothing is tagged {MAZE_FLOOR_TAG}, so nothing can find anywhere to hide`)
		end
		return nil
	end

	local eyes = EnemyObservationService:GetEyes()

	local candidates = {}
	for _, part in floors do
		local samples = math.clamp(
			math.floor(part.Size.X * part.Size.Z / AREA_PER_SAMPLE),
			1,
			MAX_SAMPLES_PER_PART
		)
		for _ = 1, samples do
			local point = samplePoint(part, agentRadius)
			table.insert(candidates, { Point = point, Score = distanceToNearest(eyes, point) })
		end
		if #candidates >= CANDIDATE_LIMIT then break end
	end

	table.sort(candidates, function(a, b)
		return a.Score > b.Score
	end)

	local filter = buildFilter()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = filter
	overlap.RespectCanCollide = true

	-- Furthest first, and the first one that holds up wins. Anything past `VERIFY_LIMIT` is close
	-- enough to somebody that it is not worth the rays -- another sample of the maze next time round
	-- will do better than the fiftieth-best spot of this one.
	for index = 1, math.min(#candidates, VERIFY_LIMIT) do
		local floorPosition = findStanding(params, overlap, candidates[index].Point, agentRadius)
		if floorPosition and not isVisible(params, eyes, floorPosition) then
			return floorPosition
		end
	end
	return nil
end

return HideSpotService
