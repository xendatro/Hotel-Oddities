local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HallwayGridService = require(ServerStorage.Services.HallwayGridService)
local MathService = require(ReplicatedStorage.Services.MathService)

local horizontal = MathService.Horizontal

local ENEMY_TAG = "Enemy"

local EYE_OFFSET = 1.5
local ROOT_HEIGHT = 3
local RIG_SIZE = Vector3.new(1.4, 5.2, 1.0)
local STANDING_CLEARANCE = 0.5
local FLOOR_PROBE_UP = 8
local FLOOR_PROBE_DOWN = 20
local MAX_FLOOR_DROP = 3

--- Tried in order and the first that fits wins, so the deepest lean the corner
--- can take comes first and the shallow ones are only fallbacks.
local LEAN_ANGLES = { 68, 60, 52, 45, 28 }
local LEAN_ARC_STEPS = 4
local ARC_RADIUS = 0.6
local STAND_OFFSETS = { 2.3, 2.9, 3.5, 1.5, 0.8, 0 }
local LEAN_STEPS = { 2.9, 2.2, 1.5, 0.8, 0 }
local ENOUGH_SPOTS = 6

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
local LEAN_SAMPLES = {
	{ 4.4, 0 },
	{ 4.0, 0.9 },
	{ 4.0, -0.9 },
	{ 3.2, 0.7 },
	{ 3.2, -0.7 },
}
local LEAN_VISIBLE_SAMPLES = 2

export type PeekSpot = {
	Stand: Vector3,
	Step: number,
	Lateral: Vector3,
	Facing: Vector3,
	LeanAngle: number,
}

export type FindOptions = {
	MinDistance: number,
	MaxDistance: number,
	RearArc: number,
	ViewCone: number,
}

export type Corner = HallwayGridService.Corner

type Search = {
	Params: RaycastParams,
	Overlap: OverlapParams,
	Eye: Vector3,
	Back: Vector3,
	FloorY: number,
	Views: { EnemyObservationService.View },
	Options: FindOptions,
}

local PeekSpotService = {}

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

local function leanAxes(lateral: Vector3, angle: number): (Vector3, Vector3)
	local radians = math.rad(angle)
	local cosine, sine = math.cos(radians), math.sin(radians)
	local up = Vector3.yAxis * cosine + lateral * sine
	local across = lateral * cosine - Vector3.yAxis * sine
	return up, across
end

local function footAt(spot: PeekSpot, lean: number): Vector3
	return spot.Stand + spot.Lateral * (spot.Step * lean)
end

local function bodyPoints(samples: { { number } }, spot: PeekSpot, lean: number): { Vector3 }
	local up, across = leanAxes(spot.Lateral, spot.LeanAngle * lean)
	local foot = footAt(spot, lean)

	local points = table.create(#samples)
	for index, sample in samples do
		points[index] = foot + up * sample[1] + across * sample[2]
	end
	return points
end

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

local function hasFloorAt(search: Search, position: Vector3): boolean
	local from = Vector3.new(position.X, search.FloorY + FLOOR_PROBE_UP, position.Z)
	local drop = Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0)
	local result = workspace:Raycast(from, drop, search.Params)
	return result ~= nil and math.abs(result.Position.Y - search.FloorY) <= MAX_FLOOR_DROP
end

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

local function isConcealedFrom(search: Search, points: { Vector3 }): boolean
	for _, point in points do
		if isClear(search.Params, search.Eye, point) then return false end
	end
	return true
end

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

local function isWithinArc(origin: Vector3, facing: Vector3, point: Vector3, arc: number): boolean
	if arc >= 360 then return true end

	local offset = horizontal(point - origin)
	local look = horizontal(facing)
	if offset.Magnitude < 1e-3 or look.Magnitude < 1e-3 then return true end

	local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(look.Unit), -1, 1)))
	return angle <= arc / 2
end

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

			local upright: PeekSpot = {
				Stand = stand,
				Step = 0,
				Lateral = corner.Lateral,
				Facing = facing,
				LeanAngle = 0,
			}
			local waiting = bodyPoints(HIDE_SAMPLES, upright, 0)
			if not isConcealedFrom(search, waiting) then
				reject("upright_exposed", depth, offset)
				continue
			end
			if not isHiddenFromEveryone(search, waiting) then
				reject("upright_visible", depth, offset)
				continue
			end

			for _, angle in LEAN_ANGLES do
				for _, step in LEAN_STEPS do
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

	local spots = collect(HallwayGridService:GetCorners(
		search.Eye,
		search.FloorY,
		options.MinDistance,
		options.MaxDistance
	))
	if #spots == 0 then return nil end

	local best, bestDistance = nil, math.huge
	for _, spot in spots do
		local distance = (spot.Stand - search.Eye).Magnitude
		if distance < bestDistance then
			best, bestDistance = spot, distance
		end
	end
	return best
end

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

function PeekSpotService:IsStillValid(spot: PeekSpot, player: Player, options: FindOptions): boolean
	local search = buildSearch(player, options)
	if not search then return false end

	local waiting = bodyPoints(HIDE_SAMPLES, spot, 0)
	if not isConcealedFrom(search, waiting) then return false end
	if not isHiddenFromEveryone(search, waiting) then return false end
	if not isArcClear(search, spot) then return false end

	return isLeanWorthwhile(search, spot)
end

function PeekSpotService.LeanPoints(spot: PeekSpot, lean: number): { Vector3 }
	return bodyPoints(LEAN_SAMPLES, spot, lean)
end

function PeekSpotService.PoseAt(spot: PeekSpot, lean: number, lookAt: Vector3?): CFrame
	local up = leanAxes(spot.Lateral, spot.LeanAngle * lean)
	local foot = footAt(spot, lean)
	local position = foot + up * ROOT_HEIGHT

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
