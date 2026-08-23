local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Configs.VoiceChatConfig)
local NoiseService = require(ServerStorage.Services.NoiseService)

local communication = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("WalkieTalkie")
local VoiceActivity = communication:FindFirstChild("VoiceActivity")
if not VoiceActivity then
	VoiceActivity = Instance.new("RemoteEvent")
	VoiceActivity.Name = "VoiceActivity"
	VoiceActivity.Parent = communication
end

local VoiceActivityService = {}

export type State = {
	Active: boolean,
	LastActiveAt: number,
}

local States: { [Player]: State } = {}
local CharacterConnections: { [Player]: RBXScriptConnection } = {}

local function tuneInput(instance: Instance)
	if instance:IsA("AudioDeviceInput") then instance.Volume = Config.Volume end
end

local function tuneVoiceEmitter(instance: Instance)
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
end

local function watchCharacter(player: Player, character: Model)
	local previous = CharacterConnections[player]
	if previous then previous:Disconnect() end
	for _, child in character:GetChildren() do
		tuneVoiceEmitter(child)
	end
	CharacterConnections[player] = character.ChildAdded:Connect(tuneVoiceEmitter)
end

local function watchPlayer(player: Player)
	local source = player:FindFirstChild("AudioDeviceInput")
	if source then tuneInput(source) end
	player.ChildAdded:Connect(function(child)
		if child.Name == "AudioDeviceInput" then tuneInput(child) end
	end)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then watchCharacter(player, player.Character) end
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
		if source then tuneInput(source) end
	end
end

function VoiceActivityService:GetState(player: Player): State?
	return States[player]
end

function VoiceActivityService:SetActive(player: Player, active: boolean)
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

RunService.Heartbeat:Connect(function()
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
end)

Players.PlayerAdded:Connect(watchPlayer)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

return VoiceActivityService
