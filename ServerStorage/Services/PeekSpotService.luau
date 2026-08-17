--- Finds the places something can wait out of sight and then lean into view: the geometry behind
--- peeking around a corner.
---
--- Two promises, and the second one is the reason this is a service rather than a raycast at the
--- spawn site. A pair of spots is only offered up when the blind one cannot be seen by anybody, and
--- when the seen one -- the place a figure will actually appear in -- is behind every living player,
--- outside the wedge they are looking down. Nothing this hands back can be watched arriving. What
--- makes it worth appearing there at all is that the seen side still has a clear line to the player:
--- it is not on their screen, but it is somewhere they would find something standing the moment they
--- turn around.
---
--- Corners come from two places, in this order:
---  1. `HallwayGridService`, which reads junctions off the hallway graph. A corridor mouth is a
---     corner the map states outright, and those are the corners worth using.
---  2. A ray fan, for everywhere the graph is silent about -- rooms, door frames, pillars, the end of
---     a wardrobe. A pair of neighbouring rays is an edge when the far one lands well past where the
---     near one's *surface*, carried on, would have put it -- not merely when the two depths differ.
---     That distinction is the whole of the fallback: a flat wall seen at a glancing angle puts
---     neighbouring rays tens of studs apart on unbroken stone, and reading those as corners is how
---     something ends up leaning out of a wall.
---
--- Either way the corner is only a direction and a distance. Turning one into a pair of standable
--- spots is the same work for both: straddle it, a little past it -- one spot on the blind side to
--- wait on, one on the seen side to lean to -- then check that they can see each other and that a
--- body can actually travel between them. Two spots either side of a solid wall straddle an edge
--- just as well; only two either side of that wall's *end* can see across. And at a door frame the
--- line between two such spots runs through the jamb, so a figure sliding along it emerges out of the
--- wall rather than around it.
---
--- Every visibility question here is asked of a figure rather than of a point. One ray at head height
--- cannot tell a body in full view from a shoulder showing past a frame, and all three promises this
--- service makes -- hidden here, unseen there, findable once looked for -- are about the body.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HallwayGridService = require(ServerStorage.Services.HallwayGridService)

local ENEMY_TAG = "Enemy"

local EYE_OFFSET = 1.5 -- studs from an R15 root up to roughly where that character looks from
local ROOT_HEIGHT = 3 -- studs from the floor to an R15 root
-- The Watcher is wide across its shoulders but shallow front-to-back. The old square probe forced
-- the hidden side deep into the branch before it fit, leaving the rig in the middle of the hall.
local STANDING_SIZE = Vector3.new(4.5, 5.2, 2.4) -- width, height and depth of the rig with margin
local STANDING_CLEARANCE = 0.5 -- studs of the box held off the floor, so the floor is not an overlap
-- The volume swept from one side of a spot to the other. Slightly wider than standing room and a
-- little shorter: the rig tilts as it travels, and a path it only just fits down is one it scrapes.
local SWEEP_SIZE = Vector3.new(4.8, 4.8, 4.8)

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
-- corners *looked at* silently discards the one a room had, and most do not pan out.
local ENOUGH_SPOTS = 6
-- How a pair is tried around a fan-found edge, nearest and tightest first. These grids are finer
-- than the checks strictly need because the expensive constraint -- that a body can actually travel
-- from one side to the other -- is satisfied by a narrow band of placements around any given corner,
-- and a coarse grid steps straight over it. Measured over the hotel, thickening them from four
-- depths and five offsets to six and eight takes the share of positions that can host a Watcher from
-- 18% to 26%, for about 5ms on a search that runs once per peek.
local EDGE_DEPTHS = { 1.5, 2.5, 3.5, 5, 6.5, 8 } -- studs past the edge to try the pair at
-- Studs onto the seen side of the corner: far enough out to read as a body rather than a smudge, and
-- more than one because the near side of an edge is often a pillar's own bay -- no room to stand in
-- at 1.5, room a stud further out.
local PEEK_OFFSETS = { 1.5, 2.25, 3 }
-- Studs onto the blind side. The thing being hidden behind has thickness: tucking 2.25 studs behind
-- the end of a thin door frame is out of sight, and behind the end of a chimney breast is still
-- inside it. It starts further back than the seen side does because a rig is about four studs across
-- and the offset is measured to its middle: tuck it 1.5 behind the sight line and the far shoulder
-- is still half a stud in front of it. The long tail is what a corridor junction needs -- being
-- around the corner of a hallway means being clear of its whole width, not of a wall's thickness.
local HIDE_OFFSETS = { 2.25, 3, 4, 5, 6, 8, 10 }
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
	Hide: Vector3, -- floor position out of everybody's sight, to wait on
	Peek: Vector3, -- floor position behind the player but in clear line of them, to lean to
	Lateral: Vector3, -- horizontal unit vector from `Hide` towards `Peek`
}

export type FindOptions = {
	MinDistance: number, -- studs from the player a corner must be at least, to not appear underfoot
	MaxDistance: number,
	-- Degrees around the direction *away* from the player's facing a corner must fall within, so 180
	-- is anywhere behind them and 360 gives the requirement up. What keeps a Watcher out of the
	-- corridor somebody is walking down and into the one they have just left.
	RearArc: number,
	-- Degrees of aim treated as this player's screen. Nothing is offered up that would put a figure
	-- inside it; roughly a first-person camera's own field of view, plus margin for turning heads.
	ViewCone: number,
}

export type Corner = HallwayGridService.Corner

-- One fan ray's answer. The surface it landed on matters as much as how far away it was: without a
-- normal there is no way to tell a corner from a wall viewed edge-on.
type Sample = {
	Distance: number,
	Position: Vector3,
	Normal: Vector3?,
}

-- Everything one search needs to keep asking the same questions of the same world.
type Search = {
	Params: RaycastParams,
	Overlap: OverlapParams,
	Eye: Vector3, -- where the player this is being found for is looking from
	Back: Vector3, -- and the horizontal direction opposite the way they face
	FloorY: number,
	Views: { EnemyObservationService.View }, -- every living player, including that one
	Options: FindOptions,
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

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
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
	floorY: number,
	facing: Vector3?
): Vector3?
	local from = Vector3.new(position.X, floorY + FLOOR_PROBE_UP, position.Z)
	local result = workspace:Raycast(from, Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0), params)
	if not result or math.abs(result.Position.Y - floorY) > MAX_FLOOR_DROP then return nil end

	local centre = result.Position + Vector3.new(0, STANDING_SIZE.Y / 2 + STANDING_CLEARANCE, 0)
	local frame = CFrame.new(centre)
	if facing and Vector3.new(facing.X, 0, facing.Z).Magnitude > 1e-3 then
		frame = CFrame.lookAt(centre, centre + Vector3.new(facing.X, 0, facing.Z))
	end
	if #workspace:GetPartBoundsInBox(frame, STANDING_SIZE, overlap) > 0 then return nil end
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

-- Whether nobody's line of sight reaches any part of a figure standing there.
local function isHiddenFromEveryone(search: Search, points: { Vector3 }): boolean
	for _, view in search.Views do
		if not isHiddenFrom(search.Params, view.Eye, points) then return false end
	end
	return true
end

-- Whether a figure standing there would be off every player's screen. Aim only, and deliberately:
-- this is asked of the place a Watcher will *become* visible in, so the wall currently between it
-- and somebody is no reassurance at all -- what matters is that when it does step out, it steps out
-- behind them.
local function isOutOfView(search: Search, points: { Vector3 }): boolean
	for _, view in search.Views do
		for _, point in points do
			if EnemyObservationService.IsWithinCone(view, point, search.Options.ViewCone) then return false end
		end
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

-- Whether the thing forming a fan-found edge screens a standing figure top to bottom. A depth
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

	local offset = horizontal(point - origin)
	local look = horizontal(facing)
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

local function shuffle<T>(items: { T }): { T }
	for index = #items, 2, -1 do
		local swap = math.random(index)
		items[index], items[swap] = items[swap], items[index]
	end
	return items
end

--- Turns one corner into a pair of spots, or nil where nothing about it works out. Nearest depth and
--- shallowest tuck win: both keep the pair as tight to the corner as the geometry allows, which is
--- what makes the lean read as a lean.
local function placeOn(search: Search, corner: Corner): PeekSpot?
	for _, depth in corner.Depths do
		local base = corner.Position + corner.Axis * depth
		local facing = -corner.Axis

		for _, peekOffset in PEEK_OFFSETS do
			local peek = findStanding(
				search.Params,
				search.Overlap,
				base + corner.Lateral * peekOffset,
				search.FloorY,
				facing
			)
			if not peek then continue end

			local peekPoints = bodyPoints(PEEK_SAMPLES, peek, corner.Lateral)
			-- Worth appearing in: a clear line from the player, so turning round finds something.
			local visible, headVisible = countVisible(search.Params, search.Eye, peekPoints)
			if not headVisible or visible < PEEK_VISIBLE_SAMPLES then continue end
			-- And safe to appear in: nowhere anybody is currently pointed.
			if not isOutOfView(search, peekPoints) then continue end

			for _, hideOffset in HIDE_OFFSETS do
				local hide = findStanding(
					search.Params,
					search.Overlap,
					base - corner.Lateral * hideOffset,
					search.FloorY,
					facing
				)
				if not hide then continue end
				if math.abs(hide.Y - peek.Y) > MAX_FLOOR_DROP then continue end

				local hidePoints = bodyPoints(HIDE_SAMPLES, hide, corner.Lateral)
				if not isHiddenFromEveryone(search, hidePoints) then continue end -- start out of sight
				if not isPathClear(search.Params, hide, peek) then continue end -- round the corner, not through it

				return { Hide = hide, Peek = peek, Lateral = corner.Lateral }
			end
		end
	end
	return nil
end

--- Walks `corners` until enough have worked out. Every one stays eligible: in a corridor lined with
--- pillars most lead nowhere, and the one that does is as likely to be last as first.
local function collectSpots(search: Search, corners: { Corner }): { PeekSpot }
	local spots = {}

	for _, corner in corners do
		if #spots >= ENOUGH_SPOTS then break end

		local distance = horizontal(corner.Position - search.Eye).Magnitude
		if distance < search.Options.MinDistance or distance > search.Options.MaxDistance then continue end
		if not isWithinArc(search.Eye, search.Back, corner.Position, search.Options.RearArc) then continue end

		local spot = placeOn(search, corner)
		if spot then
			table.insert(spots, spot)
		end
	end

	return spots
end

--- Silhouette edges around the player, for the geometry the hallway graph says nothing about.
local function findFanCorners(search: Search): { Corner }
	local params = search.Params
	local eye = search.Eye

	local directions, samples = {}, {}
	for index = 0, FAN_RAYS - 1 do
		local angle = index * 2 * math.pi / FAN_RAYS
		directions[index] = Vector3.new(math.cos(angle), 0, math.sin(angle))
		samples[index] = castSample(params, eye, directions[index])
	end

	local corners = {}
	for index = 0, FAN_RAYS - 1 do
		local neighbour = (index + 1) % FAN_RAYS
		local nearIsFirst = samples[index].Distance <= samples[neighbour].Distance
		local near = if nearIsFirst then samples[index] else samples[neighbour]
		local far = if nearIsFirst then samples[neighbour] else samples[index]

		-- Something has to be there to hide behind, it has to be a wall rather than the floor, and
		-- the far side has to open up enough to give a figure somewhere to have leaned out of.
		if far.Distance - near.Distance < MIN_EDGE_GAP then continue end
		if not near.Normal or math.abs(near.Normal.Y) > MAX_WALL_NORMAL_Y then continue end

		local blindDirection = if nearIsFirst then directions[index] else directions[neighbour]
		local farDirection = if nearIsFirst then directions[neighbour] else directions[index]
		local flat = planeDistance(eye, near, farDirection)
		if flat and math.abs(flat - far.Distance) <= PLANE_TOLERANCE then continue end -- same wall, edge-on

		-- Filtered before the expensive checks rather than in `collectSpots`, which repeats them
		-- harmlessly: an edge in front of the player or across the building is two raycasts saved.
		local corner = eye + blindDirection * near.Distance
		if near.Distance < search.Options.MinDistance or near.Distance > search.Options.MaxDistance then continue end
		if not isWithinArc(eye, search.Back, corner, search.Options.RearArc) then continue end
		if not isSolidOccluder(params, eye, blindDirection, near.Distance, search.FloorY) then continue end

		local blind, seen = bisectEdge(params, eye, blindDirection, farDirection, near.Distance)
		local lateral = horizontal(seen - blind)
		if lateral.Magnitude < 1e-4 then continue end

		table.insert(corners, {
			Position = eye + blind * near.Distance,
			Axis = blind,
			Lateral = lateral.Unit,
			Depths = EDGE_DEPTHS,
		} :: Corner)
	end

	return corners
end

local function buildSearch(player: Player, options: FindOptions): Search?
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

	-- The reported camera rather than the character's head, where one is in hand. Both questions here
	-- are about where somebody is looking from and which way, and answering either off the top of a
	-- character is how you get a thing that tucks itself behind furniture the camera sees over.
	local reportedEye, reportedLook = EnemyObservationService:GetView(player)
	local eye = reportedEye or root.Position + Vector3.new(0, EYE_OFFSET, 0)
	local facing = reportedLook or root.CFrame.LookVector

	return {
		Params = params,
		Overlap = overlap,
		Eye = eye,
		Back = -horizontal(facing),
		FloorY = root.Position.Y - ROOT_HEIGHT,
		Views = EnemyObservationService:GetViews(),
		Options = options,
	}
end

--- A corner behind `player` to peek around, or nil while the geometry around them offers none. The
--- search is a few hundred raycasts and runs on the calling thread; it is meant to be asked once per
--- peek, not once per frame.
---
--- Junctions are tried before the ray fan and the fan is only run when none of them worked out, so
--- the common case in a corridor costs no fan at all.
function PeekSpotService:Find(player: Player, options: FindOptions): PeekSpot?
	local search = buildSearch(player, options)
	if not search then return nil end

	local corners = HallwayGridService:GetCorners(
		search.Eye,
		search.FloorY,
		options.MinDistance,
		options.MaxDistance
	)
	local spots = collectSpots(search, shuffle(corners))

	if #spots == 0 then
		spots = collectSpots(search, shuffle(findFanCorners(search)))
	end

	if #spots == 0 then return nil end
	return spots[math.random(#spots)]
end

--- Whether the two sides of `spot` still hold up: nobody can see the blind side, the seen side is
--- still both clear of `player` and off everybody's screen, and a figure can still get from one to
--- the other.
---
--- A spot is found once and used for minutes. Doors open, other players wander in, and a corner that
--- was worth waiting behind when it was chosen is not necessarily one worth leaning out of now.
function PeekSpotService:IsStillValid(spot: PeekSpot, player: Player, options: FindOptions): boolean
	local search = buildSearch(player, options)
	if not search then return false end

	local hidden = bodyPoints(HIDE_SAMPLES, spot.Hide, spot.Lateral)
	if not isHiddenFromEveryone(search, hidden) then return false end

	local seen = bodyPoints(PEEK_SAMPLES, spot.Peek, spot.Lateral)
	local visible, headVisible = countVisible(search.Params, search.Eye, seen)
	if not headVisible or visible < PEEK_VISIBLE_SAMPLES then return false end
	if not isOutOfView(search, seen) then return false end

	return isPathClear(search.Params, spot.Hide, spot.Peek)
end

return PeekSpotService
