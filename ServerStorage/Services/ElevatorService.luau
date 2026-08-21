local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local HallwayStreamingService = require(ServerStorage.Services.HallwayStreamingService)

local ElevatorService = {}

local communication = ReplicatedStorage:FindFirstChild("Communication")
local elevatorCommunication = communication and communication:FindFirstChild("Elevator")
local loadingRemote = elevatorCommunication and elevatorCommunication:FindFirstChild("Loading")
local fadeCompleteRemote = elevatorCommunication and elevatorCommunication:FindFirstChild("FadeComplete")

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
	return if character then Players:GetPlayerFromCharacter(character) else nil
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
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.Health > 0 then
			character:PivotTo(target)
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then root.AssemblyLinearVelocity = Vector3.zero end
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
	end
	return streamed
end

local function teleportPlayer(state: ElevatorState, player: Player)
	if not state.Model.Parent or not isLobbyElevator(state) then return end
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

return ElevatorService
