--- Finds somewhere nearby that nobody can see: what something caught being looked at needs, which is
--- to be out of sight rather than far away. Breaking the sight line is the whole job -- once nobody
--- can see it, it is free to leave -- so a spot around the next corner is worth more than the far end
--- of the building, and costs a fraction of the search.
---
--- The search space is the floor parts tagged `MazeFloor`, and that tag is doing two jobs. It saves
--- sampling a thousand loose parts to work out which of them are standable, and -- while the maze still
--- leaks at the edges -- it is what keeps something running away from running out of the building. Only
--- tagged floor is a candidate, so wherever the tag stops, fleeing stops.
---
--- Candidates are drawn from the ring of floor within `Range` of where the runner is standing, and only
--- ones that lead *away* survive: a spot has to open ground on the nearest pair of eyes and lie off the
--- direction those eyes are in, so nothing ever hides by running through the person looking at it. The
--- survivors are scored on cover gained against ground covered, and the best handful are then checked
--- properly: a figure has to fit there, and nobody may be able to see one standing there. Scoring is
--- arithmetic and checking is raycasts, so the order matters -- only the top few ever get cast at.
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
local AREA_PER_SAMPLE = 200 -- square studs of floor each candidate stands in for: a 14x14 patch
local MAX_SAMPLES_PER_PART = 12 -- so one enormous baseplate cannot eat the whole budget
local CANDIDATE_LIMIT = 120 -- scored candidates; cheap, but not free
local VERIFY_LIMIT = 10 -- how many of the best ones earn the raycasts

local DEFAULT_RANGE = 70 -- studs of floor searched around the runner when a caller names no range
local DEFAULT_MIN_DISTANCE = 12 -- and how near a spot has to be before it is just where it already was
local MIN_EYE_CLEARANCE = 16 -- studs a hiding place must be off everybody, whatever else recommends it
local RETREAT_GAIN = 4 -- studs a spot must open on the closest watcher, so a retreat is never lateral
-- How far round from "directly towards the nearest eyes" a retreat is allowed to set off. A cosine, so
-- 0.15 is a little inside a right angle: sideways is fine, past them is not.
local MAX_TOWARDS_DOT = 0.15
local TRAVEL_WEIGHT = 0.6 -- studs of cover one stud of running has to be worth to be picked over it
-- How far behind the way it is already going a spot may be before carrying on stops meaning anything.
-- A cosine again: -0.5 is a hundred and twenty degrees, so corners and switchbacks are still on and
-- turning round in the corridor is not.
local MIN_HEADING_DOT = -0.5
local HEADING_WEIGHT = 10 -- and what staying on course is worth in studs, against everything else

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

-- The tagged floor with anything out of reach dropped, shuffled. Shuffled because the candidate budget
-- can still run out in a busy area, and taking the samples off the front of the list would mean one
-- side of the ring never gets considered.
local function getFloors(origin: Vector3, range: number): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart")
			and (instance.Position - origin).Magnitude - instance.Size.Magnitude / 2 <= range
		then
			table.insert(floors, instance)
		end
	end

	for index = #floors, 2, -1 do
		local swap = math.random(index)
		floors[index], floors[swap] = floors[swap], floors[index]
	end
	return floors
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Random points on `part`'s top face, held a body's width in from the edges so a candidate is not half
-- inside whatever stands along the floor's border, and clipped to the square around `origin`. The
-- clipping is what makes a maze-sized baseplate cost the same as a corridor tile: without it, most of
-- a big part's samples land somewhere the runner was never going to run to and are thrown away.
local function sampleFace(part: BasePart, origin: Vector3, range: number, agentRadius: number): { Vector3 }
	local half = part.Size / 2
	local centre = part.CFrame:PointToObjectSpace(origin)

	local minX = math.max(-half.X + agentRadius, centre.X - range)
	local maxX = math.min(half.X - agentRadius, centre.X + range)
	local minZ = math.max(-half.Z + agentRadius, centre.Z - range)
	local maxZ = math.min(half.Z - agentRadius, centre.Z + range)
	if minX > maxX or minZ > maxZ then return {} end

	local count = math.clamp(
		math.floor((maxX - minX) * (maxZ - minZ) / AREA_PER_SAMPLE),
		1,
		MAX_SAMPLES_PER_PART
	)

	local points = {}
	for _ = 1, count do
		local x = minX + math.random() * (maxX - minX)
		local z = minZ + math.random() * (maxZ - minZ)
		table.insert(points, part.CFrame * Vector3.new(x, half.Y, z))
	end
	return points
end

-- Distance to the closest of `eyes`, and which one that was.
local function nearestEye(eyes: { Vector3 }, point: Vector3): (number, Vector3?)
	local nearest, which = math.huge, nil :: Vector3?
	for _, eye in eyes do
		local distance = (eye - point).Magnitude
		if distance < nearest then
			nearest, which = distance, eye
		end
	end
	return nearest, which
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

export type FindOptions = {
	Range: number?, -- studs of floor around `origin` to consider; how far it is willing to run
	MinDistance: number?, -- and how far it must go, so a retreat is never a shuffle on the spot
	-- The way the caller is already going, if it is going anywhere. A retreat is usually several of
	-- these one after another -- reaching cover while somebody can still see you means picking the
	-- next one -- and without this each is chosen as though the run had just started, which is how a
	-- flight across a hotel comes out as a thing that turns round in the corridor every few seconds.
	-- Somewhere behind it can be perfectly away from everybody and still be the wrong way to go.
	Heading: Vector3?,
}

--- The best floor position within reach of `origin` that a figure could stand on unseen, or nil when
--- the floor around it offers none. Returns a floor position, which is what pathfinding and
--- `Humanoid:MoveTo` want.
---
--- `agentRadius` is the caller's own `AgentParams.AgentRadius`, and passing anything else is asking for
--- somewhere it cannot get to: every candidate has to have that much room around it, because that is
--- what the navmesh the caller will path over was built with.
---
--- A hundred-odd cheap candidates and a dozen raycasts, on the calling thread. Ask once per retreat
--- attempt, not once per frame.
function HideSpotService:Find(origin: Vector3, agentRadius: number, options: FindOptions?): Vector3?
	local range = (options and options.Range) or DEFAULT_RANGE
	local minDistance = (options and options.MinDistance) or DEFAULT_MIN_DISTANCE

	local heading = options and options.Heading and flatten(options.Heading)
	heading = if heading and heading.Magnitude > 1e-3 then heading.Unit else nil

	-- No floor within range is an ordinary answer -- it means run somewhere else and ask again -- so
	-- only a map with the tag missing entirely is worth saying anything about.
	local floors = getFloors(origin, range)
	if #floors == 0 then
		if not warnedAboutTag and #CollectionService:GetTagged(MAZE_FLOOR_TAG) == 0 then
			warnedAboutTag = true
			warn(`[enemies] nothing is tagged {MAZE_FLOOR_TAG}, so nothing can find anywhere to hide`)
		end
		return nil
	end

	local eyes = EnemyObservationService:GetEyes()
	local currentClearance, closest = nearestEye(eyes, origin)
	local towards = closest and flatten(closest - origin)
	towards = if towards and towards.Magnitude > 1e-3 then towards.Unit else nil

	local candidates = {}
	for _, part in floors do
		for _, point in sampleFace(part, origin, range, agentRadius) do
			local offset = flatten(point - origin)
			local travel = offset.Magnitude
			if travel < minDistance or travel > range then continue end

			-- Away, not merely elsewhere. Both tests are about the same thing from different sides:
			-- one says the spot is further off everybody than here is, the other says getting to it
			-- does not start by walking at the person looking.
			local clearance = nearestEye(eyes, point)
			if clearance < MIN_EYE_CLEARANCE or clearance < currentClearance + RETREAT_GAIN then continue end
			if towards and offset.Unit:Dot(towards) > MAX_TOWARDS_DOT then continue end

			-- Carrying on beats doubling back, and sharply enough behind counts as doubling back
			-- whatever else recommends it. The rest is a preference, so a run bends round the building
			-- rather than being forced straight through it.
			local score = clearance - TRAVEL_WEIGHT * travel
			if heading then
				local alignment = offset.Unit:Dot(heading)
				if alignment < MIN_HEADING_DOT then continue end
				score += HEADING_WEIGHT * alignment
			end

			table.insert(candidates, { Point = point, Score = score })
			if #candidates >= CANDIDATE_LIMIT then break end
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

	-- Best first, and the first one that holds up wins. Anything past `VERIFY_LIMIT` is a worse trade
	-- than simply asking again from wherever the next few seconds of running leaves it.
	for index = 1, math.min(#candidates, VERIFY_LIMIT) do
		local floorPosition = findStanding(params, overlap, candidates[index].Point, agentRadius)
		if floorPosition and not isVisible(params, eyes, floorPosition) then
			return floorPosition
		end
	end
	return nil
end

return HideSpotService
