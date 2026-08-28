local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.VoiceChatConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local VoiceActivityService = {}

if not RunService:IsClient() then
	return VoiceActivityService
end

local player = Players.LocalPlayer
local VoiceActivity = CommunicationService.Get("WalkieTalkie", "VoiceActivity") :: RemoteEvent
local analyzerConnection: RBXScriptConnection?
local analyzer: AudioAnalyzer?
local analyzerWire: Wire?
local speaking = false
local lastActivitySentAt = -math.huge
local voiceCutoffActive = false
local voiceMuteGroup = `VoiceDead_{player.UserId}`
local mutedVoiceEmitters: { [AudioEmitter]: string } = {}

local function muteRemoteVoiceEmitter(instance: Instance)
	local character = player.Character
	if not voiceCutoffActive
		or not instance:IsA("AudioEmitter")
		or instance.Name ~= "AudioEmitter"
		or (character and instance:IsDescendantOf(character))
	then
		return
	end

	if mutedVoiceEmitters[instance] == nil then
		mutedVoiceEmitters[instance] = instance.AudioInteractionGroup
	end
	instance.AudioInteractionGroup = voiceMuteGroup
end

local function refreshMutedVoiceEmitters()
	for _, other in Players:GetPlayers() do
		if other == player or not other.Character then continue end
		for _, descendant in other.Character:GetDescendants() do
			muteRemoteVoiceEmitter(descendant)
		end
	end
end

local function restoreMutedVoiceEmitters()
	for emitter, group in mutedVoiceEmitters do
		if emitter.Parent and emitter.AudioInteractionGroup == voiceMuteGroup then
			emitter.AudioInteractionGroup = group
		end
		mutedVoiceEmitters[emitter] = nil
	end
end

function VoiceActivityService:GetLevel(): number
	local current = analyzer
	if not current or not current.Parent then return 0 end
	local source = player:FindFirstChild("AudioDeviceInput")
	if not source or not source:IsA("AudioDeviceInput") or not source.Active or source.Muted then
		return 0
	end
	return current.RmsLevel
end

local function sendActivity(active: boolean, heartbeat: boolean?)
	local now = os.clock()
	if speaking == active and not heartbeat then return end
	speaking = active
	lastActivitySentAt = now
	VoiceActivity:FireServer(active)
end

local function stopAnalyzer()
	if analyzerConnection then
		analyzerConnection:Disconnect()
		analyzerConnection = nil
	end
	if analyzerWire then
		analyzerWire:Destroy()
		analyzerWire = nil
	end
	if analyzer then
		analyzer:Destroy()
		analyzer = nil
	end
	sendActivity(false)
end

local function startAnalyzer()
	stopAnalyzer()
	if voiceCutoffActive then return end

	local source = player:FindFirstChild("AudioDeviceInput")
	if not source or not source:IsA("AudioDeviceInput") then return end

	local currentAnalyzer = Instance.new("AudioAnalyzer")
	currentAnalyzer.Name = "VoiceActivityAnalyzer"
	currentAnalyzer.SpectrumEnabled = false
	currentAnalyzer.Parent = player

	local wire = Instance.new("Wire")
	wire.Name = "VoiceActivityAnalyzerWire"
	wire.SourceInstance = source
	wire.TargetInstance = currentAnalyzer
	wire.Parent = currentAnalyzer

	analyzer = currentAnalyzer
	analyzerWire = wire
	local lastAboveThreshold = 0
	local accumulator = 0
	analyzerConnection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < Config.Activity.PollInterval then return end
		accumulator = 0

		local now = os.clock()
		local aboveThreshold = source.Active
			and not source.Muted
			and currentAnalyzer.RmsLevel >= Config.Activity.Threshold
		if aboveThreshold then
			lastAboveThreshold = now
			if not speaking or now - lastActivitySentAt >= Config.Activity.Heartbeat then
				sendActivity(true, true)
			end
		elseif speaking and now - lastAboveThreshold >= Config.Activity.Release then
			sendActivity(false)
		end
	end)
end

local function setVoiceCutoff(active: boolean)
	if voiceCutoffActive == active then return end
	voiceCutoffActive = active

	local source = player:FindFirstChild("AudioDeviceInput")
	if source and source:IsA("AudioDeviceInput") then source.Muted = active end

	if active then
		stopAnalyzer()
		refreshMutedVoiceEmitters()
	else
		restoreMutedVoiceEmitters()
		startAnalyzer()
	end
end

local characterDeathConnection: RBXScriptConnection?
local characterAddedConnection: RBXScriptConnection?

local function bindCharacter(character: Model)
	if characterDeathConnection then
		characterDeathConnection:Disconnect()
		characterDeathConnection = nil
	end
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		characterDeathConnection = humanoid.Died:Connect(function()
			setVoiceCutoff(true)
		end)
		if humanoid.Health <= 0 then setVoiceCutoff(true) end
		return
	end

	characterAddedConnection = character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then bindCharacter(character) end
	end)
end

player.ChildAdded:Connect(function(child)
	if child.Name == "AudioDeviceInput" then
		if child:IsA("AudioDeviceInput") then child.Muted = voiceCutoffActive end
		startAnalyzer()
	end
end)

player.ChildRemoved:Connect(function(child)
	if child.Name == "AudioDeviceInput" then stopAnalyzer() end
end)

Players.DescendantAdded:Connect(function(descendant)
	if voiceCutoffActive then muteRemoteVoiceEmitter(descendant) end
end)

player.CharacterAdded:Connect(function(character)
	setVoiceCutoff(false)
	bindCharacter(character)
	if not voiceCutoffActive then startAnalyzer() end
end)

if player.Character then bindCharacter(player.Character) end
startAnalyzer()

return VoiceActivityService
