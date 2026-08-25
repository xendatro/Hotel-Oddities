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
local WARNING_POLL = 0.25
local CRASH_PROBE = 96
local CRASH_MARGIN = 1.5

type RouteNode = HallwayGraphService.RouteNode

type WarningToken = {
	Cancelled: boolean,
}

type PendingWarning = {
	WarnAt: number,
	ExpiresAt: number,
	IsNearPlayer: () -> boolean,
	Fire: (number) -> (),
}

local ChaosService = {}
local Config = EnemyConfigs.Chaos
local PendingTokens: { WarningToken } = {}

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

local function anyPlayerNear(position: Vector3, range: number): boolean
	for _, playerPosition in livingRootPositions() do
		if (playerPosition - position).Magnitude <= range then return true end
	end
	return false
end

local function anyPlayerNearSpan(span: Hallways.StraightSpan, range: number): boolean
	for _, playerPosition in livingRootPositions() do
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

local function crashPoint(route: { Vector3 }): Vector3?
	local last = route[#route]
	local direction = horizontal(last - route[#route - 1])
	if direction.Magnitude < 1e-3 then return nil end
	direction = direction.Unit

	local exclude = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	CrashParams.FilterDescendantsInstances = exclude

	local hit = workspace:Raycast(last, direction * CRASH_PROBE, CrashParams)
	if hit then
		local wall = Vector3.new(hit.Position.X, last.Y, hit.Position.Z)
		return wall - direction * CRASH_MARGIN
	end
	return last + direction * CRASH_PROBE
end

local function extendGreedily(nodes: { RouteNode }, visited: { [RouteNode]: boolean })
	local current = nodes[#nodes]
	while true do
		local options = {}
		for neighbor in current.Neighbors do
			if not visited[neighbor] then
				table.insert(options, neighbor)
			end
		end
		if #options == 0 then return end

		current = options[math.random(#options)]
		visited[current] = true
		table.insert(nodes, current)
	end
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

local function planRoute(start: RouteNode): { Vector3 }?
	local visited: { [RouteNode]: boolean } = { [start] = true }
	local nodes = { start }
	extendGreedily(nodes, visited)
	return toRoute(nodes)
end

local function planRouteThrough(start: RouteNode, targetPosition: Vector3): { Vector3 }?
	local target = HallwayGraphService:FindNearestNode(targetPosition)
	if not target then return nil end

	local approach = HallwayGraphService:FindPath(start, target)
	if not approach then return nil end

	local visited: { [RouteNode]: boolean } = {}
	for _, node in approach do
		visited[node] = true
	end

	local nodes = table.clone(approach)
	extendGreedily(nodes, visited)
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

local function collectWarnings(route: { Vector3 }, spawnAt: number): { PendingWarning }
	local pending: { PendingWarning } = {}

	for _, light in LightService:GetModels() do
		local lightPosition = light:GetPivot().Position
		local distance, travel = distanceToRoute(lightPosition, route)
		if distance > Config.LightRouteRange then continue end

		local arrivalAt = spawnAt + travel / Config.WalkSpeed
		table.insert(pending, {
			WarnAt = arrivalAt - Config.WarningTime,
			ExpiresAt = arrivalAt,
			IsNearPlayer = function()
				return anyPlayerNear(lightPosition, Config.WarnRedCullRange or math.huge)
			end,
			Fire = function(remaining: number)
				LightService:WarnRed(light, remaining + (Config.LightPassDelay or 0))
			end,
		})
	end

	local seenSpans: { [string]: boolean } = {}
	local travelled = 0
	for index, point in route do
		if index > 1 then
			travelled += (point - route[index - 1]).Magnitude
		end

		local span = Hallways.StraightSpanAt(point)
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

		local arrivalAt = spawnAt + travelled / Config.WalkSpeed
		table.insert(pending, {
			WarnAt = arrivalAt - Config.WarningTime,
			ExpiresAt = arrivalAt,
			IsNearPlayer = function()
				return anyPlayerNearSpan(span, Config.WarnHallwayCullRange or math.huge)
			end,
			Fire = function(remaining: number)
				MapOddityService:Warn(point, remaining)
			end,
		})
	end

	return pending
end

local function scheduleWarnings(route: { Vector3 }, token: WarningToken, spawnAt: number)
	local pending = collectWarnings(route, spawnAt)
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

			for position = #waiting, 1, -1 do
				local warning = waiting[position]
				local remaining = warning.ExpiresAt - now
				if remaining <= 0 then
					table.remove(waiting, position)
				elseif warning.IsNearPlayer() then
					warning.Fire(remaining)
					table.remove(waiting, position)
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

local function beginRoute(route: { Vector3 }, onSpawned: ((any) -> ())?): boolean
	local token: WarningToken = { Cancelled = false }
	local spawnAt = os.clock() + Config.SpawnDelay

	scheduleWarnings(route, token, spawnAt)

	table.insert(PendingTokens, token)
	task.delay(math.max(spawnAt - os.clock(), 0), function()
		removePending(token)
		if token.Cancelled then return end

		local origin = route[1]
		if not HallwayGraphService:IsFarFromPlayers(origin, Config.SpawnPlayerDistance) then
			token.Cancelled = true
			warn("[Chaos] cancelled because a player approached its planned spawn")
			return
		end

		local destination = route[2]
		local chaos = EnemyService:Spawn("Chaos", CFrame.lookAt(origin, destination), route, token)
		if not chaos then
			token.Cancelled = true
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

function ChaosService:Spawn(onSpawned: ((any) -> ())?): boolean
	for _ = 1, ROUTE_ATTEMPTS do
		local start = drawStart()
		if not start then return false end

		local route = planRoute(start)
		if route then
			return beginRoute(route, onSpawned)
		end
	end
	warn("[Chaos] found no route from any spawn node far from players")
	return false
end

function ChaosService:SpawnThrough(player: Player, onSpawned: ((any) -> ())?): boolean
	local root = CharacterService.GetAliveRoot(player)
	if not root then return false end

	for _ = 1, ROUTE_ATTEMPTS do
		local start = drawStart()
		if not start then return false end

		local route = planRouteThrough(start, root.Position)
		if route then
			return beginRoute(route, onSpawned)
		end
	end
	warn("[Chaos] found no route through the command caller's position")
	return false
end

function ChaosService:CancelPending(): number
	local count = #PendingTokens
	for _, token in PendingTokens do
		token.Cancelled = true
	end
	table.clear(PendingTokens)
	return count
end

return ChaosService
