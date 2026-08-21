local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.VoiceChatConfig)

local VoiceActivityService = {}

if not RunService:IsClient() then
	return VoiceActivityService
end

local player = Players.LocalPlayer
local communication = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("WalkieTalkie")
local VoiceActivity = communication:WaitForChild("VoiceActivity") :: RemoteEvent
local analyzerConnection: RBXScriptConnection?
local analyzer: AudioAnalyzer?
local analyzerWire: Wire?
local speaking = false
local lastActivitySentAt = -math.huge

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

player.ChildAdded:Connect(function(child)
	if child.Name == "AudioDeviceInput" then startAnalyzer() end
end)

player.ChildRemoved:Connect(function(child)
	if child.Name == "AudioDeviceInput" then stopAnalyzer() end
end)

startAnalyzer()

return VoiceActivityService
