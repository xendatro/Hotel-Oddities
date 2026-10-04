local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local EndingConfig = require(ReplicatedStorage.Configs.EndingConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local VanishedService = require(ReplicatedStorage.Services.VanishedService)
local ComputerService = require(ServerStorage.Services.ComputerService)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local EscapeService = require(ServerStorage.Services.EscapeService)
local HallwayStreamingService = require(ServerStorage.Services.HallwayStreamingService)

local Show = CommunicationService.Ensure(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Show) :: RemoteEvent
local Hide = CommunicationService.Ensure(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Hide) :: RemoteEvent
local PlayAgain = CommunicationService.Ensure(EndingConfig.Remotes.Folder, EndingConfig.Remotes.PlayAgain) :: RemoteEvent

local EndingService = {}

type Ending = { Character: Model, Preview: boolean }

local Ending: { [Player]: Ending } = {}

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

local function exitHitbox(): (Model?, BasePart?)
	for _, model in CollectionService:GetTagged(ElevatorConfig.Tag) do
		if model:GetAttribute(ElevatorConfig.TypeAttribute) ~= ElevatorConfig.ExitType or not model:IsA("Model") then continue end
		local hitbox = model:FindFirstChild(ElevatorConfig.HitboxName)
		if hitbox and hitbox:IsA("BasePart") then return model, hitbox end
	end
	return nil, nil
end

local function release(character: Model)
	VanishedService.SetSource(character, VanishedService.EndingTag, false)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function EndingService:IsEnding(player: Player): boolean
	return Ending[player] ~= nil
end

function EndingService:Begin(player: Player, preview: boolean?): boolean
	if Ending[player] then return false end

	local root = CharacterService.GetAliveRoot(player)
	if not root then return false end

	local character = root.Parent :: Model
	Ending[player] = { Character = character, Preview = preview == true }
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	VanishedService.SetSource(character, VanishedService.EndingTag, true)
	if not preview then
		AnalyticsService:LogStep(player, "Escaped")
		AnalyticsService:LogEvent(player, "RunEscaped", AnalyticsService:GetRunTime(player))
		EscapeService:Award(player)
		ComputerService:ResetProgress(player)
	end
	Show:FireClient(player)
	return true
end

function EndingService:Preview(player: Player): boolean
	if Ending[player] then return false end

	local humanoid = CharacterService.GetAliveHumanoid(player)
	local root = CharacterService.GetAliveRoot(player)
	local exit, hitbox = exitHitbox()
	if not humanoid or not root or not exit or not hitbox then return false end

	local floor = hitbox.Position - Vector3.yAxis * (hitbox.Size.Y / 2)
	local look = exit:GetPivot().LookVector
	local stand = floor + Vector3.yAxis * (humanoid.HipHeight + root.Size.Y / 2)
	local target = CFrame.lookAt(stand, stand + Vector3.new(look.X, 0, look.Z))
	pcall(HallwayStreamingService.PrepareTeleport, HallwayStreamingService, player, target.Position)

	if Ending[player] or CharacterService.GetAliveRoot(player) ~= root then return false end
	if not self:Begin(player, true) then return false end
	local character = player.Character
	if character then
		character:PivotTo(target)
	end
	return true
end

function EndingService:Finish(player: Player): boolean
	local ending = Ending[player]
	if not ending then return false end
	Ending[player] = nil

	local character = ending.Character
	if not ending.Preview then
		ComputerService:ResetProgress(player)
		AnalyticsService:LogEvent(player, "PlayAgain")
		AnalyticsService:StartRun(player)
	end

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

	release(character)
	Hide:FireClient(player)
	return true
end

function EndingService:Cancel(player: Player)
	local ending = Ending[player]
	if not ending then return end
	Ending[player] = nil

	release(ending.Character)
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
