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
--- Four moves:
---  1. Fan rays around the player's eye and find the silhouettes. A pair of neighbouring rays is an
---     edge when the far one lands well past where the near one's *surface*, carried on, would have
---     put it -- not merely when the two depths differ. That distinction is the whole of step one:
---     a flat wall seen at a glancing angle puts neighbouring rays tens of studs apart on unbroken
---     stone, and reading those as corners is how something ends up leaning out of a wall.
---  2. Bisect between that pair to pin the edge down, so where the spots land does not depend on how
---     coarse the fan was, and check that whatever forms it screens a figure from floor to head --
---     a discontinuity at eye height is just as happily the end of a desk.
---  3. Straddle the edge, a little past it: one spot on the blind side to wait on, one on the seen
---     side to lean to. Both have to be standable, and -- the constraint that does the real work --
---     they have to be able to see each other. Two spots either side of a solid wall straddle an
---     edge just as well; only two spots either side of that wall's *end* can see across.
---  4. Sweep a body between them. Two standable spots that can see each other are not two spots a
---     body can travel between: at a door frame the line between them runs through the jamb, and a
---     figure sliding along it emerges out of the wall rather than around it.
---
--- Every visibility question here is asked of a figure rather than of a point. One ray at head
--- height cannot tell a body in full view from a shoulder showing past a frame, and both promises
--- this service makes -- hidden here, seen there -- are about the body.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)

local ENEMY_TAG = "Enemy"

local EYE_OFFSET = 1.5 -- studs from an R15 root up to roughly where that character looks from
local ROOT_HEIGHT = 3 -- studs from the floor to an R15 root
local STANDING_SIZE = Vector3.new(2, 5, 2) -- the room a figure needs to stand somewhere unclipped
local STANDING_CLEARANCE = 0.5 -- studs of the box held off the floor, so the floor is not an overlap
-- The volume swept from one side of a spot to the other. Slightly wider than standing room and a
-- little shorter: the rig tilts as it travels, and a path it only just fits down is one it scrapes.
local SWEEP_SIZE = Vector3.new(2.6, 4.6, 2.6)

local FAN_RAYS = 96
local FAN_RANGE = 100 -- studs; nothing further away is worth peeking from
local BISECT_STEPS = 6
-- Studs the far side of a pair may miss the near side's surface plane by and still be the same
-- surface. Above it the near surface has genuinely ended and something can stand behind its end.
local PLANE_TOLERANCE = 2
local MIN_EDGE_GAP = 8 -- studs the far side must open up by, so there is somewhere to lean out of
local MAX_WALL_NORMAL_Y = 0.5 -- |Y| of a near surface's normal past which it is floor, not wall
local OCCLUDER_HEIGHTS = { 1, 4.2 } -- studs above the floor a corner must still block at
local OCCLUDER_SLACK = 3 -- studs past the corner those probes may travel before giving up

-- Corners to collect before a search calls it a day. This bounds the cost of a pillared corridor,
-- which throws up thirty-odd edges, without ever being a reason to leave one unexamined: a cap on
-- edges *looked at* silently discards the one corner a room had, and most edges do not pan out.
local ENOUGH_SPOTS = 6
-- How the pair is tried around an edge, nearest and tightest first. These grids are finer than the
-- checks strictly need because the expensive constraint -- that a body can actually travel from one
-- side to the other -- is satisfied by a narrow band of placements around any given corner, and a
-- coarse grid steps straight over it. Measured over the hotel, thickening them from four depths and
-- five offsets to six and eight takes the share of positions that can host a Watcher from 18% to
-- 26%, for about 5ms on a search that runs once per peek.
local EDGE_DEPTHS = { 1.5, 2.5, 3.5, 5, 6.5, 8 } -- studs past the edge to try the pair at
-- Studs onto the seen side of the edge: far enough out to read as a body rather than a smudge, and
-- more than one because the near side of an edge is often a pillar's own bay -- no room to stand in
-- at 1.5, room a stud further out.
local PEEK_OFFSETS = { 1.5, 2.25, 3 }
-- Studs onto the blind side. The thing being hidden behind has thickness: tucking 2.25 studs behind
-- the end of a thin door frame is out of sight, and behind the end of a chimney breast is still
-- inside it. It starts further back than the seen side does because a rig is about four studs across
-- and the offset is measured to its middle: tuck it 1.5 behind the sight line and the far shoulder
-- is still half a stud in front of it.
local HIDE_OFFSETS = { 2.25, 3, 4, 5, 6 }
local FLOOR_PROBE_UP = 8 -- studs above a candidate the floor probe starts at
local FLOOR_PROBE_DOWN = 20 -- and how far down it looks from there
local MAX_FLOOR_DROP = 3 -- studs of floor height change that still counts as the same storey

-- The two questions this service answers are about different shapes, so they get different point
-- sets, as (studs above the floor, studs along the spot's lateral axis).
--
-- Being hidden is about the outline. A Watcher rig measures about four studs across -- wider than
-- the two-stud box it is checked for standing room with -- so an outline sampled at the shoulders of
-- a normal character leaves a real one's arm showing past the corner while every ray says it is
-- tucked away. Measured against a placed rig that was one spot in ten, and one spot in ten that
-- despawns on the frame it appears.
local HIDE_SAMPLES = {
	{ 4.4, 0 },
	{ 4.0, 1.0 },
	{ 4.0, -1.0 },
	{ 3.0, 1.9 },
	{ 3.0, -1.9 },
	{ 2.0, 1.6 },
	{ 2.0, -1.6 },
	{ 0.8, 1.0 },
	{ 0.8, -1.0 },
}
-- Reading as a figure is about the mass, so the seen side is asked about the core rather than the
-- extremities: a corner that shows a body and one shoulder is a corner worth leaning out of, and
-- demanding the far arm too rules out most real ones. The head is first and asked on its own -- a
-- lean that shows a body with no head above it is a lean into somewhere not worth appearing.
local PEEK_SAMPLES = {
	{ 4.4, 0 },
	{ 3.4, 0.7 },
	{ 3.4, -0.7 },
	{ 2.2, 0.5 },
	{ 2.2, -0.5 },
	{ 0.8, 0 },
}
local PEEK_VISIBLE_SAMPLES = 4 -- of those six, before a lean counts as showing a figure at all

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

-- One fan ray's answer. The surface it landed on matters as much as how far away it was: without a
-- normal there is no way to tell a corner from a wall viewed edge-on.
type Sample = {
	Distance: number,
	Position: Vector3,
	Normal: Vector3?,
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

local function castSample(params: RaycastParams, from: Vector3, direction: Vector3): Sample
	local result = workspace:Raycast(from, direction * FAN_RANGE, params)
	if not result then
		return { Distance = FAN_RANGE, Position = from + direction * FAN_RANGE }
	end
	return {
		Distance = (result.Position - from).Magnitude,
		Position = result.Position,
		Normal = result.Normal,
	}
end

-- How far the world is in `direction`, or `FAN_RANGE` where it is not there at all.
local function castDistance(params: RaycastParams, from: Vector3, direction: Vector3): number
	return castSample(params, from, direction).Distance
end

-- How far away `sample`'s surface would be along `direction` if it simply carried on flat, or nil
-- where that plane is edge-on to the ray or behind it. This is what separates a corner from a wall
-- running away from the viewer: on unbroken stone the answer matches the ray that was actually cast.
local function planeDistance(eye: Vector3, sample: Sample, direction: Vector3): number?
	local normal = sample.Normal
	if not normal then return nil end

	local denominator = direction:Dot(normal)
	if math.abs(denominator) < 1e-3 then return nil end

	local distance = (sample.Position - eye):Dot(normal) / denominator
	if distance <= 0 then return nil end
	return distance
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

-- Where a figure standing on `floorPosition` would present itself, spread along `lateral` so the
-- samples straddle its width rather than stacking up its middle.
local function bodyPoints(samples: { { number } }, floorPosition: Vector3, lateral: Vector3): { Vector3 }
	local points = table.create(#samples)
	for index, sample in samples do
		points[index] = floorPosition + Vector3.yAxis * sample[1] + lateral * sample[2]
	end
	return points
end

-- How much of that figure `eye` can make out, and whether its head is part of it.
local function countVisible(params: RaycastParams, eye: Vector3, points: { Vector3 }): (number, boolean)
	local count, head = 0, false
	for index, point in points do
		if isClear(params, eye, point) then
			count += 1
			if index == 1 then
				head = true
			end
		end
	end
	return count, head
end

local function isHiddenFrom(params: RaycastParams, eye: Vector3, points: { Vector3 }): boolean
	for _, point in points do
		if isClear(params, eye, point) then return false end
	end
	return true
end

-- Whether a body can travel from one side of a spot to the other without passing through anything.
-- Two standable spots either side of an edge are not two spots something can move between: at a door
-- frame the straight line between them runs through the jamb, and the pair of head-height sight
-- checks that qualified them both says nothing about that.
local function isPathClear(params: RaycastParams, from: Vector3, to: Vector3): boolean
	local direction = to - from
	if direction.Magnitude < 1e-3 then return true end

	local origin = from + Vector3.yAxis * (SWEEP_SIZE.Y / 2 + STANDING_CLEARANCE)
	local frame = CFrame.lookAt(origin, origin + direction)
	return workspace:Blockcast(frame, SWEEP_SIZE, direction, params) == nil
end

-- Whether the thing forming this edge screens a standing figure top to bottom. A depth
-- discontinuity at eye height is just as happily the end of a desk or the top of a stair rail, and
-- neither hides anything from somebody looking at the floor behind it.
--
-- `direction` must be the fan ray that found the surface, not the bisected one that pins the edge
-- down. Bisection deliberately lands a fraction of a degree off the silhouette, so a probe along it
-- grazes the surface by inches -- close enough that a skirting board, a seam between two wall parts
-- or a doorway's trim decides the answer. Measured over the hotel that rejects five corners in six,
-- almost all of them real. The unrefined ray is a few degrees into the same surface and rejects the
-- three in a hundred that are genuinely waist-high.
local function isSolidOccluder(
	params: RaycastParams,
	eye: Vector3,
	direction: Vector3,
	distance: number,
	floorY: number
): boolean
	local reach = direction * (distance + OCCLUDER_SLACK)
	for _, height in OCCLUDER_HEIGHTS do
		local from = Vector3.new(eye.X, floorY + height, eye.Z)
		if workspace:Raycast(from, reach, params) == nil then return false end
	end
	return true
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
local function bisectEdge(
	params: RaycastParams,
	eye: Vector3,
	near: Vector3,
	far: Vector3,
	nearDistance: number
)
	local blind, seen = near, far

	for _ = 1, BISECT_STEPS do
		local middle = blind + seen
		if middle.Magnitude < 1e-4 then break end
		middle = middle.Unit

		if castDistance(params, eye, middle) - nearDistance < MIN_EDGE_GAP then
			blind = middle
		else
			seen = middle
		end
	end
	return blind, seen
end

-- Where everybody other than `player` is looking from, so a corner is never offered up on the
-- strength of being hidden from one person in a party of four.
local function otherEyes(player: Player): { Vector3 }
	local eyes = {}

	for _, other in Players:GetPlayers() do
		if other == player then continue end

		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if not (humanoid and humanoid.Health > 0) then continue end

		local eye = EnemyObservationService:GetView(other)
		if eye then
			table.insert(eyes, eye)
		end
	end
	return eyes
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

	-- The reported camera rather than the character's head, where one is in hand. Hiding is a
	-- question about where somebody is looking from, and answering it off the top of a character is
	-- how you get a thing that tucks itself behind furniture the camera sees straight over.
	local reportedEye, reportedLook = EnemyObservationService:GetView(player)
	local eye = reportedEye or root.Position + Vector3.new(0, EYE_OFFSET, 0)
	local facing = reportedLook or root.CFrame.LookVector
	local floorY = root.Position.Y - ROOT_HEIGHT
	local others = otherEyes(player)

	-- Sweep for silhouettes. Each one is an edge this player can see past.
	local directions, samples = {}, {}
	for index = 0, FAN_RAYS - 1 do
		local angle = index * 2 * math.pi / FAN_RAYS
		directions[index] = Vector3.new(math.cos(angle), 0, math.sin(angle))
		samples[index] = castSample(params, eye, directions[index])
	end

	local edges = {}
	for index = 0, FAN_RAYS - 1 do
		local neighbour = (index + 1) % FAN_RAYS
		local nearIsFirst = samples[index].Distance <= samples[neighbour].Distance
		local near = if nearIsFirst then samples[index] else samples[neighbour]
		local far = if nearIsFirst then samples[neighbour] else samples[index]

		-- Something has to be there to hide behind, it has to be a wall rather than the floor, and
		-- the far side has to open up enough to give a figure somewhere to have leaned out of.
		if far.Distance - near.Distance < MIN_EDGE_GAP then continue end
		if not near.Normal or math.abs(near.Normal.Y) > MAX_WALL_NORMAL_Y then continue end

		local farDirection = if nearIsFirst then directions[neighbour] else directions[index]
		local flat = planeDistance(eye, near, farDirection)
		if flat and math.abs(flat - far.Distance) <= PLANE_TOLERANCE then continue end -- same wall, seen edge-on

		table.insert(edges, {
			Blind = if nearIsFirst then directions[index] else directions[neighbour],
			Seen = farDirection,
			Distance = near.Distance,
		})
	end

	-- Shuffled so the same hallway does not always offer up the same corner, then walked until enough
	-- have worked out. Every edge stays eligible: in a corridor lined with pillars most of them lead
	-- nowhere, and the one that does is as likely to be last as first.
	local spots = {}
	for index = #edges, 2, -1 do
		local swap = math.random(index)
		edges[index], edges[swap] = edges[swap], edges[index]
	end

	for _, edge in edges do
		if #spots >= ENOUGH_SPOTS then break end
		if edge.Distance < options.MinDistance or edge.Distance > options.MaxDistance then continue end

		local blind, seen = bisectEdge(params, eye, edge.Blind, edge.Seen, edge.Distance)

		-- The axis the pair splits along: from the side the near surface covers to the side it does
		-- not, which is the direction something behind it would have to lean to be seen.
		local lateral = Vector3.new(seen.X - blind.X, 0, seen.Z - blind.Z)
		if lateral.Magnitude < 1e-4 then continue end
		lateral = lateral.Unit

		local corner = eye + blind * edge.Distance
		if not isWithinArc(eye, facing, corner, options.Arc) then continue end
		if not isSolidOccluder(params, eye, edge.Blind, edge.Distance, floorY) then continue end

		-- Settle the seen side first, then work out how far back of the edge something has to stand
		-- to be out of sight from it. Nearest depth and shallowest tuck win: both keep the pair as
		-- tight to the corner as the geometry allows, which is what makes the lean read as a lean.
		local placed = false
		for _, depth in EDGE_DEPTHS do
			if placed then break end
			local base = corner + blind * depth

			for _, peekOffset in PEEK_OFFSETS do
				if placed then break end

				local peek = findStanding(params, overlap, base + lateral * peekOffset, floorY)
				if not peek then continue end

				local visible, headVisible = countVisible(params, eye, bodyPoints(PEEK_SAMPLES, peek, lateral))
				if not headVisible or visible < PEEK_VISIBLE_SAMPLES then continue end

				for _, hideOffset in HIDE_OFFSETS do
					local hide = findStanding(params, overlap, base - lateral * hideOffset, floorY)
					if not hide then continue end
					if math.abs(hide.Y - peek.Y) > MAX_FLOOR_DROP then continue end

					local hidden = bodyPoints(HIDE_SAMPLES, hide, lateral)
					if not isHiddenFrom(params, eye, hidden) then continue end -- start out of sight

					local hiddenFromEveryone = true
					for _, other in others do
						if not isHiddenFrom(params, other, hidden) then
							hiddenFromEveryone = false
							break
						end
					end
					if not hiddenFromEveryone then continue end

					if not isPathClear(params, hide, peek) then continue end -- around the corner, not through it

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

--- Whether the two sides of `spot` still hold up: nobody can see the blind side, `player` can still
--- make out a body on the seen side, and a figure can still get from one to the other.
---
--- A spot is found once and used for minutes. Doors open, other players wander in, and a corner that
--- was worth waiting behind when it was chosen is not necessarily one worth leaning out of now.
function PeekSpotService:IsStillValid(spot: PeekSpot, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = buildFilter()
	params.RespectCanCollide = true

	local eye = EnemyObservationService:GetView(player) or root.Position + Vector3.new(0, EYE_OFFSET, 0)

	local hidden = bodyPoints(HIDE_SAMPLES, spot.Hide, spot.Lateral)
	if not isHiddenFrom(params, eye, hidden) then return false end
	for _, other in otherEyes(player) do
		if not isHiddenFrom(params, other, hidden) then return false end
	end

	local visible, headVisible = countVisible(params, eye, bodyPoints(PEEK_SAMPLES, spot.Peek, spot.Lateral))
	if not headVisible or visible < PEEK_VISIBLE_SAMPLES then return false end

	return isPathClear(params, spot.Hide, spot.Peek)
end

return PeekSpotService
