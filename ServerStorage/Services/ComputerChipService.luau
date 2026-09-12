local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.ComputerChipConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local InventoryService = require(ServerStorage.Services.InventoryService)
local RoomService = require(ServerStorage.Services.RoomService)
local Routes = require(ServerStorage.Services.ComputerChipRouteService)

local RouteRemote = CommunicationService.Ensure(Config.RemoteFolder, Config.RouteRemote)
local SyncRemote = CommunicationService.Ensure(Config.RemoteFolder, Config.SyncRemote)
local Service = {}
local Active = {}
local Pending = {}
local LastSync = {}
local Serial = 0
local Entries = {}

for _, entry in Config.Colors do Entries[entry.Key] = entry end

local function getTarget(entry)
	local maze = workspace:FindFirstChild(Config.MazeName)
	local rooms = maze and maze:FindFirstChild("Rooms")
	local room = rooms and rooms:FindFirstChild(entry.RoomName)
	local computer = room and room:FindFirstChild("ComputerModel")
	if not computer or not computer:IsA("Model") or not computer:HasTag(Config.ComputerTag) then return nil end
	return maze, room, computer
end

local function send(player, state)
	RouteRemote:FireClient(player, {
		Id = state.Id,
		Version = state.Version,
		ColorKey = state.Entry.Key,
		ToolName = state.Entry.ToolName,
		Color = state.Entry.Color,
		StartedAt = state.StartedAt,
		EndsAt = state.EndsAt,
		Duration = state.EndsAt - state.StartedAt,
		Points = state.Points,
		Forced = state.Forced,
		TrimDistance = state.TrimDistance,
	})
end

local function clear(player)
	local previous = Active[player]
	Active[player] = nil
	if previous and player.Parent == Players then
		RouteRemote:FireClient(player, { Id = previous.Id, Clear = true })
	end
end

local function alivePlayer(player, character)
	return player.Parent == Players and player.Character == character and CharacterService.GetAliveRoot(player) ~= nil
end

function Service:Activate(player, tool, colorKey)
	local entry = Entries[colorKey]
	if not entry or Pending[player] or not tool or tool.Name ~= entry.ToolName then return false end
	local character = player.Character
	if not character or tool.Parent ~= character or not alivePlayer(player, character) then return false end
	if InventoryService:Get(player, entry.ToolName) ~= tool or (tool:GetAttribute("quantity") or 0) < 1 then return false end
	local maze, room, computer = getTarget(entry)
	if not maze then return false end
	local root = CharacterService.GetAliveRoot(player)
	local origin = Routes:Locate(maze, root.Position, RoomService:GetRoom(player))
	if not origin then return false end
	local ticket = {}
	Pending[player] = ticket
	local requested = os.clock()
	local function valid()
		return Pending[player] == ticket and alivePlayer(player, character) and tool.Parent == character
			and computer.Parent == room and computer:HasTag(Config.ComputerTag)
			and os.clock() - requested < 20
	end
	local ok, route = pcall(function() return Routes:GetRoute(maze, origin, room, valid) end)
	local accept = valid()
	if Pending[player] == ticket then Pending[player] = nil end
	if not ok then warn("Computer chip route: " .. tostring(route)); return false end
	if not route or not accept or InventoryService:Get(player, entry.ToolName) ~= tool
		or (tool:GetAttribute("quantity") or 0) < 1 then return false end
	InventoryService:Remove(player, entry.ToolName, 1)
	clear(player)
	Serial += 1
	local now = workspace:GetServerTimeNow()
	local state = {
		Id = Serial, Version = 1, Entry = entry, Maze = maze, Room = room, Computer = computer, Character = character,
		StartedAt = now, EndsAt = now + Config.Duration, Points = route.Points, Forced = route.Forced,
		Revision = route.Revision, LastPosition = origin.Position, LastRoom = origin.Room,
		LastConnector = origin.Connector and origin.Connector.Model,
		LastCorridor = origin.Hallway and origin.Hallway.Center,
		TrimDistance = if origin.Hallway then origin.Hallway.HalfWidth + 2 else Config.OffRouteDistance,
		LastRepath = os.clock(), Busy = false,
	}
	Active[player] = state
	send(player, state)
	return true
end

local function distanceToRoute(points, position)
	local best = math.huge
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		local delta = b - a
		local fraction = if delta:Dot(delta) > 0.001 then math.clamp((position - a):Dot(delta) / delta:Dot(delta), 0, 1) else 0
		best = math.min(best, (position - a:Lerp(b, fraction)).Magnitude)
	end
	if #points == 1 then best = (position - points[1]).Magnitude end
	return best
end

local function repath(player, state, origin)
	state.Busy = true
	state.LastRepath = os.clock()
	task.spawn(function()
		local function valid()
			return Active[player] == state and alivePlayer(player, state.Character)
				and state.Computer.Parent == state.Room and state.Computer:HasTag(Config.ComputerTag)
				and workspace:GetServerTimeNow() < state.EndsAt
		end
		local ok, route = pcall(function() return Routes:GetRoute(state.Maze, origin, state.Room, valid) end)
		state.Busy = false
		if not ok then warn("Computer chip reroute: " .. tostring(route)); return end
		if not route or not valid() then return end
		state.Points, state.Forced, state.Revision = route.Points, route.Forced, route.Revision
		state.LastPosition = origin.Position
		state.LastRoom = origin.Room
		state.LastConnector = origin.Connector and origin.Connector.Model
		state.LastCorridor = origin.Hallway and origin.Hallway.Center
		state.TrimDistance = if origin.Hallway then origin.Hallway.HalfWidth + 2 else Config.OffRouteDistance
		state.Version += 1
		send(player, state)
	end)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < Config.CheckInterval then return end
	accumulator = 0
	for player, state in Active do
		if not alivePlayer(player, state.Character) or workspace:GetServerTimeNow() >= state.EndsAt
			or state.Computer.Parent ~= state.Room or not state.Computer:HasTag(Config.ComputerTag)
			or not state.Room:IsDescendantOf(workspace) then
			clear(player)
			continue
		end
		if state.Busy or os.clock() - state.LastRepath < Config.RepathInterval then continue end
		local root = CharacterService.GetAliveRoot(player)
		local origin = Routes:Locate(state.Maze, root.Position, RoomService:GetRoom(player))
		if not origin then continue end
		local moved = (origin.Position - state.LastPosition).Magnitude >= Config.RepathDistance
		local changed = origin.Room ~= state.LastRoom
			or (origin.Connector and origin.Connector.Model) ~= state.LastConnector
			or (origin.Hallway and origin.Hallway.Center) ~= state.LastCorridor
		if moved or changed or Routes:GetRevision() ~= state.Revision
			or distanceToRoute(state.Points, origin.Position) > Config.OffRouteDistance
			or os.clock() - state.LastRepath >= Config.ConnectorCacheLifetime then
			repath(player, state, origin)
		end
	end
end)

SyncRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (LastSync[player] or -math.huge) < 1 then return end
	LastSync[player] = now
	local state = Active[player]
	if state and workspace:GetServerTimeNow() < state.EndsAt then send(player, state) end
end)

Players.PlayerRemoving:Connect(function(player)
	Active[player], Pending[player], LastSync[player] = nil, nil, nil
end)

local function markComputers()
	for _, entry in Config.Colors do
		local _, _, computer = getTarget(entry)
		if computer then
			computer:SetAttribute(Config.ColorAttribute, entry.Key)
			local marker = computer:FindFirstChild("ChipColorMarker")
			if marker and marker:IsA("BasePart") then marker.Color = entry.Color end
			local gui = marker and marker:FindFirstChild("ChipColorLabel")
			local label = gui and gui:FindFirstChild("ColorName")
			if label and label:IsA("TextLabel") then label.Text = string.upper(entry.Key) end
		end
	end
end

markComputers()
workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") and instance.Name == "ComputerModel" then task.defer(markComputers) end
end)

return Service
