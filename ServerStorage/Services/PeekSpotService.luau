--- Finds the places something can wait out of sight and then lean into view: the geometry behind
--- peeking around a corner.
---
--- There is no list of corners to read. The map is over a thousand loose parts with no naming that
--- separates a wall from a bedframe, and hand-tagging every corner in a hotel is a job that grows
--- with every room built. So a corner is not treated as a feature of the map at all -- it is treated
--- as a feature of one player's sight line: a spot they cannot see, close enough to a spot they can
--- that a single step sideways crosses between the two. Anything that produces such a boundary --
--- the end of a wall, a door frame, a pillar, a wardrobe -- is a corner, and none of it is authored.
---
--- Three moves:
---  1. Fan rays around the player's eye. Two neighbouring rays that disagree sharply about how far
---     away the world is have an edge between them.
---  2. Bisect between that pair to pin the edge down, so where the spots land does not depend on how
---     coarse the fan was.
---  3. Straddle the edge, a little past it: one spot on the blind side to wait on, one on the seen
---     side to lean to. Both have to be standable, and -- the constraint that does the real work --
---     they have to be able to see each other. Two spots either side of a solid wall straddle an
---     edge just as well; only two spots either side of that wall's *end* can see across.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ENEMY_TAG = "Enemy"

local EYE_OFFSET = 1.5 -- studs from an R15 root up to roughly where that character looks from
local ROOT_HEIGHT = 3 -- studs from the floor to an R15 root
local STANDING_SIZE = Vector3.new(2, 5, 2) -- the room a figure needs to stand somewhere unclipped
local STANDING_CLEARANCE = 0.5 -- studs of the box held off the floor, so the floor is not an overlap

local FAN_RAYS = 72
local FAN_RANGE = 90 -- studs; nothing further away is worth peeking from
local EDGE_STEP = 3 -- studs of depth change between neighbouring rays that marks an edge
local BISECT_STEPS = 5
-- Corners to collect before a search calls it a day. This bounds the cost of a pillared corridor,
-- which throws up thirty-odd edges, without ever being a reason to leave one unexamined: a cap on
-- edges *looked at* silently discards the one corner a room had, and most edges do not pan out.
local ENOUGH_SPOTS = 6
local EDGE_DEPTHS = { 1, 3, 5, 7 } -- studs past the edge to try the pair at, nearest first
-- Studs onto the seen side of the edge: far enough out to read as a body rather than a smudge. Two,
-- because the near side of an edge is often a pillar's own bay -- no room to stand in at 1.5, room a
-- stud further out.
local PEEK_OFFSETS = { 1.5, 2.75 }
-- Studs onto the blind side, tried in order. More than one because the thing being hidden behind has
-- thickness: tucking 1.5 studs behind the end of a thin door frame is out of sight, and behind the
-- end of a chimney breast is still inside it.
local HIDE_OFFSETS = { 1.5, 2.75, 4 }
local FLOOR_PROBE_UP = 8 -- studs above a candidate the floor probe starts at
local FLOOR_PROBE_DOWN = 20 -- and how far down it looks from there
local MAX_FLOOR_DROP = 3 -- studs of floor height change that still counts as the same storey

--- A corner, expressed as the two places either side of it.
export type PeekSpot = {
	Hide: Vector3, -- floor position out of the player's sight, to wait on
	Peek: Vector3, -- floor position in the player's sight, to lean to
	Lateral: Vector3, -- horizontal unit vector from `Hide` towards `Peek`
}

export type FindOptions = {
	MinDistance: number, -- studs from the player a corner must be at least, to not appear underfoot
	MaxDistance: number,
	Arc: number, -- degrees around the player's facing a corner must fall within; 360 for anywhere
}

local PeekSpotService = {}

-- Everything that must not read as a wall: no character or enemy should carve out a fake corner.
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

local function isClear(params: RaycastParams, from: Vector3, to: Vector3): boolean
	local direction = to - from
	if direction.Magnitude < 1e-3 then return true end
	return workspace:Raycast(from, direction, params) == nil
end

-- How far the world is in `direction`, or `FAN_RANGE` where it is not there at all.
local function castDistance(params: RaycastParams, from: Vector3, direction: Vector3): number
	local result = workspace:Raycast(from, direction * FAN_RANGE, params)
	return if result then (result.Position - from).Magnitude else FAN_RANGE
end

-- The floor position a figure could stand on at this horizontal position, or nil where one could
-- not: no floor under it, a floor belonging to another storey, or no room to stand in.
local function findStanding(
	params: RaycastParams,
	overlap: OverlapParams,
	position: Vector3,
	floorY: number
): Vector3?
	local from = Vector3.new(position.X, floorY + FLOOR_PROBE_UP, position.Z)
	local result = workspace:Raycast(from, Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0), params)
	if not result or math.abs(result.Position.Y - floorY) > MAX_FLOOR_DROP then return nil end

	local centre = result.Position + Vector3.new(0, STANDING_SIZE.Y / 2 + STANDING_CLEARANCE, 0)
	if #workspace:GetPartBoundsInBox(CFrame.new(centre), STANDING_SIZE, overlap) > 0 then return nil end
	return result.Position
end

-- Whether `point` falls inside a horizontal cone of `arc` degrees opening along `facing`.
local function isWithinArc(origin: Vector3, facing: Vector3, point: Vector3, arc: number): boolean
	if arc >= 360 then return true end

	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local look = Vector3.new(facing.X, 0, facing.Z)
	if offset.Magnitude < 1e-3 or look.Magnitude < 1e-3 then return true end

	local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(look.Unit), -1, 1)))
	return angle <= arc / 2
end

-- Narrows the gap between a direction that grazes the near surface and one that clears it, so the
-- edge between them is located to a fraction of a degree rather than to the width of a fan step.
local function bisectEdge(params: RaycastParams, eye: Vector3, near: Vector3, far: Vector3, nearDistance: number)
	local blind, seen = near, far

	for _ = 1, BISECT_STEPS do
		local middle = blind + seen
		if middle.Magnitude < 1e-4 then break end
		middle = middle.Unit

		if castDistance(params, eye, middle) - nearDistance < EDGE_STEP then
			blind = middle
		else
			seen = middle
		end
	end
	return blind, seen
end

--- A corner near `player` to peek around, or nil while the geometry around them offers none. The
--- search is a few hundred raycasts and runs on the calling thread; it is meant to be asked once
--- per peek, not once per frame.
function PeekSpotService:Find(player: Player, options: FindOptions): PeekSpot?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local filter = buildFilter()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = filter
	overlap.RespectCanCollide = true

	local eye = root.Position + Vector3.new(0, EYE_OFFSET, 0)
	local floorY = root.Position.Y - ROOT_HEIGHT
	local facing = root.CFrame.LookVector

	-- Sweep for depth discontinuities. Each one is an edge this player can see past.
	local directions, distances = {}, {}
	for index = 0, FAN_RAYS - 1 do
		local angle = index * 2 * math.pi / FAN_RAYS
		directions[index] = Vector3.new(math.cos(angle), 0, math.sin(angle))
		distances[index] = castDistance(params, eye, directions[index])
	end

	local edges = {}
	for index = 0, FAN_RAYS - 1 do
		if math.abs(distances[index] - distances[(index + 1) % FAN_RAYS]) >= EDGE_STEP then
			table.insert(edges, index)
		end
	end

	-- Shuffled so the same hallway does not always offer up the same corner, then walked until enough
	-- have worked out. Every edge stays eligible: in a corridor lined with pillars most of them lead
	-- nowhere, and the one that does is as likely to be last as first.
	local spots = {}
	for index = #edges, 2, -1 do
		local swap = math.random(index)
		edges[index], edges[swap] = edges[swap], edges[index]
	end

	for _, index in edges do
		if #spots >= ENOUGH_SPOTS then break end

		local neighbour = (index + 1) % FAN_RAYS
		local nearIsFirst = distances[index] < distances[neighbour]
		local nearDistance = if nearIsFirst then distances[index] else distances[neighbour]
		if nearDistance < options.MinDistance or nearDistance > options.MaxDistance then continue end

		local blind, seen = bisectEdge(
			params,
			eye,
			if nearIsFirst then directions[index] else directions[neighbour],
			if nearIsFirst then directions[neighbour] else directions[index],
			nearDistance
		)

		-- The axis the pair splits along: from the side the near surface covers to the side it does
		-- not, which is the direction something behind it would have to lean to be seen.
		local lateral = Vector3.new(seen.X - blind.X, 0, seen.Z - blind.Z)
		if lateral.Magnitude < 1e-4 then continue end
		lateral = lateral.Unit

		local edge = eye + blind * nearDistance
		if not isWithinArc(eye, facing, edge, options.Arc) then continue end

		-- Settle the seen side first, then work out how far back of the edge something has to stand
		-- to be out of sight from it. Nearest depth and shallowest tuck win: both keep the pair as
		-- tight to the corner as the geometry allows, which is what makes the lean read as a lean.
		local placed = false
		for _, depth in EDGE_DEPTHS do
			if placed then break end
			local base = edge + blind * depth

			for _, peekOffset in PEEK_OFFSETS do
				if placed then break end

				local peek = findStanding(params, overlap, base + lateral * peekOffset, floorY)
				if not peek then continue end

				local peekEye = peek + Vector3.new(0, ROOT_HEIGHT + EYE_OFFSET, 0)
				if not isClear(params, eye, peekEye) then continue end -- the lean has to land in sight

				for _, hideOffset in HIDE_OFFSETS do
					local hide = findStanding(params, overlap, base - lateral * hideOffset, floorY)
					if not hide then continue end

					local hideEye = hide + Vector3.new(0, ROOT_HEIGHT + EYE_OFFSET, 0)
					if isClear(params, eye, hideEye) then continue end -- and start out of it
					if not isClear(params, hideEye, peekEye) then continue end -- either side of an end, not a wall

					table.insert(spots, { Hide = hide, Peek = peek, Lateral = lateral } :: PeekSpot)
					placed = true
					break
				end
			end
		end
	end

	if #spots == 0 then return nil end
	return spots[math.random(#spots)]
end

return PeekSpotService
