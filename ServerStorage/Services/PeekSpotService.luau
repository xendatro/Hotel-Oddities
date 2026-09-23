local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HallwayGridService = require(ServerStorage.Services.HallwayGridService)
local MathService = require(ReplicatedStorage.Services.MathService)
local PeekPoseConfig = require(ServerStorage.Configs.PeekPoseConfig)
local SpawnZoneService = require(ReplicatedStorage.Services.SpawnZoneService)

local horizontal = MathService.Horizontal

local ENEMY_TAG = "Enemy"

local EYE_OFFSET = 1.5
local PLAYER_ROOT_HEIGHT = 3
local RIG_SIZE = Vector3.new(1.4, 5.2, 1.0)
local STANDING_CLEARANCE = 0.5
local FLOOR_PROBE_UP = 8
local FLOOR_PROBE_DOWN = 20
local MAX_FLOOR_DROP = 3
local MAX_YAW = 25
local DEFAULT_EXPOSURE = 1.6
local MIN_EXPOSURE = 0.5
local EXPOSURE_TRIES = { 0, 0.5, -0.5, 1 }
local SWEEP_FLOOR_CLEARANCE = 0.1
local ENOUGH_SPOTS = 6
local PEEK_VISIBLE_SAMPLES = 2
local SIDE_PENALTY = 1

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

export type PeekSpot = {
	Stand: Vector3,
	Root: CFrame,
	HiddenRoot: CFrame,
	Side: "Left" | "Right",
	Scale: number,
	RootHeight: number,
	Lateral: Vector3,
	Facing: Vector3,
}

export type FindOptions = {
	MinDistance: number,
	MaxDistance: number,
	RearArc: number,
	ViewCone: number,
	FogFraction: number?,
	Exposure: number?,
	Scale: number?,
	RootHeight: number?,
}

export type Corner = HallwayGridService.Corner

type Frame = { Time: number, Points: { { number } } }

type Search = {
	Params: RaycastParams,
	Overlap: OverlapParams,
	Eye: Vector3,
	Back: Vector3,
	FloorY: number,
	MaxDistance: number,
	Views: { EnemyObservationService.View },
	Options: FindOptions,
	Scale: number,
	RootHeight: number,
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

local function hiddenPoints(spot: PeekSpot): { Vector3 }
	local across = spot.HiddenRoot.RightVector
	local points = table.create(#HIDE_SAMPLES)
	for index, sample in HIDE_SAMPLES do
		points[index] = spot.Stand + Vector3.yAxis * (sample[1] * spot.Scale) + across * (sample[2] * spot.Scale)
	end
	return points
end

local function framePoints(spot: PeekSpot, frame: Frame): { Vector3 }
	local mirror = if spot.Side == "Right" then 1 else -1
	local points = table.create(#frame.Points)
	for index, offset in frame.Points do
		points[index] = spot.Root:PointToWorldSpace(Vector3.new(offset[1] * mirror, offset[2], offset[3]) * spot.Scale)
	end
	return points
end

local function peekPoints(spot: PeekSpot): { Vector3 }
	return framePoints(spot, PeekPoseConfig.Frames[1])
end

local function probeFloor(search: Search, position: Vector3): Vector3?
	local from = Vector3.new(position.X, search.FloorY + FLOOR_PROBE_UP, position.Z)
	local drop = Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0)
	local result = workspace:Raycast(from, drop, search.Params)
	if not result or math.abs(result.Position.Y - search.FloorY) > MAX_FLOOR_DROP then return nil end
	return result.Position
end

local function findStanding(search: Search, position: Vector3, facing: Vector3): Vector3?
	local floor = probeFloor(search, position)
	if not floor then return nil end

	local size = RIG_SIZE * search.Scale
	local centre = floor + Vector3.new(0, size.Y / 2 + STANDING_CLEARANCE, 0)
	local frame = CFrame.lookAt(centre, centre + facing)
	if #workspace:GetPartBoundsInBox(frame, size, search.Overlap) > 0 then return nil end
	return floor
end

local function countVisible(params: RaycastParams, eye: Vector3, points: { Vector3 }): (number, boolean)
	local count, head = 0, false
	for index, point in points do
		if isClear(params, eye, point) then
			count += 1
			if index == PeekPoseConfig.Head then
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

local function liftAboveFloor(spot: PeekSpot, point: Vector3, radius: number): Vector3
	local minimum = spot.Root.Position.Y - spot.RootHeight + radius + SWEEP_FLOOR_CLEARANCE
	return if point.Y < minimum then Vector3.new(point.X, minimum, point.Z) else point
end

local function isPoseClear(search: Search, spot: PeekSpot): boolean
	local radius = PeekPoseConfig.SweepRadius * spot.Scale
	local frames = PeekPoseConfig.Frames
	local origin = spot.Root.Position

	local previous = framePoints(spot, frames[1])
	for index, point in previous do
		point = liftAboveFloor(spot, point, radius)
		previous[index] = point
		local direction = point - origin
		if direction.Magnitude >= 1e-3 and workspace:Spherecast(origin, radius, direction, search.Params) ~= nil then
			return false
		end
	end

	for frameIndex = 2, #frames do
		local current = framePoints(spot, frames[frameIndex])
		for index, point in current do
			point = liftAboveFloor(spot, point, radius)
			current[index] = point
			local from = previous[index]
			local direction = point - from
			if direction.Magnitude >= 1e-3 and workspace:Spherecast(from, radius, direction, search.Params) ~= nil then
				return false
			end
		end
		previous = current
	end
	return true
end

local function hasFloorUnderFeet(search: Search, spot: PeekSpot): boolean
	local points = peekPoints(spot)
	for _, index in PeekPoseConfig.Feet do
		if not probeFloor(search, points[index]) then return false end
	end
	return true
end

local function isPeekVisible(search: Search, spot: PeekSpot): (boolean, number, boolean)
	local visible, headVisible = countVisible(search.Params, search.Eye, peekPoints(spot))
	return headVisible and visible >= PEEK_VISIBLE_SAMPLES, visible, headVisible
end

local function isPeekWorthwhile(search: Search, spot: PeekSpot, diagnostic: ((any) -> ())?): boolean
	local seen, visible, headVisible = isPeekVisible(search, spot)
	if not seen then
		if diagnostic then diagnostic({ reason = "peek_visibility", visible = visible, head = headVisible }) end
		return false
	end
	if not isOutOfView(search, peekPoints(spot)) then
		if diagnostic then diagnostic({ reason = "peek_view" }) end
		return false
	end
	return true
end

local function aimRoot(position: Vector3, facing: Vector3, eye: Vector3): CFrame
	local look = facing
	local toEye = horizontal(eye - position)
	if toEye.Magnitude > 1e-3 then
		toEye = toEye.Unit
		local angle = math.deg(math.acos(math.clamp(facing:Dot(toEye), -1, 1)))
		if angle <= MAX_YAW then
			look = toEye
		else
			local sign = if facing:Cross(toEye).Y >= 0 then 1 else -1
			look = CFrame.Angles(0, math.rad(MAX_YAW * sign), 0) * facing
		end
	end
	return CFrame.lookAt(position, position + look)
end

local function exposures(search: Search): { number }
	local base = search.Options.Exposure or DEFAULT_EXPOSURE
	local list = {}
	for _, delta in EXPOSURE_TRIES do
		local exposure = base + delta
		if exposure >= MIN_EXPOSURE then
			table.insert(list, exposure)
		end
	end
	return list
end

local function placeOn(search: Search, corner: Corner, diagnostic: ((any) -> ())?): PeekSpot?
	local function reject(reason: string, depth: number, exposure: number)
		if diagnostic then
			diagnostic({ reason = reason, depth = depth, exposure = exposure })
		end
	end

	local facing = -corner.Axis
	facing = horizontal(facing - corner.Lateral * facing:Dot(corner.Lateral))
	if facing.Magnitude < 1e-3 then return nil end
	facing = facing.Unit

	local lateral = corner.Lateral
	local scale, rootHeight = search.Scale, search.RootHeight

	for _, depth in corner.Depths do
		local base = corner.Position + corner.Axis * depth

		for _, exposure in exposures(search) do
			local offset = PeekPoseConfig.HeadReach * scale - exposure
			local peekFoot = probeFloor(search, base - lateral * offset)
			if not peekFoot then
				reject("peek_floor", depth, exposure)
				continue
			end

			local root = aimRoot(peekFoot + Vector3.yAxis * rootHeight, facing, search.Eye)
			local side: "Left" | "Right" = if lateral:Dot(root.RightVector) < 0 then "Right" else "Left"
			local mirror = if side == "Right" then 1 else -1
			local hiddenCentre = root:PointToWorldSpace(Vector3.new(PeekPoseConfig.Shift * mirror * scale, 0, 0))
			local stand = findStanding(search, hiddenCentre, root.LookVector)
			if not stand then
				reject("stand", depth, exposure)
				continue
			end

			local spot: PeekSpot = {
				Stand = stand,
				Root = root,
				HiddenRoot = root.Rotation + (stand + Vector3.yAxis * rootHeight),
				Side = side,
				Scale = scale,
				RootHeight = rootHeight,
				Lateral = lateral,
				Facing = facing,
			}

			local waiting = hiddenPoints(spot)
			if not isConcealedFrom(search, waiting) then
				reject("upright_exposed", depth, exposure)
				continue
			end
			if not isHiddenFromEveryone(search, waiting) then
				reject("upright_visible", depth, exposure)
				continue
			end
			if not hasFloorUnderFeet(search, spot) then
				reject("peek_feet", depth, exposure)
				continue
			end
			if not isPoseClear(search, spot) then
				reject("arc", depth, exposure)
				continue
			end
			local seen, visible, headVisible = isPeekVisible(search, spot)
			if not seen then
				if diagnostic then
					diagnostic({ reason = "peek_visibility", depth = depth, exposure = exposure, visible = visible, head = headVisible })
				end
				continue
			end
			if diagnostic then
				diagnostic({ reason = "success", depth = depth, exposure = exposure, side = side })
			end
			return spot
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
	local scale = options.Scale or 1

	return {
		Params = params,
		Overlap = overlap,
		Eye = eye,
		Back = -horizontal(facing),
		FloorY = root.Position.Y - PLAYER_ROOT_HEIGHT,
		MaxDistance = PeekSpotService:GetMaxDistance(player, options),
		Views = EnemyObservationService:GetViews(),
		Options = options,
		Scale = scale,
		RootHeight = options.RootHeight or PLAYER_ROOT_HEIGHT * scale,
	}
end

local function scoreSpot(search: Search, spot: PeekSpot): number
	local offset = horizontal(spot.Stand - search.Eye)
	local distance = offset.Magnitude
	if distance < 1e-3 or search.Back.Magnitude < 1e-3 then return distance end

	local alignment = math.clamp(offset.Unit:Dot(search.Back.Unit), -1, 1)
	return distance * (1 + math.deg(math.acos(alignment)) / 180 * SIDE_PENALTY)
end

function PeekSpotService:GetMaxDistance(player: Player, options: FindOptions): number
	local fraction = options.FogFraction
	local fogStart, fogEnd = EnemyObservationService:GetFogRange(player)
	if not (fraction and fogStart and fogEnd) then return options.MaxDistance end
	return math.min(options.MaxDistance, fogStart + (fogEnd - fogStart) * fraction)
end

function PeekSpotService:Find(player: Player, options: FindOptions): PeekSpot?
	local search = buildSearch(player, options)
	if not search then return nil end
	if search.MaxDistance < options.MinDistance then return nil end

	local spots = {}
	for _, corner in shuffle(HallwayGridService:GetCorners(
		search.Eye,
		search.FloorY,
		options.MinDistance,
		search.MaxDistance
	)) do
		if #spots >= ENOUGH_SPOTS then break end
		if not isWithinArc(search.Eye, search.Back, corner.Position, options.RearArc) then continue end

		local spot = placeOn(search, corner)
		if spot and not SpawnZoneService:Contains(spot.Stand) then
			table.insert(spots, spot)
		end
	end

	local best, bestScore = nil, math.huge
	for _, spot in spots do
		local score = scoreSpot(search, spot)
		if score < bestScore then
			best, bestScore = spot, score
		end
	end
	return best
end

function PeekSpotService:IsInSight(spot: PeekSpot, player: Player, options: FindOptions): boolean
	local search = buildSearch(player, options)
	if not search then return false end
	if horizontal(spot.Stand - search.Eye).Magnitude > search.MaxDistance then return false end
	return (isPeekVisible(search, spot))
end

function PeekSpotService:DebugCorner(player: Player, options: FindOptions, position: Vector3): any
	local search = buildSearch(player, options)
	if not search then return nil end

	for _, corner in HallwayGridService:GetCorners(
		search.Eye,
		search.FloorY,
		options.MinDistance,
		search.MaxDistance
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

	local waiting = hiddenPoints(spot)
	if not isConcealedFrom(search, waiting) then return false end
	if not isHiddenFromEveryone(search, waiting) then return false end
	if not isPoseClear(search, spot) then return false end

	return isPeekWorthwhile(search, spot)
end

function PeekSpotService.PeekPoints(spot: PeekSpot): { Vector3 }
	return peekPoints(spot)
end

return PeekSpotService
