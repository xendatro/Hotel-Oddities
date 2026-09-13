local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Configs.ComputerChipConfig)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local ConnectorGraph = {}

local function horizontal(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function connect(a, b)
	if a == b then return end
	a.Neighbors[b] = true
	b.Neighbors[a] = true
end

local function nodeAt(position)
	return { Position = position, Neighbors = {}, CanBeDestination = true, WellConnected = true }
end

local function project(hallway, position)
	local along = math.clamp(horizontal(position - hallway.Center):Dot(hallway.Direction), -hallway.HalfLength, hallway.HalfLength)
	local point = hallway.Center + hallway.Direction * along
	local groundY = if hallway.Nodes[1] then hallway.Nodes[1].Position.Y else hallway.Center.Y + 0.5
	return Vector3.new(point.X, groundY, point.Z)
end

local function nearestHallway(graph, position, maxDistance)
	local best, bestPoint, bestDistance = nil, nil, math.huge
	for _, hallway in graph.Hallways do
		local point = project(hallway, position)
		local distance = horizontal(point - position).Magnitude
		if math.abs(point.Y - position.Y) <= Config.RoomHeightTolerance
			and distance <= (maxDistance or hallway.HalfWidth + 2) and distance < bestDistance then
			best, bestPoint, bestDistance = hallway, point, distance
		end
	end
	return best, bestPoint
end

local function attach(graph, hallway, point)
	for _, node in hallway.Nodes do
		if (node.Position - point).Magnitude < 0.1 then return node end
	end
	local node = nodeAt(point)
	for _, other in hallway.Nodes do connect(node, other) end
	table.insert(hallway.Nodes, node)
	table.insert(graph.Nodes, node)
	return node
end

local function containsRoom(room, position, padding)
	local p = padding or 0
	return position.X >= room.Min.X - p and position.X <= room.Max.X + p
		and position.Z >= room.Min.Z - p and position.Z <= room.Max.Z + p
		and math.abs(position.Y - room.FloorY) <= Config.RoomHeightTolerance
end

local function floorTouches(room, position)
	for _, floor in room.Floors do
		local localPoint = floor.CFrame:PointToObjectSpace(position)
		local half = floor.Size / 2 + Vector3.new(Config.EntranceSnapDistance, 1.5, Config.EntranceSnapDistance)
		if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y
			and math.abs(localPoint.Z) <= half.Z then return true end
	end
	return false
end

local function addEdge(graph, room, a, b)
	if a == b then return end
	connect(a, b)
	local function key(p)
		return string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
	end
	local first, second = key(a.Position), key(b.Position)
	if second < first then a, b = b, a; first, second = second, first end
	local edge = { Room = room, A = a, B = b, Key = room.Model:GetFullName() .. ":" .. first .. ":" .. second }
	graph.Edges[a] = graph.Edges[a] or {}
	graph.Edges[b] = graph.Edges[b] or {}
	graph.Edges[a][b] = edge
	graph.Edges[b][a] = edge
end

function ConnectorGraph.Build(maze, revision)
	local graph = HallwayGraph:BuildCorridors(maze)
	graph.Edges = {}
	graph.Rooms = {}
	graph.Maze = maze
	graph.Revision = revision or 0
	local folder = maze:FindFirstChild("Connectors")
	if not folder then return graph end
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then continue end
		local floors = {}
		local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in model:GetDescendants() do
			if not part:IsA("BasePart") or not CollectionService:HasTag(part, "HallwayRoomFloor") then continue end
			table.insert(floors, part)
			for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
				local p = part.CFrame:PointToWorldSpace(part.Size * Vector3.new(x, y, z) / 2)
				low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
				high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
			end end end
		end
		if #floors == 0 then continue end
		local room = { Model = model, Floors = floors, Min = low, Max = high, FloorY = high.Y, Ports = {} }
		local function addPort(position)
			local hallway, projected = nearestHallway(graph, position, Config.EntranceSnapDistance)
			if not hallway then return end
			position = Vector3.new(position.X, projected.Y, position.Z)
			for _, port in room.Ports do if (port.Position - position).Magnitude < 3 then return end end
			local anchor = attach(graph, hallway, projected)
			local port = anchor
			if (projected - position).Magnitude > 0.1 then
				port = nodeAt(position)
				table.insert(graph.Nodes, port)
				connect(port, anchor)
			end
			for _, nearby in graph.Hallways do
				local point = project(nearby, position)
				if (point - position).Magnitude <= Config.EntranceSnapDistance then
					connect(port, attach(graph, nearby, point))
				end
			end
			table.insert(room.Ports, port)
		end
		local markers = model:FindFirstChild("Connectors")
		if markers then
			for _, marker in markers:GetDescendants() do
				if marker:IsA("BasePart") then addPort(marker.Position)
				elseif marker:IsA("Attachment") then addPort(marker.WorldPosition) end
			end
		end
		if #room.Ports < 2 then
			for _, hallway in graph.Hallways do
				for _, sign in { -1, 1 } do
					local tip = project(hallway, hallway.Center + hallway.Direction * hallway.HalfLength * sign)
					if floorTouches(room, tip) then addPort(tip) end
				end
			end
		end
		if #room.Ports >= 2 then
			for i = 1, #room.Ports - 1 do
				for j = i + 1, #room.Ports do addEdge(graph, room, room.Ports[i], room.Ports[j]) end
			end
			table.insert(graph.Rooms, room)
		end
	end
	return graph
end


ConnectorGraph.Project = project
ConnectorGraph.NearestHallway = nearestHallway
ConnectorGraph.Attach = attach
ConnectorGraph.ContainsRoom = containsRoom
ConnectorGraph.AddEdge = addEdge
ConnectorGraph.NodeAt = nodeAt

return ConnectorGraph
