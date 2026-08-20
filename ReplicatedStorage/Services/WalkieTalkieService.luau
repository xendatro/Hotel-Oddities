local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)

local WalkieTalkieService = {}

if not RunService:IsClient() then
	return WalkieTalkieService
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("PlayerLocator") :: ScreenGui
local frame = gui:WaitForChild("Mode") :: Frame
local modeLabel = frame:WaitForChild("Mode") :: TextLabel
local toggle = frame:WaitForChild("Toggle") :: ImageButton
local cooldownLabel = frame:FindFirstChild("TeleportCooldown") :: TextLabel?

local walkieCommunication = ReplicatedStorage.Communication.WalkieTalkie
local SetMode = walkieCommunication.SetMode :: RemoteEvent
local VoiceActivity = walkieCommunication:WaitForChild("VoiceActivity") :: RemoteEvent
local modeIndex = 1
local enabled = false
local emitterConnection: RBXScriptConnection?
local analyzerConnection: RBXScriptConnection?
local analyzer: AudioAnalyzer?
local analyzerWire: Wire?
local speaking = false
local lastActivitySentAt = -math.huge
local mutedEmitterGroup = `WalkieTalkieMuted_{player.UserId}`

local function isVoiceEligible(): boolean
	local success, result = pcall(
		VoiceChatService.IsVoiceEnabledForUserIdAsync,
		VoiceChatService,
		player.UserId
	)
	return success and result == true
end

local function setMode(index: number, send: boolean)
	modeIndex = (index - 1) % #Config.Modes + 1
	modeLabel.Text = Config.Modes[modeIndex].Label
	if send and enabled then SetMode:FireServer(Config.Modes[modeIndex].Id) end
end

local function muteOwnEmitter(descendant: Instance)
	if descendant.Name == "RadioEmitter" and descendant:IsA("AudioEmitter") then
		descendant.AudioInteractionGroup = mutedEmitterGroup
	end
end

local function watchOwnEmitter(tool: Tool)
	if emitterConnection then emitterConnection:Disconnect() end
	for _, descendant in tool:GetDescendants() do
		muteOwnEmitter(descendant)
	end
	emitterConnection = tool.DescendantAdded:Connect(muteOwnEmitter)
end

local function sendVoiceActivity(value: boolean, heartbeat: boolean?)
	local now = os.clock()
	if speaking == value and not heartbeat then return end
	speaking = value
	lastActivitySentAt = now
	VoiceActivity:FireServer(value)
end

local function stopVoiceAnalyzer()
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
	sendVoiceActivity(false)
end

local function startVoiceAnalyzer()
	stopVoiceAnalyzer()

	local source = player:FindFirstChild("AudioDeviceInput")
	if not source or not source:IsA("AudioDeviceInput") then return end

	local currentAnalyzer = Instance.new("AudioAnalyzer")
	currentAnalyzer.Name = "WalkieTalkieVoiceAnalyzer"
	currentAnalyzer.SpectrumEnabled = false
	currentAnalyzer.Parent = player

	local wire = Instance.new("Wire")
	wire.Name = "WalkieTalkieVoiceAnalyzerWire"
	wire.SourceInstance = source
	wire.TargetInstance = currentAnalyzer
	wire.Parent = currentAnalyzer

	analyzer = currentAnalyzer
	analyzerWire = wire
	local lastAboveThreshold = 0
	local accumulator = 0
	analyzerConnection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < Config.VoiceActivity.PollInterval then return end
		accumulator = 0

		local now = os.clock()
		local aboveThreshold = source.Active
			and not source.Muted
			and currentAnalyzer.RmsLevel >= Config.VoiceActivity.Threshold
		if aboveThreshold then
			lastAboveThreshold = now
			if not speaking or now - lastActivitySentAt >= Config.VoiceActivity.Heartbeat then
				sendVoiceActivity(true, true)
			end
		elseif speaking and now - lastAboveThreshold >= Config.VoiceActivity.Release then
			sendVoiceActivity(false)
		end
	end)
end

toggle.Activated:Connect(function()
	if enabled then setMode(modeIndex + 1, true) end
end)

function WalkieTalkieService:SetEnabled(value: boolean, tool: Tool?)
	if value then
		if not isVoiceEligible() then
			enabled = false
			return
		end
		enabled = true
		if tool then watchOwnEmitter(tool) end
		gui.Enabled = true
		if cooldownLabel then cooldownLabel.Visible = false end
		setMode(modeIndex, true)
	else
		enabled = false
		if emitterConnection then
			emitterConnection:Disconnect()
			emitterConnection = nil
		end
		gui.Enabled = false
	end
end

player.ChildAdded:Connect(function(child)
	if child.Name == "AudioDeviceInput" then
		startVoiceAnalyzer()
	end
end)

player.ChildRemoved:Connect(function(child)
	if child.Name == "AudioDeviceInput" then
		stopVoiceAnalyzer()
	end
end)

function WalkieTalkieService:IsEnabled(): boolean
	return enabled
end

startVoiceAnalyzer()
setMode(1, false)
gui.Enabled = false

return WalkieTalkieService
