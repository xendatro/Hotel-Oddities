--- Finds the places something can wait out of sight and then lean into view: the geometry behind
--- peeking around a corner.
---
--- A spot is not a pair of places to stand. It is one place to stand -- behind a corner, where nobody
--- can see it -- and an angle to tip the body through so that the head and shoulders swing out past
--- that corner while the feet stay where they are. That is what peeking around a corner looks like,
--- and it is worth being precise about why the obvious alternative is wrong: two standable floor
--- positions either side of an edge, walked between, is a figure that steps out and stands in the
--- corridor. Nothing about it reads as hiding. It also demands room to stand on the far side, which
--- a corridor mouth rarely has close enough to the corner to matter, so the pair ends up so far apart
--- that the corner is not really involved.
---
--- Corners come from `HallwayGridService`, which reads junctions off the authored hallway graph, and
--- from nowhere else. An earlier version fell back to a ray fan over the room geometry for everywhere
--- the graph is silent about; it found plenty of corners and a large share of them were not corners
--- at all, which is how a Watcher ends up leaning out of a wall. A corridor mouth the map states
--- outright is the only kind worth using.
---
--- Three promises, all checked against the rig's real shape rather than a point:
---  1. Standing upright on the spot, nobody can see any part of it.
---  2. Tipped all the way out, the player it was found for has a clear line to its head and
---     shoulders -- so turning round finds something.
---  3. Tipped all the way out, it is still outside everybody's view cone, and so is the arc it
---     travels through. It can never be watched arriving; it can only be found having arrived.
---
--- The arc matters as much as the endpoints. A body tipping through forty-five degrees sweeps a
--- quarter circle, and a lean that ends in clear air can still have passed a shoulder through the
--- door frame on the way.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HallwayGridService = require(ServerStorage.Services.HallwayGridService)

local ENEMY_TAG = "Enemy"

local EYE_OFFSET = 1.5 -- studs from an R15 root up to roughly where that character looks from
local ROOT_HEIGHT = 3 -- studs from the floor to an R15 root; spots are floor positions
-- The Watcher rig is broad across the shoulders and shallow front to back. Checking it as a square
-- forces it much further back into a side corridor than it needs to go before it fits.
local RIG_SIZE = Vector3.new(1.4, 5.2, 1.0) -- central clearance; the full silhouette is checked separately
local STANDING_CLEARANCE = 0.5 -- studs the box is held off the floor, so the floor is not an overlap
local FLOOR_PROBE_UP = 8 -- studs above a candidate the floor probe starts at
local FLOOR_PROBE_DOWN = 20 -- and how far down it looks from there
local MAX_FLOOR_DROP = 3 -- studs of floor height change that still counts as the same storey

-- Degrees of tip to try, with the shallow reference pose first. Bolder poses remain fallbacks for
-- corners that need more reach to clear their frame.
--
-- The arithmetic is unforgiving and worth writing down. A head four and a half studs up travels
-- `4.4 * sin(angle)` studs sideways when the body tips about its feet -- 3.1 studs at forty-five
-- degrees. The rig is four and a half wide, so it has to stand at least 2.25 studs behind the corner
-- for its shoulders to be hidden while upright. Subtract one from the other and forty-five degrees
-- buys eight inches of head past the corner: technically visible, and in practice a grey smudge at
-- the edge of a door frame. That is the "not super visible" this is answering, and no amount of
-- tuning elsewhere fixes it, because the reach simply is not there.
--
-- Sixty degrees buys 3.8 studs, which is a head and a shoulder properly out past the frame. It is
-- also far enough over that nothing with legs could hold it, which is the point.
local LEAN_ANGLES = { 28, 45, 52, 60 }
-- Points along the arc to check for clearance, past the two ends. A lean that finishes in open air
-- can still have dragged a shoulder through the door frame half way there.
local LEAN_ARC_STEPS = 4
-- Studs of flesh around each traced path. Sample points are infinitely thin and a head is not: traced
-- as bare lines, the arc passes a skull through a door frame that a line through its centre missed by
-- a hand's width, which was the last clip left once everything else here was right. It also covers the
-- gaps between neighbouring samples, so a mullion cannot slip between two of them.
local ARC_RADIUS = 0.6
-- Studs behind the corner to plant the feet, tightest first, and every one of them spends reach the
-- lean has little of. Tight enough that a lean still gets somewhere, spread wide enough that a corner
-- whose near approach is cluttered can still be worked from further back.
-- Keep a candidate at the physical corner itself.  Larger offsets are useful
-- for broad corners, but pushing every candidate into the branch corridor can
-- put the Watcher in the middle of the hall (or inside the wall).
local STAND_OFFSETS = { 2.3, 2.9, 3.5, 1.5, 0.8, 0 }
-- Studs the feet travel toward the corner over the lean, boldest first. A step and a tip together
-- are what put a body past a door frame instead of an ear; see `PeekSpot.Step` for why the tip alone
-- cannot. Zero is kept as a last resort for the corner that has room to lean but none to step into.
local LEAN_STEPS = { 2.9, 2.2, 1.5, 0.8, 0 }
-- Corners to collect before a search calls it a day. Enough for the pick to be worth randomising,
-- few enough that a junction-dense floor does not cost a full sweep of the building.
local ENOUGH_SPOTS = 6

-- The ray fan, which finds the corners the hallway graph has no opinion about -- door frames above
-- all, and pillars, alcoves and the ends of wardrobes after that. Doorways are the reason it exists:
-- a room's frame opening onto a corridor is not a junction and the graph never mentions one, and it
-- is exactly the shape something leans out of.
--
-- A pair of neighbouring rays is an edge when the far one lands well past where the near one's
-- *surface*, carried on, would have put it -- not merely when the two depths differ. A flat wall seen
-- at a glancing angle puts neighbouring rays tens of studs apart on unbroken stone, and reading those
-- as corners is the old way of ending up leaning out of one.
local FAN_RAYS = 96
local FAN_RANGE = 150 -- studs; nothing further away is worth leaning out of
local BISECT_STEPS = 6
local PLANE_TOLERANCE = 2 -- studs the far ray may miss the near surface's plane by and still be it
local MIN_EDGE_GAP = 8 -- studs the far side must open up by, so there is somewhere to lean into
local MAX_WALL_NORMAL_Y = 0.5 -- |Y| of a near surface's normal past which it is floor, not wall
local OCCLUDER_HEIGHTS = { 1, 4.2 } -- studs above the floor a corner must still block at
local OCCLUDER_SLACK = 3 -- studs past the corner those probes may travel before giving up
local EDGE_DEPTHS = { 0, 1.5, 3 } -- studs past a fan edge to try the stance at

-- Points over the rig's silhouette, as (studs above the floor, studs across its width) in its own
-- upright frame. Both sets get tipped with the body, so they describe the same figure at any angle.
--
-- Being concealed is a question about the body, and deliberately not about the last inch of the
-- outline. Sampling the full four-and-a-half-stud span sounds more correct and is in practice
-- unsatisfiable: it forces the stance a full 2.25 studs behind the corner before it reads as hidden,
-- and the lean only has 3.8 studs of reach to spend, so what little is left over puts an ear past the
-- frame. Measured over the hotel, the wide outline left six positions in a hundred able to host a
-- Watcher at all.
--
-- What actually guarantees nobody sees it standing here is the view cone -- the spot is behind every
-- player and outside the wedge they are looking down, checked separately and never relaxed. This is
-- the second lock on the same door: enough of the body behind the corner that tipping back upright
-- reads as ducking out of view, rather than as a figure standing in the open going stiff.
local HIDE_SAMPLES = {
	{ 4.4, 0 },
	{ 4.0, 1.0 },
	{ 4.0, -1.0 },
	{ 3.0, 2.1 },
	{ 3.0, -2.1 },
	{ 2.0, 1.8 },
	{ 2.0, -1.8 },
	{ 0.8, 1.0 },
	{ 0.8, -1.0 },
}
-- Being found is a question about the head and shoulders, because those are the parts a tip actually
-- carries out past the corner -- the legs barely move and asking about them would rule out every
-- real corner. The head is first and asked on its own: shoulders past a frame with no head above
-- them is a shape, not a figure.
local LEAN_SAMPLES = {
	{ 4.4, 0 },
	{ 4.0, 0.9 },
	{ 4.0, -0.9 },
	{ 3.2, 0.7 },
	{ 3.2, -0.7 },
}
-- Of those five, past the head, before a lean counts as showing a figure. Two, because that is what
-- the reach affords: the far shoulder is on the wrong side of a body tipped away from it and stays
-- behind the frame in almost every real corner. A head and a near shoulder out past a door frame is
-- the shape in question; insisting on more of the body rules out the corners that can host it.
local LEAN_VISIBLE_SAMPLES = 2

--- A corner, expressed as where a figure waits and how it comes around it.
---
--- `Step` is small and load-bearing. A pure tip about planted feet is the honest way to describe
--- peeking and it does not reach: a head four and a half studs up travels 3.8 studs sideways at sixty
--- degrees, and a rig four and a half studs wide has to give up 2.25 of that just to have its
--- shoulders behind the corner while upright. Measured over the hotel, two hundred and sixty leans
--- were geometrically clear and four of them ended up visible to anybody. The rest of the reach has
--- to come from somewhere, and a foot that slides a stud or two toward the corner as the body goes
--- over is both where people actually get it from and the difference between a head at the edge of a
--- door frame and a body plainly leaning out of one.
export type PeekSpot = {
	Stand: Vector3, -- floor position out of everybody's sight, where it waits upright
	Step: number, -- studs the feet travel along `Lateral` over the course of the lean
	Lateral: Vector3, -- horizontal unit vector it tips and steps along to come past the corner
	Facing: Vector3, -- horizontal direction it faces while it does, back down the corridor
	LeanAngle: number, -- degrees of tip at full extension
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

		if castSample(params, eye, middle).Distance - nearDistance < MIN_EDGE_GAP then
			blind = middle
		else
			seen = middle
		end
	end
	return blind, seen
end

-- Whether the thing forming a fan-found edge screens a standing figure top to bottom. A depth
-- discontinuity at eye height is just as happily the end of a desk or the top of a stair rail, and
-- neither hides anything from somebody looking at the floor behind it.
--
-- `direction` must be the fan ray that found the surface, not the bisected one that pins the edge
-- down. Bisection deliberately lands a fraction of a degree off the silhouette, so a probe along it
-- grazes the surface by inches -- close enough that a skirting board, a seam between two wall parts
-- or a doorway's trim decides the answer. Measured over the hotel that rejects five corners in six,
-- almost all of them real. The unrefined ray is a few degrees into the same surface, and rejects the
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

--- The body's own axes after tipping `angle` degrees along `lateral`. Everything about a leaning rig
--- -- where its head is, which way its shoulders run, where its bounding box sits -- comes from these
--- two vectors, so they are computed in one place and handed around rather than re-derived.
local function leanAxes(lateral: Vector3, angle: number): (Vector3, Vector3)
	local radians = math.rad(angle)
	local cosine, sine = math.cos(radians), math.sin(radians)
	local up = Vector3.yAxis * cosine + lateral * sine
	local across = lateral * cosine - Vector3.yAxis * sine
	return up, across
end

--- Where the feet are at `lean` of the way out -- 0 waiting upright, 1 fully committed.
local function footAt(spot: PeekSpot, lean: number): Vector3
	return spot.Stand + spot.Lateral * (spot.Step * lean)
end

--- Where a figure `lean` of the way out of `spot` presents the given sample points. One definition of
--- the pose, used by every check here and by the class that drives the rig, so that what was measured
--- for clearance is what ends up on screen.
local function bodyPoints(samples: { { number } }, spot: PeekSpot, lean: number): { Vector3 }
	local up, across = leanAxes(spot.Lateral, spot.LeanAngle * lean)
	local foot = footAt(spot, lean)

	local points = table.create(#samples)
	for index, sample in samples do
		points[index] = foot + up * sample[1] + across * sample[2]
	end
	return points
end

-- Points over the upper body, which is the part a tip actually carries anywhere. Wider than the set
-- used for being found, because this asks what the lean might *hit* rather than what shows: the far
-- shoulder travels the same arc as the near one and is just as capable of going through a door frame.
-- The top of this set sits above the head rather than at it. The head is the point that travels
-- furthest through the arc, so it is the one that finds a door frame first, and tracing a path
-- through its centre leaves the top of the skull to sweep an unexamined half stud. That was the last
-- clip left standing once the rest of this was right.
local ARC_SAMPLES = {
	{ 5.0, 0 },
	{ 4.6, 0.6 },
	{ 4.6, -0.6 },
	{ 4.2, 1.1 },
	{ 4.2, -1.1 },
	{ 3.6, 2.1 },
	{ 3.6, -2.1 },
	{ 2.8, 1.8 },
	{ 2.8, -1.8 },
	{ 2.0, 1.2 },
	{ 2.0, -1.2 },
}

-- The floor position a figure could stand on at this horizontal position, or nil where one could
-- not: no floor under it, a floor belonging to another storey, or no room to stand upright in.
local function findStanding(search: Search, position: Vector3, facing: Vector3): Vector3?
	local from = Vector3.new(position.X, search.FloorY + FLOOR_PROBE_UP, position.Z)
	local drop = Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0)
	local result = workspace:Raycast(from, drop, search.Params)
	if not result or math.abs(result.Position.Y - search.FloorY) > MAX_FLOOR_DROP then return nil end

	local centre = result.Position + Vector3.new(0, RIG_SIZE.Y / 2 + STANDING_CLEARANCE, 0)
	local frame = CFrame.lookAt(centre, centre + facing)
	if #workspace:GetPartBoundsInBox(frame, RIG_SIZE, search.Overlap) > 0 then return nil end
	return result.Position
end

-- Whether there is floor to put a foot on at this horizontal position, on the storey the search is
-- about. Asked of where a step lands, which the standing box was never asked about: that question was
-- put a step away, and about a body standing straight up rather than one half way over.
local function hasFloorAt(search: Search, position: Vector3): boolean
	local from = Vector3.new(position.X, search.FloorY + FLOOR_PROBE_UP, position.Z)
	local drop = Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0)
	local result = workspace:Raycast(from, drop, search.Params)
	return result ~= nil and math.abs(result.Position.Y - search.FloorY) <= MAX_FLOOR_DROP
end

-- How much of a figure `eye` can make out, and whether its head is part of it.
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

--- Whether nobody's camera can see any part of a figure standing there. A clear ray outside the
--- player's view cone is not a sighting in first person, so camera aim is part of this test rather
--- than treating every unobstructed point around the player as visible.
local function isHiddenFromEveryone(search: Search, points: { Vector3 }): boolean
	for _, view in search.Views do
		for _, point in points do
			if EnemyObservationService.IsWithinCone(view, point, search.Options.ViewCone)
				and isClear(search.Params, view.Eye, point)
			then
				return false
			end
		end
	end
	return true
end

-- Whether a figure there would be off every player's screen. Aim only, and deliberately: this is
-- asked of the place a Watcher will *become* visible in, so the wall currently between it and
-- somebody is no reassurance at all -- what matters is that when it does tip out, it tips out behind
-- them.
local function isOutOfView(search: Search, points: { Vector3 }): boolean
	for _, view in search.Views do
		for _, point in points do
			if EnemyObservationService.IsWithinCone(view, point, search.Options.ViewCone) then
				return false
			end
		end
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

--- Whether the rig can tip the whole way to `angle` without any part of it meeting the world.
---
--- Traced as the paths the upper body's own points take, rather than as a box swung through the arc.
--- A box is the obvious thing to reach for and it is wrong here: the rig pivots about its feet, so a
--- rigid box rotated about that point drives its lower corners down through the floor at any angle
--- worth leaning, and every candidate is rejected. Real feet stay planted and only the body above
--- them travels, which is exactly what these paths describe. The floor the rig is standing on is
--- therefore not in the way, and a wall still is.
---
--- The ends alone would not do: the arc is a long one, and the shoulder that clears a door frame at
--- forty-five degrees may well have gone through it at twenty.
local function isArcClear(search: Search, spot: PeekSpot): boolean
	local previous = bodyPoints(ARC_SAMPLES, spot, 0)

	for step = 1, LEAN_ARC_STEPS do
		local current = bodyPoints(ARC_SAMPLES, spot, step / LEAN_ARC_STEPS)
		for index, point in current do
			local from = previous[index]
			local direction = point - from
			if direction.Magnitude >= 1e-3
				and workspace:Spherecast(from, ARC_RADIUS, direction, search.Params) ~= nil
			then
				return false
			end
		end
		previous = current
	end
	return true
end

--- Whether the rig tipped to `angle` is worth being there: findable by the player it was found for,
--- and still off everybody's screen, all the way out and all the way along.
local function isLeanWorthwhile(search: Search, spot: PeekSpot, diagnostic: ((any) -> ())?): boolean
	local out = bodyPoints(LEAN_SAMPLES, spot, 1)
	local visible, headVisible = countVisible(search.Params, search.Eye, out)
	if not headVisible or visible < LEAN_VISIBLE_SAMPLES then
		if diagnostic then diagnostic({ reason = "lean_visibility", visible = visible, head = headVisible }) end
		return false
	end

	for step = 1, LEAN_ARC_STEPS do
		if not isOutOfView(search, bodyPoints(LEAN_SAMPLES, spot, step / LEAN_ARC_STEPS)) then
			if diagnostic then diagnostic({ reason = "lean_view", progress = step / LEAN_ARC_STEPS }) end
			return false
		end
	end
	return true
end

--- Turns one corner into a spot, or nil where nothing about it works out. Tightest tuck and boldest
--- lean win: both keep the figure hard against the corner, which is what makes the pose read as
--- leaning around it rather than standing near it.
local function placeOn(search: Search, corner: Corner, diagnostic: ((any) -> ())?): PeekSpot?
	local function reject(reason: string, depth: number, offset: number, angle: number?, step: number?)
		if diagnostic then
			diagnostic({
				reason = reason,
				depth = depth,
				offset = offset,
				angle = angle,
				step = step,
			})
		end
	end
	-- Square to the corner, so tipping along its lateral is a clean roll rather than a stumble, and
	-- so it stares back down the corridor the player will come to look up.
	local facing = -corner.Axis
	facing = horizontal(facing - corner.Lateral * facing:Dot(corner.Lateral))
	if facing.Magnitude < 1e-3 then return nil end
	facing = facing.Unit

	for _, depth in corner.Depths do
		local base = corner.Position + corner.Axis * depth

		for _, offset in STAND_OFFSETS do
			local stand = findStanding(search, base - corner.Lateral * offset, facing)
			if not stand then
				reject("stand", depth, offset)
				continue
			end

			-- Upright and unseen is the whole premise; no lean is worth checking without it. Lean 0
			-- puts the feet on `Stand` whatever the step and angle are, so one probe settles it.
			local upright: PeekSpot = {
				Stand = stand,
				Step = 0,
				Lateral = corner.Lateral,
				Facing = facing,
				LeanAngle = 0,
			}
			if not isHiddenFromEveryone(search, bodyPoints(HIDE_SAMPLES, upright, 0)) then
				reject("upright_visible", depth, offset)
				continue
			end

			for _, angle in LEAN_ANGLES do
				for _, step in LEAN_STEPS do
					-- The feet have to end up somewhere there is floor. The upright box check does not
					-- cover it -- that was asked a step away and of a body standing straight up.
					if step > 0 and not hasFloorAt(search, stand + corner.Lateral * step) then
						reject("step_floor", depth, offset, angle, step)
						continue
					end

					local spot: PeekSpot = {
						Stand = stand,
						Step = step,
						Lateral = corner.Lateral,
						Facing = facing,
						LeanAngle = angle,
					}
					if not isArcClear(search, spot) then
						reject("arc", depth, offset, angle, step)
						continue
					end
					if not isLeanWorthwhile(search, spot, function(result)
							reject(result.reason, depth, offset, angle, step)
					end) then
						continue
					end
					if diagnostic then
						diagnostic({ reason = "success", depth = depth, offset = offset, angle = angle, step = step })
					end
					return spot
				end
			end
		end
	end
	return nil
end

--- Silhouette edges around the player, for the geometry the hallway graph says nothing about.
local function findFanCorners(search: Search): { Corner }
	local params, eye = search.Params, search.Eye

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
		-- the far side has to open up enough to give a figure somewhere to have leaned into.
		if far.Distance - near.Distance < MIN_EDGE_GAP then continue end
		if not near.Normal or math.abs(near.Normal.Y) > MAX_WALL_NORMAL_Y then continue end

		local blindDirection = if nearIsFirst then directions[index] else directions[neighbour]
		local farDirection = if nearIsFirst then directions[neighbour] else directions[index]
		local flat = planeDistance(eye, near, farDirection)
		if flat and math.abs(flat - far.Distance) <= PLANE_TOLERANCE then continue end -- same wall, edge-on

		-- Filtered before the expensive checks rather than in the caller, which repeats them
		-- harmlessly: an edge in front of the player or across the building is two raycasts saved.
		local position = eye + blindDirection * near.Distance
		if near.Distance < search.Options.MinDistance or near.Distance > search.Options.MaxDistance then continue end
		if not isWithinArc(eye, search.Back, position, search.Options.RearArc) then continue end
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

local function shuffle<T>(items: { T }): { T }
	for index = #items, 2, -1 do
		local swap = math.random(index)
		items[index], items[swap] = items[swap], items[index]
	end
	return items
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

--- A corner behind `player` to lean around, or nil while the hallways around them offer none. The
--- search is a few hundred casts and runs on the calling thread; it is meant to be asked once per
--- peek, not once per frame.
function PeekSpotService:Find(player: Player, options: FindOptions): PeekSpot?
	local search = buildSearch(player, options)
	if not search then return nil end

	local function collect(corners: { Corner }): { PeekSpot }
		local spots = {}
		for _, corner in shuffle(corners) do
			if #spots >= ENOUGH_SPOTS then break end
			if not isWithinArc(search.Eye, search.Back, corner.Position, options.RearArc) then continue end

			local spot = placeOn(search, corner)
			if spot then
				table.insert(spots, spot)
			end
		end
		return spots
	end

	-- Junctions first, and the fan only when none of them worked out. A corridor mouth the map states
	-- outright is a better corner than one inferred from a depth discontinuity, and in a corridor the
	-- common case costs no fan at all.
	local spots = collect(HallwayGridService:GetCorners(
		search.Eye,
		search.FloorY,
		options.MinDistance,
		options.MaxDistance
	))

	if #spots == 0 then
		spots = collect(findFanCorners(search))
	end

	if #spots == 0 then return nil end
	return spots[math.random(#spots)]
end

-- Debug-only inspection used by the Studio playtest helper. It is intentionally narrow: callers
-- name one graph corner and get the exact rejection stage for each pose tried there.
function PeekSpotService:DebugCorner(player: Player, options: FindOptions, position: Vector3): any
	local search = buildSearch(player, options)
	if not search then return nil end

	for _, corner in HallwayGridService:GetCorners(
		search.Eye,
		search.FloorY,
		options.MinDistance,
		options.MaxDistance
	) do
		if (corner.Position - position).Magnitude <= 4 then
			local checks = {}
			local spot = placeOn(search, corner, function(result)
				table.insert(checks, result)
			end)
			return {
				Corner = corner.Position,
				Axis = corner.Axis,
				Lateral = corner.Lateral,
				Spot = spot,
				Checks = checks,
			}
		end
	end
	return nil
end

--- Whether a spot still holds up: nobody can see it standing there, and the lean still comes out
--- somewhere clear, findable and off every screen.
---
--- A spot is found once and used for tens of seconds. Doors open and other players wander in, and a
--- corner worth waiting behind when it was chosen is not necessarily one worth leaning out of now.
function PeekSpotService:IsStillValid(spot: PeekSpot, player: Player, options: FindOptions): boolean
	local search = buildSearch(player, options)
	if not search then return false end

	if not isHiddenFromEveryone(search, bodyPoints(HIDE_SAMPLES, spot, 0)) then return false end
	if not isArcClear(search, spot) then return false end

	return isLeanWorthwhile(search, spot)
end

--- The head and shoulders at `lean` of the way out, for a caller that has to ask its own questions
--- about them frame by frame. Exported so that "is the place it is about to appear on somebody's
--- screen" is asked of the same points this service qualified the spot with, rather than of a guess
--- at where the head goes.
function PeekSpotService.LeanPoints(spot: PeekSpot, lean: number): { Vector3 }
	return bodyPoints(LEAN_SAMPLES, spot, lean)
end

--- Where the rig's root belongs, and which way up it is, at `lean` of the way out of `spot`. The
--- caller owns the timing; this owns the pose, so that the same arithmetic that was checked for
--- clearance is the arithmetic that places the model.
function PeekSpotService.PoseAt(spot: PeekSpot, lean: number, lookAt: Vector3?): CFrame
	local up = leanAxes(spot.Lateral, spot.LeanAngle * lean)
	local foot = footAt(spot, lean)
	local position = foot + up * ROOT_HEIGHT

	-- `lookAt` orthogonalises its up vector against the viewing direction. If the root is simply
	-- placed at `foot + up * ROOT_HEIGHT`, that small correction moves the model pivot off its
	-- planted feet (most notably at the shallow corner pose). Solve the root position against the
	-- actual frame up vector so the model pivot stays on the same foot point the search checked.
	local frame: CFrame
	for _ = 1, 6 do
		local target = lookAt and Vector3.new(lookAt.X, position.Y, lookAt.Z) or position + spot.Facing
		if (target - position).Magnitude < 1e-3 then
			target = position + spot.Facing
		end
		frame = CFrame.lookAt(position, target, up)
		position = foot + frame.UpVector * ROOT_HEIGHT
	end

	local target = lookAt and Vector3.new(lookAt.X, position.Y, lookAt.Z) or position + spot.Facing
	if (target - position).Magnitude < 1e-3 then
		target = position + spot.Facing
	end
	return CFrame.lookAt(position, target, up)
end

return PeekSpotService
