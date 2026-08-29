local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.VoiceChatConfig)
local NoiseService = require(ServerStorage.Services.NoiseService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local VoiceActivity = CommunicationService.Ensure("WalkieTalkie", "VoiceActivity")

local VoiceActivityService = {}

export type State = {
	Active: boolean,
	LastActiveAt: number,
}

local States: { [Player]: State } = {}
local CharacterConnections: { [Player]: RBXScriptConnection } = {}
local DeathConnections: { [Player]: RBXScriptConnection } = {}
local MutedPlayers: { [Player]: boolean } = {}

local function tuneInput(player: Player, instance: Instance)
	if not instance:IsA("AudioDeviceInput") then return end
	instance.Volume = Config.Volume
	instance.Muted = MutedPlayers[player] == true
end

local function tuneVoiceEmitter(player: Player, instance: Instance)
	if not instance:IsA("AudioEmitter") or instance.Name ~= "AudioEmitter" then return end
	pcall(function() instance.AcousticSimulationEnabled = false end)
	pcall(function() instance.OcclusionEnabled = Enum.SimulationMode.Disabled end)
	pcall(function() instance.DiffractionEnabled = Enum.SimulationMode.Disabled end)
	pcall(function() instance.ReverbEnabled = Enum.SimulationMode.Disabled end)
	instance.DistanceAttenuationBounds = NumberRange.new(Config.Distance.Minimum, Config.Distance.Maximum)
	instance.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Custom
	instance:SetDistanceAttenuation({
		[Config.Distance.Minimum] = 1,
		[Config.Distance.Maximum] = 0,
	})
	instance.AudioInteractionGroup = if MutedPlayers[player]
		then `VoiceDead_{player.UserId}`
		else ""
end

local function watchCharacter(player: Player, character: Model)
	local previous = CharacterConnections[player]
	if previous then previous:Disconnect() end
	for _, descendant in character:GetDescendants() do
		tuneVoiceEmitter(player, descendant)
	end
	CharacterConnections[player] = character.DescendantAdded:Connect(function(descendant)
		tuneVoiceEmitter(player, descendant)
	end)
end

local function handlePlayerDeath(player: Player)
	if MutedPlayers[player] then return end
	MutedPlayers[player] = true

	local source = player:FindFirstChild("AudioDeviceInput")
	if source then tuneInput(player, source) end

	local character = player.Character
	if character then
		for _, descendant in character:GetDescendants() do
			tuneVoiceEmitter(player, descendant)
		end
	end

	local state = States[player]
	if state then state.Active = false end
end

local function watchPlayer(player: Player)
	local source = player:FindFirstChild("AudioDeviceInput")
	if source then tuneInput(player, source) end
	player.ChildAdded:Connect(function(child)
		if child.Name == "AudioDeviceInput" then tuneInput(player, child) end
	end)
	player.CharacterAdded:Connect(function(character)
		MutedPlayers[player] = nil
		local currentSource = player:FindFirstChild("AudioDeviceInput")
		if currentSource then tuneInput(player, currentSource) end
		watchCharacter(player, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if DeathConnections[player] then DeathConnections[player]:Disconnect() end
			DeathConnections[player] = humanoid.Died:Connect(function()
				handlePlayerDeath(player)
			end)
			if humanoid.Health <= 0 then handlePlayerDeath(player) end
		end
	end)
	if player.Character then
		watchCharacter(player, player.Character)
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			DeathConnections[player] = humanoid.Died:Connect(function()
				handlePlayerDeath(player)
			end)
			if humanoid.Health <= 0 then handlePlayerDeath(player) end
		end
	end
end

local function getPlayerPosition(player: Player): Vector3?
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return character:GetPivot().Position
end

local function emitVoiceNoise(player: Player)
	local position = getPlayerPosition(player)
	if position then NoiseService:Emit(position, Config.NoiseRadius, player) end
end

function VoiceActivityService:ApplyVolume()
	for _, player in Players:GetPlayers() do
		local source = player:FindFirstChild("AudioDeviceInput")
		if source then tuneInput(player, source) end
	end
end

function VoiceActivityService:GetState(player: Player): State?
	return States[player]
end

function VoiceActivityService:SetActive(player: Player, active: boolean)
	if MutedPlayers[player] and active then return end
	local now = os.clock()
	local state = States[player]
	if not state then
		state = { Active = false, LastActiveAt = -math.huge }
		States[player] = state
	end

	state.Active = active
	if active then
		state.LastActiveAt = now
		emitVoiceNoise(player)
	end
end

(VoiceActivity :: RemoteEvent).OnServerEvent:Connect(function(player: Player, active: any)
	if type(active) == "boolean" then VoiceActivityService:SetActive(player, active) end
end)

local EMIT_INTERVAL = 0.05
local emitAccumulator = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
	emitAccumulator += deltaTime
	if emitAccumulator < EMIT_INTERVAL then return end
	emitAccumulator = 0

	local now = os.clock()
	for player, state in States do
		if state.Active and now - state.LastActiveAt > Config.Activity.Timeout then
			state.Active = false
		elseif state.Active then
			emitVoiceNoise(player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	States[player] = nil
	local connection = CharacterConnections[player]
	if connection then connection:Disconnect() end
	CharacterConnections[player] = nil
	local deathConnection = DeathConnections[player]
	if deathConnection then deathConnection:Disconnect() end
	DeathConnections[player] = nil
	MutedPlayers[player] = nil
end)

Players.PlayerAdded:Connect(watchPlayer)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

return VoiceActivityService
