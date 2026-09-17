local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local EndingConfig = require(ReplicatedStorage.Configs.EndingConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ComputerService = require(ServerStorage.Services.ComputerService)

local Show = CommunicationService.Ensure(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Show) :: RemoteEvent
local Hide = CommunicationService.Ensure(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Hide) :: RemoteEvent
local PlayAgain = CommunicationService.Ensure(EndingConfig.Remotes.Folder, EndingConfig.Remotes.PlayAgain) :: RemoteEvent

local EndingService = {}

local Ending: { [Player]: Model } = {}

local function lobbySpawn(): SpawnLocation?
	local lobby = workspace:FindFirstChild("Lobby")
	local spawn = lobby and lobby:FindFirstChildOfClass("SpawnLocation")
	if spawn then return spawn end

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then return descendant end
	end
	return nil
end

local function insideHitbox(hitbox: BasePart, position: Vector3): boolean
	local local_ = hitbox.CFrame:PointToObjectSpace(position)
	local half = hitbox.Size / 2
	return math.abs(local_.X) <= half.X and math.abs(local_.Y) <= half.Y and math.abs(local_.Z) <= half.Z
end

function EndingService:IsEnding(player: Player): boolean
	return Ending[player] ~= nil
end

function EndingService:Begin(player: Player): boolean
	if Ending[player] then return false end

	local root = CharacterService.GetAliveRoot(player)
	if not root then return false end

	Ending[player] = root.Parent :: Model
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	Show:FireClient(player)
	return true
end

function EndingService:Finish(player: Player): boolean
	local character = Ending[player]
	if not character then return false end
	Ending[player] = nil

	ComputerService:ResetProgress(player)

	local root = character:FindFirstChild("HumanoidRootPart")
	local spawn = lobbySpawn()
	if spawn and character.Parent then
		local target = spawn.CFrame + Vector3.yAxis * (spawn.Size.Y / 2 + EndingConfig.SpawnLift)
		pcall(function()
			player:RequestStreamAroundAsync(target.Position)
		end)
		if character.Parent then
			character:PivotTo(target)
		end
	end

	if root and root:IsA("BasePart") then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
	end

	Hide:FireClient(player)
	return true
end

function EndingService:Cancel(player: Player)
	local character = Ending[player]
	if not character then return end
	Ending[player] = nil

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then root.Anchored = false end
	Hide:FireClient(player)
end

local function watchPlayer(player: Player)
	player.CharacterRemoving:Connect(function()
		Ending[player] = nil
	end)
end

PlayAgain.OnServerEvent:Connect(function(player: Player)
	task.spawn(EndingService.Finish, EndingService, player)
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	Ending[player] = nil
end)

local elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime: number)
	elapsed += deltaTime
	if elapsed < EndingConfig.CheckInterval then return end
	elapsed = 0

	for _, model in CollectionService:GetTagged(ElevatorConfig.Tag) do
		if model:GetAttribute(ElevatorConfig.TypeAttribute) ~= ElevatorConfig.ExitType then continue end
		local hitbox = model:FindFirstChild(ElevatorConfig.HitboxName)
		if not hitbox or not hitbox:IsA("BasePart") then continue end

		for _, player in Players:GetPlayers() do
			if Ending[player] then continue end
			local root = CharacterService.GetAliveRoot(player)
			if not root or not insideHitbox(hitbox, root.Position) then continue end
			if not ComputerService:IsExitUnlocked(player) then continue end
			EndingService:Begin(player)
		end
	end
end)

return EndingService
