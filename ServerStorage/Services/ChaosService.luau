local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local HallwayGraphService = require(ReplicatedStorage.Services.HallwayGraphService)
local LightService = require(ServerStorage.Services.LightService)
local MapOddityService = require(ServerStorage.Services.MapOddityService)

local ROUTE_ATTEMPTS = 8
local START_CANDIDATES = 3
local SEARCH_BUDGET = 15000
local SEARCH_SECONDS = 0.01
local SEARCH_MAX_DEPTH = 512
local SEARCH_CLOCK_STRIDE = 256
local TIE_JITTER = 0.5
local WARNING_POLL = 0.25
local CRASH_PROBE = 96
local CRASH_MARGIN = 1.5
local SPAN_ALIGNMENT = 0.9
local DOORWAY_TAG = "Doorway"
local ENEMY_FOLDER = "Enemies"

type RouteNode = HallwayGraphService.RouteNode

export type WarningToken = {
	Cancelled: boolean,
	Run: number,
	Lights: { Model },
	Oddities: { number },
	Retract: () -> (),
}

type PendingWarning = {
	WarnAt: number,
	ExpiresAt: number,
	IsNearPlayer: ({ Vector3 }) -> boolean,
	Fire: (WarningToken, number) -> (),
}

local ChaosService = {}
local Config = EnemyConfigs.Chaos
local PendingTokens: { WarningToken } = {}
local NextRun = 0

local horizontal = MathService.Horizontal

local function routePosition(node: RouteNode): Vector3
	return node.Position + Vector3.yAxis * Config.RouteHeight
end

local function livingRootPositions(): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function nearAny(positions: { Vector3 }, position: Vector3, range: number): boolean
	for _, playerPosition in positions do
		if (playerPosition - position).Magnitude <= range then return true end
	end
	return false
end

local function nearAnySpan(positions: { Vector3 }, span: Hallways.StraightSpan, range: number): boolean
	for _, playerPosition in positions do
		local along = math.clamp((playerPosition - span.Start):Dot(span.Axis), 0, span.Length)
		if (playerPosition - (span.Start + span.Axis * along)).Magnitude <= range then
			return true
		end
	end
	return false
end

local CrashParams = RaycastParams.new()
CrashParams.FilterType = Enum.RaycastFilterType.Exclude
CrashParams.RespectCanCollide = true
CrashParams.IgnoreWater = true
CrashParams.CollisionGroup = EnemyService.CollisionGroup

local function crashExclusions(): { Instance }
	local exclude = {}
	local enemies = workspace:FindFirstChild(ENEMY_FOLDER)
	if enemies then
		table.insert(exclude, enemies)
	end
	for _, doorway in CollectionService:GetTagged(DOORWAY_TAG) do
		if doorway:IsDescendantOf(workspace) then
			table.insert(exclude, doorway)
		end
	end
	return exclude
end

local function crashPoint(route: { Vector3 }): Vector3?
	local last = route[#route]
	local direction = horizontal(last - route[#route - 1])
	if direction.Magnitude < 1e-3 then return nil end
	direction = direction.Unit

	CrashParams.FilterDescendantsInstances = crashExclusions()

	local hit = workspace:Raycast(last, direction * CRASH_PROBE, CrashParams)
	if hit then
		local wall = Vector3.new(hit.Position.X, last.Y, hit.Position.Z)
		return wall - direction * CRASH_MARGIN
	end

	local span = Hallways.StraightSpanAt(last, direction)
	if span then
		local ahead = (span.Finish - last):Dot(direction)
		if ahead > 0 then
			return last + direction * (ahead + (Config.CrashOverrun or 0))
		end
	end
	return nil
end

local Rng = Random.new()
local NO_NEIGHBORS: { RouteNode } = {}
local AdjacencySource: { RouteNode }? = nil
local Adjacency: { [RouteNode]: { RouteNode } } = {}
local OptionPool: { { RouteNode } } = {}
local RankPool: { { number } } = {}

local function adjacency(): { [RouteNode]: { RouteNode } }
	local nodes = HallwayGraphService:Get()
	if AdjacencySource == nodes then return Adjacency end

	AdjacencySource = nodes
	Adjacency = {}
	for _, node in nodes do
		local neighbors = {}
		for neighbor in node.Neighbors do
			table.insert(neighbors, neighbor)
		end
		Adjacency[node] = neighbors
	end
	return Adjacency
end

local function bufferAt(pool: { { any } }, depth: number): { any }
	local buffer = pool[depth]
	if not buffer then
		buffer = {}
		pool[depth] = buffer
	end
	return buffer
end

local function unvisitedExits(
	neighbors: { [RouteNode]: { RouteNode } },
	node: RouteNode,
	visited: { [RouteNode]: boolean }
): number
	local count = 0
	for _, neighbor in neighbors[node] do
		if not visited[neighbor] then
			count += 1
		end
	end
	return count
end

local function findLongestWalk(
	path: { RouteNode },
	visited: { [RouteNode]: boolean },
	deadline: number
): { RouteNode }
	local best = table.clone(path)
	if os.clock() >= deadline then return best end

	local neighbors = adjacency()
	local steps = 0

	local function extend(current: RouteNode, depth: number)
		if steps >= SEARCH_BUDGET or depth > SEARCH_MAX_DEPTH then return end
		steps += 1
		if steps % SEARCH_CLOCK_STRIDE == 0 and os.clock() >= deadline then
			steps = SEARCH_BUDGET
			return
		end
		if #path > #best then
			best = table.clone(path)
		end

		local options = bufferAt(OptionPool, depth) :: { RouteNode }
		local ranks = bufferAt(RankPool, depth) :: { number }
		local count = 0
		for _, neighbor in neighbors[current] or NO_NEIGHBORS do
			if visited[neighbor] then continue end

			local rank = unvisitedExits(neighbors, neighbor, visited) + Rng:NextNumber() * TIE_JITTER
			local slot = count
			while slot > 0 and ranks[slot] > rank do
				options[slot + 1] = options[slot]
				ranks[slot + 1] = ranks[slot]
				slot -= 1
			end
			options[slot + 1] = neighbor
			ranks[slot + 1] = rank
			count += 1
		end

		for index = 1, count do
			local option = options[index]
			visited[option] = true
			table.insert(path, option)
			extend(option, depth + 1)
			table.remove(path)
			visited[option] = nil
			if steps >= SEARCH_BUDGET then return end
		end
	end

	extend(path[#path], 1)
	return best
end

local function toRoute(nodes: { RouteNode }): { Vector3 }?
	if #nodes < 2 then return nil end

	local route = {}
	for _, node in nodes do
		table.insert(route, routePosition(node))
	end

	local crash = crashPoint(route)
	if crash then
		table.insert(route, crash)
	end
	return route
end

local function planRoute(start: RouteNode, deadline: number): { Vector3 }?
	local nodes = findLongestWalk({ start }, { [start] = true }, deadline)
	return toRoute(nodes)
end

local function planRouteThrough(start: RouteNode, targetPosition: Vector3, deadline: number): { Vector3 }?
	local target = HallwayGraphService:FindNearestNode(targetPosition)
	if not target then return nil end

	local approach = HallwayGraphService:FindPath(start, target)
	if not approach then return nil end

	local visited: { [RouteNode]: boolean } = {}
	for _, node in approach do
		visited[node] = true
	end

	local nodes = findLongestWalk(table.clone(approach), visited, deadline)
	return toRoute(nodes)
end

local function distanceToRoute(position: Vector3, route: { Vector3 }): (number, number)
	local nearestDistance = math.huge
	local nearestTravel = 0
	local travelled = 0

	for index = 2, #route do
		local origin = route[index - 1]
		local destination = route[index]
		local offset = destination - origin
		local horizontalOffset = horizontal(offset)
		local horizontalLength = horizontalOffset.Magnitude
		local travelLength = offset.Magnitude
		if horizontalLength > 0 then
			local pointOffset = horizontal(position - origin)
			local alpha = math.clamp(
				pointOffset:Dot(horizontalOffset) / (horizontalLength * horizontalLength),
				0,
				1
			)
			local closest = horizontal(origin) + horizontalOffset * alpha
			local distance = (horizontal(position) - closest).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestTravel = travelled + travelLength * alpha
			end
		end
		travelled += travelLength
	end

	return nearestDistance, nearestTravel
end

local SPAN_HOLD_ACROSS = 2
local SPAN_HOLD_HEIGHT = 4

local function spanHolds(span: Hallways.StraightSpan, point: Vector3, direction: Vector3?): boolean
	if direction and math.abs(span.Axis:Dot(direction)) < SPAN_ALIGNMENT then return false end

	local offset = point - span.Center
	if math.abs(offset.Y) > SPAN_HOLD_HEIGHT then return false end
	if math.abs(offset:Dot(span.Axis)) > span.Length / 2 then return false end
	return math.abs(offset:Dot(Vector3.yAxis:Cross(span.Axis).Unit)) <= SPAN_HOLD_ACROSS
end

local function routeDirection(route: { Vector3 }, index: number): Vector3?
	if index < #route then
		local forward = horizontal(route[index + 1] - route[index])
		if forward.Magnitude > 1e-3 then return forward.Unit end
	end
	if index > 1 then
		local back = horizontal(route[index] - route[index - 1])
		if back.Magnitude > 1e-3 then return back.Unit end
	end
	return nil
end

local function collectWarnings(
	route: { Vector3 },
	spawnAt: number,
	spawnTime: number,
	run: number
): { PendingWarning }
	local pending: { PendingWarning } = {}
	local warningTime = Config.WarningTime
	local speed = Config.WalkSpeed

	for _, light in LightService:GetModels() do
		local lightPosition = light:GetPivot().Position
		local distance, travel = distanceToRoute(lightPosition, route)
		if distance > Config.LightRouteRange then continue end

		local arrivalAt = spawnAt + travel / speed
		table.insert(pending, {
			WarnAt = arrivalAt - warningTime,
			ExpiresAt = arrivalAt,
			IsNearPlayer = function(positions: { Vector3 })
				return nearAny(positions, lightPosition, Config.WarnRedCullRange or math.huge)
			end,
			Fire = function(token: WarningToken, remaining: number)
				LightService:WarnRed(light, remaining + (Config.LightPassDelay or 0))
				table.insert(token.Lights, light)
			end,
		})
	end

	local seenSpans: { [string]: boolean } = {}
	local previousSpan: Hallways.StraightSpan? = nil
	for index, point in route do
		local direction = routeDirection(route, index)

		local span = previousSpan
		if not span or not spanHolds(span, point, direction) then
			span = Hallways.StraightSpanAt(point, direction)
		end
		previousSpan = span
		if not span then continue end

		local key = string.format(
			"%d:%d:%d:%d",
			math.round(span.Center.X),
			math.round(span.Center.Z),
			math.round(math.abs(span.Axis.X) * 10),
			math.round(math.abs(span.Axis.Z) * 10)
		)
		if seenSpans[key] then continue end
		seenSpans[key] = true

		local _, startTravel = distanceToRoute(span.Start, route)
		local _, finishTravel = distanceToRoute(span.Finish, route)
		local arrivalAtStart = spawnTime + startTravel / speed
		local arrivalAtFinish = spawnTime + finishTravel / speed
		local firstAt = spawnAt + math.min(startTravel, finishTravel) / speed
		local lastAt = spawnAt + math.max(startTravel, finishTravel) / speed
		local resolved = span

		table.insert(pending, {
			WarnAt = firstAt - warningTime,
			ExpiresAt = lastAt,
			IsNearPlayer = function(positions: { Vector3 })
				return nearAnySpan(positions, resolved, Config.WarnHallwayCullRange or math.huge)
			end,
			Fire = function(token: WarningToken, remaining: number)
				local oddity = MapOddityService:Warn(
					resolved,
					remaining,
					arrivalAtStart,
					arrivalAtFinish,
					warningTime,
					run
				)
				if oddity then
					table.insert(token.Oddities, oddity)
				end
			end,
		})
	end

	return pending
end

local function scheduleWarnings(route: { Vector3 }, token: WarningToken, spawnAt: number, spawnTime: number)
	local pending = collectWarnings(route, spawnAt, spawnTime, token.Run)
	if #pending == 0 then return end

	table.sort(pending, function(first: PendingWarning, second: PendingWarning)
		return first.WarnAt < second.WarnAt
	end)

	task.spawn(function()
		local index = 1
		local waiting: { PendingWarning } = {}
		while not token.Cancelled do
			local now = os.clock()
			while index <= #pending and pending[index].WarnAt <= now do
				table.insert(waiting, pending[index])
				index += 1
			end

			if #waiting > 0 then
				local positions = livingRootPositions()
				for position = #waiting, 1, -1 do
					local warning = waiting[position]
					local remaining = warning.ExpiresAt - now
					if remaining <= 0 then
						table.remove(waiting, position)
					elseif warning.IsNearPlayer(positions) then
						warning.Fire(token, remaining)
						table.remove(waiting, position)
					end
				end
			end

			if index > #pending and #waiting == 0 then return end
			task.wait(WARNING_POLL)
		end
	end)
end

local function removePending(token: WarningToken)
	local index = table.find(PendingTokens, token)
	if index then
		table.remove(PendingTokens, index)
	end
end

local function newToken(): WarningToken
	local token: WarningToken
	NextRun += 1
	token = {
		Cancelled = false,
		Run = NextRun,
		Lights = {},
		Oddities = {},
		Retract = function()
			for _, light in token.Lights do
				LightService:ClearRed(light)
			end
			table.clear(token.Lights)
			for _, oddity in token.Oddities do
				MapOddityService:Clear(oddity)
			end
			table.clear(token.Oddities)
		end,
	}
	return token
end

local function beginRoute(route: { Vector3 }, onSpawned: ((any) -> ())?, onCancelled: (() -> ())?): boolean
	local token = newToken()
	local spawnAt = os.clock() + Config.SpawnDelay
	local spawnTime = workspace:GetServerTimeNow() + Config.SpawnDelay

	scheduleWarnings(route, token, spawnAt, spawnTime)

	local function abandon(reason: string?)
		token.Cancelled = true
		token.Retract()
		if reason then
			warn(`[Chaos] {reason}`)
		end
		if onCancelled then
			onCancelled()
		end
	end

	task.spawn(function()
		while not token.Cancelled and os.clock() < spawnAt do
			if not HallwayGraphService:IsFarFromPlayers(route[1], Config.SpawnPlayerDistance) then
				abandon("cancelled because a player approached its planned spawn")
				return
			end
			task.wait(WARNING_POLL)
		end
	end)

	table.insert(PendingTokens, token)
	task.delay(math.max(spawnAt - os.clock(), 0), function()
		removePending(token)
		if token.Cancelled then return end

		local origin = route[1]
		local destination = route[2]
		local chaos = EnemyService:Spawn("Chaos", CFrame.lookAt(origin, destination), route, token)
		if not chaos then
			abandon(nil)
			return
		end
		if onSpawned then
			onSpawned(chaos)
		end
	end)
	return true
end

local function drawStart(): RouteNode?
	local starts = {}
	for _, node in HallwayGraphService:Get() do
		if node.CanBeDestination
			and next(node.Neighbors)
			and HallwayGraphService:IsFarFromPlayers(node.Position, Config.SpawnPlayerDistance)
		then
			table.insert(starts, node)
		end
	end
	if #starts == 0 then return nil end
	return starts[math.random(#starts)]
end

function ChaosService:Spawn(onSpawned: ((any) -> ())?, onCancelled: (() -> ())?): boolean
	local best: { Vector3 }? = nil
	local deadline = os.clock() + SEARCH_SECONDS
	for _ = 1, START_CANDIDATES do
		local start = drawStart()
		if start then
			local route = planRoute(start, deadline)
			if route and (not best or #route > #best) then
				best = route
			end
		end
	end
	if not best then
		warn("[Chaos] found no route from any spawn node far from players")
		return false
	end
	return beginRoute(best, onSpawned, onCancelled)
end

function ChaosService:SpawnThrough(player: Player, onSpawned: ((any) -> ())?, onCancelled: (() -> ())?): boolean
	local root = CharacterService.GetAliveRoot(player)
	if not root then return false end

	local deadline = os.clock() + SEARCH_SECONDS
	for _ = 1, ROUTE_ATTEMPTS do
		local start = drawStart()
		if not start then return false end

		local route = planRouteThrough(start, root.Position, deadline)
		if route then
			return beginRoute(route, onSpawned, onCancelled)
		end
	end
	warn("[Chaos] found no route through the command caller's position")
	return false
end

function ChaosService:CancelPending(): number
	local count = #PendingTokens
	for _, token in PendingTokens do
		token.Cancelled = true
		token.Retract()
	end
	table.clear(PendingTokens)
	return count
end

return ChaosService
