local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.ComputerChipConfig)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local RoomService = require(ServerStorage.Services.RoomService)

local ConnectorGraph = require(ServerStorage.Classes.ConnectorGraph)

local Routes = {}
local Cached = nil
local SegmentCache = {}
local ActiveComputations = 0
local Revision = 0
local InvalidationPending = false
local NextCacheSweep = 0
local Metrics = { GraphBuilds = 0, Requests = 0, CacheHits = 0, InFlightHits = 0, Direct = 0, Computations = 0, Forced = 0, PeakComputations = 0, ComputeSeconds = 0, MaxComputeSeconds = 0 }

local function horizontal(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function length(points)
	local total = 0
	for index = 2, #points do total += (points[index] - points[index - 1]).Magnitude end
	return total
end

local project = ConnectorGraph.Project
local nearestHallway = ConnectorGraph.NearestHallway
local attach = ConnectorGraph.Attach
local containsRoom = ConnectorGraph.ContainsRoom
local addEdge = ConnectorGraph.AddEdge
local nodeAt = ConnectorGraph.NodeAt

function Routes:Invalidate()
	if InvalidationPending then return end
	InvalidationPending = true
	task.delay(Config.GraphSettleTime, function()
		InvalidationPending = false
		Revision += 1
		Cached = nil
		table.clear(SegmentCache)
	end)
end

local function build(maze)
	Metrics.GraphBuilds += 1
	return ConnectorGraph.Build(maze, Revision)
end

local function getGraph(maze)
	if os.clock() >= NextCacheSweep then
		NextCacheSweep = os.clock() + 5
		for key, entry in SegmentCache do
			if entry.Done and entry.ExpiresAt <= os.clock() then SegmentCache[key] = nil end
		end
	end
	if not Cached or Cached.Maze ~= maze then Cached = build(maze) end
	return Cached
end

local function cloneGraph(base)
	local graph = { Nodes = {}, Hallways = {}, Edges = {}, Rooms = base.Rooms, Revision = base.Revision }
	local copied = {}
	for _, old in base.Nodes do
		local node = nodeAt(old.Position)
		copied[old] = node
		table.insert(graph.Nodes, node)
	end
	for old, node in copied do
		for neighbor in old.Neighbors do node.Neighbors[copied[neighbor]] = true end
		for neighbor, edge in base.Edges[old] or {} do
			graph.Edges[node] = graph.Edges[node] or {}
			graph.Edges[node][copied[neighbor]] = edge
		end
	end
	for _, old in base.Hallways do
		local hallway = table.clone(old)
		hallway.Nodes = {}
		for _, node in old.Nodes do table.insert(hallway.Nodes, copied[node]) end
		table.insert(graph.Hallways, hallway)
	end
	graph.Copied = copied
	return graph
end

local function roomAnchor(graph, room)
	local approach = RoomService:GetDoorApproach(room, Config.AgentRadius)
	if not approach then return nil end
	approach = Vector3.new(approach.X, room:GetPivot().Position.Y, approach.Z)
	local hallway, point = nearestHallway(graph, approach, Config.EntranceSnapDistance)
	return if hallway then { Hallway = hallway, Position = point, Room = room } else nil
end

local function positionAnchor(graph, position)
	local hallway, point = nearestHallway(graph, position, Config.EntranceSnapDistance)
	return if hallway then { Hallway = hallway, Position = point } else nil
end

function Routes:Locate(maze, position, hotelRoom)
	local graph = getGraph(maze)
	if hotelRoom then return roomAnchor(graph, hotelRoom) end
	for _, room in graph.Rooms do
		if containsRoom(room, position) then
			return { Connector = room, Position = Vector3.new(position.X, room.FloorY, position.Z) }
		end
	end
	local hallway, point = nearestHallway(graph, position)
	return if hallway then { Hallway = hallway, Position = point } else nil
end

local function physicsParams(room)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { room.Model }
	ray.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { room.Model }
	overlap.RespectCanCollide = true
	return ray, overlap
end

local function directClear(room, a, b)
	local ray, overlap = physicsParams(room)
	local size = Vector3.new(Config.AgentRadius * 2, Config.AgentHeight - 0.4, Config.AgentRadius * 2)
	local lift = Vector3.new(0, Config.AgentHeight / 2 + 0.25, 0)
	if #workspace:GetPartBoundsInBox(CFrame.new(a + lift), size, overlap) > 0 then return false end
	if (b - a).Magnitude > 0.01 and workspace:Blockcast(CFrame.new(a + lift), size, b - a, ray) then return false end
	local steps = math.max(1, math.ceil((b - a).Magnitude / Config.ClearanceStep))
	for index = 0, steps do
		local p = a:Lerp(b, index / steps)
		local result = workspace:Raycast(p + Vector3.yAxis * Config.GroundProbeHeight,
			-Vector3.yAxis * (Config.GroundProbeHeight + Config.GroundProbeDepth), ray)
		if not result or math.abs(result.Position.Y - p.Y) > 1.5 then return false end
	end
	return true
end

local function validCached(edge)
	local cached = SegmentCache[edge.Key]
	return if cached and cached.Done and cached.ExpiresAt > os.clock() then cached else nil
end

local function resolve(edge, alive)
	local cached = validCached(edge)
	if cached then Metrics.CacheHits += 1; return cached end
	local pending = SegmentCache[edge.Key]
	if pending and not pending.Done then
		Metrics.InFlightHits += 1
		while not pending.Done do
			if not alive() then return nil end
			task.wait(0.05)
		end
		return pending
	end
	local a, b = edge.A.Position, edge.B.Position
	local result = { Done = false, Points = { a, b }, Length = (b - a).Magnitude, Forced = false, Mode = "Direct" }
	SegmentCache[edge.Key] = result
	local ok, err = pcall(function()
		if directClear(edge.Room, a, b) then Metrics.Direct += 1; return end
		while ActiveComputations >= Config.MaxConcurrentPaths do
			if not alive() then result.Forced = true; return end
			task.wait(0.05)
		end
		if not alive() then result.Forced = true; return end
		ActiveComputations += 1
		Metrics.Computations += 1
		Metrics.PeakComputations = math.max(Metrics.PeakComputations, ActiveComputations)
		local computeStart = os.clock()
		local path = nil
		local worked = pcall(function()
			path = PathfindingService:CreatePath({ AgentRadius = Config.AgentRadius, AgentHeight = Config.AgentHeight,
				AgentCanJump = false, WaypointSpacing = Config.WaypointSpacing, Costs = { Room = math.huge } })
			path:ComputeAsync(a + Vector3.yAxis * 2, b + Vector3.yAxis * 2)
			if path.Status ~= Enum.PathStatus.Success then return end
			local points = { a }
			for _, waypoint in path:GetWaypoints() do
				if not containsRoom(edge.Room, waypoint.Position, Config.EntranceSnapDistance) then return end
				table.insert(points, waypoint.Position)
			end
			if #points < 2 then return end
			table.insert(points, b)
			result.Points = points
			result.Length = length(points)
		end)
		if path then path:Destroy() end
		ActiveComputations -= 1
		local elapsed = os.clock() - computeStart
		Metrics.ComputeSeconds += elapsed
		Metrics.MaxComputeSeconds = math.max(Metrics.MaxComputeSeconds, elapsed)
		result.Forced = not worked or #result.Points == 2
		result.Mode = if result.Forced then "Forced" else "Pathfinding"
	end)
	if not ok then result.Forced = true; warn("Computer chip connector: " .. tostring(err)) end
	if result.Forced then Metrics.Forced += 1; result.Mode = "Forced" end
	result.Done = true
	result.ExpiresAt = os.clock() + (if result.Forced then Config.FailureCacheLifetime else Config.ConnectorCacheLifetime)
	return result
end

local function insertAnchor(graph, anchor)
	if anchor.Connector then
		local node = nodeAt(anchor.Position)
		table.insert(graph.Nodes, node)
		for _, port in anchor.Connector.Ports do addEdge(graph, anchor.Connector, node, graph.Copied[port]) end
		return node
	end
	for _, hallway in graph.Hallways do
		if hallway.Center == anchor.Hallway.Center and hallway.Direction == anchor.Hallway.Direction
			and hallway.HalfLength == anchor.Hallway.HalfLength then
			return attach(graph, hallway, anchor.Position)
		end
	end
	return nil
end

function Routes:GetRoute(maze, origin, destination, alive)
	Metrics.Requests += 1
	local base = getGraph(maze)
	local target = if typeof(destination) == "Vector3" then positionAnchor(base, destination) else roomAnchor(base, destination)
	if not target or not origin then return nil end
	local graph = cloneGraph(base)
	local from, to = insertAnchor(graph, origin), insertAnchor(graph, target)
	if not from or not to then return nil end
	local function edgeCost(a, b)
		local edge = graph.Edges[a] and graph.Edges[a][b]
		local cached = edge and validCached(edge)
		return if cached then cached.Length else (a.Position - b.Position).Magnitude
	end
	for _ = 1, Config.MaxRouteRefinements do
		if not alive() or graph.Revision ~= Revision then return nil end
		local route = HallwayGraph:FindPath(from, to, edgeCost)
		if not route then return nil end
		local refined = false
		for index = 2, #route do
			local a, b = route[index - 1], route[index]
			local edge = graph.Edges[a] and graph.Edges[a][b]
			if edge and not validCached(edge) then
				if not resolve(edge, alive) then return nil end
				refined = true
			end
		end
		if refined then continue end
		local points = { from.Position }
		local forced = false
		for index = 2, #route do
			local a, b = route[index - 1], route[index]
			local edge = graph.Edges[a] and graph.Edges[a][b]
			local cached = edge and validCached(edge)
			if cached then
				forced = forced or cached.Forced
				local forward = (a.Position - edge.A.Position).Magnitude < 0.1
				if forward then
					for _, point in cached.Points do table.insert(points, point) end
				else
					for i = #cached.Points, 1, -1 do table.insert(points, cached.Points[i]) end
				end
			else table.insert(points, b.Position) end
		end
		return { Points = points, Revision = Revision, Forced = forced }
	end
	return nil
end

function Routes:GetRevision()
	return Revision
end

function Routes:GetDiagnostics(maze)
	local graph = getGraph(maze)
	local rooms, segments = {}, {}
	for _, room in graph.Rooms do
		table.insert(rooms, { Name = room.Model.Name, Entrances = #room.Ports, Position = (room.Min + room.Max) / 2 })
	end
	for key, segment in SegmentCache do
		if segment.Done then table.insert(segments, { Key = key, Mode = segment.Mode, Points = segment.Points, Length = segment.Length }) end
	end
	return { Metrics = table.clone(Metrics), Rooms = rooms, Segments = segments, ActiveComputations = ActiveComputations }
end

for _, tag in { "MazeFloor", "HallwayRoomFloor" } do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function() Routes:Invalidate() end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function() Routes:Invalidate() end)
end

local maze = workspace:FindFirstChild(Config.MazeName)
local connectors = maze and maze:FindFirstChild("Connectors")
if connectors then
	connectors.DescendantAdded:Connect(function(item)
		if item:IsA("BasePart") then Routes:Invalidate() end
	end)
	connectors.DescendantRemoving:Connect(function(item)
		if item:IsA("BasePart") then Routes:Invalidate() end
	end)
end

return Routes
