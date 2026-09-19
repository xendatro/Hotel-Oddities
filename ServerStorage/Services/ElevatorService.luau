local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HallwayStreamingService = require(ServerStorage.Services.HallwayStreamingService)

local ComputerService = require(ServerStorage.Services.ComputerService)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local EndingService = require(ServerStorage.Services.EndingService)

local ElevatorService = {}

local loadingRemote = CommunicationService.Find("Elevator", "Loading")
local fadeCompleteRemote = CommunicationService.Find("Elevator", "FadeComplete")
local arrivalRemote = CommunicationService.Ensure("Elevator", ElevatorConfig.ArrivalRemoteName)

type ElevatorState = {
	Model: Model,
	TouchConnection: RBXScriptConnection?,
	DescendantConnection: RBXScriptConnection?,
}

local states: { [Model]: ElevatorState } = {}
local activeTeleports: { [Player]: boolean } = {}
local nextTeleportAt: { [Player]: number } = {}
local fadeReady: { [Player]: number } = {}
local teleportToken = 0

if fadeCompleteRemote and fadeCompleteRemote:IsA("RemoteEvent") then
	(fadeCompleteRemote :: RemoteEvent).OnServerEvent:Connect(function(player, token)
		if typeof(token) == "number" then fadeReady[player] = token end
	end)
end

local function isLobbyElevator(state: ElevatorState): boolean
	return state.Model:GetAttribute(ElevatorConfig.TypeAttribute) == ElevatorConfig.LobbyType
end

local function destinationSpawn(): BasePart?
	local fallback: BasePart? = nil
	local maze = workspace:FindFirstChild("Maze15")
	for _, instance in CollectionService:GetTagged(ElevatorConfig.SpawnTag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			fallback = fallback or instance
			if maze and instance:IsDescendantOf(maze) then return instance end
		end
	end
	return fallback
end

local function playerFromTouch(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or hit.Parent ~= character then return nil end
	return Players:GetPlayerFromCharacter(character)
end

function ElevatorService:SendToMap(player: Player, instant: boolean?): boolean
	if activeTeleports[player] then return false end
	if not instant and (nextTeleportAt[player] or 0) > os.clock() then return false end

	local spawn = destinationSpawn()
	if not spawn then
		warn("[ElevatorService] no part tagged Spawn is available for the lobby elevator")
		return false
	end

	activeTeleports[player] = true
	teleportToken += 1
	local token = teleportToken
	local showsLoading = not instant and loadingRemote ~= nil and loadingRemote:IsA("RemoteEvent")
	if showsLoading then
		(loadingRemote :: RemoteEvent):FireClient(player, true, token)
	end

	local target = spawn.CFrame + spawn.CFrame.UpVector * (spawn.Size.Y / 2 + 3)
	local streamed = false
	local streamDone = false
	task.spawn(function()
		local ok, result = pcall(function()
			return HallwayStreamingService:PrepareTeleport(player, target.Position)
		end)
		streamed = ok and result == true
		streamDone = true
	end)

	if not instant then
		local minimumEnd = os.clock() + ElevatorConfig.MinimumLoadingTime
		local fadeDeadline = os.clock() + ElevatorConfig.FadeTimeout
		while fadeReady[player] ~= token and os.clock() < fadeDeadline do task.wait() end
		while os.clock() < minimumEnd do task.wait() end
	end
	while not streamDone do task.wait() end
	fadeReady[player] = nil

	if streamed then
		local character = player.Character
		if character and CharacterService.IsAlive(character) then
			character:PivotTo(target)
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then root.AssemblyLinearVelocity = Vector3.zero end
			arrivalRemote:FireClient(player, target)
		end
	else
		warn(`[ElevatorService] could not stream the lobby destination for {player.Name}`)
	end

	if showsLoading then
		(loadingRemote :: RemoteEvent):FireClient(player, false, token)
	end

	activeTeleports[player] = nil
	if not instant then
		nextTeleportAt[player] = os.clock() + ElevatorConfig.TeleportCooldown
		if streamed then
			AnalyticsService:LogStep(player, "ReachedMaze")
		end
	end
	return streamed
end

local function teleportPlayer(state: ElevatorState, player: Player)
	if not state.Model.Parent or not isLobbyElevator(state) then return end
	AnalyticsService:LogStep(player, "EnteredElevator")
	ElevatorService:SendToMap(player, false)
end

local function getHitbox(state: ElevatorState): BasePart?
	local hitbox = state.Model:FindFirstChild(ElevatorConfig.HitboxName)
	if not hitbox or not hitbox:IsA("BasePart") then return nil end
	hitbox.Anchored = true
	hitbox.CanTouch = true
	return hitbox
end

local function connectHitbox(state: ElevatorState)
	if state.TouchConnection then return end
	local hitbox = getHitbox(state)
	if not hitbox then return end
	state.TouchConnection = hitbox.Touched:Connect(function(hit)
		local player = playerFromTouch(hit)
		if player then task.spawn(teleportPlayer, state, player) end
	end)
end

local function register(model: Instance)
	if not model:IsA("Model") or states[model] then return end
	local state: ElevatorState = {
		Model = model,
		TouchConnection = nil,
		DescendantConnection = nil,
	}
	states[model] = state
	connectHitbox(state)
	state.DescendantConnection = model.DescendantAdded:Connect(function()
		connectHitbox(state)
	end)
end

local function unregister(model: Instance)
	if not model:IsA("Model") then return end
	local state = states[model]
	if not state then return end
	if state.TouchConnection then state.TouchConnection:Disconnect() end
	if state.DescendantConnection then state.DescendantConnection:Disconnect() end
	states[model] = nil
end

for _, model in CollectionService:GetTagged(ElevatorConfig.Tag) do register(model) end
CollectionService:GetInstanceAddedSignal(ElevatorConfig.Tag):Connect(register)
CollectionService:GetInstanceRemovedSignal(ElevatorConfig.Tag):Connect(unregister)

Players.PlayerRemoving:Connect(function(player)
	activeTeleports[player] = nil
	nextTeleportAt[player] = nil
	fadeReady[player] = nil
end)

local accessElapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	accessElapsed += deltaTime
	if accessElapsed < ElevatorConfig.AccessCheckInterval then return end
	accessElapsed = 0
	for model in states do
		if model:GetAttribute(ElevatorConfig.TypeAttribute) ~= ElevatorConfig.ExitType then continue end
		local hitbox = model:FindFirstChild(ElevatorConfig.HitboxName)
		local approach = model:FindFirstChild("Approach")
		if not hitbox or not hitbox:IsA("BasePart") or not approach or not approach:IsA("BasePart") then continue end
		for _, player in Players:GetPlayers() do
			local root = CharacterService.GetAliveRoot(player)
			if not root then continue end
			if EndingService:IsEnding(player) then continue end
			local p = hitbox.CFrame:PointToObjectSpace(root.Position)
			local half = hitbox.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z and not ComputerService:IsExitUnlocked(player) then
				local character = player.Character
				if character then
					character:PivotTo(approach.CFrame)
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end
end)

return ElevatorService
